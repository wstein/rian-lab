# ADR-0087 — Generative reach-honesty harness: prove the matrix, don't assert it

**Status:** Proposed (direction) — this ADR **locks the invariant** (§1); the generator, shrinking, and
per-target conformance lanes (§2–§4) are stated as direction and remain Open Items until built.
**Implemented:** no. The honesty mechanism today is fixture-based (`reach_rust_honesty_test` and
siblings over a hand-curated corpus); this ADR replaces the *gate* with a generative property and keeps
the fixtures as named regression cases.
**Refines:** ADR-0000 (honesty bar — supplies the precise, machine-checkable definition of "verified":
a generative property, not a curated corpus), ADR-0058 (reachability + CI parity — the property is what
the parity lane must satisfy per target).
**Refs:** ADR-0050 (typed Core IR — the space the generator samples), ADR-0064 (portable numeric
contract — the densest existing pin surface, the generator's first target), ADR-0070 (`val` default
capability — capability inference is in scope), ADR-0061 §5 (coherence — the first *non-reach* invariant
this harness gates, its 2026-06-21 amendment), ADR-0086 (competitive strategy — §2 delegates the
load-bearing mechanism here; §3's depth-before-breadth gate is *this* property going green), ADR-0049
§5a (target admission gate — sharpened from "conformance corpus" to "conformance property").
**Owners:** Kira Neri (reach honesty / CI parity — overall) · Samir Patel (generative testing /
shrinking) · Elena Rostova (numeric-lattice + reach pins) · Maya Lin (emitter conformance lanes) ·
Arthur Pendelton (coherence as a harness consumer) · Rachel Okafor (PM)

## Context

Rian's single defensible claim (ADR-0086 §1) is *honest, inferred* target reach: the `Rian.Reach`
matrix says which targets a function reaches, and — unlike Haxe's compile-and-pray — refuses to claim
one it cannot deliver. The entire moat rests on that matrix being **true**.

Today it is true *by selection bias*. `reach_rust_honesty_test` and its siblings (`rustc --test`,
`node`, `kotlinc`) check that a **hand-picked corpus** agrees with the matrix. CLAUDE.md is candid that
"much of [`test.all`] runs on hand-built source strings / a toy corpus," and this project has already
caught itself once with a suite that was "green by selection bias, NOT parity." A curated corpus proves
the matrix honest *on the programs someone thought to write* — it cannot prove honesty on the program
nobody thought of, which is exactly where an **unmodeled blocker** hides.

`Rian.Reach` is, mechanically, a call-graph walk that pins a function off a target when it hits a known
blocker: a wide-int overflow prim off `:js`, a `ref` param off `:ex`, host FFI off everything portable,
a non-bootstrapping parametric type off `:rs` (the `emittable_map` fixpoint). The fixpoint is a real
lattice computation, but the **prim/blocker set is a hand-maintained enumeration**. Add a Core
construct, forget to add its blocker rule, and the matrix lies — silently, in the one place we sell.
The only thing that catches that is a check which does **not depend on a human having written the
fixture.** That is this ADR.

## Decision

### 1. The locked invariant — what "honest reach" *means* (this is the decision)

For every program `p` expressible in the Core IR (ADR-0050) and every target `t`:

> **Soundness (no over-claim):** if `Rian.Reach` claims `p` reaches `t`, then the emitter for `t`
> produces output that the real `t` toolchain compiles **and** runs. A toolchain rejection of a
> reach-claimed program is a **P0 honesty bug** — never downgraded to "known limitation."
>
> **No silent under-claim:** if `Rian.Reach` pins `p` off `t`, that pin must carry a *modeled reason*
> (a named blocker), not an unexplained refusal. An honest under-claim (conservative pin with a reason)
> is allowed; an *unexplained* one is a bug to be turned into either a reach or a named blocker.

This invariant is the load-bearing definition the rest of the harness serves; it is decidable and
locked now. The over-claim half is the safety property (the moat's truth); the under-claim half keeps
the matrix from quietly shrinking to "nothing reaches anything," which would be vacuously sound.

### 2. The mechanism — a generative property, fixtures demoted to regression (direction)

A property-based generator samples the Core IR — sums, structs, generics + bounds, `Fn` closures, the
numeric-width lattice (ADR-0064), capabilities (ADR-0070), protocols/impls (ADR-0061) — and for each
sample drives **both** the `Rian.Reach` verdict **and** the real backend (`rustc`/`node`/`kotlinc`/BEAM
`:compile.forms` load), asserting they **agree** under §1. A disagreement fails the property with the
offending program. The existing curated tests stay as **named regression cases** (fast, deterministic,
documenting specific historical bugs); the **gate** — what ADR-0086 §3 and ADR-0049 §5a require green
before a target or a portable-surface widening lands — becomes the property, not the corpus.

### 3. Generated programs must be *runnable*, not just *type-correct* (direction)

A generator that emits ill-typed or non-terminating Core proves nothing — the toolchain would reject it
for reasons unrelated to reach. The generator produces **well-typed, total, terminating** Core (it is a
*valid-program* generator, the hard part), so a toolchain rejection is unambiguously a reach lie and
not a generator artifact. This is the cost that makes the property meaningful.

### 4. Failures must shrink to a minimal reproducer (direction)

A 200-node generated counterexample is not actionable. The harness **shrinks** a failing program to a
minimal Core fragment that still violates §1 — structurally, and **capability/type-preserving** (a
shrink step must not turn a valid program invalid, or it re-introduces §3's ambiguity). The shrunk
reproducer is what gets filed as the P0 and, once fixed, frozen as a regression fixture.

### 5. The harness gates coherence too, not only reach (direction)

The same machine generalizes beyond reach: ADR-0061 §5's coherence rules (one-impl-per-`(proto,type)`,
orphan, runtime-discriminator, overlap) are *also* an invariant a curated corpus under-tests. A
generated program whose `@targets` make it incoherent **must be rejected by `Rian.Check`**; a coherent
one **must lower legally on every declared target**. Coherence is the first non-reach consumer and the
proof the harness is a general honesty engine, not a reach one-off (ADR-0061 §5 *Amendment*).

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — lock the over-claim/under-claim invariant as the definition of honest reach | 5/5 | the one thing decidable now; everything else serves it |
| 2 — generative property as the gate; fixtures demoted to regression | 5/5 | only mechanism that catches an *unmodeled* blocker |
| 3 — generate well-typed/total/terminating Core | 4/5 | essential for a meaningful property; −1 it is the hardest piece to build |
| 4 — capability-preserving shrinking | 4/5 | turns a failure into a fix; −1 shrinking typed IR soundly is non-trivial |
| 5 — gate coherence with the same harness | 4/5 | high reuse, validates generality; −1 it widens scope before reach itself is green |

## Consequences

- **The moat becomes provable.** "Honest reach" stops being a claim backed by the programs we happened
  to test and becomes one backed by a property over arbitrary valid programs — the discipline Haxe/Fable
  never imposed, and plausibly a publishable artifact ("keeping a multi-target capability matrix
  honest").
- **Adding a target gets a hard, mechanical gate** (ADR-0086 §3 / ADR-0049 §5a): a candidate's column is
  "green" only when the property passes for it, not when a corpus does. Swift/Python/Lua-PHP-Neko
  (ADR-0071/0072/0085) inherit this bar.
- **An unmodeled blocker becomes a test failure, not a shipped lie** — the failure mode that motivated
  the ADR is now caught pre-merge.
- **A new cost center:** a valid-Core generator + sound shrinker is real engineering, and the property
  is slower than fixtures, so it runs in the full/`test.all` lane (the toolchain lane), not the inner
  loop — consistent with how `:rust`/`:jvm` tests are already excluded from `mix test`.
- **The fixtures don't die** — they stay as fast, named regression cases; only their *role* changes from
  "the proof" to "documented examples + speed."

## Open items

- **Generator substrate.** StreamData (already an Elixir dep surface) vs. a bespoke Core generator vs.
  a typed-term enumerator (à la `Coq`/`QuickChick` style). Lean: a Core-aware generator that builds
  *outward from a target type* so well-typedness (§3) is structural, not rejection-sampled.
- **Coverage order.** Which Core region first — start at the **numeric-width lattice** (ADR-0064, the
  densest blocker surface and the source of past over-claims) and **`Fn`-closure reach** (the most
  recently closed `:rs` gaps, ADR-0061 open items), where regressions are most likely.
- **Termination guarantee.** How the generator guarantees totality/termination (§3) without crippling
  the sample space — bounded recursion depth, structural-recursion-only, or a fuel parameter.
- **Shrinking strategy.** Capability/type-preserving shrink moves for Core (§4); whether to reuse a
  generic shrinker or hand-write type-directed reductions.
- **BEAM "runs" oracle.** `:compile.forms` proves *load*, not *behavior*; decide whether the BEAM lane
  asserts compile-and-load or also executes (the latter needs a generated entry point + expected value).
- **Property runtime budget.** Samples-per-target-per-CI-run, and whether nightly runs a deeper sweep
  than per-PR (the standard QuickCheck-in-CI tradeoff).
- **Determinism / seed reporting.** A failing run must print a reproducing seed (CLAUDE.md forbids
  `Math.random()`-style nondeterminism in some surfaces; the harness must surface its seed regardless).

## Alternatives considered

- **Keep the curated corpus, add more fixtures.** Rejected — more fixtures is more of the same
  selection bias; the moat is precisely the claim a fixture cannot prove (the program nobody wrote).
- **Leave the mechanism inside ADR-0086 §2.** Rejected — ADR-0086 is a *strategy* decision-lock meant to
  stop changing once accepted; the harness will churn (generator, shrinker, per-target lanes), and that
  churn belongs in its own ADR (the ADR-0061 precedent: a mechanism ADR absorbs iterative `DONE` edits).
  If this ADR never grows past §1, fold it back.
- **Make `Rian.Reach` a sound effect-type system now (Koka-style rows), skipping the harness.** Rejected
  *for now* (ADR-0086 §8) — that is a research bet; the generative property is the pragmatic bridge that
  keeps the *current* heuristic honest until the type-theoretic version is justified. The two are
  complementary: a sound system would *reduce* what the harness must catch, not replace the need to
  check the emitters agree with it.
- **Property over surface `.rian` source instead of Core IR.** Rejected — generating valid *surface*
  syntax adds parser-shaped noise unrelated to reach; Core (ADR-0050) is the typed spine every gate and
  emitter already consumes, so it is the honest sampling space.
