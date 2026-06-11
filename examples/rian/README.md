# Rian by example

A guided tour of **Rian's surface syntax and character** — a typed,
capability-disciplined language that lowers the *same source* to two targets:
idiomatic **Elixir/BEAM** and idiomatic, ownership-checked **Rust**.

> **Status — read this first.** These `.rian` files are **illustrative source**,
> validated against the specs and ADRs catalogued in the
> [design corpus](../../docs/README.md) — they are **not yet compilable**. Rian
> has no lexer or declaration parser yet
> ([ADR-0031](../../docs/adr/0031-bootstrap-strategy.md), Stage 0.1 — the gate
> to compiling real files). The compiler's passes today are driven by
> hand-built IR, demonstrated by the runnable Elixir drivers catalogued in the
> [project README](../../README.md). This is exactly how the corpus itself
> presents Rian source: as the surface the verified passes will consume once the
> parser lands.

## The files

| File | Shows |
| --- | --- |
| [01_basics.rian](01_basics.rian) | Expression-orientation, `:=` single-assignment, `if`/blocks, the operator table (`/` vs `div`, `<>`, `\|>`, non-associative comparisons) |
| [02_types_match.rian](02_types_match.rian) | `type` / `struct` / `alias`, the `match` expression, recursive sums, guarded arms |
| [03_clauses_guards.rian](03_clauses_guards.rian) | Multi-clause functions, the restricted guard sublanguage, static exhaustiveness, union narrowing, `@partial` |
| [04_capabilities.rian](04_capabilities.rian) | **The heart of the language** — `val`/`iso`/`ref`/`tag` driving Rust ownership and BEAM linearity, with no lifetimes |
| [05_modules.rian](05_modules.rian) | `mod`, `pub`, `use`, `const`, and `.` as the universal qualifier |
| [06_macros_comptime.rian](06_macros_comptime.rian) | Declarative pattern→template macros (hygienic, no `quote`/`unquote`) and the pure `comptime` sandbox |
| [07_ffi.rian](07_ffi.rian) | Free BEAM interop — atom-head Erlang calls, PascalCase Elixir calls, `extern` typed bindings |
| [08_lambdas_collections.rian](08_lambdas_collections.rian) | Lambdas, `if`/block bodies, list/map literals, and the BEAM-only refusals on Rust |
| [09_capstone_calc.rian](09_capstone_calc.rian) | A complete tiny evaluator tying it all together, including the portable-core vs BEAM-only boundary |
| [10_function_forms.rian](10_function_forms.rian) | Every function body form — `:=` one-liner, multiline **block body** (`… end`), multi-clause groups mixing both, and lambdas |

Suggested reading order is numeric; 04 is the one to linger on — it is what
distinguishes Rian from "Elixir with different keywords."

### Function body forms

A `fn` body is one of two shapes (no semantic difference — both yield a value
via implicit return), plus the anonymous lambda form:

```elixir
fn double(n i64) i64 := n * 2          # 1. single-expression body (the one-liner)

fn norm(v val Vec(f64)) f64            # 2. block body — multiline, last expr is the value
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

fn add(x i64, y i64) i64 := x + y          # single clause: typed head is the boundary

fn classify(i64) str                       # bodiless SIGNATURE line ...
fn classify(0)            := "zero"         # ... followed by contiguous
fn classify(n) when n > 0 := "positive"    #     pattern-head clauses
fn classify(_)            := "negative"

name := expr                               # single-assignment binding (shadow, never mutate)
total <- expr                              # mutation — capability-gated, BEAM-illegal unless local

if c do a else b end                       # `if` is an expression; `else` is REQUIRED in value position
match x do P -> e   ...   end              # `match` is an expression; arms use `->`, must be exhaustive

(x) -> x * 2                               # lambda
[1, 2, 3]      [h | t]      %{a: 1}        # list / cons / map literals

type T := A | B(payload f64)               # sealed sum (ADT)
struct P(x f64, y f64)                     # product / record
alias Id := i64                            # transparent synonym

fn f(s val Shape) ...   # val (default, borrow) | iso (owned/use-once) | ref (&mut) | tag (identity)

Geometry.area(x)   # Rian module call      point.x         # field access
Value.Num(n)       # variant path          :lists.sum(xs)  # Erlang FFI (atom head)
String.upcase(s)   # Elixir-lib FFI

macro square(x) => x * x                   # declarative macro (AST substitution, hygienic)
comptime(2 + 3 * 4)                        # pure compile-time constant folding -> 14
```

## Operator precedence (tightest → loosest)

`f(…)` · `.field` › unary `-`/`not` › `* / rem div` › `+ -` › `<>` › `in` ›
`|>` › `< <= > >=` *(non-assoc)* › `== !=` *(non-assoc)* › `and` › `or` › `<-`.

See [docs/spec/expressions.md](../../docs/spec/expressions.md) for the full table
and worked consequences.

## Seeing them actually run (today)

Until the parser lands, the verified passes are exercised through Elixir
drivers that feed hand-built IR equivalent to the source above:

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
