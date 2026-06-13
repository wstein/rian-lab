# ADR-0056 — `comptime if target`: the proven-equivalent target conditional

**Status:** **Proposed (draft) — motivation thin; likely dormant.** Not accepted. The 2026-06-13 goal clarification (Rian shares *sequential logic + tests*; **concurrency is native-per-target**, ADR-0031) removed this ADR's primary motivation — the OTP/concurrency "fracture" is no longer a Rian-source problem at all. What remains is a narrow sequential-representation niche the portable prelude (ADR-0047) already mostly covers. Kept on record as the disciplined alternative to an undisciplined `@target_fallback`; **do not implement** unless a concrete sequential-only need appears.
**Refs:** ADR-0030 (pure `comptime` / monomorphization), ADR-0031 (bootstrap; non-BEAM = sequential core — the lock this touches), ADR-0035 (no hidden control flow), ADR-0041 §2 (unmapped BEAM call = compile error, never a silent stub) / §4 (std-mapping), ADR-0044 §4 (OTP behaviour on non-BEAM = compile error), ADR-0046 §2 (compile-time specialization is idiomatic-per-target), ADR-0047 (portable prelude tiers), ADR-0050 (typed core IR)
**Owners:** Maya Lin (multi-target / ecosystem fracture) · Samir Patel (no-silent-stub guard) · Elena Rostova (selection/lowering) · Arthur Pendelton (equivalence checking) · Kira Neri (determinism) · Marcus Chen (transparency) · Rachel Okafor (PM)

## Context

> **Goal-clarification update (2026-06-13).** Rian's purpose is to **share sequential application
> logic and tests** across targets (the lexer/parser running on BEAM/Rust/JS is the proof), and
> **concurrency is native-per-target by design** (ADR-0031) — OTP on the BEAM, async/threads in
> Rust, Promises/workers in JS. This **removes this ADR's original motivation**: the
> `gen_server`-vs-`struct` "fracture" never was a Rian-source problem, because concurrency-flavoured
> code is **not shared Rian** — you write the pure logic once in Rian and call it from a native
> gen_server / task / worker. The Context below is preserved for the record, but its OTP framing is
> superseded; the only residual niche is §1's sequential-representation tail.

Today every BEAM-flavoured line makes its module BEAM-only: the emitters hard-fail late on an
unmapped BEAM call (ADR-0041 §2) or an OTP behaviour on a non-BEAM target (ADR-0044 §4). That
failure is **correct and deliberate** — a silent semantic substitution (swap a supervised
`gen_server` for a plain struct and compile green) is exactly the correctness/security-grade bug
ADR-0041 §2 forbids. The original worry was that "correct and unusable" pushes authors to **fork into
`_beam.rian` / `_rust.rian`**. The goal clarification above largely dissolves that worry for the
concurrency cases (they aren't shared Rian source); what is left is genuinely target-specific
**sequential** code (a native scalar formatter, a native regex engine) that the portable-prelude
tiers (ADR-0047) don't reach.

The team debate (2026-06-13) rated a target conditional **3/5 — merit, needs an ADR, not a sprint**:
worth specifying so the *idea* has a disciplined home, explicitly **not** a silent-fallback macro.
This ADR is that home. It is **Proposed**, not Accepted.

The nearest precedent is already accepted: **ADR-0046 §2** ("compile-time specialization is
idiomatic-per-target — one program, each target specializes as far as its idiom allows") and
**ADR-0041 §1** (target-conditioned *representation*). `comptime if target` turns that
compiler-automatic selection into an **author-directed** one — under the same no-silent-stub
discipline.

## Decision (proposed)

### 1. The construct

```elixir
# A *sequential* representation tail the portable prelude doesn't reach: pick the
# target-native scalar formatter, same observable String on every backend.
def format_f64(x Float64) String :=
  comptime if target == :rust do
    __prim_rust_ryu(x)        # Rust: ryu, shortest round-trip
  else
    __prim_dtoa(x)            # BEAM/JS: their native shortest-float
  end
```

> **Not for concurrency.** This is *not* the `gen_server`-vs-`struct` case — that is **not** shared
> Rian source at all (see Context). Both branches here produce the **same `String`**; the construct
> only selects the idiomatic *sequential* implementation.

`target` is a **compile-time atom** (`:beam` / `:rust` / `:js` / …). `comptime if target` is a
compile-time branch evaluated **per target during lowering**: the unselected branch is not emitted.
Unlike the existing expression-level `comptime` folding (ADR-0030 — pure, runs pre-typecheck on the
untyped AST, no `target` binding), this is a **typed-core-IR construct (ADR-0050)**: both branches
are **type-checked** before selection. It is the typed pipeline's job, not the untyped comptime
sandbox's.

### 2. The no-silent-stub guardrails (the price of admission)

A `comptime if target` is **rejected at compile time** unless it satisfies one of:

- **(a) Proven-equivalent.** Both branches type-check against the **same** signature, and the checker
  proves type-equivalence (same return type, same error set, same effect set — ADR-0048). The
  selection is then a pure representation/performance choice, identical in kind to ADR-0046 §2
  automatic specialization. *Observable behaviour is identical; only the machine differs.*
- **(b) Type-visible difference.** If the branches differ observably, the difference must appear in
  the function's **declared type/effect signature**, so every caller sees it (ADR-0035 — what you
  read is what runs). A difference that is *not* representable in the signature is **not** admissible
  under (b); it must reach (a) or be rejected.

And in **all** cases:

- **(c) An unavailable capability is still a hard error.** If a branch uses something with no legal
  form on its target — an OTP behaviour selected on a non-BEAM target (ADR-0044 §4), an unmapped
  BEAM-stdlib call (ADR-0041 §2) — the construct does **not** rescue it. `comptime if target` is a
  **selector among legal implementations**, never a wrapper that legalises an illegal branch. The
  per-target branch is compiled as if written directly; its illegality is reported as if written
  directly.

### 3. Relationship to the ADR-0031 sequential-core boundary

- **The sequential-core boundary is untouched and not reopened.** `comptime if target` is **not** a
  concurrency tool: it cannot synthesize concurrency on Rust/JS, and it has no business expressing the
  `gen_server`-vs-`struct` split — concurrency is **native-per-target by design** (ADR-0031, clarified
  2026-06-13), so that split lives in native host code, never in shared Rian source.
- **Scope is sequential-only.** Both branches must compute the **same sequential result** (guardrail
  (a)) or surface their difference in the signature (guardrail (b)). The construct selects an
  idiomatic *sequential* implementation; it never changes the concurrency or effect story.

This keeps the debate's consensus line — **"proven-equivalent, or type-visible difference, else hard
error"** — while staying entirely inside the sequential core. Because concurrency is native, the
"forced file-forking" this was meant to relieve barely arises; the residual sequential niche is what,
if anything, would justify implementing it.

## Rationale

- It gives the *idea* a disciplined home instead of letting it recur as an undisciplined
  `@target_fallback` request (which the review rejected 1/5 — silent gen_server→struct swap violates
  ADR-0041 §2 / ADR-0044 §4).
- It rides the **already-accepted** ADR-0046 §2 / ADR-0041 §1 precedent (target-conditioned
  specialization/representation), only moving the steering wheel from the compiler to the author —
  with the same guardrails, so it adds no new soundness surface.
- Guardrail (a)'s equivalence check is the load-bearing part: without it the construct *is* the
  silent-stub bug. With it, an admissible `comptime if target` is — by construction — invisible to
  every caller, exactly like the overflow-op or `Symbol`-representation per-target choices already
  shipped.
- Its *residual* value is the irreducibly target-specific **sequential** tail: the portable prelude
  (ADR-0047) handles the common surface, concurrency is native-per-target (ADR-0031), and what is
  left — a native scalar formatter, a native regex — is small. That smallness is precisely why this
  stays **Proposed/dormant**: the disciplined design exists if needed, but the problem it solves is
  now minor.

## Ratings

| Decision | Rating |
|---|---|
| `comptime if target` as an author-directed extension of ADR-0046 §2 specialization | 3/5 (merit; motivation thinned by native-per-target concurrency) |
| Guardrail (a) proven-equivalent — selection invisible to callers | 4/5 |
| Guardrail (b) type-visible difference in the signature | 4/5 |
| Guardrail (c) unavailable capability is still a hard error (not legalised) | 5/5 |
| Sequential-core lock preserved (no synthesized concurrency on non-BEAM) | 5/5 |
| Silent `@target_fallback` (gen_server → struct, green build) | 1/5 (rejected — the bug this prevents) |
| Lifting the sequential-core lock to allow OTP on non-BEAM | 1/5 (rejected — out of scope; ADR-0031 stands) |

## Consequences (if accepted)

- **No decision-lock amendment needed:** the sequential-core boundary stays intact (concurrency is
  native-per-target); this construct lives entirely inside the sequential core, so it does not touch
  ADR-0031's 2026-06-12 lock.
- **Typed core IR (ADR-0050):** a `CTargetIf` node with both branches typed; emitters select per
  target during lowering. **Not** the untyped pre-typecheck `comptime` path.
- **Checker:** the (a) type/effect-equivalence proof; the (b) signature-visibility rule; (c) reuses
  the existing per-target legality checks (ADR-0041 §2, ADR-0044 §4) applied to the selected branch.
- **Determinism (Kira):** selection is a pure function of `target`; the build stays reproducible, the
  unselected branch is dead-stripped.
- **Pairs with ADR-0047:** prelude tiers remain the *first* answer (shrink the target-specific tail);
  this is the escape hatch for what tiers cannot reach.

## Open items

- **Equivalence proof strength (a):** how far the checker proves observable equivalence vs. relies on
  the shared signature + author tests. Likely: signature + effect-set equality is enforced; deeper
  behavioural equivalence is the author's asserted contract (as with any two function clauses).
- **`target` granularity:** atom equality (`:beam`) only, or capability predicates
  (`comptime if has_otp`)? Start with the closed atom set (ADR-0049 tiers); predicates deferred.
- **Interaction with effect inference (ADR-0048):** whether a branch's effects must match (a) or may
  be unioned and surfaced under (b).
- **Whether this stays `comptime if` or gets a distinct keyword** (`target_match`?) to avoid confusion
  with the untyped expression-level `comptime` (ADR-0030).
