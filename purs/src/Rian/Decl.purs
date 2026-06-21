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
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (elem, foldMap, foldl)
import Data.List (List(..), (:))
import Data.List as List
import Data.Maybe (Maybe(..), fromJust)
import Data.String (Pattern(..)) as Str
import Data.String as Str
import Data.String.CodePoints as CP
import Data.String.Common (joinWith, trim)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Rian.IR (Field, Prog, Struct, Type, Variant)
import Rian.Lexer (detokenize, tokenize)
import Rian.Token (Token(..))
import Rian.TypeStr as TypeStr

-- | Parse declaration source into the whole-program IR (the `assemble` path, before the
-- | program-wide tail passes).
-- @rian_sig pub def parseToProg(src val String) Prog
parseToProg :: String -> Prog
parseToProg src = assemble (splitDecls (List.fromFoldable (tokenize src)))

--------------------------------------------------------------------------------
-- Declaration splitting (token stream → raw decls)
--------------------------------------------------------------------------------

data RawDecl
  = DType String Boolean (Maybe String)
  | DStruct String Boolean (Maybe String)

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
takeDecl (TAnnot a : _) = stage2 ("annotation `@" <> a <> "`")
takeDecl (TKw "pub" : rest) = let Tuple decl rest' = takeDecl rest in Tuple (markPub decl) rest'
takeDecl (TKw "type" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DType (detok toks) false Nothing) rest'
takeDecl (TKw "struct" : rest) = let Tuple toks rest' = takeType rest Nil in Tuple (DStruct (detok toks) false Nothing) rest'
takeDecl (TKw k : _) = stage2 ("declaration `" <> k <> "`")
takeDecl other = unsafeCrashWith ("Decl: expected a declaration, got " <> here other)

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

markPub :: RawDecl -> RawDecl
markPub (DType s _ d) = DType s true d
markPub (DStruct s _ d) = DStruct s true d

detok :: List Token -> String
detok = detokenize <<< Array.fromFoldable

--------------------------------------------------------------------------------
-- Assemble (raw decls → IR)
--------------------------------------------------------------------------------

assemble :: List RawDecl -> Prog
assemble decls =
  { types: Array.mapMaybe typeOf arr
  , structs: Array.mapMaybe structOf arr
  }
  where
  arr = Array.fromFoldable decls
  typeOf (DType s p d) = Just (parseType s p d)
  typeOf _ = Nothing
  structOf (DStruct s p d) = Just (parseStruct s p d)
  structOf _ = Nothing

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
progSexpr prog = joinWith "\n" (map typeSexpr prog.types <> map structSexpr prog.structs)

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
