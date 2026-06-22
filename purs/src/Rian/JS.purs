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
-- | Both print modes are ported: `compile` (the runtime module) and `compileTypes` (the `.d.mts`
-- | sidecar, ADR-0086 §5). Module `const`s + references (`resolveConsts`/`constJs`, the `EConstRef`
-- | Core node), `@external` bodies (`externalFn`/`importsJs`, the 3 `ExtSpec` forms + ESM imports),
-- | value-union discrimination over a user type (`bakeUnionDisc` bakes the `PTyped` disc; a sum
-- | member tests the tagged-array head, a struct member tests `__struct__`), and protocol dispatch
-- | (`protocolDispatchersJs` regenerates the JS dispatcher from `Prog.protocols`/`implDecls`, skipping
-- | the BEAM-shaped `dispatch == "dispatcher"` func), struct *construction* `Name(f: v)` (`bakeStructs`
-- | → the `EStruct` Core node → a `__struct__`-tagged object), and string interpolation (the program
-- | tail `Rian.Assemble.runProgramTail`, composed before the gate) are all ported.
module Rian.JS
  ( compile
  , compileSexpr
  , compileTypes
  , compileTypesSexpr
  ) where

import Prelude

import Data.Array (any, concatMap, elem, filter, find, foldl, head, index, length, mapMaybe, mapWithIndex, nub, null, range, snoc, sort, uncons, unsnoc)
import Data.Foldable (foldMap)
import Data.Enum (fromEnum)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as Str
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (singleton, toCharArray)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.External (render) as Ext
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CMapPatPair(..), CPat(..), CStmt(..), CWithClause, LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Const, ExtSpec(..), Func, Method, Prog, Range, Struct, Type, Variant, bodySurface)
import Rian.Macro (mapNode)
import Rian.Opaque (erase)
import Rian.Pratt (Pat(..), Surface(..), parse, parseBody) as P
import Rian.Prim (normalize, overflowOps)
import Rian.Shadow (dedup)
import Rian.TypeStr (normalize, splitTopCommas) as TS

-- | Compile `src`'s functions to a single ECMAScript module (a string).
-- @rian_sig pub def compile(src val String) String
compile :: String -> String
compile src =
  let
    -- the program tail (interpolation resolution + `Show` injection) runs before the gate, matching
    -- the reference's `Decl.parse` → `Check.gate!` order (ADR-0069).
    prog0 = runProgramTail (assemble (parseToProg src))
  in
    case checkProgram prog0 of
      Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
      Nothing ->
        let
          prog = erase prog0
          _ = rejectMixedIntMode prog
          i53 = programNumberMode prog
          -- the BEAM `:dispatcher` is a guarded runtime type-test, not the JS shape; drop it and
          -- regenerate it with JS-native guards (`protocolDispatchersJs`). The `:impl` methods stay
          -- as plain functions (ADR-0061 §3).
          funcs = filter (\f -> f.dispatch /= Just "dispatcher") (allFuncs prog)
          -- `const NAME := value` (ADR-0033) → a top-level JS `const`; a reference resolves to it,
          -- threaded through `cset` so every clause body and sibling const sees the const set.
          consts = allConsts prog
          cset = map _.name consts
          reg = jsReg prog
          constJsOut = joinWith "\n" (map (constJs i53 cset reg) consts)
          fnJs = joinWith "\n\n" (map (functionJs i53 cset reg) funcs)
          importJsOut = importsJs funcs
          dispJsOut = protocolDispatchersJs i53 prog
        in
          joinWith "\n\n" (filter (_ /= "") [ importJsOut, constJsOut, fnJs, dispJsOut ])

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
-- Rewrite a reference to a declared `const` (`SId NAME`, NAME in the set) into an `SConstRef`,
-- which `Core.fromExpr` lifts to `EConstRef` and this emitter spells as the const's name. Empty
-- set short-circuits (most programs have no consts). Mirrors `Rian.JS.resolve_consts`.
resolveConsts :: Array String -> P.Surface -> P.Surface
resolveConsts cset node
  | null cset = node
  | otherwise = walk node
      where
      walk (P.SId name) | name `elem` cset = P.SConstRef name
      walk other = mapNode walk other

-- `const NAME := value` → a top-level JS `const` (exported when `pub`). The value parses, resolves
-- sibling const references, and emits in the program integer mode: a single-expression value emits
-- inline; a multi-statement block wraps in an IIFE so the `const` still binds one expression.
constJs :: Boolean -> Array String -> JsReg -> Const -> String
constJs i53 cset reg c =
  let
    stmts = case fromExpr (bakeStructs reg (resolveConsts cset (normalize (P.parseBody c.value)))) of
      EBlock ss -> ss
      other -> [ CExprStmt other ]
    val = case dedup stmts [] jsFresh of
      [ CExprStmt e ] -> exprJs i53 e
      deduped -> "(() => { " <> blockReturn i53 deduped <> " })()"
    export = if c.pub then "export " else ""
  in
    export <> "const " <> c.name <> " = " <> val <> ";"

-- the value-union discriminator registry (ADR-0083): each sum type → its ctor tags, plus the set
-- of struct names. `bakeUnionDisc` consults it so `patMatch` can emit a sum/struct runtime test.
type JsReg = { sums :: Array (Tuple String (Array String)), structs :: Array String }

jsReg :: Prog -> JsReg
jsReg prog =
  { sums: map (\t -> Tuple t.name (map _.ctor t.variants)) (allTypes prog)
  , structs: map _.name (allStructs prog)
  }

-- Bake a value-union type-pattern's discriminator into the surface so `patMatch` (which threads no
-- type registry) can emit a sum's tag / a struct's `__struct__` test. `mapNode` skips arm PATTERNS,
-- so a `case` arm's pattern is baked explicitly; everything else recurses. Mirrors `bake_union_disc`.
bakeUnionDisc :: JsReg -> P.Surface -> P.Surface
bakeUnionDisc reg (P.SCase s arms) =
  P.SCase (bakeUnionDisc reg s)
    (map (\a -> a { pat = bakePat reg a.pat, guard = map (bakeUnionDisc reg) a.guard, body = bakeUnionDisc reg a.body }) arms)
bakeUnionDisc reg node = mapNode (bakeUnionDisc reg) node

-- `name T` → encode T's discriminator in the disc field for a user type (a primitive keeps `Nothing`,
-- which `patMatch` tests with `typeof`). Encoded as `"sum:C1,C2"` / `"struct:Name"`.
bakePat :: JsReg -> P.Pat -> P.Pat
bakePat reg (P.PTyped name tname Nothing) =
  case find (\(Tuple n _) -> n == tname) reg.sums of
    Just (Tuple _ ctors) -> P.PTyped name tname (Just ("sum:" <> joinWith "," ctors))
    Nothing ->
      if elem tname reg.structs then P.PTyped name tname (Just ("struct:" <> tname))
      else P.PTyped name tname Nothing
bakePat _ p = p

-- Resolve struct construction (ADR-0050): a labeled call to a declared struct (`Name(f: v, …)`,
-- the parser's `SCall (SId Name) [SLabel …]`) is rewritten to `SStructLit` (→ `Core.EStruct`), so
-- it lowers to a `__struct__`-tagged object instead of a function call. A non-struct name or any
-- non-label arg falls through. Mirrors the reference's annotate-time struct resolution.
bakeStructs :: JsReg -> P.Surface -> P.Surface
bakeStructs reg = walk
  where
  walk node = case node of
    P.SCall (P.SId name) args | elem name reg.structs ->
      let labels = mapMaybe asLabel args
      in
        if length labels == length args then P.SStructLit name (map (\(Tuple l v) -> Tuple l (walk v)) labels)
        else mapNode walk node
    _ -> mapNode walk node
  asLabel (P.SLabel l v) = Just (Tuple l v)
  asLabel _ = Nothing

functionJs :: Boolean -> Array String -> JsReg -> Func -> String
functionJs i53 cset reg f =
  if not (null f.externals) then externalFn f
  else case wideIntType f of
    Just t -> unsafeCrashWith ("`" <> f.name <> "`: fixed-width integer `" <> t <> "` is not supported on JS (ADR-0064)")
    Nothing ->
      let
        arity = maybe 0 (\c -> length c.pats) (head f.clauses)
        params = joinWith ", " (map (\i -> "a" <> show i) (upto arity))
        body = joinWith "\n" (map (clauseJs i53 cset reg) f.clauses)
        export = if f.pub then "export " else ""
      in
        export <> "function " <> f.name <> "(" <> params <> ") {\n" <> body
          <> "\n  throw new Error(\"" <> f.name <> ": no clause matched\");\n}"

-- ── protocol dispatch (ADR-0061 §3): a JS dispatcher per protocol method ──
-- select the impl by the first argument's runtime shape, with JS-native guards. Mirrors
-- `protocol_dispatchers_js`: one dispatcher per (protocol, method) that has ≥1 impl, in order.
protocolDispatchersJs :: Boolean -> Prog -> String
protocolDispatchersJs i53 prog =
  let
    reg = jsReg prog
    dispatcher p m =
      case map _.ty (filter (\i -> i.proto == p.name) prog.implDecls) of
        [] -> Nothing
        implTypes -> Just (dispatcherJs i53 reg p.name m implTypes)
  in
    joinWith "\n\n" (concatMap (\p -> mapMaybe (dispatcher p) p.methods) prog.protocols)

dispatcherJs :: Boolean -> JsReg -> String -> Method -> Array String -> String
dispatcherJs i53 reg proto method implTypes =
  let
    arity = length (TS.splitTopCommas method.params)
    params = joinWith ", " (map (\i -> "a" <> show i) (upto arity))
    clauses = joinWith "\n"
      (map (\ty -> "  if (" <> jsGuard i53 reg ty <> ") return " <> mangle proto ty method.name <> "(" <> params <> ");") implTypes)
  in
    "export function " <> method.name <> "(" <> params <> ") {\n" <> clauses
      <> "\n  throw new Error(\"" <> method.name <> ": no protocol impl\");\n}"

-- the mangled impl-method name the dispatcher routes to (`Protocol.expand`'s naming).
mangle :: String -> String -> String -> String
mangle proto ty method = "impl_" <> Str.toLower proto <> "_" <> Str.toLower ty <> "_" <> method

-- the JS guard selecting the impl for `ty` by the first argument's runtime shape (fixed to `a0`):
-- a sum/struct member tests its discriminator, a primitive tests `typeof` (raises for a type with
-- no runtime discriminator, as the reference does).
jsGuard :: Boolean -> JsReg -> String -> String
jsGuard i53 reg ty =
  case find (\(Tuple n _) -> n == ty) reg.sums of
    Just (Tuple _ ctors) -> sumDiscJs ctors "a0"
    Nothing -> if elem ty reg.structs then structDiscJs ty "a0" else typeTestJs i53 ty "a0"

-- the `:js` external spec, if any (the target key is the bare `"js"`, as `Decl` stores it).
jsExternal :: Func -> Maybe ExtSpec
jsExternal f = map snd (find (\(Tuple t _) -> t == "js") f.externals)

-- an `@external` function (ADR-0068): emit the `:js` host body verbatim. No `:js` body → the
-- function is off `:js` (Reach pins it); reaching here is an off-target compile, a clear error.
-- A file-reference calls the imported function (its `import` is at the module top, `importsJs`).
externalFn :: Func -> String
externalFn f = case jsExternal f of
  Nothing -> unsafeCrashWith ("`" <> f.name <> "`: no `@external(:js, …)` body — not reachable on :js")
  Just (ExtFile _ fun) -> jsExternalFn f (fun <> "(" <> joinWith ", " (map _.name f.params) <> ")")
  Just spec -> jsExternalFn f (Ext.render spec f.params)

-- wrap a `:js` host expression as the function body, binding each Rian param to its positional
-- argument by name so the expression can reference it (mirrors `Rian.JS.js_external_fn`).
jsExternalFn :: Func -> String -> String
jsExternalFn f host =
  let
    args = joinWith ", " (map (\i -> "a" <> show i) (upto (length f.params)))
    binds = joinWith " " (mapWithIndex (\i p -> "const " <> p.name <> " = a" <> show i <> ";") f.params)
    export = if f.pub then "export " else ""
  in
    export <> "function " <> f.name <> "(" <> args <> ") { " <> binds <> " return (" <> host <> "); }"

-- ESM imports for `@external(:js, "./ffi.mjs", "fun")` file-references (ADR-0080 §7 b): one
-- `import { … } from "path"` per referenced file, the imported functions deduped + sorted, the
-- paths sorted (mirrors `Rian.JS.imports_js`).
importsJs :: Array Func -> String
importsJs funcs =
  let
    refs = concatMap fileRefs funcs
    fileRefs f = case jsExternal f of
      Just (ExtFile path fun) -> [ Tuple path fun ]
      _ -> []
    paths = nub (sort (map fst refs))
    importLine path =
      let funs = nub (sort (mapMaybe (\(Tuple p fn) -> if p == path then Just fn else Nothing) refs))
      in "import { " <> joinWith ", " funs <> " } from \"" <> path <> "\";"
  in
    joinWith "\n" (map importLine paths)

-- `0..n-1` (empty for `n <= 0`; `Array.range 0 (-1)` would wrongly give `[0,-1]`).
upto :: Int -> Array Int
upto n = if n <= 0 then [] else range 0 (n - 1)

-- `{ if (<tests>) { <binds> <guarded return> } }` — binds live inside the test so a nested field
-- access only runs once the shape is known; a `when` guard follows.
clauseJs :: Boolean -> Array String -> JsReg -> Clause -> String
clauseJs i53 cset reg clause =
  let
    step (Tuple ts bs) (Tuple i p) = let Tuple t b = patMatch i53 p ("a" <> show i) in Tuple (ts <> t) (bs <> b)
    Tuple tests binds = foldl step (Tuple [] []) (mapWithIndex Tuple (map fromPat clause.pats))
    paramNames = map fst binds
    inner = bindLines binds <> [ guardedReturn i53 cset reg paramNames clause.body clause.guard ]
    bodyStr = joinWith " " inner
    guarded = if null tests then bodyStr else "if (" <> joinWith " && " tests <> ") { " <> bodyStr <> " }"
  in
    "  { " <> guarded <> " }"

bindLines :: Array (Tuple String String) -> Array String
bindLines = map (\(Tuple n a) -> "const " <> n <> " = " <> a <> ";")

guardedReturn :: Boolean -> Array String -> JsReg -> Array String -> Maybe Body -> Maybe String -> String
guardedReturn i53 cset reg params body guard = case guard of
  Nothing -> clauseReturn i53 cset reg params body
  Just g -> "if (" <> exprJs i53 (fromExpr (bakeStructs reg (resolveConsts cset (bakeUnionDisc reg (normalize (P.parse g)))))) <> ") { " <> clauseReturn i53 cset reg params body <> " }"

-- a clause body parses to a block: `let`s then `return` the final value; `:=` shadowing is resolved
-- on the Core IR by `Rian.Shadow` (JS `let`/`const` forbid same-scope re-declaration). The body is
-- baked (union discriminators) then const-resolved before lowering, as the reference does.
clauseReturn :: Boolean -> Array String -> JsReg -> Array String -> Maybe Body -> String
clauseReturn i53 cset reg params body = case body of
  Nothing -> unsafeCrashWith "Rian.JS: a clause has no body"
  Just b -> case fromExpr (bakeStructs reg (resolveConsts cset (bakeUnionDisc reg (normalize (bodySurface b))))) of
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
  -- a type-pattern `n Type` (ADR-0083): bind `n` and test the runtime type. A primitive (`Nothing`)
  -- tests `typeof`; a sum/struct member's discriminator was baked into `disc` by `bakeUnionDisc`.
  PTyped n t disc -> Tuple [ typedDiscJs i53 t acc disc ] [ Tuple n acc ]
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
  -- a reference to a declared `const` → the top-level `const`'s name (emitted by `constJs`).
  EConstRef name -> name
  -- a struct construction → a `__struct__`-tagged object (the runtime struct shape).
  EStruct name pairs ->
    "{ __struct__: " <> dquote name
      <> (if null pairs then "" else ", " <> joinWith ", " (map (\(Tuple l v) -> l <> ": " <> exprJs i53 v) pairs))
      <> " }"
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

-- a value-union type-pattern's runtime test (ADR-0083). A primitive (`Nothing`) tests `typeof`; a
-- baked sum/struct disc tests the JS-native discriminator the dispatcher uses (tag array / `__struct__`).
typedDiscJs :: Boolean -> String -> String -> Maybe String -> String
typedDiscJs i53 t acc disc = case disc of
  Nothing -> typeTestJs i53 t acc
  Just d -> case Str.stripPrefix (Str.Pattern "sum:") d of
    Just ctors -> sumDiscJs (Str.split (Str.Pattern ",") ctors) acc
    Nothing -> case Str.stripPrefix (Str.Pattern "struct:") d of
      Just sname -> structDiscJs sname acc
      Nothing -> typeTestJs i53 t acc

-- a sum member: a sum value is a tagged array `["Ctor", …]`, so "is a `T`" tests the head against
-- `T`'s ctor tags (mirrors `sum_disc_js`).
sumDiscJs :: Array String -> String -> String
sumDiscJs ctors acc =
  "Array.isArray(" <> acc <> ") && (" <> joinWith " || " (map (\c -> acc <> "[0] === " <> dquote c) ctors) <> ")"

-- a struct member: a struct is `{__struct__: "Name", …}` (mirrors `struct_disc_js`).
structDiscJs :: String -> String -> String
structDiscJs sname acc =
  "typeof " <> acc <> " === \"object\" && " <> acc <> " !== null && " <> acc <> ".__struct__ === " <> dquote sname

-- a value-union type-pattern's primitive runtime test (ADR-0083); a non-primitive with no baked disc
-- raises (a clause-head type-pattern over a user type is not baked, as in the reference).
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

--------------------------------------------------------------------------------
-- compile_types: the TypeScript `.d.mts` sidecar (ADR-0086 §5) — a typed *view* of the runtime
-- module: `export function`/`const` per `pub` decl + `type`/`interface`/range aliases describing
-- the values `compile` actually emits (a sum = `["Ctor",…]`, a struct = `{__struct__,…}`). A type
-- outside the mapped subset becomes `unknown` (honest), never a misleading `any`. Pure type-string
-- mapping — no Core IR — so no Core extension is needed.
--------------------------------------------------------------------------------

-- | Emit a TypeScript declaration sidecar (`.d.mts`) for `src`.
-- @rian_sig pub def compile_types(src val String) String
compileTypes :: String -> String
compileTypes src =
  let prog0 = assemble (parseToProg src)
  in case checkProgram prog0 of
    Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
    Nothing ->
      let
        prog = erase prog0
        known = knownTypeNames prog
        rangeDts = joinWith "\n" (map dtsRange (allRanges prog))
        typeDts = joinWith "\n" (map (dtsSum known) (allTypes prog))
        structDts = joinWith "\n" (map (dtsStruct known) (allStructs prog))
        constDts = joinWith "\n" (map (dtsConst known) (filter _.pub (allConsts prog)))
        fnDts = joinWith "\n" (map (dtsFunc known) (filter dtsEligible (allFuncs prog)))
        body = joinWith "\n\n" (filter (_ /= "") [ rangeDts, typeDts, structDts, constDts, fnDts ])
      in
        if body == "" then "" else body <> "\n"

-- only `pub` functions with a portable body export (a private `def` or an `@external` with
-- `clauses == []` is not part of the surface).
dtsEligible :: Func -> Boolean
dtsEligible f = f.pub && not (null f.clauses)

allTypes :: Prog -> Array Type
allTypes prog = prog.types <> concatMap _.types prog.mods

allStructs :: Prog -> Array Struct
allStructs prog = prog.structs <> concatMap _.structs prog.mods

allRanges :: Prog -> Array Range
allRanges prog = prog.ranges <> concatMap _.ranges prog.mods

-- top-level `const` is rejected by `Decl` (it must live in a `mod`), so consts come only from mods.
allConsts :: Prog -> Array Const
allConsts prog = concatMap _.consts prog.mods

-- every user type-name in scope (so a reference resolves instead of being read as a type variable).
knownTypeNames :: Prog -> Array String
knownTypeNames prog = map _.name (allTypes prog) <> map _.name (allStructs prog) <> map _.name (allRanges prog)

dtsRange :: Range -> String
dtsRange r = "export type " <> r.name <> " = number;"

-- a sum → a discriminated union of tagged tuples (`["Ctor", …]`), exactly the runtime arrays.
dtsSum :: Array String -> Type -> String
dtsSum known t =
  let
    tvars = collectTvars known (concatMap _.fields t.variants)
    variants = case joinWith " | " (map (dtsVariant known tvars) t.variants) of
      "" -> "never"
      vs -> vs
  in
    "export type " <> t.name <> generics tvars <> " = " <> variants <> ";"

dtsVariant :: Array String -> Array String -> Variant -> String
dtsVariant known tvars v = case v.fields of
  [] -> "[" <> dquote v.ctor <> "]"
  fs -> "[" <> dquote v.ctor <> ", " <> joinWith ", " (map (\f -> tsType known tvars f.ty) fs) <> "]"

-- a struct → a `{__struct__: "Name", …}` interface with a discriminant literal.
dtsStruct :: Array String -> Struct -> String
dtsStruct known s =
  let
    tvars = collectTvars known s.fields
    fields = joinWith " " (mapWithIndex (\i f -> fromMaybe ("f" <> show i) f.label <> ": " <> tsType known tvars f.ty <> ";") s.fields)
  in
    "export interface " <> s.name <> generics tvars <> " { __struct__: " <> dquote s.name <> "; " <> fields <> " }"

dtsConst :: Array String -> Const -> String
dtsConst known c = "export const " <> c.name <> ": " <> tsTypeM known [] c.ty <> ";"

dtsFunc :: Array String -> Func -> String
dtsFunc known f =
  let params = joinWith ", " (map (\p -> p.name <> ": " <> tsTypeM known f.tvars p.ty) f.params)
  in "export function " <> f.name <> generics f.tvars <> "(" <> params <> "): " <> tsTypeM known f.tvars f.ret <> ";"

generics :: Array String -> String
generics tvars = if null tvars then "" else "<" <> joinWith ", " tvars <> ">"

-- the type variables a declaration introduces (every tvar-shaped identifier in its field types,
-- first-appearance order).
collectTvars :: forall r. Array String -> Array { ty :: String | r } -> Array String
collectTvars known fields = nub (concatMap (\f -> scanTvars known f.ty) fields)

scanTvars :: Array String -> String -> Array String
scanTvars known t = filter (isTvar known) (typeWords t)

isTvar :: Array String -> String -> Boolean
isTvar known name =
  upperFirst name && tsPrim name == Nothing && not (elem name tsReserved) && not (elem name known)

-- the JS-valid Rian primitives and their faithful TypeScript carriers (ADR-0064).
tsPrim :: String -> Maybe String
tsPrim t = case t of
  "Int" -> Just "bigint"
  "Int8" -> Just "number"
  "Int16" -> Just "number"
  "Int32" -> Just "number"
  "Int53" -> Just "number"
  "UInt8" -> Just "number"
  "UInt16" -> Just "number"
  "UInt32" -> Just "number"
  "Float32" -> Just "number"
  "Float64" -> Just "number"
  "Bool" -> Just "boolean"
  "String" -> Just "string"
  "Char" -> Just "number"
  "Symbol" -> Just "string"
  "Any" -> Just "unknown"
  _ -> Nothing

-- structural heads handled by name (never a tvar) + the wide ints that map to `unknown`.
tsReserved :: Array String
tsReserved = [ "Int64", "Int128", "UInt64", "UInt128", "Vec", "Fn", "Map", "Dict", "Result", "Option", "Union" ]

-- map a Rian type-string to its faithful TypeScript carrier; anything outside the mapped subset is
-- `unknown` (honest). `known` = declared type-names, `tvars` = in-scope generics.
tsTypeM :: Array String -> Array String -> Maybe String -> String
tsTypeM known tvars = case _ of
  Nothing -> "unknown"
  Just t -> tsType known tvars t

tsType :: Array String -> Array String -> String -> String
tsType known tvars t = tsApp known tvars (TS.normalize (Str.trim t))

tsApp :: Array String -> Array String -> String -> String
tsApp known tvars t =
  if t == "" then "unknown"
  else case tsPrim t of
    Just p -> p
    Nothing ->
      if elem t tvars then t
      else if isJustPrefix "(" t && isJustSuffix ")" t then tsTuple known tvars t
      else case parseApp t of
        Just (Tuple hd args) -> tsApplication known tvars hd args
        Nothing -> if elem t known then t else "unknown"

-- `Head(arg, …)` → `Just (Head, [arg, …])`, else `Nothing` (a bare name / tuple).
parseApp :: String -> Maybe (Tuple String (Array String))
parseApp t = case Str.indexOf (Str.Pattern "(") t of
  Just i | isJustSuffix ")" t ->
    let
      hd = Str.take i t
      inner = dropLastChar (Str.drop (i + 1) t)
    in
      if identStr hd then Just (Tuple hd (TS.splitTopCommas inner)) else Nothing
  _ -> Nothing

tsTuple :: Array String -> Array String -> String -> String
tsTuple known tvars t = "[" <> joinWith ", " (map (tsType known tvars) (TS.splitTopCommas (innerParens t))) <> "]"

tsApplication :: Array String -> Array String -> String -> Array String -> String
tsApplication known tvars hd args = case hd of
  "Vec" | length args == 1 -> "Array<" <> tsType known tvars (ax 0) <> ">"
  "Option" | length args == 1 -> "[" <> dquote "Some" <> ", " <> tsType known tvars (ax 0) <> "] | [" <> dquote "None" <> "]"
  "Result" | length args == 2 -> "[" <> dquote "ok" <> ", " <> tsType known tvars (ax 0) <> "] | [" <> dquote "error" <> ", " <> tsType known tvars (ax 1) <> "]"
  "Union" | not (null args) -> joinWith " | " (map (tsType known tvars) args)
  "Fn" | not (null args) -> case unsnoc args of
    Just { init, last } -> "(" <> joinWith ", " (mapWithIndex (\i a -> "a" <> show i <> ": " <> tsType known tvars a) init) <> ") => " <> tsType known tvars last
    Nothing -> "unknown"
  _ | (hd == "Map" || hd == "Dict") && length args == 2 ->
    let kts = tsType known tvars (ax 0)
    in if kts == "string" || kts == "number" then "Record<" <> kts <> ", " <> tsType known tvars (ax 1) <> ">" else "unknown"
  _ -> if elem hd known then hd <> "<" <> joinWith ", " (map (tsType known tvars) args) <> ">" else "unknown"
  where
  ax i = fromMaybe "" (index args i)

-- ── tiny string helpers for the .d.mts mapper ──
isJustPrefix :: String -> String -> Boolean
isJustPrefix p s = case Str.stripPrefix (Str.Pattern p) s of
  Just _ -> true
  Nothing -> false

isJustSuffix :: String -> String -> Boolean
isJustSuffix p s = case Str.stripSuffix (Str.Pattern p) s of
  Just _ -> true
  Nothing -> false

dropLastChar :: String -> String
dropLastChar s = Str.take (Str.length s - 1) s

innerParens :: String -> String
innerParens s = dropLastChar (Str.drop 1 s)

upperFirst :: String -> Boolean
upperFirst s = case head (toCharArray s) of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

-- a non-empty identifier: first char a letter/`_`, the rest word chars.
identStr :: String -> Boolean
identStr s = case uncons (toCharArray s) of
  Just { head: c, tail } -> (isAlpha c || c == '_') && allWord (snoc tail c)
  Nothing -> false
  where
  isAlpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  isWord c = isAlpha c || (c >= '0' && c <= '9') || c == '_'
  allWord = foldl (\acc x -> acc && isWord x) true

-- | The `js` parity unit: the compiled ECMAScript module for `src`.
compileSexpr :: String -> String
compileSexpr = compile

-- | The `jsdts` parity unit: the TypeScript `.d.mts` sidecar for `src`.
compileTypesSexpr :: String -> String
compileTypesSexpr = compileTypes
