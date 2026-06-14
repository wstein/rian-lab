# ADR-0049 — Backend Target Roadmap & Tiers

**Status:** Accepted (direction) · **Refines:** ADR-0026 (the flat six-target list), ADR-0031 (bootstrap stages; backend-parallel emitters)
**Refs:** ADR-0034 (integers), ADR-0035 (no hidden allocation on non-GC targets), ADR-0041 (target model), ADR-0042 (dispatch), ADR-0047 (stdlib), ADR-0048 (effects)
**Owners:** Maya Lin (emitters/tiers) · Liam Davis (ECMAScript) · Arthur Pendelton (typeclass/effect lowering) · Elena Rostova (Rust/WASM) · Kira Neri (CI parity) · Samir Patel (conformance) · Marcus Chen (supply chain) · Rachel Okafor (PM)

## Context

ADR-0026 named six targets — **JVM, Rust, Go, BEAM, JS, WASM** — as a *flat* list with no priority.
That under-specifies the work: the targets are not equally ready, equally cheap, or equally important,
and "multi-target" without a tier contract means every target is perpetually half-done. This ADR sets
**tiers** (a support contract) and a **roadmap**, and resolves the JS-target question (ECMAScript,
direct; PureScript reference-only).

## Decision

### 1. A tier is a support contract

| Tier | Contract |
|---|---|
| **1** | Idiomatic emitter; full stdlib (ADR-0047) + effect lowering (ADR-0048) + target model (ADR-0041); **CI-gated/blocking** (ADR-0026 parity); all tour examples compile **and run**; conformance matrix green |
| **2** | Language core + stdlib; CI runs but **non-blocking**; may lag a feature; examples compile |
| **3** | Experimental / partial; best-effort; **no support promise** |

### 2. Tier assignments

| Target | Tier | Rationale |
|---|---|---|
| **BEAM** | **1** | The bootstrap path (ADR-0031): Elixir-source interim → Erlang abstract forms. OTP/concurrency lives here. |
| **Rust** | **1** | Backend-parallel source emitter, already component-tested (ADR-0031). The ownership/zero-cost anchor. |
| **ECMAScript** | **1** | Web/Node reach; an *easy*, forgiving emission target. **Direct emission** (a source emitter like Rust). |
| **JVM** | **2** | Broad enterprise reach. **Emitter landed (2026-06-13, `Rian.JVM`) — Kotlin, not Java** (see §3a). A source emitter on the typed core IR, like Rust/JS. |
| **WASM** | **2** | **Rides the Rust pipeline** — emit Rust, compile to `wasm32` — so it is cheap given Rust is Tier 1. A *direct* WASM emitter is deferred. |
| **Go** | **3** | Deferred/best-effort; no near-term resourcing. |

### 3a. The JVM emitter targets Kotlin (landed 2026-06-13)

The Tier-2 JVM emitter (`Rian.JVM`) lowers to **Kotlin source**, not Java. Rian is sum-and-match
oriented, and Kotlin's `sealed interface` + `data class` + smart-cast `is` patterns + expression-`if`
map almost 1:1 — far less boilerplate than Java's pre-Valhalla boxing, and consistent with the
idiomatic-per-target ethos (BEAM/Rust/JS each get their native shape; ADR-0041 already specced sums →
"JVM enum/sealed"). A Rian sum lowers to a sealed hierarchy (`data class Num(val f0: Long): Expr`),
a multi-clause `def` to an `if`-dispatcher with smart-cast binds. `Int64` → `Long` (64-bit native,
no boxing dance). It is a **source emitter on the typed core IR** (`Core.from_expr`/`from_pat`), the
fourth backend with no new fork (ADR-0050) and the second proof of that thesis after `Rian.JS`.

**Scope (MVP):** functions (single/multi-clause), `Int64`/`Float64`/`Bool`/`String`, operators,
`if`, local calls, `when` guards, and sum variants — verified end-to-end (the `selfhost_opt` optimizer
lowers to Kotlin, compiles with `kotlinc`, and folds correctly under `java`). Lists/`Vec`, maps,
structs, `case`, protocols, and FFI raise `Rian.JVM.Unsupported` (the next increments). Per ADR-0026
parity, JVM CI stays **non-blocking** until promoted (and `kotlinc`/`java` are absent from the
Erlang-only CI image, so the run-tests no-op there, like the `node`/`rustc` pattern).

**Artifacts & citizenship** are a separate ladder (**ADR-0062**): rung B — a runnable `.jar` via
`kotlinc` (`Rian.JVM.to_jar/3`, `mix rian.jar`) — is shipped; rung C — *direct* JVM bytecode (the
analog of `Rian.Beam`'s abstract forms, via a `java.lang.classfile` helper, ultimately in-process
once Rian self-hosts on the JVM) plus Java interop — is the path to first-class citizenship and is
gated on scheduling + the self-hosting roadmap.

### 3. ECMAScript is emitted directly; PureScript is a reference, not a dependency

The JS target emits **ECMAScript directly from day one**. **PureScript is a *semantic reference only*** —
its lowering of **type classes → dictionary passing**, HM inference, and **effects → `Effect`/`Aff`** is
studied to inform Rian's own JS lowering (it confirms ADR-0042's JS protocol dispatch as
dictionary/vtable objects, and ADR-0048's effect erasure). **No `purs` dependency, ever** — avoiding the
supply-chain/trust surface (Marcus) that the interim-`purs` and co-equal-target options would have added.
PureScript's value is that its type system is the closest typed-FP model to Rian's; we borrow the
*lowering knowledge*, not the compiler.

Most of the ECMAScript target is already specified across the corpus:

- `Int` → **`BigInt`**, `Int53`/`Int32` → native `number`; **`Int64` is NOT supported on JS**
  (superseded by **ADR-0064 §2a** — the old `Int64 → BigInt` mapping silently widened a bounded type).
  `Symbol`/opaque → **branded types** (ADR-0041/0043).
- **Integer division has no operator in ECMAScript.** Unlike Pascal/Ada, ECMAScript follows IEEE 754:
  `/` always returns a `Number` (double) — `5 / 2 === 2.5`. So a Rian **`div`** (integer division,
  truncate-toward-zero, matching the BEAM) must **not** lower to a bare `/`. The emitter is mode-aware
  (`expr_js(%EBin{op: "div"})`): **number-mode** (`Int53`/`Int32`) → `Math.trunc(l / r)`; **BigInt-mode**
  (`Int`) → `l / r` (BigInt `/` already truncates toward zero, so it matches `div` for both signs).
  Float division (`/`, which the checker types `Float64`) lowers to **native JS `/`** (`js_op("/")`):
  `Float64` is a JS `number`, and ECMAScript `/` *is* IEEE-754 float division — exactly `/`'s meaning.
  The JVM emitter is symmetric (`kt_op("/")` → Kotlin `Double` `/`).
- Effects **erase** to ambient JS IO (ADR-0048); the event loop **fits the sequential core** (ADR-0031 —
  no OTP off-BEAM).
- Protocol dispatch → **dictionary/vtable objects** (ADR-0042 JS note, confirmed by the PureScript study).

### 4. Relationship to the bootstrap stages (ADR-0031)

Only **BEAM** is the bootstrap path (interim Elixir-source → abstract forms at Stage 0.5). **Rust,
ECMAScript, JVM, WASM, and Go are backend-parallel *source emitters*** — they ride Stages 0.1/0.3
automatically (the front-end is backend-agnostic) and have **no abstract-forms swap**. WASM is the
exception that isn't even its own emitter yet: it is `Rust → rustc wasm32`.

### 5. CI parity is the tier line (ADR-0026)

- **Tier 1** (BEAM, Rust, ECMAScript): each emitter runs the conformance matrix (ADR-0041) on **every
  commit, blocking**; all tour examples must compile and run.
- **Tier 2** (JVM, WASM): CI runs **non-blocking** until promoted.
- **Tier 3** (Go): best-effort, no CI promise.

### 6. Roadmap sequence

1. **Now:** BEAM (bootstrap) + Rust (parallel) — component-tested.
2. **Complete Tier 1:** the **ECMAScript emitter** (direct) — the near-term target-language work, gated on
   the declaration parser + shared IR (ADR-0031 Stage 0.1).
3. **Tier 2:** JVM emitter; WASM via the Rust→`wasm32` pipeline.
4. **Tier 3:** Go emitter, when a concrete need appears.

All target work scales *after* the front-end (parser + typed core IR) is solid — the leverage point
ADR-0031 already identifies.

## Ratings

| Decision | Rating |
|---|---|
| Tiers as a support contract (1 blocking-CI / 2 non-blocking / 3 best-effort) | 5/5 |
| Tier 1 = BEAM, Rust, ECMAScript | 5/5 |
| ECMAScript **direct**; PureScript **reference-only**, no `purs` dependency | 5/5 |
| WASM Tier 2 **via the Rust pipeline**; direct WASM emitter deferred | 4/5 |
| JVM Tier 2; Go Tier 3 | 4/5 |
| Backend-parallel source emitters ride Stages 0.1/0.3; only BEAM has the abstract-forms swap | 5/5 |
| Co-equal PureScript target / interim `purs` accelerator | 2/5 (rejected — permanent or interim `purs` trust surface) |

## Consequences

- **ADR-0026's flat target list becomes tiered;** "multi-target" now has a concrete support contract and
  an order of work.
- **ECMAScript is the next emitter to build** to complete Tier 1, after the parser/IR.
- **WASM is nearly free** given Rust Tier 1 (Rust→`wasm32`), which is why it sits at Tier 2 rather than 3.
- The **conformance matrix** (ADR-0041) and the **stdlib** (ADR-0047) gain per-tier obligations; Tier-1
  targets must satisfy all of target-model + effects + stdlib.
- Concurrency stays **BEAM-only**; every other tier gets the **sequential core** (ADR-0031), with the
  named non-BEAM concurrency gap applying to Rust/ECMAScript/JVM/WASM/Go alike.

## Open items

- **Direct WASM emitter** — when (if) the Rust→`wasm32` path's output size/runtime is unacceptable.
- **JVM value-type story** — boxing vs Project Valhalla value classes for opaque types / ranges
  (ADR-0043/0036) and `Int*` (ADR-0034) on the JVM.
- **ECMAScript module/interop conventions** — ESM vs CJS output; npm interop (the JS analogue of the
  ADR-0026 Hex/rebar3 ecosystem work).
- **Per-tier conformance-matrix contents** — the concrete cross-target test set each tier must pass.
- **Promotion criteria** — what advances a target from Tier 2 → Tier 1 (or Tier 3 → Tier 2).
