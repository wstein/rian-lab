# ADR-0088 — Reference interpreter as the executable spec & conformance oracle (not a runtime target)

**Status:** Proposed
**Implemented:** no — direction + scope. The decision is to *build* the reference interpreter (P1) and
*promote* it to the conformance oracle; no interpreter exists yet (`lib/rian/interp.ex` is the
**string-interpolation** desugar, ADR-0069 — an unrelated module that happens to share the word,
hence the naming decision in §1).
**Refines:** ADR-0000 (charter — Rian lowers to existing idiomatic targets and ships **no separate
Rian runtime**; the interpreter is a *spec we can run*, explicitly not a runtime), ADR-0050 (one typed
Core IR — the interpreter is a **pure consumer of Core**, like an emitter; **no fork**), ADR-0058
(reachability-gated honesty matrix — the interpreter *anchors* it rather than widening it), ADR-0060
(testing: executable spec-by-example — the conformance corpus the oracle runs).
**Amends:** ADR-0052 §"Playground architecture" — the live-playground engine is no longer *only*
self-host → JS; the reference interpreter compiled to WASM/JS is a second, **earlier** engine that
ships ahead of the `v1==v2` bootstrap (see §3).
**Refs:** ADR-0057 (concurrency native-per-target — removes the one thing a runtime VM would be *for*),
ADR-0063 (bootstrap / self-host — the standing #1 priority a VM would compete with; the playground now
ships *ahead* of it), ADR-0049 §5a / ADR-0085 (backend-tier admission + target budget — a future VM
would enter here, not as an exception), ADR-0035 (no hidden control flow — the evaluation order the
interpreter must honour), ADR-0064 (portable numeric contract — integer wrap the oracle pins),
ADR-0069 (string interpolation — owns the `Rian.Interp` name).
**Owners:** Kira Neri (honesty/oracle inversion) · Maya Lin (Core consumer / emitters) · Elena Rostova
(numerics; the deferred-VM dissent) · Mira Halden (anti-drift gate) · Liam Davis (playground/DX) ·
Rachel Okafor (PM)

## Context

A recurring "rian-vm" proposal turned out to be **three different things wearing one name**, and the
debate's real work was separating them:

- **an interpreter** — a *function* `Core → value`, total and tree-walking;
- **a runtime VM** — a *product we would own forever* (its own bytecode, GC, scheduler), as an
  emission target;
- **a playground engine** — a *packaging concern* (how "edit, see it run" works in the browser).

Conflated, "rian-vm" looked compelling. Separated, only the interpreter is unambiguously worth
building now, the VM is the one to refuse, and the playground is a packaging choice that the
interpreter happens to unlock early.

The charter is **load-bearing here, not ceremonial.** Rian's thesis (ADR-0000) is that the *same
source* lowers to existing idiomatic targets with **no separate Rian runtime**; ADR-0050 forbids a
second IR fork; ADR-0057 makes concurrency native-per-target — which removes the single thing a
portable VM would exist to provide (a portable scheduler). So a bytecode VM-as-target is not a neutral
addition: it contradicts three accepted decisions at once.

The **honesty matrix is the swing vote.** A bytecode VM would *widen* the per-target conformance matrix
(ADR-0058) and has no host type-checker to anchor it. A tree-walking interpreter, *promoted to the
oracle*, does the opposite: it gives the matrix a single executable reference every emitter is checked
against.

## Decision

### 1. Build P1 — the reference interpreter (`Rian.Eval`), a pure Core consumer, **not** a runtime

A small, **total, tree-walking** evaluator over `Rian.Core` (ADR-0050): `Core → value`, sequential-only
(ADR-0057 — no scheduler, no processes), **no bytecode, no GC we write**. It is a pure consumer of the
typed Core, exactly like an emitter — so it inherits the gates (`Check`/`Exhaustiveness`/`Reach`) and
adds no new IR (ADR-0050, no fork). It is the **executable specification**, explicitly **not a runtime
target** and not on the `Rian.Reach` `@targets` vocabulary.

**Naming (honest correction).** The debate proposed calling it `Rian.Interp`. That name is **already
taken** by the string-interpolation desugar (ADR-0069, `lib/rian/interp.ex`), which is *not* a partial
interpreter — so "fold/replace the partial `Rian.Interp`" rests on a misread and is dropped. The new
module is **`Rian.Eval`** (the reference evaluator); it starts fresh, not from the interpolation pass.

### 2. Promote it to the conformance **oracle** by wiring, not decree

Add an **`:eval` lane to `Rian.ConformanceTest`** (`test/rian/conformance_test.exs`, the ADR-0049 §5a
Tier-1 gate): run the portable-core corpus through `Rian.Eval` and assert **`eval` agrees with each
emitter** (`:ex`/`:rs`/`:js`) value-for-value. The oracle is *real* the day a BEAM/`eval` disagreement
is a **failing BEAM test** — i.e. the BEAM is the bug, not the interpreter.

This **inverts the conformance hierarchy** (Kira's concession): today the BEAM backend is the de-facto
spec; after the inversion the interpreter is, and the BEAM is *de-privileged* to "one backend among
several". That is the cost, and it is **accepted** because it is exactly what makes P1 a *net-honesty
gain* — a single anchor instead of an implicit one.

### 3. P3 — playground engine = P1 → WASM/JS, shipped **ahead** of self-host (amends ADR-0052)

The interpreter compiled to WASM/JS is a complete in-browser "edit, see it run" engine that **does not
wait for the `v1==v2` self-host bootstrap** (ADR-0063). ADR-0052 decided the live engine is "self-host
→ JS only"; this **amends** it: there are now *two* engines — the reference interpreter (early, ships
the playground on the scalar corpus) and, later, self-host → JS (the *whole compiler* in the browser).
The same corpus eventually runs on both, a **free cross-check** (does the interpreter agree with
self-host-on-JS?). Ship behind a flag the moment the scalar corpus is green on `:eval` — **do not wait
for feature-complete** (Liam's deadline pressure, addressed honestly).

### 4. Reject P2 — a bytecode VM with its own GC/scheduler **as a runtime/emission target**

Rejected, on the charter, not on taste:
- **ADR-0000** — a VM-as-target *is* the separate Rian runtime the thesis refuses.
- **ADR-0050** — its bytecode is a second IR fork.
- **ADR-0057** — native-per-target concurrency removes the portable scheduler that would justify it.
- **ADR-0058** — it widens the conformance matrix with a target that has no host checker to anchor.
- **ADR-0063** — it competes with the standing #1 priority (self-host).

**Deferred, not forbidden** (Elena's dissent). If a bytecode VM ever lands, the **interpreter-as-oracle
is its precondition** (you cannot conformance-test a VM without an executable spec). So building P1
first is **path-independent** — correct on every branch, including the one where the VM is eventually
built. A future VM enters under the ADR-0049 §5a target budget like any backend, only with a concrete
trigger (§Open items).

### 5. Reject P4 (status quo) and P5 (bytecode interchange)

- **P4 — wait for self-host → JS for the playground.** Rejected: too slow; P1 → WASM ships the
  playground far earlier (§3).
- **P5 — a portable bytecode interchange / AOT artifact.** Out of scope; it is P2-shaped (a second
  artifact to own) and is revisited only *with* P2, under the same trigger.

### 6. Anti-drift gate — the interpreter may not become a shadow dialect (Mira)

`Rian.Eval` may **only execute constructs at least one emitter also supports.** An interpreter-only
feature is forbidden, enforced as a check (Mira owns it), so the oracle can never drift *ahead* of the
emitters into a "shadow language" that passes `:eval` but no real target.

### 7. Scope P1 ruthlessly

Tree-walk on `Rian.Core` only; no bytecode; no GC we write; **sequential-only** (ADR-0057). Honour the
evaluation order the spec already fixes (ADR-0035 ordering, ADR-0064 integer wrap, `case`
fall-through). Resist every "while we're here, let's also…" — the value of P1 is that it is *small and
total*.

## Ratings

| Proposal | Verdict | Rating |
|---|---|---|
| **P1** — reference interpreter (`Rian.Eval`), promoted to oracle | **Build now** | 5/5 |
| **P3** — playground engine = P1 → WASM | **Build next** | 4/5 |
| P2 — bytecode VM as a runtime target | Reject (defer) | 2/5 |
| P4 — status quo, wait for self-host → JS | Reject (too slow for the playground) | 2/5 |
| P5 — portable bytecode interchange / AOT artifact | Out of scope; revisit with P2 | 2/5 |

## Key points

- **"rian-vm" was three proposals in one name** — interpreter (a function), runtime VM (a product), and
  playground engine (packaging). Separating them *is* the decision.
- **The charter eliminates P2 directly** — ADR-0000's no-separate-runtime + ADR-0050's no-fork, and
  ADR-0057 removes the portable scheduler a VM would be *for*.
- **The honesty matrix is the swing vote** — a VM widens it with no host checker; the
  interpreter-as-oracle anchors it. Inverting the oracle (de-privileging the BEAM) is what makes P1 a
  net-honesty gain.
- **The embedding case for a VM is weaker than it looks** (Maya) — embedders want *their* runtime,
  which is exactly why ADR-0085 emits their language. Generic embedders are a smaller audience than a
  VM's permanent cost.
- **P1-first is path-independent** — even the deferred VM needs the interpreter as its oracle, so
  nobody loses by building P1 first.

## Consequences

- **The conformance hierarchy inverts.** BEAM stops being the implicit spec; a BEAM/`eval` disagreement
  becomes a BEAM bug. Expect this to surface latent BEAM-backend assumptions (integer wrap, `case`
  fall-through, ADR-0035 ordering) — finding them is the point.
- **The playground ships early** — on P1 → WASM, well before self-host → JS (ADR-0063); later the same
  corpus runs on both, a free cross-check.
- **A risk to watch:** the interpreter drifting *ahead* of the emitters into a shadow dialect — mitigated
  by the §6 anti-drift gate.
- **The debate is recorded** (this ADR), so the P2 rejection and Elena's dissent are not re-litigated
  from zero in six months.

## Open items

- **`:eval` lane wiring** — `eval == emitter` over the portable-core corpus in `Rian.ConformanceTest`;
  decide the value-equality serialization (the ADR-0087 reach-honesty harness already canonicalizes
  BEAM/JS/Rust values to one form — reuse it).
- **Anti-drift check** — the mechanical form of §6 (an `:eval`-supported-construct ⊆ ∪ emitter-supported
  set assertion).
- **Scalar-corpus green bar** — the precise subset whose greenness on `:eval` unlocks the playground
  flag (§3).
- **P2 re-open trigger** (Elena) — a concrete generic-embedding customer, **or** an AOT need Rust/WASM
  cannot meet — and only *after* P1 is the oracle, entering under the §5a target budget.

## Alternatives considered

- **P2 — bytecode VM as a runtime target.** Rejected (§4): contradicts ADR-0000/0050/0057, widens the
  honesty matrix (ADR-0058), competes with self-host (ADR-0063). Deferred-not-forbidden with a trigger.
- **P4 — wait for self-host → JS.** Rejected: the playground would slip behind the `v1==v2` gate for no
  reason once P1 → WASM exists.
- **P5 — bytecode interchange / AOT.** Out of scope; P2-shaped; revisited only with P2.
- **Name it `Rian.Interp` (the debate's suggestion).** Rejected: the name is the interpolation desugar
  (ADR-0069); the reference evaluator is `Rian.Eval`, started fresh (§1).
- **Keep the BEAM as the spec (don't invert the oracle).** Rejected: it leaves the honesty matrix with
  an *implicit*, un-runnable anchor — the very thing P1 fixes.
