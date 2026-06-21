-- | The host/stdlib **foreign-call signature table** (the PureScript port of `Rian.Builtins`,
-- | lib/rian/builtins.ex, ADR-0084). A pure lookup table consumed by `Rian.Check` (to *type*
-- | a foreign call) and `Rian.Reach` (to pin any caller to `:ex` — these are host FFI, not
-- | portable). `module` is the call-head name (`"String"`, `"erlang"`, …) or `Nothing` for a
-- | `Kernel` auto-import (a bare call).
-- |
-- |   * `ret` — the declared concrete Rian return type, or `Nothing`.
-- |   * `known` — whether `{module, fun, arity}` is a registered builtin (the `@table` only —
-- |     a poly-only entry like `List.map/2` is NOT `known`, matching the reference).
-- |   * `polySig` — the fixed-head polymorphic `{params, ret, tvars}` (the caller instantiates
-- |     the tvars from argument types), or `Nothing`.
module Rian.Builtins
  ( Key
  , PolySig
  , ret
  , known
  , polySig
  , builtinSexpr
  ) where

import Prelude

import Data.Array (find)
import Data.Int as Int
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String (Pattern(..)) as Str
import Data.String.Common (joinWith, split)
import Data.Tuple (Tuple(..), snd)

type Key = { mod :: Maybe String, fun :: String, arity :: Int }
type PolySig = { params :: Array String, ret :: String, tvars :: Array String }

-- ── lookups ──────────────────────────────────────────────────────────────────

-- @rian_sig pub def ret(module val Option(String), fun val String, arity val Int53) Option(String)
ret :: Maybe String -> String -> Int -> Maybe String
ret m f a = lookupKey { mod: m, fun: f, arity: a } table

-- @rian_sig pub def known(module val Option(String), fun val String, arity val Int53) Bool
known :: Maybe String -> String -> Int -> Boolean
known m f a = isJust (lookupKey { mod: m, fun: f, arity: a } table)

-- @rian_sig pub def polySig(module val Option(String), fun val String, arity val Int53) Option((Vec(String), String, Vec(String)))
polySig :: Maybe String -> String -> Int -> Maybe PolySig
polySig m f a = lookupKey { mod: m, fun: f, arity: a } poly

lookupKey :: forall v. Key -> Array (Tuple Key v) -> Maybe v
lookupKey k = map snd <<< find (\(Tuple k' _) -> k' == k)

-- ── the concrete-return table (`ret` / `known`) ──────────────────────────────

-- a Kernel auto-import (bare call, `module = Nothing`).
k0 :: String -> Int -> String -> Tuple Key String
k0 fun arity r = Tuple { mod: Nothing, fun, arity } r

-- a module-qualified host call.
km :: String -> String -> Int -> String -> Tuple Key String
km m fun arity r = Tuple { mod: Just m, fun, arity } r

table :: Array (Tuple Key String)
table =
  -- Kernel auto-imports
  [ k0 "map_size" 1 "Int53"
  , k0 "tuple_size" 1 "Int53"
  , k0 "byte_size" 1 "Int53"
  , k0 "bit_size" 1 "Int53"
  , k0 "inspect" 1 "String"
  , k0 "inspect" 2 "String"
  , k0 "to_string" 1 "String"
  , k0 "is_atom" 1 "Bool"
  , k0 "is_binary" 1 "Bool"
  , k0 "is_list" 1 "Bool"
  , k0 "is_map" 1 "Bool"
  , k0 "is_tuple" 1 "Bool"
  , k0 "is_integer" 1 "Bool"
  , k0 "is_number" 1 "Bool"
  , k0 "is_nil" 1 "Bool"
  -- String (host)
  , km "String" "replace" 3 "String"
  , km "String" "replace" 4 "String"
  , km "String" "trim" 1 "String"
  , km "String" "trim" 2 "String"
  , km "String" "trim_leading" 2 "String"
  , km "String" "trim_trailing" 2 "String"
  , km "String" "upcase" 1 "String"
  , km "String" "downcase" 1 "String"
  , km "String" "capitalize" 1 "String"
  , km "String" "slice" 2 "String"
  , km "String" "slice" 3 "String"
  , km "String" "duplicate" 2 "String"
  , km "String" "pad_leading" 2 "String"
  , km "String" "pad_trailing" 2 "String"
  , km "String" "first" 1 "String"
  , km "String" "last" 1 "String"
  , km "String" "reverse" 1 "String"
  , km "String" "length" 1 "Int53"
  , km "String" "to_atom" 1 "Symbol"
  , km "String" "to_existing_atom" 1 "Symbol"
  -- arbitrary-precision parse → unbounded `Int`, not `Int53`.
  , km "String" "to_integer" 1 "Int"
  , km "String" "to_integer" 2 "Int"
  , km "String" "split" 2 "Vec(String)"
  , km "String" "split" 3 "Vec(String)"
  , km "String" "contains?" 2 "Bool"
  , km "String" "starts_with?" 2 "Bool"
  , km "String" "ends_with?" 2 "Bool"
  , km "String" "match?" 2 "Bool"
  -- Map (host)
  , km "Map" "has_key?" 2 "Bool"
  -- Enum (host; concrete returns only)
  , km "Enum" "count" 1 "Int53"
  , km "Enum" "member?" 2 "Bool"
  , km "Enum" "any?" 1 "Bool"
  , km "Enum" "all?" 1 "Bool"
  , km "Enum" "empty?" 1 "Bool"
  , km "Enum" "join" 2 "String"
  , km "Enum" "map_join" 3 "String"
  -- Integer / Float / Atom → String
  , km "Integer" "to_string" 1 "String"
  , km "Integer" "to_string" 2 "String"
  , km "Float" "to_string" 1 "String"
  , km "Atom" "to_string" 1 "String"
  -- Regex (host)
  , km "Regex" "escape" 1 "String"
  , km "Regex" "match?" 2 "Bool"
  , km "Regex" "replace" 3 "String"
  , km "Regex" "replace" 4 "String"
  -- Path (host)
  , km "Path" "join" 1 "String"
  , km "Path" "join" 2 "String"
  , km "Path" "expand" 1 "String"
  , km "Path" "expand" 2 "String"
  , km "Path" "basename" 1 "String"
  , km "Path" "dirname" 1 "String"
  , km "Path" "extname" 1 "String"
  , km "Path" "relative_to" 2 "String"
  , km "Path" "relative_to_cwd" 1 "String"
  -- IO (host effect)
  , km "IO" "puts" 1 "Symbol"
  , km "IO" "puts" 2 "Symbol"
  , km "IO" "write" 1 "Symbol"
  -- Erlang BIFs
  , km "erlang" "phash2" 1 "Int53"
  , km "erlang" "phash2" 2 "Int53"
  , km "erlang" "integer_to_binary" 1 "String"
  , km "erlang" "integer_to_binary" 2 "String"
  , km "erlang" "float_to_binary" 1 "String"
  , km "erlang" "float_to_binary" 2 "String"
  , km "erlang" "atom_to_binary" 1 "String"
  , km "erlang" "atom_to_binary" 2 "String"
  , km "erlang" "binary_to_atom" 1 "Symbol"
  , km "erlang" "binary_to_atom" 2 "Symbol"
  -- arbitrary-precision / unbounded → `Int`.
  , km "erlang" "binary_to_integer" 1 "Int"
  , km "erlang" "unique_integer" 0 "Int"
  , km "erlang" "unique_integer" 1 "Int"
  , km "erlang" "system_time" 0 "Int"
  , km "erlang" "system_time" 1 "Int"
  , km "file" "format_error" 1 "String"
  , km "math" "pi" 0 "Float64"
  , km "math" "sqrt" 1 "Float64"
  , km "math" "pow" 2 "Float64"
  ]

-- ── the fixed-head polymorphic table (`polySig`) ─────────────────────────────

p :: String -> String -> Int -> Array String -> String -> Array String -> Tuple Key PolySig
p m fun arity params r tvars = Tuple { mod: Just m, fun, arity } { params, ret: r, tvars }

poly :: Array (Tuple Key PolySig)
poly =
  [ p "List" "reverse" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "List" "map" 2 [ "Vec(T)", "Fn(T,U)" ] "Vec(U)" [ "T", "U" ]
  , p "List" "filter" 2 [ "Vec(T)", "Fn(T,Bool)" ] "Vec(T)" [ "T" ]
  , p "List" "reject" 2 [ "Vec(T)", "Fn(T,Bool)" ] "Vec(T)" [ "T" ]
  , p "List" "flat_map" 2 [ "Vec(T)", "Fn(T,Vec(U))" ] "Vec(U)" [ "T", "U" ]
  , p "List" "concat" 2 [ "Vec(T)", "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "List" "take" 2 [ "Vec(T)", "Int53" ] "Vec(T)" [ "T" ]
  , p "List" "drop" 2 [ "Vec(T)", "Int53" ] "Vec(T)" [ "T" ]
  , p "List" "sort" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "List" "uniq" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "Enum" "map" 2 [ "Vec(T)", "Fn(T,U)" ] "Vec(U)" [ "T", "U" ]
  , p "Enum" "filter" 2 [ "Vec(T)", "Fn(T,Bool)" ] "Vec(T)" [ "T" ]
  , p "Enum" "reject" 2 [ "Vec(T)", "Fn(T,Bool)" ] "Vec(T)" [ "T" ]
  , p "Enum" "uniq" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "Enum" "reverse" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "Enum" "sort" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "Enum" "to_list" 1 [ "Vec(T)" ] "Vec(T)" [ "T" ]
  , p "Enum" "map_reduce" 3 [ "Vec(T)", "A", "Fn(T,A,(U,A))" ] "(Vec(Any),Any)" []
  , p "List" "map_reduce" 3 [ "Vec(T)", "A", "Fn(T,A,(U,A))" ] "(Vec(Any),Any)" []
  , p "Map" "new" 0 [] "Dict(Any,Any)" []
  , p "Map" "new" 1 [ "Vec(T)" ] "Dict(Any,Any)" [ "T" ]
  , p "Map" "new" 2 [ "Vec(T)", "Fn(T,U)" ] "Dict(Any,Any)" [ "T", "U" ]
  , p "Map" "put" 3 [ "Dict(K,V)", "K", "V" ] "Dict(K,V)" [ "K", "V" ]
  , p "Map" "delete" 2 [ "Dict(K,V)", "K" ] "Dict(K,V)" [ "K", "V" ]
  , p "Map" "update" 4 [ "Dict(K,V)", "K", "V", "Fn(V,V)" ] "Dict(K,V)" [ "K", "V" ]
  , p "Map" "merge" 2 [ "Dict(K,V)", "Dict(K,V)" ] "Dict(K,V)" [ "K", "V" ]
  ]

-- ── parity entry ─────────────────────────────────────────────────────────────

-- | The `bui` stream: `known`/`ret`/`polySig` for a `mod;fun;arity` key (`mod` = `nil` for a
-- | Kernel auto-import). Serialized as `known=<bool> ret=<ty|:nil> poly=<sig|:nil>`.
builtinSexpr :: String -> String
builtinSexpr src = case split (Str.Pattern ";") src of
  [ m, f, a ] ->
    let
      modv = if m == "nil" then Nothing else Just m
      arity = maybe (-1) identity (Int.fromString a)
    in
      "known=" <> show (known modv f arity)
        <> " ret=" <> maybe ":nil" identity (ret modv f arity)
        <> " poly=" <> maybe ":nil" polyStr (polySig modv f arity)
  _ -> "?"

polyStr :: PolySig -> String
polyStr ps = "(" <> joinWith "," ps.params <> ");" <> ps.ret <> ";" <> joinWith "," ps.tvars
