-- | ECMAScript emitter (ADR-0049 Tier 1) — the PureScript port of `Rian.JS` (lib/rian/js.ex),
-- | ADR-0084. A **direct** JS source emitter on the typed Core IR (ADR-0050): it consumes
-- | `Core.fromExpr`/`fromPat`, never the surface. JS has no native multi-clause matching, so a
-- | multi-clause function lowers to a **dispatcher** (positional `a0,a1,…`, one guarded block per
-- | clause, a final `throw`).
-- |
-- | Integer mode is whole-program (ADR-0064): if any signature names a JS-number width
-- | (`Int53`/`Int32`/smaller) the module emits in number-mode (`i53 = true`, native `number`),
-- | else BigInt-mode (`Int` → `42n`). `Int`+number widths cannot mix (`rejectMixedIntMode`);
-- | `Int64`+ are rejected (`rejectWideInt`), never silently elevated to BigInt.
-- |
-- | This is the runtime-module print mode (`compile`). NOT yet ported (need a Core/Func extension):
-- | `const` references (no `EConstRef` in PS Core), protocol dispatch (no `Func.dispatch` marker),
-- | `@external` bodies, value-union type-patterns over a user type (no `PTyped` discriminator), and
-- | the `.d.ts` sidecar (`compile_types`). The parity corpus avoids those.
module Rian.JS
  ( compile
  , compileSexpr
  ) where

import Prelude

import Data.Array (any, elem, filter, foldl, head, index, length, mapMaybe, mapWithIndex, null, range, snoc, uncons, unsnoc)
import Data.Foldable (foldMap)
import Data.Enum (fromEnum)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as Str
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (singleton, toCharArray)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CMapPatPair(..), CPat(..), CStmt(..), CWithClause, LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Func, Prog, bodySurface)
import Rian.Opaque (erase)
import Rian.Pratt (Surface(..), parse) as P
import Rian.Prim (overflowOps)
import Rian.Shadow (dedup)

-- | Compile `src`'s functions to a single ECMAScript module (a string).
-- @rian_sig pub def compile(src val String) String
compile :: String -> String
compile src =
  let
    prog0 = assemble (parseToProg src)
  in
    case checkProgram prog0 of
      Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
      Nothing ->
        let
          prog = erase prog0
          _ = rejectMixedIntMode prog
          i53 = programNumberMode prog
          funcs = allFuncs prog
          fnJs = joinWith "\n\n" (map (functionJs i53) funcs)
        in
          -- imports / consts / protocol dispatchers are deferred; the join keeps their slots so the
          -- shape composes once they land (matches the reference's reject-empty-then-join).
          joinWith "\n\n" (filter (_ /= "") [ fnJs ])

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> concatModFuncs prog.mods
  where
  concatModFuncs ms = foldl (\acc m -> acc <> m.funcs) [] ms

-- ── whole-program integer mode (ADR-0064) ────────────────────────────────────
-- the JS-number integer widths (`Int53`/`Int32`/smaller) — if a signature names one anywhere, the
-- whole module emits in number-mode; bare `Int` is BigInt.
jsNumberWords :: Array String
jsNumberWords = [ "Int53", "Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32" ]

wideInts :: Array String
wideInts = [ "Int64", "Int128", "UInt64", "UInt128" ]

-- the identifier words in a type string (`Vec(Int53)` → `["Vec","Int53"]`) — a regex-free `\bword\b`.
typeWords :: String -> Array String
typeWords s = filter (_ /= "") (go (toCharArray s) [] [])
  where
  go cs cur acc = case uncons cs of
    Nothing -> snoc acc (charsToStr cur)
    Just { head: c, tail } ->
      if isWordChar c then go tail (snoc cur c) acc
      else go tail [] (snoc acc (charsToStr cur))
  isWordChar c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
  charsToStr = foldMap singleton

sigTypes :: Prog -> Array String
sigTypes prog = mapMaybe identity (foldl (\acc f -> acc <> map _.ty f.params <> [ f.ret ]) [] (allFuncs prog))

jsNumberInt :: String -> Boolean
jsNumberInt t = any (\w -> elem w jsNumberWords) (typeWords t)

jsBigintInt :: String -> Boolean
jsBigintInt t = elem "Int" (typeWords t)

programNumberMode :: Prog -> Boolean
programNumberMode prog = any jsNumberInt (sigTypes prog)

-- `Int` (→ BigInt) and a JS-number width (→ number) cannot coexist: BigInt and number never mix in
-- JS, and number-mode would silently demote `Int` (ADR-0064 §2a). Refuse the mix loudly.
rejectMixedIntMode :: Prog -> Unit
rejectMixedIntMode prog =
  let ts = sigTypes prog
  in
    if any jsNumberInt ts && any jsBigintInt ts then
      unsafeCrashWith "ecmascript: a module cannot mix `Int` (BigInt) with a fixed-width JS-number type (`Int53`/`Int32`) — ADR-0064 §2a"
    else unit

-- a wide fixed-width integer (`Int64`+) has no faithful JS representation and is never elevated to
-- BigInt (ADR-0064); a function naming one is rejected (Reach pins it off `:js` first).
wideIntType :: Func -> Maybe String
wideIntType f = head (filter (\t -> elem t wideInts) (mapMaybe identity (map _.ty f.params <> [ f.ret ])))

-- ── functions / clauses ──────────────────────────────────────────────────────
functionJs :: Boolean -> Func -> String
functionJs i53 f =
  if not (null f.externals) then unsafeCrashWith ("`" <> f.name <> "`: `@external` is not yet ported in the PS JS emitter")
  else case wideIntType f of
    Just t -> unsafeCrashWith ("`" <> f.name <> "`: fixed-width integer `" <> t <> "` is not supported on JS (ADR-0064)")
    Nothing ->
      let
        arity = maybe 0 (\c -> length c.pats) (head f.clauses)
        params = joinWith ", " (map (\i -> "a" <> show i) (upto arity))
        body = joinWith "\n" (map (clauseJs i53) f.clauses)
        export = if f.pub then "export " else ""
      in
        export <> "function " <> f.name <> "(" <> params <> ") {\n" <> body
          <> "\n  throw new Error(\"" <> f.name <> ": no clause matched\");\n}"

-- `0..n-1` (empty for `n <= 0`; `Array.range 0 (-1)` would wrongly give `[0,-1]`).
upto :: Int -> Array Int
upto n = if n <= 0 then [] else range 0 (n - 1)

-- `{ if (<tests>) { <binds> <guarded return> } }` — binds live inside the test so a nested field
-- access only runs once the shape is known; a `when` guard follows.
clauseJs :: Boolean -> Clause -> String
clauseJs i53 clause =
  let
    step (Tuple ts bs) (Tuple i p) = let Tuple t b = patMatch i53 p ("a" <> show i) in Tuple (ts <> t) (bs <> b)
    Tuple tests binds = foldl step (Tuple [] []) (mapWithIndex Tuple (map fromPat clause.pats))
    paramNames = map fst binds
    inner = bindLines binds <> [ guardedReturn i53 paramNames clause.body clause.guard ]
    bodyStr = joinWith " " inner
    guarded = if null tests then bodyStr else "if (" <> joinWith " && " tests <> ") { " <> bodyStr <> " }"
  in
    "  { " <> guarded <> " }"

bindLines :: Array (Tuple String String) -> Array String
bindLines = map (\(Tuple n a) -> "const " <> n <> " = " <> a <> ";")

guardedReturn :: Boolean -> Array String -> Maybe Body -> Maybe String -> String
guardedReturn i53 params body guard = case guard of
  Nothing -> clauseReturn i53 params body
  Just g -> "if (" <> exprJs i53 (fromExpr (P.parse g)) <> ") { " <> clauseReturn i53 params body <> " }"

-- a clause body parses to a block: `let`s then `return` the final value; `:=` shadowing is resolved
-- on the Core IR by `Rian.Shadow` (JS `let`/`const` forbid same-scope re-declaration).
clauseReturn :: Boolean -> Array String -> Maybe Body -> String
clauseReturn i53 params body = case body of
  Nothing -> unsafeCrashWith "Rian.JS: a clause has no body"
  Just b -> case fromExpr (bodySurface b) of
    EBlock stmts -> blockReturn i53 (dedup stmts params jsFresh)
    other -> blockReturn i53 (dedup [ CExprStmt other ] params jsFresh)

jsFresh :: String -> Int -> String
jsFresh base count = base <> "$" <> show count

blockReturn :: Boolean -> Array CStmt -> String
blockReturn i53 stmts = case unsnoc stmts of
  Nothing -> ""
  Just { init, last } ->
    if null init then case last of
      CExprStmt e -> "return " <> exprJs i53 e <> ";"
      _ -> stmtReturn i53 last
    else joinWith " " (map (stmtJs i53) init) <> " " <> stmtReturn i53 last

stmtJs :: Boolean -> CStmt -> String
stmtJs i53 = case _ of
  CBind n e -> "let " <> n <> " = " <> exprJs i53 e <> ";"
  CTypedBind n _ e -> "let " <> n <> " = " <> exprJs i53 e <> ";"
  CExprStmt e -> exprJs i53 e <> ";"

stmtReturn :: Boolean -> CStmt -> String
stmtReturn i53 = case _ of
  CExprStmt e -> "return " <> exprJs i53 e <> ";"
  _ -> unsafeCrashWith "Rian.JS: a block's final statement must be an expression (ADR-0035)"

-- ── pattern matching → {tests, binds} against the access path `acc` ───────────
patMatch :: Boolean -> CPat -> String -> Tuple (Array String) (Array (Tuple String String))
patMatch i53 pat acc = case pat of
  PWild -> Tuple [] []
  PVar n -> Tuple [] [ Tuple n acc ]
  PAs n p -> let Tuple ts bs = patMatch i53 p acc in Tuple ts (snoc bs (Tuple n acc))
  PPin s -> case s of
    P.SId name -> Tuple [ acc <> " === " <> name ] []
    _ -> unsafeCrashWith "ecmascript: pin (only `^var` is supported)"
  PTyped n t -> Tuple [ typeTestJs i53 t acc ] [ Tuple n acc ]
  PLit (LInt v) -> Tuple [ acc <> " === " <> litInt i53 v ] []
  PLit (LStr v) -> Tuple [ acc <> " === " <> jsStr v ] []
  PChar cp -> Tuple [ acc <> " === " <> cpLit i53 cp ] []
  PAtom a -> Tuple [ acc <> " === " <> jsAtom a ] []
  PTuple es -> let Tuple ts bs = matchElems i53 es acc in Tuple (cons1 (acc <> ".length === " <> show (length es)) ts) bs
  PCtor ctor args ->
    let Tuple ts bs = matchCtorArgs i53 args acc
    in Tuple (cons1 (acc <> "[0] === " <> dquote ctor) ts) bs
  PList es Nothing -> let Tuple ts bs = matchElems i53 es acc in Tuple (cons1 (acc <> ".length === " <> show (length es)) ts) bs
  PList es (Just tail) ->
    let
      n = length es
      Tuple ts bs = matchElems i53 es acc
      Tuple tt tb = patMatch i53 tail (acc <> ".slice(" <> show n <> ")")
    in
      Tuple (cons1 (acc <> ".length >= " <> show n) (ts <> tt)) (bs <> tb)
  PStruct name fields -> matchStruct i53 name fields acc
  PMap pairs -> matchMap i53 pairs acc

cons1 :: forall a. a -> Array a -> Array a
cons1 x xs = [ x ] <> xs

matchElems :: Boolean -> Array CPat -> String -> Tuple (Array String) (Array (Tuple String String))
matchElems i53 es acc = foldl step (Tuple [] []) (mapWithIndex Tuple es)
  where
  step (Tuple ts bs) (Tuple i p) = let Tuple t b = patMatch i53 p (acc <> "[" <> show i <> "]") in Tuple (ts <> t) (bs <> b)

matchCtorArgs :: Boolean -> Array CPat -> String -> Tuple (Array String) (Array (Tuple String String))
matchCtorArgs i53 args acc = foldl step (Tuple [] []) (mapWithIndex Tuple args)
  where
  step (Tuple ts bs) (Tuple i p) = let Tuple t b = patMatch i53 p (acc <> "[" <> show (i + 1) <> "]") in Tuple (ts <> t) (bs <> b)

matchStruct :: Boolean -> String -> Array (Tuple String CPat) -> String -> Tuple (Array String) (Array (Tuple String String))
matchStruct i53 name fields acc = foldl step (Tuple [ acc <> ".__struct__ === " <> dquote name ] []) fields
  where
  step (Tuple ts bs) (Tuple f p) = let Tuple t b = patMatch i53 p (acc <> "." <> f) in Tuple (ts <> t) (bs <> b)

matchMap :: Boolean -> Array CMapPatPair -> String -> Tuple (Array String) (Array (Tuple String String))
matchMap i53 pairs acc = foldl step (Tuple [] []) pairs
  where
  step (Tuple ts bs) = case _ of
    CMPKey _ _ -> unsafeCrashWith "a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)"
    CMPAtom k p ->
      let
        ks = dquote k
        Tuple t b = patMatch i53 p (acc <> "[" <> ks <> "]")
      in
        Tuple (ts <> cons1 ("Object.hasOwn(" <> acc <> ", " <> ks <> ")") t) (bs <> b)

-- ── case arms ────────────────────────────────────────────────────────────────
caseArmJs :: Boolean -> CArm -> String
caseArmJs i53 arm =
  let
    Tuple tests binds = patMatch i53 arm.pat "_s"
    inner = joinWith " " (bindLines binds <> [ armReturn i53 arm.body arm.guard ])
  in
    if null tests then inner else "if (" <> joinWith " && " tests <> ") { " <> inner <> " }"

armReturn :: Boolean -> CExpr -> Maybe CExpr -> String
armReturn i53 body guard = case guard of
  Nothing -> "return " <> branchJs i53 body <> ";"
  Just g -> "if (" <> exprJs i53 g <> ") { return " <> branchJs i53 body <> "; }"

-- ── expression emission ──────────────────────────────────────────────────────
exprJs :: Boolean -> CExpr -> String
exprJs i53 = case _ of
  ENum n -> numJs i53 n
  EChar cp -> cpLit i53 cp
  EStr s -> jsStr s
  EId b | b == "true" || b == "false" -> b
  EId x -> if pascal x then "[" <> dquote x <> "]" else x
  EAtom a -> jsAtom a
  EUnary "-" x -> "-" <> exprJs i53 x
  EUnary "not" x -> "!" <> exprJs i53 x
  EUnary op _ -> unsafeCrashWith ("ecmascript: unary operator `" <> op <> "`")
  EBin "div" l r ->
    if i53 then "Math.trunc(" <> exprJs i53 l <> " / " <> exprJs i53 r <> ")"
    else "(" <> exprJs i53 l <> " / " <> exprJs i53 r <> ")"
  EBin "in" l r -> exprJs i53 r <> ".includes(" <> exprJs i53 l <> ")"
  EBin op l r -> "(" <> exprJs i53 l <> " " <> jsOp op <> " " <> exprJs i53 r <> ")"
  ETuple es -> "[" <> joinWith ", " (map (exprJs i53) es) <> "]"
  EList es Nothing -> "[" <> joinWith ", " (map (exprJs i53) es) <> "]"
  EList es (Just tail) -> "[" <> joinWith ", " (map (exprJs i53) es <> [ "..." <> exprJs i53 tail ]) <> "]"
  EMap pairs -> "{" <> joinWith ", " (map (jsMapPair i53) pairs) <> "}"
  EMapUpdate base pairs -> "{..." <> exprJs i53 base <> ", " <> joinWith ", " (map (jsMapPair i53) pairs) <> "}"
  ECall fun args -> callJs i53 fun args
  EIf c t e -> "(" <> exprJs i53 c <> " ? " <> branchJs i53 t <> " : " <> branchJs i53 e <> ")"
  EDot head field -> exprJs i53 head <> "." <> field
  EWith clauses body els -> exprJs i53 (desugarWith clauses body els)
  ELambda params body -> "(" <> joinWith ", " (map _.name params) <> ") => " <> branchJs i53 body
  ECapture body -> "(" <> joinWith ", " (map (\i -> "_" <> show i) (oneTo (capArity body))) <> ") => " <> exprJs i53 body
  ECaptureNamed (EId n) _ -> n
  ECaptureNamed path a ->
    let ps = map (\i -> "_a" <> show i) (upto a)
    in "(" <> joinWith ", " ps <> ") => " <> exprJs i53 path <> "(" <> joinWith ", " ps <> ")"
  ECapArg n -> "_" <> show n
  ECase scrut arms ->
    "(() => { const _s = " <> exprJs i53 scrut <> "; " <> joinWith " " (map (caseArmJs i53) arms)
      <> " throw new Error(\"case: no clause matched\"); })()"
  EBlock stmts -> branchJs i53 (EBlock stmts)
  other -> unsafeCrashWith ("ecmascript: expression " <> tag other)

-- a coarse tag for the Unsupported message (kept tiny; only reached on a genuinely unported node).
tag :: CExpr -> String
tag = case _ of
  ELabel _ _ -> "ELabel"
  _ -> "?"

-- `0..` empty for `n < 1`; `&(1)` (cap-arity 0) → `() => 1`.
oneTo :: Int -> Array Int
oneTo n = if n < 1 then [] else range 1 n

-- the JS `typeof` of an integer/`Char` in this program's whole-program int mode.
intTypeof :: Boolean -> String
intTypeof i53 = if i53 then "number" else "bigint"

-- a value-union type-pattern's primitive runtime test (ADR-0083); a non-primitive raises (the
-- user-type discriminator needs a `PTyped` field PS Core doesn't carry yet).
typeTestJs :: Boolean -> String -> String -> String
typeTestJs i53 t acc =
  if t == "Bool" then tof "boolean"
  else if t == "String" then tof "string"
  else if t == "Char" then tof (intTypeof i53)
  else if isIntType t then tof (intTypeof i53)
  else if isFloatType t then tof "number"
  else unsafeCrashWith ("ecmascript: JS type-pattern over non-primitive `" <> t <> "`")
  where
  tof k = "typeof " <> acc <> " === " <> dquote k

isIntType :: String -> Boolean
isIntType t = elem t [ "Int", "Int8", "Int16", "Int32", "Int53", "Int64", "Int128", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128" ]

isFloatType :: String -> Boolean
isFloatType t = elem t [ "Float", "Float32", "Float64" ]

-- ── call dispatch ────────────────────────────────────────────────────────────
callJs :: Boolean -> CExpr -> Array CExpr -> String
callJs i53 fun args = case fun of
  EId name -> callId i53 name args
  EDot hd field -> callDot i53 hd field args
  _ -> unsafeCrashWith "ecmascript: call over a non-identifier callee"

callId :: Boolean -> String -> Array CExpr -> String
callId i53 name args
  | isPrim name = primCall i53 name args
  | elem name overflowOps && length args == 2 =
      unsafeCrashWith ("`" <> name <> "` operates on `Int64`, not supported on JS (ADR-0064)")
  | firstIsLabel args = "{ __struct__: " <> dquote name <> ", " <> joinWith ", " (map (labelPair i53) args) <> " }"
  | pascal name = "[" <> joinWith ", " (cons1 (dquote name) (map (exprJs i53) args)) <> "]"
  | otherwise = name <> "(" <> joinWith ", " (map (exprJs i53) args) <> ")"

isPrim :: String -> Boolean
isPrim name = Str.take 7 name == "__prim_"

firstIsLabel :: Array CExpr -> Boolean
firstIsLabel args = case head args of
  Just (ELabel _ _) -> true
  _ -> false

labelPair :: Boolean -> CExpr -> String
labelPair i53 = case _ of
  ELabel l e -> l <> ": " <> exprJs i53 e
  e -> exprJs i53 e

-- portable-prelude primitives (ADR-0047) lowered to JS objects/strings; arity is guaranteed by the
-- prim contract, so positional access is safe.
primCall :: Boolean -> String -> Array CExpr -> String
primCall i53 name args = case name of
  "__prim_map_new" -> "{}"
  "__prim_map_get" -> paren i53 (a 0) <> "[" <> exprJs i53 (a 1) <> "]"
  "__prim_map_put" -> "{..." <> paren i53 (a 0) <> ", [" <> exprJs i53 (a 1) <> "]: " <> exprJs i53 (a 2) <> "}"
  "__prim_map_has" -> "Object.hasOwn(" <> paren i53 (a 0) <> ", " <> exprJs i53 (a 1) <> ")"
  "__prim_str_chars" -> "[..." <> paren i53 (a 0) <> "].map(c => " <> cpExpr i53 "c.codePointAt(0)" <> ")"
  "__prim_str_from_chars" -> paren i53 (a 0) <> ".map(c => String.fromCodePoint(Number(c))).join(\"\")"
  "__prim_char_code" -> exprJs i53 (a 0)
  "__prim_int_to_string" -> "String(" <> exprJs i53 (a 0) <> ")"
  "__prim_to_string" -> "String(" <> exprJs i53 (a 0) <> ")"
  "__prim_float_repr" -> "(" <> exprJs i53 (a 0) <> ").toExponential()"
  "__prim_int_to_float" -> "Number(" <> exprJs i53 (a 0) <> ")"
  "__prim_str_concat" -> "(" <> exprJs i53 (a 0) <> " + " <> exprJs i53 (a 1) <> ")"
  "__prim_str_concat_all" -> "(" <> joinWith " + " (map (exprJs i53) args) <> ")"
  "__prim_char_to_string" -> "String.fromCodePoint(Number(" <> exprJs i53 (a 0) <> "))"
  "__prim_panic" -> "(() => { throw new Error(" <> exprJs i53 (a 0) <> "); })()"
  _ -> unsafeCrashWith ("ecmascript: primitive `" <> name <> "`")
  where
  a i = fromMaybe (EId "undefined") (index args i)

callDot :: Boolean -> CExpr -> String -> Array CExpr -> String
callDot i53 hd field args = case hd of
  EId "Map"
    | field == "get" -> paren i53 (ix 0) <> "[" <> exprJs i53 (ix 1) <> "]"
    | field == "put" -> "{..." <> paren i53 (ix 0) <> ", [" <> exprJs i53 (ix 1) <> "]: " <> exprJs i53 (ix 2) <> "}"
  EId "String"
    | field == "to_charlist" -> "[..." <> paren i53 (ix 0) <> "].map(c => " <> cpExpr i53 "c.codePointAt(0)" <> ")"
  EId "List"
    | field == "to_string" -> paren i53 (ix 0) <> ".map(c => String.fromCodePoint(Number(c))).join(\"\")"
  EAtom "lists"
    | field == "reverse" -> paren i53 (ix 0) <> ".slice().reverse()"
  EId mod
    | mod /= "Map" && mod /= "String" -> field <> "(" <> joinWith ", " (map (exprJs i53) args) <> ")"
  _ -> unsafeCrashWith ("ecmascript: call `" <> field <> "` over an unsupported namespace")
  where
  ix i = fromMaybe (EId "undefined") (index args i)

-- one JS map pair; a non-atom (computed) key has no faithful JS-object lowering (ADR-0033).
jsMapPair :: Boolean -> CMapPair -> String
jsMapPair i53 = case _ of
  CMKey _ _ -> unsafeCrashWith "a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)"
  CMAtom k v -> k <> ": " <> exprJs i53 v

-- an `if`/lambda branch: a single-expr block is an expression, a multi-statement block an IIFE.
branchJs :: Boolean -> CExpr -> String
branchJs i53 = case _ of
  EBlock stmts -> case unsnoc stmts of
    Nothing -> "undefined"
    Just { init, last } ->
      if null init then case last of
        CExprStmt e -> exprJs i53 e
        _ -> "(() => { " <> blockReturn i53 stmts <> " })()"
      else "(() => { " <> blockReturn i53 stmts <> " })()"
  expr -> exprJs i53 expr

-- ── with / capture desugaring (Core-local, the JS emitter's own) ──────────────
-- a `with` desugars to a nest of `case`s (ADR-0040): each `p <- e` becomes
-- `case e do p -> <rest> ; _withN -> <else> end`.
desugarWith :: Array CWithClause -> CExpr -> Array CArm -> CExpr
desugarWith clauses body els = go 0 clauses
  where
  go d cls = case uncons cls of
    Nothing -> body
    Just { head: wc, tail } ->
      let cv = "_with" <> show d
      in ECase wc.expr
        [ { pat: wc.pat, guard: Nothing, body: go (d + 1) tail }
        , { pat: PVar cv, guard: Nothing, body: withElse cv }
        ]
  withElse cv = if null els then EId cv else ECase (EId cv) els

-- the arity of an anonymous capture `&(…&N…)` — the largest `&N`.
capArity :: CExpr -> Int
capArity = case _ of
  ECapArg n -> n
  EBin _ l r -> max (capArity l) (capArity r)
  EUnary _ x -> capArity x
  EDot h _ -> capArity h
  EIf c t e -> max (capArity c) (max (capArity t) (capArity e))
  ECall f args -> foldl (\acc e -> max acc (capArity e)) (capArity f) args
  ETuple es -> capList es
  EList es Nothing -> capList es
  EList es (Just tail) -> max (capList es) (capArity tail)
  EMap ps -> capList (map mapPairVal ps)
  EMapUpdate base ps -> max (capArity base) (capList (map mapPairVal ps))
  _ -> 0
  where
  capList = foldl (\acc e -> max acc (capArity e)) 0
  mapPairVal = case _ of
    CMAtom _ v -> v
    CMKey _ v -> v

-- ── leaf helpers ─────────────────────────────────────────────────────────────
-- `Int` → BigInt literal (`42n`); a float literal is a plain number; in number-mode an integer
-- literal is a plain native number.
numJs :: Boolean -> String -> String
numJs i53 n = if isFloatLit n then n else if i53 then n else n <> "n"

litInt :: Boolean -> Int -> String
litInt i53 v = if i53 then show v else show v <> "n"

-- a `Char`/codepoint follows the program's integer mode (number or BigInt) so it never mixes.
cpLit :: Boolean -> Int -> String
cpLit i53 cp = if i53 then show cp else show cp <> "n"

cpExpr :: Boolean -> String -> String
cpExpr i53 js = if i53 then js else "BigInt(" <> js <> ")"

isFloatLit :: String -> Boolean
isFloatLit n = Str.contains (Str.Pattern ".") n || Str.contains (Str.Pattern "e") n || Str.contains (Str.Pattern "E") n

-- a Rian `String`/atom → a JS double-quoted literal; escape quote/backslash/common control chars by
-- name and any other control codepoint as `\uHHHH` (printable codepoints pass through).
jsStr :: String -> String
jsStr s = "\"" <> foldMap jsStrCp (CP.toCodePointArray s) <> "\""

jsAtom :: String -> String
jsAtom = jsStr

jsStrCp :: CP.CodePoint -> String
jsStrCp cp =
  let n = fromEnum cp
  in
    if n == 92 then "\\\\"
    else if n == 34 then "\\\""
    else if n == 10 then "\\n"
    else if n == 13 then "\\r"
    else if n == 9 then "\\t"
    else if n < 0x20 || n == 0x7F then "\\u" <> hex4 n
    else CP.singleton cp

hex4 :: Int -> String
hex4 n =
  let h = Int.toStringAs Int.hexadecimal n
  in case Str.length h of
    1 -> "000" <> h
    2 -> "00" <> h
    3 -> "0" <> h
    _ -> h

jsOp :: String -> String
jsOp = case _ of
  "==" -> "==="
  "!=" -> "!=="
  "and" -> "&&"
  "or" -> "||"
  "<>" -> "+"
  "/" -> "/"
  "rem" -> "%"
  op -> if elem op [ "+", "-", "*", "<", "<=", ">", ">=", "%" ] then op else unsafeCrashWith ("ecmascript: operator `" <> op <> "`")

-- parenthesise an operand of a postfix `[…]`/`.method()` so precedence holds.
paren :: Boolean -> CExpr -> String
paren i53 e = "(" <> exprJs i53 e <> ")"

-- a JS string literal for a tag / identifier (an identifier never needs escaping; matches the
-- reference's `inspect(name)` for the PascalCase/field names it is used on).
dquote :: String -> String
dquote s = "\"" <> s <> "\""

pascal :: String -> Boolean
pascal s = case head (toCharArray s) of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

-- | The `js` parity unit: the compiled ECMAScript module for `src`.
compileSexpr :: String -> String
compileSexpr = compile
