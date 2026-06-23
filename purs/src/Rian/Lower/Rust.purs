-- | Rust source emitter (ADR-0049 / ADR-0061) — the PureScript port of `Rian.Lower`'s
-- | `to_rust` half (lib/rian/lower.ex), ADR-0084 Phase 5. A direct Rust source emitter on
-- | the typed Core IR (ADR-0050), consuming `Rian.Core.fromExpr`/`fromPat`. **Rust is the
-- | genuine shipping text target of `Rian.Lower`** (the Elixir-text half is not ported — see
-- | `Rian.Roundtrip`'s subsumption note; `Rian.Beam` is the BEAM path).
-- |
-- | A Rian function lowers to `fn name(params) -> ret { match scrut { pat => arm, … } }`,
-- | mirroring the clause dispatcher (clauses-guards §5.2): one param matches it directly, N
-- | match the argument tuple. Parameter types come from the capability lowering
-- | (`Rian.Capability.rustParam`: `val`/`iso`/`ref`/`tag` → `&[T]`/`Vec<T>`/`&T`); the return
-- | from `Rian.Capability.owned` (`Result(ok, err)` → `Result<owned, owned>`).
-- |
-- | **Staged port.** This increment covers the **single-clause portable core**: primitive
-- | `val` params, the arithmetic/comparison/boolean operators (precedence-aware, via the
-- | `{string, prec}` algebra `p`/`emit`), `div`/`rem`/float-`/`, unary `-`/`not`, `if`, and
-- | local calls (recursion). Sum/struct construction + patterns, lists, maps, strings/chars,
-- | capabilities beyond `val`-primitives, generics/monomorphization, and protocol traits are
-- | later increments — an unported node raises a clear "stage" crash, excluded from the
-- | `rust` parity corpus (oracle = `Rian.Decl.compile`'s `:rust`).
module Rian.Lower.Rust
  ( compile
  ) where

import Prelude

import Data.Array (filter, foldl, length)
import Data.Maybe (Maybe(..), fromMaybe, isNothing)
import Data.String (Pattern(..), stripPrefix, stripSuffix)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Capability (owned, rustParam) as Cap
import Rian.Check (checkProgram)
import Rian.Core (CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Clause, Func, Param, Prog, bodySurface)
import Rian.Opaque (erase)
import Rian.Pratt (Pat) as P
import Rian.Prim (normalize)
import Rian.TypeStr (splitTopCommas) as TS

-- | Compile `src`'s functions to a single Rust module (a string). Mirrors the `:rust`
-- | half of `Rian.Decl.compile`: each non-dispatch function is lowered and joined `\n\n`
-- | (a protocol dispatcher has no Rust shape — Rust uses traits — so it is dropped).
-- @rian_sig pub def compile(src val String) String
compile :: String -> String
compile src =
  let
    prog0 = runProgramTail (assemble (parseToProg src))
  in
    case checkProgram prog0 of
      Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
      Nothing ->
        let
          prog = erase prog0
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
        in
          joinWith "\n\n" (map rustFn funcs)

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> foldl (\acc m -> acc <> m.funcs) [] prog.mods

-- ── function / clause dispatch ────────────────────────────────────────────────

rustFn :: Func -> String
rustFn f =
  let
    paramDecls = joinWith ", " (map paramDecl f.params)
    ret = rustRet (fromMaybe "" f.ret)
    scrut = rustScrut f.params
    arms = joinWith "\n" (map (clauseArm f) f.clauses)
  in
    "fn " <> f.name <> "(" <> paramDecls <> ") -> " <> ret <> " {\n"
      <> "    match "
      <> scrut
      <> " {\n"
      <> arms
      <> "\n    }\n}"

-- a parameter's Rust declaration: `name: <capability-lowered type>` (ADR-0055).
paramDecl :: Param -> String
paramDecl pm = pm.name <> ": " <> Cap.rustParam pm.cap (fromMaybe "" pm.ty)

-- the match scrutinee: one param matches directly, N>1 match the argument tuple.
rustScrut :: Array Param -> String
rustScrut params = case map _.name params of
  [ one ] -> one
  many -> "(" <> joinWith ", " many <> ")"

-- one `pat => body,` arm. The clause-head patterns form the match pattern (one, or a tuple
-- of N); the body lowers through the precedence-aware emitter, then is return-coerced.
clauseArm :: Func -> Clause -> String
clauseArm f c =
  let
    pat = tupleOrOne (map corePatRs c.pats)
    cbody = case c.body of
      Just b -> fromExpr (normalize (bodySurface b))
      Nothing -> unsafeCrashWith ("rust: clause of " <> f.name <> " has no body")
    arm = coerceRet (fromMaybe "" f.ret) (rustArmBody cbody (fst (emit cbody)))
  in
    "        " <> pat <> " => " <> arm <> ","

-- a multi-statement block body is braced as a match-arm value (`{ … }`); a single
-- expression (or single-stmt block) is the value directly. Mirrors `rust_arm_body`.
rustArmBody :: CExpr -> String -> String
rustArmBody (EBlock stmts) s | length stmts >= 2 = "{ " <> s <> " }"
rustArmBody _ s = s

tupleOrOne :: Array String -> String
tupleOrOne [ one ] = one
tupleOrOne many = "(" <> joinWith ", " many <> ")"

corePatRs :: P.Pat -> String
corePatRs pat = patRs (fromPat pat)

patRs :: CPat -> String
patRs PWild = "_"
patRs (PVar x) = x
patRs (PLit (LInt v)) = show v
patRs _ = unsafeCrashWith "rust: pattern not yet ported (stage)"

-- ── return-type lowering ───────────────────────────────────────────────────────

rustRet :: String -> String
rustRet ret = case resultParts ret of
  Plain t -> Cap.owned t
  Res ok err -> "Result<" <> Cap.owned ok <> ", " <> Cap.owned err <> ">"

data RetParts = Plain String | Res String String

-- `Result(ok, err)` → `Res ok err`; any other type is `Plain`.
resultParts :: String -> RetParts
resultParts ret =
  case stripPrefix (Pattern "Result(") ret >>= stripSuffix (Pattern ")") of
    Just inner -> case TS.splitTopCommas inner of
      [ ok, err ] -> Res ok err
      _ -> Plain ret
    Nothing -> Plain ret

-- a `String`/`Symbol` body yields a `&str`, so an owned return `.to_string()`s it.
coerceRet :: String -> String -> String
coerceRet ret body = if stringRepr ret then "(" <> body <> ").to_string()" else body

stringRepr :: String -> Boolean
stringRepr "String" = true
stringRepr "Symbol" = true
stringRepr _ = false

-- ── expression emission (precedence-aware `{string, prec}`) ────────────────────

-- parenthesize `node` when its precedence is below the surrounding minimum `ctx`.
p :: Int -> CExpr -> String
p ctx node =
  let Tuple s pr = emit node
  in if pr < ctx then "(" <> s <> ")" else s

emit :: CExpr -> Tuple String Int
emit (ENum n) = Tuple n 12
emit (EId "pi") = Tuple "std::f64::consts::PI" 12
emit (EId x) = Tuple x 12
emit (EUnary "-" x) = Tuple ("-" <> p 11 x) 11
emit (EUnary "not" x) = Tuple ("!" <> p 11 x) 11
emit (EIf c t e) =
  Tuple ("if " <> p 0 c <> " { " <> emitBlock t <> " } else { " <> emitBlock e <> " }") 0
-- integer `div`/`rem` → Rust `/`/`%`; float `/` → an explicit `f64` cast on each side.
emit (EBin "div" l r) = Tuple (p 10 l <> " / " <> p 11 r) 10
emit (EBin "rem" l r) = Tuple (p 10 l <> " % " <> p 11 r) 10
emit (EBin "/" l r) = Tuple ("(" <> p 0 l <> " as f64) / (" <> p 0 r <> " as f64)") 10
emit (EBin op l r) =
  let
    pr = prec op
    Tuple lc rc = case assoc op of
      AL -> Tuple pr (pr + 1)
      AR -> Tuple (pr + 1) pr
      AN -> Tuple (pr + 1) (pr + 1)
  in
    Tuple (p lc l <> " " <> disp op <> " " <> p rc r) pr
emit (ECall f args) = Tuple (p 12 f <> "(" <> joinWith ", " (map (p 0) args) <> ")") 12
emit (EBlock stmts) = Tuple (emitBlock (EBlock stmts)) 0
emit _ = unsafeCrashWith "rust: expression not yet ported (stage)"

-- a block in tail position (an `if` branch): its statements joined, the final an expression.
emitBlock :: CExpr -> String
emitBlock (EBlock []) = "()"
emitBlock (EBlock stmts) = joinWith " " (map stmtRs stmts)
emitBlock e = p 0 e

stmtRs :: CStmt -> String
stmtRs (CExprStmt e) = p 0 e
stmtRs (CBind n e) = "let " <> n <> " = " <> p 0 e <> ";"
stmtRs (CTypedBind n _ e) = "let " <> n <> " = " <> p 0 e <> ";"

-- ── operator precedence (mirrors `Rian.Lower` prec/assoc/disp) ─────────────────

data Assoc = AL | AR | AN

prec :: String -> Int
prec op
  | op == "*" || op == "/" || op == "rem" || op == "div" = 10
  | op == "+" || op == "-" = 9
  | op == "<>" = 8
  | op == "in" = 7
  | op == "|>" = 6
  | op == "<" || op == "<=" || op == ">" || op == ">=" = 5
  | op == "==" || op == "!=" = 4
  | op == "and" = 3
  | op == "or" = 2
  | otherwise = 1 -- `<~`

assoc :: String -> Assoc
assoc op
  | op == "<>" || op == "<~" = AR
  | op == "<" || op == "<=" || op == ">" || op == ">=" || op == "==" || op == "!=" || op == "in" = AN
  | otherwise = AL

-- the Rust spelling of an operator (`and`/`or` → `&&`/`||`; `<~` → `=`); else verbatim.
disp :: String -> String
disp "and" = "&&"
disp "or" = "||"
disp "<~" = "="
disp op = op
