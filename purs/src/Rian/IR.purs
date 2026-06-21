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
  , Prog
  ) where

import Data.Maybe (Maybe)

-- @rian_sig struct Field(label Option(String), type val String)
type Field = { label :: Maybe String, ty :: String }

-- @rian_sig struct Variant(ctor String, fields Vec(Field))
type Variant = { ctor :: String, fields :: Array Field }

-- @rian_sig struct Type(name String, variants Vec(Variant), is_pub Bool, doc Option(String))
type Type = { name :: String, variants :: Array Variant, pub :: Boolean, doc :: Maybe String }

-- @rian_sig struct Struct(name String, fields Vec(Field), is_pub Bool, doc Option(String))
type Struct = { name :: String, fields :: Array Field, pub :: Boolean, doc :: Maybe String }

-- The whole-program IR (the slice ported so far: data-type declarations). `funcs`/`mods`/
-- `consts`/… join as `Rian.Decl`'s remaining stages land.
type Prog = { types :: Array Type, structs :: Array Struct }
