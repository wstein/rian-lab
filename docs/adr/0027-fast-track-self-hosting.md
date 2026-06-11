# ADR-0027 — Fast Track to Self-Hosting

**Status:** Accepted; FFI implemented & verified · **Refs:** ADR-0026 (ecosystem)
**Owners:** Chloe Bennett (FFI/host) · Arthur Pendelton (bootstrap) · Maya Lin (subset)
**Implementation:** FFI in `lib/rian/lower.ex` · **Tests:** `test/rian/ffi_test.exs` (6/6)

## Context

We want the Rian compiler written in Rian (self-hosting) as fast as possible. The lever, from
the brief: as a new BEAM language, **FFI is free** — Rian compiles to BEAM modules, so calling
Erlang/Elixir functions is just emitting `Module:function(...)`. So we **do not build a Rian
stdlib yet**; we lean on the target libraries and add only one new primitive: the FFI call.

## Decision

1. **FFI via path-calls; no Rian stdlib (yet).**
   - Lowercase module head = **Erlang module**: `lists::sum(xs)` → `:lists.sum(xs)`.
   - PascalCase head = **Elixir module**: `String::upcase(s)` → `String.upcase(s)`.
   - Bare FFI calls are typed `dynamic`; optional `extern` declarations give precise types for
     hot bindings. FFI is **BEAM-only** (no Rust lowering; flagged by the subset linter).
   - *Verified:* `:lists.sum/reverse`, `String.upcase`, and nested `String.trim(downcase(...))`
     emitted from Rian, compiled, and executed correctly on the BEAM.

2. **Bootstrap stages with a fixpoint check.**
   - **Stage 0** — the Elixir-hosted compiler (current; ~1,900 lines, 88 tests).
   - **Stage 1** — compiler rewritten in the Rian self-hosting subset, compiled by Stage 0.
   - **Stage 2** — Stage 1 compiles its own source; **self-hosting is proven when Stage 1's
     output byte-equals Stage 2's** (the bootstrap fixpoint). Stage 0 is then retired.

3. **Stage 1 needs only the BEAM backend.** The compiler runs on the BEAM, so the Rust backend
   is a feature it *emits*, not a prerequisite to run it. Critical path shrinks accordingly.

4. **Bootstrap in gradual/dynamic mode, tighten later.** FFI returns `dynamic`; write the
   compiler-in-Rian loosely typed first, add `extern` specs and annotations as it stabilizes.

5. **Reuse OTP for compiler plumbing.** File I/O via `:file`/`:io`, codegen via `:compile.forms`
   — all FFI. The compiler-in-Rian needs no bespoke runtime.

6. **No fork** (per ADR-0026). The compiler may stay Elixir-hosted while self-hosting proceeds;
   self-hosting replaces the host with Rian incrementally, module by module.

## Self-hosting subset (what the compiler-in-Rian needs)

| Capability | Status |
|---|---|
| Sum types (`type`) / records (`struct`) | ✅ built (+verified) |
| Pattern matching + guards | ✅ built (+verified checker) |
| `match` expression | ✅ built |
| Recursion (`fn` self-reference) | ✅ built |
| Modules + `pub` | ✅ specced |
| Expressions / operator table | ✅ built (+verified) |
| **FFI to BEAM libs** | ✅ **built this ADR** |
| Lambdas / closures (for `lists:map`, etc.) | ⬜ specced, not lowered |
| `if` / block / `let`-sequencing bodies | ⬜ specced, partial lowering |
| List / map **literals** (construction) | ⬜ patterns done; literals not yet |
| Binaries / strings / maps / lists ops | ✅ via FFI |

**Critical path to Stage 1:** lambdas, `if`/block bodies, and list/map literal *construction*.
With those three plus FFI (done), the existing front-end (parse → typecheck-shape →
exhaustiveness → emit) is expressible in Rian and can compile itself.

## Ratings

| Decision | Rating |
|---|---|
| FFI to target libs; no stdlib yet | 5/5 |
| Bare FFI = dynamic; `extern` for typed bindings | 4/5 |
| Bootstrap stages + fixpoint verification | 5/5 |
| Stage 1 needs only the BEAM backend | 5/5 |
| Bootstrap in gradual mode, tighten later | 4/5 |
| Reuse OTP for I/O + `:compile.forms` | 5/5 |
| Fork anything | 1/5 (reject) |

## Consequences

- Interop is genuinely free: a Rian module is an ordinary BEAM module, callable from `erl`/IEx,
  and Rian calls any Erlang/Elixir MFA with no shim — demonstrated.
- Self-hosting is gated on three remaining language features, not on a stdlib effort.
- `extern` typed-binding syntax and a curated set of Erlang stdlib `extern`s become the seed of
  the eventual Rian stdlib (thin typed wrappers over `lists`/`maps`/`string`).

## Open items
- `extern` declaration syntax and where stdlib bindings live.
- Branch-aware linearity once `if`/`match` bodies lower (FFI args may move `iso` values).
- Decide the Stage-1 emission IR (readable `.erl` first, per ADR-0026).
