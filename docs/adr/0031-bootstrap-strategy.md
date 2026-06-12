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

| Stage | Deliverable | Backend |
|---|---|---|
| **0 (today)** | Front-end components + per-function emission, verified | Elixir source (`eval`) |
| **0.1 — the gate** | **Lexer + declaration parser**: parse whole `mod`/`type`/`fn`/`macro` files into the structures the pipeline already consumes | — |
| **0.2** | Module emitter + driver: parsed defs → one module → run | Elixir source |
| **0.3** | **Functioning language**: compile & run real `.rian` files; iterate syntax/behavior freely here | Elixir source (interim) |
| **0.5** | Swap backend to Erlang abstract forms / Core Erlang (`:compile.forms`); invisible to the language | Erlang-native (ADR-0026) |
| **1** | Self-host: rewrite the compiler in Rian, FFI to `:lists`/`:maps`/`:compile` | BEAM |
| **2** | Fixpoint: Stage1 compiles itself; compare artifacts | BEAM |

The single highest-leverage next step is **Stage 0.1 — the lexer + declaration parser** —
because every downstream component (checker, exhaustiveness, capabilities, macros, emitters)
already exists and is tested. That parser is what turns "verified components" into "a language
that reads source files."

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
