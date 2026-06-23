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

import Data.Array (all, elem, filter, find, foldl, index, mapWithIndex, null, uncons)
import Data.Enum (fromEnum)
import Data.Foldable (foldMap)
import Data.Int (hexadecimal, toStringAs) as Int
import Data.Maybe (Maybe(..), isNothing)
import Data.Monoid (power)
import Data.String (Pattern(..), contains, length, stripPrefix) as Str
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (charAt, toCharArray) as CU
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Func, Prog, Variant, bodySurface)
import Rian.IR (Type) as IR
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
          types = allTypes prog
          meta = buildMeta types
          typeDecls = joinWith "\n\n" (map sumDecl types)
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
          fnDecls = joinWith "\n\n" (map (functionKt meta) funcs)
        in
          joinWith "\n\n" (filter (_ /= "") [ typeDecls, fnDecls ])

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> foldl (\acc m -> acc <> m.funcs) [] prog.mods

allTypes :: Prog -> Array IR.Type
allTypes prog = prog.types <> foldl (\acc m -> acc <> m.types) [] prog.mods

-- ── sum types → sealed interface + data class / object (inc 3) ──────────────────
-- a ctor → its field labels (`Nothing` = anonymous), so a pattern/declaration picks the
-- declared field name (`radius`) or the positional `f<i>` fallback (ADR-0049 §3b).
type Meta = Array (Tuple String (Array (Maybe String)))

buildMeta :: Array IR.Type -> Meta
buildMeta types = types >>= \t -> map (\v -> Tuple v.ctor (map _.label v.fields)) t.variants

-- a sum `type` → `sealed interface Name` + a `data class`/`object` per variant. A single
-- variant whose ctor IS the type name is a newtype-style wrapper — just the variant body.
-- (The single-element check uses an `if` inside a plain `[ v ]` branch, not a guarded array
-- pattern `[ v ] | g` — the latter mis-lowers on the purerl backend.)
sumDecl :: IR.Type -> String
sumDecl t = case t.variants of
  [ v ] -> if v.ctor == t.name then variantBody v else sealedDecl t
  _ -> sealedDecl t

sealedDecl :: IR.Type -> String
sealedDecl t =
  "sealed interface " <> t.name <> "\n"
    <> joinWith "\n" (map (\v -> variantBody v <> " : " <> t.name) t.variants)

-- the data class / object for a variant (without the `: SealedInterface` supertype). A nullary
-- variant is a singleton `object`; an arg-carrying one a `data class` with its field names.
variantBody :: Variant -> String
variantBody v
  | null v.fields = "object " <> v.ctor
  | otherwise =
      "data class " <> v.ctor <> "("
        <> joinWith ", " (mapWithIndex (\i f -> "val " <> fieldName f.label i <> ": " <> ktType f.ty) v.fields)
        <> ")"

-- the Kotlin field name for a variant's i-th field: its declared label, else `f<i>`.
fieldName :: Maybe String -> Int -> String
fieldName (Just l) _ = l
fieldName Nothing i = "f" <> show i

-- the i-th field name of a ctor, resolved through the meta (a labelled field keeps its name).
fieldKey :: Meta -> String -> Int -> String
fieldKey meta ctor i = case find (\(Tuple c _) -> c == ctor) meta of
  Just (Tuple _ labels) -> fieldName (join (index labels i)) i
  Nothing -> "f" <> show i

-- a function → `[private ]fun name(a0: T, …): Ret {\n <clause lines>\n}`. A non-total clause set
-- closes with a `throw` (no clause matched).
functionKt :: Meta -> Func -> String
functionKt meta f =
  let
    sigParams = joinWith ", " (mapWithIndex (\i p -> "a" <> show i <> ": " <> ktTypeM p.ty) f.params)
    Tuple lines closed = clauseLines meta f.clauses
    tail =
      if closed then ""
      else "  throw RuntimeException(" <> ktStr (f.name <> ": no clause matched") <> ")\n"
    vis = if f.pub then "" else "private "
  in
    vis <> "fun " <> f.name <> "(" <> sigParams <> "): " <> ktTypeM f.ret <> " {\n" <> lines <> tail <> "}"

-- ── clause dispatch (inc 2 if-chain + inc 3 sum patterns) ──────────────────────
-- The clause lines of a function, top-to-bottom, plus whether the set is **closed** (a clause
-- matched unconditionally, so the trailing `throw` is dropped). Each clause becomes an `if
-- (<structural tests>) { <binds> <return> }`; an unconditional clause closes the function; a
-- guard-only clause rides a scoped `run { … }`. Mirrors `clause_lines`.
clauseLines :: Meta -> Array Clause -> Tuple String Boolean
clauseLines meta clauses = case uncons clauses of
  Nothing -> Tuple "" false
  Just { head: c, tail: rest } ->
    let
      Tuple tests binds = clauseMatch meta c.pats
      line = bindStr binds <> guardedReturn meta c.body c.guard
    in
      case c.guard of
        Nothing -> closedOrCond meta tests line rest
        Just _ -> runOrCond meta tests line rest

-- no guard: empty tests → unconditional (closes the function); else a conditional `if`.
closedOrCond :: Meta -> Array String -> String -> Array Clause -> Tuple String Boolean
closedOrCond _ [] line _ = Tuple ("  " <> line <> "\n") true
closedOrCond meta tests line rest = prependIf meta tests line rest

-- a guard with no structural tests carries its condition in the `if` `guardedReturn` emits;
-- wrap it in a scoped `run { … }` (an empty `if () { … }` is not valid Kotlin) so a matched
-- guard returns non-locally from the function. With tests, it is a plain conditional `if`.
runOrCond :: Meta -> Array String -> String -> Array Clause -> Tuple String Boolean
runOrCond meta [] line rest = prepend ("  run { " <> line <> " }\n") (clauseLines meta rest)
runOrCond meta tests line rest = prependIf meta tests line rest

prependIf :: Meta -> Array String -> String -> Array Clause -> Tuple String Boolean
prependIf meta tests line rest =
  prepend ("  if (" <> joinWith " && " tests <> ") { " <> line <> " }\n") (clauseLines meta rest)

prepend :: String -> Tuple String Boolean -> Tuple String Boolean
prepend s (Tuple lines closed) = Tuple (s <> lines) closed

-- match each clause-head pattern against its positional `a<i>` → (tests, binds), concatenated.
clauseMatch :: Meta -> Array P.Pat -> Tuple (Array String) (Array (Tuple String String))
clauseMatch meta pats =
  let
    parts = mapWithIndex (\i p -> patMatch meta (fromPat p) ("a" <> show i)) pats
  in
    Tuple (parts >>= fst) (parts >>= snd)

-- a single pattern against the Kotlin access path `acc` → (tests, binds). Inc 2: a literal
-- tests (`acc == lit`), a variable binds it, a wildcard does nothing. Inc 3: a sum ctor pattern
-- smart-casts (`acc is Ctor`) and recurses into its fields (`acc.f0` / `acc.radius`, via the
-- meta). (List / char / symbol / type / as / pin patterns are later increments.)
patMatch :: Meta -> CPat -> String -> Tuple (Array String) (Array (Tuple String String))
patMatch _ PWild _ = Tuple [] []
patMatch _ (PVar n) acc = Tuple [] [ Tuple n acc ]
patMatch _ (PLit v) acc = Tuple [ acc <> " == " <> litKt v ] []
-- a `Symbol`/atom pattern (`:ok`) tests the interned name as a Kotlin `String` (ADR-0041);
-- a `Char` pattern tests the codepoint `Long`.
patMatch _ (PAtom a) acc = Tuple [ acc <> " == " <> ktStr a ] []
patMatch _ (PChar cp) acc = Tuple [ acc <> " == " <> show cp <> "L" ] []
patMatch meta (PCtor ctor args) acc =
  let
    parts = mapWithIndex (\i p -> patMatch meta p (acc <> "." <> fieldKey meta ctor i)) args
  in
    Tuple ([ acc <> " is " <> ctor ] <> (parts >>= fst)) (parts >>= snd)
patMatch _ _ _ = unsafeCrashWith "jvm: stage — unported clause pattern (inc 3: literals / vars / wildcards / sum ctors)"

litKt :: LitVal -> String
litKt (LInt n) = show n <> "L"
litKt (LStr s) = ktStr s

bindStr :: Array (Tuple String String) -> String
bindStr binds = joinWith "" (map (\(Tuple n a) -> "val " <> n <> " = " <> a <> "; ") binds)

-- a clause's value: `return <body>` (no guard) or `if (<guard>) { return <body> }`. The guard
-- string is parsed + normalized then lowered like any expression.
guardedReturn :: Meta -> Maybe Body -> Maybe String -> String
guardedReturn meta body Nothing = "return " <> clauseValue meta (bodyExprOf body)
guardedReturn meta body (Just g) =
  "if (" <> exprKt meta (fromExpr (normalize (P.parse g))) <> ") { return " <> clauseValue meta (bodyExprOf body) <> " }"

bodyExprOf :: Maybe Body -> CExpr
bodyExprOf (Just b) = fromExpr (normalize (bodySurface b))
bodyExprOf Nothing = unsafeCrashWith "jvm: clause has no body"

-- a `:=` body is parsed to an `EBlock`; we handle the single-expression block (a multi-
-- statement block — `:=` binds before the value — is a later increment).
clauseValue :: Meta -> CExpr -> String
clauseValue meta (EBlock [ CExprStmt e ]) = exprKt meta e
clauseValue _ (EBlock _) = unsafeCrashWith "jvm: stage — multi-statement body block (inc 3)"
clauseValue meta e = exprKt meta e

-- ── expressions ────────────────────────────────────────────────────────────────
exprKt :: Meta -> CExpr -> String
exprKt _ (ENum n) = numKt n
exprKt _ (EChar cp) = show cp <> "L"
exprKt _ (EStr s) = ktStr s
-- a `Symbol` (`:foo`) lowers to its interned name as a Kotlin `String` (ADR-0041).
exprKt _ (EAtom a) = ktStr a
-- a reference to a declared `const` → the top-level `val`'s name.
exprKt _ (EConstRef name) = name
exprKt _ (EId "true") = "true"
exprKt _ (EId "false") = "false"
-- a bare PascalCase id is a nullary sum variant — its singleton `object` of the same name.
exprKt _ (EId x) = x
exprKt meta (EUnary "-" x) = "-" <> exprKt meta x
exprKt meta (EUnary "not" x) = "!" <> exprKt meta x
exprKt _ (EUnary op _) = unsafeCrashWith ("jvm: unary operator `" <> op <> "`")
exprKt meta (EBin op l r) = "(" <> exprKt meta l <> " " <> ktOp op <> " " <> exprKt meta r <> ")"
-- a PascalCase call is sum construction `Ctor(args)`; a lowercase one a local call — same shape.
-- ── the `__prim_*` intrinsics (ADR-0047): string / char / int ops over Kotlin (inc 4) ──
exprKt meta (ECall (EId "__prim_panic") [ msg ]) = "throw RuntimeException(" <> exprKt meta msg <> ")"
exprKt meta (ECall (EId "__prim_int_to_string") [ n ]) = "(" <> exprKt meta n <> ").toString()"
exprKt meta (ECall (EId "__prim_to_string") [ x ]) = "(" <> exprKt meta x <> ").toString()"
exprKt meta (ECall (EId "__prim_str_concat_all") args) = "(" <> joinWith " + " (map (exprKt meta) args) <> ")"
exprKt meta (ECall (EId "__prim_str_concat") [ a, b ]) = "(" <> exprKt meta a <> " + " <> exprKt meta b <> ")"
exprKt meta (ECall (EId "__prim_char_to_string") [ c ]) = "String(Character.toChars((" <> exprKt meta c <> ").toInt()))"
exprKt meta (ECall (EId "__prim_str_chars") [ s ]) = "(" <> exprKt meta s <> ").codePoints().toArray().map { it.toLong() }"
exprKt meta (ECall (EId "__prim_str_from_chars") [ cs ]) = "(" <> exprKt meta cs <> ").joinToString(\"\") { String(Character.toChars(it.toInt())) }"
-- a `Char`'s codepoint is already its `Long` value — identity.
exprKt meta (ECall (EId "__prim_char_code") [ c ]) = exprKt meta c
exprKt meta (ECall (EId "__prim_int_to_float") [ n ]) = "(" <> exprKt meta n <> ").toDouble()"
-- a PascalCase call is sum construction `Ctor(args)`; a lowercase one a local call — same shape.
exprKt meta (ECall (EId f) args) = f <> "(" <> joinWith ", " (map (exprKt meta) args) <> ")"
-- Kotlin `if` is an expression.
exprKt meta (EIf c t e) = "if (" <> exprKt meta c <> ") " <> branchKt meta t <> " else " <> branchKt meta e
exprKt meta (ECase scrut arms) = caseKt meta scrut arms
exprKt _ _ = unsafeCrashWith "jvm: stage — unported expression (inc 3)"

-- a `case` → a labelled `run rcase@{ … }`. The scrutinee is named (`val __s = …`) unless it is
-- already a bare id; each arm reuses the dispatcher's test/bind/guard machinery and
-- `return@rcase`es its body; a non-total arm set ends in a throw.
caseKt :: Meta -> CExpr -> Array CArm -> String
caseKt meta scrut arms =
  let
    Tuple decl acc = case scrut of
      EId n -> Tuple [] n
      other -> Tuple [ "val __s = " <> exprKt meta other ] "__s"
    Tuple armLines closed = caseArms meta acc arms []
    tl = if closed then [] else [ "throw RuntimeException(\"case: no clause matched\")" ]
  in
    "run rcase@{\n" <> joinWith "\n" (decl <> armLines <> tl) <> "\n}"

-- emit `case` arms top-to-bottom, mirroring `clause_lines`: a structural test → an `if`, a
-- guard-only arm → a scoped `run { … }`, an unconditional arm closes (drops the rest + throw).
caseArms :: Meta -> String -> Array CArm -> Array String -> Tuple (Array String) Boolean
caseArms meta acc arms out = case uncons arms of
  Nothing -> Tuple out false
  Just { head: a, tail: rest } ->
    let
      Tuple tests binds = patMatch meta a.pat acc
      stmt = bindStr binds <> guardedArm meta (branchKt meta a.body) a.guard
    in
      case Tuple (null tests) a.guard of
        Tuple true Nothing -> Tuple (out <> [ stmt ]) true
        Tuple true _ -> caseArms meta acc rest (out <> [ "run { " <> stmt <> " }" ])
        _ -> caseArms meta acc rest (out <> [ "if (" <> joinWith " && " tests <> ") { " <> stmt <> " }" ])

guardedArm :: Meta -> String -> Maybe CExpr -> String
guardedArm _ bodyKt Nothing = "return@rcase " <> bodyKt
guardedArm meta bodyKt (Just g) = "if (" <> exprKt meta g <> ") { return@rcase " <> bodyKt <> " }"

-- a branch value: a single-expression block unwraps to that expression.
branchKt :: Meta -> CExpr -> String
branchKt meta (EBlock [ CExprStmt e ]) = exprKt meta e
branchKt meta e = exprKt meta e

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
  -- a bare nominal type (a sum / struct name) → its Kotlin name verbatim. Guarded to
  -- paren-free names so a not-yet-ported `Vec(…)`/`Fn(…)`/tuple still stage-crashes.
  | nominal t = t
  | otherwise = unsafeCrashWith ("jvm: stage — type `" <> t <> "` (inc 3)")

nominal :: String -> Boolean
nominal t = not (Str.contains (Str.Pattern "(") t) && case CU.charAt 0 t of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

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
