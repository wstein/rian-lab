# ADR-0063 — Bootstrap plan: the self-hosting boundary and the fixed-point criterion

**Status:** Proposed · **Refs:** ADR-0027 (fast track to self-hosting), ADR-0031 (reuse the runtime, not the compiler; abstract-forms backend), ADR-0050 (typed core IR — one IR, many front/back ends), ADR-0047 (portable prelude — the stdlib the ported compiler leans on), SELFHOST.md (the blocker ledger + the lexer/parser fixpoints)
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
| **2 — Front-end self-host** | the Rian front-end produces the **same AST/IR** the Elixir front-end builds; the existing backend compiles it | parser output term-equals `Rian.Pratt.parse`; the **declaration** front-end's IR equals `Rian.Decl.parse` and runs via `Rian.Beam.compile_ir/2` | **core + multi-clause done** — a Rian **declaration** front-end (`selfhost_decl.rian`) parses `type` sums and `def` functions — **including multi-clause `def` with clause patterns** (ctor/nested-literal/var/wildcard) and **capabilities** (`val`/`iso`/`ref`/`tag`) — into IR that **equals `Rian.Decl.parse`** and **compiles+runs** on the real backend (a multi-clause `simp` over a sum runs; `decl_fixpoint_test.exs`). **Remaining:** `when` guards, parametric param types (`Vec(T)`), cons/list/string/char patterns, `mod`/`struct`/`alias`/`protocol`/generics/doc-comments, and the portable stdlib breadth |
| **3 — Bootstrap fixed point** | the **whole compiler**, written in Rian, compiles its own source; doing so twice is stable | compile the Rian compiler source with the Elixir-hosted compiler → v1; compile the *same source* with v1 → v2; assert **v1 == v2** (bit-identical `.beam`) | **future** (the canonical terminus); its **determinism prerequisite is verified** — `Rian.Beam` emits byte-identical bytecode on recompilation (`selfhost_fixedpoint_test.exs`) |

**"Real self-hosting" = Stage 2** (the front-end genuinely self-hosts, reusing a trusted backend);
**Stage 3** is the canonical bootstrap fixed point that retires the Elixir host entirely.

### 3. Honesty rule (Kira)

Do not call Stage 1 a "bootstrap fixed point." It is **self-application**: a ported stage lexing real
Rian source (including its own) and matching the reference. The genuine vN==vN+1 fixed point is Stage 3
and requires the compiler in Rian. Each stage's claim is bounded to what its proof actually shows.

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

## Open items

- **IR equality for Stage 2** — the Core IR carries some incidental fields (positions, fresh names);
  define the canonical/normalized equality the front-end diff uses.
- **Portable-stdlib breadth** — enumerate the `Enum`/`Map`/`String` ops the real front-end needs and
  port them (ADR-0047), the true gate on Stage 2.
- ~~**Determinism for Stage 3**~~ — **verified**: `Rian.Beam` already emits byte-identical bytecode on
  recompilation (the optimizer/parser/module sources round-trip identically — `selfhost_fixedpoint_test.exs`).
  Re-audit if the emitter gains atom-table or name-ordering nondeterminism.
