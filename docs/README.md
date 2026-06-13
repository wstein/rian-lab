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
| End-to-end lowering (Elixir + Rust) | Implemented | [lower.ex](../lib/rian/lower.ex) |
| Hygienic macros + pure comptime | Implemented | [macro.ex](../lib/rian/macro.ex), [comptime.ex](../lib/rian/comptime.ex) |
| Lexer + declaration parser | **Stage 0.1 (broad)** | [decl.ex](../lib/rian/decl.ex) — token-driven; `type`/`struct`/`alias`/`const`/`use`/`mod` + single/multi-param `def`, `:=`/block/`case` bodies, `when` guards, `pub` visibility. Struct & sum-variant construction (positional + named) and constant references lower per target. The modules tour ([05_modules.rian](../examples/rian/05_modules.rian)) parses and lowers end-to-end. Not yet: `macro` files |
| Real type checker | **Compile gate + flow narrowing** | [check.ex](../lib/rian/check.ex) — ADR-0034 §1/§4: unification-based inference gates `compile`, rejecting only *provable* return-type mismatches; `case` arms and pattern clauses narrow bound variables to the matched variant's field types. Error sets (§2) and protocol bounds (§3) await their surface |
| Erlang abstract-forms backend | Not started | interim backend emits Elixir/text source |

A growing slice now flows **from `.rian` source** through the parser → typed core
IR → dual-target lowering (the modules tour compiles end-to-end); the remaining
passes still run on hand-built IR. The component suites pass and this front-end
path is integration-tested ([decl_run.exs](../examples/decl_run.exs),
[decl_test.exs](../test/rian/decl_test.exs)). Treat the "verified" banners inside
individual specs as *component-level* unless the tour exercises them end-to-end.

## Architecture Decision Records

| ADR | Title | Status |
| --- | --- | --- |
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
| [0042](adr/0042-protocol-bounded-generics.md) | Protocol-bounded generics: `forall` binders, `protocol`/`impl`, coherence, dispatch | Accepted (direction) |
| [0043](adr/0043-opaque-types.md) | Opaque types: module-scoped nominal distinctness over a base, zero-cost | Accepted (direction) |
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
| [0055](adr/0055-capabilities-through-dispatch-and-opaque.md) | Capabilities through dynamic dispatch & opaque types: capability on the protocol method receiver (survives `dyn` erasure); opaque-over-struct presents the join of field capabilities | Accepted (direction) |
| [0056](adr/0056-comptime-target-conditional.md) | `comptime if target`: proven-equivalent (or type-visible) sequential target conditional, else hard error. Motivation thinned — concurrency is native-per-target (ADR-0031), so the fracture it addressed isn't shared Rian source | **Proposed (dormant)** |
| [0057](adr/0057-concurrency-and-otp-are-native-per-target.md) | Concurrency & OTP are native-per-target: Rian source is sequential logic + tests; gen_servers/tasks/workers are written in the host's native language and call shared Rian functions. Supersedes 0044 | Accepted (direction) |
| [0058](adr/0058-configurable-target-environments.md) | Configurable target environments (`:ex`/`:rs`/`:js`), reachability-gated: `Rian.Reach` computes per-function reach via a call-graph fixpoint; `mix rian.targets [--require …]` reports and gates by need. Concurrency-FFI is a fallout | Accepted; partially implemented |

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

## Known gaps & open threads

These are the highest-priority items distilled from the specs' own "open items"
sections; they are tracked here so the corpus has one place to look:

- **No single typed core IR** — **designed: [ADR-0050](adr/0050-typed-core-ir.md)** (migration
  pending). Each pass defines its own pattern/expression shape; the emitter consumes surface
  patterns while the checker consumes lowered ones — the drift B1 hit in *three* places
  ([SELFHOST.md](../SELFHOST.md)). ADR-0050 fixes the contract (one typed sealed-sum core IR,
  emitters as pure consumers, one parser); the incremental migration is the highest-leverage
  refactor and is sequenced before the ECMAScript emitter and Stage 0.5.
- **Declaration parser** (ADR-0031 Stage 0.1) — the gate to compiling real files.
- **Symbol resolution** for ADR-0029 — Rian module vs Elixir-stdlib vs field.
- **Backend swap** to Erlang abstract forms / `:compile.forms` (ADR-0026), still
  unexercised — the "invisible swap" assumption has no test coverage.
