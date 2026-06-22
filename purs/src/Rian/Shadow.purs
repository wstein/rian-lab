-- | Capture-avoiding `:=` shadow rename over the Core IR (ADR-0034) — the PureScript port
-- | of `Rian.Shadow` (lib/rian/shadow.ex), ADR-0084. A Rian block may rebind a name
-- | (`x := …; x := …`); on targets whose binding forms forbid same-scope re-declaration
-- | (JS `let`/`const`, Kotlin `val`/`var`) the second binding needs a fresh name. This pass
-- | rewrites a Core `EBlock` statement list so every same-scope binding is unique and every
-- | reference resolves to the binding in force at its position.
-- |
-- | The fresh-name *scheme* is target-specific, supplied as `fresh = \base count -> name`;
-- | the renaming *logic* is shared. `dedup` seeds the version map with the clause params so a
-- | `:=` rebinding a parameter is renamed; each nested Rian block is its own target scope.
-- |
-- | The Elixir reference walks unknown nodes with `Map.from_struct` reflection (purerl has
-- | none), so the traversal here is **reflection-free**: an explicit per-`CExpr` recursion,
-- | special-casing `EId` (rename), `EBlock` (a fresh scope), and `ECase` (arm patterns bind
-- | their own vars), threading the rename map through every other child.
module Rian.Shadow
  ( Fresh
  , dedup
  , dedupSexpr
  ) where

import Prelude

import Data.Array (filter, snoc)
import Data.Array (find) as Array
import Data.Foldable (elem, foldl)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple (Tuple(..), snd)
import Rian.Core (CExpr(..), CMapPair(..), CPat(..), CStmt(..), coreSexpr, fromExpr)
import Rian.Prim (normalize)
import Rian.Pratt (parseBody) as P

-- the rename map (a free reference's current name) and the per-name version count.
type Rename = Array (Tuple String String)
type Ver = Array (Tuple String Int)

-- | The target's fresh-name scheme: `base`, the shadow count → a fresh identifier.
type Fresh = String -> Int -> String

-- | Rewrite a block's statement list so shadowing binds get fresh names. `params` are the
-- | clause parameter names (seeded so a param rebind renames).
-- @rian_sig pub def dedup(stmts val Vec(Stmt), params val Vec(String), fresh val Fn(String, Int53, String)) Vec(Stmt)
dedup :: Array CStmt -> Array String -> Fresh -> Array CStmt
dedup stmts params fresh = dedBlock fresh stmts [] (map (\p -> Tuple p 1) params)

type State = { acc :: Array CStmt, r :: Rename, ver :: Ver }

dedBlock :: Fresh -> Array CStmt -> Rename -> Ver -> Array CStmt
dedBlock fresh stmts r0 ver0 =
  (foldl (stepStmt fresh) { acc: [], r: r0, ver: ver0 } stmts).acc

stepStmt :: Fresh -> State -> CStmt -> State
stepStmt fresh st = case _ of
  CBind n e -> dedBind fresh n Nothing e st
  CTypedBind n t e -> dedBind fresh n (Just t) e st
  CExprStmt e -> st { acc = snoc st.acc (CExprStmt (dedExpr fresh e st.r)) }

dedBind :: Fresh -> String -> Maybe String -> CExpr -> State -> State
dedBind fresh n mt e st =
  let
    e2 = dedExpr fresh e st.r
    count = fromMaybe 0 (aLookup n st.ver)
    Tuple name r2 =
      if count == 0 then
        -- first binding in this block shadows any outer rename of the same name
        Tuple n (dropKey n st.r)
      else
        let new = fresh n count in Tuple new (aPut n new st.r)
    stmt = case mt of
      Just t -> CTypedBind name t e2
      Nothing -> CBind name e2
  in
    { acc: snoc st.acc stmt, r: r2, ver: aPut n (count + 1) st.ver }

-- rename free references through `r`, descending into nested binders with the shadowed
-- names removed (a nested block opens a fresh scope; `case` arm patterns bind their own vars).
dedExpr :: Fresh -> CExpr -> Rename -> CExpr
dedExpr fresh node r = case node of
  EId x -> EId (fromMaybe x (aLookup x r))
  EBlock stmts -> EBlock (dedBlock fresh stmts r [])
  ECase scrut arms -> ECase (rec scrut) (map (dedArm fresh r) arms)
  EUnary op e -> EUnary op (rec e)
  EBin op l rr -> EBin op (rec l) (rec rr)
  ECall f args -> ECall (rec f) (map rec args)
  EDot h nm -> EDot (rec h) nm
  EIf c t e -> EIf (rec c) (rec t) (rec e)
  EWith cls body els ->
    EWith (map (\cl -> cl { expr = rec cl.expr }) cls) (rec body) (map (dedArm fresh r) els)
  EList es tl -> EList (map rec es) (map rec tl)
  EMap ps -> EMap (map (dedMapPair fresh r) ps)
  ETuple es -> ETuple (map rec es)
  ELambda ps body -> ELambda ps (rec body)
  ECapture e -> ECapture (rec e)
  ECaptureNamed e nn -> ECaptureNamed (rec e) nn
  ELabel nm e -> ELabel nm (rec e)
  other -> other
  where
  rec e = dedExpr fresh e r

dedArm :: Fresh -> Rename -> { pat :: CPat, guard :: Maybe CExpr, body :: CExpr } -> { pat :: CPat, guard :: Maybe CExpr, body :: CExpr }
dedArm fresh r arm =
  let inner = dropKeys (patVarNames arm.pat) r in
  arm { guard = map (\g -> dedExpr fresh g inner) arm.guard, body = dedExpr fresh arm.body inner }

dedMapPair :: Fresh -> Rename -> CMapPair -> CMapPair
dedMapPair fresh r (CMAtom k v) = CMAtom k (dedExpr fresh v r)
dedMapPair fresh r (CMKey k v) = CMKey (dedExpr fresh k r) (dedExpr fresh v r)

-- the variable names a pattern binds (so an arm body's rename map drops them). Mirrors the
-- reference: only `PVar`/`PCtor`/`PList`/`PTuple`/`PStruct` contribute (an `@`-as binder and
-- literals do not), so a shadowed name re-bound by an arm pattern resolves to the arm var.
patVarNames :: CPat -> Array String
patVarNames (PVar n) = [ n ]
patVarNames (PCtor _ args _) = bind args patVarNames
patVarNames (PList ps tail) = maybe [] patVarNames tail <> bind ps patVarNames
patVarNames (PTuple ps) = bind ps patVarNames
patVarNames (PStruct _ fs) = bind fs (\(Tuple _ p) -> patVarNames p)
patVarNames _ = []

-- ── association-list helpers ─────────────────────────────────────────────────

aLookup :: forall v. String -> Array (Tuple String v) -> Maybe v
aLookup k = map snd <<< Array.find (\(Tuple k' _) -> k' == k)

aPut :: forall v. String -> v -> Array (Tuple String v) -> Array (Tuple String v)
aPut k v xs = snoc (dropKey k xs) (Tuple k v)

dropKey :: forall v. String -> Array (Tuple String v) -> Array (Tuple String v)
dropKey k = filter (\(Tuple k' _) -> k' /= k)

dropKeys :: forall v. Array String -> Array (Tuple String v) -> Array (Tuple String v)
dropKeys ks = filter (\(Tuple k' _) -> not (k' `elem` ks))

-- ── parity entry ─────────────────────────────────────────────────────────────

-- | The `shd` stream: dedup a `;`-separated body (clause params fixed to `["p"]`, the
-- | fresh scheme `base$count`), composing `Pratt.parseBody → Prim.normalize → Core → dedup`.
dedupSexpr :: String -> String
dedupSexpr src =
  let
    stmts = case fromExpr (normalize (P.parseBody src)) of
      EBlock ss -> ss
      e -> [ CExprStmt e ]
  in
    coreSexpr (EBlock (dedup stmts [ "p" ] freshScheme))

freshScheme :: Fresh
freshScheme base count = base <> "$" <> show count
