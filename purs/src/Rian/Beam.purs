-- | Erlang **abstract-forms** BEAM backend (ADR-0031 / ADR-0026) — the PureScript port of
-- | `Rian.Beam` (lib/rian/beam.ex), ADR-0084 **Phase 8** (execution / self-host). Rather than emit
-- | source text, this lowers a checked program directly to the Erlang **abstract format** and runs
-- | it through `compile:forms/2` → `code:load_binary/3` → `Mod:main()` — real `.beam` bytecode, no
-- | Elixir-compiler dependency. The bulk (the forms construction) is pure PureScript over an opaque
-- | `ETerm`; the Erlang FFI tail (the term constructors + compile/load/run) lives in `Beam.erl`.
-- |
-- | **Staged port.** Inc 1: the foundation — the `ETerm` term-builders, module assembly
-- | (`-module`/`-export` + function forms), and the portable expression/pattern core (integer/float/
-- | char/atom/bool literals, the operator algebra, variables, `:=` binds, local calls, `if`). Inc 2:
-- | **multi-clause dispatch** (a multi-clause `def` → one Erlang function, one clause per group
-- | member — Erlang dispatches natively), **`when` guards** (function-clause + `case`-arm → the
-- | Erlang guard sequence `[[G]]`), and **`case`** expressions. Verified by EXECUTION: `runMain`
-- | compiles + loads + runs `main/0` and stringifies the result, parity-gated (the `beam` stream)
-- | against the Elixir reference running the same program. **Deferred (later increments):** the
-- | type-directed lowering (the annotated/range-expanded core — `Show`/overflow/value-union
-- | discrimination), sum/struct/list/map/string lowering + their patterns, `@external`, specs/`type`
-- | attrs, and the whole-program / cross-module + const machinery. An unported node raises a clear crash.
module Rian.Beam
  ( runMain
  ) where

import Prelude

import Data.Array (head, length)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), Replacement(..), contains, drop, replaceAll, stripPrefix, take) as Str
import Data.String.CodeUnits (charAt) as CU
import Data.String.Common (toUpper)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Func, Prog, bodySurface)
import Rian.Pratt (parse) as P
import Rian.Prim (normalize)

-- ── the Erlang-FFI boundary (Beam.erl) ───────────────────────────────────────
foreign import data ETerm :: Type
foreign import mkAtomTerm :: String -> ETerm -- a raw atom
foreign import mkIntStr :: String -> ETerm -- a raw integer, from a Rian numeric string
foreign import mkIntI :: Int -> ETerm -- a raw integer, from a PureScript Int
foreign import mkFloatStr :: String -> ETerm -- a raw float
foreign import mkBinary :: String -> ETerm -- a raw binary (a Rian String literal)
foreign import mkTuple :: Array ETerm -> ETerm
foreign import mkList :: Array ETerm -> ETerm
-- compile the forms list → load → run `Mod:main()` → the `~p`-rendered result (or a diagnostic).
foreign import runMainImpl :: ETerm -> String -> String

-- | Compile `src` to BEAM abstract forms, load the module, run its `main/0`, and return the
-- | stringified result (or a `Rian.Check:`/`compile_error:` diagnostic). The execution-parity entry.
-- @rian_sig pub def runMain(src val String) String
runMain :: String -> String
runMain src =
  case checkProgram prog of
    Just msg -> "Rian.Check: " <> msg
    Nothing -> runMainImpl (moduleForms "rian_main" prog) "rian_main"
  where
  prog = runProgramTail (assemble (parseToProg src))

-- the functions to compile: a single `mod`'s, else the top-level ones (mirrors `funcs_of`).
funcsOf :: Prog -> Array Func
funcsOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.funcs
    _ -> []
  fs -> fs

-- ── module assembly ──────────────────────────────────────────────────────────
moduleForms :: String -> Prog -> ETerm
moduleForms modName prog =
  let
    funcs = funcsOf prog
    exports = map (\f -> nameArity f.name (funcArity f)) funcs
  in
    mkList ([ attrModule modName, attrExport exports ] <> map functionForm funcs)

funcArity :: Func -> Int
funcArity f = case head f.clauses of
  Just c -> length c.pats
  Nothing -> length f.params

-- a function → `{function, 1, Name, Arity, [Clause]}`.
functionForm :: Func -> ETerm
functionForm f =
  fFunction f.name (funcArity f) (map clauseForm f.clauses)

-- a function clause → `{clause, 1, [PatForm], Guard, [BodyForm]}`. A multi-clause `def` is one
-- Erlang function with one clause per group member (Erlang dispatches natively); a `when` guard
-- lowers to the Erlang guard sequence `[[GuardExpr]]`.
clauseForm :: Clause -> ETerm
clauseForm c =
  fClause (map (patForm <<< fromPat) c.pats) (clauseGuardForm c.guard) (bodyForms (bodyExprOf c.body))

-- a function clause's `when` guard (a source string) → the Erlang guard sequence; `Nothing` → `[]`.
clauseGuardForm :: Maybe String -> ETerm
clauseGuardForm Nothing = noGuard
clauseGuardForm (Just g) = mkList [ mkList [ exprForm (fromExpr (normalize (P.parse g))) ] ]

-- a `case`-arm guard (already core) → the Erlang guard sequence `[[GuardExpr]]`; `Nothing` → `[]`.
armGuardForm :: Maybe CExpr -> ETerm
armGuardForm Nothing = noGuard
armGuardForm (Just g) = mkList [ mkList [ exprForm g ] ]

-- a `:=` body parses to an `EBlock`; lower each statement to a body form (a bare expression is a
-- one-statement body).
bodyForms :: CExpr -> Array ETerm
bodyForms (EBlock stmts) = map stmtForm stmts
bodyForms e = [ exprForm e ]

stmtForm :: CStmt -> ETerm
stmtForm (CExprStmt e) = exprForm e
-- a `:=` bind → an Erlang `{match, 1, {var,…}, Rhs}` (the declared type is erased, ADR-0034 §1).
stmtForm (CBind n e) = mkTuple [ mkAtomTerm "match", ln, fVar (varAtom n), exprForm e ]
stmtForm (CTypedBind n _ e) = mkTuple [ mkAtomTerm "match", ln, fVar (varAtom n), exprForm e ]

-- ── expressions → abstract forms ─────────────────────────────────────────────
exprForm :: CExpr -> ETerm
exprForm (ENum n) = numForm n
exprForm (EChar cp) = fIntegerI cp
exprForm (EId "true") = fAtom "true"
exprForm (EId "false") = fAtom "false"
-- a lowercase identifier is a variable; a PascalCase one is a nullary constructor (deferred).
exprForm (EId x) = if startsUpper x then unsafeCrashWith "abstract-forms: a constructor reference (Phase 8 inc 1)" else fVar (varAtom x)
exprForm (EAtom a) = fAtom a
exprForm (EUnary "-" x) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm "-", exprForm x ]
exprForm (EUnary "not" x) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm "not", exprForm x ]
exprForm (EBin op l r) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm (erlOp op), exprForm l, exprForm r ]
-- a local call `f(args)` → `{call, 1, {atom,1,f}, [args]}` (inc 1: a bare local call — no var
-- application, imports, or cross-module resolution yet).
exprForm (ECall (EId f) args) = fCall (fAtom f) (map exprForm args)
-- `if c do t else e end` → an Erlang `case c of true -> t; false -> e end`.
exprForm (EIf c t e) =
  mkTuple
    [ mkAtomTerm "case"
    , ln
    , exprForm c
    , mkList [ fClause [ fAtom "true" ] noGuard (bodyForms t), fClause [ fAtom "false" ] noGuard (bodyForms e) ]
    ]
-- `case scrut do pat [when g] -> body … end` → an Erlang `{case, 1, Scrut, [Clause]}`.
exprForm (ECase scrut arms) =
  mkTuple [ mkAtomTerm "case", ln, exprForm scrut, mkList (map caseArmForm arms) ]
exprForm _ = unsafeCrashWith "abstract-forms: unported expression (Phase 8 inc 1)"

caseArmForm :: CArm -> ETerm
caseArmForm arm = fClause [ patForm arm.pat ] (armGuardForm arm.guard) (bodyForms arm.body)

-- ── patterns → abstract forms (inc 1: wildcards / vars / literals / atoms) ──
patForm :: CPat -> ETerm
patForm PWild = fVar "_"
patForm (PVar x) = fVar (varAtom x)
patForm (PLit (LInt n)) = fIntegerI n
patForm (PLit (LStr _)) = unsafeCrashWith "abstract-forms: a string pattern (Phase 8 inc 1)"
patForm (PAtom a) = fAtom a
patForm _ = unsafeCrashWith "abstract-forms: unported clause pattern (Phase 8 inc 1)"

-- ── abstract-format node builders ────────────────────────────────────────────
ln :: ETerm
ln = mkIntI 1

fInteger :: String -> ETerm
fInteger n = mkTuple [ mkAtomTerm "integer", ln, mkIntStr n ]

fIntegerI :: Int -> ETerm
fIntegerI n = mkTuple [ mkAtomTerm "integer", ln, mkIntI n ]

fFloat :: String -> ETerm
fFloat n = mkTuple [ mkAtomTerm "float", ln, mkFloatStr n ]

fAtom :: String -> ETerm
fAtom a = mkTuple [ mkAtomTerm "atom", ln, mkAtomTerm a ]

fVar :: String -> ETerm
fVar v = mkTuple [ mkAtomTerm "var", ln, mkAtomTerm v ]

fCall :: ETerm -> Array ETerm -> ETerm
fCall target args = mkTuple [ mkAtomTerm "call", ln, target, mkList args ]

fFunction :: String -> Int -> Array ETerm -> ETerm
fFunction name arity clauses =
  mkTuple [ mkAtomTerm "function", ln, mkAtomTerm name, mkIntI arity, mkList clauses ]

fClause :: Array ETerm -> ETerm -> Array ETerm -> ETerm
fClause pats guard body = mkTuple [ mkAtomTerm "clause", ln, mkList pats, guard, mkList body ]

-- the empty Erlang guard sequence (`[]` — an unguarded clause).
noGuard :: ETerm
noGuard = mkList []

attrModule :: String -> ETerm
attrModule m = mkTuple [ mkAtomTerm "attribute", ln, mkAtomTerm "module", mkAtomTerm m ]

attrExport :: Array ETerm -> ETerm
attrExport es = mkTuple [ mkAtomTerm "attribute", ln, mkAtomTerm "export", mkList es ]

-- a `{Name, Arity}` raw tuple (an export entry).
nameArity :: String -> Int -> ETerm
nameArity n a = mkTuple [ mkAtomTerm n, mkIntI a ]

-- ── leaf helpers ─────────────────────────────────────────────────────────────
-- a Rian numeric string → an integer or float abstract node (a `.`/`e` ⇒ float; `_` stripped).
numForm :: String -> ETerm
numForm n0 =
  let
    n = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n0
  in
    if Str.contains (Str.Pattern ".") n || Str.contains (Str.Pattern "e") n || Str.contains (Str.Pattern "E") n then fFloat n
    else fInteger n

-- a Rian operator → its Erlang name (the abstract `op` atom). Mirrors `erl_op`.
erlOp :: String -> String
erlOp "==" = "=="
erlOp "!=" = "/="
erlOp "<=" = "=<"
erlOp ">=" = ">="
erlOp "<" = "<"
erlOp ">" = ">"
erlOp "and" = "andalso"
erlOp "or" = "orelse"
erlOp "+" = "+"
erlOp "-" = "-"
erlOp "*" = "*"
erlOp "/" = "/"
erlOp "div" = "div"
erlOp "rem" = "rem"
erlOp op = unsafeCrashWith ("abstract-forms: operator `" <> op <> "`")

-- a Rian variable name → its Erlang variable atom: a `_`-prefixed name is kept verbatim, else the
-- first letter is upper-cased (Erlang variables are capitalized). Mirrors `var_atom`.
varAtom :: String -> String
varAtom x = case Str.stripPrefix (Str.Pattern "_") x of
  Just _ -> x
  Nothing -> toUpper (Str.take 1 x) <> Str.drop 1 x

-- the first character is an upper-case ASCII letter (a constructor / nominal head).
startsUpper :: String -> Boolean
startsUpper x = case CU.charAt 0 x of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

-- a clause's body `Body` → its `CExpr` (re-parse + normalize, like the other emitters).
bodyExprOf :: Maybe Body -> CExpr
bodyExprOf (Just b) = fromExpr (normalize (bodySurface b))
bodyExprOf Nothing = unsafeCrashWith "abstract-forms: clause has no body"
