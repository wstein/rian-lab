-- | The single tokenizer for Rian source — the PureScript port of `Rian.Lexer`
-- | (lib/rian/lexer.ex), ADR-0084 Phase 1. It is the foundation the token-driven
-- | declaration parser needs: `do`/`end`/`;` and **significant newlines** become real
-- | tokens here.
-- |
-- | `tokenize` is the full declaration stream (collapsed `TNl` separators, comments
-- | stripped); `exprTokens` is the newline-free expression stream the Pratt parser
-- | consumes; `tokenizeTrivia` keeps comments + uncollapsed newlines for the formatter.
-- | `detokenize` renders a token list back to a re-lexable string.
-- |
-- | Faithful to the Elixir reference (verified by cross-language parity, ADR-0084):
-- | the port is pure — no regex/FFI. The scanner runs over a decoded `List Int` of
-- | Unicode codepoints (purerl's `Data.String.CodePoints.uncons` is byte-wise, so
-- | `toCodePointArray` is the only UTF-8-correct entry), and token payloads are rebuilt
-- | with `fromCodePointArray`. A malformed literal is a lex error via `unsafeCrashWith`,
-- | mirroring the reference's `raise ArgumentError`.
module Rian.Lexer
  ( tokenize
  , exprTokens
  , tokenizeTrivia
  , detokenize
  , detokenizeWith
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (any, elem, foldMap, foldl)
import Data.Int as Int
import Data.List (List(..), (:))
import Data.List as List
import Data.Maybe (Maybe(..), fromJust)
import Data.String.CodePoints as CP
import Data.String.Common (joinWith, toUpper, trim)
import Data.String.Pattern (Pattern(..))
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Rian.Token (Token(..), StrPart(..), isNewline)

--------------------------------------------------------------------------------
-- Vocabulary (mirrors the module attributes in lexer.ex)
--------------------------------------------------------------------------------

opWords :: Array String
opWords = [ "and", "or", "not", "in", "rem", "div" ]

keywords :: Array String
keywords =
  [ "if", "do", "else", "end", "def", "type", "range", "case", "when", "struct"
  , "alias", "mod", "pub", "const", "macro", "use", "with", "for", "protocol"
  , "impl", "opaque", "abstract"
  ]

-- multi-char operators, matched greedily before the single-char ops.
multiOps :: Array String
multiOps =
  [ "->", "..", ":=", "|>", "<>", "<~", "<-", "<=", ">=", "==", "!=", "::", "=>" ]

singleOps :: Array String
singleOps =
  [ "+", "-", "*", "/", "<", ">", ".", "|", ":", "&", "@", "^" ]

--------------------------------------------------------------------------------
-- Codepoints — the scanner works over a decoded `List Int` (`Cs`)
--------------------------------------------------------------------------------

type Cs = List Int

toCps :: String -> Cs
toCps = List.fromFoldable <<< map fromEnum <<< CP.toCodePointArray

csToString :: Cs -> String
csToString = CP.fromCodePointArray <<< map intToCp <<< Array.fromFoldable
  where
  intToCp n = unsafePartial (fromJust (toEnum n))

isPrefix :: Cs -> Cs -> Boolean
isPrefix Nil _ = true
isPrefix _ Nil = false
isPrefix (Cons p ps) (Cons x xs) = p == x && isPrefix ps xs

stripPrefixCs :: Cs -> Cs -> Maybe Cs
stripPrefixCs Nil s = Just s
stripPrefixCs _ Nil = Nothing
stripPrefixCs (Cons p ps) (Cons x xs) = if p == x then stripPrefixCs ps xs else Nothing

-- split off the maximal prefix of codepoints satisfying `pred`.
spanCs :: (Int -> Boolean) -> Cs -> { taken :: Cs, rest :: Cs }
spanCs pred (Cons x xs) | pred x = let r = spanCs pred xs in { taken: Cons x r.taken, rest: r.rest }
spanCs _ s = { taken: Nil, rest: s }

splitOnFirstCs :: Cs -> Cs -> Maybe { before :: Cs, after :: Cs }
splitOnFirstCs needle = go Nil
  where
  go acc rest
    | isPrefix needle rest = Just { before: List.reverse acc, after: List.drop (List.length needle) rest }
    | otherwise = case rest of
        Cons x xs -> go (Cons x acc) xs
        Nil -> Nothing

startsWith :: String -> Cs -> Boolean
startsWith p s = isPrefix (toCps p) s

--------------------------------------------------------------------------------
-- Codepoint predicates (ASCII, matching the `\d`/`\w` regex classes)
--------------------------------------------------------------------------------

isDigit :: Int -> Boolean
isDigit c = c >= 48 && c <= 57

isDigitU :: Int -> Boolean
isDigitU c = isDigit c || c == 95

isHex :: Int -> Boolean
isHex c = isDigit c || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)

isAlphaU :: Int -> Boolean
isAlphaU c = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95

isWord :: Int -> Boolean
isWord c = isAlphaU c || isDigit c

-- the `:`-atom operator run characters (`+ - * / < > = !`)
isAtomOpChar :: Int -> Boolean
isAtomOpChar c = c `elem` [ 43, 45, 42, 47, 60, 62, 61, 33 ]

isWs :: Int -> Boolean
isWs c = c == 32 || c == 9 || c == 13 || c == 10 || c == 11 || c == 12

--------------------------------------------------------------------------------
-- The scanner — one rule per construct, tried in source order via `<|>`
--------------------------------------------------------------------------------

type Step = { prepend :: List Token, rest :: Cs }

-- @rian_sig pub def tokenizeTrivia(src val String) Vec(Token)
tokenizeTrivia :: String -> Array Token
tokenizeTrivia s = Array.fromFoldable (List.reverse (lexLoop (toCps s) Nil))

-- the accumulator is in reverse (head = most recent), like lib/rian/lexer.ex.
lexLoop :: Cs -> List Token -> List Token
lexLoop Nil acc = acc
lexLoop cs acc = case step cs of
  Just s -> lexLoop s.rest (s.prepend <> acc)
  Nothing -> unsafeCrashWith ("cannot scan: " <> csToString cs)

step :: Cs -> Maybe Step
step cs =
  spaceRule cs
    <|> nlRule cs
    <|> commentRule cs
    <|> punctMulti "%{" TMapopen cs
    <|> punctMulti "<<" TBitopen cs
    <|> punctMulti ">>" TBitclose cs
    <|> annotRule cs
    <|> punctRule cs
    <|> heredocRule cs
    <|> stringRule cs
    <|> charRule cs
    <|> opAtomRule cs
    <|> multiRule cs
    <|> singleRule cs
    <|> numberRule cs
    <|> identRule cs

emit :: Token -> Cs -> Step
emit tok rest = { prepend: tok : Nil, rest }

spaceRule :: Cs -> Maybe Step
spaceRule (Cons c xs) | c == 32 || c == 9 || c == 13 = Just { prepend: Nil, rest: xs }
spaceRule _ = Nothing

nlRule :: Cs -> Maybe Step
nlRule (Cons 10 xs) = Just (emit TNl xs)
nlRule _ = Nothing

commentRule :: Cs -> Maybe Step
commentRule cs
  | startsWith "#" cs = let r = takeComment cs in Just (emit (TComment r.comment) r.rest)
  | otherwise = Nothing

takeComment :: Cs -> { comment :: String, rest :: Cs }
takeComment cs = case splitOnFirstCs (toCps "\n") cs of
  Just { before, after } -> { comment: trimTrailing (csToString before), rest: Cons 10 after }
  Nothing -> { comment: trimTrailing (csToString cs), rest: Nil }

punctMulti :: String -> Token -> Cs -> Maybe Step
punctMulti pat tok cs = emit tok <$> stripPrefixCs (toCps pat) cs

annotRule :: Cs -> Maybe Step
annotRule cs = case stripPrefixCs (toCps "@") cs of
  Just rest@(Cons c _) | isAlphaU c ->
    let core = spanCs isWord rest in Just (emit (TAnnot (csToString core.taken)) core.rest)
  _ -> Nothing

punctRule :: Cs -> Maybe Step
punctRule (Cons c xs) = (\tok -> emit tok xs) <$> punctTok c
punctRule _ = Nothing

punctTok :: Int -> Maybe Token
punctTok 40 = Just TLparen
punctTok 41 = Just TRparen
punctTok 91 = Just TLbracket
punctTok 93 = Just TRbracket
punctTok 123 = Just TLbrace
punctTok 125 = Just TRbrace
punctTok 44 = Just TComma
punctTok 59 = Just TSemi
punctTok _ = Nothing

heredocRule :: Cs -> Maybe Step
heredocRule cs
  | startsWith "\"\"\"" cs =
      case splitOnFirstCs (toCps "\"\"\"") (List.drop 3 cs) of
        Just { before, after } -> Just (emit (THeredoc (csToString before)) after)
        Nothing -> unsafeCrashWith "unterminated heredoc string"
  | otherwise = Nothing

stringRule :: Cs -> Maybe Step
stringRule cs = case stripPrefixCs (toCps "\"") cs of
  Just rest -> let r = lexStringToken rest in Just (emit r.token r.rest)
  Nothing -> Nothing

charRule :: Cs -> Maybe Step
charRule cs = case stripPrefixCs (toCps "'") cs of
  Just rest -> let r = lexChar rest in Just (emit (TChar r.cp) r.rest)
  Nothing -> Nothing

opAtomRule :: Cs -> Maybe Step
opAtomRule cs = case stripPrefixCs (toCps ":") cs of
  Just rest ->
    let
      run = spanCs isAtomOpChar rest
      runStr = csToString run.taken
    in
      if runStr /= "" && runStr /= "=" then Just (atom runStr run.rest)
      else case opWordName rest of
        Just w -> Just (atom w (List.drop (List.length (toCps w)) rest))
        Nothing -> Nothing
  Nothing -> Nothing
  where
  atom name rest = { prepend: TId name : TOp ":" : Nil, rest }

multiRule :: Cs -> Maybe Step
multiRule cs =
  (\op -> emit (TOp op) (List.drop (List.length (toCps op)) cs))
    <$> Array.find (\op -> startsWith op cs) multiOps

singleRule :: Cs -> Maybe Step
singleRule (Cons c xs) = (\op -> emit (TOp op) xs) <$> Array.find (\op -> toCps op == (c : Nil)) singleOps
singleRule _ = Nothing

numberRule :: Cs -> Maybe Step
numberRule cs = (\r -> emit (TNum (normNum r.lexeme)) r.rest) <$> scanNumber cs

identRule :: Cs -> Maybe Step
identRule cs = (\r -> emit (if keyColon r.rest then TId r.lexeme else word r.lexeme) r.rest) <$> scanIdent cs

--------------------------------------------------------------------------------
-- `:`-atoms, keyword-in-key-position, word classification
--------------------------------------------------------------------------------

opWordName :: Cs -> Maybe String
opWordName rest =
  let w = csToString (spanCs isWord rest).taken
  in if w `elem` opWords then Just w else Nothing

-- is the upcoming text a key colon (`end:` → key) rather than the bind `:=` / spec `::`?
keyColon :: Cs -> Boolean
keyColon rest
  | startsWith ":=" rest = false
  | startsWith "::" rest = false
  | otherwise = startsWith ":" rest

word :: String -> Token
word w
  | w `elem` opWords = TOp w
  | w `elem` keywords = TKw w
  | otherwise = TId w

--------------------------------------------------------------------------------
-- Numbers (the `\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?` grammar, hand-rolled)
--------------------------------------------------------------------------------

scanNumber :: Cs -> Maybe { lexeme :: String, rest :: Cs }
scanNumber cs@(Cons c _) | isDigit c =
  let
    a = spanCs isDigitU cs
    b = case stripFraction a.rest of
      Just f -> { taken: a.taken <> f.taken, rest: f.rest }
      Nothing -> a
    d = case stripExponent b.rest of
      Just e -> { taken: b.taken <> e.taken, rest: e.rest }
      Nothing -> b
  in Just { lexeme: csToString d.taken, rest: d.rest }
scanNumber _ = Nothing

stripFraction :: Cs -> Maybe { taken :: Cs, rest :: Cs }
stripFraction cs = case stripPrefixCs (toCps ".") cs of
  Just afterDot@(Cons c _) | isDigit c ->
    let run = spanCs isDigitU afterDot in Just { taken: Cons 46 run.taken, rest: run.rest }
  _ -> Nothing

stripExponent :: Cs -> Maybe { taken :: Cs, rest :: Cs }
stripExponent (Cons c tail) | c == 101 || c == 69 =
  let
    signed = case tail of
      Cons s rest2 | s == 43 || s == 45 -> { sign: s : Nil, after: rest2 }
      _ -> { sign: Nil, after: tail }
    run = spanCs isDigit signed.after
  in case run.taken of
    Nil -> Nothing
    _ -> Just { taken: Cons c (signed.sign <> run.taken), rest: run.rest }
stripExponent _ = Nothing

-- normalize `1e9` → `1.0e9`; the lexeme is ASCII, so String ops are codepoint-safe here.
normNum :: String -> String
normNum s =
  if CP.indexOf (Pattern ".") s /= Nothing then s
  else case firstE of
    Just i -> let p = CP.splitAt i s in p.before <> ".0e" <> CP.drop 1 p.after
    Nothing -> s
  where
  firstE = case CP.indexOf (Pattern "e") s, CP.indexOf (Pattern "E") s of
    Just i, Just j -> Just (min i j)
    Just i, Nothing -> Just i
    Nothing, Just j -> Just j
    Nothing, Nothing -> Nothing

--------------------------------------------------------------------------------
-- Identifiers (`[A-Za-z_]\w*(?:\?|!(?!=))?`)
--------------------------------------------------------------------------------

scanIdent :: Cs -> Maybe { lexeme :: String, rest :: Cs }
scanIdent cs@(Cons c _) | isAlphaU c =
  let
    core = spanCs isWord cs
    base = csToString core.taken
  in case core.rest of
    Cons 63 xs -> Just { lexeme: base <> "?", rest: xs } -- trailing `?`
    Cons 33 xs -> case xs of
      Cons 61 _ -> Just { lexeme: base, rest: core.rest } -- `!=` operator, not the name
      _ -> Just { lexeme: base <> "!", rest: xs }
    _ -> Just { lexeme: base, rest: core.rest }
scanIdent _ = Nothing

--------------------------------------------------------------------------------
-- Char literals
--------------------------------------------------------------------------------

lexChar :: Cs -> { cp :: Int, rest :: Cs }
lexChar cs = case stripPrefixCs (toCps "\\") cs of
  Just rest -> let e = charEscape rest in { cp: e.cp, rest: closeChar e.rest }
  Nothing -> case cs of
    Cons 39 _ -> unsafeCrashWith "empty character literal '' — use a string"
    Cons h tail -> { cp: h, rest: closeChar tail }
    Nil -> unsafeCrashWith "unterminated character literal"

closeChar :: Cs -> Cs
closeChar (Cons 39 rest) = rest
closeChar Nil = unsafeCrashWith "unterminated character literal"
closeChar cs = unsafeCrashWith ("character literal must be a single codepoint near: " <> csToString cs)

--------------------------------------------------------------------------------
-- Escapes (shared by Char and String literals)
--------------------------------------------------------------------------------

charEscape :: Cs -> { cp :: Int, rest :: Cs }
charEscape (Cons h tail) = case h of
  97 -> { cp: 0x07, rest: tail } -- \a
  98 -> { cp: 0x08, rest: tail } -- \b
  100 -> { cp: 0x7F, rest: tail } -- \d
  101 -> { cp: 0x1B, rest: tail } -- \e
  102 -> { cp: 0x0C, rest: tail } -- \f
  110 -> { cp: 0x0A, rest: tail } -- \n
  114 -> { cp: 0x0D, rest: tail } -- \r
  115 -> { cp: 0x20, rest: tail } -- \s
  116 -> { cp: 0x09, rest: tail } -- \t
  118 -> { cp: 0x0B, rest: tail } -- \v
  48 -> { cp: 0, rest: tail } -- \0
  92 -> { cp: 92, rest: tail } -- \\
  39 -> { cp: 39, rest: tail } -- \'
  34 -> { cp: 34, rest: tail } -- \"
  120 -> escapeX tail -- \xHH
  117 -> escapeU tail -- \u{...} or \uHHHH
  _ -> unsafeCrashWith ("unknown character escape near: " <> csToString (Cons h tail))
charEscape Nil = unsafeCrashWith "unknown character escape near end of input"

escapeX :: Cs -> { cp :: Int, rest :: Cs }
escapeX cs =
  let h = takeHex 2 cs
  in if h.count == 0 then unsafeCrashWith "`\\x` escape needs at least one hex digit"
     else { cp: cpBang (parseHex h.hex), rest: h.rest }

escapeU :: Cs -> { cp :: Int, rest :: Cs }
escapeU cs = case stripPrefixCs (toCps "{") cs of
  Just afterBrace -> case splitOnFirstCs (toCps "}") afterBrace of
    Just { before, after } | not (List.null before) ->
      { cp: cpBang (parseHexStrict before), rest: after }
    _ -> unsafeCrashWith "empty or unterminated `\\u{...}` escape"
  Nothing ->
    let h = takeHex 4 cs
    in if h.count == 4 then { cp: cpBang (parseHex h.hex), rest: h.rest }
       else unsafeCrashWith "`\\u` escape needs four hex digits — or use `\\u{...}`"

-- take up to `maxN` leading hex digits.
takeHex :: Int -> Cs -> { hex :: String, count :: Int, rest :: Cs }
takeHex maxN cs =
  let r = go maxN cs Nil in { hex: csToString (List.reverse r.acc), count: List.length r.acc, rest: r.rest }
  where
  go n t acc
    | n <= 0 = { acc, rest: t }
    | otherwise = case t of
        Cons x xs | isHex x -> go (n - 1) xs (Cons x acc)
        _ -> { acc, rest: t }

parseHex :: String -> Int
parseHex hex = case Int.fromStringAs Int.hexadecimal hex of
  Just n -> n
  Nothing -> unsafeCrashWith ("invalid hex digits in escape: " <> hex)

-- like parseHex, but first validate every codepoint is a hex digit (the `\u{...}` path).
parseHexStrict :: Cs -> Int
parseHexStrict hex =
  if any (not <<< isHex) hex then unsafeCrashWith ("invalid hex digits in escape: " <> csToString hex)
  else parseHex (csToString hex)

-- a valid scalar Unicode codepoint (no surrogates, ≤ U+10FFFF).
cpBang :: Int -> Int
cpBang n
  | (n >= 0 && n <= 0xD7FF) || (n >= 0xE000 && n <= 0x10FFFF) = n
  | otherwise = unsafeCrashWith ("codepoint out of range or a surrogate: " <> show n)

--------------------------------------------------------------------------------
-- String literals (with `${...}` interpolation)
--------------------------------------------------------------------------------

lexStringToken :: Cs -> { token :: Token, rest :: Cs }
lexStringToken cs = let r = lexParts cs Nil [] in { token: stringToken r.parts, rest: r.rest }

-- `litRev` accumulates the current literal run reversed; `parts` the completed segments.
lexParts :: Cs -> Cs -> Array StrPart -> { parts :: Array StrPart, rest :: Cs }
lexParts Nil _ _ = unsafeCrashWith "unterminated string literal"
lexParts cs litRev parts = case stripPrefixCs (toCps "\"") cs of
  Just rest -> { parts: Array.snoc parts (Lit (flush litRev)), rest }
  Nothing -> case stripPrefixCs (toCps "${") cs of
    Just rest ->
      let h = captureHole rest 0 Nil
      in lexParts h.rest Nil (parts <> [ Lit (flush litRev), Hole (csToString (List.reverse h.srcRev)) ])
    Nothing -> case stripPrefixCs (toCps "\\$") cs of
      Just rest -> lexParts rest (Cons 36 litRev) parts -- `\$` → literal `$`
      Nothing -> case stripPrefixCs (toCps "\\") cs of
        Just rest -> let e = charEscape rest in lexParts e.rest (Cons e.cp litRev) parts
        Nothing -> case cs of
          Cons h tail -> lexParts tail (Cons h litRev) parts
          Nil -> unsafeCrashWith "unterminated string literal"
  where
  flush rev = csToString (List.reverse rev)

-- capture a hole's raw source up to its matching `}` (brace-depth aware).
captureHole :: Cs -> Int -> Cs -> { srcRev :: Cs, rest :: Cs }
captureHole Nil _ _ = unsafeCrashWith "unterminated interpolation hole `${` in string"
captureHole cs depth acc = case stripPrefixCs (toCps "}") cs of
  Just rest -> if depth == 0 then { srcRev: acc, rest } else captureHole rest (depth - 1) (Cons 125 acc)
  Nothing -> case stripPrefixCs (toCps "{") cs of
    Just rest -> captureHole rest (depth + 1) (Cons 123 acc)
    Nothing -> case cs of
      Cons h tail -> captureHole tail depth (Cons h acc)
      Nil -> unsafeCrashWith "unterminated interpolation hole `${` in string"

stringToken :: Array StrPart -> Token
stringToken parts
  | any partIsHole parts = TIstr parts
  | otherwise = TStr (foldMap partLitText parts)

partIsHole :: StrPart -> Boolean
partIsHole (Hole _) = true
partIsHole _ = false

partLitText :: StrPart -> String
partLitText (Lit t) = t
partLitText (Hole _) = ""

--------------------------------------------------------------------------------
-- The three public streams
--------------------------------------------------------------------------------

-- @rian_sig pub def tokenize(src val String) Vec(Token)
tokenize :: String -> Array Token
tokenize = collapseNl <<< stripTrivia <<< tokenizeTrivia

-- @rian_sig pub def exprTokens(src val String) Vec(Token)
exprTokens :: String -> Array Token
exprTokens = Array.filter (not <<< isNewline) <<< stripTrivia <<< tokenizeTrivia

-- drop comment tokens; collapse a raw heredoc to its trimmed `TStr`.
stripTrivia :: Array Token -> Array Token
stripTrivia = map deHeredoc <<< Array.filter (not <<< isComment)
  where
  isComment (TComment _) = true
  isComment _ = false
  deHeredoc (THeredoc c) = TStr (trim c)
  deHeredoc t = t

-- collapse runs of `TNl` to one and drop leading/trailing ones.
collapseNl :: Array Token -> Array Token
collapseNl toks =
  let
    collapsed = (foldl stepC { acc: [], prev: false } toks).acc
    front = Array.dropWhile isNewline collapsed
  in Array.reverse (Array.dropWhile isNewline (Array.reverse front))
  where
  stepC st t =
    if isNewline t then if st.prev then st else { acc: Array.snoc st.acc TNl, prev: true }
    else { acc: Array.snoc st.acc t, prev: false }

--------------------------------------------------------------------------------
-- detokenize (the inverse — a re-lexable rendering; String ops here are UTF-8-safe)
--------------------------------------------------------------------------------

-- @rian_sig pub def detokenize(toks val Vec(Token)) String
detokenize :: Array Token -> String
detokenize = detokenizeWith " "

-- @rian_sig pub def detokenizeWith(nlAs val String, toks val Vec(Token)) String
detokenizeWith :: String -> Array Token -> String
detokenizeWith nlAs toks =
  trimTrailing (joinWith "" (Array.mapWithIndex render toks))
  where
  render i tok =
    tokStr nlAs tok <> if glueAfter tok (Array.index toks (i + 1)) then "" else " "

-- an operator-name atom (`:` then `{:op,":"}`+id) must glue, else a re-lex loses it.
glueAfter :: Token -> Maybe Token -> Boolean
glueAfter (TOp ":") (Just (TId name)) = firstCharAtomOp name || name `elem` opWords
  where
  firstCharAtomOp n = case List.head (toCps n) of
    Just c -> isAtomOpChar c
    Nothing -> false
glueAfter _ _ = false

tokStr :: String -> Token -> String
tokStr nlAs TNl = nlAs
tokStr _ (TId x) = x
tokStr _ (TNum n) = n
tokStr _ (TChar cp) = "'" <> charSource cp <> "'"
tokStr _ (TStr s) = "\"" <> escapeStr s <> "\""
tokStr _ (TIstr parts) = "\"" <> foldMap partSource parts <> "\""
  where
  partSource (Lit s) = escapeStr s
  partSource (Hole src) = "${" <> src <> "}"
tokStr _ (TOp o) = o
tokStr _ (TKw k) = k
tokStr _ (TAnnot a) = "@" <> a
tokStr _ TLparen = "("
tokStr _ TRparen = ")"
tokStr _ TLbracket = "["
tokStr _ TRbracket = "]"
tokStr _ TLbrace = "{"
tokStr _ TRbrace = "}"
tokStr _ TMapopen = "%{"
tokStr _ TBitopen = "<<"
tokStr _ TBitclose = ">>"
tokStr _ TComma = ","
tokStr _ TSemi = ";"
tokStr _ (TComment text) = text
tokStr _ (THeredoc content) = "\"\"\"" <> content <> "\"\"\""

-- re-lexable rendering of a codepoint inside `'…'` (the inverse of lexChar).
charSource :: Int -> String
charSource 10 = "\\n"
charSource 9 = "\\t"
charSource 13 = "\\r"
charSource 0 = "\\0"
charSource 92 = "\\\\"
charSource 39 = "\\'"
charSource cp
  | cp < 0x20 || cp == 0x7F = "\\u{" <> upperHex cp <> "}"
  | otherwise = singletonCp cp

-- re-escape a decoded string value for rendering inside `"…"`.
escapeStr :: String -> String
escapeStr s = foldMap (strCpSource <<< fromEnum) (CP.toCodePointArray s)

strCpSource :: Int -> String
strCpSource 92 = "\\\\"
strCpSource 34 = "\\\""
strCpSource 36 = "\\$"
strCpSource 10 = "\\n"
strCpSource 9 = "\\t"
strCpSource 13 = "\\r"
strCpSource cp
  | cp < 0x20 || cp == 0x7F = "\\u{" <> upperHex cp <> "}"
  | otherwise = singletonCp cp

singletonCp :: Int -> String
singletonCp cp = CP.singleton (unsafePartial (fromJust (toEnum cp)))

upperHex :: Int -> String
upperHex n = toUpper (Int.toStringAs Int.hexadecimal n)

trimTrailing :: String -> String
trimTrailing s =
  CP.fromCodePointArray (Array.reverse (Array.dropWhile (isWs <<< fromEnum) (Array.reverse (CP.toCodePointArray s))))
