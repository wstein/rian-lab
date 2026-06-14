# ADR-0070 — `val` is the inferred default capability; annotate only `iso`/`ref`/`tag`

**Status:** Accepted · **implemented** (a bare parameter parses as `val`; explicit `iso`/`ref`/`tag` stay spelled)
**Implemented:** yes — `Rian.Decl.param/1` defaults a capability-less parameter to `:val` (`def f(x Int64)` ≡ `def f(x val Int64)`); explicit `val` still parses (redundant, allowed); `iso`/`ref`/`tag` remain explicit. Tests: `test/rian/decl_test.exs` (params assert `cap: :val`). Pure parse-time default — checker/Reach/emitters see the same capability as before.
**Refs:** ADR-0025 (the capability model this relaxes), ADR-0055 (capabilities through dispatch — receiver capabilities unaffected), ADR-0035 (no hidden behaviour — `val` is the *read-only* default, the safe one), ADR-0065 (surface — an additive ergonomic change), ADR-0000 (charter — keep the distinctive capability model, cut its tax)
**Owners:** Elena Rostova (Rust/DX) · Arthur Pendelton (soundness — co-signs) · Chloe Bennett (ergonomics) · Maya Lin (multi-target) · Kira Neri (no hidden behaviour) · Rachel Okafor (PM)
**Origin:** the Gleam/Haxe borrow debate (2026-06-14, consensus #5, 4/5) and the corpus-review debate (capabilities are a surface tax most targets ignore).

## Context

Today **every** parameter carries an explicit capability (`val`/`iso`/`ref`/`tag`, ADR-0025) — e.g.
`def area(shape val Shape) Float64`. That is a cognitive tax on *every signature*, and three of four
targets (JS/JVM, and the BEAM for the common read-only case) derive **no benefit** from the most
common annotation, `val`: on JS `ref` is even a documented no-op (value-lowered). For a language whose
pitch is "share sequential logic across targets" (ADR-0000), the universal surface front-loads one
target's (Rust's) concern.

The debate's resolution: **keep the capability model (it is load-bearing for Rust soundness and BEAM
linearity — ADR-0025) but stop making the 90% case pay for it at the surface.**

## Decision

1. **A bare parameter defaults to `val`.** `def f(x Int64)` means `def f(x val Int64)`. `val` is the
   read-only, shared, reusable capability — the safe default, so defaulting to it can never *grant*
   ownership or mutation that wasn't requested (ADR-0035: the default is the least-powerful one).
2. **Annotate only when you mean more than `val`** — `iso` (owned/linear), `ref` (`&mut`, BEAM-illegal),
   `tag` (by-reference tag) stay explicit. These are exactly the *load-bearing* annotations Rust
   soundness and BEAM use-once depend on, so nothing sound is lost by inferring only `val`.
3. **No behaviour change, only surface.** Inference of `val` is purely the parse-time default; the
   checker, Reach, and every emitter see the same capability they do today.

## Rationale

- **Cuts the most common annotation entirely** — a beginner's first functions lose all capability
  noise, directly improving onboarding (the corpus-review DX finding).
- **Preserves the novel model** (ADR-0000 §4): the annotations that *matter* (`iso`/`ref`) are still
  spelled, so ownership-checked Rust + BEAM linearity are unaffected.
- **Defaulting to the least-powerful capability is the safe direction** (ADR-0035) — the opposite
  default (`iso`) would silently grant ownership.

## Consequences

- `Rian.Decl` treats a param with no capability keyword as `val`; the existing explicit `val` keeps
  working (redundant but allowed) so no source breaks.
- Examples/tour and `docs/` lose most `val` noise — fold into the "Rian in 10 minutes" surface guide.
- The surface freeze (ADR-0065) is satisfied: this is *additive/relaxing* (fewer required tokens), not
  a change to existing token meanings.

## Open items

- **Should `tag` also be inferable?** Unresolved in the debate. `tag` is read-only-by-reference; in
  some positions it may be derivable from usage rather than annotated. Deferred — `val`-default first,
  measure, then revisit `tag`.
- **Interaction with `@external`** (ADR-0068): external params are already restricted to `val`/`tag`;
  the `val` default applies there unchanged.
