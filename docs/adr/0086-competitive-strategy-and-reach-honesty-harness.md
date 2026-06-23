# ADR-0086 — Competitive strategy: prove the reach matrix, then depth before breadth

**Status:** Proposed · **§5 (TypeScript view) Accepted + implemented 2026-06-22**
**Implemented:** partial — the *strategy* (sequencing + positioning) is direction-only, and its one load-bearing reach mechanism (the generative reach-honesty harness) is split into ADR-0087; **no reach-affecting code lands on this ADR until ADR-0087's gate (§2) is green.** The exception is **§5, now shipped** (`Rian.JS.compile_types/1` + the `.d.mts` sidecar in the npm package): the TS view is *documentation, not a gate*, so it neither rests on §2 nor widens the portable core — it is the one part of this ADR safe to build ahead of the gate.
**Refines:** ADR-0000 (honesty bar — strengthens *how* the matrix is verified: generative property, not a hand-picked corpus), ADR-0058 (reachability + CI parity — adds the property the parity lane must satisfy), ADR-0049 §5a (backend tiers / target budget — supplies the gate Swift/Python/Lua-PHP-Neko candidates pass *through*).
**Depends on / delegates to:** ADR-0087 (generative reach-honesty harness — owns the §2 mechanism this strategy gates on), ADR-0061 §5 (target-set-relative coherence — owns the §4 precondition this strategy rests on; this ADR re-decides neither).
**Refs:** ADR-0050 (typed Core IR is the emitter spine), ADR-0057 (concurrency native-per-target — the deliberate non-portability the thesis depends on), ADR-0064 (portable numeric contract — the largest existing honest-pin surface), ADR-0070 (`val` default capability), ADR-0071 (Python — *gated* behind §2/§3), ADR-0072 (Swift — *gated* behind §2/§3), ADR-0084 (PureScript port — the mid-flight cost §3 protects), ADR-0085 (Haxe-style dynamic triad — the §5a discipline this ADR generalizes).
**Owners:** Kira Neri (reach honesty / CI parity — §2/§3) · Maya Lin (emitters / TS view — §5) · Arthur Pendelton (coherence dependency — §4, owned in ADR-0061) · Samir Patel (rigor — §2/§4) · Elena Rostova (numerics / reach pins) · Rachel Okafor (PM / sequencing — §3)

## Context

The standing question — *"make Rian compete with best-in-class"* — is incoherent taken literally,
and naming the field is what makes it tractable:

- **[Scala.js](https://www.scala-js.org/)** ships a whole-program linker + optimizer producing JS
  that rivals hand-written output. We will not beat it on JS *quality* this decade.
- **[Swift](https://www.swift.org/)** added a real ownership model in 2023–24 (`~Copyable`,
  `borrowing`/`consuming` — SE‑0377/0390) and owns Apple-native at a depth we cannot approach.
- **[Roc](https://www.roc-lang.org/)** *hides* ownership entirely (reference counting + opportunistic
  in-place mutation when refcount is 1) and leads on pure-functional ergonomics.
- **[Gleam](https://gleam.run/)** hit 1.0 in 2024 with two homogeneous targets (BEAM **and** JS),
  famously friendly diagnostics, and a deliberate **no-type-classes** stance.
- **[Haxe](https://haxe.org/)** is the 20-year proof that one source → ~10 targets is *buildable* —
  and the cautionary tale of what it costs without a gate (ADR-0085): `#if target` conditionals and
  per-target stdlib reimplementation, so code "compiles everywhere, breaks at runtime on the target
  whose stdlib didn't map."
- **TypeScript** is the default typed language for the JS target specifically — the per-target
  competitor a web developer reaches for by default.

Beating each on its home turf is unwinnable. The only defensible position is the **intersection none
of them occupies**: *one typed source → BEAM **and** Rust **and** JS/JVM, with ownership **inferred**
(not hidden like Roc, not hand-written like Swift/Rust) and target reach **inferred and honestly
refused** (not hand-picked like Gleam, not compile-and-pray like Haxe).* That pairing — inferred
ownership + honest inferred reach — is the one sentence no competitor can say.

**The problem this ADR exists to fix:** that sentence is currently *asserted, not proven*. The reach
matrix's honesty rests on `reach_rust_honesty_test` and friends running over a **toy corpus**
(CLAUDE.md). A matrix that is honest on a hand-picked corpus is honest *by selection bias* — the exact
failure this project already caught itself in once ("suite green by selection bias, NOT parity").
`Rian.Reach` is, today, a call-graph walk over an **enumerated** blocker set (wide-int prims, `ref`,
host FFI, the parametric-type `emittable_map` fixpoint). The fixpoint is a real lattice computation;
the *prim blocker set is a hand-maintained list*. An unmodeled blocker is a silent lie — and the lie
is in the one claim (honest reach) that is our entire moat. Everything else in this ADR is downstream
of closing that crack.

## Decision

### 1. The thesis, stated precisely (so every later decision can be judged against it)

Rian competes only on the intersection: **inferred ownership × honest inferred reach × the
BEAM+Rust+JS+JVM target set.** A proposal earns roadmap attention iff it *deepens that intersection*.
"Be more like X" where X already won X (Scala.js on JS quality, Swift on Apple depth, Roc on FP
ergonomics, Gleam on a narrow two-target story) is explicitly **out of scope** — we do not chase a
rival onto its home turf.

### 2. Make reach honesty *provable*, not *asserted* — gate on a generative property

A reach claim is honest iff it is mechanically verified (ADR-0000/0058), and today that verification
rests on a hand-picked corpus — honesty *by selection bias*. This ADR commits to strengthening the
gate from "passes a fixture corpus" to **"survives a generative property":** *if `Rian.Reach` claims
program `p` reaches target `t`, the emitter for `t` must produce output the real `t` toolchain
compiles and runs* (and the contrapositive — a program the toolchain rejects must not be claimed
reachable). This is the **load-bearing mechanism under the whole moat** (§1), with real design surface
(generator over Core, shrinking, per-target conformance lanes), so it lives in its **own ADR — see
ADR-0087 (generative reach-honesty harness)**, which *locks the invariant above* and owns the
mechanics. The commitment recorded *here* is the **gate it enforces:** no new target (§3) and no
widening of "portable" may land until its column is green under that property, not merely under
fixtures.

### 3. Depth before breadth — new targets gated behind §2, not added beside it

The drift tax (CLAUDE.md) is **multiplicative in target count**: every new Core node must satisfy, or
honestly pin off, *every* emitter. With the PureScript re-platform mid-flight (ADR-0084), target
sprawl now competes directly with self-host parity (`v1==v2`, ADR-0063), which is the work that makes
the drift tax self-amortizing. Therefore:

1. **Deepen the four we have** before adding a fifth. The concrete depth work is the remaining `:rs`
   gaps (recursion cycles needing `Box`, compound-nested parametric fields, `Fn`-field comparison —
   CLAUDE.md) — each closed is a claim *structurally unavailable* to Roc/Swift/Gleam.
2. **Swift (ADR-0072), Python (ADR-0071), and the Lua/PHP/Neko triad (ADR-0085) stay candidates**,
   named with their unlocks (Apple-native; dynamic/legacy-web; embedding), **gated behind §2**: a
   candidate joins the `@targets` vocabulary only when its column is green under the generative
   harness, never on the strength of a design ADR. This is ADR-0049 §5a's admission gate, sharpened
   from "conformance corpus" to "conformance *property*."
3. **Self-host parity outranks every candidate** (ADR-0063 sequencing, unchanged).

### 4. Coherence is a precondition owned by ADR-0061 — recorded here, not re-decided

Multi-target protocol lowering requires coherence — one instance per `(protocol, type)`, the orphan
rule, no overlapping impls — already specified and shipped as **target-set-relative coherence in
ADR-0061 §5**. The breadth strategy *depends on* it, and the dependency is the point: Gleam can omit
ad-hoc polymorphism *because* it is narrow (two homogeneous GC'd runtimes where an untyped dictionary
behaves identically on both); Rian lowers the *same* dispatch to **monomorphized Rust**, where an
incoherent instance is a type error or a silently divergent binary — a soundness bug the reach matrix
(§2) cannot catch because it does not model instance identity. That rationale, **and the sharpening it
forces** — extracting coherence to `Rian.Coherence` and running it as an explicit, per-module
`Rian.Check` gate plus a property test (ADR-0061 §5, `Amended 2026-06-21`; the orphan rule stays
*structural* until cross-module impls exist) — live in ADR-0061, the single authority for coherence.
This ADR only records that the strategy rests on it.

### 5. TypeScript as a typed *view* over the JS backend (not a fifth semantic target)

The JS emitter holds full Core types and discards them at the boundary. Emit **TypeScript + generated
`.d.ts`** as a *typed print mode of the existing JS backend* — same lowering, same semantics, one
extra annotation pass. This is the one place Rian's type system currently goes dark: a consumer
importing a Rian module gets real signatures checked by *their* compiler across the FFI boundary,
instead of `any`. The `Int53`/`BigInt` contract (ADR-0064, `reject_wide_int!`) becomes *visible* in
the output rather than implicit. **Honest scope limit:** TS types are structural and erased — they are
consumer-side documentation, **not** a capability/reach gate; the gate stays `Rian.Reach` + §2. Because
it is one backend with two print modes, it adds a bounded annotation cost, not a new emitter's full
drift-tax row. This is also the direct answer to "why not just write TypeScript": *typed once, lowered
to BEAM/Rust/JVM too — a claim TS cannot make by construction.*

**Amended 2026-06-22 — emit detail decided and shipped (resolves the §5 open item).**
The typed view is a **declaration sidecar**, not `.ts` source: `Rian.JS.compile_types/1` is
a **second print mode** of the JS backend (same `Decl.parse` → `Check.gate!` → `Opaque.erase`
prologue as `compile/1`) that emits a TypeScript declaration file for the module's **exported**
surface — `export function`/`export const` for every `pub` declaration plus `type`/`interface`/range
aliases for the user types they reference. The runtime `.mjs` is untouched.

- **Filename: `<name>.d.mts`, not `<name>.d.ts`.** The runtime is ESM (`.mjs`), and TypeScript
  resolves an ESM module's declarations from the sibling `.d.mts` (a `.d.ts` does *not* resolve for
  a relative `import "./m.mjs"` — verified with `tsc`). The npm `package.json` also gains a
  `"types"` field pointing at it, so a package-name import is typed too. The build
  (`rian build --js -o`, ADR-0082 step 4) writes the sidecar beside the `.mjs`.
- **Capabilities leave no TS trace.** `val`/`iso`/`tag`/`ref` shape Rust/BEAM only (ADR-0055) and
  have no JS runtime meaning, so they are fully erased in the view (a `Vec(T)` param is `T[]` whether
  it arrived `val` or `iso`).
- **Reach surfaces only by omission.** The view declares only what the `.mjs` actually exports; a
  function that is not JS-reachable never reaches this print mode (`compile/1` fails first). The
  declarations *describe runtime values* — a sum is `["Ctor", …]`, a struct `{__struct__: "Name", …}`,
  a `Result` an `["ok", v]` / `["error", e]` pair, an `Int` a `bigint`, an `Int53`/`Char` a `number`.
  A type outside the faithfully-mappable subset becomes `unknown` (honest), never a misleading `any`.
- **Types are documentation, not a gate** (unchanged): the reach gate stays `Rian.Reach` + §2.

**Amended 2026-06-23 — a third print mode: native `.ts` source.** The declaration sidecar
(`compile_types/1`) describes only the *exported* surface and pairs with the runtime `.mjs`. A second
consumer need is a **self-contained, readable typed module**: `Rian.JS.compile_ts/1` emits native
TypeScript — the **byte-identical runtime** of `compile/1` with a type annotation woven into every
`function`/`const` signature, and the value types it references declared inline. So the JS backend now
has **three print modes over one Core lowering**: `compile` (the `.mjs` runtime), `compile_types` (the
`.d.mts` surface view), and `compile_ts` (typed `.ts` source). The `.ts` differs from the sidecar in
two ways: it includes **private** functions (a runnable module needs them, not just the export surface)
and it carries the runtime bodies, not just signatures — so it type-checks standalone under
`tsc --strict` (the bodies satisfy their own headers — verified). It is gated by the `jsts` parity
stream (PureScript `compileTs` ≡ Elixir `compile_ts`); like the sidecar it is **documentation, not a
reach gate**. The playground (ADR-0090) renders the live `.ts` beside the live `.mjs`.

This sets the **pattern** a future typed view over another *dynamic* target (the ADR-0085 Lua/PHP/Neko
triad, or ADR-0071 Python — all type-erasing like JS) would reuse: a second print mode over the same
lowering, not a new emitter. It **adds no target and widens nothing** — the §5a admission gate and the
target budget (ADR-0049 §5a) stand; a typed view is a print mode of an *already-admitted* target, never
a way to smuggle one in.

### 6. Reach blockers must read like diagnostics, not mysteries

Inference is a moat for the compiler and a mystery for the user unless it is *legible*. Every reach
pin must print like a friendly error: `file:line` + the *specific* cause — e.g.
`":ex"-only: line 12 calls __prim_wrapping_add, which has no JS lowering` rather than a bare
`FunctionClauseError`/`Unsupported` raise. This unifies the DX agenda (Gleam/Elm-grade messages) with
the inference agenda: the same work that makes reach trustworthy makes it teachable.

### 7. Competitive positioning — the one-sentence deltas (write them down, then live by them)

The positioning surface (README / docs) states the differentiator against each live competitor, and
every later decision is checked against these:

- **vs Gleam** — "+Rust/JVM, +inferred reach instead of hand-picked targets."
- **vs Roc** — "ownership **inferred and exposed** as portable Rust, not hidden behind refcounting."
- **vs Haxe / Fable** — "honest, gated reach, not compile-and-pray `#if`."
- **vs TypeScript** — "typed *once*, lowered to many — not typed JS only."
- **vs Swift / Rust** — "the same ownership discipline, **inferred** from a GC-shaped surface, not
  hand-written." (Swift's `~Copyable` is cited as *validation* — ownership in a friendly language is
  now convergent design, not a Rust idiosyncrasy.)

### 8. Effects-as-rows — parked as a north star, not a roadmap item

[Koka](https://koka-lang.github.io/) proves algebraic effects can be **inferred as row types** and
printed — i.e. inferred ≠ unprincipled. The honest end-state for `Rian.Reach` is to become a sound
effect/capability *type system* (honest by construction) rather than a call-graph walk over an
enumerated blocker set (honest by exhaustive testing, §2). This is a **research bet**, explicitly *not*
scheduled here; §2 is the pragmatic bridge that keeps the heuristic honest until — or unless — the
type-theoretic version is justified.

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — compete only on the inferred-ownership × honest-reach intersection; refuse rivals' home turf | 5/5 | the only defensible framing; makes every other call judgeable |
| 2 — gate on a generative reach-honesty property (mechanism split to ADR-0087) | 5/5 | closes the one crack under the whole moat; non-negotiable, comes first |
| 3 — depth before breadth; candidates gated behind §2; self-host outranks targets | 5/5 | the drift tax is multiplicative — sequencing *is* solvency |
| 4 — record coherence as a precondition; delegate the rule to ADR-0061 §5 | 4/5 | the right *home* for an already-shipped rule; −1 the real work is the 0061 extract-to-`Rian.Coherence` + Check-gate amendment |
| 5 — TypeScript as a typed view over the JS backend | 4/5 | high-leverage, low-machinery adoption unlock; −1 TS types are doc, not a gate |
| 6 — legible reach diagnostics (`file:line` + cause) | 4/5 | unifies DX + inference; −1 it is polish, ranked below §2/§4 |
| 7 — written one-sentence competitor deltas | 5/5 | free, and disciplines every downstream decision |
| 8 — effects-as-rows parked as a north star | 3/5 | right direction; −2 it is a research bet, not a commitment |
| Adopting a *strategy* ADR at all (vs. only feature ADRs) | 4/5 | honest as a sequencing contract; −1 strategy ADRs rot if not revisited |

## Consequences

- **The honesty thesis becomes provable, not aspirational.** Once §2 ships, "honest reach" is backed
  by a generative property over arbitrary programs — the claim Haxe/Fable never made, and arguably a
  publishable artifact in its own right ("keeping a multi-target capability matrix honest").
- **New targets get slower to add, on purpose.** Swift/Python/Lua/PHP/Neko (ADR-0071/0072/0085) cannot
  join `@targets` until green under §2. This is the intended brake: an aspirational column *is* the
  Haxe failure (ADR-0085 §7), and poisons the one thing we sell.
- **Coherence constrains the protocol surface** (ADR-0061): a second `Eq` instance is now a compile
  error, not a runtime surprise — the cost of lowering the same dispatch to Rust.
- **`Rian.JS` grows a TS print mode**, not a sibling emitter — bounded drift-tax cost, real FFI-boundary
  payoff.
- **Reach pins become teachable**, turning the inference from a mystery into a feature.
- **Self-host parity (ADR-0063) is explicitly protected** from target-sprawl resourcing during the
  PureScript re-platform (ADR-0084).

## Open items

- **§2 / §4 mechanics live in their owning ADRs.** The generator scope, shrinking strategy, and
  per-target conformance lanes are open items in **ADR-0087**; the orphan/overlap enforcement algorithm
  is an open item in **ADR-0061 §5** (its `Amended 2026-06-21` note). They are not re-listed here.
- **§5 TS emit detail.** `.ts` source vs `.js`+`.d.ts` sidecar; how capabilities/reach surface (if at
  all) in the emitted types; whether `iso`/`val` leave any TS-visible trace or are fully erased.
- **§6 diagnostic catalog.** A stable code per blocker class (wide-int prim, `ref`, host FFI,
  parametric non-bootstrap) so messages are greppable and documented.
- **§8 trigger.** What evidence would promote effects-as-rows from north-star to roadmap — likely: §2
  catching the *same class* of unmodeled blocker more than once (a sign the enumerated set is
  structurally insufficient).

## Alternatives considered

- **Breadth-first: add Swift/Dart/Python now to look multi-target.** Rejected — multiplicative drift
  tax against a mid-flight re-platform (ADR-0084), and an ungated column is the Haxe failure mode
  (ADR-0085 §7) applied to our own moat.
- **Keep the fixture corpus; skip the generative harness.** Rejected — fixture honesty is selection-bias
  honesty (the project's own prior lesson), and the moat is precisely the claim a fixture cannot prove.
- **Drop protocols entirely, à la Gleam.** Rejected — Gleam can omit ad-hoc polymorphism *because* it
  is narrow; our Rust lowering makes coherence (not absence) the cost of breadth (§4).
- **Compete on JS quality (a Scala.js-grade linker).** Rejected (for now) — fighting Scala.js on its
  home turf; the TS *view* (§5) is the higher-leverage, lower-cost JS move.
- **Commit to effects-as-rows now.** Rejected — a research bet, not a deliverable; §2 is the pragmatic
  bridge that keeps reach honest in the meantime (§8).
