-- | Shared helpers for the **type-string surface** — the textual form of types
-- | (`Fn(A, B)`, `Map(K, V)`, `Vec(T)`, `Name(A, B)`) that several stages parse.
-- | The PureScript port of `Rian.TypeStr` (lib/rian/type_str.ex), ADR-0084 Phase 2.
-- |
-- | The single source of truth for "split a parenthesised argument list on its
-- | top-level commas" and the value-union canonicalization (ADR-0083). Depends on
-- | `Rian.Lexer` to decide comma nesting (each `TComma` token at paren depth 0).
module Rian.TypeStr
  ( splitTopCommas
  , splitTopPipes
  , normalize
  ) where

import Prelude

import Data.Array as Array
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..), fromJust, isJust)
import Data.String (stripPrefix, stripSuffix)
import Data.String.CodePoints as CP
import Data.String.Common (joinWith, trim)
import Data.String.Pattern (Pattern(..))
import Partial.Unsafe (unsafePartial)
import Rian.Lexer (exprTokens)
import Rian.Token (Token(..))

-- codepoint helpers (ASCII type strings, but kept Unicode-correct for consistency)
toCps :: String -> Array Int
toCps = map fromEnum <<< CP.toCodePointArray

fromCps :: Array Int -> String
fromCps = CP.fromCodePointArray <<< map (\n -> unsafePartial (fromJust (toEnum n)))

-- | Split `s` on its **top-level commas only** (nested generics stay intact). Each
-- | component is trimmed; empty components are dropped.
splitTopCommas :: String -> Array String
splitTopCommas "" = []
splitTopCommas s = Array.filter (_ /= "") (map trim (slice (topCommaCuts s) s))

-- the codepoint positions of the depth-0 commas. The lexer decides nesting; the Nth
-- depth-0 comma token is the Nth `,` codepoint (a type string hides no comma).
topCommaCuts :: String -> Array Int
topCommaCuts s =
  let
    ords = topCommaOrdinals (exprTokens s)
    commaIdx = map _.i (Array.filter (\x -> x.c == 44) (Array.mapWithIndex { i: _, c: _ } (toCps s)))
  in
    Array.mapMaybe (Array.index commaIdx) ords

-- 0-based ordinal (among all commas) of each comma token at paren depth 0.
topCommaOrdinals :: Array Token -> Array Int
topCommaOrdinals toks = (foldl stepO { ords: [], i: 0, d: 0 } toks).ords
  where
  stepO st TComma | st.d == 0 = st { ords = Array.snoc st.ords st.i, i = st.i + 1 }
  stepO st TComma = st { i = st.i + 1 }
  stepO st TLparen = st { d = st.d + 1 }
  stepO st TRparen = st { d = st.d - 1 }
  stepO st _ = st

-- cut `s` into pieces at the given comma positions (the commas are dropped).
slice :: Array Int -> String -> Array String
slice cuts s =
  let
    cps = toCps s
    res = foldl (\acc pos -> { pieces: Array.snoc acc.pieces (sub cps acc.start pos), start: pos + 1 }) { pieces: [], start: 0 } cuts
  in
    Array.snoc res.pieces (sub cps res.start (Array.length cps))
  where
  sub cps a b = fromCps (Array.slice a b cps)

-- | Split `s` on its **top-level `|` only** (paren-aware). Each component is trimmed;
-- | empty components are dropped.
splitTopPipes :: String -> Array String
splitTopPipes s =
  let
    res = foldl stepP { parts: [], cur: [], depth: 0 } (toCps s)
  in
    Array.filter (_ /= "") (map (trim <<< fromCps) (Array.snoc res.parts res.cur))
  where
  stepP st c
    | c == 40 = st { cur = Array.snoc st.cur c, depth = st.depth + 1 } -- '('
    | c == 41 = st { cur = Array.snoc st.cur c, depth = st.depth - 1 } -- ')'
    | c == 124 && st.depth == 0 = st { parts = Array.snoc st.parts st.cur, cur = [] } -- '|'
    | otherwise = st { cur = Array.snoc st.cur c }

-- | Canonicalize a type-reference string. A top-level `|` becomes the value-union form
-- | `Union(m1, m2, …)` (ADR-0083) — members flattened, de-duplicated, sorted. A type
-- | with no top-level `|` is returned trimmed.
normalize :: String -> String
normalize t = case splitTopPipes t of
  [ single ] -> trim single
  members -> "Union(" <> joinWith ", " (Array.sort (Array.nub (Array.concatMap unionMembers members))) <> ")"

-- the members of a single union component, flattening a nested `Union(…)` / `(A | B)`.
unionMembers :: String -> Array String
unionMembers m
  | Just rest <- stripPrefix (Pattern "Union(") m =
      Array.concatMap unionMembers (splitTopCommas (dropClose rest))
  | Just rest <- stripPrefix (Pattern "(") m, endsWith ")" m =
      Array.concatMap unionMembers (splitTopPipes (dropClose rest))
  | otherwise = [ trim m ]

endsWith :: String -> String -> Boolean
endsWith p s = isJust (stripSuffix (Pattern p) s)

-- drop exactly the one trailing `)` (not every trailing one).
dropClose :: String -> String
dropClose s = let cps = toCps s in fromCps (Array.slice 0 (Array.length cps - 1) cps)
