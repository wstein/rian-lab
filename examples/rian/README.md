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
| [13_protocols.rian](13_protocols.rian) | Protocols & impls (ADR-0042) — `protocol`/`impl … for …`, first-argument dispatch, the orphan-rule coherence checks; primitive-type impls compile to a guarded BEAM dispatcher and run |
| [14_test_framework.rian](14_test_framework.rian) | Tests in Rian (ADR-0057) — `@test def name() Bool`, run by `Rian.Test` and bridged to ExUnit (one case per `@test`); the dogfooding wedge |
| [15_targets.rian](15_targets.rian) | Portability as a declaration (ADR-0058) — `@targets(ex, rs, js)` on a `mod`; the compiler gates every `pub` fn's reachability against the contract |
| [16_doctests.rian](16_doctests.rian) | Doctests (ADR-0060 tier B) — `expr #=> expected` in a `@doc` heredoc, executed by `Rian.Doctest`; a drifted example fails the build |
| [17_stdlib_eq_ord.rian](17_stdlib_eq_ord.rian) | A portable stdlib slice over `Eq`/`Ord` (ADR-0042) — `contains`/`sort`/`maximum` as **bounded generics** (`forall T: Eq`/`Ord`); the protocol's first real customer, with `@test`s + doctests |
| [18_dict_eq.rian](18_dict_eq.rian) | A `Dict` over `Eq` — `get`/`has`/`put` bounded `forall K: Eq` over a generic `Pair(k K, v V)`; "Dict keys need Eq" made real (Int64 + String keys), runs on BEAM/JS, with `@test`s + doctests |
| [conformance_core.rian](conformance_core.rian) | The **Tier-1 admission gate** corpus (ADR-0049 §5a) — `@test`s over the portable core (`Int53` arithmetic, `div`/`rem`, comparison/boolean, multi-clause recursion + guards) that `Rian.ConformanceTest` runs on **every** Tier-1 target (`:ex`/`:rs`/`:js`); a regression on any fails the build |

Suggested reading order is numeric; 04 is the one to linger on — it is what
distinguishes Rian from "Elixir with different keywords."

Outside the numbered tour, two **self-hosting spikes** are written in Rian and
compile + run on real BEAM bytecode:

- [selfhost_lexer.rian](selfhost_lexer.rian) — a real arithmetic lexer (its own
  `Token` sum, list-pattern recursion).
- [selfhost_lexer_v2.rian](selfhost_lexer_v2.rian) — porting the *real*
  `Rian.Lexer` to Rian (slice 1): adds **identifiers and keywords** on top of
  numbers/operators/parens, using `Char` comparisons and ordinal arithmetic
  (ADR-0036). Checked against the reference lexer by `Rian.Fixpoint`.
- [selfhost_parser.rian](selfhost_parser.rian) — a precedence-climbing
  expression parser (a slice of `Rian.Pratt`) that consumes the lexer's
  `Vec(Token)`, builds its own `Expr` sum, and threads `(Expr, Vec(Token))` as a
  `Parse` pair. It exercises higher-order-free recursion, sum construction,
  nested list/variant patterns, and `case` — and hits **no** backend wall.
- [selfhost_parse.rian](selfhost_parse.rian) — the expression/pattern parser,
  fully self-hosted: a port of the **whole `Rian.Pratt` grammar** (self-hosting
  rung 2, ADR-0063). It builds Pratt's exact surface tuples as raw Rian tuples/
  atoms threaded through a parametric `R(node, rest)`, so the output term-equals
  `Rian.Pratt.parse` with **no projection** (`test/rian/parse_fixpoint_test.exs`).
  Covers prefix (`-`/`not`/`&`-capture), primaries (if/case/with, list/map/tuple,
  paren-or-lambda, atom/str/char/num/id), postfix (dot/call), labelled args,
  precedence climbing, AND the full pattern grammar (wild/var/lit/char/atom/tuple/
  list+tail/map/ctor/struct) + blocks. Found two real Rian limits along the way:
  the closed-list tail `nil` is produced as `:nil` (== Elixir `nil`), and the
  keyword-named tags `:if`/`:case`/`:with`/`:struct` can't be spelled as atoms, so
  they're built via a single counted `String.to_atom` crutch (the only FFI).
  String-interpolation and `<-`-propagation sugar (resolved by later passes) are
  out of scope.
- [selfhost_core.rian](selfhost_core.rian) — the **surface→Core lowering**, fully
  self-hosted (the pipeline stage after the parser, ADR-0063/0050): translates the
  whole `Rian.Pratt` surface AST into the typed **Core IR**. Every expression node
  (literals, unary/binary, calls with labelled args, dot, `if`, tuples, lists with
  tails, maps, blocks, `case` with guards, lambdas, captures, `with`) and every
  pattern (wild/var/lit/char/atom/tuple/ctor/list/struct/map) is rendered to a
  canonical s-expression and **equivalence-locked** against `Rian.Core.from_expr`/
  `from_pat` (`test/rian/core_fixpoint_test.exs`). The Lower-internal resolved
  nodes and the never-parsed `as`/pin patterns are not surface-reachable.
- [selfhost_decl.rian](selfhost_decl.rian) — a Rian **declaration** front-end
  (self-hosting **Stage 2**, ADR-0063): parses `type` sums and `def` functions
  into a `Decl` representation that, projected to `Rian.IR`, **equals what
  `Rian.Decl.parse` builds** and is then **compiled and run by the real backend**
  (`Rian.Beam.compile_ir/2`) — a Rian front-end producing IR the existing backend
  consumes (`test/rian/decl_fixpoint_test.exs`). Core forms; the long tail of
  `Rian.Decl` (multi-clause, capabilities, parametric types, mod/struct/protocol)
  remains.
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
- [selfhost_cap.rian](selfhost_cap.rian) — the **capability checker**, fully
  self-hosted (ADR-0063, ADR-0055): the complete capability→Rust mapping
  (`val`/`iso`/`tag`/`ref` × every `Copy` width, `String`, nominal types, nested
  `Vec(...)`, parametric generics `Name(A, B)` — including the reference quirk that
  `val` of a generic borrows the unlowered spelling) plus `ref`-rejecting BEAM
  legality, **equivalence-locked** against `Rian.Capability` over the whole matrix
  (`test/rian/cap_fixpoint_test.exs`). `val` borrows a non-`Copy` type but passes a
  `Copy` scalar by value; `ref` is the BEAM-illegal `&mut` outside the portable
  core (P5). Type-string tokenisation is the type-parser's stage; the BEAM
  linearity check is native typestate.
- [selfhost_exhaust.rian](selfhost_exhaust.rian) — the **exhaustiveness gate**,
  fully self-hosted (ADR-0063): the complete Maranget usefulness check `U(P, q)`
  with `specialize`/`default`/`signature` over single- and multi-column matrices,
  constructors with arguments (arity-specialised), wildcards, and finite/infinite
  signatures — patterns are `PWild | PCtor(name, args)`, so lists/tuples/sums are
  all just constructors. **Equivalence-locked** against the real
  `Rian.Exhaustiveness.useful?` (`test/rian/exhaust_fixpoint_test.exs`); the typing
  env is searched linearly, so the port is FFI-free. Exhaustiveness is then `not
  useful(…, [PWild…])`; only the witness/counterexample diagnostic remains.
- [selfhost_js.rian](selfhost_js.rian) — the **ECMAScript backend** port
  (ADR-0063, ADR-0049 Tier 1): emits JS source text from the Core IR, with the
  operator remapping that is the point (`and`→`&&`, `==`→`===`, `<>`→`+`,
  atoms→quoted strings, binary always parenthesised). **Fixpoint-locked** against
  the reference `Rian.JS` emitter — the port's output equals the `return`
  expression `Rian.JS.compile` produces, term-for-term
  (`test/rian/js_fixpoint_test.exs`). Covers the literal/unary/binary slice;
  calls, lists, `if`/`case`, structs, and prims remain.
- [selfhost_rust.rian](selfhost_rust.rian) — the **Rust text backend** port
  (ADR-0063, ADR-0049): emits Rust source from Core. Unlike JS, it is
  **precedence-aware** — it threads each node's precedence and parenthesises only
  when a child binds looser than its context — matching `Rian.Lower.emit_expr(_,
  :rust)` term-for-term (`test/rian/rust_emit_fixpoint_test.exs`). Atoms are
  BEAM-only; calls/lists/structs remain.
- [selfhost_jvm.rian](selfhost_jvm.rian) — the **Kotlin/JVM backend**, fully
  self-hosted (ADR-0063, ADR-0049 Tier 2): a whole-module emitter — sum types →
  `sealed interface` + `object`/`data class`, functions with **multi-clause
  pattern dispatch** (`is` smart-cast tests + `val` binds + the trailing throw),
  `if`, operators, primitives — **equivalence-locked** against `Rian.JVM.compile`
  over its full supported surface (`test/rian/jvm_module_fixpoint_test.exs`). The
  stage consumes Core (parsing is the parser/Core stage's job); lists/maps/case/
  lambda/`@external`/`Rian.Shadow` are reference gaps, not port gaps.
- [selfhost_beam.rian](selfhost_beam.rian) — the **BEAM abstract-forms backend**
  port (ADR-0063): builds the Erlang abstract forms `:compile.forms` consumes,
  doing the real `erl_op` mapping (`!=`→`/=`, `<=`→`=<`, `and`→`andalso`).
  **Fixpoint-locked** against Erlang's own parser — the forms equal `:erl_parse`'s
  canonical AST and compile+run (`test/rian/beam_emit_fixpoint_test.exs`).
  Operators are carried as strings (Rian can't spell `:+`); strings/calls/lists
  remain.
- [selfhost_checker.rian](selfhost_checker.rian) — the **real type checker**
  (inference) port (ADR-0063, ADR-0064): a slice of the REAL `Rian.Check.infer`
  (not the toy-language `selfhost_check`), inferring `Int53`/`Bool`/`String`/
  `Float64`/`unknown` for closed integer expressions and **fixpoint-locked**
  against `Rian.Check.infer` (`test/rian/checker_infer_fixpoint_test.exs`). It is
  conservative — an unbound identifier is `unknown`, not a guess. Env, floats,
  calls, lambdas, and `case` remain.
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
