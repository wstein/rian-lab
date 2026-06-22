-- | Lowers typed-Core patterns (`Rian.Core` `CPat`) into the *checker* patterns
-- | (the Maranget `Ctor id args` / `Wild` form) consumed by `Rian.Exhaustiveness`.
-- | The PureScript port of `Rian.PatternLower` (lib/rian/pattern_lower.ex), ADR-0084 /
-- | ADR-0050. The first gate consuming the ported Core (`from_pat`), after `Rian.Range`.
-- |
-- | The Elixir reference keys its signature environment with *heterogeneous* terms
-- | (atoms, `{:tuple,n}`, `{:lit,v}`, the bool/list atoms). PureScript has no atom
-- | identity, so the checker constructor id is a real sum (`CtorId`): the list nil/cons
-- | and `true`/`false` become named constructors of types `list`/`bool`, exactly as the
-- | Elixir `base_env` registers them (`to_snake "True" == :true` over there). Because no
-- | `Data.Map` is in the purerl package set, the env is modelled as small association
-- | lists (the envs are tiny); `aPut` gives `Map.put` (replace-or-insert) semantics.
module Rian.PatternLower
  ( LitV(..)
  , CtorId(..)
  , CkPat(..)
  , Sig(..)
  , Env
  , Clause
  , aLookup
  , aPut
  , arityOf
  , toSnake
  , lower
  , lowerMany
  , lowerClause
  , addStruct
  ) where

import Prelude

import Data.Array (filter, find, index, length, snoc, uncons)
import Data.Foldable (foldl)
import Data.FoldableWithIndex (foldlWithIndex)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String.CodeUnits (singleton, toCharArray)
import Data.String.Common (toLower)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Core (CPat(..), LitVal(..), fromPat)
import Rian.Pratt (parsePats)

-- | A 0-arity literal constructor's value. The Elixir `{:lit, v}` value universe is
-- | `i64 | str | atom`; a `Char` literal is its codepoint (an `LvInt`).
data LitV = LvInt Int | LvStr String | LvAtom String

derive instance Eq LitV

-- | A checker constructor id. `CNil`/`CCons` are the list constructors (Elixir atoms
-- | `nil`/`cons`); `true`/`false` are `CName "true"`/`CName "false"` of type `bool`.
data CtorId
  = CNil
  | CCons
  | CTuple Int
  | CName String
  | CLit LitV

derive instance Eq CtorId

-- | A checker pattern: a wildcard (also a var / lowered pin), or a constructor with
-- | sub-patterns.
data CkPat = Wild | Ctor CtorId (Array CkPat)

-- | A type's constructor signature. `Finite` lists every member; `Infinite` is a bare
-- | primitive (`Int64`/`Char`/`String`/`Map`) that always demands a `_`.
data Sig = Finite (Array CtorId) | Infinite

-- | The signature environment. `arity`/`typeOf` are keyed by constructor id, `ctors`/
-- | `structs` by type name. Modelled as association lists (no `Data.Map` in the set).
type Env =
  { arity :: Array (Tuple CtorId Int)
  , typeOf :: Array (Tuple CtorId String)
  , ctors :: Array (Tuple String Sig)
  , structs :: Array (Tuple String (Array String))
  }

-- | One lowered clause: the checker `pat` vector and the effective `guard` flag (the
-- | explicit guard OR'd with any guard introduced by a pin / non-empty map).
type Clause = { pat :: Array CkPat, guard :: Boolean }

-- ── Association-list helpers (Map.put / Map.get over a small list) ──────────

aLookup :: forall k v. Eq k => k -> Array (Tuple k v) -> Maybe v
aLookup k = map snd <<< find (\(Tuple k' _) -> k' == k)

aPut :: forall k v. Eq k => k -> v -> Array (Tuple k v) -> Array (Tuple k v)
aPut k v xs = snoc (filter (\(Tuple k' _) -> k' /= k) xs) (Tuple k v)

-- ── Arity ──────────────────────────────────────────────────────────────────

arityOf :: Env -> CtorId -> Int
arityOf _ (CTuple n) = n
arityOf _ (CLit _) = 0
arityOf env c = fromMaybe 0 (aLookup c env.arity)

-- ── Name normalization (PascalCase / "JNum" → snake) ─────────────────────────

-- | The two Elixir snake regexes fused into one neighbour-aware pass: insert `_`
-- | before an uppercase letter that either follows a lowercase/digit, or sits between
-- | an uppercase and a lowercase (the acronym boundary), then downcase.
-- @rian_sig pub def toSnake(name val String) String
toSnake :: String -> String
toSnake name = toLower (foldlWithIndex step "" cs)
  where
  cs = toCharArray name
  step i acc c =
    let
      prev = index cs (i - 1)
      next = index cs (i + 1)
      needsU = isUpper c
        && ((maybe false isUpper prev && maybe false isLowerAlpha next)
              || maybe false isLowerOrDigit prev)
    in
      acc <> (if needsU then "_" else "") <> singleton c

isUpper :: Char -> Boolean
isUpper c = c >= 'A' && c <= 'Z'

isLowerAlpha :: Char -> Boolean
isLowerAlpha c = c >= 'a' && c <= 'z'

isLowerOrDigit :: Char -> Boolean
isLowerOrDigit c = isLowerAlpha c || (c >= '0' && c <= '9')

-- ── Lowering ─────────────────────────────────────────────────────────────────

-- | Lower one Core pattern → `Tuple checker introduced_guard?`.
-- @rian_sig pub def lower(pat val Pat, env val Env) (CkPat, Bool)
lower :: CPat -> Env -> Tuple CkPat Boolean
lower PWild _ = Tuple Wild false
lower (PVar _) _ = Tuple Wild false
-- a type-pattern (`n Type`, a union arm) BINDS `n`; for coverage it is a binding wildcard.
lower (PTyped _ _ _) _ = Tuple Wild false
lower (PAs _ p) env = lower p env
lower (PPin _) _ = Tuple Wild true
lower (PLit (LInt v)) _ = Tuple (Ctor (CLit (LvInt v)) []) false
lower (PLit (LStr v)) _ = Tuple (Ctor (CLit (LvStr v)) []) false
-- a `Char` literal pattern is its codepoint literal for exhaustiveness (ADR-0036).
lower (PChar cp) _ = Tuple (Ctor (CLit (LvInt cp)) []) false
-- an atom (`:ok`) is a nullary literal constructor over the open atom universe.
lower (PAtom a) _ = Tuple (Ctor (CLit (LvAtom a)) []) false
lower (PTuple ps) env =
  let Tuple cps intro = lowerMany ps env in Tuple (Ctor (CTuple (length ps)) cps) intro
lower (PCtor name ps) env =
  let Tuple cps intro = lowerMany ps env in Tuple (Ctor (CName (toSnake name)) cps) intro
lower (PList elems tail) env = lowerList elems tail env
-- open maps are refutable (unless empty): treat like a guarded clause for coverage.
lower (PMap pairs) _ = case pairs of
  [] -> Tuple Wild false
  _ -> Tuple Wild true
lower (PStruct name fields) env =
  let
    s = toSnake name
    order = case aLookup s env.structs of
      Just o -> o
      Nothing -> unsafeCrashWith ("struct pattern over `" <> name <> "`: its type is not in scope")
    inOrder = map
      ( \f -> case find (\(Tuple k _) -> k == f) fields of
          Just (Tuple _ p) -> p
          Nothing -> PWild
      )
      order
    Tuple cps intro = lowerMany inOrder env
  in
    Tuple (Ctor (CName s) cps) intro

lowerMany :: Array CPat -> Env -> Tuple (Array CkPat) Boolean
lowerMany ps env =
  foldl
    (\(Tuple acc i) p -> let Tuple c j = lower p env in Tuple (snoc acc c) (i || j))
    (Tuple [] false)
    ps

lowerList :: Array CPat -> Maybe CPat -> Env -> Tuple CkPat Boolean
lowerList elems tail env = case uncons elems of
  Nothing -> case tail of
    Nothing -> Tuple (Ctor CNil []) false
    Just t -> lower t env
  Just { head: h, tail: rest } ->
    let
      Tuple hc hi = lower h env
      Tuple tc ti = lowerList rest tail env
    in
      Tuple (Ctor CCons [ hc, tc ]) (hi || ti)

-- | Lower one clause: parse the source pattern vector, lower each, OR the guard flags.
-- @rian_sig pub def lowerClause(src val String, guard val Bool, env val Env) Clause
lowerClause :: String -> Boolean -> Env -> Clause
lowerClause src guard env =
  let
    cpats = map fromPat (parsePats src)
    Tuple pats intro = lowerMany cpats env
  in
    { pat: pats, guard: guard || intro }

-- | Register a product type (struct) so struct patterns can be ordered + decomposed.
-- @rian_sig pub def addStruct(env val Env, name val String, fields val Vec(String)) Env
addStruct :: Env -> String -> Array String -> Env
addStruct env name fields =
  let s = toSnake name in
  env
    { arity = aPut (CName s) (length fields) env.arity
    , typeOf = aPut (CName s) s env.typeOf
    , ctors = aPut s (Finite [ CName s ]) env.ctors
    , structs = aPut s fields env.structs
    }
