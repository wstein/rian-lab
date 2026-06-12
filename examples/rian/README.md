# Rian by example

A guided tour of **Rian's surface syntax and character** — a typed,
capability-disciplined language that lowers the *same source* to two targets:
idiomatic **Elixir/BEAM** and idiomatic, ownership-checked **Rust**.

> **Status — read this first.** These files use the **ADR-0033 surface** (`def`,
> `case`, juxtaposed types, Crystal primitives like `Int64`). A **Stage 0.1
> declaration parser** ([`Rian.Decl`](../../lib/rian/decl.ex),
> [ADR-0031](../../docs/adr/0031-bootstrap-strategy.md)) now compiles the
> `type` + `def` subset of this surface end-to-end — parse → Elixir + Rust → run
> (`mix run examples/decl_run.exs`). These tour files reach **beyond** that MVP
> (`mod`, `struct`, `alias`, `case` bodies, macros, `extern`), so they stay
> **illustrative** until the parser broadens; the verified passes are also
> exercised through the hand-built-IR drivers in the
> [project README](../../README.md). See the
> [design corpus](../../docs/README.md) for the spec/ADR map.

## The files

| File | Shows |
| --- | --- |
| [01_basics.rian](01_basics.rian) | Expression-orientation, `:=` single-assignment, `if`/blocks, the operator table (`/` vs `div`, `<>`, `\|>`, non-associative comparisons) |
| [02_types_match.rian](02_types_match.rian) | `type` / `struct` / `alias`, the `case` expression, recursive sums, guarded arms |
| [03_clauses_guards.rian](03_clauses_guards.rian) | Multi-clause functions, the restricted guard sublanguage, static exhaustiveness, union narrowing, `@partial` |
| [04_capabilities.rian](04_capabilities.rian) | **The heart of the language** — `val`/`iso`/`ref`/`tag` driving Rust ownership and BEAM linearity, with no lifetimes |
| [05_modules.rian](05_modules.rian) | `mod`, `pub`, `use`, `const`, and `.` as the universal qualifier |
| [06_macros_comptime.rian](06_macros_comptime.rian) | Declarative pattern→template macros (hygienic, no `quote`/`unquote`) and the pure `comptime` sandbox |
| [07_ffi.rian](07_ffi.rian) | Free BEAM interop — atom-head Erlang calls, PascalCase Elixir calls, `extern` typed bindings |
| [08_lambdas_collections.rian](08_lambdas_collections.rian) | Lambdas, `if`/block bodies, list/map literals, and the BEAM-only refusals on Rust |
| [09_capstone_calc.rian](09_capstone_calc.rian) | A complete tiny evaluator tying it all together, including the portable-core vs BEAM-only boundary |
| [10_function_forms.rian](10_function_forms.rian) | Every function body form — `:=` one-liner, multiline **block body** (`… end`), multi-clause groups mixing both, and lambdas |
| [11_wire_formats.rian](11_wire_formats.rian) | Binary wire formats — `@wire` structs deriving byte-exact `decode`/`encode` (length-prefixed, nested, streaming), erroring as values |
| [12_error_handling.rian](12_error_handling.rian) | Errors as values — sealed error sets, the `T \| E` Result sugar, `{:ok,_}`/`{:error,_}`, and `with`/`else` propagation (compiles end-to-end) |

Suggested reading order is numeric; 04 is the one to linger on — it is what
distinguishes Rian from "Elixir with different keywords."

### Function body forms

A `def` body is one of two shapes (no semantic difference — both yield a value
via implicit return), plus the anonymous lambda form:

```elixir
def double(n Int64) Int64 := n * 2          # 1. single-expression body (the one-liner)

def norm(v val Vec(Float64)) Float64            # 2. block body — multiline, last expr is the value
  total := v |> sum
  total / len(v)
end

(x) -> x * 2                           # 3. lambda — anonymous, single-expression
```

Both single-clause and multi-clause functions may use **either** body form, and
a multi-clause group may mix them clause by clause (see
[10_function_forms.rian](10_function_forms.rian)). There is no `return` keyword.

## Syntax cheat-sheet

```elixir
# comments start with `#`

def add(x Int64, y Int64) Int64 := x + y          # single clause: typed head is the boundary

def classify(Int64) String                       # bodiless SIGNATURE line ...
def classify(0)            := "zero"         # ... followed by contiguous
def classify(n) when n > 0 := "positive"    #     pattern-head clauses
def classify(_)            := "negative"

name := expr                               # single-assignment binding (shadow, never mutate)
total <~ expr                              # mutation — capability-gated, BEAM-illegal unless local

if c do a else b end                       # `if` is an expression; `else` is REQUIRED in value position
case x do P -> e   ...   end              # `case` is an expression; arms use `->`, must be exhaustive

(x) -> x * 2                               # lambda
[1, 2, 3]      [h | t]      %{a: 1}        # list / cons / map literals

type T := A | B(payload Float64)               # sealed sum (ADT)
struct P(x Float64, y Float64)                     # product / record
alias Id := Int64                            # transparent synonym

def f(s val Shape) ...   # val (default, borrow) | iso (owned/use-once) | ref (&mut) | tag (identity)

Geometry.area(x)   # Rian module call      point.x         # field access
Value.Num(n)       # variant path          :lists.sum(xs)  # Erlang FFI (atom head)
String.upcase(s)   # Elixir-lib FFI

macro square(x) => x * x                   # declarative macro (AST substitution, hygienic)
comptime(2 + 3 * 4)                        # pure compile-time constant folding -> 14
```

## Operator precedence (tightest → loosest)

`f(…)` · `.field` › unary `-`/`not` › `* / rem div` › `+ -` › `<>` › `in` ›
`|>` › `< <= > >=` *(non-assoc)* › `== !=` *(non-assoc)* › `and` › `or` › `<~`.

See [docs/spec/expressions.md](../../docs/spec/expressions.md) for the full table
and worked consequences.

## Seeing them actually run (today)

The Stage 0.1 parser compiles a real `.rian` file from the `type`+`def` subset:

```sh
mix run examples/decl_run.exs       # reads examples/area.rian -> Elixir + Rust, executed
```

The fuller surface is exercised through Elixir drivers that feed hand-built IR
equivalent to the source above:

```sh
mix run examples/lower_run.exs      # area/1: Rian source -> Elixir + Rust, executed
mix run examples/dot_run.exs        # `.` qualifier lowering + a Value match
mix run examples/features_run.exs   # lambdas, if/blocks, list/map literals on the BEAM
mix run examples/macro_run.exs      # macros + comptime, hygiene proven (hyg(5) = 105)
mix run examples/selfhost_run.exs   # FFI to :lists / String, executed on the BEAM
mix run examples/cap_run.exs        # capability -> Rust signature matrix + BEAM linearity
```

Each driver prints the emitted Elixir and Rust for the corresponding `.rian`
constructs and runs the BEAM output to prove it. The `.rian` files here are the
human-facing surface those drivers stand in for.
