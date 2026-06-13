# ADR-0044 — OTP Behaviours: `@behaviour` annotation, checked callbacks, threaded state (BEAM-only)

> ⚠️ **SUPERSEDED (2026-06-13) by [ADR-0057](0057-concurrency-and-otp-are-native-per-target.md).**
> The goal clarification — *Rian shares **sequential** logic + tests; concurrency is native-per-target,
> **including OTP/Elixir*** — moves OTP to the wrong layer for this ADR. OTP behaviours are **not** a
> Rian surface: you write the `gen_server`/supervisor in **native Elixir/Erlang** and call shared
> Rian functions from the callbacks. Everything below (`@behaviour` annotation, callback contract
> registry, state-type threading, BEAM-only behaviour emission) is **withdrawn, not implemented**, and
> kept only as a historical record.

**Status:** ~~Accepted (direction)~~ **Superseded by ADR-0057** · ~~implementation gated on the declaration parser (ADR-0031 Stage 0.1) and the checker~~
**Refs:** ADR-0026 (first-class OTP behaviours — closes that open item), ADR-0030 (macros are declarative, *not* `use`/injection), ADR-0031 (concurrency is OTP/actors, BEAM-native; non-BEAM = sequential core), ADR-0034 (typed contracts), ADR-0035 (errors are values; no silent drop), ADR-0041 (target model — BEAM-only features), ADR-0042 (protocols — the kin concept)
**Owners:** Maya Lin (architecture) · Arthur Pendelton (contract checking) · Elena Rostova (BEAM/state) · Chloe Bennett (parser) · Samir Patel (contract rigor) · Kira Neri (supervision/releases) · Rachel Okafor (PM)

## Context

ADR-0026 promised "OTP behaviours first-class — `gen_server`/`supervisor`/`application` callbacks
emitted with the right `-behaviour()` attribute and exports," but left the *surface* undecided.
Elixir's `use GenServer` is a macro that injects defaults and `@behaviour` — a door **closed** by
ADR-0030 (Rian macros are declarative/hygienic, not `use`/injection). OTP is **BEAM-native** and not
portable (ADR-0031): behaviours are a BEAM-target feature, not part of the portable core.

A behaviour *is* an interface — conceptually kin to a protocol (ADR-0042) — but it binds a whole
**module** and is **BEAM-only**, where a protocol dispatches on a **type** and is **portable**. They
are kept distinct (different dispatch entity, different portability) while **sharing the
contract-checking machinery**.

## Decision

### 1. `@behaviour(name)` annotation on a `mod`

Reuses the existing annotation surface (`@wire`, `@partial`) — maps 1:1 to Erlang `-behaviour(name)`:

```elixir
@behaviour(gen_server)
mod Counter
  type State := Int64                                   # the behaviour's state type, declared once

  def init(start State) {:ok, State}
    {:ok, start}
  end

  def handle_call(:value, from, count State) {:reply, State, State}
    {:reply, count, count}
  end

  def handle_cast(:increment, count State) {:noreply, State}
    {:noreply, count + 1}
  end
end
```

### 2. Callbacks are ordinary `def`s, checked against a built-in contract registry

The checker holds the **OTP callback contracts** (`init/1 :: {:ok, state} | {:stop, reason}`,
`handle_call/3 :: {:reply, reply, state} | {:noreply, state} | {:stop, reason, reply, state} | …`,
etc.) and verifies the module's `def`s satisfy the **required set** with correct arity and shape —
the same checking shape as protocol-method verification (ADR-0042), shared machinery. The emitter
adds `-behaviour(name)` and the required `-export`s. This is what makes behaviours *first-class*: the
contract is **checked**, not merely attributed.

- **v1 registry:** `gen_server`, `supervisor`, `application`.
- Callback return tuples (`{:reply, …}`, `{:noreply, …}`) are tagged sums — native Rian (ADR-0034/0040).

### 3. The state type is declared once and threaded (better than dialyzer-by-convention)

The behaviour's `State` type is declared once and the checker **enforces it across every callback** —
`init` produces it, `handle_call`/`handle_cast`/… thread it. Erlang/Elixir get this only loosely via
`-spec`/dialyzer; Rian enforces it.

### 4. BEAM-only — non-BEAM emit is a compile error

A `@behaviour` module emitted to a non-BEAM target (Rust/Go/JS/WASM) is a **compile error**, never a
silent drop (ADR-0035, ADR-0041). OTP has no portable equivalent to fake; the error names the
BEAM-only dependency.

### 5. Behaviours are kin to protocols but distinct

| | OTP behaviour (this ADR) | Protocol (ADR-0042) |
|---|---|---|
| Implementing entity | a **module** | a **type** |
| Portability | **BEAM-only** | portable (all targets) |
| Declaration | `@behaviour(name)` on a `mod` | `impl P for Type` |
| Contract checking | **shared machinery** | shared machinery |

### 6. Supervision is data, not a DSL (v1)

A supervisor's `init/1` returns child specs + a strategy — expressed with the existing struct/record
surface as ordinary data. No supervision DSL in v1.

## Ratings

| Decision | Rating |
|---|---|
| `@behaviour(gen_server)` annotation (reuse `@wire`/`@partial`) | 5/5 |
| Callbacks = `def`s, checked against a built-in contract registry | 5/5 |
| State type declared once, checked across callbacks | 5/5 |
| Kin to protocols but kept distinct; shared contract-checking | 4/5 |
| BEAM-only; non-BEAM emit = compile error | 5/5 |
| Child specs as data; supervision DSL deferred | 4/5 |
| `use GenServer`-style injection macro | 1/5 (rejected — ADR-0030) |

## Consequences

- **Closes the ADR-0026 OTP-behaviours open item.**
- **Parser (Stage 0.1):** `@behaviour(name)` annotation on `mod` (the `@wire`/`@partial` machinery).
- **Checker:** the OTP contract registry + state-type threading; shares protocol-contract checking.
- **Emitter (BEAM):** `-behaviour()` attribute + required exports; ties to the Erlang-native backend
  cutover (ADR-0031) — behaviour emission is naturally module-level work that targets the
  Erlang-native emitter, not the interim Elixir-source path.

## Open items

- **Custom behaviours** — declaring your own callback set (Erlang `-callback`); maps to the
  protocol-contract machinery, deferred to v2.
- **Supervision DSL** — typed child-spec builders / a `supervisor` sugar over the raw data form.
- **`gen_statem` / `gen_event` / `gen_server` `handle_continue`** — extend the registry beyond the v1
  trio.
- **Hot-code-upgrade callbacks** (`code_change/3`, `format_status`) — registry completeness.
