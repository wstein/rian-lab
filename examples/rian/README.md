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

Outside the numbered tour, two **self-hosting spikes** are written in Rian and
compile + run on real BEAM bytecode:

- [selfhost_lexer.rian](selfhost_lexer.rian) — a real arithmetic lexer (its own
  `Token` sum, list-pattern recursion).
- [selfhost_parser.rian](selfhost_parser.rian) — a precedence-climbing
  expression parser (a slice of `Rian.Pratt`) that consumes the lexer's
  `Vec(Token)`, builds its own `Expr` sum, and threads `(Expr, Vec(Token))` as a
  `Parse` pair. It exercises higher-order-free recursion, sum construction,
  nested list/variant patterns, and `case` — and hits **no** backend wall.
- [selfhost_eval.rian](selfhost_eval.rian) — an evaluator that folds the `Expr`
  sum to an `Int64`, threading a **symbol table** (`Map(String, Int64)`) with
  `let`-binding and `Var` lookup. The symbol table is the first place that
  reaches for a map; its empty initial environment `%{}` was the construct that
  drove the BEAM **map-literal** increment.
- [selfhost_check.rian](selfhost_check.rian) — a type-checker pass that infers a
  `Ty` (`TInt`/`TBool`) for the `Expr` language, reporting a **structured type
  error** via a `struct Mismatch(op, expected, got)`. The diagnostic record is
  the first place a checker wants a `struct`; it drove the BEAM **struct**
  increment (a struct value is a tagged map, read by field access).
- [selfhost_codegen.rian](selfhost_codegen.rian) — a **code generator + stack
  VM**: it compiles the `Expr` sum to a post-order list of `Instr` and executes
  them on a stack (`Vec(Int64)`). It handles **variables and `let`** via
  load/store **slots** — the generator threads a compile-time `name → slot`
  environment and the VM threads a slot store (`Map(Int64, Int64)`) — so
  `let x = 5 in x + 1` lowers to `[Push 5, Store 0, Load 0, Push 1, IAdd]`. The
  full `lex → parse → codegen → run` pipeline runs on `.beam`; no backend wall.
- [selfhost_opt.rian](selfhost_opt.rian) — an **optimizer** (constant folding +
  algebraic identities: `2 + 3 → 5`, `x * 1 → x`, `x * 0 → 0`). It matches IR
  nodes by shape with nested variant and literal-in-variant patterns
  (`Add(Num(a), Num(b))`, `Mul(_, Num(0))`) — and hits **no** wall. Slotting it
  before codegen shrinks the emitted program (`(2 + 3) * 4` → a single `Push 20`).
  Being variant-only, it is **tri-target**: it lowers to BEAM (runs), Rust (an
  idiomatic `enum` + `match`), and JavaScript (runs under node) — one IR, three
  back ends (ADR-0050).
- [selfhost_calc.rian](selfhost_calc.rian) — **the whole calc compiler in one
  Rian module.** It ties every layer above (lexer, parser, optimizer, code
  generator, stack VM) into a single self-contained program compiled to one
  `.beam`: `run("1 + 2 * (3 - 4)") → -1`. `String → Vec(Token) → Expr → Expr′ →
  Vec(Instr) → Int64`, end to end — the front-to-back pipeline as one artifact.
  It also parses **`let`-bindings and variables** from source — the lexer scans
  identifiers and the `let`/`in` keywords, the parser builds `Let`/`Var`, and the
  codegen allocates slots: `run("let x = 5 in x + 1") → 6`, with correct lexical
  shadowing. It also parses top-level **`def` declarations** — a program is a run
  of `def name = expr;` declarations then a result, desugared to nested `let`s:
  `run("def a = 2; def b = 3; a * b + a") → 8`. The whole pipeline also **lowers
  to JavaScript and runs under node** (`Rian.JS.compile`), so the calc runs on
  two targets.
- [selfhost_modules.rian](selfhost_modules.rian) — **the same calc split across
  many modules.** `mod CalcLex` / `CalcParse` / `CalcGen` / `Calc` each compile
  to their own BEAM module (`Elixir.CalcLex`, …); the driver `Calc.run` calls
  across them by name (`CalcLex.lex(…)`), and variant tags are global so a module
  pattern-matches another's data without re-declaring the type. Load with
  `Rian.Beam.load_program/1`.

- [selfhost_funcs.rian](selfhost_funcs.rian) — **user-defined functions +
  recursion.** A tree-walking interpreter whose program is a function table
  (`name → Fun` of params + body) plus an `Expr`; a call binds its arguments in a
  fresh environment and recurses, so self- and mutual recursion work
  (`fact(5) = 120`, `even`/`odd`). Runs on BEAM and under node.
- [selfhost_listlib.rian](selfhost_listlib.rian) — **a portable `List` library
  (ADR-0047 §2)** — `reverse`/`append`/`length`/`sum` written in Rian over cons
  recursion, **no host FFI** — so it lowers to every backend through the same
  machinery (verified on BEAM and node). The right way to retire per-emitter FFI
  stopgaps for lists.
- [prelude_dict.rian](prelude_dict.rian) — **a portable `Dict` over a `__prim_*`
  primitive layer (ADR-0047 §2).** A `Map` can't be pure Rian (it bottoms out in
  a BEAM map / JS object / Rust `HashMap`), so a tiny set of `__prim_map_*` calls
  is lowered natively by each backend, and the useful composite ops (`get_or`,
  `inc`) are written **once in Rian** over them. `inc`/`get_or` run on BEAM and
  under node; only the four primitives are per-target.
- [prelude_str.rian](prelude_str.rian) — **a portable `Str` over `__prim_str_*`
  (ADR-0047 §2).** `chars`/`from_chars`/`concat` forward to per-target primitives
  (BEAM `String.to_charlist`/`List.to_string`/binary-append; JS codepoints/`+`;
  Rust `chars()`/`collect()`/`format!`) — all three lower and run. With it,
  [selfhost_lexer.rian](selfhost_lexer.rian) uses `__prim_str_chars` instead of
  host FFI, so its source is portable (it now runs on BEAM **and** under node).
- [prelude_int.rian](prelude_int.rian) — **explicit overflow ops over `__prim_*`
  (ADR-0035 §3).** Bare `+` on `Int64` is native-per-target (bignum on BEAM/JS, a
  panicking/wrapping `i64` on Rust); when you need one deterministic answer
  everywhere, `Int.wrapping_add`/`saturating_add`/`checked_add` project the sum
  onto the 64-bit domain — Rust's native `i64::{wrapping,saturating,checked}_add`,
  a bignum projection on BEAM/JS. `checked_add` returns `Option(Int64)`, surfacing
  overflow in the type (no hidden control flow). Prefer a **subrange** (ADR-0036)
  when the bound is known at the type level; these are the unbounded-`Int64`
  fallback. Verified on BEAM, rustc, and node.

See [SELFHOST.md](../../SELFHOST.md) for the blocker ledger they produced.

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
