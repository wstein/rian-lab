-- | Kotlin/JVM source emitter (ADR-0049 Tier 2) — the PureScript port of `Rian.JVM`
-- | (lib/rian/jvm.ex), ADR-0084. A direct Kotlin source emitter on the typed Core IR
-- | (ADR-0050), consuming `Rian.Core.fromExpr`/`fromPat` (never the surface tuples). The
-- | fourth backend on the same Core, after `Rian.JS` and `Rian.Lower.Rust`.
-- |
-- | Kotlin has no native multi-clause functions, so a `def` lowers through one dispatcher:
-- | `[private ]fun name(a0: T, …): Ret { <clause lines> }`. Types come from `ktType`
-- | (`Int64`/`Int53` → `Long`, `Float64` → `Double`, `Bool` → `Boolean`, `Char` → `Long`
-- | codepoint, `Symbol` → `String`, `Vec(T)` → `List<T>`); an integer literal carries the
-- | `L` suffix, and `Int` (arbitrary precision, ADR-0064) is rejected — a `Long` would wrap.
-- |
-- | **Staged port.** Increment 1: single-clause portable core — primitive `val` params, the
-- | precedence-aware operator algebra (`+`/`-`/`*`/`div`/`rem`/float-`/`, comparisons,
-- | `and`/`or`, `in`, unary `-`/`not`), `if`-expressions, and local calls (recursion). Still
-- | later: the multi-clause dispatcher (`if`-chain + smart-casts), sums + `case`, strings,
-- | lists, structs, generics, lambdas, and protocols. An unported node raises a clear "stage"
-- | crash, kept out of the `jvm` parity corpus (oracle = `Rian.JVM.compile`).
module Rian.JVM
  ( compile
  ) where

import Prelude

import Data.Array (all, elem, filter, foldl, mapWithIndex)
import Data.Enum (fromEnum)
import Data.Foldable (foldMap)
import Data.Int (hexadecimal, toStringAs) as Int
import Data.Maybe (Maybe(..), isNothing)
import Data.Monoid (power)
import Data.String (Pattern(..), contains, length, stripPrefix) as Str
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (toCharArray) as CU
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CExpr(..), CPat(..), CStmt(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Clause, Func, Prog, bodySurface)
import Rian.Opaque (erase)
import Rian.Prim (normalize)

-- | Compile `src`'s functions to a single Kotlin module (a string). Mirrors `Rian.JVM.compile`:
-- | run the type gate, erase opaque types, drop protocol dispatchers (no Kotlin shape yet),
-- | then emit each function; the units join `\n\n`.
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
          joinWith "\n\n" (map functionKt funcs)

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> foldl (\acc m -> acc <> m.funcs) [] prog.mods

-- a function → `[private ]fun name(a0: T, …): Ret {\n <clause lines>\n}`. A non-total clause set
-- closes with a `throw` (no clause matched); inc 1's single var-clause is always total.
functionKt :: Func -> String
functionKt f =
  let
    sigParams = joinWith ", " (mapWithIndex (\i p -> "a" <> show i <> ": " <> ktTypeM p.ty) f.params)
    Tuple lines closed = clauseLines f.clauses
    tail =
      if closed then ""
      else "  throw RuntimeException(" <> ktStr (f.name <> ": no clause matched") <> ")\n"
    vis = if f.pub then "" else "private "
  in
    vis <> "fun " <> f.name <> "(" <> sigParams <> "): " <> ktTypeM f.ret <> " {\n" <> lines <> tail <> "}"

-- ── clause dispatch (inc 1: the single total var-clause) ───────────────────────
-- A single clause whose parameters are all plain variables and has no guard is total:
-- bind each var to its positional `a<i>` and `return` the body. (The multi-clause `if`-chain
-- dispatcher with structural tests is increment 2.)
clauseLines :: Array Clause -> Tuple String Boolean
clauseLines clauses = case clauses of
  [ c ]
    | isNothing c.guard && all (isPVar <<< fromPat) c.pats ->
        let
          names = map (pvarName <<< fromPat) c.pats
          binds = joinWith "" (mapWithIndex (\i n -> "val " <> n <> " = a" <> show i <> "; ") names)
        in
          Tuple ("  " <> binds <> "return " <> clauseValue (bodyExpr c) <> "\n") true
  _ -> unsafeCrashWith "jvm: stage — multi-clause / non-var clause patterns (inc 2)"

-- a `:=` body is parsed to an `EBlock`; inc 1 handles the single-expression block (a multi-
-- statement block — `:=` binds before the value — is a later increment).
clauseValue :: CExpr -> String
clauseValue (EBlock [ CExprStmt e ]) = exprKt e
clauseValue (EBlock _) = unsafeCrashWith "jvm: stage — multi-statement body block (inc 2)"
clauseValue e = exprKt e

bodyExpr :: Clause -> CExpr
bodyExpr c = case c.body of
  Just b -> fromExpr (normalize (bodySurface b))
  Nothing -> unsafeCrashWith "jvm: clause has no body"

isPVar :: CPat -> Boolean
isPVar (PVar _) = true
isPVar _ = false

pvarName :: CPat -> String
pvarName (PVar n) = n
pvarName _ = unsafeCrashWith "jvm: expected a variable pattern"

-- ── expressions ────────────────────────────────────────────────────────────────
exprKt :: CExpr -> String
exprKt (ENum n) = numKt n
exprKt (EChar cp) = show cp <> "L"
exprKt (EStr s) = ktStr s
-- a `Symbol` (`:foo`) lowers to its interned name as a Kotlin `String` (ADR-0041).
exprKt (EAtom a) = ktStr a
exprKt (EId "true") = "true"
exprKt (EId "false") = "false"
exprKt (EId x) = x
exprKt (EUnary "-" x) = "-" <> exprKt x
exprKt (EUnary "not" x) = "!" <> exprKt x
exprKt (EUnary op _) = unsafeCrashWith ("jvm: unary operator `" <> op <> "`")
exprKt (EBin op l r) = "(" <> exprKt l <> " " <> ktOp op <> " " <> exprKt r <> ")"
exprKt (ECall (EId f) args) = f <> "(" <> joinWith ", " (map exprKt args) <> ")"
-- Kotlin `if` is an expression.
exprKt (EIf c t e) = "if (" <> exprKt c <> ") " <> branchKt t <> " else " <> branchKt e
exprKt _ = unsafeCrashWith "jvm: stage — unported expression (inc 1)"

-- a branch value: a single-expression block unwraps to that expression.
branchKt :: CExpr -> String
branchKt (EBlock [ CExprStmt e ]) = exprKt e
branchKt e = exprKt e

-- an integer literal carries the `L` (Long) suffix; a float literal is emitted verbatim.
numKt :: String -> String
numKt n =
  if Str.contains (Str.Pattern ".") n || Str.contains (Str.Pattern "e") n || Str.contains (Str.Pattern "E") n then n
  else n <> "L"

ktOp :: String -> String
ktOp "==" = "=="
ktOp "!=" = "!="
ktOp "and" = "&&"
ktOp "or" = "||"
ktOp "<>" = "+"
ktOp "div" = "/"
ktOp "rem" = "%"
ktOp "in" = "in"
ktOp "/" = "/"
ktOp op = if elem op [ "+", "-", "*", "<", "<=", ">", ">=" ] then op else unsafeCrashWith ("jvm: operator `" <> op <> "`")

-- ── types ──────────────────────────────────────────────────────────────────────
ktTypeM :: Maybe String -> String
ktTypeM Nothing = unsafeCrashWith "jvm: missing type annotation"
ktTypeM (Just t) = ktType t

ktType :: String -> String
ktType "Int" = unsafeCrashWith "jvm: `Int` (arbitrary precision, ADR-0064) needs BigInteger; use `Int64`"
ktType "Int64" = "Long"
ktType "Int53" = "Long"
ktType "Bool" = "Boolean"
ktType "String" = "String"
ktType "Symbol" = "String"
ktType "Char" = "Long"
ktType t
  | widthInt t = "Long"
  | widthFloat t = "Double"
  | otherwise = unsafeCrashWith ("jvm: stage — type `" <> t <> "` (inc 1)")

-- `Int8`…`Int128`/`UInt8`… → `Long`; `Float32`/`Float64` → `Double`. (`Int`/`Float` alone have
-- no digits and never reach here — `Int` is rejected above; a bare `Float` is not a Rian type.)
widthInt :: String -> Boolean
widthInt t = case Str.stripPrefix (Str.Pattern "UInt") t of
  Just rest -> allDigits rest
  Nothing -> case Str.stripPrefix (Str.Pattern "Int") t of
    Just rest -> allDigits rest
    Nothing -> false

widthFloat :: String -> Boolean
widthFloat t = case Str.stripPrefix (Str.Pattern "Float") t of
  Just rest -> allDigits rest
  Nothing -> false

allDigits :: String -> Boolean
allDigits s = s /= "" && all (\c -> c >= '0' && c <= '9') (CU.toCharArray s)

-- ── string literals (mirrors `kt_str`) ─────────────────────────────────────────
ktStr :: String -> String
ktStr s = "\"" <> foldMap ktStrCp (CP.toCodePointArray s) <> "\""

ktStrCp :: CP.CodePoint -> String
ktStrCp cp = case fromEnum cp of
  92 -> "\\\\"
  34 -> "\\\""
  36 -> "\\$"
  10 -> "\\n"
  13 -> "\\r"
  9 -> "\\t"
  n
    | n < 0x20 || n == 0x7F -> "\\u" <> ktHex4 n
    | otherwise -> CP.singleton cp

ktHex4 :: Int -> String
ktHex4 n = let h = Int.toStringAs Int.hexadecimal n in power "0" (4 - Str.length h) <> h
