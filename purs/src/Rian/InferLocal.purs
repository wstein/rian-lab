-- | Infer-local / declare-public (ADR-0034) — the PureScript port of `Rian.InferLocal`
-- | (lib/rian/infer_local.ex), ADR-0084. Fills the types a **private** function leaves
-- | undeclared by local inference (a `def`-style helper needn't write a signature the compiler
-- | can recover); `pub` functions are untouched — they stay the explicit, declared boundary.
-- |
-- | Both **returns** and **parameters** are filled, by a bounded fixpoint that rebuilds the
-- | inference context each round (so a type filled this pass is visible to its callers next pass):
-- |
-- |   1. `fixpoint :unknown` — resolve params + returns with NO arithmetic default, so a param is
-- |      never frozen to `Int53` from a neighbour that may still resolve (a not-yet-typed callee);
-- |   2. `fixpoint Int53` — re-run with the `Int53` default, pinning genuinely-unconstrained
-- |      arithmetic params (`x + y` → `Int53`);
-- |   3. `generalizeParams` — a param the body left wholly unconstrained is parametric: generalize
-- |      it to a fresh `forall T` (so `def id(x) := x` works across types without an annotation);
-- |   4. `fixpoint Int53` — fix returns that depended on the above.
-- |
-- | A param used at conflicting types, or a return that still can't be pinned (self-recursion, an
-- | unmodelled body), renders `Any` (the dynamic top, ADR-0034): a real type, valid on every
-- | target but `:rs`, so the function is honestly dynamic rather than a parse error.
module Rian.InferLocal
  ( fillReturns
  , fillReturnsSexpr
  , fillSigSexpr
  ) where

import Prelude

import Data.Array (concatMap, filter, foldl, index, length, mapWithIndex, null, sortWith)
import Data.Foldable (any, sum)
import Data.Maybe (Maybe(..), fromMaybe, isNothing)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Check (Ic, Ty(..), inferParamType, inferReturnType, programIc, tyStr)
import Rian.Decl (parseToProg)
import Rian.IR (Body(..), Func, Prog, bodySurface)

-- | Fill undeclared private-function return + parameter types by local inference. A no-op unless
-- | some private function omitted its return or has an `:infer` (untyped) parameter.
-- @rian_sig pub def fill_returns(prog val Prog) Prog
fillReturns :: Prog -> Prog
fillReturns prog =
  if any (\f -> untypedRet f || hasInferParam f) (allFuncs prog) then
    let
      p0 = parseBodies prog
      p1 = fixpoint Unknown p0
      p2 = fixpoint int53 p1
      p3 = generalizeParams p2
      p4 = fixpoint int53 p3
    in
      fillUntypedAny p4
  else prog
  where
  int53 = TName "Int53"

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> concatMap _.funcs prog.mods

-- an undeclared **private** return (`pub` boundaries stay explicit).
untypedRet :: Func -> Boolean
untypedRet f = not f.pub && isNothing f.ret

-- a private function with a parameter left untyped (`:infer`, a lone lowercase token).
hasInferParam :: Func -> Boolean
hasInferParam f = not f.pub && any (\p -> isNothing p.ty) f.params

-- ── parse every clause body to its AST once (idempotent), so the fixpoint reuses it ──
parseBodies :: Prog -> Prog
parseBodies = overFuncs pb
  where
  pb f = f { clauses = map (\c -> c { body = map (Expanded <<< bodySurface) c.body }) f.clauses }

-- ── the bounded fixpoint: rebuild the ic each round, fill params then returns, stop when nothing
-- new is filled (bounded by the number of undeclared params + returns; monotone — only fills) ──
fixpoint :: Ty -> Prog -> Prog
fixpoint nd prog0 = go (slotCount prog0 + 1) prog0
  where
  go fuel p =
    if fuel <= 0 then p
    else
      let
        ic = (programIc p) { numDefault = nd }
        r = pass ic p
      in
        if r.accum then go (fuel - 1) r.value else r.value

slotCount :: Prog -> Int
slotCount prog = sum (map funcSlots (allFuncs prog))
  where
  funcSlots f = length (filter (\p -> isNothing p.ty) f.params) + (if isNothing f.ret then 1 else 0)

-- one pass over the top-level + module functions; `accum` is "did anything fill this pass".
pass :: Ic -> Prog -> { accum :: Boolean, value :: Prog }
pass ic prog =
  let
    rf = fillStep ic prog.funcs
    rm = mapAccum (\ch m -> let r = fillStep ic m.funcs in { accum: ch || r.accum, value: m { funcs = r.value } }) false prog.mods
  in
    { accum: rf.accum || rm.accum, value: prog { funcs = rf.value, mods = rm.value } }

-- params first (a return needs its param types), then the return.
fillStep :: Ic -> Array Func -> { accum :: Boolean, value :: Array Func }
fillStep ic funcs =
  let
    rp = fillParams ic funcs
    rr = fillFuncs ic rp.value
  in
    { accum: rp.accum || rr.accum, value: rr.value }

fillParams :: Ic -> Array Func -> { accum :: Boolean, value :: Array Func }
fillParams ic = mapAccum step false
  where
  step ch f =
    if hasInferParam f then let r = solveConcreteParams ic f in { accum: ch || r.accum, value: r.value }
    else { accum: ch, value: f }

-- fill only the params provable NOW (a concrete result). Leave an unconstrained `:infer` param for
-- a later round (a callee may not be typed yet) or for generalization. A used-at-conflict → `Any`.
solveConcreteParams :: Ic -> Func -> { accum :: Boolean, value :: Func }
solveConcreteParams ic f =
  let r = mapAccum pstep false (mapWithIndex Tuple f.params)
  in { accum: r.accum, value: f { params = r.value } }
  where
  pstep ch (Tuple i p) =
    if isNothing p.ty then case paramFill (inferParamType f i ic) of
      Just t -> { accum: true, value: p { ty = Just t } }
      Nothing -> { accum: ch, value: p }
    else { accum: ch, value: p }

-- a concrete inferred param type to write; `:mismatch` → `Any` (dynamic top); `:unknown` → leave.
paramFill :: Ty -> Maybe String
paramFill Unknown = Nothing
paramFill Mismatch = Just "Any"
paramFill t = Just (tyStr t)

fillFuncs :: Ic -> Array Func -> { accum :: Boolean, value :: Array Func }
fillFuncs ic = mapAccum step false
  where
  step ch f =
    if untypedRet f then case retFill (inferReturnType f ic) of
      Just t -> { accum: true, value: f { ret = Just t } }
      Nothing -> { accum: ch, value: f }
    else { accum: ch, value: f }

-- a concrete inferred return to write; `:unknown`/`:mismatch` → leave (defaulted to `Any` later).
retFill :: Ty -> Maybe String
retFill Unknown = Nothing
retFill Mismatch = Nothing
retFill t = Just (tyStr t)

-- ── generalize: a private function's still-`:infer` param is parametric — a fresh `forall T` ──
generalizeParams :: Prog -> Prog
generalizeParams = overFuncs generalizeFunc

generalizeFunc :: Func -> Func
generalizeFunc f =
  if not f.pub && any (\p -> isNothing p.ty) f.params then
    let r = mapAccum gstep f.tvars f.params
    in f { params = r.value, tvars = r.accum }
  else f
  where
  gstep used p =
    if isNothing p.ty then let tv = freshTvar used in { accum: used <> [ tv ], value: p { ty = Just tv } }
    else { accum: used, value: p }

-- the first unused type-variable name: single letters (`T`…`Z`, `A`…`S`), then letter+digit
-- (`A0`…`Z9`) — the whole space `Check.tvar?` accepts. A duplicate would collapse two parameters'
-- independent polymorphism into a spurious equality, so exhausting all 286 raises (sound, never a guess).
-- Scanned by hand with `index`/`foldl`: purerl miscompiles `find`/`elem` over this large literal
-- array (the predicate evaluates wrong, so the whole search returns nothing); the manual walk is exact.
freshTvar :: Array String -> String
freshTvar used = go 0
  where
  go i = case index candidates i of
    Nothing -> unsafeCrashWith "too many inferred type variables in one function — annotate some parameter types"
    Just c -> if usedHas c then go (i + 1) else c
  usedHas c = foldl (\acc u -> acc || u == c) false used
  -- spelled out as one flat literal rather than built from `enumFromTo`/`concatMap` (purerl's
  -- `Enum Char` yields empty ranges, and the build chain lowered to a malformed array).
  candidates =
    [ "T", "U", "V", "W", "X", "Y", "Z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O"
    , "P", "Q", "R", "S", "A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "B0", "B1", "B2", "B3", "B4"
    , "B5", "B6", "B7", "B8", "B9", "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "D0", "D1", "D2"
    , "D3", "D4", "D5", "D6", "D7", "D8", "D9", "E0", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "F0"
    , "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8"
    , "G9", "H0", "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "I0", "I1", "I2", "I3", "I4", "I5", "I6"
    , "I7", "I8", "I9", "J0", "J1", "J2", "J3", "J4", "J5", "J6", "J7", "J8", "J9", "K0", "K1", "K2", "K3", "K4"
    , "K5", "K6", "K7", "K8", "K9", "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "M0", "M1", "M2"
    , "M3", "M4", "M5", "M6", "M7", "M8", "M9", "N0", "N1", "N2", "N3", "N4", "N5", "N6", "N7", "N8", "N9", "O0"
    , "O1", "O2", "O3", "O4", "O5", "O6", "O7", "O8", "O9", "P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"
    , "P9", "Q0", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8", "Q9", "R0", "R1", "R2", "R3", "R4", "R5", "R6"
    , "R7", "R8", "R9", "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "T0", "T1", "T2", "T3", "T4"
    , "T5", "T6", "T7", "T8", "T9", "U0", "U1", "U2", "U3", "U4", "U5", "U6", "U7", "U8", "U9", "V0", "V1", "V2"
    , "V3", "V4", "V5", "V6", "V7", "V8", "V9", "W0", "W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "X0"
    , "X1", "X2", "X3", "X4", "X5", "X6", "X7", "X8", "X9", "Y0", "Y1", "Y2", "Y3", "Y4", "Y5", "Y6", "Y7", "Y8"
    , "Y9", "Z0", "Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7", "Z8", "Z9"
    ]

-- ── a private return still unpinned renders `Any` (the dynamic top, ADR-0034) ──
fillUntypedAny :: Prog -> Prog
fillUntypedAny = overFuncs (\f -> if not f.pub && isNothing f.ret then f { ret = Just "Any" } else f)

-- apply `g` to every top-level and module function.
overFuncs :: (Func -> Func) -> Prog -> Prog
overFuncs g prog = prog { funcs = map g prog.funcs, mods = map (\m -> m { funcs = map g m.funcs }) prog.mods }

-- a deterministic left-to-right map-with-accumulator. Replaces `Data.Traversable.mapAccumL`, whose
-- purerl `StateL` lowering mishandles an `Array`-typed accumulator (the `generalize` pass threads
-- the used-tvar list as state — `mapAccumL` corrupts it, so `freshTvar` sees a bogus `used`).
mapAccum :: forall s a b. (s -> a -> { accum :: s, value :: b }) -> s -> Array a -> { accum :: s, value :: Array b }
mapAccum f s0 = foldl step { accum: s0, value: [] }
  where
  step acc x = let r = f acc.accum x in { accum: r.accum, value: acc.value <> [ r.value ] }

-- | The `ilr` parity unit: every function's return after `fillReturns`, `name/arity=>ret` sorted.
fillReturnsSexpr :: String -> String
fillReturnsSexpr src =
  joinWith ";" (sortWith identity (map entry (allFuncs (fillReturns (parseToProg src)))))
  where
  entry f = f.name <> "/" <> show (length f.params) <> "=>" <> fromMaybe "_" f.ret

-- | The `ilp` parity unit: every function's FULL inferred signature after `fillReturns` —
-- | `name/arity:p0,p1=>ret[tvars]` sorted (proves parameter inference + `forall T` generalization).
fillSigSexpr :: String -> String
fillSigSexpr src =
  joinWith ";" (sortWith identity (map entry (allFuncs (fillReturns (parseToProg src)))))
  where
  entry f =
    f.name <> "/" <> show (length f.params)
      <> ":" <> joinWith "," (map (\p -> fromMaybe "_" p.ty) f.params)
      <> "=>" <> fromMaybe "_" f.ret
      <> (if null f.tvars then "" else "[" <> joinWith "," f.tvars <> "]")
