-- | Maranget pattern-match analysis (usefulness, "Warnings for pattern matching",
-- | JFP 2007) — the PureScript port of `Rian.Exhaustiveness` (lib/rian/exhaustiveness.ex),
-- | ADR-0084 / ADR-0036. One algorithm yields three diagnostics: exhaustiveness,
-- | unreachable clauses, and a counterexample witness (algorithm I). Consumes the checker
-- | patterns produced by `Rian.PatternLower` over the ported `Rian.Core`.
-- |
-- | `program_env` (the whole-program env that injects the prelude types) is NOT ported
-- | here: it depends on `Rian.Prelude.with_prelude`, a tail dependency that lands with the
-- | later passes. The analysis engine itself — `base_env`/`add_type`/`add_range`/`useful?`/
-- | `analyze`/`render` — is complete and parity-gated via the `plw`/`exh` streams over a
-- | fixed scenario table (mirrored in `gen_fixtures.exs`), the same shape as `Rian.Range`.
module Rian.Exhaustiveness
  ( Cov(..)
  , Arm
  , Result
  , baseEnv
  , addType
  , addRange
  , useful
  , analyze
  , render
  , renderVec
  , programEnv
  , plowSexpr
  , analyzeSexpr
  , programEnvSexpr
  ) where

import Prelude

import Data.Array (difference, filter, findMap, length, nubEq, null, range, replicate, snoc, sortWith, splitAt, uncons, (:))
import Data.Foldable (all, any, elem, find, foldMap, foldl)
import Data.FoldableWithIndex (foldlWithIndex)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String.CodeUnits as CU
import Data.String.Common (joinWith, split, toUpper)
import Data.String.Pattern (Pattern(..))
import Data.Tuple (Tuple(..), fst, snd)
import Rian.Decl (parseToProg)
import Rian.IR (Range, Struct, Type)
import Rian.PatternLower (CkPat(..), CtorId(..), Env, LitV(..), Sig(..), addStruct, arityOf, aLookup, aPut, lowerClause, toSnake)
import Rian.Prelude (withPrelude)

-- | Whether the present head constructors cover the whole type.
data Cov = Complete (Array CtorId) | Incomplete

-- ── Environment helpers ─────────────────────────────────────────────────────

-- | Base env: built-in bool, list, and the infinite primitive types.
-- @rian_sig pub def baseEnv() Env
baseEnv :: Env
baseEnv =
  { arity: [ Tuple CNil 0, Tuple CCons 2, Tuple (CName "true") 0, Tuple (CName "false") 0 ]
  , typeOf:
      [ Tuple CNil "list", Tuple CCons "list", Tuple (CName "true") "bool", Tuple (CName "false") "bool" ]
  , ctors:
      [ Tuple "list" (Finite [ CNil, CCons ])
      , Tuple "bool" (Finite [ CName "true", CName "false" ])
      , Tuple "int" Infinite
      , Tuple "float" Infinite
      , Tuple "str" Infinite
      , Tuple "map" Infinite
      ]
  , structs: []
  }

-- | Register a sum type: `variants` is `[(ctor_id, arity)]`.
-- @rian_sig pub def addType(env val Env, typeName val Symbol, variants val Vec((CtorId, Int53))) Env
addType :: Env -> String -> Array (Tuple CtorId Int) -> Env
addType env tn variants =
  let
    ids = map (\(Tuple c _) -> c) variants
    arity' = foldlWithIndex (\_ acc (Tuple c a) -> aPut c a acc) env.arity variants
    typeOf' = foldlWithIndex (\_ acc c -> aPut c tn acc) env.typeOf ids
  in
    env { arity = arity', typeOf = typeOf', ctors = aPut tn (Finite ids) env.ctors }

-- | Register a finite ordinal `range` type (ADR-0036): the inclusive interval `lo..hi`
-- | over an ordinal base. Its members are the `{:lit, v}` constructors, so a `case`
-- | covering the whole interval is exhaustive.
-- @rian_sig pub def addRange(env val Env, typeName val Symbol, lo val Int53, hi val Int53) Env
addRange :: Env -> String -> Int -> Int -> Env
addRange env tn lo hi =
  let
    members = map (\v -> CLit (LvInt v)) (range lo hi)
    typeOf' = foldlWithIndex (\_ acc m -> aPut m tn acc) env.typeOf members
  in
    env { typeOf = typeOf', ctors = aPut tn (Finite members) env.ctors }

-- | The signature env for a whole program (prelude + user types + ranges + structs). The
-- | built-in `Option` is prepended via `Rian.Prelude.with_prelude`, so a `case` over it is
-- | exhaustiveness-checkable without a `type Option := …` in the source (ADR-0047 §3).
-- @rian_sig pub def programEnv(types val Vec(Type), structs val Vec(Struct), ranges val Vec(Range)) Env
programEnv :: Array Type -> Array Struct -> Array Range -> Env
programEnv types structs ranges =
  foldl addS (foldl addR (foldl addT baseEnv (withPrelude types)) ranges) structs
  where
  addT env t = addType env (toSnake t.name) (map variant t.variants)
  variant v = Tuple (CName (toSnake v.ctor)) (length v.fields)
  addR env r = addRange env r.name r.lo r.hi
  addS env s = addStruct env s.name (map (toSnake <<< fromMaybe "" <<< _.label) s.fields)

-- ── Signature / matrix operations ────────────────────────────────────────────

signature :: Env -> Array CtorId -> Cov
signature env present = case uncons present of
  Nothing -> Incomplete
  Just { head: c } -> case c of
    CTuple _ -> Complete [ c ]
    _ -> case aLookup c env.typeOf >>= \tn -> aLookup tn env.ctors of
      Just (Finite alls) -> if subset alls present then Complete alls else Incomplete
      _ -> Incomplete
  where
  subset alls ps = all (\x -> elem x ps) alls

headCtors :: Array (Array CkPat) -> Array CtorId
headCtors rows = nubEq (rows >>= headOf)
  where
  headOf row = case uncons row of
    Just { head: Ctor c _ } -> [ c ]
    _ -> []

-- Specialize by constructor c: keep rows that can match c, expanding sub-patterns.
specialize :: Array (Array CkPat) -> CtorId -> Env -> Array (Array CkPat)
specialize rows c env = rows >>= row
  where
  a = arityOf env c
  row r = case uncons r of
    Just { head: Ctor c' args, tail: rest } -> if c' == c then [ args <> rest ] else []
    Just { head: Wild, tail: rest } -> [ replicate a Wild <> rest ]
    Nothing -> []

-- Default matrix: rows whose head is a wildcard, with the head column dropped.
defaultM :: Array (Array CkPat) -> Array (Array CkPat)
defaultM rows = rows >>= row
  where
  row r = case uncons r of
    Just { head: Ctor _ _ } -> []
    Just { head: Wild, tail: rest } -> [ rest ]
    Nothing -> []

-- ── Usefulness U(P, q) ───────────────────────────────────────────────────────

-- | Is pattern vector `q` useful w.r.t. matrix `rows`?
-- @rian_sig pub def useful(rows val Vec(Vec(CkPat)), q val Vec(CkPat), env val Env) Bool
useful :: Array (Array CkPat) -> Array CkPat -> Env -> Boolean
useful rows q env = case uncons q of
  Nothing -> null rows
  Just { head: Ctor c args, tail: qrest } -> useful (specialize rows c env) (args <> qrest) env
  Just { head: Wild, tail: qrest } -> case signature env (headCtors rows) of
    Complete ctors ->
      any (\c -> useful (specialize rows c env) (replicate (arityOf env c) Wild <> qrest) env) ctors
    Incomplete -> useful (defaultM rows) qrest env

-- ── Witness / counterexample (algorithm I) ───────────────────────────────────

witness :: Array (Array CkPat) -> Int -> Env -> Maybe (Array CkPat)
witness rows 0 _ = if null rows then Just [] else Nothing
witness rows n env =
  let present = headCtors rows in
  case signature env present of
    Complete ctors -> findMap
      ( \c ->
          let a = arityOf env c in
          case witness (specialize rows c env) (a + n - 1) env of
            Just ws ->
              let { before: headWs, after: rest } = splitAt a ws in
              Just (Ctor c headWs : rest)
            Nothing -> Nothing
      )
      ctors
    Incomplete -> case witness (defaultM rows) (n - 1) env of
      Just ws -> Just (missingHead env present : ws)
      Nothing -> Nothing

missingHead :: Env -> Array CtorId -> CkPat
missingHead env present = case uncons present of
  Nothing -> Wild
  Just { head: c } -> case aLookup c env.typeOf >>= \tn -> aLookup tn env.ctors of
    Just (Finite alls) -> case uncons (difference alls present) of
      Just { head: m } -> Ctor m (replicate (arityOf env m) Wild)
      Nothing -> Wild
    _ -> Wild

-- ── Top-level analysis ───────────────────────────────────────────────────────

type Arm = { pat :: Array CkPat, guard :: Boolean }

type Result = { exhaustive :: Boolean, missing :: Maybe (Array CkPat), unreachable :: Array Int }

-- | Analyze clauses. `n` is the scrutinee arity. Returns exhaustiveness, a witness
-- | (when not exhaustive), and the 0-based indices of unreachable clauses.
-- @rian_sig pub def analyze(arms val Vec(Arm), n val Int53, env val Env) Result
analyze :: Array Arm -> Int -> Env -> Result
analyze arms n env =
  let
    unguarded = map _.pat (filter (not <<< _.guard) arms)
    exhaustive = not (useful unguarded (replicate n Wild) env)
    missing = if exhaustive then Nothing else witness unguarded n env
    final = foldlWithIndex step { unreach: [], prior: [] } arms
    step idx acc arm =
      { unreach: if useful acc.prior arm.pat env then acc.unreach else snoc acc.unreach idx
      , prior: if arm.guard then acc.prior else snoc acc.prior arm.pat
      }
  in
    { exhaustive, missing, unreachable: final.unreach }

-- ── Rendering (for diagnostics + parity) ─────────────────────────────────────

-- @rian_sig pub def render(node val CkPat) String
render :: CkPat -> String
render Wild = "_"
render (Ctor (CLit v) []) = inspectLit v
render (Ctor (CTuple _) args) = "{" <> joinWith ", " (map render args) <> "}"
render (Ctor CNil []) = "[]"
render (Ctor CCons [ h, t ]) = "[" <> render h <> " | " <> render t <> "]"
render (Ctor c []) = pascal c
render (Ctor c args) = pascal c <> "(" <> joinWith ", " (map render args) <> ")"
render _ = "_"

renderVec :: Array CkPat -> String
renderVec = joinWith ", " <<< map render

inspectLit :: LitV -> String
inspectLit (LvInt n) = show n
inspectLit (LvStr s) = "\"" <> s <> "\""
inspectLit (LvAtom a) = ":" <> a

pascal :: CtorId -> String
pascal (CName s)
  | s == "true" || s == "false" = s
  | otherwise = joinWith "" (map cap (split (Pattern "_") s))
pascal (CLit v) = inspectLit v
pascal (CTuple n) = "tup" <> show n
pascal CNil = "[]"
pascal CCons = "cons"

cap :: String -> String
cap w = case CU.uncons w of
  Just { head, tail } -> toUpper (CU.singleton head) <> tail
  Nothing -> ""

-- ── Parity scenarios (fixed table, mirrored in gen_fixtures.exs) ──────────────

type SArm = { src :: String, guard :: Boolean }
type Scenario = { env :: Env, arms :: Array SArm, n :: Int }

a :: String -> SArm
a src = { src, guard: false }

envTree :: Env
envTree = addType baseEnv "tree" [ Tuple (CName "leaf") 0, Tuple (CName "node") 2 ]

envOption :: Env
envOption = addType baseEnv "option" [ Tuple (CName "some") 1, Tuple (CName "none") 0 ]

envPoint :: Env
envPoint = addStruct baseEnv "Point" [ "x", "y" ]

scenarios :: Array (Tuple String Scenario)
scenarios =
  [ Tuple "list-exhaustive" { env: baseEnv, arms: [ a "[]", a "[h | t]" ], n: 1 }
  , Tuple "list-missing-nil" { env: baseEnv, arms: [ a "[h | t]" ], n: 1 }
  , Tuple "list-wild" { env: baseEnv, arms: [ a "[]", a "_" ], n: 1 }
  , Tuple "tuple-2" { env: baseEnv, arms: [ a "{x, y}" ], n: 1 }
  , Tuple "tree-exhaustive" { env: envTree, arms: [ a "Leaf", a "Node(l, r)" ], n: 1 }
  , Tuple "tree-missing-node" { env: envTree, arms: [ a "Leaf" ], n: 1 }
  , Tuple "tree-nested-witness" { env: envTree, arms: [ a "Node(Leaf, Leaf)", a "Leaf" ], n: 1 }
  , Tuple "option-exhaustive" { env: envOption, arms: [ a "Some(x)", a "None" ], n: 1 }
  , Tuple "option-missing-none" { env: envOption, arms: [ a "Some(x)" ], n: 1 }
  , Tuple "lit-int-infinite" { env: baseEnv, arms: [ a "0", a "1" ], n: 1 }
  , Tuple "lit-int-wild" { env: baseEnv, arms: [ a "0", a "_" ], n: 1 }
  , Tuple "range-exhaustive" { env: addRange baseEnv "digit" 0 3, arms: [ a "0", a "1", a "2", a "3" ], n: 1 }
  , Tuple "range-incomplete" { env: addRange baseEnv "digit" 0 3, arms: [ a "0", a "1" ], n: 1 }
  , Tuple "unreachable-after-wild" { env: baseEnv, arms: [ a "_", a "[]" ], n: 1 }
  , Tuple "as-passthrough" { env: baseEnv, arms: [ a "all @ [h | t]", a "[]" ], n: 1 }
  , Tuple "guard-excluded" { env: baseEnv, arms: [ { src: "[]", guard: true }, a "_" ], n: 1 }
  , Tuple "two-arg" { env: envTree, arms: [ a "Leaf, Leaf", a "_, _" ], n: 2 }
  -- struct patterns: a single-ctor type is exhaustive; field order is canonicalized so a
  -- reordered `Point(y: …, x: …)` lowers to the same positional vector.
  , Tuple "struct-exhaustive" { env: envPoint, arms: [ a "Point(x: p, y: q)" ], n: 1 }
  , Tuple "struct-reordered" { env: envPoint, arms: [ a "Point(y: q, x: p)" ], n: 1 }
  -- atom literals are an open universe (infinite): a `_` arm is still required.
  , Tuple "atom-infinite" { env: baseEnv, arms: [ a ":ok", a ":err" ], n: 1 }
  , Tuple "atom-wild" { env: baseEnv, arms: [ a ":ok", a "_" ], n: 1 }
  ]

lookupScenario :: String -> Maybe Scenario
lookupScenario name = map snd (find (\(Tuple k _) -> k == name) scenarios)

loweredArms :: Scenario -> Array Arm
loweredArms sc = map (\arm -> lowerClause arm.src arm.guard sc.env) sc.arms

-- | The `plw` stream: the lowered checker patterns + effective guard, per arm. Directly
-- | exercises `PatternLower.lower`.
plowSexpr :: String -> String
plowSexpr name = case lookupScenario name of
  Nothing -> "?"
  Just sc -> joinWith " ; " (map (\c -> renderVec c.pat <> " g=" <> show c.guard) (loweredArms sc))

-- | The `exh` stream: the `analyze` result over a scenario's lowered arms.
analyzeSexpr :: String -> String
analyzeSexpr name = case lookupScenario name of
  Nothing -> "?"
  Just sc ->
    let r = analyze (loweredArms sc) sc.n sc.env in
    "exh=" <> show r.exhaustive
      <> " miss=" <> maybe "-" renderVec r.missing
      <> " unr=" <> joinWith "," (map show r.unreachable)

-- | The `pge` stream: build `program_env` from a source's types/structs/ranges and serialize
-- | its `ctors` signature table (sorted by type name), so the prelude/type/range/struct
-- | registration is checked end-to-end (`Decl → program_env`).
programEnvSexpr :: String -> String
programEnvSexpr src =
  let prog = parseToProg src in
  envSexpr (programEnv prog.types prog.structs prog.ranges)

envSexpr :: Env -> String
envSexpr env = "(env" <> foldMap entry (sortWith fst env.ctors) <> ")"
  where
  entry (Tuple tn sig) = " (" <> tn <> " " <> sigStr sig <> ")"
  sigStr (Finite cs) = joinWith "," (map ctorStr cs)
  sigStr Infinite = "*"

ctorStr :: CtorId -> String
ctorStr CNil = "nil"
ctorStr CCons = "cons"
ctorStr (CTuple n) = "tup" <> show n
ctorStr (CName s) = s
ctorStr (CLit (LvInt n)) = "#" <> show n
ctorStr (CLit (LvStr s)) = "#" <> s
ctorStr (CLit (LvAtom a)) = "#:" <> a
