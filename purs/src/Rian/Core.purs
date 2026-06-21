-- | The typed core IR (ADR-0050) — the PureScript port of `Rian.Core`'s
-- | `from_expr`/`from_pat` (lib/rian/core.ex), ADR-0084 Phase 2. Lowers the transient
-- | surface AST (`Rian.Pratt`'s output) into a sealed-sum core that the checker and every
-- | emitter consume.
-- |
-- | Each node will carry an inferred `type` once `Rian.Check` lands; until then the nodes
-- | are purely structural (the checker fills the types). `from_expr` performs the surface
-- | desugarings — pipe `|>` → call, range `..` → `List.seq`, comprehension → nested
-- | `List.flat_map` — so every downstream pass sees one representation.
-- |
-- | Parity (the `cor` stream) composes `lexer → Pratt → Core`: `coreSexpr` canonicalizes
-- | the typed core (Core has no built-in renderer, unlike Pratt) and is diffed against the
-- | matching `CoreCanon` in `purs/test/gen_fixtures.exs`. Staged out (excluded from the
-- | corpus, mirroring the Pratt stages): string interpolation (resolved before Core),
-- | for-comprehension *pattern* generators (gensym), bitstrings, map update.
module Rian.Core
  ( CExpr(..)
  , CPat(..)
  , LitVal(..)
  , CArm
  , CWithClause
  , CStmt(..)
  , CMapPair(..)
  , CMapPatPair(..)
  , fromExpr
  , fromPat
  , coreSexpr
  , corePatSexpr
  , fromSource
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..))
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Pratt as P

--------------------------------------------------------------------------------
-- Core IR nodes
--------------------------------------------------------------------------------

data LitVal = LInt Int | LStr String

data CExpr
  = ENum String
  | EStr String
  | EChar Int
  | EId String
  | EAtom String
  | EUnary String CExpr
  | EBin String CExpr CExpr
  | ECall CExpr (Array CExpr)
  | EDot CExpr String
  | EIf CExpr CExpr CExpr
  | ECase CExpr (Array CArm)
  | EWith (Array CWithClause) CExpr (Array CArm)
  | EBlock (Array CStmt)
  | EList (Array CExpr) (Maybe CExpr) -- Nothing = `:close`
  | EMap (Array CMapPair)
  | EMapUpdate CExpr (Array CMapPair) -- `%{base | k: v, …}` (ADR-0033)
  | ETuple (Array CExpr)
  | ELambda (Array P.Param) CExpr
  | ECapture CExpr
  | ECaptureNamed CExpr Int
  | ECapArg Int
  | ELabel String CExpr

type CArm = { pat :: CPat, guard :: Maybe CExpr, body :: CExpr }
type CWithClause = { pat :: CPat, expr :: CExpr }

data CStmt
  = CBind String CExpr
  | CTypedBind String String CExpr
  | CExprStmt CExpr

data CMapPair
  = CMAtom String CExpr
  | CMKey CExpr CExpr

data CPat
  = PWild
  | PVar String
  | PLit LitVal
  | PChar Int
  | PAtom String
  | PTuple (Array CPat)
  | PList (Array CPat) (Maybe CPat)
  | PCtor String (Array CPat)
  | PAs String CPat
  | PPin P.Surface -- the pinned expression, carried verbatim (matched at runtime)
  | PStruct String (Array (Tuple String CPat))
  | PMap (Array CMapPatPair)
  | PTyped String String

data CMapPatPair
  = CMPAtom String CPat
  | CMPKey CExpr CPat

--------------------------------------------------------------------------------
-- from_expr — surface AST → typed core (with the desugarings)
--------------------------------------------------------------------------------

-- | Translate a surface expression (`Rian.Pratt` output) into the typed core.
-- @rian_sig pub def fromExpr(surface val Surface) Expr
fromExpr :: P.Surface -> CExpr
fromExpr (P.SNum n) = ENum n
fromExpr (P.SStr s) = EStr s
fromExpr (P.SChar c) = EChar c
fromExpr (P.SId x) = EId x
fromExpr (P.SAtom a) = EAtom a
fromExpr (P.SStrInterp _) =
  unsafeCrashWith "Core: string interpolation is not supported here (resolved before Core, ADR-0069)"
-- the pipe `a |> f(b, …)` desugars to a plain call `f(a, b, …)`.
fromExpr (P.SBin "|>" l r) = fromExpr (pipeInto l r)
-- an inclusive range `lo..hi` desugars to the portable prelude `List.seq(lo, hi)`.
fromExpr (P.SBin ".." l r) = fromExpr (P.SCall (P.SDot (P.SId "List") "seq") [ l, r ])
fromExpr (P.SBin op l r) = EBin op (fromExpr l) (fromExpr r)
fromExpr (P.SUnary op x) = EUnary op (fromExpr x)
fromExpr (P.SCall f args) = ECall (fromExpr f) (map fromExpr args)
fromExpr (P.SDot h n) = EDot (fromExpr h) n
fromExpr (P.SIf c t e) = EIf (fromExpr c) (fromExpr t) (fromExpr e)
fromExpr (P.STuple es) = ETuple (map fromExpr es)
fromExpr (P.SMapLit ps) = EMap (map fromMapPair ps)
fromExpr (P.SMapUpdate base ps) = EMapUpdate (fromExpr base) (map fromMapPair ps)
fromExpr (P.SCapArg n) = ECapArg n
fromExpr (P.SCapture b) = ECapture (fromExpr b)
fromExpr (P.SCaptureNamed p a) = ECaptureNamed (fromExpr p) a
fromExpr (P.SLabel n e) = ELabel n (fromExpr e)
fromExpr (P.SLambda ps b) = ELambda ps (fromExpr b)
fromExpr (P.SFor clauses body) = desugarFor clauses body
fromExpr (P.SListLit es tail) = EList (map fromExpr es) (map fromExpr tail)
fromExpr (P.SCase scrut arms) = ECase (fromExpr scrut) (map fromArm arms)
fromExpr (P.SWith clauses body els) =
  EWith (map fromWithClause clauses) (fromExpr body) (map fromArm els)
-- ADR-0035: a block's value is its final expression — a trailing bind has no portable value.
fromExpr (P.SBlock stmts) = case Array.last stmts of
  Just (P.StBind name _) -> unsafeCrashWith (trailingBind name)
  Just (P.StTypedBind name _ _) -> unsafeCrashWith (trailingBind name)
  _ -> EBlock (map fromStmt stmts)

trailingBind :: String -> String
trailingBind name =
  "Core: a block body must end in an expression, not the binding `" <> name <> " := …` (ADR-0035)"

pipeInto :: P.Surface -> P.Surface -> P.Surface
pipeInto l (P.SCall fun args) = P.SCall fun (Array.cons l args)
pipeInto l callee = P.SCall callee [ l ]

fromMapPair :: P.MapPair -> CMapPair
fromMapPair (P.MAtom k v) = CMAtom k (fromExpr v)
fromMapPair (P.MKey k v) = CMKey (fromExpr k) (fromExpr v)

fromStmt :: P.Stmt -> CStmt
fromStmt (P.StBind n e) = CBind n (fromExpr e)
fromStmt (P.StTypedBind n t e) = CTypedBind n t (fromExpr e)
fromStmt (P.StExpr e) = CExprStmt (fromExpr e)

fromArm :: P.Arm -> CArm
fromArm a = { pat: fromPat a.pat, guard: map fromExpr a.guard, body: fromExpr a.body }

fromWithClause :: P.WithClause -> CWithClause
fromWithClause c = { pat: fromPat c.pat, expr: fromExpr c.expr }

-- comprehension desugar (ADR-0079), right-to-left. A *variable* generator is a direct
-- `List.flat_map` lambda binding; a filter is an `if … else []`; the leaf is `[body]`.
-- A non-variable (pattern) generator needs gensym — staged out, excluded from the corpus.
desugarFor :: Array P.ForClause -> P.Surface -> CExpr
desugarFor clauses body = case Array.uncons clauses of
  Nothing -> EList [ fromExpr body ] Nothing
  Just { head, tail } -> case head of
    P.FGen (P.PVar name) src -> flatMap src (ELambda [ { name, ty: Nothing } ] (desugarFor tail body))
    P.FGen _ _ -> unsafeCrashWith "Core: for-comprehension pattern generator needs gensym (stage 2)"
    P.FFilter cond -> EIf (fromExpr cond) (desugarFor tail body) (EList [] Nothing)
  where
  flatMap src callback = ECall (EDot (EId "List") "flat_map") [ fromExpr src, callback ]

--------------------------------------------------------------------------------
-- from_pat — surface pattern → core pattern
--------------------------------------------------------------------------------

-- | Translate a surface pattern (`Rian.Pratt` output) into the typed core.
-- @rian_sig pub def fromPat(surface val Surface) Pat
fromPat :: P.Pat -> CPat
fromPat P.PWild = PWild
fromPat (P.PVar name) = PVar name
fromPat (P.PLitInt n) = PLit (LInt n)
fromPat (P.PLitStr s) = PLit (LStr s)
fromPat (P.PCharLit cp) = PChar cp
fromPat (P.PAtom name) = PAtom name
fromPat (P.PTuple ps) = PTuple (map fromPat ps)
fromPat (P.PCtor ctor args) = PCtor ctor (map fromPat args)
fromPat (P.PListP ps tail) = PList (map fromPat ps) (map fromPat tail)
fromPat (P.PAs name p) = PAs name (fromPat p)
fromPat (P.PTyped name tname) = PTyped name tname
fromPat (P.PPin e) = PPin e
fromPat (P.PStruct name fields) = PStruct name (map (\(Tuple f p) -> Tuple f (fromPat p)) fields)
fromPat (P.PMap pairs) = PMap (map fromMapPatPair pairs)

fromMapPatPair :: P.MapPatPair -> CMapPatPair
fromMapPatPair (P.MPAtom k p) = CMPAtom k (fromPat p)
fromMapPatPair (P.MPKey k p) = CMPKey (fromExpr k) (fromPat p)

--------------------------------------------------------------------------------
-- coreSexpr — the canonical parity oracle (matches CoreCanon in gen_fixtures.exs)
--------------------------------------------------------------------------------

-- | Parse a source string, lower it to Core, and render the canonical s-expression — the
-- | `cor` parity stream entry (`lexer → Pratt → Core → coreSexpr`).
fromSource :: String -> String
fromSource = coreSexpr <<< fromExpr <<< P.parse

coreSexpr :: CExpr -> String
coreSexpr (ENum n) = n
coreSexpr (EStr s) = "\"" <> s <> "\""
coreSexpr (EChar c) = "?" <> show c
coreSexpr (EId x) = x
coreSexpr (EAtom a) = ":" <> a
coreSexpr (EUnary op x) = "(" <> op <> " " <> coreSexpr x <> ")"
coreSexpr (EBin op l r) = "(" <> op <> " " <> coreSexpr l <> " " <> coreSexpr r <> ")"
coreSexpr (ECall f args) = "(call " <> coreSexpr f <> foldMap (\a -> " " <> coreSexpr a) args <> ")"
coreSexpr (EDot h n) = "(. " <> coreSexpr h <> " " <> n <> ")"
coreSexpr (EIf c t e) = "(if " <> coreSexpr c <> " " <> coreSexpr t <> " " <> coreSexpr e <> ")"
coreSexpr (ECase s arms) =
  "(case " <> coreSexpr s <> foldMap (\a -> " (" <> corePatSexpr a.pat <> " -> " <> coreSexpr a.body <> ")") arms <> ")"
coreSexpr (EWith clauses body els) =
  "(with " <> joinWith " " (map clause clauses) <> " " <> coreSexpr body <> elseArms els <> ")"
  where
  clause c = "(<- " <> corePatSexpr c.pat <> " " <> coreSexpr c.expr <> ")"
  elseArms [] = ""
  elseArms arms = " (else" <> foldMap (\a -> " (" <> corePatSexpr a.pat <> " -> " <> coreSexpr a.body <> ")") arms <> ")"
coreSexpr (EBlock stmts) = "(block" <> foldMap (\s -> " " <> coreStmt s) stmts <> ")"
coreSexpr (EList elems Nothing) = "[" <> joinWith " " (map coreSexpr elems) <> "]"
coreSexpr (EList elems (Just t)) = "[" <> joinWith " " (map coreSexpr elems) <> " | " <> coreSexpr t <> "]"
coreSexpr (EMap pairs) = "%{" <> joinWith " " (map coreMapPair pairs) <> "}"
coreSexpr (EMapUpdate base pairs) =
  "%{" <> coreSexpr base <> " | " <> joinWith " " (map coreMapPair pairs) <> "}"
coreSexpr (ETuple es) = "{" <> joinWith " " (map coreSexpr es) <> "}"
coreSexpr (ELambda ps b) = "(lambda (" <> joinWith " " (map _.name ps) <> ") " <> coreSexpr b <> ")"
coreSexpr (ECapture b) = "(& " <> coreSexpr b <> ")"
coreSexpr (ECaptureNamed p a) = "(&/ " <> coreSexpr p <> " " <> show a <> ")"
coreSexpr (ECapArg n) = "&" <> show n
coreSexpr (ELabel n e) = n <> ": " <> coreSexpr e

coreMapPair :: CMapPair -> String
coreMapPair (CMAtom k v) = k <> ": " <> coreSexpr v
coreMapPair (CMKey k v) = coreSexpr k <> " => " <> coreSexpr v

coreStmt :: CStmt -> String
coreStmt (CBind n e) = "(:= " <> n <> " " <> coreSexpr e <> ")"
coreStmt (CTypedBind n t e) = "(:= " <> n <> " " <> t <> " " <> coreSexpr e <> ")"
coreStmt (CExprStmt e) = coreSexpr e

corePatSexpr :: CPat -> String
corePatSexpr PWild = "_"
corePatSexpr (PVar x) = x
corePatSexpr (PLit (LInt v)) = show v
corePatSexpr (PLit (LStr v)) = "\"" <> v <> "\""
corePatSexpr (PChar cp) = "?" <> show cp
corePatSexpr (PAtom a) = ":" <> a
corePatSexpr (PTuple ps) = "{" <> joinWith ", " (map corePatSexpr ps) <> "}"
corePatSexpr (PList ps Nothing) = "[" <> joinWith ", " (map corePatSexpr ps) <> "]"
corePatSexpr (PList ps (Just t)) = "[" <> joinWith ", " (map corePatSexpr ps) <> " | " <> corePatSexpr t <> "]"
corePatSexpr (PCtor n []) = n
corePatSexpr (PCtor n args) = n <> "(" <> joinWith ", " (map corePatSexpr args) <> ")"
corePatSexpr (PAs n p) = "(@ " <> n <> " " <> corePatSexpr p <> ")"
corePatSexpr (PPin e) = "(^ " <> P.sexpr e <> ")"
corePatSexpr (PStruct n fields) =
  n <> "(" <> joinWith ", " (map (\(Tuple k p) -> k <> ": " <> corePatSexpr p) fields) <> ")"
corePatSexpr (PMap fields) = "%{" <> joinWith ", " (map coreMapPatPair fields) <> "}"
corePatSexpr (PTyped _ _) = unsafeCrashWith "Core: sexpr of a type-pattern (no reference clause)"

coreMapPatPair :: CMapPatPair -> String
coreMapPatPair (CMPAtom k p) = k <> ": " <> corePatSexpr p
coreMapPatPair (CMPKey k p) = coreSexpr k <> " => " <> corePatSexpr p
