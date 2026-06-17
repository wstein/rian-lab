# ADR-0050 — One Typed Core IR: single contract, sealed-sum nodes, emitters as pure consumers

**Status:** Accepted (direction) · **Refines:** the `ir.ex` "expr/pattern stay tuples" pragma (overturned, with evidence)
**Implemented:** §1/§2/§4 yes — `Rian.Core` typed sealed-sum IR (`test/rian/core_test.exs`); all emitters
(Beam/Lower/JS/JVM) consume Core. §3 *infrastructure* yes — every emitter now builds its Core via
`Check.annotate/3`, so each node carries its inferred `type` (`Check.clause_env/3` supplies the
per-clause typing env). §3 *consumption* pending — no emitter yet reads `node.type` for its representation
choice (ADR-0041/0043/0046 still derive types the old way); reading it off the node is the remaining step.
**Refs:** ADR-0027 (self-hosting), ADR-0031 (abstract-forms backend; Stage 0.1), ADR-0034 (types; exhaustiveness over sums), ADR-0041 (representation needs types at emission), ADR-0043 (opaque erasure), ADR-0046 (monomorphization), ADR-0049 (three new emitters incoming)
**Owners:** Maya Lin (pipeline/emitters) · Arthur Pendelton (typed IR) · Chloe Bennett (parser unification) · Elena Rostova (migration) · Samir Patel (metric/dogfood) · Kira Neri (backend swap) · Rachel Okafor (PM)
**Evidence:** [SELFHOST.md](../../SELFHOST.md) verdict #3 (B1 fixed in *three* places — "the fork a self-hosted front end would inherit"); README "known gaps" #1.

## Context

The compiler has **one representation problem in three forms**. An expr/pattern node is produced by
**two parsers** ([`Rian.Pratt`](../../lib/rian/pratt.ex) `parse_pat` *and* [`Rian.Decl`](../../lib/rian/decl.ex)
`pattern`) and consumed in **two shapes**: the checker walks [`Rian.PatternLower`](../../lib/rian/pattern_lower.ex)'s
normalized `{:ctor, tag, args}` Maranget form, while the **emitter** ([`Rian.Lower`](../../lib/rian/lower.ex))
re-walks the **raw surface tuples**. Adding one construct (B1, list patterns) touched all three.
[`Rian.IR`](../../lib/rian/ir.ex) already structifies **declarations** but deliberately keeps **expr +
pattern as tuples** ("struct-ifying every arithmetic node would be churn without payoff").

That pragma predates two facts: the **B1 triplication** (drift is now demonstrated, not hypothetical)
and the **Tier-1 roadmap** (ADR-0049 adds **three** emitters — ECMAScript, JVM, WASM). Building three
more emitters on the surface-tuple representation casts three more forks. This ADR fixes the IR contract
*before* that happens.

## Decision

### 1. One typed core IR is the single contract; emitters are pure consumers

The pipeline is **`Lexer → Parser → surface AST → lower+check → typed core IR → emitters`**. The surface
AST is **transient** (parser output, immediately lowered). **Every downstream pass — the checker and
*all* emitters — consumes the typed core IR.** The emitter **stops walking surface tuples.** There is
exactly one downstream representation.

### 2. One parser

`Rian.Decl` **reuses `Rian.Pratt`** for pattern and expression parsing; the duplicate `Decl.pattern` /
`Pratt.parse_pat` split is eliminated. Patterns/expressions are parsed in **one** place.

### 3. The core IR is typed

After checking, core-IR nodes **carry the inferred type** (ADR-0034). This is **required**, not
cosmetic: the emitter's representation choices need it —

- closed-set `Symbol` → enum vs open `&'static str` (ADR-0041),
- opaque-type erasure (ADR-0043),
- monomorphization / closed-set specialization (ADR-0046).

An untyped emitter literally cannot make these decisions. The checker produces the typed core IR; the
emitter reads the types off it.

**Implementation note (2026-06-17).** The encoding is resolved (see Open items): each `Rian.Core` node
carries an inline `type` field, filled by `Check.annotate/3`. Every emitter (`Beam`, `Lower`, `JS`,
`JVM`) now annotates each clause body — `Check.annotate(ast, Check.clause_env(pats, params, ic), ic)`
with `ic = Check.program_ic(prog)` — instead of calling the bare `Core.from_expr/1`. So the *typed* core
flows into all four emitters today; what remains is to have the representation decisions (ADR-0041/0043/
0046) read `node.type` rather than re-derive it. That step is now a pure emitter-local change, not a
pipeline change.

### 4. The core IR is sealed sums / typed structs (expr + pattern, not just declarations)

Extend the struct treatment `ir.ex` already gives declarations to **expression and pattern** nodes:
sealed sums / typed structs, **not loose tuples**. Two payoffs the old pragma couldn't see:

- **No drift** — one node shape, `@enforce_keys`-guaranteed, a single site to change.
- **Self-hosting dogfood (ADR-0027/0034)** — when the compiler is rewritten *in Rian*, it represents
  its own IR with Rian types, and a **sealed-sum IR gives it exhaustiveness over IR nodes**. The
  totality gate that is Rian's pitch then applies to the compiler's *own* passes — a missed IR case is
  a compile error in the self-hosted compiler.

### 5. Migration is incremental, behind tests, and sequenced first

**Not a flag-day rewrite** (all passes are green). Lock the IR *shape* here; migrate **pass-by-pass,
behind the existing suites** — the emitter onto the typed core one construct at a time. Sequence it
**before**:

- the **ECMAScript emitter** (ADR-0049 Tier 1) — so emitter #3 is built on the core IR, not a 4th fork;
- the **abstract-forms backend** (ADR-0031 Stage 0.5) — `:compile.forms` wants a stable typed IR, not
  eval'd surface strings.

### Success metric

**Adding an expr/pattern form is a single-site change** — the core-IR node + one lowering — never three.
B1 (list patterns), done again under this IR, must touch one place.

## Ratings

| Decision | Rating |
|---|---|
| One typed core IR; emitters pure consumers of the core (not surface) | 5/5 |
| One parser (`Decl` reuses `Pratt`) | 5/5 |
| Core IR typed (carries inferred types) — required by ADR-0041/0043/0046 | 5/5 |
| Core IR as sealed sums / typed structs — exhaustiveness over IR nodes for the self-hosted compiler | 4/5 |
| Incremental migration behind tests, before ECMAScript + Stage 0.5 | 5/5 |
| Keep expr/pattern as loose tuples (current `ir.ex` pragma) | 2/5 (overturned, with evidence) |

## Consequences

- **Overturns the `ir.ex` expr/pattern-as-tuples pragma**, with evidence (B1 triplication, three
  incoming emitters) rather than preference. `ir.ex`'s moduledoc is updated to point here.
- **Unblocks clean implementation of every typed-emission decision** (ADR-0041/0043/0046) — the emitter
  finally has types.
- **De-risks the three new emitters** (ADR-0049): they are built once, against the core IR.
- **Prerequisite for the abstract-forms backend** (ADR-0031 Stage 0.5) and for **self-hosting**
  (ADR-0027) — the compiler-in-Rian inherits a single, exhaustively-checkable IR, not a fork.
- This is the **last design/architecture lock**; remaining work is implementation or tagged v2 deferrals.

## Open items

- ~~**Encoding of the inferred type on a node**~~ — *resolved:* an inline `type` field on each `Rian.Core`
  node (not a side-table), filled by `Check.annotate/3`. All four emitters now build their Core through
  `annotate`, so the typed node is what flows downstream.
- **How much normalization the core keeps** — does the core pattern stay the Maranget `{:ctor, tag,
  args}` form (good for the checker) while the emitter de-normalizes for idiomatic output, or do both
  read the normalized form? Resolve during migration.
- **Migration order** — which emitter construct moves first; the BEAM path vs the Rust path.
- **`ir.ex` node catalogue** — the concrete sealed-sum definitions for expr + pattern (the structs to
  add alongside `Type`/`Struct`/`Const`/…).

## Amendment (P1 — newline-tolerant `:=` bodies, 2026-06-14)

The design review flagged the "a `def … :=` body must stay on one line" rule as a **wart to kill
before freezing the surface** (P7), not a design choice. `Rian.Decl`'s `:=`-body collector
(`take_line`) is now **newline-tolerant**: a body continues across a newline when (a) inside
unbalanced `(`/`[`/`{`/`%{`, (b) a binary operator trails the line or (c) leads the next, or (d) the
body simply begins on the next line. A plain one-liner still ends at its newline. This is a *layout*
relaxation only — tokens and the operator table are unchanged (and are what P7 will freeze). The
self-host budget the review noted: `compiler/decl.rian` (which re-parses bodies) and the
`Rian.Fixpoint` anchor will track this when the Rian-written front-end widens to multi-line bodies.

## Spike finding (P6 — shared-traversal LCD check, 2026-06-14)

The review's P6 dissent (Mira/Dmitri vs Tomás/Kai): a shared-traversal emitter refactor risks
**lowest-common-denominator semantics** — the exact thing ADR-0041 exists to prevent — e.g. Rust
losing its real `enum` to a "simulated tuple." Resolution path was *spike one feature first*.

**Spike (`bench/p6_sum_lowering_lcd.exs`): no LCD regression.** Lowering `type Expr := Num(Int64) |
Add(Expr, Expr) | Zero` over the one Core IR yields, simultaneously, a real Rust `enum Expr { Num(i64),
Add(Expr, Expr) }`, a Kotlin `sealed interface` + `data class`/`object`, a BEAM tagged tuple
(`{:num, 5}`), and a JS tagged array — all idiomatic. **Conclusion:** a shared traversal is safe **iff
it shares the traversal *skeleton* but keeps a per-target *representation* hook at the lowering leaf**
(the existing `rust_enum` / `sealed interface` / tagged-tuple split). Sharing the *representation*
(collapsing everyone to a common tagged tuple) is where LCD would bite — Rust would lose its enum. So:
generalize the traversal, never the representation. (P6 stays *spike-only* until a concrete refactor is
proposed against that constraint.)
