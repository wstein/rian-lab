# Rian Language Specification — Modules, Visibility & Imports

**Status:** Locked (PoC) · **Refs:** ADR-0019..ADR-0021 · **Owner:** Julian Vance
**Targets:** Elixir (BEAM, complete) · Rust (idiomatic, superset)

---

## 1. Forms

```
mod Geometry do
  use Std.(Vec, sqrt)            # unqualified import
  use Math                        # qualified import (Math.pi)

  pub type Shape := Circle(radius f64) | Square(side f64)

  pub fn area(Shape) f64
  pub fn area(Circle(r)) := Math.pi * r * r
  pub fn area(Square(s)) := s * s

  fn helper(x f64) f64 := x * x   # private (no `pub`)
end
```

- A `mod Name do … end` groups `fn` / `type` / `struct` / `alias` / `const`.
- **Private by default; `pub` exports** (`pub fn`, `pub type`, `pub struct`, `pub const`).
- **`.` is the single, universal qualifier** (ADR-0029): `Geometry.area(x)` calls across a
  module and `point.x` reads a field, disambiguated by operand case the way Elixir does it.
  (ADR-0003 reserved `::` for paths; ADR-0029 superseded that — `::` is no longer Rian syntax.)
- Imports use `use`:
  - `use Geometry` → qualified access (`Geometry.area(…)`).
  - `use Geometry.(area, Shape)` → those names unqualified.

---

## 2. Grammar (EBNF)

```ebnf
module      = "mod" ModPath "do" { item } "end" ;
ModPath     = TypeName { "." TypeName } ;            (* Geometry, A.B *)
item        = import | const | function | type_decl | struct_decl | alias_decl ;
import      = "use" ModPath [ "." "(" use_names ")" ] ;
use_names   = use_name { "," use_name } ;
use_name    = name | TypeName ;
const       = [ "pub" ] "const" name [ type ] ":=" expr ;
function    = [ "pub" ] ( single_clause | multi_clause ) ;   (* see clause spec *)
type_decl   = [ "pub" ] (* … see types spec … *) ;
```

`pub` may prefix `fn`, `type`, `struct`, `alias`, and `const`.

---

## 3. Lowering

| Rian | Elixir | Rust |
|---|---|---|
| `mod Geometry do … end` | `defmodule Geometry do … end` | `pub mod geometry { … }` |
| `mod A.B` | `defmodule A.B` | `mod a { mod b { … } }` |
| `pub fn f` | `def f` | `pub fn f` |
| private `fn f` | `defp f` | `fn f` |
| `pub type` / `pub struct` | module type + public constructors | `pub enum` / `pub struct` |
| `pub const PI := 3.14159` | `@pi 3.14159` (+ accessor) | `pub const PI: f64 = 3.14159;` |
| `use Geometry` | `alias Geometry` | `use crate::geometry` |
| `use Geometry.(area, Shape)` | `import Geometry, only: [...]` + `alias` | `use crate::geometry::{area, Shape}` |
| `Geometry.area(x)` | `Geometry.area(x)` | `geometry::area(x)` |

Module names are PascalCase in Rian; the Rust backend lowercases path segments to follow Rust
convention (`Geometry` → `geometry`), while Elixir keeps them PascalCase.

---

## 4. Target rings & boundaries

- A module annotated `@target :rust` lowers to a Rust crate/NIF; default modules lower to
  Elixir.
- Cross-ring calls (BEAM module → `@target :rust` module) go through the Rustler-shaped NIF
  boundary; only portable-core signatures may cross it (see the three-ring model).
- The subset linter flags any `pub` item in a `@target :rust` module whose signature uses a
  BEAM-only feature (open maps, dynamic, supervisors).

---

## 5. Open items
- `pub(mod)`-style restricted visibility (export to parent only) — deferred; binary pub/priv for PoC.
- Re-exports (`pub use`) and module aliases.
- Mapping of nested-module privacy to Elixir (which has flat module namespacing).
