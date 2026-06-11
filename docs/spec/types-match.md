# Rian Language Specification — Type Declarations & `match`

**Status:** Locked (PoC) · **Refs:** ADR-0011..ADR-0014 · **Owner:** Julian Vance
**Companion to:** `rian-spec-clauses-guards.md` (shares its §3 patterns and §4 guards)
**Targets:** Elixir (BEAM, complete) · Rust (idiomatic, superset)

This spec closes the forward references made by the clause spec (`type Tree(T) := …`,
`match`). The `match` expression reuses the clause spec's pattern language, guard
sublanguage, exhaustiveness engine, and union-narrowing lowering.

---

## 1. Declaration forms

```
# sum type (nullary + payload variants), generic, recursive
type Tree(T) := Leaf | Node(left Tree(T), value T, right Tree(T))

# sum type, simple enum
type Color := Red | Green | Blue

# sum type with payloads
type Shape := Circle(radius f64) | Square(side f64)

# record / product type  -> Elixir struct, Rust struct
struct Point(x f64, y f64)

# transparent synonym -> Rust `type Id = i64;`, nothing on Elixir
alias Id := i64
```

Three keywords, each with a distinct target representation:

| Keyword | Concept | Elixir | Rust |
|---|---|---|---|
| `type` | sealed sum (ADT) | atom / tagged tuple | `enum` |
| `struct` | product / record | `defstruct` (`%Name{}`) | `struct` |
| `alias` | transparent synonym | `@type` (transparent) | `type X = …` |

---

## 2. EBNF grammar

```ebnf
declaration  = type_decl | struct_decl | alias_decl ;

type_decl    = "type" TypeName [ type_params ] ":=" variants ;
variants     = variant { "|" variant } ;
variant      = CtorName [ "(" fields ")" ] ;

struct_decl  = "struct" TypeName [ type_params ] "(" fields ")" ;
alias_decl   = "alias" TypeName [ type_params ] ":=" type ;

type_params  = "(" TypeVar { "," TypeVar } ")" ;     (* e.g. (T), (K, V) *)

fields       = field { "," field } ;
field        = [ label ] [ capability ] type ;       (* label: lowercase, no colon *)
label        = name ;
capability   = "iso" | "val" | "ref" | "tag" ;        (* default: val *)

(* ---- match expression ---- *)
match_expr   = "match" expr "do" arm { arm } "end" ;
arm          = pattern [ "when" guard_expr ] "->" arm_body ;
arm_body     = { stmt } expr ;        (* implicit return; ends at next arm or `end` *)
```

- `field = [label] [capability] type`: a lowercase name before a type is a **label**;
  a type alone is an **unlabeled positional field**. Labels are compile-time only.
- Patterns matching variants are **positional** (`Circle(r)`, `Node(l, _, r)`); named-field
  patterns are deferred (§8).
- Construction uses positional (`Circle(1.0)`) or named (`Circle(radius: 1.0)`) args;
  the `key: value` form is the same association syntax used by map literals.

---

## 3. Encoding rules (BEAM)

Adopted from the Gleam custom-type encoding (proven, statically typed on the BEAM):

1. **Nullary variant** → atom in snake_case: `Leaf` → `:leaf`, `Red` → `:red`.
2. **Variant with fields** → tagged tuple, first element the snake_case atom tag,
   remaining elements the fields **in declaration order**: `Node(l, v, r)` → `{:node, l, v, r}`.
3. **Labels are erased** at the BEAM runtime (compile-time ergonomics only).
4. **snake_case collision** between two variant tags is a **compile error**.
5. `struct Name(...)` → `%Name{...}` (a real Elixir struct, fields preserved).
6. `alias` introduces no runtime representation.

---

## 4. Lowering tables

### 4.1 `type` (sum) → Elixir / Rust

```
type Shape := Circle(radius f64) | Square(side f64)
```
```elixir
@type shape :: {:circle, float()} | {:square, float()}
# constructors (generated helpers):
#   Circle(radius: r) => {:circle, r}
#   Square(side: s)   => {:square, s}
```
```rust
#[derive(Clone, Debug, PartialEq)]   // auto-derived for val-only types
enum Shape {
    Circle { radius: f64 },
    Square { side: f64 },
}
```

### 4.2 Generic + recursive (auto-boxing on Rust)

```
type Tree(T) := Leaf | Node(left Tree(T), value T, right Tree(T))
```
```elixir
@type tree(t) :: :leaf | {:node, tree(t), t, tree(t)}
```
```rust
#[derive(Clone, Debug, PartialEq)]
enum Tree<T> {
    Leaf,
    Node { left: Box<Tree<T>>, value: T, right: Box<Tree<T>> },  // recursive => Box
}
```
Constructor lowering auto-boxes recursive fields:
`Node(left: l, value: v, right: r)` → `Tree::Node { left: Box::new(l), value: v, right: Box::new(r) }`.

### 4.3 `struct` → Elixir / Rust

```
struct Point(x f64, y f64)
```
```elixir
defmodule Point do
  defstruct [:x, :y]
  @type t :: %Point{x: float(), y: float()}
end
```
```rust
#[derive(Clone, Debug, PartialEq)]
struct Point { x: f64, y: f64 }
```

### 4.4 `alias` → Elixir / Rust

```
alias Id := i64
```
```elixir
@type id :: integer()        # transparent; Id and i64 interchangeable
```
```rust
type Id = i64;               // transparent synonym
```

### 4.5 Field capabilities

| Field cap | Rust | Elixir | Note |
|---|---|---|---|
| `val` (default) | `T` / `Box<T>` if recursive | term | shareable, immutable |
| `iso` | owned `T` / `Box<T>` | linear handle | unique; affects `Clone` derivation |
| `ref` | `&mut T` | — | BEAM-illegal unless process-local |
| `tag` | `*const ()` / id | `pid`/`ref` | identity only |

A type containing an `iso` field is **not** auto-`Clone`d (only `Debug`).

---

## 5. The `match` expression

`match` is an **expression** (yields a value) on both targets, reusing the clause spec's
pattern (§3) and guard (§4) grammar, exhaustiveness engine (§6), and union-narrowing
lowering (§5.3).

```
fn area(Shape) f64
fn area(s) :=
  match s do
    Circle(r) -> pi * r * r
    Square(s) -> s * s
  end
```
```elixir
def area(s) do
  case s do
    {:circle, r} -> 3.14159265 * r * r
    {:square, s} -> s * s
  end
end
```
```rust
fn area(s: Shape) -> f64 {
    match s {
        Shape::Circle { radius: r } => std::f64::consts::PI * r * r,
        Shape::Square { side: s }   => s * s,
    }
}
```

Rules:
- Arms use `->` (consistent with Elixir `case` and Rian lambdas); `fn` bodies keep `:=`.
- Arm bodies are **implicit blocks**: a sequence of expressions, last is the value; the arm
  ends at the next arm header (`pattern [when …] ->`) or `end`. No `do` per arm.
- **Exhaustiveness is required and static** (same engine as `fn` clauses): `_` or full
  structural coverage; **guarded arms do not count**.
- First-match, top-to-bottom on both targets.
- Union narrowing lowers to a **guard on Elixir, a pattern arm on Rust** (clause spec §5.3).

---

## 6. Worked example (end to end)

```
type Json :=
    JNull
  | JBool(bool)
  | JNum(f64)
  | JStr(str)
  | JArr(Vec(Json))

fn type_of(Json) str
fn type_of(j) :=
  match j do
    JNull    -> "null"
    JBool(_) -> "bool"
    JNum(n) when n == 0.0 -> "zero"
    JNum(_)  -> "number"
    JStr(_)  -> "string"
    JArr(_)  -> "array"
  end
```
```elixir
# representation: :j_null | {:j_bool, b} | {:j_num, n} | {:j_str, s} | {:j_arr, xs}
def type_of(j) do
  case j do
    :j_null            -> "null"
    {:j_bool, _}       -> "bool"
    {:j_num, n} when n == 0.0 -> "zero"
    {:j_num, _}        -> "number"
    {:j_str, _}        -> "string"
    {:j_arr, _}        -> "array"
  end
end
```
```rust
#[derive(Clone, Debug, PartialEq)]
enum Json {
    JNull,
    JBool(bool),
    JNum(f64),
    JStr(String),
    JArr(Vec<Json>),     // self-reference through Vec; no extra Box needed
}

fn type_of(j: Json) -> &'static str {
    match j {
        Json::JNull           => "null",
        Json::JBool(_)        => "bool",
        Json::JNum(n) if n == 0.0 => "zero",
        Json::JNum(_)         => "number",
        Json::JStr(_)         => "string",
        Json::JArr(_)         => "array",
    }
}
```
Notes: positional unlabeled variants (`JBool(bool)`) lower to Rust tuple variants;
`Vec(Json)` makes the type recursive *through* `Vec`, which is already heap-indirected, so no
extra `Box` is inserted; the guarded arm (`when n == 0.0`) is backed by the unguarded
`JNum(_)`, so the match is exhaustive on both targets.

---

## 7. Rejected / deferred

| Form | Status | Reason |
|---|---|---|
| Open / extensible sum types | Rejected | Rust enums are closed; needed for exhaustiveness |
| Inline structural unions to Rust (`int \| str`) | BEAM-only | No idiomatic Rust form; declare a `type` |
| Named-field patterns (`Circle(radius: r)`) | Deferred | Positional patterns are canonical (labels erased) |
| Generic bounds / constraints (`T: Ord`) | Deferred | Parametric only in PoC; revisit with comptime/traits |
| Unifying `struct`/`type`/`alias` under one keyword | Rejected | Loses idiomatic `%Name{}` records and transparent aliases |
| `do`-delimited match arms | Rejected | Arms are implicit blocks ending at next header / `end` |

---

## 8. Open items for next ADR
- Mutual recursion across multiple `type` declarations — boxing/cycle detection on Rust.
- Whether `struct` supports `@enforce_keys` semantics by default (non-optional fields).
- Named-field pattern sugar (`Circle(radius: r)`) once labels need to survive into matching.
- Constructor helper generation strategy on Elixir (functions vs macros) for arity/typespec.
