# ADR-0060 — Testing strategy: executable spec-by-example, value-returning assertions; Gherkin rejected

**Status:** Accepted (direction) · **tier B doctest runner shipped (MVP)** — `Rian.Doctest` executes `expr #=> expected` examples in `@doc` heredocs on the BEAM (both sides real Rian; a drifted example fails the build), with `Rian.Doctest.exunit/1` surfacing each as an ExUnit case; **tier C shipped** — boolean assertion macros (`assert`/`refute`/`assert_eq`/`assert_neq`) **and** the value-returning matcher DSL with formatted diagnostics (`expect_eq`/`expect_neq`/`expect_true`/`expect_false` → `Outcome := Pass | Fail(String)`), both hygienic Rian macros in `examples/rian/prelude_test.rian`, injected by `Rian.Test` and lowering to all three targets; only `contain` (membership) stays deferred (needs the `List` prelude linked) and `describe`/`it` grouping is not a macro (§4); the property/fixpoint tier is **partly shipped** (`Rian.Fixpoint`, the exhaustiveness gate)
**Implemented:** partial — doctest runner + fixpoint tier + the full assertion/matcher vocabulary shipped (`Rian.Doctest`, `Rian.Fixpoint`, `examples/rian/prelude_test.rian`; `test/rian/doctest_test.exs`, `test/rian/fixpoint_test.exs`, `test/rian/rian_native_test.exs`); `contain` + `describe`/`it` grouping deferred
**Refs:** ADR-0035 (no hidden control flow — errors are values; assertions return outcomes, never throw), ADR-0032 (one surface family — no second grammar), ADR-0030 (declarative/hygienic macros — an internal spec DSL, not injection), ADR-0051 (doc comments / heredocs — the doctest host), ADR-0042 (protocol-bounded generics — matchers need `Eq`/`Show`/`Ord`), ADR-0047 (portable prelude — `Test` is portable Rian), ADR-0052 (documentation site — renders proven-current specs), ADR-0057 (portable sequential logic **and tests** across targets), ADR-0027/0031 (self-hosting; `Rian.Fixpoint`)
**Owners:** Liam Davis (ergonomics/DX) · Samir Patel (rigor) · Maya Lin (multi-target/cost) · Kira Neri (honesty/determinism) · Arthur Pendelton (no-exceptions fit) · Elena Rostova (protocols) · Chloe Bennett (surface) · Rachel Okafor (PM)

## Context

"Should Rian adopt spec/BDD to improve DX?" conflates **three** things with opposite cost/benefit,
and the team resolved the question only after separating them:

1. **Gherkin / Cucumber** — external `Feature/Scenario/Given/When/Then` natural-language files bound
   to code by step-definition regexes.
2. **RSpec-style spec** — an *executable* `describe`/`it`/matcher DSL written in code.
3. **Specification by example / doctests** — examples that are *simultaneously* documentation and
   tests (what the by-example tour and `docs/spec/*.md` gesture at, but do not enforce).

Three facts about Rian shape the answer:

- **Recurring drift.** Prose examples in ADRs/specs have repeatedly gone stale against the code
  (e.g. the abstract-forms backend documented as "not started" while it was the default; `pi`
  called "undefined" while it lowered). Each is a *doctest that was never run*.
- **No exceptions** (ADR-0035). Mainstream BDD assertions raise on failure; Rian has no exceptions,
  so an assertion must **return** an outcome value.
- **Multi-target, pre-protocol.** The pitch is *write logic + tests once, run on every target it
  reaches* (ADR-0057). But a rich matcher DSL needs `Eq`/`Show`/`Ord` — protocol-bounded generics
  (ADR-0042 pt 2), still unbuilt. Any matcher work is downstream of protocols, exactly like the test
  framework itself.

## Decision

### 1. Three testing tiers, each with a distinct job — do not conflate them

| Tier | What | Job | Status |
|---|---|---|---|
| **A — Properties / fixpoint / golden** | generative + reference-equivalence (`Rian.Fixpoint`), the exhaustiveness/error-set/linearity gates | **rigor / coverage** | partly shipped |
| **B — Spec-by-example / doctests** | examples in `@doc`/`@moduledoc` heredocs (ADR-0051) and `docs/spec/*.md` fences, executed | **documentation that cannot drift** | **adopt first** |
| **C — assertion macros + matchers** | boolean `assert`/`refute`/`assert_eq`/`assert_neq` + diagnostic matchers `expect_eq`/`expect_neq`/`expect_true`/`expect_false` (→ `Outcome`); `contain` + `describe`/`it` deferred | **readable unit specs** | shipped (`prelude_test.rian`); `contain` needs `List`, `describe` isn't a macro |

Tier B is **documentation, not coverage** (Samir's constraint): a green doctest proves the shown
input, nothing more. It must never be sold as, or substituted for, Tier A. Its value is killing the
drift bug-class Tier A does not touch.

### 2. Assertions are values, not exceptions (ADR-0035)

An example / `it` returns `Test.Outcome := Pass | Fail(String)`; a suite folds outcomes into a
report. The **per-target harness** maps `Fail(msg)` to that target's native xUnit failure (ExUnit
`flunk`, Rust `panic!`/`assert!`, `node:test` `throw`). This makes the Rian surface a pure
value-flow — *more* principled than the exception-based BDD it borrows from, not a workaround.

### 3. Tests lower once to each target's idiomatic xUnit, reach-gated

A `@test def` lowers to ExUnit (BEAM), Rust `#[test]`, and `node:test` (JS) — the
once-tested-everywhere payoff (ADR-0057). **Shipped:** all three harnesses —
`Rian.Test.exunit/1` (BEAM), `Rian.Test.rust/1` (`rustc --test`-verified), and
`Rian.Test.js/1` (`node --test`-verified); one `@test` surface, three native
xUnits. Discovery is the **`@test` annotation** (the annotation parser was
extended past `@doc`/`@moduledoc`/`@typedoc`). *Refinement:* reach-gating each
test to exactly the targets its function-under-test reaches (`Rian.Reach`,
ADR-0058) is not yet wired — the harness emits for the requested target.

### 4. Any spec DSL is **internal** — built from Rian's own surface (ADR-0030/0032)

The assertion layer is hygienic-macro sugar over ordinary `def`s — inside the one surface family
(ADR-0032), **not** a separate grammar. **Shipped** (`examples/rian/prelude_test.rian`): the
ExUnit-equivalent *boolean* assertion macros — `assert(cond)`, `refute(cond)`, `assert_eq(a, b)`,
`assert_neq(a, b)` — declarative pattern→template macros (ADR-0030) that expand to a plain `Bool`,
so a `@test def` reads like ExUnit while staying a pure value-flow (§2). They need only built-in
`==`/`!=`/`not`, so they carry no protocol or prelude dependency and lower on all three targets.
Rian macros are **scope-local** with no cross-file import (ADR-0030), so `Rian.Test` **prepends**
the lib to every test source it compiles — that injection is how the vocabulary is shared.

The **diagnostic matcher DSL** also shipped, layered on the boolean floor: `expect_eq`/`expect_neq`/
`expect_true`/`expect_false` return `Outcome := Pass | Fail(String)` (§2) and, on failure, name the
mismatch via string interpolation (`Fail("expected ${expected}, got ${actual}")`, ADR-0069) — so a
red test says *how it differed*, not just *that it did*. The operands must be interpolatable (a
`Show` type, or `impl Show` — else an honest compile error, never a silent `inspect`). `Rian.Test`
interprets a test's `Bool` **or** `Outcome` return uniformly, and the Rust/JS harnesses wrap an
`Outcome` test to assert `Pass` and surface its message. The matchers are spelled `expect_*`, **not**
the bare `eq`/`be` originally sketched: a prepended macro shadows a same-named function, so a bare
`eq` would hijack the `Eq` stdlib's `eq`/`neq` — the `expect_` prefix keeps the vocabulary
collision-safe.

Two pieces stay deferred, for distinct reasons:

- **`contain` (membership matcher)** needs the `List` prelude linked into the test source (like
  `assert_in`); it is the one matcher with a non-built-in dependency.
- **A `describe`/`it` grouping layer** is **not** expressible as a Rian macro: macros are
  expression→expression substitutions (ADR-0030), not declaration generators, so they cannot emit
  `def`s. The `@test def` itself **is** the unit; grouping is by module/file, not a macro.

### 5. Gherkin / external feature files are rejected

Recorded so the question stops recurring. A natural-language `.feature` layer is **not** adopted:

- **Second grammar (ADR-0032).** Gherkin is a distinct NL surface with its own parser, glued to
  Rian by step-regexes — the one-surface-family commitment forbids it.
- **Drift (ADR-0035 honesty).** A `Scenario`'s prose and its step definition are *two* artifacts
  that rot apart — the exact "describes the test" drift we keep paying down. Tier B/C are
  "*is* the test" and cannot drift; Gherkin is "*describes* the test" and always does.
- **Audience mismatch.** Gherkin's headline benefit is business-stakeholder-readable acceptance
  criteria. Rian's user writes portable sequential logic + tests (library/systems authors,
  ADR-0057); that stakeholder is not in the room, so we would pay the full tooling cost for value we
  cannot bank.
- **Cost / sequencing.** A Gherkin parser + step binder + three step-emitters, for a language whose
  test framework is itself blocked on protocols, is the penthouse before the foundation.

## Ratings

| Option | Rating | Note |
|---|---|---|
| Tier B — doctests / executable spec-by-example | 5/5 | kills a live bug-class; zero new surface; rides EEP-48/rustdoc doctest machinery |
| Make the by-example tour runnable (assert stated outputs in CI) | 4/5 | extends the `Rian.Fixpoint` "demo → regression" move to the tour |
| Tier A — property/generative + the existing gates | 4/5 | the rigor backbone; BDD must not displace it |
| Tier C — internal `describe`/`it` + matchers | 3/5 | ergonomic; **downstream of protocols (ADR-0042)** — a *second* protocol customer, not their driver |
| RSpec-style as a *separate* effort from the test framework | 1/5 | it *is* the test framework with grouping sugar — one effort, not two |
| Gherkin / external `.feature` files | 1/5 | second grammar, prose↔stepdef drift, audience mismatch, pre-protocol cost |

## Consequences

- **Doctests close the stale-example bug-class** at its source: an example that drifts fails the
  build, instead of being hand-removed in a later cleanup pass.
- **The docs become one executable artifact.** The tour, the specs, and the per-target API reference
  (ADR-0052) render examples that are *proven* current.
- **No matcher DSL ships before protocols.** Equality/format/ordering matchers (`eq`, `be`,
  `contain`) are `Eq`/`Show`/`Ord` consumers (ADR-0042 pt 2). They are a *showcase* of protocols, not
  a reason to reshape protocols around test ergonomics — the stdlib (`Dict`/`List` over `Eq`/`Ord`)
  remains the protocol critical path.
- **Tier discipline is load-bearing.** Documentation examples (B) and unit specs (C) never count as
  coverage; the property/fixpoint/gate tier (A) is the only thing that does.

## Open items

- **Doctest runner.** *Shipped* ([`Rian.Doctest`](../../lib/rian/doctest.ex)): the `#=>` marker
  (`expr #=> expected`, both real Rian, compared by value on the BEAM); doctests on top-level **and
  single-`mod` module-internal** functions (the checks are injected into the module so unqualified
  references resolve); and `run_markdown/1` / `exunit_markdown/1` over ` ```rian ` fences in
  `docs/spec/*.md` (e.g. [expressions.md](../spec/expressions.md) §4, locked in CI). *Still open:*
  multi-module-internal doctests and the per-target (Rust/JS) doctest harness.
- **Tour-as-regression.** Each `examples/rian/*.rian` already compiles; assert its documented
  outputs in CI (the `Rian.Fixpoint` pattern, generalised).
- **ExUnit → `@test def` transpilation.** *Shipped* (`Rian.Transpile`, ADR-0075): `mix rian.transpile`
  flattens an ExUnit test module to module-less `@test def`s and rewrites `assert`/`refute` to the
  assertion macros — so the test-porting track produces drafts that run end-to-end via `Rian.Test`,
  closing the loop the assertion macros opened. `assert_raise`/`setup` (no Rian image) stay markers.
- **`@test` annotation** vs the `test_` prefix convention — needs the annotation parser extended
  beyond doc comments (decl.ex).
- **Matcher surface + `Test.Outcome`.** *Shipped* (`examples/rian/prelude_test.rian`): the
  value-returning `Outcome := Pass | Fail(String)` and the diagnostic matchers
  `expect_eq`/`expect_neq`/`expect_true`/`expect_false`, formatted via interpolation (ADR-0069 —
  which now resolves a `${call()}` hole's type). *Still open:* `contain` (needs the `List` prelude
  linked) and the `eq`/`be`-bounded matcher set over arbitrary `Ord`/`Show` types as protocols
  mature (ADR-0042). `describe`/`it` grouping is not a macro (see §4) — it would need a
  declaration-generating facility Rian's macros deliberately lack.
- **Property/generative testing** for the compiler (generated corpora vs the reference lexer/parser)
  — the Tier-A expansion beyond today's fixed fixpoint corpus.
