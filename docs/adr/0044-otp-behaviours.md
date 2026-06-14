# ADR-0044 — OTP Behaviours: `@behaviour` annotation, checked callbacks, threaded state (BEAM-only)

> ⚠️ **SUPERSEDED (2026-06-13) by [ADR-0057](0057-concurrency-and-otp-are-native-per-target.md).**
> The goal clarification — *Rian shares **sequential** logic + tests; concurrency is native-per-target,
> **including OTP/Elixir*** — moves OTP to the wrong layer for this ADR. OTP behaviours are **not** a
> Rian surface: you write the `gen_server`/supervisor in **native Elixir/Erlang** and call shared
> Rian functions from the callbacks. Everything below (`@behaviour` annotation, callback contract
> registry, state-type threading, BEAM-only behaviour emission) is **withdrawn, not implemented**, and
> kept only as a historical record.

**Status:** ~~Accepted (direction)~~ **Superseded by ADR-0057** · ~~implementation gated on the declaration parser (ADR-0031 Stage 0.1) and the checker~~
**Implemented:** no — superseded by ADR-0057; withdrawn, never implemented
**Refs:** ADR-0026 (first-class OTP behaviours — closes that open item), ADR-0030 (macros are declarative, *not* `use`/injection), ADR-0031 (concurrency is OTP/actors, BEAM-native; non-BEAM = sequential core), ADR-0034 (typed contracts), ADR-0035 (errors are values; no silent drop), ADR-0041 (target model — BEAM-only features), ADR-0042 (protocols — the kin concept)
**Owners:** Maya Lin (architecture) · Arthur Pendelton (contract checking) · Elena Rostova (BEAM/state) · Chloe Bennett (parser) · Samir Patel (contract rigor) · Kira Neri (supervision/releases) · Rachel Okafor (PM)

## Historical record (the withdrawn proposal)

This ADR proposed making **OTP behaviours a first-class Rian surface**: an `@behaviour(gen_server)`
annotation on a `mod`, OTP callbacks written as ordinary `def`s and checked against a built-in
contract registry, a once-declared `State` type threaded across callbacks, and BEAM-only emission of
`-behaviour()` + exports. None of it was implemented.

**Why it was withdrawn ([ADR-0057](0057-concurrency-and-otp-are-native-per-target.md)).** The
2026-06-13 goal clarification fixed Rian's scope as **portable *sequential* logic + tests**, with
**concurrency — including OTP — native-per-target**. That puts OTP on the wrong side of the boundary
for a Rian surface: you write the `gen_server`/supervisor in **native Elixir/Erlang** and call shared
Rian functions from its callbacks. A Rian-level `@behaviour` surface would re-import the very
host-concurrency coupling ADR-0057 keeps out of the shared core.

The one idea that outlived this ADR is the **contract-checking machinery** (verify a set of `def`s
against a required-callback contract), which lands instead as protocol-method checking in
**[ADR-0042](0042-protocol-bounded-generics.md)** — a portable, type-dispatched concept rather than a
BEAM-only module-dispatched one. See ADR-0057 for the accepted concurrency model and ADR-0026 (whose
"first-class OTP behaviours" promise ADR-0057 formally withdraws).
