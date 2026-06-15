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
- [selfhost_js.rian](selfhost_js.rian) — the **ECMAScript backend**, fully
  self-hosted (ADR-0063, ADR-0049 Tier 1): a whole-module emitter — functions with
  multi-clause **pattern dispatch**, sum variants as tagged arrays
  (`["Ctor", …]`), structs (`{__struct__: …}`), tuples/lists (with `...`-spread
  tail)/maps, `.field`, `if` (ternary), `case` (IIFE), operators (`and`→`&&`,
  `==`→`===`, `<>`→`+`, `div`→`Math.trunc`), atoms→strings, primitives.
  **Equivalence-locked** against `Rian.JS.compile` over its expression+function
  surface (`test/rian/js_module_fixpoint_test.exs`). Protocol dispatch, the
  whole-program int-mode, and `Rian.Shadow` are out of scope (program-level /
  separate-subsystem concerns).
- [selfhost_rust.rian](selfhost_rust.rian) — the **Rust text backend**, fully
  self-hosted (ADR-0063, ADR-0049/0055/0061): a whole-module emitter — sum types →
  `#[derive(…)] enum`, functions with `match`-over-the-param-tuple multi-clause
  dispatch (capability-lowered signatures like `o: &Opt`), the precedence-aware
  expression emitter, `if`, variant construct (`Enum::Ctor`) + ctor-pattern match,
  guards. **Equivalence-locked** against `Rian.Lower.rust_program`
  (`test/rian/rust_module_fixpoint_test.exs`). The emitter consumes *resolved* +
  *capability-lowered* Core — resolution is the parser/Core stage's job and
  capability lowering is the (self-hosted) capability stage's. Generics (tvars +
  owned↔borrow coercion), iso/cons lists, String-returns, structs/maps, and the
  Elixir text target are out of scope.
- [selfhost_jvm.rian](selfhost_jvm.rian) — the **Kotlin/JVM backend**, fully
  self-hosted (ADR-0063, ADR-0049 Tier 2): a whole-module emitter — sum types →
  `sealed interface` + `object`/`data class`, functions with **multi-clause
  pattern dispatch** (`is` smart-cast tests + `val` binds + the trailing throw),
  `if`, operators, primitives — **equivalence-locked** against `Rian.JVM.compile`
  over its full supported surface (`test/rian/jvm_module_fixpoint_test.exs`). The
  stage consumes Core (parsing is the parser/Core stage's job); lists/maps/case/
  lambda/`@external`/`Rian.Shadow` are reference gaps, not port gaps.
- [selfhost_beam.rian](selfhost_beam.rian) — the **BEAM abstract-forms backend**,
  fully self-hosted (ADR-0063, the default self-host target): builds the Erlang
  abstract forms for a whole module's functions. BEAM uses Erlang's **native**
  clause matching, so the patterns ARE the dispatch forms (no test/bind generation
  like JVM/JS). Covers functions, multi-clause dispatch, operators, `if`, `case`,
  variants/tuples/lists, guards. The fixpoint compiles via `:compile.forms` and
  **RUNS** the module, asserting it behaves identically to `Rian.Beam`
  (`test/rian/beam_module_fixpoint_test.exs`). Operators/names ride as strings
  (Rian can't spell `:+` or Erlang var atoms), inflated by the fixpoint;
  strings/prims/maps/structs/shadowed-binds are out of scope.
- [selfhost_checker.rian](selfhost_checker.rian) — the **real type checker**
  (inference) port (ADR-0063, ADR-0064): a slice of the REAL `Rian.Check.infer`
  (not the toy-language `selfhost_check`), inferring `Int53`/`Bool`/`String`/
  `Float64`/`unknown` for closed integer expressions and **fixpoint-locked**
  against `Rian.Check.infer` (`test/rian/checker_infer_fixpoint_test.exs`). It is
  conservative — an unbound identifier is `unknown`, not a guess. Env, floats,
  calls, lambdas, and `case` remain.
- [selfhost_compose.rian](selfhost_compose.rian) — the first **COMPOSITION** rung
  (ADR-0063 Step 3): the per-stage ports above are each verified in *isolation*
  (diffed against the Elixir reference via projection glue). This module instead
  **wires four stages directly** over shared types — `compile(s) =
  forms(lower(parse(lex(s))))` — with no Elixir glue between them. Its output IS
  Erlang abstract forms (`{:op, _, :+, …}`), so `test/rian/compose_fixpoint_test.exs`
  feeds them to `:compile.forms`, **runs** the module, and asserts it behaves
  identically to the full Elixir toolchain. Real Rian source (arithmetic
  expressions over variables), not a toy language; the one host crutch is
  `String.to_atom` (the operator/variable atoms Rian can't spell), counted in the
  ledger. Widening the subset and closing the `v1==v2` loop (Stage 3) are the next
  rungs.
- [selfhost_compose_decl.rian](selfhost_compose_decl.rian) — **COMPOSITION rung 2**
  (ADR-0063 Step 3): widens the composed subset from an *expression* to a whole
  single-clause **`def` declaration**. The pipeline now parses the def head +
  parameter list + `:=` body and assembles the **complete** Erlang function form —
  `compile_def(s) = emit_def(parse_def(lex(s)))` — so name, arity, params, and body
  all come from the source, in Rian. `test/rian/compose_decl_fixpoint_test.exs`
  loads + **runs** it and asserts behaviour identical to `Rian.Beam` on the same
  `def`. The only Elixir residual is the two module-level attribute forms
  (`:module`/`:export`) — the export list needs a *tagless* `{name, arity}` tuple
  that Rian's tag-injecting variant lowering can't spell; even there the name and
  arity are read back out of the Rian-produced form. Multi-clause heads, patterns,
  and guards are the next widening.
- [selfhost_compose_multi.rian](selfhost_compose_multi.rian) — **COMPOSITION rung 3**
  (ADR-0063 Step 3): widens the composed subset from a single-clause `def` to a
  whole **multi-clause, self-recursive function** — the shape a real compiler stage
  actually is. `def` lexes to its own token so the body parser stops at the next
  clause; clause heads carry **literal/variable patterns** (`0` → `{:integer,…}`,
  `n` → `{:var,…}`); the expression grammar gains **function calls** (`fib(n - 1)` →
  the Erlang local-call form). `compile_fn(s) = emit_fn(parse_clauses(lex(s)))` emits
  one multi-clause `{:function, …}` and `test/rian/compose_multi_fixpoint_test.exs`
  **runs** it — compiling `fib`/`fact`/`sumto` to functions that compute identically
  to `Rian.Beam` (recursion, pattern dispatch, and precedence all surviving). Host-
  FFI-free (quoted-atom operator literals + `Prim.str_to_atom`). Guards and multi-
  function modules are the next widening.
- [selfhost_compose_mod.rian](selfhost_compose_mod.rian) — **COMPOSITION rung 4**
  (ADR-0063 Step 3): the composed pipeline now emits a whole **multi-function
  module**, not a single function. `group` folds the flat clause stream into one
  group per function, and `compile_module(src, modname)` assembles the **entire**
  `:compile.forms` input — the `:module`/`:export` attributes *and* every
  `{:function,…}` form — as native Rian **tuple literals** (the export entries are
  the *tagless* `{name, arity}` tuples a tagged variant ctor can't spell). The
  decisive step: `test/rian/compose_mod_fixpoint_test.exs` authors **no** Erlang
  form by hand — it passes the Rian-produced list straight to `:compile.forms` and
  **runs** it, identical to `Rian.Beam` across multi-function, multi-clause, and
  mutually-recursive (`even`/`odd`) modules. Host-FFI-free. This is the last rung
  before a Rian *driver* owns the `:compile.forms` call itself.
- [selfhost_compose_driver.rian](selfhost_compose_driver.rian) — **COMPOSITION rung 5
  / capstone** (ADR-0063 Step 3 / §4): a Rian **driver** owns the whole loop, source
  string → a loaded, runnable module: `build(src, modname) =
  load(compile_forms(compile_module(src, modname)), modname)`. The two irreducible
  BEAM toolchain calls — `:compile.forms` and `:code.load_binary` — are declared as
  `@external(:ex, …)` FFI (ADR-0068) and **counted** in `@selfhost_ffi`; everything
  between them (destructuring `{:ok, _, _}`, threading the binary, returning the
  module atom) is ordinary Rian. `test/rian/compose_driver_fixpoint_test.exs` calls
  **only** `build/2` — no Elixir compile/load anywhere — and runs the returned module,
  identical to `Rian.Beam`. This is the **BEAM-bootstrap terminus shape** (§4): feed
  `build` a slice of the compiler's own source and the loop closes. (The portable
  terminus — compiling the compiler to Rust/JS — is separate and further.)
- [selfhost_compose_cond.rian](selfhost_compose_cond.rian) — **COMPOSITION rung 6**
  (ADR-0063 Step 3): widens the rung-5 driver's surface past arithmetic toward real
  compiler code — `if … do … else … end` (lowered to an Erlang `case` on the
  boolean), comparison operators (`== < > <= >=`, with Rian `<=` → Erlang `=<`), and
  boolean `and`/`or` (→ `andalso`/`orelse`). The expression emitter drops the
  `ErlForm` sum and builds every form as a native Rian **tuple literal** — the only
  shape that can express the nested `{:case, L, Cond, [Clause, Clause]}` an `if`
  needs (the `:"case"` tag is a quoted-atom literal, since `case` is reserved). The
  driver is unchanged: `build/2` still owns the compile→load loop. The fixpoint
  (`test/rian/compose_cond_fixpoint_test.exs`) builds + runs `max`/`abs`/`countdown`/
  `gcd`/`inrange`, identical to `Rian.Beam`. Widening toward the full Rian surface
  (so `build` can compile a slice of the compiler's own source — the `v1==v2` fixed
  point) continues from here.
- [selfhost_compose_real_beam.rian](selfhost_compose_real_beam.rian) — **COMPOSITION
  rung 7** (ADR-0063 Step 3/§4): the first cut connecting the two disconnected
  successes — per-stage equivalence and the composition loop. Rungs 1-6 used a *toy*
  backend (the driver's own `forms`); this rung's backend **is** the
  equivalence-locked [selfhost_beam.rian](selfhost_beam.rian), called **across
  modules**: the driver builds selfhost_beam's `Func` IR and invokes
  `SelfhostBeam.compile_forms` (loaded under its `:"Elixir.SelfhostBeam"` atom — a
  Pascal-qualified call, ADR-0041), so stage N's Rian output is stage N+1's Rian
  input with no projection glue. The `Form`→abstract-form inflation the beam fixpoint
  test did in Elixir (`erl_op`/`var_atom`) is ported into the driver. The cross-module
  call is **composition, not a host crutch** — excluded from the FFI ledger (see
  `Rian.SelfHost.ffi_in_file/1`); the only host FFI is still
  `:compile.forms`/`:code.load_binary`. `test/rian/compose_real_beam_fixpoint_test.exs`
  calls only `build/2` and runs the result, identical to `Rian.Beam`. Widening the
  *front-end* to the real parser/core ports is the next cut.
- [selfhost_compose_real_front.rian](selfhost_compose_real_front.rian) — **COMPOSITION
  rung 8** (ADR-0063 Step 3): extends rung 7 to the **front-end**. Each clause body is
  now parsed by the equivalence-locked [selfhost_parse.rian](selfhost_parse.rian) (the
  full Rian.Pratt grammar) via a cross-module `SelfhostParse.parse`, its raw surface
  tuple (`{:bin,op,l,r}`, `{:if,c,{:block,_},{:block,_}}`, …) lowered to `selfhost_beam`
  Core, then compiled by the cross-module `SelfhostBeam.compile_forms` (rung 7). **Two
  verified stages composed end to end** — connected only by driver-local lexing,
  declaration-splitting, and a raw-surface→Core lowering (none reimplementing either
  port). Both load under `:"Elixir.Selfhost*"` atoms (ADR-0041); both are sibling
  ports, so the calls are composition, not host crutches (excluded from the FFI
  ledger). `test/rian/compose_real_front_fixpoint_test.exs` runs `fib`/`max`/`gcd`/
  `poly` — with the **real** Pratt precedence and surface — identical to `Rian.Beam`.
  The remaining toy piece is the declaration layer (`selfhost_decl` is `:partial`).
- [selfhost_compose_real_decl.rian](selfhost_compose_real_decl.rian) — **COMPOSITION
  rung 9** (ADR-0063 Step 3): replaces the front-end's last toy piece — declaration
  splitting — with the equivalence-locked [selfhost_decl.rian](selfhost_decl.rian).
  The whole program is parsed by a cross-module `SelfhostDecl.parse_program`, its
  `Decl`/`Expr`/`Pat` IR lowered to `selfhost_beam` Core/Pat (the **surface→Core
  lowering** — incl. cons-list patterns → `PList`), then compiled by the cross-module
  `SelfhostBeam.compile_forms`. **Both front-end (lex→SelfhostDecl) and back-end
  (SelfhostBeam) are now verified ports**; the only driver-local glue is the lexer,
  the lowering, and the Form inflater — none reimplementing a verified stage.
  `selfhost_decl`'s surface has no `if` (that was rung 8) but **does** have cons-list
  patterns, so this rung compiles list-pattern recursion —
  `test/rian/compose_real_decl_fixpoint_test.exs` runs `fib`/`fact`/`even`/`odd`/
  **`sum`**/**`len`** (over lists), identical to `Rian.Beam`. Both ports load under
  `:"Elixir.Selfhost*"` atoms (ADR-0041); sibling-port calls are composition, not
  host crutches. Path to `v1==v2`: widen `selfhost_decl` past its `:partial` slice.
- [selfhost_compose_real_lex.rian](selfhost_compose_real_lex.rian) — **COMPOSITION
  rung 10** (ADR-0063 Step 3): wires the verified lexer too, so the driver owns **no
  lexing or parsing** — the whole front-end is verified ports. The
  [selfhost_lexer_v2.rian](selfhost_lexer_v2.rian) port (`SelfhostLexerV2.tokenize`)
  feeds [selfhost_decl.rian](selfhost_decl.rian) directly (its token tags are a
  superset of the parser's — **no projection**), whose IR is lowered to
  `selfhost_beam` Core and compiled by `SelfhostBeam.compile_forms`. **Three verified
  ports** (lexer, declaration parser, backend) composed cross-module; the only
  driver-local code is the surface→Core lowering and the Form inflater.
  `test/rian/compose_real_lex_fixpoint_test.exs` runs `fib`/`fact`/`even`/`odd`/`sum`/
  `len` — incl. a source with `#` comments and blank lines that only the real lexer
  handles — identical to `Rian.Beam`. Path to `v1==v2`: widen `selfhost_decl` off
  `:partial` (it lacks `if`/`case`/strings/sum-types) and the lowering to match.
- [selfhost_compose_real_sum.rian](selfhost_compose_real_sum.rian) — **COMPOSITION
  rung 11** (ADR-0063 Step 3): widens the composed build's **surface** to **sum types
  + constructor-pattern dispatch**, using `selfhost_decl`'s already-locked `type`/ctor
  capability — **no verified-port change**. Only the driver glue grows: the `type`
  declaration is *erased* (variants are atoms / tagged tuples on the BEAM), and the
  `Form` inflater learns `FCtorN`/`FCtor` (nullary ctor → snake atom `Red`→`:red`;
  applied ctor → tagged tuple `Pair(a,b)`→`{:pair,a,b}`) via a `to_snake` matching
  `Rian.PatternLower.to_snake` (`SNum`→`:s_num`, `SP`→`:sp`).
  `test/rian/compose_real_sum_fixpoint_test.exs` compiles `Color`/`Shape`/`Box`
  programs — nullary dispatch, payload destructuring, and ctor-value construction —
  identical to `Rian.Beam`. Same three verified ports as rung 10; only host FFI:
  `:compile.forms`/`:code.load_binary`.

**The loop closes on real source** — [test/rian/compose_selfcompile_fixpoint_test.exs](../../test/rian/compose_selfcompile_fixpoint_test.exs)
feeds the composed `build` a **verbatim slice of a real compiler stage** —
[selfhost_cap.rian](selfhost_cap.rian)'s `Ty` sum type + `copyt` function — and asserts
it runs identically to `Rian.Beam`. This is the first time a stage compiles its *own*
source, not a hand-written corpus (the test even asserts each `copyt` clause is verbatim
in the real file, so it can't drift into a toy). **Honest scope:** the loop is
*self-compiling* (codegen), **not** *self-checking* — `Rian.Check`/`Exhaustiveness`/
`Capability` are not in the `build` loop — and it's a *slice*: the whole file needs
`if`/strings/`Prim`, which the surface doesn't cover yet. Widening that surface until
`build` compiles a whole real `selfhost_*.rian` file is the work before `v1==v2`.
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
- [prelude_list.rian](prelude_list.rian) — **the eager iterable-accepting reducers
  over a concrete list (ADR-0047 §2).** `List.sum`/`product`/`any`/`all`/`length` —
  the Python `sum`/`any`/`all`/`len` family — written **once in Rian** as pure cons
  recursion (no `__prim_*`, since a list is already portable). Each has a natural
  empty-list identity (0/1/false/true/0), so it is **total** (no `Option`, no crash),
  and all five **reach every target** (`ex`/`rs`/`js`/`jvm`, verified by
  `mix rian.targets`). A *lazy* generator/`Iterator` protocol is deliberately NOT
  provided — laziness is a per-target evaluation concern, native like concurrency
  (ADR-0057), not portable sequential logic.
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
  equal to JS `String(x)` on **BEAM, node, rustc, and the JVM**
  ([show_float_test.exs](../../test/rian/show_float_test.exs)) — the JVM lane excludes
  only the tiniest denormal extremes (< ~1e-322), where the JLS pins `Double.toString`
  to a non-shortest form (`4.9E-324` vs ECMA `5e-324`).

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
