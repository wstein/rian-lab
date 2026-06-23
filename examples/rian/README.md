# Rian by example

A guided tour of **Rian's surface syntax and character** — a typed,
capability-disciplined language that lowers the *same source* to four targets:
idiomatic **Elixir/BEAM**, ownership-checked **Rust**, **ECMAScript**, and
**Kotlin/JVM**. Portability is *inferred* per function (`Rian.Reach`), so a file
reaches the subset its features allow — not every example reaches all four, and
that is the point (see [15_targets.rian](15_targets.rian)).

> **Status — read this first.** These files use the **ADR-0033 surface** (`def`,
> `case`, juxtaposed types, `Int53` as the portable default integer). The
> [`Rian.Decl`](../../lib/rian/decl.ex) front-end now parses most of this surface,
> and the four emitters (BEAM, Rust, ECMAScript, Kotlin/JVM) lower it.
>
> **Verified vs. illustrative.** Every numbered file is one of two kinds, gated by
> CI ([`Rian.TourReachTest`](../../test/rian/tour_reach_test.exs), also run by
> `mix rian.tour --check`):
>
> - **gated** — the file parses and carries a `#@reach <targets>` header (below the
>   title banner), with a `#@reach-pin name=…` line for any function that reaches
>   less than the file's union. CI fails if the real `Rian.Reach` analysis drifts
>   from the declaration, *and* it runs the real emitter for every target in the
>   file's floor (rejecting a claim the compiler cannot actually produce), so the
>   portability claims cannot rot. Worked examples are `expr #=> value` doctests,
>   executed on the BEAM ([`Rian.TourDoctestTest`](../../test/rian/tour_doctest_test.exs)).
> - **illustrative** — the file uses surface the `Rian.Decl` front-end does not yet
>   accept (`@partial`, `extern`, `@wire`, `else if` chains). These carry an
>   `#@illustrative` banner with a reason and are *not* compiled; CI asserts they
>   stay unparseable, so the marker cannot outlive the gap.
>
> These files are also the **source of the generated tour dataset**
> (`site/src/data/tour.json`, ADR-0091): `mix rian.tour` folds each file's title,
> reach matrix, and doctests into the data the site renders, so the page shows
> exactly what CI gates. See the [design corpus](../../docs/README.md) for the
> spec/ADR map.

## The files

| File | Shows |
| --- | --- |
| [hello.rian](hello.rian) | The classic first program — `main/0` (the `mix rian.run` entry point) and console output through a portable `@external` `puts` wrapper (`IO.puts`/`console.log`), reaching `ex`/`js` |
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
| [12_error_handling.rian](12_error_handling.rian) | Errors as values — sealed error sets, the explicit `Result(T, E)` return type (the `T \| E` sugar was **removed** — ADR-0083 makes `\|` a value union everywhere), `{:ok,_}`/`{:error,_}`, and `with`/`else` propagation. Reaches `ex`/`rs`/`js` (Result pins it off `:jvm`) |
| [13_protocols.rian](13_protocols.rian) | Protocols & impls (ADR-0042) — `protocol`/`impl … for …`, first-argument dispatch, the orphan-rule coherence checks; primitive-type impls compile to a guarded BEAM dispatcher and run |
| [14_test_framework.rian](14_test_framework.rian) | Tests in Rian (ADR-0057) — `@test def name() Bool`, run by `Rian.Test` and bridged to ExUnit (one case per `@test`); the dogfooding wedge |
| [15_targets.rian](15_targets.rian) | Portability as a declaration (ADR-0058) — `@targets(ex, rs, js)` on a `mod`; the compiler gates every `pub` fn's reachability against the contract |
| [16_doctests.rian](16_doctests.rian) | Doctests (ADR-0060 tier B) — `expr #=> expected` in a `@doc` heredoc, executed by `Rian.Doctest`; a drifted example fails the build |
| [17_stdlib_eq_ord.rian](17_stdlib_eq_ord.rian) | A portable stdlib slice over `Eq`/`Ord` (ADR-0042) — `contains`/`sort`/`maximum` as **bounded generics** (`forall T: Eq`/`Ord`); the protocol's first real customer, with `@test`s + doctests |
| [18_dict_eq.rian](18_dict_eq.rian) | A `Dict` over `Eq` — `get`/`has`/`put` bounded `forall K: Eq` over a generic `Pair(k K, v V)`; "Dict keys need Eq" made real (Int53 + String keys), runs on BEAM/JS, with `@test`s + doctests |
| [19_prelude_consumer.rian](19_prelude_consumer.rian) | **Consuming the `List` prelude with closures** — `map`/`filter`/`reduce`/`member` fed `Fn` callbacks, all reaching `ex`/`rs`/`js` (the consumer side of ADR-0061 closure-as-value: `&impl Fn` params, lambdas lower per target); runs on BEAM with the prelude linked |
| [conformance_core.rian](conformance_core.rian) | The **Tier-1 admission gate** corpus (ADR-0049 §5a) — `@test`s over the portable core (`Int53` arithmetic, `div`/`rem`, comparison/boolean, multi-clause recursion + guards) that `Rian.ConformanceTest` runs on **every** Tier-1 target (`:ex`/`:rs`/`:js`); a regression on any fails the build |

Suggested reading order is numeric; 04 is the one to linger on — it is what
distinguishes Rian from "Elixir with different keywords."

Outside the numbered tour, a set of **compiler-construction spikes** are written in
Rian and compile + run on real BEAM bytecode:

- [lexer.rian](../../test/fixtures/rian/lexer.rian) — a real arithmetic lexer (its own
  `Token` sum, list-pattern recursion).
- [parser.rian](../../test/fixtures/rian/parser.rian) — a precedence-climbing
  expression parser (a slice of `Rian.Pratt`) that consumes the lexer's
  `Vec(Token)`, builds its own `Expr` sum, and threads `(Expr, Vec(Token))` as a
  `Parse` pair. It exercises higher-order-free recursion, sum construction,
  nested list/variant patterns, and `case` — and hits **no** backend wall.
- [eval.rian](../../test/fixtures/rian/eval.rian) — an evaluator that folds the `Expr`
  sum to an `Int64`, threading a **symbol table** (`Map(String, Int64)`) with
  `let`-binding and `Var` lookup. The symbol table is the first place that
  reaches for a map; its empty initial environment `%{}` was the construct that
  drove the BEAM **map-literal** increment.
- [check.rian](../../test/fixtures/rian/check.rian) — a type-checker pass that infers a
  `Ty` (`TInt`/`TBool`) for the `Expr` language, reporting a **structured type
  error** via a `struct Mismatch(op, expected, got)`. The diagnostic record is
  the first place a checker wants a `struct`; it drove the BEAM **struct**
  increment (a struct value is a tagged map, read by field access).
- [codegen.rian](../../test/fixtures/rian/codegen.rian) — a **code generator + stack
  VM**: it compiles the `Expr` sum to a post-order list of `Instr` and executes
  them on a stack (`Vec(Int64)`). It handles **variables and `let`** via
  load/store **slots** — the generator threads a compile-time `name → slot`
  environment and the VM threads a slot store (`Map(Int64, Int64)`) — so
  `let x = 5 in x + 1` lowers to `[Push 5, Store 0, Load 0, Push 1, IAdd]`. The
  full `lex → parse → codegen → run` pipeline runs on `.beam`; no backend wall.
- [opt.rian](../../test/fixtures/rian/opt.rian) — an **optimizer** (constant folding +
  algebraic identities: `2 + 3 → 5`, `x * 1 → x`, `x * 0 → 0`). It matches IR
  nodes by shape with nested variant and literal-in-variant patterns
  (`Add(Num(a), Num(b))`, `Mul(_, Num(0))`) — and hits **no** wall. Slotting it
  before codegen shrinks the emitted program (`(2 + 3) * 4` → a single `Push 20`).
  Being variant-only, it is **tri-target**: it lowers to BEAM (runs), Rust (an
  idiomatic `enum` + `match`), and JavaScript (runs under node) — one IR, three
  back ends (ADR-0050).
- [calc.rian](../../test/fixtures/rian/calc.rian) — **the whole calc compiler in one
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
- [modules.rian](../../test/fixtures/rian/modules.rian) — **the same calc split across
  many modules.** `mod CalcLex` / `CalcParse` / `CalcGen` / `Calc` each compile
  to their own BEAM module (`Elixir.CalcLex`, …); the driver `Calc.run` calls
  across them by name (`CalcLex.lex(…)`), and variant tags are global so a module
  pattern-matches another's data without re-declaring the type. Load with
  `Rian.Beam.load_program/1`.

- [funcs.rian](../../test/fixtures/rian/funcs.rian) — **user-defined functions +
  recursion.** A tree-walking interpreter whose program is a function table
  (`name → Fun` of params + body) plus an `Expr`; a call binds its arguments in a
  fresh environment and recurses, so self- and mutual recursion work
  (`fact(5) = 120`, `even`/`odd`). Runs on BEAM and under node.
- [listlib.rian](../../test/fixtures/rian/listlib.rian) — **a portable `List` library
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
  [lexer.rian](../../test/fixtures/rian/lexer.rian) uses `__prim_str_chars` instead of
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
- [prelude_list.rian](prelude_list.rian) — **the eager iterable-accepting reducers
  over a concrete list (ADR-0047 §2).** `List.sum`/`product`/`any`/`all`/`length` —
  the Python `sum`/`any`/`all`/`len` family — written **once in Rian** as pure cons
  recursion (no `__prim_*`, since a list is already portable). Each has a natural
  empty-list identity (0/1/false/true/0), so it is **total** (no `Option`, no crash),
  and all five **reach every target** (`ex`/`rs`/`js`/`jvm`, verified by
  `mix rian.targets`). A *lazy* generator/`Iterator` protocol is deliberately NOT
  provided — laziness is a per-target evaluation concern, native like concurrency
  (ADR-0057), not portable sequential logic.
- [prelude_io.rian](prelude_io.rian) — **`Console` host console output (ADR-0068).** Unlike
  the pure preludes, console output has no portable contract, so this is a thin `@external`
  wrapper — one host body per target: `puts`/`print` over `IO.puts`/`console.log`/`println!`/
  `println`. Reaches **all four** targets (verified to compile + run on BEAM, node, rustc, and
  kotlinc): the statically-typed `:rs`/`:jvm` bodies run the call **and** yield `:ok` (`Symbol`),
  since their native console call returns unit. Named `Console`, not `IO` — a Rian `mod IO` would
  shadow the host `IO` and break the BEAM's own output.
- [foldable.rian](foldable.rian) — **Tier 2: `Foldable`, eager ELEMENT-GENERIC reduction
  over a protocol (ADR-0073 + ADR-0074).** A one-method protocol with an **associated
  type** (`type Elem; to_list(self) Vec(Elem)`) bridges any container to a list, so the
  element is fixed per impl (`type Elem := Int53` / `:= String`) and ONE `fcount` reduces
  a `Bag` of `Int53` **and** a `Words` of `String` — dispatched by runtime type (ADR-0042).
  Eager — no lazy `Iterator` (rejected, ADR-0057). Honest reach: a sum-dispatch consumer
  is `[:ex, :js]` (the constructor-tag atom pins off `:rs`/`:jvm`, exactly the shipped
  `Show`-over-`Expr`); associated types erase on the BEAM and only the Rust emitter
  materialises them (`trait { type Elem; }`). Verified on BEAM (+ rustc for the lowering).
- [stdlib_show.rian](stdlib_show.rian) — **portable `Show.float` — ECMAScript
  `Number::toString` (ECMA-262 §7.1.12.1, ADR-0069 §6).** Written ONCE in Rian over
  `__prim_float_repr` (each target's native shortest-round-trip string): it parses
  the repr to the unique shortest digits and applies the ECMA presentation rules,
  so the output is byte-identical across targets by construction. Conformance-tested
  equal to JS `String(x)` on **all four targets — BEAM, node, rustc, and the JVM**
  ([show_float_test.exs](../../test/rian/show_float_test.exs)), the denormal extremes
  included (`__prim_float_repr` returns the *shortest* round-tripping decimal on each
  target — the JVM by a shortest-search, since `Double.toString` is not always shortest).
- [prelude_test.rian](prelude_test.rian) — **the unit-test assertion vocabulary
  (ADR-0060 · ADR-0030).** ExUnit-equivalent `assert`/`refute`/`assert_eq`/`assert_neq`
  as hygienic Rian macros (no `quote`/`unquote`) that expand to a plain `Bool`, so a
  `@test def` reads like ExUnit while staying a pure value-flow (ADR-0035: assertions
  are values, not exceptions). `Rian.Test` prepends this lib to every test source it
  compiles, so the vocabulary is available to every `@test def` on all three targets
  with no boilerplate (macros are scope-local, so injection is how the lib is shared).
  For diagnostics, the **matcher** family `expect_eq`/`expect_neq`/`expect_true`/`expect_false`
  returns `Outcome := Pass | Fail(String)` and names the mismatch on failure (e.g.
  `Fail("expected 42, got 41")`, formatted via interpolation, ADR-0069); `Rian.Test`
  surfaces that message on every target. `contain` (membership) stays deferred — it needs
  the `List` prelude linked, like `assert_in`.

### Function body forms

A `def` body is one of two shapes (no semantic difference — both yield a value
via implicit return), plus the anonymous lambda form:

```elixir
def double(n Int53) Int53 := n * 2          # 1. single-expression body (the one-liner)

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
# `Int53` is the portable default integer (a native JS `number`, an `i64`
# elsewhere); a bare integer literal infers it. Use a fixed-width `Int8`…`Int64`
# / `UInt*` only when the WIDTH is the point — `Int64` is off `:js` (ADR-0064).

def add(x Int53, y Int53) Int53 := x + y          # single clause: typed head is the boundary

def classify(Int53) String                       # bodiless SIGNATURE line ...
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
alias Id := Int53                            # transparent synonym

def f(s val Shape) ...   # val (default, borrow) | iso (owned/use-once) | ref (&mut) | tag (identity)

Geometry.area(x)   # Rian module call      point.x         # field access
Value.Num(n)       # variant path          :lists.sum(xs)  # Erlang FFI (atom head)
String.upcase(s)   # Elixir-lib FFI

macro square(x) := x * x                   # declarative macro (AST substitution, hygienic)
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
