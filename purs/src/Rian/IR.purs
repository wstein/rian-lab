-- | The core intermediate representation — the typed records the declaration parser
-- | (`Rian.Decl`) emits and the lowering backend consumes. The PureScript port of
-- | `Rian.IR` (lib/rian/ir.ex), ADR-0084 / ADR-0050.
-- |
-- | This module grows with `Rian.Decl`'s stages: the data-type records (`Field`,
-- | `Variant`, `Type`, `Struct`) land with the `type`/`struct` parser; `Param`/`Clause`/
-- | `Func`/`Mod`/`Const`/`Range`/`Opaque`/`Use` arrive with the `def`/`mod`/… stages.
-- |
-- | Note: the Rian field is `type`; the PureScript record uses `ty` (a reserved word in
-- | PS), bridged by the `@rian_sig` annotation. The capability on a field (`val`/`iso`/…)
-- | is parsed-and-dropped today (the `Field` record carries no `cap`, matching the Elixir
-- | reference — field-cap lowering is a later concern, capability-lowering.md §5).
module Rian.IR
  ( Field
  , Variant
  , Type
  , Struct
  , Cap(..)
  , Param
  , Clause
  , Func
  , Const
  , Use
  , Range
  , Opaque
  , Mod
  , Prog
  ) where

import Prelude

import Data.Maybe (Maybe)
import Data.Tuple (Tuple)
import Rian.Pratt (Pat)

-- @rian_sig struct Field(label Option(String), type val String)
type Field = { label :: Maybe String, ty :: String }

-- @rian_sig struct Variant(ctor String, fields Vec(Field))
type Variant = { ctor :: String, fields :: Array Field }

-- @rian_sig struct Type(name String, variants Vec(Variant), is_pub Bool, doc Option(String))
type Type = { name :: String, variants :: Array Variant, pub :: Boolean, doc :: Maybe String }

-- @rian_sig struct Struct(name String, fields Vec(Field), is_pub Bool, doc Option(String))
type Struct = { name :: String, fields :: Array Field, pub :: Boolean, doc :: Maybe String }

-- @rian_sig type Cap := Val | Iso | Ref | Tag
data Cap = Val | Iso | Ref | Tag

derive instance Eq Cap

-- A function parameter: `name`, reference `cap`ability, and `ty` (`Nothing` = infer-local,
-- the Elixir `:infer`).
-- @rian_sig struct Param(name String, ty String, cap Cap)
type Param = { name :: String, ty :: Maybe String, cap :: Cap }

-- One function clause: argument `pats` (surface patterns), a `body` source string (`Nothing`
-- for a bodiless signature), and an optional `guard` source string.
-- @rian_sig struct Clause(pats Vec(Pat), body Core, guard Option(Core))
type Clause = { pats :: Array Pat, body :: Maybe String, guard :: Maybe String }

-- A function: `name`, `params`, return type `ret`, `clauses`. `tvars`/`bounds` are the
-- `forall` binders (ADR-0042). (synthetic/dispatch/externals/effects/test land later.)
-- @rian_sig struct Func(name String, params Vec(Param), ret String, clauses Vec(Clause), is_pub Bool, tvars Vec(String), bounds Map(String, Vec(String)), doc Option(String))
type Func =
  { name :: String
  , params :: Array Param
  , ret :: Maybe String
  , clauses :: Array Clause
  , pub :: Boolean
  , tvars :: Array String
  , bounds :: Array (Tuple String (Array String))
  , doc :: Maybe String
  }

-- A module-scoped constant (`const NAME [Type] := value`). `ty` is `Nothing` when omitted
-- (inferred from the value's literal shape). `value` is the body source.
-- @rian_sig struct Const(name String, ty String, value String, is_pub Bool, doc Option(String))
type Const = { name :: String, ty :: Maybe String, value :: String, pub :: Boolean, doc :: Maybe String }

-- An import inside a module: `use Path` (qualified) or `use Path.(a, b)` (selective).
-- @rian_sig struct Use(path String, names Vec(String))
type Use = { path :: String, names :: Array String }

-- A finite ordinal subrange type (`range Name := lo..hi`, ADR-0036). `lo`/`hi` are inclusive
-- integer bounds (a `Char` bound is its codepoint); `base` is `Int64` or `Char`.
-- @rian_sig struct Range(name String, base String, lo Int53, hi Int53, is_pub Bool, doc Option(String))
type Range = { name :: String, base :: String, lo :: Int, hi :: Int, pub :: Boolean, doc :: Maybe String }

-- An abstract type (`opaque Name := Base` / `abstract …`, ADR-0067/0043): nominally distinct
-- from `Base`, erased to `Base` at emit. `ops`/`casts` are the `abstract` operator/cast rules
-- (empty for a plain `opaque`; modelled as rendered strings until `abstract` lands).
-- @rian_sig struct Opaque(name String, base String, is_pub Bool, doc Option(String), ops Vec(String), casts Vec(String))
type Opaque =
  { name :: String, base :: String, pub :: Boolean, doc :: Maybe String, ops :: Array String, casts :: Array String }

-- A module (`mod Name do … end`) grouping uses/types/ranges/opaques/structs/consts/funcs.
-- @rian_sig struct Mod(name String, uses Vec(Use), types Vec(Type), ranges Vec(Range), opaques Vec(Opaque), structs Vec(Struct), consts Vec(Const), funcs Vec(Func), doc Option(String))
type Mod =
  { name :: String
  , uses :: Array Use
  , types :: Array Type
  , ranges :: Array Range
  , opaques :: Array Opaque
  , structs :: Array Struct
  , consts :: Array Const
  , funcs :: Array Func
  , doc :: Maybe String
  }

-- The whole-program IR. Top-level `const`/`use` are module-scoped (rejected at top level),
-- so the top scope carries only types/ranges/opaques/structs/funcs; `mods` hold their own.
type Prog =
  { types :: Array Type
  , ranges :: Array Range
  , opaques :: Array Opaque
  , structs :: Array Struct
  , funcs :: Array Func
  , mods :: Array Mod
  }
