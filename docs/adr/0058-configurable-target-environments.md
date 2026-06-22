# ADR-0058 — Configurable target environments; reachability-gated portability

**Status:** Accepted (direction) · **partially implemented** (the reachability analysis, the `mix rian.targets --require` gate, **and the in-source `@targets(…)` module annotation + its compile-time contract gate** — `Rian.Reach.gate!/1`, enforced in `Decl.compile`/`compile_beam` and `Beam.compile`/`compile_program` — are shipped; **the build default is shipped too** — `Rian.Reach.build_default/0` reads the `:rian_lab` app env `:rian_targets` (else `mix.exs` `rian: [targets: […]]`), and a module with no `@targets` falls back to it, so an unannotated module is gated by the build's required set. Fully implemented)
**Implemented:** yes — `Rian.Reach` (`targets/0` → `[:ex, :rs, :js, :jvm]`, `gate!/1`, `build_default/0`), `IR.Mod.targets` from the `@targets(…)` annotation, and `Mix.Tasks.Rian.Targets` (`test/rian/reach_test.exs`, `test/rian/reach_rust_honesty_test.exs`)
**Refs:** ADR-0031 (sequential-core boundary), ADR-0041 §2 (unmapped BEAM call = compile error, never a silent stub), ADR-0047 (portable prelude `__prim_*`), ADR-0048 (effect tracking — the lattice this generalizes to), ADR-0049 (backend target roadmap / tiers), ADR-0057 (concurrency & OTP are native-per-target)
**Owners:** Maya Lin (emitters/build) · Samir Patel (gate rigor) · Kira Neri (honesty/determinism) · Arthur Pendelton (analysis lattice) · Elena Rostova (interop seam) · Liam Davis (ergonomics) · Rachel Okafor (PM)

## Context

ADR-0057 says Rian source is **portable sequential logic** and concurrency is **native-per-target**.
But the recon for this decision found the principle was **documentation, not enforcement**: the type
checker has no notion of target reachability, and raw host FFI is unrestricted — `:erlang.spawn(…)`
**compiles green on the BEAM** and is only caught if the same code happens to be lowered to Rust
(`lower.ex:870` raises). So "portable" was discovered by accident, not checked.

The owner's steer rejected a *binary* portable-vs-BEAM flag (a `@shared` marker): **portability is
not one bit, it is a configurable *set of target environments*, selected by need** — a library for
hex + npm + crates needs `[ex, rs, js]`; an internal service needs `[ex]`; a web bundle needs
`[js]`. The constraints (what FFI is allowed) follow from *which targets you picked*.

## Decision

### 1. Closed, emitter-backed target vocabulary

`:ex` (Elixir/BEAM), `:rs` (Rust), `:js` (ECMAScript) — the ADR-0049 Tier-1 emitters — and **`:jvm`
(Kotlin/JVM, ADR-0049 Tier 2; emitter landed 2026-06-13, `Rian.JVM`).** A token with
no emitter (`:wasm`, `:go`) is a **compile error**, never a silent no-op — the vocabulary
grows only when an emitter lands (Kira: no over-claims in the type system itself). The vocabulary
just grew, exactly as designed: `Rian.Reach.targets/0` now returns `[:ex, :rs, :js, :jvm]`, so
`@targets(… jvm)` is a valid contract and `mix rian.targets` reports a JVM column. (Reach stays
coarse — it gates on host-FFI/concurrency pinning, not emitter coverage — so a `:jvm`-reachable
function may still hit a `Rian.JVM.Unsupported` for a construct the Tier-2 emitter has not lowered
yet, the same partial-emitter posture `:js` carried while it grew.)

### 2. The required set is configurable, at three levels

- **CLI (shipped):** `mix rian.targets FILE --require ex,rs,js` — the listed targets become a
  required set; the task exits non-zero on any function that cannot reach all of them.
- **Module promise (shipped):** `@targets(ex, rs, js)` on a `mod` — a hard contract for *every `pub`
  function* in that module, any subset of the vocabulary. The unit that *is* portable says so, so a
  library author gets feedback without a downstream build flipping a flag (Samir). Parsed onto
  `IR.Mod.targets`; gated by `Rian.Reach.gate!/1` at compile time (a `pub` function failing to reach
  a declared target is a `Rian.Reach.Error`). A module with no annotation is not gated.
- **Build default (shipped):** `mix.exs` `rian: [targets: […]]` (or the `:rian_lab` app env
  `:rian_targets`) — supplies the required set for modules that don't declare one
  (`Rian.Reach.build_default/0`).

**Checking vs emitting are separated (Kira's rule):** the **declared set is what gets *checked***
(the promise); the **build set is what gets *emitted*** (the deployment). A module promising `:rs` is
*checked* for `:rs` even on an `:ex`-only build; it just isn't *emitted* there. Checking reachability
is not running the emitter, so this is cheap and the promise cannot be silently un-made by a build.

**No declaration ⇒ no gate** (Liam): an unannotated module with no build default is pure analysis
(`mix rian.targets` on demand), never a nag — constraints are *selected by need*, including the need
for none while prototyping.

### 3. Reachability is computed, not attempted — `Rian.Reach`

Per function, `reach ⊆ {:ex, :rs, :js}` is computed by classifying *constructs* and propagating along
the local call graph (the error-set fixpoint of `Rian.Check`, relabeled):

- **`ex`-only constructs:** host FFI — an Erlang remote call `:mod.fun(…)`, or an `Mod.fun(…)` call
  to a module that is **not** a Rian module in the program. This subsumes **all
  concurrency/process/state FFI** (`:erlang.spawn`, `GenServer`, `Task`, `Process`, `:ets`, …),
  flagged `kind: :concurrency` — native-per-target by design (ADR-0057), so never portable.
- **portable constructs:** the core language + the `__prim_*` portable prelude (ADR-0047) + Rian
  cross-module calls → all targets.
- **propagation:** `reach(f) = local(f) ∩ ⋂ reach(callee)` — a portable-looking caller inherits a
  callee's `ex`-only pin.

The lattice is `{:ex, :rs, :js}` today and is **structured to relabel to effects** (ADR-0048): same
fixpoint, richer labels — so reachability, effects, and eventually capability all become one
propagation engine (Arthur), not three special cases. **Concurrency is not special-cased**; it falls
out as one family of `ex`-only constructs.

### 4. The gate

For each `pub` function, `required ⊆ reach(f)` or **compile error** naming the blocking construct and
the targets it kills. This is the same machine as ADR-0041 §2's "unmapped = error," moved **before**
lowering and made *honest per declared target* instead of discovered at emit time.

## Rationale

- **Configurable-by-need beats one bit:** the same analysis serves a tri-target library, a BEAM-only
  service, and a web bundle — you declare the set, the constraints follow. A binary `@shared` couldn't
  express "this is `[rs, js]` but never `ex`."
- **Computed, not attempted:** the team explicitly rejected the attempt-and-fail model (portability
  found only by trying to lower); a classifier gives per-function results, good diagnostics, and a
  pre-lowering gate.
- **Honesty:** `mix rian.targets` turns "we claim this runs on node" into a checkable fact — directly
  fixing the README over-claims the recon surfaced.

## Ratings

| Decision | Rating |
|---|---|
| Configurable target-environment set (not a binary `@shared` flag) | 5/5 |
| Closed, emitter-backed vocabulary; unknown target = error | 5/5 |
| Computed reachability via call-graph fixpoint (relabelable to effects) | 5/5 |
| Check-the-promise / emit-the-build separation | 4/5 |
| No declaration ⇒ analysis only, no gate | 4/5 |
| Concurrency-FFI as a fallout, not a special case | 5/5 |
| Binary `@shared` portable/BEAM-only flag | 1/5 (superseded — can't express target subsets) |
| Attempt-and-fail portability discovery (status quo) | 2/5 (no pre-check, accidental coverage) |

## Consequences

- **Shipped:** `Rian.Reach` (`lib/rian/reach.ex`) + `mix rian.targets [--require …]`
  (`lib/mix/tasks/rian.targets.ex`), with tests. The concurrency-FFI lint is the report's blocker
  note / the `--require` gate.
- **Open — in-source `@targets(…)`:** extend the annotation parser (`decl.ex:255`, today only
  `@doc`/`@moduledoc`/`@typedoc`) and add the gate at `decl.ex:229` between `Check.gate!` and lowering.
- **Open — build default:** read `rian: [targets: …]` from `mix.exs` config.
- **Supersedes the dormant `@shared` idea** floated in the prior debate.
- **Honesty pass:** reconcile `examples/rian/README.md` multi-target claims with
  `mix rian.targets` output.

### CI default scope (2026-06-13 design review)

A review asked for the `--require` gate to be **opt-out** (on by default everywhere). We **scoped it**
instead: a blanket default-on gate would flag every concurrency/FFI-adjacent function as a "failure",
but those are `:ex`-only *by design* (ADR-0057) — correct code, not a portability bug. So CI gates
**default-on for the shared core** (`examples/rian/prelude_*.rian`, and any `@targets`-declared module
— a declared promise must hold) and **opt-in for BEAM-pinned application code**. Writing unportable
code stays an intentional, documented act (omit the `@targets` annotation) instead of the gate crying
wolf over code never meant to be portable. Wired in `.github/workflows/ci.yml` as a
`mix rian.targets --require ex,rs,js` step over the prelude files (all green as of this change).

## Open items

- **Cross-module reach threading:** v1 treats a Rian `OtherMod.fun(…)` call as portable rather than
  threading the callee's reach (under-approximates a blocker hidden behind a sibling module). Promote
  to a whole-program call graph when multi-module portability matters.
- **Atom-literal classification:** bare atoms are unclassified in v1 (Symbol/Result tags, portable per
  ADR-0041); revisit if a non-tag atom literal needs `ex`-only treatment to match the Rust emitter.
- **Clause-head pattern scanning:** FFI lives in bodies/guards today; scan patterns if atom patterns
  become reachable.
- **Effect unification (ADR-0048):** fold the `{:ex,:rs,:js}` lattice into the effect lattice when the
  effect checker lands, so there is one propagation engine.
