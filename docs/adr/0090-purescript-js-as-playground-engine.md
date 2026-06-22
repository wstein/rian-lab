# ADR-0090 — PureScript → JS is the playground engine; purerl is the parity oracle

**Status:** Proposed
**Implemented:** no — direction + scope. The front-end, gates, inference, `Reach`, and the
assemble tail are ported to PureScript and parity-gated (`purs/src/Rian/*`,
`docs/purescript-migration.md`); the **emitters are not** (`Rian.JS`/`JVM`/`Lower`/`Beam` are
Elixir-only), and **no JS-backend build profile exists** — the port has only ever been compiled
through purerl. This ADR decides the *direction*; nothing here ships before the `Rian.JS` port
(the next emitter step) and a stock-`purs` JS build.
**Refines:** ADR-0084 (PureScript port — this **re-frames its purpose**: the port's *primary
deliverable* is a JS compiler for browser + node; type-safety-over-Dialyzer stands, but is no
longer the headline; purerl is recast in §2).
**Amends:**
- **ADR-0088 §3** — the live-playground engine is **no longer the `Rian.Eval` interpreter →
  WASM/JS.** Once the compiler is PureScript, its **own native JS backend** ships the *whole real
  compiler* to the browser; that strictly dominates a separate interpreter-to-WASM artifact (§4).
  `Rian.Eval`'s **oracle** role (ADR-0088 §1–2, §6) is untouched — only its §3 *engine* role is
  superseded.
- **ADR-0052 §"Playground architecture"** — "live engine = self-host → JS only / interpreter
  first" becomes "**PureScript → JS now; self-host → JS is a later language milestone, not the
  gate**" (§3, §5).
**Refs:** ADR-0049 (Tier-1 ECMAScript — the emitter this rides on), ADR-0058 (reachability-gated
honesty matrix — the parity corpus that gates the JS build), ADR-0063 (self-host / `v1==v2` —
demoted from playground precondition to milestone), ADR-0082 (native packaging — the npm/node
artifact), ADR-0087 (reach-honesty harness — value canonicalization the cross-build check reuses),
the emitter sequencing in `docs/purescript-emitter-port-plan.md` (Part A = `Rian.JS`, first).
**Owners:** Maya Lin (architecture / emitters) · Liam Davis (playground / DX) · Kira Neri
(build/CI / two-backend parity) · Marcus Chen (npm/node distribution) · Mira Halden (anti-drift) ·
Rachel Okafor (PM)

## Context

ADR-0052 and ADR-0088 both decided the live-playground engine **while the compiler was Elixir**.
Elixir has no clean browser story, so the only options on the table were *compile a separate
artifact to WASM* (ADR-0088 §3 — the `Rian.Eval` interpreter) or *wait for the whole language to
self-host onto JS* (ADR-0052 — gated on the `v1==v2` bootstrap). Both are workarounds for one
missing capability: **a compiler that runs in a browser.**

ADR-0084 removes that constraint as a *side effect* nobody costed. **PureScript's home backend is
JavaScript** — `purs` emits clean ES modules natively, with the JS backend built into the compiler
binary (no extra tool). **purerl (PureScript → Erlang) is the add-on**, bolted on to keep the BEAM
self-host bootstrap. So the same sources being ported for the migration compile to **browser and
node JS for free** through stock `purs` — no WASM, no Rust/WASM toolchain, no `v1==v2` loop.

This flips the framing of the port itself. ADR-0084 justified PureScript on *type-safety over
Dialyzer* and *BEAM retention via purerl*. In practice the load-bearing payoff is the **JS target**:
the in-browser playground compiler **and** a node-distributable `rian` CLI. Recast accordingly:

- **JS (browser + node) is the port's primary product.** It is why PureScript — a language whose
  native backend is JS — is the right host, over any other typed language.
- **purerl / BEAM is primarily the parity oracle.** Each ported module is checked byte-for-byte
  against its Elixir twin through the purerl build (`purs/test/*.erl`,
  `docs/purescript-migration.md`); that harness is what makes the port trustworthy. purerl also
  *retains* BEAM as a real target and keeps the self-host bootstrap alive (ADR-0063). But the
  reason to run on Erlang at all is now **parity + BEAM-retention**, not "Erlang is the
  destination."

The migration is already ~80% of the way to a browser compiler without anyone aiming there:
Lexer, Pratt, Core, Decl, **Check** (inference + the full 11-check gate + `annotate`),
Exhaustiveness, Capability, **Reach**, Macro, Protocol, Assemble are all ported and parity-gated.
The **only** Erlang FFI boundary in the entire port is `Rian.HostRef` (`@external` arity
reflection). What remains for a browser compiler is the JS emitter — **which is the next emitter
step anyway** (`docs/purescript-emitter-port-plan.md`, Part A).

## Decision

### 1. The playground engine is the PureScript compiler, compiled to JS by stock `purs`

The live "edit, see it run" engine is the **real Rian compiler** — `Lexer → Pratt → Core → Check
→ Exhaustiveness → Capability → Reach → Rian.JS` — compiled to a committed JS bundle by the
**stock `purs` JavaScript backend** and run client-side. An edited snippet compiles in the browser
with no backend; the emitted user JS runs in a **sandboxed iframe / Web Worker** with a step or
time budget. This is *not* a new engine to maintain: it is the same source as the purerl/BEAM
build, through a second backend.

### 2. Re-frame the port (amends ADR-0084): JS is the target, purerl is the oracle

- **Primary target: JS** — browser (playground) and node (CLI/npm, ADR-0082). The headline
  deliverable of the PureScript port is the JS compiler.
- **purerl / BEAM: parity oracle + bootstrap retention.** Keep the purerl build and the
  byte-equality parity harness against the Elixir reference as the migration's correctness spine,
  and keep BEAM as a real target / the self-host path (ADR-0063). The Dialyzer-replacement win of
  ADR-0084 stands — it is now a *means*, not the *motive*.

### 3. Self-host → JS is demoted from "playground gate" to "language milestone"

ADR-0052 gated the live playground on self-host → JS (the *whole language* lowering itself onto
JS, behind the `v1==v2` bootstrap, ADR-0063). That gate is **removed**: the PureScript → JS
compiler delivers an in-browser compiler *now*, written in a typed language, with no bootstrap
loop. Self-host → JS remains a worthwhile **language milestone** (it proves Rian can express its
own compiler and that the compiler reaches `:js`), and when it lands it becomes a **free
cross-check**: does Rian-on-JS agree with PureScript-on-JS over the same corpus? But nothing in the
playground waits on it.

### 4. Reject the interpreter → WASM as the *engine* (supersedes ADR-0088 §3); keep it as the *oracle*

ADR-0088 §3 chose `Rian.Eval` → WASM/JS as the early playground engine. That was correct **while
the compiler was Elixir**. With a PureScript compiler it is dominated on every axis:

- **Fidelity** — the PureScript → JS engine *is* the real compiler (all gates, the real `Rian.JS`
  output, the real four-target reach panel). An interpreter is a second semantics that must be kept
  in lockstep; the §6 anti-drift gate exists precisely because it can drift.
- **Substrate** — stock `purs` → JS produces clean ES modules. WASM-in-browser is the less slick,
  heavier substrate (the original motivation for this reframing).
- **Cost** — no separate artifact: the engine is a byproduct of the migration's next step, not new
  code to own.

**`Rian.Eval` survives undiminished as the conformance oracle** (ADR-0088 §1–2, §6): the
executable spec every backend — now including PureScript-on-JS — is checked against. Only its §3
*packaging* role is retired. (Per ADR-0088 §4, the interpreter is also still the precondition for
any future bytecode VM — building it remains path-independent.)

### 5. Carry over the standing rejections

- **BEAM-in-WASM** (AtomVM/Firefly/Popcorn) — still rejected (ADR-0052, ADR-0088): no interim WASM
  engine to build and discard.
- **Server-side compile** — still rejected: the portal stays static / offline / CDN-hostable. The
  PureScript → JS bundle is what makes a *client-side* compiler possible without a server.

### 6. Anti-drift: one source, two backends, one parity corpus

The browser compiler must **not** become a third dialect. Enforce that the **JS-backend build is
the same PureScript source as the purerl build**, gated by the **same parity corpus**: the JS build
must pass the migration's parity streams (re-run through a JS test harness), reusing the ADR-0087
value canonicalization for cross-backend equality. A construct that passes on purerl but is absent
on the JS build (or vice-versa) is a build-parity bug, not a feature. (This is the two-backend
analogue of ADR-0088 §6.)

### 7. Scope the first ship ruthlessly

To light up the playground:

1. **Port `Rian.JS`** (emitter-port-plan Part A — "well-bounded"; its prerequisite `Check.annotate`
   + `ic` has landed). This is the *only* stage strictly required to compile + run user code.
2. **Add a JS-backend build profile** — a second spago/`purs` config over the **standard
   PureScript registry** (where `Data.Map` etc. live; the port's purerl-driven assoc-list choices
   are *more* JS-portable, not less). Differences from the purerl build are exactly two: the
   package set, and FFI.
3. **Handle the one FFI boundary** — provide a JS FFI for `Rian.HostRef`, or stub it
   (conservatively accept `@external`); and **skip `Rian.Beam` in-browser** — there is no
   `:compile.forms` in a browser and a playground needs no `.beam`.
4. **Smoke-build the *current* (emitter-less) sources through `purs` → JS early** — before stacking
   the emitter on top — to flush package-set / FFI gaps while the surface is small.

Port `Rian.Lower` (Rust) and `Rian.JVM` (Kotlin) later **for the display panes only** — they are
shown as emitted source, never run in the browser, so they do not gate the live engine.

## Ratings

| Proposal | Verdict | Rating |
|---|---|---|
| **PureScript → JS (stock `purs`) = playground engine** | **Build (next emitter step)** | 5/5 |
| **Re-frame: JS primary target, purerl = parity oracle** | **Adopt** | 5/5 |
| `Rian.Eval` → WASM as the *engine* (ADR-0088 §3) | Superseded (keep as oracle) | 2/5 |
| self-host → JS as the playground *gate* (ADR-0052) | Demoted to milestone | 3/5 |
| BEAM-in-WASM · server-side compile | Reject (carried over) | 1/5 |

## Key points

- **The constraint both prior ADRs designed around is gone.** They assumed an Elixir compiler with
  no browser path; ADR-0084 makes the compiler PureScript, whose **native backend is JS**.
- **The playground engine is now a byproduct, not a project** — finishing the already-planned
  `Rian.JS` port + a JS build profile yields the *real* compiler in the browser.
- **purerl's job was misread as the destination** — it is the parity oracle (vs the Elixir
  reference) and the BEAM-retention path; **JS is the destination**.
- **The real compiler beats a shadow interpreter** — no second semantics to keep in lockstep, no
  WASM, all four reach panes are real output.
- **One piece of work, two goals** — "port `Rian.JS` to PureScript" was already the next migration
  step; it now *also* unlocks the live playground.

## Consequences

- **The migration's priority order gains a product reason to front-load the JS spine** (`Rian.JS`)
  ahead of `Beam`/`Lower`/`JVM`: it is both the next emitter and the playground unlock.
- **A second build profile is now a maintained artifact** — purerl (parity/BEAM) and stock-JS
  (browser/node) over one source. §6 keeps them honest; CI must run both.
- **node/npm `rian` falls out for free** (ADR-0082) — the same JS bundle is a `npx rian` CLI, not
  just a browser engine.
- **`Rian.Eval` is no longer on the playground critical path** — its value is now purely the
  conformance oracle (ADR-0088 §1–2). It can be built on its own schedule.
- **A new drift surface exists** — purerl-build vs JS-build divergence — addressed by §6, not
  assumed away.

## Open items

- **JS build profile** — the spago/`purs` config + standard package set; decide bundler (esbuild
  vs the `purs bundle`/`spago bundle-app` path) and the committed-bundle location under `site/`.
- **`Rian.HostRef` on JS** — stub vs real JS FFI for `@external` arity reflection (the browser has
  no `code:ensure_loaded`); likely "conservatively accept," matching the not-yet-loadable branch.
- **Two-backend parity harness** — run the migration parity streams through a JS test runner
  (node), reusing ADR-0087 canonicalization; wire into CI alongside `purerl-build.sh`.
- **Sandbox shape** — iframe `sandbox="allow-scripts"` (cross-origin) + Worker timeout/step budget
  for runaway user programs; decide the I/O channel (postMessage).
- **Self-host-on-JS cross-check** — when ADR-0063 reaches JS, assert Rian-on-JS ≡ PureScript-on-JS
  over the corpus (the free cross-check from §3).
- **emitter-port-plan update** — fold this engine decision into
  `docs/purescript-emitter-port-plan.md` Part A (add the JS-backend build + sandbox as Part A
  deliverables, not just the `.mjs`/`.d.mts` outputs).

## Alternatives considered

- **`Rian.Eval` → WASM as the engine (ADR-0088 §3).** Superseded (§4): dominated once the compiler
  is PureScript; the interpreter stays as the oracle.
- **self-host → JS as the gate (ADR-0052).** Demoted (§3): a language milestone and a future
  cross-check, not a precondition for shipping the playground.
- **Keep the compiler in Elixir, ship via WASM or self-host.** Rejected — that is the very
  constraint ADR-0084 removes; re-adopting it discards the port's main payoff.
- **Single backend (drop purerl, go JS-only).** Rejected: purerl is the parity oracle that makes
  the port trustworthy and the BEAM-retention / self-host path (ADR-0063). Two backends over one
  source is the point, gated by §6.
- **Server-side compile / BEAM-in-WASM.** Rejected, carried over from ADR-0052/0088 (§5).
