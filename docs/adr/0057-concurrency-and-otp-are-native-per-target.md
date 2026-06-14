# ADR-0057 — Concurrency & OTP are native-per-target; Rian is sequential-logic shared across hosts

**Status:** Accepted (direction) · **Supersedes:** [ADR-0044](0044-otp-behaviours.md) (OTP behaviours as a Rian surface) · **Refines:** [ADR-0031](0031-bootstrap-strategy.md) (sequential-core boundary), [ADR-0026](0026-ecosystem-integration.md) (withdraws the "first-class OTP behaviours in Rian" promise)
**Implemented:** n/a — principle (Rian models no concurrency); enforced negatively by `Rian.Reach`, whose `@conc_erl_fun`/concurrency FFI list pins any `:erlang.spawn`/`send`/… caller to `:ex` (`test/rian/reach_test.exs`)
**Refs:** ADR-0035 (no hidden control flow), ADR-0041 (target model; BEAM-only features), ADR-0042 (protocols — the portable interface concept), ADR-0047 (portable prelude), ADR-0056 (already dormant under this principle)
**Owners:** Maya Lin (architecture) · Elena Rostova (BEAM interop) · Samir Patel (boundary rigor) · Kira Neri (supervision/releases) · Arthur Pendelton (types across the boundary) · Rachel Okafor (PM)

## Context

Rian's purpose is to write **application logic and tests once** and run them on multiple targets
(Elixir/BEAM, ECMAScript, Rust) — the canonical proof is Rian's own lexer/parser running on all
three. The 2026-06-13 goal clarification settled the scope of that shared core and, crucially, where
concurrency lives:

> **Concurrency is native-per-target — and that includes OTP/Elixir.**

This *reverses* ADR-0044, which had made OTP behaviours a first-class **Rian** surface
(`@behaviour(gen_server)` on a `mod`, a checked callback registry, threaded state). Under the
clarified goal that is the wrong layer: OTP — `gen_server`, supervision, `application` — is the BEAM's
**native** concurrency runtime, and you write it in **native Elixir/Erlang**, exactly as you write
async/threads in native Rust and Promises/workers in native JS. Rian does not model, abstract, or
emit any of them.

## Decision

### 1. Rian source is pure sequential logic + tests

A Rian module compiles to a plain module of (effect-tracked, ADR-0048) **sequential** functions on
every target. It contains no concurrency, no supervision, no actor, no OTP behaviour. That is the
whole portable core.

### 2. Concurrency lives in the host, in the host's native language

Processes/tasks/actors, supervision, scheduling, and OTP behaviours are written **natively per
target** and **call Rian-compiled functions** across the ordinary FFI/interop boundary (ADR-0041).
The *state-transition computation* inside a callback may be a shared Rian function; the
callback/behaviour/spawn **scaffolding is native**.

```elixir
# native Elixir — the OTP wiring (NOT Rian)
defmodule Counter do
  use GenServer
  def init(n), do: {:ok, n}
  def handle_cast(:inc, count), do: {:noreply, RianCounter.increment(count)}   # <- shared logic
  def handle_call(:value, _from, count), do: {:reply, count, count}
end
```

```elixir
# shared Rian — the pure transition, also callable from a Rust actor or a JS worker
mod RianCounter do
  pub def increment(count Int64) Int64 := count + 1
end
```

```rust
// native Rust — the same shared logic inside a tokio task (NOT Rian)
tokio::spawn(async move { let next = rian_counter::increment(count); /* … */ });
```

### 3. Rian provides no OTP / behaviour / concurrency surface

There is **no** `@behaviour(name)`, no callback contract registry, no `spawn`/`receive`, no
supervision DSL in the language. The portable *interface* concept Rian does offer is the **protocol**
(ADR-0042), which dispatches on a **type** and is portable — distinct from an OTP behaviour, which
binds a module to a BEAM runtime and is therefore out of scope here.

### 4. The boundary is typed and explicit

Rian functions called from host code expose their signatures (types, error sets, effects — ADR-0034,
ADR-0040, ADR-0048) at the interop seam. The host is responsible for the concurrency contract
(message protocol, supervision strategy, failure semantics); Rian is responsible for the sequential
contract. Neither leaks into the other — "what you read is what runs" holds on both sides
(ADR-0035).

## Rationale

- It is the honest consequence of "share sequential logic + tests": OTP behaviours in Rian source
  would be BEAM-only code in a language whose point is cross-target sharing — they could never run on
  the Rust or JS targets, so they don't belong in the shared layer.
- It removes a large surface (ADR-0044's contract registry, state threading, behaviour emission) for
  **zero loss of capability** — every OTP feature remains available, written where it already is
  idiomatic and battle-tested: native Elixir/Erlang.
- It keeps Rian's compiler small and its core honest. The interop boundary (call a compiled function)
  already exists on every target; concurrency simply sits on the host side of it.
- It dissolves the "ecosystem fracture" worry that motivated ADR-0056 at the root: there is nothing
  to fork, because the concurrent shell was never shared Rian in the first place.

## Ratings

| Decision | Rating |
|---|---|
| Rian source = sequential logic + tests only | 5/5 |
| Concurrency & OTP native-per-target, calling shared Rian functions | 5/5 |
| No `@behaviour`/OTP/concurrency surface in the language | 5/5 |
| Typed, explicit Rian↔host interop boundary | 4/5 |
| OTP behaviours as a first-class Rian surface (ADR-0044) | 1/5 (superseded — wrong layer) |

## Consequences

- **ADR-0044 is superseded.** Its `@behaviour` annotation, OTP contract registry, state-type
  threading, and BEAM-only behaviour emission are **withdrawn** — not implemented. The doc stays as a
  historical record with a supersession banner.
- **ADR-0026's "first-class OTP behaviours" promise is withdrawn** in favour of native interop.
- **ADR-0031** is refined: "concurrency is OTP/actors, BEAM-native" now reads explicitly as *written
  in native Elixir/Erlang*, not expressed in Rian.
- **ADR-0056** (`comptime if target`) stays dormant — this principle is exactly why its motivation is
  thin.
- **No compiler work is added**; a surface is *removed* from the roadmap (the Stage 0.1 behaviour
  parser/checker/emitter is dropped).
- **Docs/examples:** any example showing OTP-in-Rian is reframed as native-host wiring around a shared
  Rian function.

## Open items

- **Interop ergonomics per target** — the idiomatic call shape from Elixir / Rust / JS into a compiled
  Rian module (naming, error-tuple ↔ `Result` ↔ exception mapping at the seam); catalogue with the
  target-model work (ADR-0041).
- **Shared concurrency *logic*** (not runtime) — e.g. a pure state machine a host drives — is already
  expressible as sequential Rian (a `step(state, msg) -> state` function); confirm no further surface
  is wanted.
- **Effect annotations at the boundary** (ADR-0048) — how a Rian function's effect set informs the
  host wrapper (e.g. "this is pure, safe to call in a hot loop").
