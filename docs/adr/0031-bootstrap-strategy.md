# ADR-0031 — Bootstrap Strategy: Reuse the Elixir *Runtime*, Not the Elixir *Compiler*

**Status:** Accepted · **Refines:** ADR-0027 (fast track to self-hosting) · **Consistent with:** ADR-0026 (don't fork Elixir/OTP)
**Owners:** Arthur Pendelton (compilers) · Chloe Bennett (parser) · Maya Lin (architecture) · Rachel Okafor (PM)

## Context

Rian is syntactically Elixir-adjacent, which invites the question: should we bootstrap by
starting from the Elixir codebase — adapt its parser, modify its implementation, and get a full
working language immediately, then iterate syntax/behavior continuously?

"Start with the Elixir codebase" conflates three very different strategies:

1. **Fork the Elixir compiler** — modify `elixir_tokenizer.erl` + `elixir_parser.yrl`.
2. **Target Elixir source** — emit `.ex` text, shell out to `elixirc`.
3. **Host in Elixir + reuse the runtime** — write Rian's compiler in Elixir, reuse BEAM/OTP/
   stdlib, emit to BEAM.

We already do (3). The question is whether to move toward (1).

## Decision

**Do not fork the Elixir compiler. Continue hosting Rian's compiler in Elixir and reuse the
Elixir/BEAM *runtime and ecosystem* maximally. Reach a fully functioning language fast by using
Elixir-*source* emission as an interim backend, then swap the backend to Erlang abstract forms
(`:compile.forms`) without touching the language.**

The decisive architectural fact: **the front-end (lex → parse → check) is backend-agnostic.**
Therefore "get a functioning language fast" and "emit Erlang-native / don't fork" are **not in
tension** — they are different layers and are sequenced independently.

### Strategies, rated

| Strategy | Rating | Rationale |
|---|---|---|
| Fork Elixir compiler (modify lexer/grammar) | **1/5** | Rian's distinctive semantics — `:=` single-assignment variables, `<-` capability-gated mutation, mandatory signature capabilities, closed exhaustive sums, non-Elixir macros — are absent from Elixir's AST and must be rebuilt regardless; meanwhile you inherit a grammar that fights them, stay permanently downstream of Elixir releases, and inherit `quote`/`unquote` (the rejected macro model). |
| "Adapt" Elixir's yecc parser | **2/5** | Changing binding semantics, operators, and `fn name(params) RetType` heads is a grammar rewrite of an LALR `.yrl` — *more* work than extending our existing Pratt parser, with none of Rian's type/capability machinery for free. |
| Transpile Rian → Elixir source (as the destination) | **3/5** | Fastest to end-to-end working, but textual IR is fragile, slow per-module, and inherits Elixir's macro/hygiene model; acceptable only as a temporary accelerator, not the final backend. |
| **Host in Elixir; emit Elixir source now → swap to abstract forms later** | **5/5** | Functioning language immediately; the backend swap is invisible to the language; honors ADR-0026 on its own schedule. |

## Why forking is the trap (not ideology)

- **Semantics, not syntax.** The interesting parts of Rian don't exist in Elixir's model, so
  "adapt" really means "rip out and replace the front-end" — while still constrained by the
  inherited grammar.
- **Macro mandate violation.** A fork inherits `quote`/`unquote`; the macro decision (ADR-0030)
  was explicitly *not that*.
- **Permanent downstream cost.** Every Elixir release becomes a merge against a parser you've
  diverged from; you can never be a "first-class" language, only a patched Elixir.
- **Larger trust surface.** A fork inherits Elixir's whole expansion model, which would have to
  be re-audited against our pure-comptime / sandboxed-macro decisions.
- **Our parser is cheaper to extend.** The hand-written Pratt parser already handles Rian's real
  precedence, lambdas, `if`/blocks, literals, dot syntax, and patterns (116 tests). Parsing
  whole files is an extension of it; bending `elixir_parser.yrl` is not.

## What we DO reuse from Elixir (maximally)

- **Runtime:** the BEAM, OTP behaviours, supervision, processes. **Concurrency is OTP/actors** —
  Rian does not add CSP (Go), coroutines (Kotlin), or Oz-style dataflow concurrency; `:=` is a
  single-assignment *variable*, not a blocking dataflow primitive. Non-BEAM targets get the
  sequential core; concurrency stays BEAM-native.
- **Ecosystem:** Hex, Mix/rebar3 integration, EEP-48 docs, dialyzer specs (per ADR-0026).
- **Stdlib via FFI:** `:lists`, `:maps`, `String`, `Enum`, … are callable for free (ADR-0027).
- **Execution today:** we already emit Elixir source and run it on the BEAM in every test.

The kernel of the proposal — *lean on Elixir, get a full language working, iterate
continuously* — is correct. The only correction is **which layer**: the runtime and ecosystem,
plus interim source emission — **not** the compiler source.

## Roadmap (refines ADR-0027)

State legend: ✅ done · 🟡 in progress · ⬜ not started. State reflects the
implementation as of 2026-06-12 (214 component tests green at HEAD).

| Stage | Deliverable | Backend | State |
|---|---|---|---|
| **0 (today)** | Front-end components + per-function emission, verified | Elixir source (`eval`) | ✅ **Done** — all passes implemented & tested ([lib/rian/](../../lib/rian/)) |
| **0.1 — the gate** | **Lexer + declaration parser**: parse whole `mod`/`type`/`fn`/`macro` files into the structures the pipeline already consumes | — | 🟡 **In progress** — [`Rian.Lexer`](../../lib/rian/lexer.ex) + [`Rian.Decl`](../../lib/rian/decl.ex) parse `type`/`struct`/`alias`/`def` (`:=` / `… end` block / `case` bodies, `when` guards, multi-param). `mod` parsing underway; `macro` files not yet |
| **0.2** | Module emitter + driver: parsed defs → one module → run | Elixir source | 🟡 **Partial** — [`Decl.compile/1`](../../lib/rian/decl.ex) parses → lowers → runs a module end-to-end ([decl_run.exs](../../examples/decl_run.exs)); `mod`-level grouping/visibility pending |
| **0.3** | **Functioning language**: compile & run real `.rian` files; iterate syntax/behavior freely here | Elixir source (interim) | 🟡 **Started** — real files compile & run ([examples/area.rian](../../examples/area.rian)); exhaustiveness gate fires on parsed source. Surface still narrow |
| **0.5** | Swap backend to Erlang abstract forms / Core Erlang (`:compile.forms`); invisible to the language | Erlang-native (ADR-0026) | ⬜ **Not started** — interim backend still emits Elixir/text source |
| **1** | Self-host: rewrite the compiler in Rian, FFI to `:lists`/`:maps`/`:compile` | BEAM | ⬜ **Not started** |
| **2** | Fixpoint: Stage1 compiles itself; compare artifacts | BEAM | ⬜ **Not started** |

The highest-leverage work now is **closing out Stage 0.1 → 0.2**: land `mod`
parsing and module-level grouping/visibility so multi-declaration files emit as
one cohesive module. The downstream components (checker, exhaustiveness,
capabilities, macros, emitters) already exist and are tested — finishing the
declaration parser + module emitter is what turns "verified components" into "a
language that reads and runs whole source files." A first increment of the real
type checker ([`Rian.Check`](../../lib/rian/check.ex), ADR-0034) has also landed
alongside the parser work.

> **Note — the Rust target is not a bootstrap stage.** The stages above track the
> *BEAM* path (interim Elixir source → Erlang abstract forms at Stage 0.5).
> Rust is a **backend-parallel** target: the front-end emits idiomatic,
> ownership-checked Rust ([`Rian.Lower.to_rust/5`](../../lib/rian/lower.ex),
> capabilities → Rust signatures via [`Rian.Capability`](../../lib/rian/capability.ex)),
> already implemented and tested at the component level (emitted Rust is compiled
> with `rustc` in examples). It rides Stages 0.1/0.3 automatically — parsed
> `.rian` files emit both targets — and stays a **source emitter** permanently;
> there is no "Rust abstract forms" swap analogous to Stage 0.5.

## Consequences
- No fork; no permanent downstream tax; macro mandate preserved.
- A runnable language arrives as soon as the declaration parser + driver land, on the interim
  Elixir-source backend — so syntax/behavior iteration can begin immediately.
- The Erlang-native backend (ADR-0026) is sequenced *after* the language works, as a
  backend-only swap.

## Open items
- Decide the interim cutover point from Elixir-source emission to abstract forms (likely once
  the module emitter is stable and pattern/guard lowering is exercised on real files).
- Mix compiler + rebar3 plugin packaging (ADR-0026) can land alongside Stage 0.3.
