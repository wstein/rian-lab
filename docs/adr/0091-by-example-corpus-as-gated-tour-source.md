# ADR-0091 — The by-example corpus is the gated source of the tour

**Status:** Accepted
**Implemented:** yes — `examples/rian/NN_*.rian` carry machine-readable `#@reach` / `#@reach-pin` /
`#@illustrative` headers; `Rian.Tour.Examples` verifies them against the real `Rian.Reach` analysis,
runs their `#=>` doctests on the BEAM, and feeds the corpus into `tour.json` as the `"examples"`
section; `mix rian.tour --check`, `Rian.TourReachTest`, and `Rian.TourDoctestTest` gate it.
**Refines:** ADR-0058 (reachability-gated honesty matrix — the tour's portability claims are now
gated by the same `Rian.Reach`), ADR-0060 (executable spec-by-example — the worked examples are
doctests), ADR-0057 (portability is inferred, native-per-target concurrency).
**Amended 2026-06-22:** the gate now also asserts **emittability** (not just reachability); the six
curated cells became `#@pane`-tagged files so source has one home; their emitter-output assertions
moved to the emitter suites. See "Amendment — converge, not collapse" below.

## Context

The "Rian by example" tour existed as **two unconnected corpora**:

1. `examples/rian/NN_*.rian` — 19 hand-written, comment-rich teaching files.
2. `Rian.Tour`'s six inline `@cells` — minimal source strings that generate the site-consumed
   `site/src/data/tour.json` through the *real* emitters, so the site panes cannot drift.

Only (2) was gated. The hand-written files (1) — including the ones the README calls "the heart of
the language" (capabilities) and the capstone — carried precise factual claims (Rust-lowering
matrices, "evaluates to −20", per-target reachability) that **nothing verified**. They drifted:
"two targets" after four had shipped, a removed `T | E` sugar still advertised, `Int64` taught as the
default after `Int53` had replaced it. A confidently-wrong tutorial is worse than none.

A full merge — making the curated `@cells` *be* the example files — was rejected: the minimal cells
are hand-tuned for the site UI, and the teaching files' value is their prose, which no emitter can
regenerate. The question was how to make the files **inputs to the gated dataset** without losing
either.

## Decision

Keep the prose hand-written; make every **claim of fact** machine-checked.

1. **Machine-readable headers.** Each numbered file declares, in its leading comments, either
   `#@reach <targets>` (the union of target environments its functions reach) plus
   `#@reach-pin name=<targets>` for every function *below* that union, or `#@illustrative <reason>`
   when it uses surface the `Rian.Decl` front-end does not yet accept.
2. **Reach gate.** `Rian.Tour.Examples.check!/0` runs the real `Rian.Reach` analysis and fails the
   build if the computed union drifts from `#@reach`, if a below-union function lacks a pin, if a pin
   is wrong/stale, or if an `#@illustrative` file actually parses (the marker cannot outlive the gap).
3. **Executable worked examples.** `expr #=> expected` doctests (ADR-0060) replace loose
   "evaluates to X" prose; `check_doctests!/0` runs them on the BEAM. Doctest-free files are never
   compiled, so a BEAM-illegal-but-doctest-free file (e.g. `ref` in 04) is untouched.
4. **One gated dataset.** `Rian.Tour.Examples.dataset/0` feeds the corpus into `generate/0` as the
   `"examples"` section of `tour.json` — each file's title, kind, declared reach, the honest
   per-function `reachByFn` matrix, its pins, and its doctests. The files are now *inputs* to the
   published tour; a drift between a file and the site data fails the existing freshness gate
   (`Rian.TourTest` / `mix rian.tour --check`).

The curated `@cells` stay as the site's minimal panes (they exercise the emitters end-to-end, which
the larger files cannot all do). The two corpora now share one gate instead of one being unguarded.

## Consequences

- The tour's portability and worked-example claims cannot rot: a reach regression, a wrong pin, or a
  drifted doctest fails CI.
- An `#@illustrative` file that the front-end learns to parse fails the gate, forcing its promotion to
  a `#@reach` header — the illustrative set shrinks as the parser grows, and cannot silently mislead.
- New per-file maintenance: a new numbered file must carry a header or the gate fails (no silent
  skips). This is the intended forcing function.
- `tour.json` grows by the `"examples"` section; the site may render it but is not required to.

## Alternatives considered

- **Merge the cells into the files (full single-source).** Not done — but see the amendment: the
  curated cells and the teaching files keep *distinct render roles* (minimal all-four panes vs. deep
  prose + honest reach), while their **source ownership** is now unified (cells read from
  `#@pane` files). "Converge, not collapse."
- **Gate by whole-file compilation to all four targets.** Rejected as the *reach* contract: the
  boundary files (capabilities' `ref`, the capstone's FFI `show`) *teach* non-portability; forcing
  four-target compilation would delete that pedagogy. (The amendment adds whole-file *emit* checking
  only on a file's **floor** — the targets every function reaches — which keeps that pedagogy while
  still catching over-claims.)
- **A single union per file with no pins.** Rejected: it hides an `ex`-only helper behind a portable
  sibling's reach. Per-function pins keep mixed files honest.

## Amendment — converge, not collapse (2026-06-22)

A follow-up debate revisited "should the two corpora merge?" with new evidence:

- **The "files break the emitters" rationale was overstated.** 8 of 9 fully-portable example files
  emit cleanly to all three non-Elixir targets; feasibility was never the blocker. The real reasons to
  keep two artifacts are **teaching UX** (a deep file's pane is 1–3 KB of emitted code, hostile on a
  landing page) and **distinct render shapes** (`cells` carry per-target *panes*; `examples` carry
  *reach + doctests*).
- **Reachability ≠ emittability.** `Rian.Reach` is an over-approximation (no full `Check`), so a file
  could claim a target the compiler then refuses. `02` did exactly this (`flip`'s `range Bit` return
  fails the checker on ex/js/jvm); `04` claimed `rs` but never declared `type Shape`, so only Rust
  failed. Both were shipped over-claims the reach-only gate missed.

**Decisions taken:**

1. **Gate emittability on the floor.** `check!/0` now runs the real emitter for every target *every*
   function reaches (the floor) and fails if it raises. `02`/`04` were fixed to be genuinely
   all-target-emittable.
2. **Decouple the cells' hidden role.** The specific emitted-output assertions (`fn area(s: &Shape)`,
   the JVM guard form) moved from `Rian.TourTest` to `Rian.LowerTest`/`Rian.JVMTest`; the tour tests
   tour data, the emitter suites test emitters.
3. **Unify source ownership.** The six inline cell sources became `#@pane`-tagged files under
   `examples/rian/panes/`, gated minimal (`check_panes!/0`: ≤15 lines, emits to all four). `Rian.Tour`
   reads them; `tour.json` is byte-identical.

**Not done (parked):** a literal single corpus (one file serving both the minimal pane and the deep
tour). Revisit if the site grows collapsible/lazy panes, which would remove the teaching-UX objection.

**Live cells emit labeled tagged-object sums.** The by-example cells (and the playground) now show a
sum variant as a tagged object with its declared field names — `Circle(radius Float64)` →
`{ $: "Circle", radius: r }` (an anonymous field falls back to `_n`), not a tagged array. The
live bundle (purs `JS.purs`) is parity-locked to the Elixir reference, so the static `tour.json`
panes and the live-recompiled panes agree. The JS-value-representation decision and its rejected
hybrid alternative are recorded in **ADR-0049 §3b**.
