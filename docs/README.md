# Rian — Design Corpus

This directory is the canonical record of Rian's design: **Architecture Decision
Records** (ADRs — *what* we decided and *why*) and **Specifications** (specs —
the normative behaviour the implementation must match).

> **Provenance.** ADRs are numbered from a longer series; this repository
> captures the decisions from ADR-0026 onward. Earlier ADRs (0001–0025) and
> ADR-0028 are *referenced* by these documents but predate this corpus and are
> not included here.

## Status at a glance

| Area | State | Evidence |
| --- | --- | --- |
| Expression parser (Pratt, precedence) | Implemented | [pratt.ex](../lib/rian/pratt.ex), 22/22 precedence asserts |
| Exhaustiveness / reachability | Implemented | [exhaustiveness.ex](../lib/rian/exhaustiveness.ex), Maranget |
| Pattern lowering | Implemented | [pattern_lower.ex](../lib/rian/pattern_lower.ex) |
| Capability → Rust sig + BEAM linearity | Implemented (partial) | [capability.ex](../lib/rian/capability.ex) |
| End-to-end **text** lowering (Rust + Elixir-debug) | Implemented | [lower.ex](../lib/rian/lower.ex) — **Rust** is the real text target; the **Elixir text is a DEBUG/inspection view only** (`mix rian.compile --show-elixir`), *not* the BEAM execution path. The BEAM runs from `Rian.Beam` abstract-forms bytecode (P3, ADR-0031) |
| Hygienic macros + pure comptime | Implemented | [macro.ex](../lib/rian/macro.ex), [comptime.ex](../lib/rian/comptime.ex) |
| Lexer + declaration parser | **Stage 0.1 (broad)** | [decl.ex](../lib/rian/decl.ex) — token-driven; `type`/`struct`/`alias`/`const`/`use`/`mod` + single/multi-param `def`, `:=`/block/`case` bodies, `when` guards, `pub` visibility. Struct & sum-variant construction (positional + named) and constant references lower per target. The modules tour ([05_modules.rian](../examples/rian/05_modules.rian)) parses and lowers end-to-end. Not yet: `macro` files |
| Real type checker | **Compile gate + flow narrowing** | [check.ex](../lib/rian/check.ex) — ADR-0034 §1/§4: unification-based inference gates `compile`, rejecting only *provable* return-type mismatches; `case` arms and pattern clauses narrow bound variables to the matched variant's field types. Error sets (§2) are checked at the `T \| E` boundary; concrete generics (`Vec(T)`) infer. Protocol bounds (§3) await their surface |
| Erlang abstract-forms backend (Stage 0.5) | Implemented | [beam.ex](../lib/rian/beam.ex) — lowers to the Erlang abstract format + `:compile.forms` → loadable `.beam` (no `eval`); the default BEAM execution path. **Dialyzer-checkable**: every function emits a `-spec` and every sum/struct a named `-type` (kept via `:debug_info`); `Int*→integer()`, `Float*→float()`, `Bool→boolean()`, `String→binary()`, `Vec(T)→[t()]`, `Fn(A,R)→fun((a())->r())`, sum→union, struct→map\|tuple, generic→`any()` |
| ECMAScript backend | Implemented (partial) | [js.ex](../lib/rian/js.ex) — ADR-0049 Tier 1 on the core IR; **protocol dispatch** (ADR-0061 §3, node-verified) incl. **struct dispatch**; **structs** as `__struct__`-tagged objects (construction/field-access/patterns); **atoms** (→ JS strings) and **`Result`** (`{:ok,_}`/`{:error,_}` → `["ok", v]`) incl. tuple/atom `case` patterns, node-verified; gaps: `with`/lambdas/general FFI |
| Self-hosting (compiler in Rian) | Started | six-layer pipeline in Rian compiles to `.beam`; real-lexer port at **slice 3** (ids, all 16 keywords, comparisons `< > <= >= == !=`, word-ops `and/or/not/in/rem/div`, and **string `"…"` + char `'X'` literals** scanned char-by-char), diffed vs reference by [fixpoint.ex](../lib/rian/fixpoint.ex) and **locked in CI** ([ci.yml](../.github/workflows/ci.yml)). Out of slice: floats/brackets/escapes |
| Protocols & impls (ADR-0042, ADR-0061) | **multi-target** | [protocol.ex](../lib/rian/protocol.ex) — coherence-checked desugar; `forall T: Bound` enforced at call sites ([check.ex](../lib/rian/check.ex)). **BEAM** guarded dispatcher (primitive/sum/struct); **JS** native dispatcher (`typeof`/tag, node-verified); **Rust** fresh `trait Rian<P>` + `impl`s + `fn f<T: RianEq>` with UFCS calls ([lower.ex](../lib/rian/lower.ex), rustc-verified). Deferred: dynamic dispatch, multi-unit Rust dedup, target-relative coherence |
| Rian-native tests (ADR-0057, ADR-0060 §3) | **multi-target** | [test.ex](../lib/rian/test.ex) — `@test def name() Bool` runs on the BEAM (`Rian.Test.exunit/1` → ExUnit), and lowers to a **Rust `#[test]`** module (`Rian.Test.rust/1`, `rustc --test`-verified) and a **`node:test`** module (`Rian.Test.js/1`, `node --test`-verified) — the same `@test` surface, three native harnesses ([14_test_framework.rian](../examples/rian/14_test_framework.rian)) |
| Doctests (ADR-0060 tier B) | **MVP** | [doctest.ex](../lib/rian/doctest.ex) — `expr #=> expected` in a `@doc` heredoc, executed (both sides real Rian); `Rian.Doctest.exunit/1` surfaces each as an ExUnit case ([16_doctests.rian](../examples/rian/16_doctests.rian)). A drifted example fails the build. Module-internal + `docs/spec` extraction deferred |
| Source formatter (ADR-0045) | **incl. line wrapping** | [format.ex](../lib/rian/format.ex) (engine [format/doc.ex](../lib/rian/format/doc.ex), tree [format/cst.ex](../lib/rian/format/cst.ex)) + [`mix rian.format`](../lib/mix/tasks/rian.format.ex) (`--check`/`--diff`/`--stdout`/stdin) — a gofmt-style, zero-config formatter: a bracket-structured lossless **CST** + a Wadler/**Lindig** linear pretty-printer; never reparses. Re-derives indentation + spacing, **wraps bracket interiors to 98 columns** (one item per line + trailing comma; declaration heads never reflow), honors a **magic trailing comma**, and **wraps top-level `:=` operator chains** leading-operator (full `@cont_ops`, **precedence-aware**); keeps comments/heredocs verbatim; **total** (unlexable input unchanged). Verified over the whole corpus + seeded property/fuzz suite for **significant-token equivalence, parse-still-valid, idempotence, comment fidelity, totality**. **LSP** formatting + rangeFormatting backend ([lsp/formatting.ex](../lib/rian/lsp/formatting.ex)) and the **`rian fmt` escript** ship; the **Doc engine is self-hosted** ([compiler/format.rian](../compiler/format.rian)), fixpoint-locked to `Rian.Format.Doc`. Remaining: GenLSP transport, full formatter self-host |

A growing slice now flows **from `.rian` source** through the parser → typed core
IR → dual-target lowering (the modules tour compiles end-to-end); the remaining
passes still run on hand-built IR. The component suites pass and this front-end
path is integration-tested ([decl_run.exs](../examples/decl_run.exs),
[decl_test.exs](../test/rian/decl_test.exs)). Treat the "verified" banners inside
individual specs as *component-level* unless the tour exercises them end-to-end.

## Architecture Decision Records

| ADR | Title | Status |
| --- | --- | --- |
| [0000](adr/0000-charter.md) | **Charter** — Rian's thesis (portable sequential logic + tests; concurrency native-per-target; portability inferred), the *borrow surface, never semantics* rule, the one-IR/many-emitters target model, and **how to read statuses** (this corpus states decisions, not shipped code — the Status-at-a-glance table + tests are the shipped-ness index) | Accepted — living |
| [0025](adr/0025-memory-capabilities.md) | **Memory capabilities** `val`/`iso`/`ref`/`tag` — one annotation yields ownership-checked Rust *and* BEAM use-once linearity (no hand-written lifetimes); `ref` is BEAM-illegal. The foundational decision 5 ADRs referenced but never had a file (written 2026-06-14) | Accepted; Implemented |
| [0026](adr/0026-ecosystem-integration.md) | Erlang/BEAM ecosystem integration (no fork) | Accepted |
| [0027](adr/0027-fast-track-self-hosting.md) | Fast track to self-hosting (free FFI, bootstrap stages) | Accepted |
| [0029](adr/0029-dot-syntax.md) | Dot syntax as the universal qualifier | Accepted; implemented |
| [0030](adr/0030-macros.md) | Macros: declarative, hygienic, pattern→template (+ comptime) | Accepted; implemented |
| [0031](adr/0031-bootstrap-strategy.md) | Bootstrap: reuse the Elixir *runtime*, not the *compiler* | Accepted |
| [0032](adr/0032-surface-syntax-family.md) | Surface syntax belongs to the Elixir/Ruby/Crystal family | Accepted |
| [0033](adr/0033-surface-vocabulary.md) | Surface vocabulary: `def`, juxtaposed types, `case`/`when`, Crystal primitives | Accepted |
| [0034](adr/0034-type-system-foundations.md) | Type system: unification, error sets, protocol bounds, flow narrowing | Accepted (direction) |
| [0035](adr/0035-no-hidden-control-flow.md) | No hidden control flow (errors are values; no exceptions) | Accepted |
| [0036](adr/0036-range-subrange-types.md) | Range (subrange) types: finite ordinal subtypes over `Int64`/`Char` | Accepted (direction) |
| [0037](adr/0037-binary-wire-format-records.md) | Binary wire-format records: `@wire` structs with derived `decode`/`encode` | Accepted (direction) |
| [0038](adr/0038-language-server.md) | Language server (LSP): tolerant analysis layer over the compiler library | Accepted (direction) |
| [0039](adr/0039-failable-bind-arrow.md) | Reassign `<-` to failable-bind/generator; re-spell mutation | Accepted (direction) |
| [0040](adr/0040-error-handling.md) | Error handling: `Result`, `T \| E` sugar, `with` propagation, error-set composition | Accepted (direction) |
| [0041](adr/0041-target-model.md) | Target model: per-target representation, observable contracts, module resolution | Accepted (direction) |
| [0042](adr/0042-protocol-bounded-generics.md) | Protocol-bounded generics: `forall` binders, `protocol`/`impl`, coherence, dispatch | Accepted; §3/§5 MVP implemented (primitive-type impls, BEAM) |
| [0043](adr/0043-opaque-types.md) | Opaque types: module-scoped nominal distinctness over a base, zero-cost | **Accepted (implemented)** |
| [0044](adr/0044-otp-behaviours.md) | OTP behaviours: `@behaviour` annotation, checked callbacks, threaded state (BEAM-only) | ~~Accepted~~ **Superseded by 0057** |
| [0045](adr/0045-formatter.md) | Formatter: one canonical zero-config style, comment-preserving, deterministic | Accepted (direction) |
| [0046](adr/0046-compile-time-by-default.md) | Compile-Time by Default: universal compile-time checks; per-target specialization; semantic-only optimization | Accepted |
| [0047](adr/0047-portable-prelude-stdlib.md) | Portable prelude & stdlib: three tiers, hybrid implementation, `Option` not `nil` | Accepted (direction) |
| [0048](adr/0048-effect-tracking.md) | Effect tracking: fine-grained, inferred, ambient (not object-capability); `pure = empty effect set` | Accepted (direction) |
| [0049](adr/0049-backend-target-roadmap.md) | Backend target roadmap & tiers: T1 BEAM/Rust/ECMAScript, T2 JVM/WASM, T3 Go | Accepted (direction) |
| [0050](adr/0050-typed-core-ir.md) | One typed core IR: single contract, sealed-sum nodes, emitters as pure consumers | Accepted (direction) |
| [0051](adr/0051-doc-comments.md) | Doc comments: `@moduledoc`/`@doc`/`@typedoc` → EEP-48/rustdoc/JSDoc; documented self-hosting from day one | Accepted (direction) |
| [0052](adr/0052-documentation-site.md) | Documentation site: Astro/Starlight portal + native per-target API reference | Accepted (direction) |
| [0053](adr/0053-repl-interactive-surfaces.md) | REPL & interactive surfaces: a compiling, connected REPL; one eval engine, many surfaces | Accepted (direction) |
| [0054](adr/0054-connected-repl-prerequisites.md) | Connected REPL prerequisites: attach authentication + an evaluation sandbox/fuel envelope — gates ADR-0053 §2's `--remote` before it ships | Accepted (direction); not implemented |
| [0055](adr/0055-capabilities-through-dispatch-and-opaque.md) | Capabilities through dynamic dispatch & opaque types: capability on the protocol method receiver (survives `dyn` erasure); opaque-over-struct presents the join of field capabilities | Accepted (direction) |
| [0056](adr/0056-comptime-target-conditional.md) | `comptime if target`: proven-equivalent (or type-visible) sequential target conditional, else hard error. Motivation thinned — concurrency is native-per-target (ADR-0031), so the fracture it addressed isn't shared Rian source | **Proposed (dormant)** |
| [0057](adr/0057-concurrency-and-otp-are-native-per-target.md) | Concurrency & OTP are native-per-target: Rian source is sequential logic + tests; gen_servers/tasks/workers are written in the host's native language and call shared Rian functions. Supersedes 0044 | Accepted (direction) |
| [0058](adr/0058-configurable-target-environments.md) | Configurable target environments (`:ex`/`:rs`/`:js`), reachability-gated: `Rian.Reach` computes per-function reach via a call-graph fixpoint; `mix rian.targets [--require …]` reports and gates by need; the in-source `@targets(…)` module contract is gated by `Rian.Reach.gate!`, and an unannotated module falls back to the **build default** (`mix.exs` `rian: [targets: …]` / app env). Concurrency-FFI is a fallout | Accepted; implemented |
| [0059](adr/0059-join-lattice-lub.md) | Join lattice (LUB) for `if`/`case`/list-element types: `Check.join/2` is the least-upper-bound over the `num_widens?` order (numeric + same-constructor covariant `Vec`/`Option`); `:unknown` absorbing, gaps explicit. Closes the strict-`unify` join asymmetry | Accepted; implemented |
| [0060](adr/0060-testing-spec-by-example.md) | Testing: three tiers (properties/fixpoint · executable spec-by-example/doctests · `describe`/`it`+matchers); assertions are values not exceptions (ADR-0035); doctests land first, matchers wait on protocols; **Gherkin rejected** (second grammar, prose↔stepdef drift, audience mismatch) | Accepted (direction) |
| [0061](adr/0061-multi-target-protocol-lowering.md) | Multi-target protocol/generics lowering: dispatch is **native-per-target** (runtime guarded dispatcher on BEAM/JS, static `trait`+monomorphization on Rust); bounds are one portable static check + a real Rust trait bound; **coherence is target-set-relative** (ADR-0058) — the runtime-discriminator rule binds only `:ex`/`:js`, the orphan rule is adopted universally | Proposed (design) |
| [0062](adr/0062-jvm-bytecode-and-citizenship.md) | JVM citizenship ladder: **rung B** (shipped) — runnable `.jar` via Kotlin + `kotlinc` (`Rian.JVM.to_jar`, `mix rian.jar`); **rung C** (proposed) — direct bytecode, the ADR-0031 analog, via a `java.lang.classfile` helper (C1) → in-process once self-hosted on the JVM (C3); citizenship needs Java interop + Java-callable signatures + line tables, not just bytecode | Proposed |
| [0066](adr/0066-error-propagation-sugar.md) | Error-propagation sugar (P4, design/shootout): a per-call propagation operator with the invariant that it **types the error set at the `pub` boundary** (unify into the declared `\| E`, never an untyped escape) and is **visible** (ADR-0035 — propagation is control flow). Excludes `?` (boolean predicate) and `!` (reserved). Shootout narrows to **`try` prefix** (inline) + **bare `<-` bind** (statement, reuses ADR-0039, no new token) | Proposed |
| [0065](adr/0065-surface-stability.md) | Surface stability (P7, gated on P1): a **partial, additive-only freeze** of the **token vocabulary** (keywords, operators, punctuation, literals) and the **operator precedence/associativity table** (`Rian.Pratt.opinfo`) — the surface tooling/formatters key off. Explicitly **not** frozen: layout/whitespace (P1 just relaxed it), numeric semantics (P2), `ref` portability (P5), error-propagation sugar (P4), and anything unimplemented. "Freeze the surface, and not a moment before" | Proposed |
| [0064](adr/0064-portable-numeric-contract.md) | Portable numeric contract (P2): replaces "native-per-target integers" (supersedes the integer clauses of ADR-0034 §1/0041/0035) with **`Int`** (arbitrary precision, the new default literal type — identical everywhere) + fixed-width `Int8…64`/`UInt*` (defined two's-complement wrap — identical everywhere). No type is cheap on every target (the BEAM has no fixed width; Rust no free bignum), so intent picks: `Int` default + masking-free on BEAM, fixed-width opt-in. **Gated on a measured spike** — per-op BEAM masking is ~15× native (`bench/numeric_masking.exs`) | Proposed; partial (`Int` + literal range-check in) |
| [0063](adr/0063-bootstrap-plan-and-fixed-point.md) | Self-hosting bootstrap plan: **boundary** = Rian front-end (lexer+parser→Core IR) feeding the existing Elixir checker+`Rian.Beam`, marched down over time; **fixed-point ladder** — Stage 0 equivalence (done) · Stage 1 self-application (done for the lexer: lexes real toolchain source incl. the Rian parser's) · Stage 2 front-end self-host (same IR, reuse backend) · Stage 3 bootstrap fixed point (whole compiler in Rian, v1==v2 bit-identical). "Real self-hosting" = Stage 2 | Proposed |
| [0067](adr/0067-abstract-types.md) | **Abstract types** (Gleam/Haxe debate #1, 5/5): extend `opaque` (ADR-0043) with an **operator** and **controlled-cast** surface — zero-cost wrappers that erase to a base per target (Haxe `abstract`), without implicit-cast sprawl (ADR-0035). Collapses `opaque`/`range` (single-base) toward one mechanism. **`Int53` stays a builtin** — it is per-target (JS `number`/`i64`) *and* carries a whole-program JS number-mode invariant, neither expressible by single-base erasure (§3, corrected) | **Accepted (P1a–P1c done; `opaque`+`abstract` ops/casts)** |
| [0068](adr/0068-external-target-bodies.md) | **`@external` target-scoped FFI bodies** (Gleam/Haxe debate #2, 4/5): a Gleam-style `@external(:target, "spec")` per-target host body (**reject** Haxe `#if`-in-body) that `Rian.Reach` reads to compute an honest target set — turns "FFI pins to `:ex`" into honestly-multi-target functions; target-conditionality lives only at the declaration boundary, never in portable logic (ADR-0057/0058) | Accepted; Implemented |
| [0069](adr/0069-string-interpolation-auto-stringify.md) | **String interpolation + portable `Show`** (design): `"…${expr}…"` holes that auto-stringify *arbitrary* values through a promoted-to-prelude `Show` protocol (ADR-0042/0061), desugaring to `show(_) <> …`; backed by two `__prim_*_to_string` intrinsics so it joins the portable core honestly (Reach `:prim` blocker where an emitter lacks them). Kills the #1 portability leak (`Integer.to_string` FFI pins to `:ex`). Holds ADR-0035 by hiding only a *pure* `Show.show`, never control flow or an `inspect` fallback. **Implemented (partial):** `${expr}` (§1, JS/Kotlin-familiar) + auto-stringify for `Char`/`Int*`/`Bool`/`String` holes via static (monomorphic) resolution in `Rian.Interp` + `__prim_int_to_string`/`__prim_char_to_string` on all four targets, byte-identical, lowered to a single-shot join (§6) — no runtime dispatcher (sidesteps the Char/Int collision); `Float`/user-`Show` deferred | Accepted; Implemented (partial) |
| [0070](adr/0070-default-val-capability.md) | **`val` is the inferred default capability** (Gleam/Haxe debate #5, 4/5): a bare param defaults to `val` (read-only, the least-powerful); only `iso`/`ref`/`tag` need spelling. Cuts the capability tax on the 90% case without losing Rust soundness or BEAM linearity (the load-bearing annotations stay explicit); defaulting to the least-powerful capability is the safe direction (ADR-0035) | **Accepted; Implemented** |
| [0071](adr/0071-python-backend.md) | **Python backend — the reach target** (new-backend debate, Python first): a JS-shaped dynamic/GC emitter on Core for the largest unreached audience (data/ML/scripting). Native bignum `int` → **`Int` reaches `:py`**, and fixed-width wrap + the 64-bit overflow ops via masking → the broadest non-BEAM numeric reach. Sum dispatch via `match`/`case` (Python ≥3.10) with a trailing `case _: raise` (host won't check exhaustiveness; Rian's gate does). Emits **type hints + `mypy --strict` in conformance** (the only honesty net for a dynamic target). Verifiable day one (`python3` ubiquitous in CI) | Accepted (direction); not yet implemented |
| [0072](adr/0072-swift-backend.md) | **Swift backend — mobile completion** (new-backend debate, Swift second, gated): an ARC/value-semantics emitter on Core; with the Kotlin backend it claims "shared logic across iOS + Android + web" (broader than KMP). Best algebraic-type fit Rian has — `enum` + **compiler-checked** exhaustive `switch`, so **no trailing default**. `Int`/(pre-6.0) 128-bit pin off `:swift` (no stdlib bignum). **Gated on `swiftc` in CI** — `:swift` stays out of the default `@targets` and reach claims are provisional until the conformance harness compiles+runs Swift (ADR-0000/0058 honesty) | Proposed (direction); gated on CI parity |
| [0073](adr/0073-foldable-protocol.md) | **`Foldable`: eager polymorphic reduction over a protocol** — fold-shaped reducers (`fcount`, …) over a protocol with an associated `type Elem` (ADR-0074), so one reducer folds a `Bag` of `Int53` *and* a `Words` of `String`; runs on the BEAM, reach-gated honestly (`[:ex, :js]` for the sum-dispatch consumer), Rust lowering rustc-verified. The **lazy-iterator** surface is deliberately unimplemented (laziness is native-per-target, ADR-0057) | Accepted; Implemented (eager) |
| [0074](adr/0074-associated-types.md) | **Associated types for protocols (element-generic bounds)** — a bodiless `type Elem` in a `protocol`, bound `type Elem := Concrete` in an `impl`, coherence-checked at parse time (an impl must bind exactly its protocol's associated types); lowers to Rust `trait { type Elem; }` + `impl { type Elem = i64; }` (rustc-verified), erased on BEAM/JS. Retires ADR-0073's `Int53` pin. Checker-resolution (Stage 2b) **dropped** — the conservative checker has no mismatch to resolve against; the Rust emitter is the sole consumer | Accepted; Implemented |
| [0075](adr/0075-transpiler-type-inference.md) | **Transpiler type inference: filling `_Unk` holes** — Algorithm-J over the Elixir AST (occurs-check, `[Gen]` generalization, `Int53` cross-target default, two-pass sibling + cross-module propagation, Result/error-set synthesis, `@spec` harvest), **accident-free** (type-check-gated). ~31% measured ceiling on the compiler corpus (corpus-bound); sum-type reconstruction for struct IR is the open lever. The unused `port_analysis`/`port.spec` layer was removed | Accepted (direction); MVP implemented |
| [0076](adr/0076-roundtrip-forms-equivalence.md) | **Elixir→Rian→Elixir roundtrip: forms-level equivalence, two BEAM paths** — the transpile-migration verification oracle (`Rian.Roundtrip` + `Rian.FormsEquiv`). Byte-identical `.beam` is unreachable between two frontends, so the bar is **normalized abstract-forms equality** modulo a *justified* quotient (annotations, variable α-renaming, a small safe-rewrite whitelist — `if`→`case` clause order, negated-literal fold). Both BEAM backends (`Rian.Beam` forms + `Rian.Lower` Elixir source) must agree (`equiv_two_paths`); distinct from the self-host `v1==v2` of ADR-0063 | Accepted; Implemented |
| [0077](adr/0077-linter.md) | **Linter: advisory, semantics-aware style checks (the gofmt↔vet split)** — a separate `mix rian.lint` complementing the ADR-0045 formatter. The formatter stays mechanical/total/meaning-free; the linter is **advisory** (ranked warnings, opt-in CI severity gate, `--fix` only for the mechanically-safe subset) and **semantics-aware** (consumes the typed Core IR + `Rian.Reach`). Owns what the formatter can't: over-long `def` heads (parser-gated — migrates formatter-ward later), naming conventions (ADR-0034 casing), unused/shadowed bindings, deep nesting, residual `TODO_PORT`/`_Unk`, non-portable constructs. Never duplicates the checker's hard gates | Proposed (direction) |
| [0078](adr/0078-bitstrings.md) | **Bitstrings/binaries — a BEAM-first `<<seg::spec, …>>` surface** — fills the construct `lib/rian`'s lexer/string code is built on (the dominant transpiler `TODO_PORT` bucket, ADR-0075/0076). Elixir-compatible spelling; `String` is its UTF-8 special case (ADR-0041). **BEAM-native** (Erlang bitstring abstract forms) for construction + patterns; Rust/JS/JVM raise `Unsupported` and `Rian.Reach` pins bitstring-using functions **BEAM-only** (honest matrix, ADR-0000) until faithful bit-level lowering lands. Staged: construction → patterns → transpiler emit | Accepted (direction); implemented incrementally |
| [0079](adr/0079-comprehensions.md) | **Comprehensions — `for p <- src, filter, … do body end` as eager prelude sugar** — the last *portable* surface gap (everything else still blocking the compiler's own roundtrip is non-portable by design or a transpiler bug). Reuses ADR-0039's `<-` generator arrow; `Core.from_expr` desugars to nested `List.flat_map`/`if`/`[body]` over the portable prelude (ADR-0047), so **every emitter/checker consumes it for free** and it carries no Reach blocker — as portable as the prelude ops it desugars to (ADR-0061). Surface (always list-producing) covers plain-variable **and full-pattern** generators (`for {:mod, name, _} <- decls`, `for Ok(v) <- rs` — a non-matching element is filtered, not an error); the Elixir-only `into:`/`reduce:` forms are transpiler-desugared to portable `List.reduce` folds (`into: %{}` inherits the map blocker, ADR-0000). Still honest markers: binary generators `<<b <- bin>>`, exotic `into:` targets, `uniq:` | Accepted (direction); implemented |
| [0080](adr/0080-project-layout-and-skeleton.md) | **Standard project layout, `rian new` skeleton, editor/tool config** — one canonical project shape (`src/`+`test/`+`_build/`, cargo/gleam model) and a **declarative `rian.toml` manifest** (not an executable `mix.exs`) — resolving the ADR-0026/0031 manifest open item. Manifest carries name/version/`kind`/license/**`targets`** (the project's portability contract feeding `Rian.Reach`, ADR-0058) + the only style knobs (`[lint]`, ADR-0077). Skeleton ships README/LICENSE(Apache-2.0)/**AGENTS.md** (canonical, vendor-neutral; CLAUDE.md a pointer)/`.editorconfig`/`.gitignore` + a runnable hello-world. The formatter stays **zero-config by design** (ADR-0045) — `.editorconfig` *mirrors*, never overrides, the fixed style. File↔module casing per ADR-0033/0034 | Proposed (direction) |
| [0081](adr/0081-effect-annotations-and-bridge-rename.md) | **`@effects(host)` effect annotation; `@rian`→`@rian_sig` bridge rename** — gives ADR-0048's host effect a surface: the explicit `@effects(...)` row (`@effects(host)`), **no short keyword/sugar** — one grammar production, no per-effect keyword (ADR-0050). The effect is **inferred** for `defp` and a **checked declare-public assertion** for `pub` (ADR-0034) — the transpiler emits `@effects(host)` on `pub` boundaries only. Explicitly **not** `@external` (ADR-0068): effect-on-a-portable-body vs per-target *body* (comparison table). Untangles the two annotation layers — **Elixir-bridge** (`.ex`, the `@rian_*` namespace) vs **Rian-surface** (`.rian`: `@effects`/`@external`). The bridge stays namespaced: `@rian`→`@rian_sig`, `@rian_host` kept — honest siblings, mapping `@rian_host`→`@effects(host)` across the boundary. `@foreign`/`@host`/`@sig` rejected. **Bridge rename implemented**; effect surface gated on ADR-0048 (transpiler keeps the interim `# @rian_host:` comment until then) | Bridge rename implemented; effect surface Proposed |
| [0082](adr/0082-native-packaging-layer.md) | **Native packaging layer — generate native build files from `rian.toml`** — closes (in part) the ADR-0026 "Hex/Cargo metadata from a Rian manifest" + ADR-0080 §2 packaging open items. **One generator, two delivery modes, five invariants:** (1) a single `rian.toml → native manifest` function (`Rian.Pkg`, per-target backends mirroring the emitters, ADR-0050) is the one source of truth; (2) **PUSH** (`rian build`) writes a self-contained native project only under `_build/<target>/` (ADR-0080 §1 — generated, never authored; overwrite, never merge); (3) **PULL** ships native plugins (Mix compiler + rebar3 first, ADR-0026 §3; then Cargo build-dep, Gradle task) calling the *same* generator for embedding; (4) **nothing ships unless a real `cargo`/`gradle`/`mix` build passes through the generated manifest** (ADR-0000 honesty; non-empty `[deps]` with no resolver is a loud error, not a silent drop); (5) the manifest **wires in `@external` foreign files** (ADR-0080 §7), not just copies them. BEAM defaults to **`rebar.config`** (Erlang-native, not `mix.exs` — keeps ADR-0080's host-decoupling); `rian eject` is the one-way promotion to a user-owned project. Staged Cargo → BEAM → Gradle → npm → plugins → eject | Proposed (direction) |

### Amending a decision-lock

ADRs are decision-locks: an **`Amended <date>`** line records when a locked rule
changes. Because the codebase treats ADRs as authoritative, an amendment is
**not done** until it has been propagated. Before considering an amendment
complete:

1. **Implement** the new rule and update the ADR text with a dated `Amended …`
   note quoting the new rule.
2. **Sweep for the superseded wording** — `grep` the tree for the old rule's
   phrasing (e.g. `no implicit narrow/widen`, `must unify exactly`) and fix every
   contradicting code comment, moduledoc, and sibling ADR.
3. **Pin the new behavior with a test**, and where the rule is a cross-surface
   invariant, an *executable* one — e.g. "what `Decl.compile` rejects, the REPL
   rejects" ([repl_test.exs](../test/rian/repl_test.exs)) rather than prose like
   the prose-only form ADR-0053's "the gate runs at the prompt" had before this
   test existed.
4. **Check the sibling sites** the rule should reach — a checking rule added at
   one position (a binding) usually has cousins (returns, branch joins) that must
   either adopt it or be explicitly documented as intentionally excluded.

This step exists because the 2026-06-13 widening amendment (ADR-0034 §1) initially
left contradicting comments and an un-propagated join rule within hours.

## Specifications

| Spec | Scope |
| --- | --- |
| [expressions.md](spec/expressions.md) | Expressions, operator precedence, blocks, `if` |
| [precedence-validation.md](spec/precedence-validation.md) | Machine-checked operator table |
| [types-match.md](spec/types-match.md) | `type` / `struct` / `alias` declarations and `match` |
| [clauses-guards.md](spec/clauses-guards.md) | Multi-clause functions, pattern + guard sublanguage |
| [pattern-lowering.md](spec/pattern-lowering.md) | Surface patterns → checker IR |
| [exhaustiveness.md](spec/exhaustiveness.md) | Usefulness algorithm, signatures, witnesses |
| [capability-lowering.md](spec/capability-lowering.md) | `val`/`iso`/`ref`/`tag` → Rust + BEAM linearity |
| [modules.md](spec/modules.md) | `mod`, visibility, imports |
| [error-handling.md](spec/error-handling.md) | `Result`, the `T \| E` sugar, `with` propagation, error-set composition |
| [end-to-end-lowering.md](spec/end-to-end-lowering.md) | Whole-pipeline `area/1` walkthrough |
| [selfhost-features.md](spec/selfhost-features.md) | Lambdas, `if`/blocks, list/map literals |

## Reading order

1. **Direction** — ADR-0026, ADR-0027, ADR-0031, ADR-0032 (ecosystem, self-hosting,
   bootstrap, and the surface-syntax family that governs every later syntax decision).
   Then the design spine: ADR-0033 (vocabulary), ADR-0034 (type-system foundations —
   the artifact every recent debate converges on), ADR-0035 (no hidden control flow).
2. **Surface language** — `expressions` → `types-match` → `clauses-guards` → `modules`.
3. **Semantics & lowering** — `pattern-lowering` → `exhaustiveness` → `capability-lowering`
   → `end-to-end-lowering`.
4. **Metaprogramming** — ADR-0030 + `selfhost-features`.

For the surface syntax *by example*, read the annotated tour in
[examples/rian/](../examples/rian/README.md) alongside the specs — each `.rian` file
demonstrates one facet (expressions, types/`match`, capabilities, modules,
macros/`comptime`, FFI) and cites the spec it follows.

For **how to write idiomatic Rian** — naming, control flow, errors, capabilities,
and the design judgment of *which construct to reach for* — see
[Effective Rian](style-guide.md), the style guide (modelled on *Effective Go*).

## Known gaps & open threads

These are the highest-priority items distilled from the specs' own "open items"
sections; they are tracked here so the corpus has one place to look:

- **Protocol-bounded generics** (ADR-0042 part 2) — **MVP landed**: `protocol`/`impl` parse,
  desugar to a guarded BEAM dispatcher ([protocol.ex](../lib/rian/protocol.ex)), run, and are
  coherence-checked; dispatch covers **primitive, sum (by constructor tag), and struct** types —
  enough for a real `Eq`/`Show` over the compiler's own data (`Token`, `Expr`). `forall T: Bound`
  is now **enforced at call sites** (a concrete type lacking the required `impl` is a proven error).
  A **portable stdlib** rides it: `contains`/`sort`/`maximum` over `Eq`/`Ord`
  ([17_stdlib_eq_ord.rian](../examples/rian/17_stdlib_eq_ord.rian)) and a **`Dict` over `Eq`**
  (`get`/`has`/`put` bounded `forall K: Eq` over a generic `Pair(k K, v V)`, Int64 + String keys,
  [18_dict_eq.rian](../examples/rian/18_dict_eq.rian)) — both run by their own `@test`s + doctests
  on BEAM/JS. *Still open:* dynamic (`dyn`) dispatch.
- **JS emitter completeness** (ADR-0049) — `with`/lambdas/atoms/FFI still raise `Unsupported`
  ([js.ex](../lib/rian/js.ex)); a browser playground that runs the compiler client-side needs them.
- **Two-Elixir-emitter consolidation** — *resolved*. The Erlang abstract-forms backend
  ([beam.ex](../lib/rian/beam.ex)) is the real BEAM path; [lower.ex](../lib/rian/lower.ex)'s Elixir
  *text* is a **debug view** (`mix rian.compile --show-elixir`). Both now consume the typed core IR,
  and the text emitter threads the same lexical scope `Rian.Beam` does — so the last documented
  divergence (higher-order *application*: a function-valued variable emits `f.(x)`, a local call
  `f(x)`) is gone. The two Elixir paths no longer drift.
- **Declarative `@targets(…)` annotation** (ADR-0058) — **shipped**: a `@targets(ex, rs, js)` module
  contract is parsed onto `IR.Mod.targets` and gated at compile time by `Rian.Reach.gate!` (every
  `pub` function must reach the declared set); an unannotated module falls back to the **build
  default** (`Rian.Reach.build_default/0` — `mix.exs` `rian: [targets: …]` or the app env).
- **Self-hosting Stage 1** — port the real compiler modules to Rian, each diffed against the
  reference by [fixpoint.ex](../lib/rian/fixpoint.ex). The lexer port is at slice 2; the next
  slices (string/char/float literals, brackets, `@annot`) are blocked on portable string/regex
  primitives, then the declaration parser ([decl.ex](../lib/rian/decl.ex)) follows.
