-- | Declaration parser (ADR-0031) — the PureScript port of `Rian.Decl` (lib/rian/decl.ex),
-- | ADR-0084 Phase 2/3. Token-driven recursive descent over `Rian.Lexer.tokenize`: each
-- | declaration's tokens are detokenized to a string, then parsed into the `Rian.IR` records.
-- |
-- | **Staged port.** This covers the **data-type declarations** — `type` (sum) and `struct`
-- | (product), with `@doc` and `pub` — exercising the structural core (split-decls, the
-- | `[label] [cap] Type` field grammar, union-type fields). The heavy forms raise a clear
-- | "stage 2" message and are excluded from the corpus: `def` (signatures/clauses/bodies/
-- | `forall`), `mod`, `const`, `alias`, `range`, `opaque`/`abstract`, `use`, `protocol`/`impl`,
-- | `macro`, and the program-wide tail passes (interpolation / stdlib / infer-local — they
-- | need the unported `Check`/`InferLocal`/`Protocol`). Type strings are ASCII, so the string
-- | helpers use the standard (byte-wise-on-purerl, but ASCII-safe) `Data.String` ops.
module Rian.Decl
  ( parseToProg
  , progSexpr
  , declSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NEA
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (elem, foldMap, foldl)
import Data.Int as Int
import Data.List (List(..), (:))
import Data.List as List
import Data.Maybe (Maybe(..), fromJust, fromMaybe, isJust)
import Data.String (Pattern(..)) as Str
import Data.String as Str
import Data.String.CodePoints as CP
import Data.String.Common (joinWith, trim)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Rian.IR (Cap(..), Clause, Const, ExtSpec(..), Field, Func, Mod, Opaque, Param, Prog, Range, Struct, Type, Use, Variant)
import Rian.Lexer (detokenize, exprTokens, tokenize)
import Rian.Pratt (Pat, parsePats, sexprPat)
import Rian.Pratt as P
import Rian.Token (Token(..))
import Rian.TypeStr as TypeStr

-- | Parse declaration source into the whole-program IR (the `assemble` path, before the
-- | program-wide tail passes).
-- @rian_sig pub def parseToProg(src val String) Prog
parseToProg :: String -> Prog
parseToProg src =
  let
    decls = splitDecls (List.fromFoldable (tokenize src))
    aliases = collectAliases decls
    top = assembleScope decls aliases
  in
    if not (Array.null top.consts) then unsafeCrashWith "Decl: `const` must appear inside a `mod`"
    else if not (Array.null top.uses) then unsafeCrashWith "Decl: `use` must appear inside a `mod`"
    else
      { types: top.types
      , ranges: top.ranges
      , opaques: top.opaques
      , structs: top.structs
      , funcs: top.funcs
      , mods: buildMods decls aliases
      }

type Aliases = Array (Tuple String String)

-- one scope's IR (top level, or a module body) before the program-wide tail passes.
type Scope =
  { types :: Array Type
  , ranges :: Array Range
  , opaques :: Array Opaque
  , structs :: Array Struct
  , funcs :: Array Func
  , consts :: Array Const
  , uses :: Array Use
  }

buildMods :: List RawDecl -> Aliases -> Array Mod
buildMods decls aliases = Array.mapMaybe modOf (Array.fromFoldable decls)
  where
  modOf (DMod name inner doc) =
    let
      scoped = collectAliases inner <> aliases
      s = assembleScope inner scoped
    in
      Just
        { name
        , uses: s.uses
        , types: s.types
        , ranges: s.ranges
        , opaques: s.opaques
        , structs: s.structs
        , consts: s.consts
        , funcs: s.funcs
        , doc
        }
  modOf _ = Nothing

--------------------------------------------------------------------------------
-- Declaration splitting (token stream → raw decls)
--------------------------------------------------------------------------------

-- a raw `def` (pre-grouping): params/ret/guard/body are detokenized source strings.
type RawDef =
  { name :: String
  , params :: String
  , ret :: Maybe String
  , guard :: Maybe String
  , body :: Maybe String
  , pub :: Boolean
  , tvars :: Array String
  , bounds :: Array (Tuple String (Array String))
  , doc :: Maybe String
  , externals :: Array (Tuple String ExtSpec)
  }

data RawDecl
  = DType String Boolean (Maybe String)
  | DStruct String Boolean (Maybe String)
  | DDef RawDef
  | DConst String Boolean (Maybe String)
  | DUse String
  | DAlias String
  | DRange String Boolean (Maybe String)
  | DOpaque String Boolean (Maybe String)
  | DMod String (List RawDecl) (Maybe String)

declKws :: Array String
declKws =
  [ "type", "def", "struct", "alias", "mod", "pub", "const", "macro", "use"
  , "import", "protocol", "impl", "opaque", "abstract"
  ]

splitDecls :: List Token -> List RawDecl
splitDecls Nil = Nil
splitDecls (TNl : rest) = splitDecls rest
splitDecls toks = let Tuple decl rest = takeDecl toks in decl : splitDecls rest

takeDecl :: List Token -> Tuple RawDecl (List Token)
takeDecl (TAnnot a : TStr doc : rest)
  | a `elem` [ "doc", "moduledoc", "typedoc" ] =
      let Tuple decl rest' = takeDecl (skipNl rest) in Tuple (attachDoc doc decl) rest'
-- `@external(:target, spec)` — a target-scoped FFI body (ADR-0068); one or more precede a
-- bodiless `def`, attaching a per-target host body to it.
takeDecl (TAnnot "external" : TLparen : rest) =
  let
    Tuple argToks rest' = takeParens rest 0 Nil
    Tuple target spec = parseExternal argToks
    Tuple decl rest'' = takeDecl (skipNl rest')
  in
    Tuple (attachExternal decl target spec) rest''
takeDecl (TAnnot "external" : _) =
  unsafeCrashWith "Decl: expected `@external(:target, \"host expression\")`"
takeDecl (TAnnot a : _) = stage2 ("annotation `@" <> a <> "`")
takeDecl (TKw "pub" : rest) = let Tuple decl rest' = takeDecl rest in Tuple (markPub decl) rest'
takeDecl (TKw "type" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DType (detok toks) false Nothing) rest'
takeDecl (TKw "struct" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DStruct (detok toks) false Nothing) rest'
takeDecl (TKw "def" : rest) = let Tuple raw rest' = takeDef rest in Tuple (DDef raw) rest'
takeDecl (TKw "const" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DConst (detok toks) false Nothing) rest'
takeDecl (TKw "use" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DUse (detok toks)) rest'
takeDecl (TKw "alias" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DAlias (detok toks)) rest'
takeDecl (TKw "range" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DRange (detok toks) false Nothing) rest'
takeDecl (TKw "opaque" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DOpaque (detok toks) false Nothing) rest'
takeDecl (TKw "mod" : TId name : TKw "do" : rest) =
  let Tuple inner rest' = takeModBody rest Nil in Tuple (DMod name inner Nothing) rest'
takeDecl (TKw "mod" : _) = unsafeCrashWith "Decl: expected `mod Name do … end`"
takeDecl (TKw k : _) = stage2 ("declaration `" <> k <> "`")
takeDecl other = unsafeCrashWith ("Decl: expected a declaration, got " <> here other)

-- collect a `mod` body declaration-by-declaration up to its closing `end`.
takeModBody :: List Token -> List RawDecl -> Tuple (List RawDecl) (List Token)
takeModBody (TNl : rest) acc = takeModBody rest acc
takeModBody (TKw "end" : rest) acc = Tuple (List.reverse acc) rest
takeModBody Nil _ = unsafeCrashWith "Decl: `mod` body not closed by `end`"
takeModBody toks acc = let Tuple decl rest = takeDecl toks in takeModBody rest (decl : acc)

-- collect a declaration's tokens up to the next declaration boundary (drops the newlines).
takeType :: List Token -> List Token -> Tuple (List Token) (List Token)
takeType Nil acc = Tuple (List.reverse acc) Nil
takeType (TNl : rest) acc =
  if rest == Nil || declBoundary rest then Tuple (List.reverse acc) rest
  else takeType rest acc
takeType (t : rest) acc = takeType rest (t : acc)

declBoundary :: List Token -> Boolean
declBoundary (TKw "end" : _) = true
declBoundary (TAnnot _ : _) = true
declBoundary (TKw k : _) = k `elem` declKws
declBoundary _ = false

skipNl :: List Token -> List Token
skipNl (TNl : rest) = skipNl rest
skipNl toks = toks

attachDoc :: String -> RawDecl -> RawDecl
attachDoc doc (DType s p _) = DType s p (Just doc)
attachDoc doc (DStruct s p _) = DStruct s p (Just doc)
attachDoc doc (DDef r) = DDef (r { doc = Just doc })
attachDoc doc (DConst s p _) = DConst s p (Just doc)
attachDoc doc (DRange s p _) = DRange s p (Just doc)
attachDoc doc (DOpaque s p _) = DOpaque s p (Just doc)
attachDoc doc (DMod n inner _) = DMod n inner (Just doc)
attachDoc _ d = d

markPub :: RawDecl -> RawDecl
markPub (DType s _ d) = DType s true d
markPub (DStruct s _ d) = DStruct s true d
markPub (DDef r) = DDef (r { pub = true })
markPub (DConst s _ d) = DConst s true d
markPub (DRange s _ d) = DRange s true d
markPub (DOpaque s _ d) = DOpaque s true d
markPub _ = unsafeCrashWith "Decl: `pub` may only precede `def` / `type` / `struct` / `const`"

detok :: List Token -> String
detok = detokenize <<< Array.fromFoldable

--------------------------------------------------------------------------------
-- Assemble (raw decls → IR)
--------------------------------------------------------------------------------

assembleScope :: List RawDecl -> Aliases -> Scope
assembleScope decls aliases =
  { types: map (substType aliases) (Array.mapMaybe typeOf arr)
  , ranges: Array.mapMaybe rangeOf arr
  , opaques: Array.mapMaybe opaqueOf arr
  , structs: map (substStruct aliases) (Array.mapMaybe structOf arr)
  , funcs: map (substFunc aliases) (map (buildFunc <<< NEA.toArray) (Array.groupBy sameFunc (Array.mapMaybe defOf arr)))
  , consts: map (substConst aliases) (Array.mapMaybe constOf arr)
  , uses: Array.mapMaybe useOf arr
  }
  where
  arr = Array.fromFoldable decls
  typeOf (DType s p d) = Just (parseType s p d)
  typeOf _ = Nothing
  structOf (DStruct s p d) = Just (parseStruct s p d)
  structOf _ = Nothing
  defOf (DDef r) = Just r
  defOf _ = Nothing
  constOf (DConst s p d) = Just (parseConst s p d)
  constOf _ = Nothing
  useOf (DUse s) = Just (parseUse s)
  useOf _ = Nothing
  rangeOf (DRange s p d) = Just (parseRange s p d)
  rangeOf _ = Nothing
  opaqueOf (DOpaque s p d) = Just (parseOpaque s p d)
  opaqueOf _ = Nothing
  sameFunc a b = a.name == b.name && rawArity a == rawArity b

--------------------------------------------------------------------------------
-- alias collection + substitution
--------------------------------------------------------------------------------

-- alias synonyms plus `range` names — both substitute out of type positions (a range name
-- resolves to its ordinal `base`, ADR-0036 "representation, not newtype").
collectAliases :: List RawDecl -> Aliases
collectAliases decls = Array.mapMaybe aliasOf arr <> Array.mapMaybe rangeAlias arr
  where
  arr = Array.fromFoldable decls
  aliasOf (DAlias s) = Just (parseAlias s)
  aliasOf _ = Nothing
  rangeAlias (DRange s p d) = let r = parseRange s p d in Just (Tuple r.name r.base)
  rangeAlias _ = Nothing

parseAlias :: String -> Tuple String String
parseAlias text = case splitOnce ":=" text of
  Just { left, right } -> Tuple (stripTypeParams left) right
  Nothing -> unsafeCrashWith ("Decl: alias needs `:=`: " <> text)

-- whole-word substitution of every alias name in a type string (transitive to a fixpoint).
substTypeStr :: Aliases -> String -> String
substTypeStr aliases s =
  let resolved = foldl (\acc a -> wholeWordReplace (fst a) (snd a) acc) s aliases
  in if resolved == s then resolved else substTypeStr aliases resolved

wholeWordReplace :: String -> String -> String -> String
wholeWordReplace name val s = joinWith "" (map (\t -> if t == name then val else t) (splitWords s))

-- split into maximal word tokens (`[A-Za-z0-9_]+`) and single non-word-char tokens.
splitWords :: String -> Array String
splitWords s = flush (foldl step { cur: [], acc: [] } (toCps s))
  where
  step st c
    | isWordCp c = st { cur = Array.snoc st.cur c }
    | otherwise = { cur: [], acc: st.acc <> wordOf st.cur <> [ fromCps [ c ] ] }
  flush st = st.acc <> wordOf st.cur
  wordOf [] = []
  wordOf w = [ fromCps w ]
  isWordCp c = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95

substType :: Aliases -> Type -> Type
substType aliases t = t { variants = map (substVariant aliases) t.variants }

substVariant :: Aliases -> Variant -> Variant
substVariant aliases v = v { fields = map (substField aliases) v.fields }

substField :: Aliases -> Field -> Field
substField aliases f = f { ty = substTypeStr aliases f.ty }

substStruct :: Aliases -> Struct -> Struct
substStruct aliases s = s { fields = map (substField aliases) s.fields }

substFunc :: Aliases -> Func -> Func
substFunc aliases f =
  f
    { params = map (\p -> p { ty = map (substTypeStr aliases) p.ty }) f.params
    , ret = map (substTypeStr aliases) f.ret
    }

substConst :: Aliases -> Const -> Const
substConst aliases c = c { ty = map (substTypeStr aliases) c.ty }

--------------------------------------------------------------------------------
-- const / use
--------------------------------------------------------------------------------

parseConst :: String -> Boolean -> Maybe String -> Const
parseConst text pub doc = case splitOnce ":=" text of
  Just { left: decl, right: value } -> case wordsWs (collapseParens decl) of
    [ name, ty ] -> { name, ty: Just ty, value, pub, doc }
    [ name ] -> { name, ty: inferConstType value, value, pub, doc }
    _ -> unsafeCrashWith ("Decl: const needs `NAME [Type] := value`: " <> text)
  Nothing -> unsafeCrashWith ("Decl: const needs `:=`: " <> text)

-- infer a const's type from its literal value (the value is always a literal).
inferConstType :: String -> Maybe String
inferConstType value = literalType (P.parse value)

literalType :: P.Surface -> Maybe String
literalType (P.SNum n) = Just (if contains "." n then "Float64" else "Int53")
literalType (P.SStr _) = Just "String"
literalType (P.SStrInterp _) = Just "String"
literalType (P.SAtom _) = Just "Symbol"
literalType (P.SId b)
  | b == "true" || b == "false" = Just "Bool"
literalType (P.SListLit es _) = case Array.head es of
  Just e -> map (\t -> "Vec(" <> t <> ")") (literalType e)
  Nothing -> Nothing
literalType _ = Nothing

--------------------------------------------------------------------------------
-- range / opaque
--------------------------------------------------------------------------------

parseRange :: String -> Boolean -> Maybe String -> Range
parseRange text pub doc = case splitOnce ":=" text of
  Just { left, right } ->
    let b = parseBounds (trim right)
    in { name: stripTypeParams left, base: b.base, lo: b.lo, hi: b.hi, pub, doc }
  Nothing -> unsafeCrashWith ("Decl: range declaration needs `:=`: " <> text)

parseBounds :: String -> { lo :: Int, hi :: Int, base :: String }
parseBounds text = case splitFirst ".." text of
  Just { left: loS, right: hiS } ->
    let
      lo = parseOrdinal (trim loS)
      hi = parseOrdinal (trim hiS)
    in
      if lo.kind /= hi.kind then unsafeCrashWith ("Decl: range bounds must share a base: " <> text)
      else if lo.val > hi.val then unsafeCrashWith ("Decl: empty/inverted range (need lo <= hi): " <> text)
      else { lo: lo.val, hi: hi.val, base: if lo.kind == "char" then "Char" else "Int64" }
  Nothing -> unsafeCrashWith ("Decl: range needs `lo..hi`: " <> text)

-- an ordinal bound: a `Char` literal → {codepoint, char}; else an integer.
parseOrdinal :: String -> { val :: Int, kind :: String }
parseOrdinal s
  | startsWithStr "'" s = case List.fromFoldable (exprTokens s) of
      (TChar cp : Nil) -> { val: cp, kind: "char" }
      _ -> unsafeCrashWith ("Decl: invalid Char bound: " <> s)
  | otherwise = case Int.fromString (Str.replaceAll (Str.Pattern " ") (Str.Replacement "") s) of
      Just n -> { val: n, kind: "int" }
      Nothing -> unsafeCrashWith ("Decl: invalid integer bound: " <> s)

parseOpaque :: String -> Boolean -> Maybe String -> Opaque
parseOpaque text pub doc = case splitOnce ":=" text of
  Just { left, right } ->
    { name: stripTypeParams left, base: collapseParens (trim right), pub, doc, ops: [], casts: [] }
  Nothing -> unsafeCrashWith ("Decl: opaque declaration needs `:=`: " <> text)

parseUse :: String -> Use
parseUse text =
  let s = collapseDots (collapseParens text)
  in case extractParens s of
    Just { name: path, inside, rest } ->
      if rest == "" then { path: trimTrailingDot path, names: splitTop ',' inside }
      else unsafeCrashWith ("Decl: trailing tokens after use `" <> text <> "`: " <> rest)
    Nothing -> { path: s, names: [] }

trimTrailingDot :: String -> String
trimTrailingDot s = fromMaybe s (Str.stripSuffix (Str.Pattern ".") s)

-- collapse whitespace adjacent to `.` (the `\s*\.\s*` → `.` rewrite for `use` paths).
collapseDots :: String -> String
collapseDots s = fromCps (Array.reverse (go (toCps s) [] false))
  where
  go cs out skip = case Array.uncons cs of
    Nothing -> out
    Just { head: c, tail }
      | c == 46 -> go tail (Array.cons 46 (Array.dropWhile isWs out)) true
      | isWs c -> if skip then go tail out true else go tail (Array.cons c out) false
      | otherwise -> go tail (Array.cons c out) false
  isWs c = c == 32 || c == 9

--------------------------------------------------------------------------------
-- `def` token parsing (→ RawDef)
--------------------------------------------------------------------------------

takeDef :: List Token -> Tuple RawDef (List Token)
takeDef (TId name : rest) =
  let Tuple paramToks rest' = balancedParens rest
  in takeHead name (detok paramToks) rest' Nil
takeDef other = unsafeCrashWith ("Decl: expected a function name after `def`: " <> here other)

balancedParens :: List Token -> Tuple (List Token) (List Token)
balancedParens (TLparen : rest) = takeParens rest 0 Nil
balancedParens other = unsafeCrashWith ("Decl: expected `(` after the function name: " <> here other)

takeParens :: List Token -> Int -> List Token -> Tuple (List Token) (List Token)
takeParens (TRparen : rest) 0 acc = Tuple (List.reverse acc) rest
takeParens (TLparen : rest) d acc = takeParens rest (d + 1) (TLparen : acc)
takeParens (TRparen : rest) d acc = takeParens rest (d - 1) (TRparen : acc)
takeParens (t : rest) d acc = takeParens rest d (t : acc)
takeParens Nil _ _ = unsafeCrashWith "Decl: unbalanced `(` in the parameter list"

-- collect the head (return type / `when` guard) then the body: `:= expr` (to newline), a
-- bodiless signature, or — staged out — a `<nl> … end` block body.
takeHead :: String -> String -> List Token -> List Token -> Tuple RawDef (List Token)
takeHead name params (TOp ":=" : rest) head =
  let Tuple bodyToks rest' = takeLine rest Nil 0
  in Tuple (defRaw name params head (Just (detok bodyToks))) rest'
takeHead name params (TNl : rest) head =
  if rest == Nil || declBoundary rest then Tuple (defRaw name params head Nothing) rest
  else
    let Tuple blockToks rest' = takeBlock rest 1 Nil
    in Tuple (defRaw name params head (Just (detokBlock blockToks))) rest'
takeHead name params Nil head = Tuple (defRaw name params head Nothing) Nil
takeHead name params (t : rest) head = takeHead name params rest (t : head)

-- the closed target vocabulary (`Rian.Reach.targets()`, unported — hardcoded, ADR-0058 §2).
extTargets :: Array String
extTargets = [ "ex", "rs", "js", "jvm" ]

-- `@external(:target, spec)` args → `{target, spec}`. The target is validated; the spec is a
-- raw host-expression string, a function reference (`Mod.fun` / `:erlang.fun`), or a foreign
-- file reference (`"path", "fun"`). FFI is trusted, not parsed beyond its shape (ADR-0068).
parseExternal :: List Token -> Tuple String ExtSpec
parseExternal (TOp ":" : TId t : TComma : rest) =
  if t `elem` extTargets then Tuple t (parseExternalSpec rest)
  else unsafeCrashWith ("Decl: unknown target `:" <> t <> "` in `@external`; known: ex, rs, js, jvm")
parseExternal _ = unsafeCrashWith "Decl: `@external` takes a target atom and a spec: `@external(:js, \"expr\")`"

parseExternalSpec :: List Token -> ExtSpec
parseExternalSpec (TStr s : Nil) = ExtStr s
parseExternalSpec (TStr path : TComma : TStr fun : Nil) = ExtFile path fun
parseExternalSpec (TOp ":" : TId m : rest) = ExtRef (Array.cons m (dottedTail rest)) true
parseExternalSpec (TId m : rest) = ExtRef (Array.cons m (dottedTail rest)) false
parseExternalSpec _ =
  unsafeCrashWith "Decl: `@external` spec must be a string `\"expr\"` or a reference `Mod.fun`/`:erlang.fun`"

dottedTail :: List Token -> Array String
dottedTail (TOp "." : TId x : rest) = Array.cons x (dottedTail rest)
dottedTail Nil = []
dottedTail _ = unsafeCrashWith "Decl: malformed `@external` reference (expected `Mod.fun`)"

attachExternal :: RawDecl -> String -> ExtSpec -> RawDecl
attachExternal (DDef r) target spec
  | isJust r.body = unsafeCrashWith ("Decl: `" <> r.name <> "`: `@external` cannot accompany a portable body")
  | isJust (Array.find (\(Tuple k _) -> k == target) r.externals) =
      unsafeCrashWith ("Decl: `" <> r.name <> "`: duplicate `@external(:" <> target <> ", …)`")
  | otherwise = DDef (r { externals = Array.snoc r.externals (Tuple target spec) })
attachExternal _ _ _ = unsafeCrashWith "Decl: `@external(…)` may only precede a `def`"

-- A `do … end` block body: collect the tokens up to the matching `end` (depth-counted;
-- an atom/field keyword `:do`/`x.end` does not move the counter), then `block_seps`
-- rewrites a top-level newline to a `;` statement separator.
takeBlock :: List Token -> Int -> List Token -> Tuple (List Token) (List Token)
takeBlock (TKw k : rest) depth acc
  | accHeadColonDot acc = takeBlock rest depth (TKw k : acc)
takeBlock (TKw "do" : rest) depth acc = takeBlock rest (depth + 1) (TKw "do" : acc)
takeBlock (TKw "end" : rest) 1 acc = Tuple (List.reverse acc) rest
takeBlock (TKw "end" : rest) depth acc = takeBlock rest (depth - 1) (TKw "end" : acc)
takeBlock (t : rest) depth acc = takeBlock rest depth (t : acc)
takeBlock Nil _ _ = unsafeCrashWith "Decl: block body not closed by `end`"

detokBlock :: List Token -> String
detokBlock tokens = detok (blockSeps tokens 0 0 0 Nil)

-- `d` = `do`/`end` depth, `w` = open `with`-headers (between `with` and its `do`, where
-- newlines separate comma-joined clauses, not statements), `p` = bracket depth. A
-- top-level newline (all zero) becomes a `;`; any other newline is dropped.
blockSeps :: List Token -> Int -> Int -> Int -> List Token -> List Token
blockSeps Nil _ _ _ acc = List.reverse acc
blockSeps (TKw k : r) d w p acc
  | accHeadColonDot acc = blockSeps r d w p (TKw k : acc)
blockSeps (TKw "with" : r) d w p acc = blockSeps r d (w + 1) p (TKw "with" : acc)
blockSeps (TKw "do" : r) d w p acc
  | w > 0 = blockSeps r (d + 1) (w - 1) p (TKw "do" : acc)
  | otherwise = blockSeps r (d + 1) w p (TKw "do" : acc)
blockSeps (TKw "end" : r) d w p acc = blockSeps r (d - 1) w p (TKw "end" : acc)
blockSeps (TNl : r) 0 0 0 acc = blockSeps r 0 0 0 (TSemi : acc)
blockSeps (TNl : r) d w p acc = blockSeps r d w p acc
blockSeps (t : r) d w p acc
  | isOpen t = blockSeps r d w (p + 1) (t : acc)
  | isClose t = blockSeps r d w (max (p - 1) 0) (t : acc)
  | otherwise = blockSeps r d w p (t : acc)

defRaw :: String -> String -> List Token -> Maybe String -> RawDef
defRaw name params headRev body =
  let
    headStr = detok (List.reverse headRev)
    sf = splitForall headStr
    ph = parseHead sf.ret
    ret = map (TypeStr.normalize <<< collapseParens) ph.ret
  in
    { name, params, ret, guard: ph.guard, body, pub: false, tvars: sf.tvars, bounds: sf.bounds, doc: Nothing, externals: [] }

-- a `:=` body: a newline ends it unless the body plainly continues (inside unbalanced
-- brackets, a `do…end`, or across a trailing/leading continuation operator).
takeLine :: List Token -> List Token -> Int -> Tuple (List Token) (List Token)
takeLine Nil acc _ = Tuple (List.reverse acc) Nil
takeLine (TNl : rest) Nil depth =
  if declBoundary rest then Tuple Nil rest else takeLine rest Nil depth
takeLine (TKw k : rest) acc depth
  | accHeadColonDot acc = takeLine rest (TKw k : acc) depth
takeLine (TKw "do" : rest) acc depth = takeLine rest (TKw "do" : acc) (depth + 1)
takeLine (TKw "end" : rest) acc depth = takeLine rest (TKw "end" : acc) (max (depth - 1) 0)
takeLine (TNl : rest) acc depth =
  if depth > 0 || lineContinues acc rest then takeLine rest acc depth
  else Tuple (List.reverse acc) rest
takeLine (t : rest) acc depth
  | isOpen t = takeLine rest (t : acc) (depth + 1)
  | isClose t = takeLine rest (t : acc) (max (depth - 1) 0)
  | otherwise = takeLine rest (t : acc) depth

accHeadColonDot :: List Token -> Boolean
accHeadColonDot (TOp ":" : _) = true
accHeadColonDot (TOp "." : _) = true
accHeadColonDot _ = false

isOpen :: Token -> Boolean
isOpen t = t `elem` [ TLparen, TLbracket, TLbrace, TMapopen, TBitopen ]

isClose :: Token -> Boolean
isClose t = t `elem` [ TRparen, TRbracket, TRbrace, TBitclose ]

contOps :: Array String
contOps =
  [ "+", "-", "*", "/", "<", ">", "<=", ">=", "==", "!=", "<>", "|>", "and", "or", "in", "rem", "div" ]

lineContinues :: List Token -> List Token -> Boolean
lineContinues acc rest = trailing acc || leading rest
  where
  trailing (TOp o : _) = o `elem` contOps
  trailing _ = false
  leading (TOp o : _) = o `elem` contOps
  leading _ = false

-- `Ret forall T, U: Bound` → split off the binder list.
splitForall :: String -> { ret :: String, tvars :: Array String, bounds :: Array (Tuple String (Array String)) }
splitForall head = case Str.indexOf (Str.Pattern " forall ") head of
  Nothing -> { ret: head, tvars: [], bounds: [] }
  Just i ->
    let
      ret = Str.take i head
      binders = Str.drop (i + Str.length " forall ") head
      parsed = parseBinders binders
    in
      { ret, tvars: map fst parsed, bounds: Array.filter (\b -> not (Array.null (snd b))) parsed }

parseBinders :: String -> Array (Tuple String (Array String))
parseBinders binders = Array.filter (\b -> fst b /= "") (map parseBinder (splitTop ',' binders))

parseBinder :: String -> Tuple String (Array String)
parseBinder b = case splitFirst ":" b of
  Nothing -> Tuple (trim b) []
  Just { left: name, right: bounds } ->
    Tuple (trim name) (Array.filter (_ /= "") (map trim (Str.split (Str.Pattern "+") bounds)))

parseHead :: String -> { ret :: Maybe String, guard :: Maybe String }
parseHead head
  | head == "" = { ret: Nothing, guard: Nothing }
  | startsWithStr "when " head = { ret: Nothing, guard: Just (trim (dropPrefix "when " head)) }
  | contains " when " head =
      case splitFirst " when " head of
        Just { left, right } -> { ret: nz left, guard: Just (trim right) }
        Nothing -> { ret: nz head, guard: Nothing }
  | otherwise = { ret: nz head, guard: Nothing }

--------------------------------------------------------------------------------
-- build_func (raw defs → Func)
--------------------------------------------------------------------------------

buildFunc :: Array RawDef -> Func
buildFunc group = case Array.uncons group of
  Nothing -> unsafeCrashWith "Decl: empty function group"
  Just { head: first, tail: rest } ->
    if first.body == Nothing then
      if not (Array.null first.externals) && Array.null rest then externalFunc first
      else if Array.null rest then
        unsafeCrashWith ("Decl: function `" <> first.name <> "` has a signature but no clauses")
      else multiClauseFunc first rest
    else if Array.null rest then singleClauseFunc first
    else unsafeCrashWith ("Decl: cannot group clauses of `" <> first.name <> "`")

-- a bodiless `def` carrying only `@external(:target, …)` bodies (ADR-0068): no portable
-- clauses; `Rian.Reach` reads the externals for an honest target set.
externalFunc :: RawDef -> Func
externalFunc sig =
  let params = boundaryParams (parseParams sig.params) in
  { name: sig.name
  , params
  , ret: reqRet sig
  , clauses: []
  , externals: sig.externals
  , pub: sig.pub
  , tvars: sig.tvars
  , bounds: sig.bounds
  , doc: sig.doc
  }

-- bodiless signature + pattern clauses.
multiClauseFunc :: RawDef -> Array RawDef -> Func
multiClauseFunc sig clauses =
  let
    params0 = parseParams sig.params
    params = if sig.pub then boundaryParams params0 else params0
  in
    { name: sig.name
    , params
    , ret: reqRet sig
    , clauses: map (clauseOf (Array.length params)) clauses
    , externals: []
    , pub: sig.pub
    , tvars: sig.tvars
    , bounds: sig.bounds
    , doc: sig.doc
    }

-- a single def whose head parameters double as the clause patterns.
singleClauseFunc :: RawDef -> Func
singleClauseFunc d =
  let
    hp = Array.mapWithIndex (\i p -> headParam p i) (splitTop ',' d.params)
    params0 = map _.param hp
    params = if d.pub then boundaryParams params0 else params0
  in
    { name: d.name
    , params
    , ret: reqRet d
    , clauses: [ { pats: map _.pat hp, body: d.body, guard: d.guard } ]
    , externals: []
    , pub: d.pub
    , tvars: d.tvars
    , bounds: d.bounds
    , doc: d.doc
    }

clauseOf :: Int -> RawDef -> Clause
clauseOf arity d = case d.body of
  Nothing -> unsafeCrashWith ("Decl: clause of `" <> d.name <> "` has no body")
  Just _ ->
    let pats = parsePats d.params
    in if Array.length pats /= arity then unsafeCrashWith ("Decl: clause has " <> show (Array.length pats) <> " patterns but arity " <> show arity)
       else { pats, body: d.body, guard: d.guard }

reqRet :: RawDef -> Maybe String
reqRet d = case d.ret of
  Just r -> Just r
  Nothing -> if d.pub then unsafeCrashWith ("Decl: public function `" <> d.name <> "` needs a return type") else Nothing

-- on a `pub` boundary an infer-typed param keeps the legacy reading: the name becomes the type.
boundaryParams :: Array Param -> Array Param
boundaryParams = Array.mapWithIndex \i p -> case p.ty of
  Nothing -> p { name = "arg" <> show i, ty = Just p.name }
  _ -> p

parseParams :: String -> Array Param
parseParams str = Array.mapWithIndex build (splitTop ',' str)
  where
  build i p =
    let r = param p
    in { name: fromMaybe ("arg" <> show i) r.name, ty: r.ty, cap: r.cap }

-- a `[cap] name [Type]` parameter → name / cap / type (`Nothing` = infer).
param :: String -> { name :: Maybe String, cap :: Cap, ty :: Maybe String }
param p =
  let
    parts = Array.partition (\t -> t `elem` capNames) (wordsWs (collapseParamParens p))
    cap = case parts.yes of
      [] -> Val
      [ c ] -> capOf c
      _ -> unsafeCrashWith ("Decl: multiple capabilities on `" <> p <> "`")
  in case parts.no of
    [] -> unsafeCrashWith ("Decl: parameter `" <> p <> "` has no name")
    [ tok ] ->
      if typeToken tok then { name: Nothing, cap, ty: Just (TypeStr.normalize tok) }
      else { name: Just tok, cap, ty: Nothing }
    toks -> case Array.uncons toks of
      Just { head: first, tail: more } ->
        if typeToken first then { name: Nothing, cap, ty: Just (unionType toks p) }
        else { name: Just first, cap, ty: Just (unionType more p) }
      Nothing -> unsafeCrashWith ("Decl: empty parameter `" <> p <> "`")

capNames :: Array String
capNames = caps

capOf :: String -> Cap
capOf "val" = Val
capOf "iso" = Iso
capOf "ref" = Ref
capOf "tag" = Tag
capOf c = unsafeCrashWith ("Decl: unknown capability `" <> c <> "`")

-- one head parameter of a single-clause def → { param, clause pattern }.
headParam :: String -> Int -> { param :: Param, pat :: Pat }
headParam pstr i =
  let t = trim pstr
  in
    if structuralPattern t then patternParam t i
    else if ctorHead t then ctorHeadParam t i
    else
      let r = param t
          nm = fromMaybe ("arg" <> show i) r.name
      in { param: { name: nm, ty: r.ty, cap: r.cap }, pat: varPat nm }

patternParam :: String -> Int -> { param :: Param, pat :: Pat }
patternParam pstr i = case parsePats pstr of
  [ pat ] -> { param: inferParam i, pat }
  _ -> unsafeCrashWith ("Decl: bad pattern parameter `" <> pstr <> "`")

ctorHeadParam :: String -> Int -> { param :: Param, pat :: Pat }
ctorHeadParam t i = case parsePats t of
  [ pat ] -> { param: inferParam i, pat }
  _ -> unsafeCrashWith ("Decl: bad constructor-head parameter `" <> t <> "`")

inferParam :: Int -> Param
inferParam i = { name: "arg" <> show i, ty: Nothing, cap: Val }

varPat :: String -> Pat
varPat = parsePatOf

-- a single var pattern via the shared parser (so the surface Pat type is constructed there).
parsePatOf :: String -> Pat
parsePatOf s = case parsePats s of
  [ p ] -> p
  _ -> unsafeCrashWith ("Decl: expected a single pattern: " <> s)

-- a head parameter that is unambiguously a destructuring pattern.
structuralPattern :: String -> Boolean
structuralPattern pstr =
  let t = trim pstr
  in startsWithStr "{" t || startsWithStr "[" t || startsWithStr "%" t
       || startsWithStr ":" t || startsWithStr "\"" t || startsWithStr "'" t
       || startsWithStr "^" t || t == "_" || startsDigit t

startsDigit :: String -> Boolean
startsDigit s = case firstCp (dropMinus s) of
  Just c -> c >= 48 && c <= 57
  Nothing -> false
  where
  dropMinus x = fromMaybe x (Str.stripPrefix (Str.Pattern "-") x)

-- a `Foo(args)` clause head: PascalCase name then a parenthesized group.
ctorHead :: String -> Boolean
ctorHead t = case firstCp t of
  Just c | c >= 65 && c <= 90 -> contains "(" t && endsWithStr ")" t
  _ -> false

rawArity :: RawDef -> Int
rawArity d = countParams d.params

countParams :: String -> Int
countParams p = case trim p of
  "" -> 0
  s -> 1 + (foldl step { c: 0, d: 0 } (List.fromFoldable (exprTokens s))).c
  where
  step st t
    | t == TComma && st.d == 0 = st { c = st.c + 1 }
    | isOpen t = st { d = st.d + 1 }
    | isClose t = st { d = st.d - 1 }
    | otherwise = st

-- collapse_param_parens: like collapseParens but keep a space between a lowercase param
-- name and a `(` opening an anonymous tuple type; glue an uppercase type to its `(`.
collapseParamParens :: String -> String
collapseParamParens s = fromCps (Array.reverse (go (toCps s) [] false))
  where
  go cs out skip = case Array.uncons cs of
    Nothing -> out
    Just { head: c, tail }
      | c == 41 || c == 44 -> go tail (Array.cons c (Array.dropWhile isWs out)) true
      | c == 40 -> go tail (Array.cons 40 (glueUpper out)) true
      | isWs c -> if skip then go tail out true else go tail (Array.cons c out) false
      | otherwise -> go tail (Array.cons c out) false
  isWs c = c == 32 || c == 9
  -- drop the whitespace before a `(` iff it follows an uppercase-headed word.
  glueUpper out = case Array.uncons out of
    Just { head: w, tail } | isWs w ->
      let word = Array.takeWhile isWordCp tail
      in case Array.last word of
        Just c | c >= 65 && c <= 90 -> tail
        _ -> out
    _ -> out
  isWordCp c = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95

parseType :: String -> Boolean -> Maybe String -> Type
parseType text pub doc = case splitOnce ":=" text of
  Just { left, right } ->
    { name: stripTypeParams left
    , variants: map variant (splitTop '|' right)
    , pub
    , doc
    }
  Nothing -> unsafeCrashWith ("Decl: type declaration needs `:=`: " <> text)

parseStruct :: String -> Boolean -> Maybe String -> Struct
parseStruct text pub doc = case extractParens text of
  Just { name, inside, rest } ->
    if rest == "" then { name: trim name, fields: fields inside, pub, doc }
    else unsafeCrashWith ("Decl: trailing tokens after struct `" <> text <> "`: " <> rest)
  Nothing -> { name: trim text, fields: [], pub, doc }

variant :: String -> Variant
variant v = case extractParens v of
  Just { name: ctor, inside, rest } ->
    if rest == "" then { ctor: trim ctor, fields: fields inside }
    else unsafeCrashWith ("Decl: trailing tokens after variant `" <> v <> "`: " <> rest)
  Nothing -> { ctor: trim v, fields: [] }

fields :: String -> Array Field
fields inside = case trim inside of
  "" -> []
  s -> map field (splitTop ',' s)

-- a field is `[label] [cap] Type`; the capability is stripped (not stored). A multi-token
-- type is valid only as a value-union (ADR-0083).
field :: String -> Field
field f = case Array.filter (\t -> not (t `elem` caps)) (wordsWs (collapseParens f)) of
  [ ty ] -> { label: Nothing, ty: TypeStr.normalize ty }
  toks -> case Array.uncons toks of
    Just { head: first, tail: more } ->
      if typeToken first then { label: Nothing, ty: unionType toks f }
      else { label: Just first, ty: unionType more f }
    Nothing -> unsafeCrashWith ("Decl: empty field in `" <> f <> "`")

caps :: Array String
caps = [ "val", "iso", "ref", "tag" ]

unionType :: Array String -> String -> String
unionType toks raw = case toks of
  [ tok ] -> TypeStr.normalize tok
  _ ->
    let joined = joinWith " " toks
    in if Array.length (TypeStr.splitTopPipes joined) > 1 then TypeStr.normalize joined
       else unsafeCrashWith ("Decl: bad field `" <> raw <> "`")

typeToken :: String -> Boolean
typeToken s = case firstCp s of
  Just c -> c >= 65 && c <= 90
  Nothing -> false

--------------------------------------------------------------------------------
-- String helpers (ASCII type strings)
--------------------------------------------------------------------------------

splitOnce :: String -> String -> Maybe { left :: String, right :: String }
splitOnce sep s = case Str.indexOf (Str.Pattern sep) s of
  Just i ->
    let p = Str.splitAt i s
    in Just { left: trim p.before, right: trim (Str.drop (Str.length sep) p.after) }
  Nothing -> Nothing

-- split on a single char at bracket depth 0 (`()`/`{}`/`[]`); trims, drops empties.
splitTop :: Char -> String -> Array String
splitTop sepCh s =
  Array.filter (_ /= "") (map (trim <<< fromCps) (Array.snoc res.parts res.cur))
  where
  sepc = fromEnum (CP.codePointFromChar sepCh)
  res = foldl step { parts: [], cur: [], depth: 0 } (toCps s)
  step st c
    | c == sepc && st.depth == 0 = st { parts = Array.snoc st.parts st.cur, cur = [] }
    | c == 40 || c == 123 || c == 91 = st { cur = Array.snoc st.cur c, depth = st.depth + 1 }
    | c == 41 || c == 125 || c == 93 = st { cur = Array.snoc st.cur c, depth = st.depth - 1 }
    | otherwise = st { cur = Array.snoc st.cur c }

-- "name(inside)rest" → { name, inside, rest }; Nothing if no `(`.
extractParens :: String -> Maybe { name :: String, inside :: String, rest :: String }
extractParens s = case splitOnce "(" s of
  Just { left: name, right: afterOpen } ->
    -- splitOnce trimmed; re-derive the untrimmed split for paren matching
    case Str.indexOf (Str.Pattern "(") s of
      Just i ->
        let after = Str.drop (i + 1) s
            r = matchParen (toCps after) 0 []
        in Just { name, inside: fromCps r.inside, rest: trim (fromCps r.rest) }
      Nothing -> Nothing
  Nothing -> case Str.indexOf (Str.Pattern "(") s of
    Just _ -> Nothing
    Nothing -> Nothing

matchParen :: Array Int -> Int -> Array Int -> { inside :: Array Int, rest :: Array Int }
matchParen cs depth acc = case Array.uncons cs of
  Nothing -> { inside: acc, rest: [] }
  Just { head: c, tail }
    | c == 40 -> matchParen tail (depth + 1) (Array.snoc acc 40)
    | c == 41 && depth == 0 -> { inside: acc, rest: tail }
    | c == 41 -> matchParen tail (depth - 1) (Array.snoc acc 41)
    | otherwise -> matchParen tail depth (Array.snoc acc c)

stripTypeParams :: String -> String
stripTypeParams name = case Str.indexOf (Str.Pattern "(") name of
  Just i -> trim (Str.take i name)
  Nothing -> trim name

-- collapse whitespace adjacent to `(`/`)`/`,` (the `\s*([(),])\s*` → `\1` rewrite).
collapseParens :: String -> String
collapseParens s = fromCps (Array.reverse (go (toCps s) [] false))
  where
  go cs out skip = case Array.uncons cs of
    Nothing -> out
    Just { head: c, tail }
      | c == 40 || c == 41 || c == 44 -> go tail (Array.cons c (Array.dropWhile isWs out)) true
      | isWs c -> if skip then go tail out true else go tail (Array.cons c out) false
      | otherwise -> go tail (Array.cons c out) false
  isWs c = c == 32 || c == 9

wordsWs :: String -> Array String
wordsWs = Array.filter (_ /= "") <<< Str.split (Str.Pattern " ")

-- split on the first occurrence of `sep` (no trimming — unlike `splitOnce`).
splitFirst :: String -> String -> Maybe { left :: String, right :: String }
splitFirst sep s = case Str.indexOf (Str.Pattern sep) s of
  Just i -> Just { left: Str.take i s, right: Str.drop (i + Str.length sep) s }
  Nothing -> Nothing

startsWithStr :: String -> String -> Boolean
startsWithStr p s = case Str.stripPrefix (Str.Pattern p) s of
  Just _ -> true
  Nothing -> false

endsWithStr :: String -> String -> Boolean
endsWithStr p s = case Str.stripSuffix (Str.Pattern p) s of
  Just _ -> true
  Nothing -> false

contains :: String -> String -> Boolean
contains p s = case Str.indexOf (Str.Pattern p) s of
  Just _ -> true
  Nothing -> false

dropPrefix :: String -> String -> String
dropPrefix p s = fromMaybe s (Str.stripPrefix (Str.Pattern p) s)

nz :: String -> Maybe String
nz s = if trim s == "" then Nothing else Just (trim s)

--------------------------------------------------------------------------------
-- codepoint helpers
--------------------------------------------------------------------------------

toCps :: String -> Array Int
toCps = map fromEnum <<< CP.toCodePointArray

fromCps :: Array Int -> String
fromCps = CP.fromCodePointArray <<< map (\n -> unsafePartial (fromJust (toEnum n)))

firstCp :: String -> Maybe Int
firstCp s = Array.head (toCps s)

here :: List Token -> String
here Nil = "end of input"
here (TKw k : _) = "keyword `" <> k <> "`"
here (_ : _) = "token"

stage2 :: forall a. String -> a
stage2 what = unsafeCrashWith ("Decl: " <> what <> " is not yet ported (stage 2)")

--------------------------------------------------------------------------------
-- Prog serializer — the `dcl` parity oracle (matches DeclCanon in gen_fixtures.exs)
--------------------------------------------------------------------------------

-- | Parse declaration source and render the canonical s-expression — the `dcl` stream entry.
declSexpr :: String -> String
declSexpr = progSexpr <<< parseToProg

progSexpr :: Prog -> String
progSexpr prog =
  joinWith "\n"
    ( map typeSexpr prog.types
        <> map rangeSexpr prog.ranges
        <> map opaqueSexpr prog.opaques
        <> map structSexpr prog.structs
        <> map funcSexpr prog.funcs
        <> map modSexpr prog.mods
    )

modSexpr :: Mod -> String
modSexpr m =
  "(mod " <> m.name <> docFlag m.doc
    <> foldMap (\u -> " " <> useSexpr u) m.uses
    <> foldMap (\t -> " " <> typeSexpr t) m.types
    <> foldMap (\r -> " " <> rangeSexpr r) m.ranges
    <> foldMap (\o -> " " <> opaqueSexpr o) m.opaques
    <> foldMap (\s -> " " <> structSexpr s) m.structs
    <> foldMap (\c -> " " <> constSexpr c) m.consts
    <> foldMap (\f -> " " <> funcSexpr f) m.funcs
    <> ")"

rangeSexpr :: Range -> String
rangeSexpr r =
  "(range " <> r.name <> pubFlag r.pub <> docFlag r.doc <> " " <> r.base <> " " <> show r.lo <> ".." <> show r.hi <> ")"

opaqueSexpr :: Opaque -> String
opaqueSexpr o =
  "(opaque " <> o.name <> pubFlag o.pub <> docFlag o.doc <> " " <> o.base
    <> foldMap (\op -> " op=" <> op) o.ops
    <> foldMap (\c -> " cast=" <> c) o.casts
    <> ")"

useSexpr :: Use -> String
useSexpr u = "(use " <> u.path <> foldMap (\n -> " " <> n) u.names <> ")"

constSexpr :: Const -> String
constSexpr c =
  "(const " <> c.name <> pubFlag c.pub <> docFlag c.doc <> " " <> tyOf c.ty <> " " <> c.value <> ")"
  where
  tyOf Nothing = "_infer"
  tyOf (Just t) = t

funcSexpr :: Func -> String
funcSexpr f =
  "(func " <> f.name <> pubFlag f.pub <> docFlag f.doc
    <> foldMap (\tv -> " tvar=" <> tv) f.tvars
    <> foldMap (\b -> " bound=" <> fst b <> ":" <> joinWith "+" (snd b)) f.bounds
    <> retFlag f.ret
    <> " (params" <> foldMap paramSexpr f.params <> ")"
    <> foldMap clauseSexpr f.clauses
    <> externalsSexpr f.externals
    <> ")"
  where
  retFlag Nothing = ""
  retFlag (Just r) = " ret=" <> r

externalsSexpr :: Array (Tuple String ExtSpec) -> String
externalsSexpr [] = ""
externalsSexpr ext =
  " (externals" <> foldMap (\(Tuple t s) -> " (ext " <> t <> " " <> extSpecStr s <> ")") (Array.sortWith fst ext) <> ")"

extSpecStr :: ExtSpec -> String
extSpecStr (ExtStr s) = "str:" <> s
extSpecStr (ExtRef parts erl) = "ref:" <> (if erl then ":" else "") <> joinWith "." parts
extSpecStr (ExtFile p f) = "file:" <> p <> "," <> f

paramSexpr :: Param -> String
paramSexpr p = " (param " <> p.name <> " " <> capStr p.cap <> " " <> tyOf p.ty <> ")"
  where
  tyOf Nothing = "_infer"
  tyOf (Just t) = t

capStr :: Cap -> String
capStr Val = "val"
capStr Iso = "iso"
capStr Ref = "ref"
capStr Tag = "tag"

clauseSexpr :: Clause -> String
clauseSexpr c =
  " (clause (" <> joinWith " " (map sexprPat c.pats) <> ")" <> guardOf c.guard <> bodyOf c.body <> ")"
  where
  guardOf Nothing = ""
  guardOf (Just g) = " when=" <> g
  bodyOf Nothing = ""
  bodyOf (Just b) = " body=" <> b

typeSexpr :: Type -> String
typeSexpr t =
  "(type " <> t.name <> pubFlag t.pub <> docFlag t.doc <> foldMap variantSexpr t.variants <> ")"

structSexpr :: Struct -> String
structSexpr s =
  "(struct " <> s.name <> pubFlag s.pub <> docFlag s.doc <> foldMap fieldSexpr s.fields <> ")"

variantSexpr :: Variant -> String
variantSexpr v = " (variant " <> v.ctor <> foldMap fieldSexpr v.fields <> ")"

fieldSexpr :: Field -> String
fieldSexpr f = " (field " <> labelOf f.label <> " " <> f.ty <> ")"
  where
  labelOf Nothing = "_"
  labelOf (Just l) = l

pubFlag :: Boolean -> String
pubFlag true = " pub"
pubFlag false = ""

docFlag :: Maybe String -> String
docFlag Nothing = ""
docFlag (Just d) = " doc=" <> d
