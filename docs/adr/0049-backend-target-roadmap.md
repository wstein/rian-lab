# ADR-0049 — Backend Target Roadmap & Tiers

**Status:** Accepted (direction) · **Refines:** ADR-0026 (the flat six-target list), ADR-0031 (bootstrap stages; backend-parallel emitters)
**Implemented:** partial — `Rian.Beam`/`Rian.Lower` (BEAM+Rust), `Rian.JS` (Tier 1), `Rian.JVM` (Tier 2) emitters exist; Go/WASM not started, JS/JVM are subsets
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

### 2a. Once portable: the tier is a (host × target) matrix, not a number per target

The table above assigns **one tier per target** because today there is **one host**: the compiler runs
on the BEAM, so "which target" fully determines the support contract. **Portable self-hosting (ADR-0063
§4) breaks that** — the Rian compiler, lowered to JS/Rust/Kotlin, runs on several hosts, and the *same*
target can have very different maturity depending on *which host emits it*. From that point the support
contract is a **(host platform × target) matrix**, governed by one principle — **output type decides
host-coupling**:

- **Source backends are host-agnostic.** Emitting Rust/JS/Kotlin *source* is pure string generation, so
  any host emits it; those cells inherit the target's tier unchanged. (Running the source still needs the
  target toolchain — that is downstream of emission, not part of it.)
- **Bytecode backends are host-coupled** — emitting a platform's *bytecode* needs that platform's
  assembler in-process:
  - **The native-bytecode diagonal is first-class.** A host emitting its *own* platform's bytecode —
    BEAM→`.beam` via `:compile.forms`, JVM→`.class` via `java.lang.classfile` (ADR-0062 rung **C3**) — is
    the high-support cell, the genuine `:compile.forms`-shaped path.
  - **Off-diagonal cross-host bytecode is best-effort (Tier-3-flavoured *per cell*).** Emitting a
    *foreign* platform's bytecode — e.g. a JS/Rust-hosted compiler hand-writing JVM `.class` (ADR-0062
    rung **C2**) — is a real but niche capability that carries no support promise even when the *target*
    is Tier 1/2.
  - **`.beam` has no portable writer.** `:compile.forms` does heavy lowering and the `.beam` format is
    not a stable hand-writable spec, so off-BEAM hosts cannot hand-write `.beam` (there is no "C2 for
    BEAM") — BEAM bytecode is produced only on a BEAM. The JVM classfile format, being fully specified,
    is the one bytecode target a foreign host can write at all.

Illustrative matrix (post-portable-self-host; `src` = host-agnostic source emit):

| Compiler host \ target | `.beam` | `.class` | Rust / JS / Kotlin src |
|---|---|---|---|
| **BEAM** | diagonal ✅ (`:compile.forms`) | `src → kotlinc`, or C1 helper | src ✅ |
| **JVM** | needs a BEAM | diagonal ✅ (C3, `java.lang.classfile`) | src ✅ |
| **JS / native** | needs a BEAM | C2 hand-written (best-effort) | src ✅ |

**Orthogonality — do not conflate rung with tier.** The ADR-0062 *rung* (C1/C2/C3) is the *mechanism*
that makes the bytes; the *tier* (this ADR) is the *support contract*. A rung is never a tier: finishing
rung C **+** the citizenship contract is part of what would **promote JVM from Tier 2 → Tier 1** — it is
not itself "Tier 2." Until portable self-hosting lands, the single-host table in §2 is the whole story;
the matrix is the honest shape the moment there is more than one host.

### 3a. The JVM emitter targets Kotlin (landed 2026-06-13)

The Tier-2 JVM emitter (`Rian.JVM`) lowers to **Kotlin source**, not Java. Rian is sum-and-match
oriented, and Kotlin's `sealed interface` + `data class` + smart-cast `is` patterns + expression-`if`
map almost 1:1 — far less boilerplate than Java's pre-Valhalla boxing, and consistent with the
idiomatic-per-target ethos (BEAM/Rust/JS each get their native shape; ADR-0041 already specced sums →
"JVM enum/sealed"). A Rian sum lowers to a sealed hierarchy (`data class Num(val f0: Long): Expr`),
a multi-clause `def` to an `if`-dispatcher with smart-cast binds. A clause whose only condition is a
`when` guard (a variable pattern that binds but tests nothing) lowers to a scoped `run { … }` carrying
the guard as its inner `if` — never an empty `if () { … }`, which is not valid Kotlin. `Int64` →
`Long` (64-bit native, no boxing dance). It is a **source emitter on the typed core IR** (`Core.from_expr`/`from_pat`), the
fourth backend with no new fork (ADR-0050) and the second proof of that thesis after `Rian.JS`.

**Scope (MVP):** functions (single/multi-clause), `Int64`/`Float64`/`Bool`/`String`, operators,
`if`, local calls, `when` guards, and sum variants — verified end-to-end (the `selfhost_opt` optimizer
lowers to Kotlin, compiles with `kotlinc`, and folds correctly under `java`). **`case`** (a labelled
`run rcase@{ … }`), **lists/`Vec`** (`listOf`/cons, with `size`/index/`drop` clause+`case` patterns),
the **`Str`/`Char` codepoint prims**, **`Symbol`/atoms** (→ a Kotlin `String`, ADR-0041), **generic
functions** (`forall T` → `fun <T : Any>`), and **protocols** (a `dispatch: :dispatcher` → a
`when (a0)` over `is <Type>`; bounded-generic consumers call it, ADR-0042), and **lambdas**
(`(a) -> body` → a Kotlin lambda `{ a -> body }`, `Fn(arg…, ret)` → a function type `(arg…) -> ret`,
capturing natively — ADR-0061), **captures** (`&(&1 * 2)` → `{ _1 -> … }`, `&name/arity` →
`::name`), and **tuples** (`{a, b}`/`{a, b, c}` → Kotlin `Pair`/`Triple`, type `(A, B)` →
`Pair<A, B>`, destructured via `componentN()`), and **structs** (`struct Name(f T, …)` →
a Kotlin `data class`, named-arg construction + field access + `is Name` patterns), and
**maps** (`%{k: v}` atom-keyed → `mapOf("k" to v)`, `Dict(K, V)` → `Map<K, V>`, get/put/has)
now lower too. A **`with`** expression desugars to nested `case`s (ADR-0040, shared via
`Core.desugar_with`, so JS gets it too). Still raising
`Rian.JVM.Unsupported` (the next increments): arity-≥4 tuples (use a struct), tagged tuples
(`{:ok, v}` — a Result, BEAM-only), non-atom map keys (BEAM-only), map update (`%{m | …}`),
bitstrings,
general FFI, and a dispatcher returning an associated type (ADR-0074 — no concrete Kotlin return). Per ADR-0026
parity, JVM CI stays **non-blocking** until promoted: CI installs `kotlinc` and runs the JVM
execution tests in a dedicated `continue-on-error` lane (the blocking `mix test.all` gate keeps
`kotlinc` off its PATH, so it stays Tier-1 only). A JVM regression surfaces on CI without failing the
build — promotion to Tier 1 would fold the lane into `test.all`. The `:jvm` tests still self-skip
their executed-output checks when `kotlinc` is absent (local dev without the toolchain).

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

### 5a. Tier-1 admission gate + a target budget (the anti-sprawl rule)

*Added 2026-06-14, from the Gleam/Haxe borrow debate — consensus #3, rated 4/5.*

Haxe's cautionary lesson is not a feature; it is a **failure mode**: ~10 backends with no admission
discipline, so the common std lib frayed toward the lowest common denominator and per-target escape
hatches multiplied until "write once" became marketing. Gleam's counter-discipline (two targets, a
frozen small core) is exactly why its portable surface holds. Rian sits between — and must steer by an
explicit rule, not by momentum:

1. **A target is Tier 1 *iff* the portable-core conformance suite (the ADR-0041 matrix + the tour
   examples) is green on it on every commit.** Greenness is the gate, not a roadmap promise. A target
   that cannot pass the portable core stays Tier 2/3, honestly.
2. **New targets enter at Tier 2 and *graduate* on sustained green**, never the reverse. A Tier-1
   target that regresses the matrix is **demoted**, not waived.
3. **The portable-core contract is frozen-by-default**: widening what "portable" must mean (a new
   prelude op, a new intrinsic) is a deliberate change reviewed against *all* Tier-1 targets at once —
   never a unilateral "add it for the target that's easy."
4. **Target budget.** Adding target N+1 is a decision with a cost (it can only *narrow* the LCD), made
   explicitly — not a default. The current order of business is **self-hosting the Gleam-proven
   BEAM+JS core** (ADR-0063) before widening; **JVM stays Tier 2** under rule 1 (its MVP does not claim
   portable-core parity — lists/maps/FFI raise `Unsupported`), which is the rule working as
   intended, not a gap to paper over.

The proposed/candidate backends — Python (ADR-0071), Swift (ADR-0072), and the **Haxe-style dynamic
triad Lua/PHP/Neko (ADR-0085)** — all enter *under* these four rules, not around them: each is a
Tier-2/3 candidate counted against the target budget, graduates only on sustained green conformance,
and may not widen the frozen portable core. ADR-0085 is the pointed case — it adopts the very targets
this Haxe lesson came from, which is honest **only** because it does so under the gate, not in spite of
it (it borrows Haxe's demonstrated *reach*, refuses Haxe's *sprawl*).

**The gate is mechanized** — `Rian.ConformanceTest` (`test/rian/conformance_test.exs`) compiles and
*runs* the portable-core corpus (`examples/rian/conformance_core.rian` + `14_test_framework.rian`) on
every Tier-1 target (`:ex` via `Rian.Test.run`, `:rs` via `rustc --test`, `:js` via `node --test`) plus
a `reach`-matrix check; a Tier-1 regression fails the build. The corpus is presently **scalar** (`Int53`
arithmetic / `div`-`rem` / comparison / multi-clause recursion + guards): lists/`Vec` + cons patterns and
sum-type `match` are portable on `:ex`/`:js` but have open gaps in the **Rust** `@test`-harness lowering
(duplicate-type / type-mismatch emission), so they are not yet all-Tier-1 green and join the corpus when
that lands. **JVM audit (2026-06-14):** `Rian.JVM` compiles the scalar corpus but raises `Unsupported`
on portable-core lists/maps/structs/strings/FFI (`jvm_test.exs`), so it cannot pass the *full*
portable-core matrix → **Tier 2 by rule 1**, confirmed.

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
| Post-portable-self-host, the contract is a **(host × target) matrix** (§2a): native-bytecode diagonal first-class, cross-host bytecode best-effort, source backends host-agnostic | 5/5 |
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
- **The tier becomes a matrix once portable self-hosting lands** (§2a): the per-target numbers in §2 are
  the single-host (BEAM) projection of a future **(host × target)** contract, whose cells are formalized
  when the compiler first runs off the BEAM. The native-bytecode diagonal is first-class; cross-host
  bytecode is best-effort; source backends are host-agnostic.

## Open items

- **Direct WASM emitter** — when (if) the Rust→`wasm32` path's output size/runtime is unacceptable.
- **JVM value-type story** — boxing vs Project Valhalla value classes for opaque types / ranges
  (ADR-0043/0036) and `Int*` (ADR-0034) on the JVM.
- **ECMAScript module/interop conventions** — ESM vs CJS output; npm interop (the JS analogue of the
  ADR-0026 Hex/rebar3 ecosystem work).
- **Per-tier conformance-matrix contents** — the concrete cross-target test set each tier must pass.
- **Promotion criteria** — what advances a target from Tier 2 → Tier 1 (or Tier 3 → Tier 2).
