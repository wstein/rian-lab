-- | Type checking (ADR-0034) — the PureScript port of `Rian.Check` (lib/rian/check.ex),
-- | ADR-0084. **Stage 1: the type algebra** — the two lattice kernels every later pass is
-- | built on:
-- |
-- |   * `unify` — equal → itself, `Unknown` → the other, `Any` → the other, `Fn(…)`
-- |     structurally (componentwise), else `Mismatch`. This is the "match a partial
-- |     inference against a declaration" join, where `Unknown` is a *wildcard*.
-- |   * `join` — the least-upper-bound for branch/arm/element types (the arms of an `if`/
-- |     `case`, the elements of a list). Here `Unknown` is *absorbing* (top), `Bottom` is
-- |     the fold identity, `Any` absorbs, and `_Unk` defers. Numeric widths join to their
-- |     LUB over the `⊑` widening order; same-constructor parametric types join covariantly.
-- |
-- | `infer`/`annotate`/the error-set fixpoint/the program gates land in later stages (they
-- | consume the inference context + the whole-program call graph). The Elixir `ty` is a
-- | `String | :unknown | :mismatch | :bottom`; here it is a real sum (`Ty`) — the
-- | "reframe, not lift" the migration calls for (a name string vs the three sentinels).
module Rian.Check
  ( Ty(..)
  , tyStr
  , tyOf
  , unify
  , join
  , unifySexpr
  , joinSexpr
  ) where

import Prelude hiding (join)

import Data.Array (find, length, uncons, zipWith)
import Data.Foldable (all, any)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String as Str
import Data.String.CodeUnits (toCharArray)
import Data.String.Common (joinWith, split)
import Rian.TypeStr (splitTopCommas)

-- | An inferred type: a type-name string (`"Int53"`, `"Fn(_,Int64)"`, `"Vec(Int53)"`), or
-- | one of the three sentinels — `Unknown` (`:unknown`, an unfinished inference hole),
-- | `Mismatch` (a proven clash), `Bottom` (`:bottom`, the join identity / empty branch set).
data Ty = TName String | Unknown | Mismatch | Bottom

derive instance Eq Ty

-- | The Elixir-atom rendering of a `Ty`, for the parity oracle.
tyStr :: Ty -> String
tyStr (TName s) = s
tyStr Unknown = ":unknown"
tyStr Mismatch = ":mismatch"
tyStr Bottom = ":bottom"

-- | Read a parity-input type token back into a `Ty` (the sentinels round-trip).
tyOf :: String -> Ty
tyOf ":unknown" = Unknown
tyOf ":mismatch" = Mismatch
tyOf ":bottom" = Bottom
tyOf s = TName s

-- ── unification kernel ───────────────────────────────────────────────────────

-- | Unify two types: equal → itself; `Unknown` → the other; `Any` → the other; `Fn(…)`
-- | structurally; else `Mismatch`.
unify :: Ty -> Ty -> Ty
unify t u
  | t == u = t
unify Unknown t = t
unify t Unknown = t
unify (TName "Any") t = t
unify t (TName "Any") = t
unify (TName a) (TName b)
  | isFn a && isFn b = unifyFn a b
unify _ _ = Mismatch

-- componentwise-unify two `Fn(...)` strings; `Mismatch` on differing arity / any clash.
unifyFn :: String -> String -> Ty
unifyFn a b =
  let
    pa = fnParts a
    pb = fnParts b
  in
    if length pa == length pb then
      let parts = zipWith compUnify pa pb in
      if any (_ == Mismatch) parts then Mismatch
      else TName ("Fn(" <> joinWith "," (map tyStr parts) <> ")")
    else Mismatch

compUnify :: Ty -> Ty -> Ty
compUnify x y
  | x == y = x
  | wildcard x = y
  | wildcard y = x
  | isFnTy x && isFnTy y = unifyFn (tyStr x) (tyStr y)
  | otherwise = case numLub x y of
      Just j -> j
      Nothing -> Mismatch

-- two numeric widths reconcile to their LUB (so an inferred `Fn(_,Int53)` over literals
-- matches a declared `Fn(Int64,Int64)`); `Nothing` when they have no common width.
numLub :: Ty -> Ty -> Maybe Ty
numLub x y =
  case numKind x, numKind y of
    Just _, Just _ -> case join x y of
      Unknown -> Nothing
      t -> Just t
    _, _ -> Nothing

fnParts :: String -> Array Ty
fnParts s = map tyOf (splitTopCommas (Str.drop 3 (dropLastParen s)))

isFn :: String -> Boolean
isFn s = Str.take 3 s == "Fn("

isFnTy :: Ty -> Boolean
isFnTy (TName s) = isFn s
isFnTy _ = false

wildcard :: Ty -> Boolean
wildcard (TName "_") = true
wildcard (TName s) = isTvar s
wildcard _ = false

-- a `forall` type variable: a single uppercase letter, optionally one digit (`T`, `T1`).
isTvar :: String -> Boolean
isTvar s = case toCharArray s of
  [ c ] -> isUpper c
  [ c, d ] -> isUpper c && isDigit d
  _ -> false

-- ── join: least-upper-bound for branch/arm/element types ─────────────────────

-- | The LUB of two branch/arm/element types (ADR-0059). NOT `unify`: here `Unknown` is
-- | *absorbing* (top), `Bottom` is the identity, `Any` absorbs, `_Unk` defers.
join :: Ty -> Ty -> Ty
join t u
  | t == u = t
join Bottom t = t
join t Bottom = t
join (TName "_Unk") t = t
join t (TName "_Unk") = t
join (TName "Any") _ = TName "Any"
join _ (TName "Any") = TName "Any"
join Unknown _ = Unknown
join _ Unknown = Unknown
join from to =
  case numKind from, numKind to of
    Just a, Just b -> numJoin a b
    _, _ -> parametricJoin from to

-- ── numeric LUB over the `⊑` widening order ──────────────────────────────────

data Kind = KInt | KUint | KFloat

derive instance Eq Kind

-- a numeric type name → `{kind, bits}`, or `Nothing` (a bare `Int` / non-numeric).
numKind :: Ty -> Maybe { kind :: Kind, bits :: Int }
numKind (TName s) =
  case Str.stripPrefix (Str.Pattern "UInt") s of
    Just w -> numBits KUint w
    Nothing -> case Str.stripPrefix (Str.Pattern "Int") s of
      Just w -> numBits KInt w
      Nothing -> case Str.stripPrefix (Str.Pattern "Float") s of
        Just w -> numBits KFloat w
        Nothing -> Nothing
numKind _ = Nothing

numBits :: Kind -> String -> Maybe { kind :: Kind, bits :: Int }
numBits kind w = case Int.fromString w of
  Just n -> Just { kind, bits: n }
  Nothing -> Nothing

-- The mixed-kind combinations are explicit; same-kind (`KInt`/`KInt`, …) is the final
-- catch-all (`kindPrefix k <> max width`). The cases are disjoint, so this matches the
-- Elixir order (same-kind first there) for every input.
numJoin :: { kind :: Kind, bits :: Int } -> { kind :: Kind, bits :: Int } -> Ty
numJoin { kind: KUint, bits: a } { kind: KInt, bits: b } = uintSignedJoin a b
numJoin { kind: KInt, bits: a } { kind: KUint, bits: b } = uintSignedJoin b a
numJoin { kind: KInt, bits: a } { kind: KFloat, bits: b } = intFloatJoin (a - 1) b
numJoin { kind: KFloat, bits: b } { kind: KInt, bits: a } = intFloatJoin (a - 1) b
numJoin { kind: KUint, bits: a } { kind: KFloat, bits: b } = intFloatJoin a b
numJoin { kind: KFloat, bits: b } { kind: KUint, bits: a } = intFloatJoin a b
numJoin a b = TName (kindPrefix a.kind <> show (max a.bits b.bits))

intWidths :: Array Int
intWidths = [ 8, 16, 32, 64, 128 ]

floatWidths :: Array Int
floatWidths = [ 32, 64 ]

-- `UIntₐ ⊔ Int_b` = least Int width strictly wider than `a` and at least `b`.
uintSignedJoin :: Int -> Int -> Ty
uintSignedJoin u i = case find (\c -> c > u && c >= i) intWidths of
  Just c -> TName ("Int" <> show c)
  Nothing -> Unknown

intFloatJoin :: Int -> Int -> Ty
intFloatJoin exactBits fb = case find (\c -> c >= fb && floatMantissa c >= exactBits) floatWidths of
  Just c -> TName ("Float" <> show c)
  Nothing -> Unknown

floatMantissa :: Int -> Int
floatMantissa 64 = 53
floatMantissa 32 = 24
floatMantissa _ = 0

kindPrefix :: Kind -> String
kindPrefix KInt = "Int"
kindPrefix KUint = "UInt"
kindPrefix KFloat = "Float"

-- ── parametric (same-constructor covariant) join ─────────────────────────────

parametricJoin :: Ty -> Ty -> Ty
parametricJoin from to
  | isFnTy from || isFnTy to = Unknown
parametricJoin from to =
  case parseParametric from, parseParametric to of
    Just f, Just t
      | f.name == t.name && length f.args == length t.args ->
          let parts = zipWith join f.args t.args in
          if any (_ == Unknown) parts then Unknown
          else TName (f.name <> "(" <> joinWith "," (map tyStr parts) <> ")")
    _, _ -> Unknown

-- `Name(a, b)` → `{name, [a, b]}` (the outer constructor + its top-level args).
parseParametric :: Ty -> Maybe { name :: String, args :: Array Ty }
parseParametric (TName s) =
  case Str.indexOf (Str.Pattern "(") s of
    Just i ->
      let
        name = Str.take i s
        rest = Str.drop (i + 1) s
      in
        case Str.stripSuffix (Str.Pattern ")") rest of
          Just inner | isIdent name -> Just { name, args: map tyOf (splitTopCommas inner) }
          _ -> Nothing
    Nothing -> Nothing
parseParametric _ = Nothing

-- ── small string helpers ─────────────────────────────────────────────────────

-- drop the trailing `)` of a well-formed `Fn(...)` / `Name(...)` before splitting args.
dropLastParen :: String -> String
dropLastParen s = case Str.stripSuffix (Str.Pattern ")") s of
  Just t -> t
  Nothing -> s

-- `^[A-Za-z_]\w*$` — an identifier (a constructor name).
isIdent :: String -> Boolean
isIdent s = case uncons (toCharArray s) of
  Nothing -> false
  Just r -> isIdentStart r.head && all isWord r.tail

isIdentStart :: Char -> Boolean
isIdentStart c = isUpper c || isLower c || c == '_'

isWord :: Char -> Boolean
isWord c = isIdentStart c || isDigit c

isUpper :: Char -> Boolean
isUpper c = c >= 'A' && c <= 'Z'

isLower :: Char -> Boolean
isLower c = c >= 'a' && c <= 'z'

isDigit :: Char -> Boolean
isDigit c = c >= '0' && c <= '9'

-- ── parity entries ───────────────────────────────────────────────────────────

-- | The `uni` / `joi` streams: a `t;;u` pair (the sentinels spelled `:unknown` etc.).
unifySexpr :: String -> String
unifySexpr = pairOp unify

joinSexpr :: String -> String
joinSexpr = pairOp join

pairOp :: (Ty -> Ty -> Ty) -> String -> String
pairOp f src = case split (Str.Pattern ";;") src of
  [ a, b ] -> tyStr (f (tyOf a) (tyOf b))
  _ -> "?"
