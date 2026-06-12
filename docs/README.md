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
| Lexer + declaration parser | **Stage 0.1 (MVP)** | [decl.ex](../lib/rian/decl.ex) — token-driven; `type` + single/multi-param `def`, `:=` and block bodies, end-to-end ([decl_run.exs](../examples/decl_run.exs)) |
| Real type checker | **Not started** | passes are "typecheck-shape" only; FFI is `dynamic` |
| Erlang abstract-forms backend | Not started | interim backend emits Elixir/text source |

All passes today are driven by **hand-built IR**, not by parsing `.rian` source.
The component test suites pass; cross-pass integration is thin. Treat the
"verified" banners inside individual specs as *component-level*, not end-to-end.

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

- **No single typed core IR.** Each pass defines its own pattern/expression
  shape. This produced drift between the emitter and the linearity checker —
  now fixed: `Rian.Capability.count_uses/1` is total over the current parser
  AST — but the structural risk remains (the emitter still consumes surface
  patterns while the checker consumes lowered ones). A shared IR is the
  highest-leverage refactor.
- **Declaration parser** (ADR-0031 Stage 0.1) — the gate to compiling real files.
- **Symbol resolution** for ADR-0029 — Rian module vs Elixir-stdlib vs field.
- **Backend swap** to Erlang abstract forms / `:compile.forms` (ADR-0026), still
  unexercised — the "invisible swap" assumption has no test coverage.
