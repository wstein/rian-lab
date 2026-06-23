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

import Data.Array (all, elem, filter, foldl, mapWithIndex, uncons)
import Data.Enum (fromEnum)
import Data.Foldable (foldMap)
import Data.Int (hexadecimal, toStringAs) as Int
import Data.Maybe (Maybe(..), isNothing)
import Data.Monoid (power)
import Data.String (Pattern(..), contains, length, stripPrefix) as Str
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (toCharArray) as CU
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Func, Prog, bodySurface)
import Rian.Opaque (erase)
import Rian.Pratt (Pat, parse) as P
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

-- ── clause dispatch (inc 2: the multi-clause `if`-chain) ───────────────────────
-- The clause lines of a function, top-to-bottom, plus whether the set is **closed** (a clause
-- matched unconditionally, so the trailing `throw` is dropped). Each clause becomes an `if
-- (<structural tests>) { <binds> <return> }`; an unconditional clause (no tests, no guard)
-- closes the function; a guard-only clause rides a scoped `run { … }`. Mirrors `clause_lines`.
clauseLines :: Array Clause -> Tuple String Boolean
clauseLines clauses = case uncons clauses of
  Nothing -> Tuple "" false
  Just { head: c, tail: rest } ->
    let
      Tuple tests binds = clauseMatch c.pats
      line = bindStr binds <> guardedReturn c.body c.guard
    in
      case c.guard of
        Nothing -> closedOrCond tests line rest
        Just _ -> runOrCond tests line rest

-- no guard: empty tests → unconditional (closes the function); else a conditional `if`.
closedOrCond :: Array String -> String -> Array Clause -> Tuple String Boolean
closedOrCond [] line _ = Tuple ("  " <> line <> "\n") true
closedOrCond tests line rest = prependIf tests line rest

-- a guard with no structural tests carries its condition in the `if` `guardedReturn` emits;
-- wrap it in a scoped `run { … }` (an empty `if () { … }` is not valid Kotlin) so a matched
-- guard returns non-locally from the function. With tests, it is a plain conditional `if`.
runOrCond :: Array String -> String -> Array Clause -> Tuple String Boolean
runOrCond [] line rest = prepend ("  run { " <> line <> " }\n") (clauseLines rest)
runOrCond tests line rest = prependIf tests line rest

prependIf :: Array String -> String -> Array Clause -> Tuple String Boolean
prependIf tests line rest =
  prepend ("  if (" <> joinWith " && " tests <> ") { " <> line <> " }\n") (clauseLines rest)

prepend :: String -> Tuple String Boolean -> Tuple String Boolean
prepend s (Tuple lines closed) = Tuple (s <> lines) closed

-- match each clause-head pattern against its positional `a<i>` → (tests, binds), concatenated.
clauseMatch :: Array P.Pat -> Tuple (Array String) (Array (Tuple String String))
clauseMatch pats =
  let
    parts = mapWithIndex (\i p -> patMatch (fromPat p) ("a" <> show i)) pats
  in
    Tuple (parts >>= fst) (parts >>= snd)

-- a single pattern against the Kotlin access path `acc` → (tests, binds). Inc 2: a literal
-- tests (`acc == lit`), a variable binds it, a wildcard does nothing. (Sum / list / char /
-- symbol / type / as / pin patterns are later increments — they raise a stage crash.)
patMatch :: CPat -> String -> Tuple (Array String) (Array (Tuple String String))
patMatch PWild _ = Tuple [] []
patMatch (PVar n) acc = Tuple [] [ Tuple n acc ]
patMatch (PLit v) acc = Tuple [ acc <> " == " <> litKt v ] []
patMatch _ _ = unsafeCrashWith "jvm: stage — unported clause pattern (inc 2: literals / vars / wildcards)"

litKt :: LitVal -> String
litKt (LInt n) = show n <> "L"
litKt (LStr s) = ktStr s

bindStr :: Array (Tuple String String) -> String
bindStr binds = joinWith "" (map (\(Tuple n a) -> "val " <> n <> " = " <> a <> "; ") binds)

-- a clause's value: `return <body>` (no guard) or `if (<guard>) { return <body> }`. The guard
-- string is parsed + normalized then lowered like any expression.
guardedReturn :: Maybe Body -> Maybe String -> String
guardedReturn body Nothing = "return " <> clauseValue (bodyExprOf body)
guardedReturn body (Just g) =
  "if (" <> exprKt (fromExpr (normalize (P.parse g))) <> ") { return " <> clauseValue (bodyExprOf body) <> " }"

bodyExprOf :: Maybe Body -> CExpr
bodyExprOf (Just b) = fromExpr (normalize (bodySurface b))
bodyExprOf Nothing = unsafeCrashWith "jvm: clause has no body"

-- a `:=` body is parsed to an `EBlock`; inc 1/2 handle the single-expression block (a
-- multi-statement block — `:=` binds before the value — is a later increment).
clauseValue :: CExpr -> String
clauseValue (EBlock [ CExprStmt e ]) = exprKt e
clauseValue (EBlock _) = unsafeCrashWith "jvm: stage — multi-statement body block (inc 2)"
clauseValue e = exprKt e

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
