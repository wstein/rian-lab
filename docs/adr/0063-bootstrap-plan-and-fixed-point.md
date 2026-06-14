# ADR-0063 — Bootstrap plan: the self-hosting boundary and the fixed-point criterion

**Status:** Proposed
**Implemented:** partial — **BEAM** self-hosting (§4): Stage 0/1 equivalence-locked (ported lexer + parser slice; `Rian.Fixpoint`, `examples/rian/selfhost_*.rian`; `test/rian/fixpoint_test.exs`, `parse_fixpoint_test.exs`), the surface→Core lowering ported over the literal/unary/binary slice (`selfhost_core.rian` equals `Rian.Core.from_expr`; `core_fixpoint_test.exs`), the capability checker ported over the scalar/String/Vec/nominal slice (`selfhost_cap.rian` equals `Rian.Capability`; `cap_fixpoint_test.exs`), the exhaustiveness gate ported over the single-column nullary-constructor slice (`selfhost_exhaust.rian` agrees with Maranget `useful?/3`; `exhaust_fixpoint_test.exs`), the ECMAScript backend's expression emitter ported over the literal/unary/binary slice (`selfhost_js.rian` equals `Rian.JS` term-for-term; `js_fixpoint_test.exs`), the Rust/Kotlin/BEAM backends' expression emitters ported over the same slice (`selfhost_rust.rian` = `Rian.Lower.emit_expr`; `selfhost_kotlin.rian` = `Rian.JVM`; `selfhost_beam.rian` = `:erl_parse`'s abstract forms; `rust_emit_fixpoint_test.exs`/`kotlin_emit_fixpoint_test.exs`/`beam_emit_fixpoint_test.exs`), a slice of the real type checker ported (`selfhost_checker.rian` agrees with `Rian.Check.infer` on closed integer expressions; `checker_infer_fixpoint_test.exs`), Stage 2 near-complete (decl front-end IR-equals `Rian.Decl`), Stage 3 (`v1==v2` `.beam`) not. The marching boundary is **measured** (`Rian.SelfHost` → `docs/self-host-status.md`, `test/rian/self_host_status_test.exs`), FFI crutches are **counted+enforced** (`@selfhost_ffi` ledger, `self_host_ffi_test.exs`), and the two untested-fragility areas now have fixpoints with teeth (`checker_fixpoint_test.exs`, `string_emit_fixpoint_test.exs`). **Portable** self-hosting (compile-the-compiler to Rust/JS) is a *separate, further* terminus, gated on ADR-0047 breadth + the `Fn` Reach gap — not near.
**Refs:** ADR-0027 (fast track to self-hosting), ADR-0031 (reuse the runtime, not the compiler; abstract-forms backend), ADR-0050 (typed core IR — one IR, many front/back ends), ADR-0047 (portable prelude — the stdlib the ported compiler leans on), SELFHOST.md (the blocker ledger + the lexer/parser fixpoints)
**Owners:** Arthur Pendelton (compilers) · Chloe Bennett (parser) · Maya Lin (architecture) · Samir Patel (conformance) · Kira Neri (honesty) · Rachel Okafor (PM)

## Context

The self-hosting work has produced impressive spikes (a toy lexer→parser→optimizer→checker→codegen→VM
pipeline that compiles to real `.beam`) and two *equivalence-locked* ported stages: the lexer matches
`Rian.Lexer.tokenize/1` and a parser slice matches `Rian.Pratt.parse` (the fixpoint harnesses). But
"self-hosting" has been measured by **spikes that run**, with **no defined finish line**. SELFHOST.md
is a *blocker ledger*, not a *bootstrap plan*: it never states how much of the compiler must be in
Rian to claim self-hosting, in what order, or what the success proof is.

This ADR fixes that: it defines the **boundary** (what must be in Rian) and the **fixed-point
criterion** (the proof), as a staged ladder.

## Decision

### 1. The boundary: front-end first, march it down (ADR-0031)

Real self-hosting does **not** require porting everything at once. The compiler is a pipeline
(lexer → parser → typed Core IR → checker/exhaustiveness → emitters), and the typed Core IR (ADR-0050)
is a clean seam. So the **minimal viable self-hosted compiler** is:

> a **Rian-written front-end** (lexer + parser → the same Core IR the Elixir front-end builds), feeding
> the **existing Elixir-hosted checker + `Rian.Beam` emitter**.

Then the boundary marches down — checker, then the emitter — into Rian, one stage at a time, each
ported stage **equivalence-locked against the reference** (the fixpoint method) before the next. The
backend (`Rian.Beam`'s abstract-forms emitter) is the **last** thing to move, because it is the
hardest and the reference is most trusted there.

Cross-cutting prerequisite: the **portable stdlib** (ADR-0047). The real lexer/parser/checker lean on
`Enum`/`Map`/`String`/`List` ops; porting them needs those written in Rian. `List` (pure) and
`Dict`/`Str` prim-layers exist; the breadth (folds/maps/filters, keyword/struct helpers) is the
gating library work and blocks Stage 2 below.

### 2. The fixed-point ladder (the proof, staged)

| Stage | Claim | Proof | Status |
|---|---|---|---|
| **0 — Equivalence** | each ported stage matches the reference on a corpus | fixpoint diff (lexer vs `tokenize/1`; parser vs `Pratt.parse`) | **done** (lexer slices 1-5; parser slice) |
| **1 — Self-application** | a ported stage processes **real toolchain source** (incl. the self-hosting sources themselves) and agrees with the reference | run the Rian lexer over `selfhost_parse.rian` / preludes, diff vs `Rian.Lexer.tokenize/1` | **done for the lexer** (`test/rian/selfhost_fixedpoint_test.exs`) |
| **2 — Front-end self-host** | the Rian front-end produces the **same AST/IR** the Elixir front-end builds; the existing backend compiles it | parser output term-equals `Rian.Pratt.parse`; the **declaration** front-end's IR equals `Rian.Decl.parse` and runs via `Rian.Beam.compile_ir/2` | **near-complete** — a Rian **declaration** front-end (`selfhost_decl.rian`) parses `type` sums, **`struct` records**, **`mod` nesting** (incl. `pub def`), and `def` functions — multi-clause with **clause patterns** (var/lit/ctor/wildcard + **cons/list**), **capabilities**, **parametric types** (`Vec(T)`), **list construction**, **`.field`/labeled construction**, and **`when` guards** — into IR that **equals `Rian.Decl.parse`** and **compiles+runs** on the real backend (cons-recursive `rev`, a `struct` program, a `mod` compiled to its own BEAM module; `decl_fixpoint_test.exs`). **Remaining:** string/char clause patterns, `alias`/`protocol`/generics/doc-comments, and the portable stdlib breadth |
| **3 — Bootstrap fixed point** | the **whole compiler**, written in Rian, compiles its own source; doing so twice is stable | compile the Rian compiler source with the Elixir-hosted compiler → v1; compile the *same source* with v1 → v2; assert **v1 == v2** (bit-identical `.beam`) | **future** (the canonical terminus); its **determinism prerequisite is verified** — `Rian.Beam` emits byte-identical bytecode on recompilation (`selfhost_fixedpoint_test.exs`) |

**"Real self-hosting" = Stage 2** (the front-end genuinely self-hosts, reusing a trusted backend);
**Stage 3** is the canonical bootstrap fixed point that retires the Elixir host entirely.

**This whole ladder is the BEAM terminus** — Stage 2 feeds `Rian.Beam.compile_ir/2` and Stage 3 asserts
`v1 == v2` over `.beam` bytecode. It says nothing about lowering the compiler to Rust or JS; that is a
*separate, further* terminus (§4).

### 3. Honesty rule (Kira)

Do not call Stage 1 a "bootstrap fixed point." It is **self-application**: a ported stage lexing real
Rian source (including its own) and matching the reference. The genuine vN==vN+1 fixed point is Stage 3
and requires the compiler in Rian. Each stage's claim is bounded to what its proof actually shows.

### 4. Two termini: BEAM self-hosting vs portable self-hosting (do not conflate)

The debate kept tripping over a contradiction: the docs imply "self-hosting" is one finish line, but
there are **two**, and the portable one is much further out than the prose suggested. Name them apart.

- **BEAM self-hosting** — the Stages 0–3 ladder above. The Rian compiler compiles its own source to
  `.beam` and the result is a stable fixed point *on the BEAM*. This is the reachable, on-the-critical-
  path goal; the host language being retired is Elixir, the target staying the BEAM. The blockers are
  parser/checker/backend coverage + ADR-0047 stdlib breadth — **not** target portability.
- **Portable self-hosting** — compiling *the compiler itself* to **Rust and/or JS** (`mix rian.build
  --rust`/`--js` over the Rian-written compiler), so Rian's toolchain runs off the BEAM entirely. This
  is the headline once `v1==v2` holds, but it is **gated on strictly more**:
  1. **ADR-0047 prelude breadth** — every `Enum`/`Map`/`String`/`List` op the compiler uses must be
     written in portable Rian, not host FFI (the `@selfhost_ffi` ledger measures the remaining debt).
  2. **The parametric / `Fn` Reach gaps** — a real compiler is saturated with `Vec(Token)`, `Map(K,V)`,
     and higher-order passes; `Rian.Reach` still **honestly pins** the `Fn(...)`-signature shapes (and,
     until recently, owned-generic/parametric returns) off `:rs`. Portable self-hosting cannot precede
     those landing — the recent Rust-generic work (ADR-0061: owned↔borrow coercion, `enum Pair<K,V>`,
     `Option(T)`/`T|E` returns) closed most of them, leaving returned closures (`Fn`) as the live gap.

**Sequencing trap to avoid (consensus):** do **not** port the checker on top of host-FFI crutches and
then swap the stdlib underneath it — the diff becomes unverifiable. A small **P5 portable core** lands
*before* the checker port (P3), and each crutch is **counted** in the `@selfhost_ffi` ledger so every
swap deletes a line. The marching boundary is **measured** (`Rian.SelfHost`, `self-host-status.md`),
not asserted — "% of the pipeline self-hosted" is a number, not a vibe.

## Rationale

- **A finish line beats momentum.** Spikes proved capability; a staged criterion converts "look, it
  runs" into "this stage is *proven equivalent / self-applies / self-hosts*."
- **Front-end-first is the cheap, high-signal path** (ADR-0031): the IR seam lets a Rian front-end
  reuse the trusted backend, so Stage 2 is reachable without porting the hardest component.
- **The fixpoint method already scales** to each stage — Stage 0/1 reuse it verbatim; Stage 2 diffs IR;
  Stage 3 diffs bytecode. One verification idea, four stages.

## Consequences

- **Now:** Stage 0 (equivalence) and Stage 1 (lexer self-application) are real and tested. The roadmap
  has a defined target instead of open-ended spikes.
- **Next:** widen the parser slice → port `Rian.Decl` → Stage 2 (front-end self-host), gated on the
  portable stdlib (ADR-0047). Stage 3 follows once the backend is in Rian.
- SELFHOST.md becomes the *ledger of blockers per stage*; this ADR is the *plan*.
- **The boundary is instrumented (not narrated):** `Rian.SelfHost` declares each pipeline stage's
  self-host state and renders `docs/self-host-status.md` (a `% self-hosted` headline + per-stage table),
  snapshot-gated so it can't drift; the `@selfhost_ffi` ledger enumerates every host-FFI crutch in the
  self-host sources and a test (via `Rian.Reach`) fails on an **unlisted** crutch *or* a **stale** ledger
  line — so each P5 swap must delete both the call and its ledger entry.

## Open items

- **IR equality for Stage 2** — the Core IR carries some incidental fields (positions, fresh names);
  define the canonical/normalized equality the front-end diff uses.
- **Portable-stdlib breadth** — enumerate the `Enum`/`Map`/`String` ops the real front-end needs and
  port them (ADR-0047), the true gate on Stage 2.
- ~~**Determinism for Stage 3**~~ — **verified**: `Rian.Beam` already emits byte-identical bytecode on
  recompilation (the optimizer/parser/module sources round-trip identically — `selfhost_fixedpoint_test.exs`).
  Re-audit if the emitter gains atom-table or name-ordering nondeterminism.
