# ADR-0076 — `__Unknown`: sound gradual typing for the dynamic targets

**Status:** Accepted (direction)
**Implemented:** partial — Phase 1 (the checker rule) shipped (`Rian.Check`,
`test/rian/gradual_test.exs`); Reach-pinning, emitter `any()` lowering, transpiler
integration, and the Dialyzer cross-check are staged below.
**Refs:** ADR-0034 (type-system foundations / `:unknown`), ADR-0040 (`T | E` / error
sets), ADR-0042 (`Fn(…)`), ADR-0057/0058 (target reachability), ADR-0064 (portable
numerics), ADR-0026 (Dialyzer `-spec` emission), ADR-0075 (transpiler inference)

## Context

Two pressures want a *gradual* escape hatch in an otherwise sound, static, four-target
language: (a) the Elixir→Rian porting track (ADR-0075) produces partially-typed drafts
(`_Ty`/`_Ret` holes, ~1085 whole-program `Unk` placeholders) that cannot compile; (b)
typed Rian must interoperate with untyped code on the dynamic targets. The hard
constraint: **do not loosen the compile-time guarantees of fully-typed Rian.**

The Erlang/Elixir literature frames the trade-off precisely. Dialyzer uses *success
typings* — it never false-positives but under-approximates. Gradualizer / eqWAlizer /
etylizer add *gradual* typing, and the Elixir core team states the load-bearing fact:
**"gradual type systems must introduce runtime type checks in order to remain sound."**
TypeScript `any` skips those checks and is **unsound** — it would violate our constraint
by letting an untyped value leak into typed code. TypeScript `unknown` is **sound** — a
value cannot be *used* until it is narrowed.

Key realization: `Rian.Check` is *already* internally gradual — `unify(:unknown, t) → t`
and it *"only reports a provable mismatch."* The static half exists; the missing half is
the discipline that keeps consumption sound.

## Decision

Add **`__Unknown`** as a **sound** gradual "open" type (TypeScript-`unknown`-shaped,
eqWAlizer-aligned), never `any`-shaped:

1. **Assignment *into* is unrestricted** — any value flows into `__Unknown`; it is the
   top for assignment. (`assignable?(_from, "__Unknown") = true`.)
2. **Consumption requires narrowing** — a `__Unknown` value standing where a concrete
   type is required is a type error; it must be narrowed via `case`/pattern first. The
   exhaustiveness gate *forces a wildcard*, which **is** the runtime check the
   programmer writes. This is what keeps fully-typed code sound: the unknown cannot
   reach a typed position unchecked.
3. **The gradual guarantee is the invariant** — a module with **zero** `__Unknown` is
   unchanged: fully static, fully sound, all four targets. `__Unknown` only ever relaxes
   checking *locally* and never alters the typed part's behaviour.
4. **`__Unknown` ⇒ Reach `{:ex, :js}`** (staged, Phase 2) — runtime casts don't exist on
   Rust/JVM, so a signature mentioning `__Unknown` is pinned off `:rs`/`:jvm`, exactly
   like `Int` (ADR-0064). This makes "JS or Ex only" *mechanical* and bars `__Unknown`
   from `@targets`-portable code — the leash.

Surface `__Unknown` (declared openness, a runtime-checked contract) is **distinct** from
internal `:unknown` (inference uncertainty — silent, absorbing, never a contract).

**Lowering:** `__Unknown` erases to `any()` in the BEAM `-spec`/`-type` (already the
`type_form/2` fallback in `Rian.Beam`) and to untyped JS; Rust/JVM never see it (pinned
off by Reach). No auto-cast emission — the narrow's pattern-match is the runtime check.

**Dialyzer** rides along as a free external **second-opinion validator** on emitted BEAM
(specs already emitted, ADR-0026; success typings never false-positive). Independent of
`__Unknown`.

**Deferred:** full set-theoretic types (union/intersection/negation, etylizer-style) —
the correct long-term answer for multi-clause false positives, out of scope here.

## Phases

- **Phase 1 (shipped):** `Rian.Check` — `assignable?(_from, "__Unknown") = true`;
  consumption falls through to the existing mismatch path (sound); narrowing reuses flow
  narrowing + exhaustiveness. `__Unknown` already parses and lowers (`any()` fallback).
- **Phase 2:** `Rian.Reach` — `__Unknown` in a signature adds a blocker killing
  `[:rs, :jvm]`; `@targets(:rs|:jvm)` modules touching `__Unknown` are rejected.
- **Phase 3:** confirm/seal BEAM + JS lowering for `__Unknown`-rich code; JS emitter test.
- **Phase 4:** the transpiler emits `__Unknown` for residual `Unk`/`_Ty` so drafts
  compile-and-run on Ex/JS; `mix rian.transpile` counts `__Unknown` as visible debt.
- **Phase 5:** `mix rian.dialyze` — compile to BEAM and shell out to Dialyzer as an
  external cross-check (the self-host bootstrap oracle).

## Consequences

- A new sound, opt-in dynamic type that gives the JS/Ex targets TypeScript-style openness
  without weakening fully-typed Rian (the gradual guarantee, tested).
- `__Unknown` is the porting track's compile-and-run hatch — but pinned to `{:ex, :js}`
  and surfaced as counted debt, so it can't silently become the permanent default.

## Open items

- Scrutinee narrowing (`case x do %Foo{} -> use(x as Foo)`) — fields narrow today; the
  scrutinee itself does not yet refine. Non-blocking (fields cover the common case).
- The Reach blocker (Phase 2) and the Dialyzer task (Phase 5).
- A proven gradual-guarantee property (zero-`__Unknown` modules lower byte-identically).
