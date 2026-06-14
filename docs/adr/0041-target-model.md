# ADR-0041 — Target Model: per-target representation, observable contracts, module resolution

**Status:** Accepted (direction) · implementation rides the emitters ([`Rian.Lower`](../../lib/rian/lower.ex)) and the declaration parser (ADR-0031 Stage 0.1)
**Implemented:** partial — per-target representation/dispatch lives in the emitters (`Rian.Lower`, `Rian.Beam`, `Rian.JS`, `Rian.JVM`) and reachability in `Rian.Reach` (`test/rian/reach_test.exs`); the model is realized, but the full BEAM-stdlib→target mapping catalogue is incremental and not complete
**Refs:** ADR-0026 (Erlang-native backend), ADR-0029 (dot syntax / symbol resolution), ADR-0032/0033 (atom lowering open item), ADR-0034 §2 (error sets), ADR-0035 (no silent partiality; allocation visibility), ADR-0036 (finite vs open universes), ADR-0037 (`@wire`)
**Owners:** Maya Lin (emitters) · Elena Rostova (Rust/perf) · Chloe Bennett (resolution) · Arthur Pendelton (open/closed universes) · Marcus Chen (contracts) · Kira Neri (determinism) · Liam Davis (JS) · Rachel Okafor (PM)
**Closes:** the atom-lowering open item in ADR-0032/0033, the error-tag representation item in ADR-0034, the Rust symbol-resolution item in ADR-0029, and the allocation-visibility item in ADR-0035 — four open items in one ADR.

## Context

Rian targets **JVM, Rust, Go, BEAM, JS, WASM** (ADR-0026). Several semantic questions were deferred
across four ADRs to "a target-model ADR" that did not exist: how `Symbol`/atoms, error tags, and
allocation lower to **non-atom, non-BEAM** targets, and how the Rust emitter tells a Rian module from
a BEAM-stdlib call (ADR-0029).

The governing precedent is the integer-overflow decision (ADR-0034 §1 / ADR-0035): **native-per-target
representation, a documented and identical *observable* contract, no simulation of one runtime on
another, deeper compatibility via libraries.** This ADR generalizes that stance to the remaining
representation questions. It does **not** enumerate the full BEAM-stdlib→target mapping catalogue
(an incremental table); it fixes the *model*.

> **⚠ The integer application of this stance is superseded by [ADR-0064](0064-portable-numeric-contract.md)
> (P2).** "Native-per-target integer semantics" was judged a portability bug for *integers* specifically:
> they now have portable contracts — `Int` (arbitrary precision) + fixed-width wrap. The model here still
> governs `Symbol`/atoms/allocation/concurrency; only the integer clause moved.

## Decision

### 1. `Symbol` lowers per-target; closed sets are zero-cost (the range/error-set cut, third instance)

A `Symbol` is a native interned **atom** on the BEAM. On other targets it lowers by the same
finite-vs-open cut already used for `range` (ADR-0036) and error sets (ADR-0040):

| Case | Lowering |
|---|---|
| **Closed set** — a sealed `type` of symbol tags, or a `case` the checker proves covers a finite set | a **native enum** (Rust `enum`, JVM `enum`/sealed, Go `const` int, JS small-int/string const). **Zero runtime cost, exhaustive.** |
| **Open `Symbol`** — genuinely unbounded use (already requires `_` in `case`, ADR-0033) | a **`&'static str`** on Rust (no global state, no lock; compare is a memcmp usually settled by length/first byte); interned `String` on JVM, `Symbol.for(s)` or string on JS, string on Go. |
| **Runtime-dynamic symbols** (created from user input at runtime) | a **deterministic id-interner** (source-order or content-hash ids, *never* runtime-random) — the *only* place a global interner appears; reserved for this case, not the default. |

A **uniform global interner on every target (model A)** is rejected: lock/contention, first-touch
allocation, and init-order footguns on Rust, for no observable benefit.

### 2. Observable contracts (what makes per-target representation safe)

- **`Symbol` supports equality only — no portable ordering.** Atom term-ordering on the BEAM is
  implementation-defined (atom-table position) and would not match string/enum ordering elsewhere.
  Equality is total and **identical on every target**; ordering is **not offered**. **Enforced (P9,
  2026-06-14):** `Rian.Reach.symbol_lint!/1` (run inside `gate!`) makes ordering an atom literal
  (`:a < :b`) a **compile error**, not a silent per-target divergence — use `==`/`!=`. (Open-`Symbol`
  representation caveats on Rust — `&'static str`, no global interner — are documented; a finer
  `@targets`-scoped open-vs-closed lint awaits the atom-classification work `Rian.Reach` tracks.)
- **An unmapped BEAM-stdlib call on a non-BEAM target is a compile error, never a silent stub.**
  `:lists.sum` is free FFI on the BEAM; on Rust it maps to a real equivalent or **fails to compile**
  (ADR-0035 no-silent-partiality). A stubbed `:maps.get` returning a default would be a
  correctness/security-grade bug.
- **Interner ids are deterministic per build** (source-order / content-hash), so reproducible builds
  and any serialized symbol are stable across runs (Kira).

### 3. Error tags and sealed sums — closed by construction

Error sets (ADR-0040) and sealed `type` sums are **closed**, so they never reach the open fallback:

| Target | Representation |
|---|---|
| BEAM | tagged tuple — `{:error, :not_found}` / `{:ok, v}` |
| Rust | native `enum` (the discriminated union) |
| JVM | sealed class / `enum` |
| Go | struct with a tag field |
| JS | tagged object `{tag: "...", ...}` |

### 4. Module resolution (closes the ADR-0029 Rust item)

Every qualified call `Mod.fun(...)` resolves to exactly one of three kinds:

1. **Rian-defined module** → emit to the target's module system.
2. **BEAM-stdlib module** (`:lists`, `:maps`, `Enum`, …) → **free FFI on the BEAM**; on non-BEAM,
   resolved via the **std-mapping table** to a target equivalent, **or compile error** if unmapped
   (per §2). Never a silent stub.
3. **Rian prelude** → the portable core stdlib, provided on **every** target (defined in
   [ADR-0047](0047-portable-prelude-stdlib.md)).

### 5. Allocation visibility (consolidates the ADR-0035 item)

On the non-GC targets (Rust/WASM), the allocating builtins are **`String`, `Bytes`, and the open
`Symbol` interner fallback**; all are governed by capabilities (`iso`/`ref`, ADR-0025). GC targets
(BEAM/JVM/JS) allocate as their runtimes do. No new mechanism — the capability model already governs
this; the target model only names the allocating surface.

### 6. `Symbol` on the wire

A `Symbol` is **not directly `@wire`-serializable** (ADR-0037): its representation is not byte-stable
across targets. A symbol crosses a wire boundary only via an **explicit `Symbol ↔ int/string`
mapping** — which is the ADR-0037 "tagged-unions-on-the-wire" open item, now with a stated reason.

## Ratings

| Decision | Rating |
|---|---|
| Closed→enum, open→`&'static str` fallback (native-per-target, optimize provable closed sets) | 5/5 |
| Id-interner only for runtime-dynamic symbols; deterministic ids | 4/5 |
| `Symbol` = equality only, no portable ordering | 5/5 |
| Sealed sums / error tags → tagged union per target | 5/5 |
| Unmapped BEAM-stdlib call = compile error, never stub | 5/5 |
| Module-resolution table (Rian / BEAM-stdlib map-or-error / prelude) | 5/5 |
| `Symbol` not directly wire-serializable; explicit mapping | 4/5 |
| Allocation = capability-governed on Rust/WASM | 5/5 |
| Uniform global interner on every target (model A) | 2/5 (rejected) |

## Consequences

- **Four open items close** (atom lowering in 0032/0033, error-tag rep in 0034, Rust symbol
  resolution in 0029, allocation visibility in 0035). Their ADRs point here.
- The emitters ([`Rian.Lower`](../../lib/rian/lower.ex)) gain: the closed-set→enum path for symbols,
  the `&'static str` open fallback, the module-resolution three-way, and the tagged-union path for
  sealed sums (the latter largely exists for Rust already).
- The checker ([`Rian.Check`](../../lib/rian/check.ex)) supplies the **closed-set proof** for symbols —
  the same finite-signature machinery the exhaustiveness engine already runs (ADR-0036).
- A **conformance test matrix** asserts the *observable* contract (symbol equality identical across
  targets; no ordering; unmapped-stdlib is a compile error) — Samir.

## Open items

- **Std-mapping table contents** — which `:lists`/`:maps`/`Enum`/`String` functions map to which
  Rust/Go/JS/JVM equivalents. A long catalogue, filled incrementally; unmapped = compile error until
  filled (no silent gaps).
- **Runtime-dynamic symbol API** — is creating a `Symbol` from a runtime string even in the portable
  core, or BEAM-only? Decides whether the id-interner ships on non-BEAM targets at all.
- **JVM/Go/JS/WASM emitters do not yet exist** — this ADR is the model they will implement; only
  BEAM and Rust emit today (ADR-0026/0031). The model is target-complete; the emitters are not.
- **`Symbol` display/`inspect`** across targets (atom name vs interned string vs enum variant name).
