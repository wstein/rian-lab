# ADR-0031 — Bootstrap Strategy: Reuse the Elixir *Runtime*, Not the Elixir *Compiler*

**Status:** Accepted · **Refines:** ADR-0027 (fast track to self-hosting) · **Consistent with:** ADR-0026 (don't fork Elixir/OTP)
**Implemented:** yes — Elixir-hosted front-end with both interim text backend (`Rian.Lower`) and abstract-forms backend (`Rian.Beam`); Elixir compiler not forked
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
- **Execution:** the default BEAM path lowers to **Erlang abstract forms** (`:compile.forms` →
  loadable `.beam`); the Elixir-source emitter remains as a demo/inspection path.

The kernel of the proposal — *lean on Elixir, get a full language working, iterate
continuously* — is correct. The only correction is **which layer**: the runtime and ecosystem,
plus interim source emission — **not** the compiler source.

## Roadmap (refines ADR-0027)

State legend: ✅ done · 🟡 in progress · ⬜ not started. State reflects the
implementation as of 2026-06-13.

| Stage | Deliverable | Backend | State |
|---|---|---|---|
| **0** | Front-end components + per-function emission, verified | Elixir source (`eval`) | ✅ **Done** — all passes implemented & tested ([lib/rian/](../../lib/rian/)) |
| **0.1 — the gate** | **Lexer + declaration parser**: parse whole `mod`/`type`/`fn` files into the structures the pipeline consumes | — | ✅ **Done** — [`Rian.Lexer`](../../lib/rian/lexer.ex) + [`Rian.Decl`](../../lib/rian/decl.ex) parse `type`/`range`/`struct`/`alias`/`const`/`use`/`def` and `mod` files (`:=` / `… end` block / `case`, `with`, `when` guards, multi-param) |
| **0.2** | Module emitter + driver: parsed defs → one module → run | Elixir source / BEAM | ✅ **Done** — [`Decl.compile/1`](../../lib/rian/decl.ex) and [`Rian.Beam.load_program/1`](../../lib/rian/beam.ex) compile a `mod` (or several) to one module and run it |
| **0.3** | **Functioning language**: compile & run real `.rian` files; iterate syntax/behavior freely | BEAM | ✅ **Done** — real files compile & run; surface now covers sums, `struct`, `range`/`Char`, generics (`Vec(T)`), `case`/`with`, capabilities, typed bindings; exhaustiveness/error-set/linearity gates fire |
| **0.5** | Swap backend to Erlang **abstract forms** (`:compile.forms`); invisible to the language | Erlang-native (ADR-0026) | ✅ **Done** — [`Rian.Beam`](../../lib/rian/beam.ex) lowers to the Erlang abstract format + `:compile.forms` → loadable `.beam` (no `eval`, no Elixir-compiler dep, line-tracked). The default execution path for BEAM tests and the self-hosting spikes |
| **1** | Self-host: rewrite the compiler in Rian, FFI to `:lists`/`:maps`/`:compile` | BEAM | 🟡 **Started** — a six-layer compiler pipeline (lexer→parser→optimizer→checker→codegen→VM) is written in Rian and compiles to real `.beam` ([examples/rian/](../../examples/rian/), SELFHOST.md); the **real** `Rian.Lexer` port is underway ([lexer_v2.rian](../../compiler/lexer_v2.rian)) and diffed against the reference by [`Rian.Fixpoint`](../../lib/rian/fixpoint.ex) |
| **2** | Fixpoint: Stage1 compiles itself; compare artifacts | BEAM | ⬜ **Not started** — the per-component fixpoint *harness* exists (`Rian.Fixpoint`); a full Stage1-compiles-Stage1 reproducibility check does not |

The highest-leverage work now is **Stage 1**: porting the real compiler modules
to Rian one at a time, each diffed against the Elixir reference by `Rian.Fixpoint`
so a ported slice is a regression test. The blockers are protocol-bounded
generics (ADR-0042 part 2 — needed to type map/fold-shaped compiler code and a
test framework) and a portable stdlib beyond `List`/`Dict`/`Str`. The front-end
components (parser, checker, exhaustiveness, capabilities, the three emitters)
all exist and are tested.

> **Note — the Rust target is not a bootstrap stage.** The stages above track the
> *BEAM* path (interim Elixir source → Erlang abstract forms at Stage 0.5).
> Rust — and every other target (ECMAScript, JVM, WASM, Go; see the tiers in
> [ADR-0049](0049-backend-target-roadmap.md)) — is a **backend-parallel** target: the front-end emits idiomatic,
> ownership-checked Rust ([`Rian.Lower.to_rust/5`](../../lib/rian/lower.ex),
> capabilities → Rust signatures via [`Rian.Capability`](../../lib/rian/capability.ex)),
> already implemented and tested at the component level (emitted Rust is compiled
> with `rustc` in examples). It rides Stages 0.1/0.3 automatically — parsed
> `.rian` files emit both targets — and stays a **source emitter** permanently;
> there is no "Rust abstract forms" swap analogous to Stage 0.5.

## Consequences
- No fork; no permanent downstream tax; macro mandate preserved.
- A runnable language arrived on the interim Elixir-source backend, then the Erlang-native
  abstract-forms backend ([`Rian.Beam`](../../lib/rian/beam.ex)) landed as a **backend-only swap**
  invisible to the language — exactly as sequenced (Stage 0.5, now done).

## Open items

**Cutover & packaging — resolved in the 2026-06-12 decision-lock review:**

- **The cutover was a *gate*, not a date — and it has happened.** The de-risking spike (push a
  function through abstract forms → `:compile.forms` → `:code.load_binary` → call, as a test) became
  the [`Rian.Beam`](../../lib/rian/beam.ex) backend: the abstract-forms path is the default for BEAM
  execution and produces real, hashable `.beam`. The interim Elixir-source/`eval` text emitter
  remains only as a demo/inspection path (and the Rust source emitter); it was never a shippable
  target (ADR-0026 demotes it: `'Elixir.Mod':func` prefixing is non-first-class for Erlang callers,
  and `eval` produces no hashable `.beam`).
  - **Readable `.erl` first** as the first Erlang-native output (ADR-0026 pragmatic step + permanent
    debug output) — it is the prettyprint of the abstract forms, so it costs nothing extra.
  - **Full-cutover gate = the ADR-0026 interop acceptance test passing** (a Rian module callable from
    both `erl` and IEx with no shims) *and* pattern/guard lowering exercised on real files
    (≈ end 0.3 / start 0.5). That test *cannot* pass on the Elixir-source backend, so it defines the
    cutover.
- **Packaging splits by readiness, not "alongside 0.3":**
  - **Manifest schema** (app/version/deps → Hex metadata; ADR-0026 open item) is backend-independent
    and starts **now** at 0.3.
  - A **throwaway `Mix.Tasks.Compile.Rian` dev harness** may land at 0.3 to dogfood the driver and
    serve as the integration test bed — **unpublished**, and it must **invoke the self-contained
    escript** (ADR-0026), never the host Elixir in-process.
  - **Publishable** Mix compiler + rebar3 plugin (and **Hex publish/consume**) wait until **after the
    0.5 cutover**, so they emit first-class, hashable `.beam` — not `'Elixir.Mod'`-prefixed `eval`
    output. The **rebar3 plugin is the first-class priority** (ADR-0026's "Erlang citizen" thesis);
    the Mix harness is merely the cheaper first prototype.

**Other open items:**

- **Concurrency is native-per-target — a deliberate boundary, not a gap** (clarified 2026-06-13;
  refines the 2026-06-12 lock). Rian's purpose is to **share sequential application logic and tests**
  across targets — the canonical proof is Rian's own lexer/parser running on the BEAM, Rust, and
  ECMAScript. Concurrency is **out of the portable core by design**: it *may and should* be
  implemented in each target's native runtime — OTP on the BEAM, async/threads in Rust,
  Promises/workers in JS. So "non-BEAM gets the sequential core" is not an unfilled gap to lament but
  the **intended division of labour**: shared Rian = sequential logic; orchestration wraps it
  natively per platform. *If* portable structured concurrency were ever added it would still have to
  be lexically explicit (Occam-style scoped parallelism, no detached tasks; ADR-0035), never Go-style
  implicit `go` — but the default stance is "write it native," not "abstract it portably."
  - **No forced file-forking for concurrency**, because concurrency-flavoured code is simply **not
    shared Rian source** — you write the pure logic once in Rian and call it from a native gen_server
    / task / worker. The residual case for an author-directed target conditional (sequential
    representation tails the portable prelude can't reach, ADR-0047) is narrow; see
    [ADR-0056](0056-comptime-target-conditional.md) (**Proposed, motivation now thin** — not a
    concurrency tool).
