# ADR-0067 — Abstract types: zero-cost wrappers with operators and controlled casts

**Status:** Accepted (direction) — unimplemented; gated on the declaration parser + `opaque` lowering (ADR-0043 / ADR-0031 Stage 0.1)
**Extends:** ADR-0043 (opaque types — nominal distinctness over a base, zero-cost). This ADR adds the *operator* and *cast* surface that ADR-0043 deliberately left out.
**Refs:** ADR-0036 (`range` — "representation, not newtype"), ADR-0033 (surface vocabulary), ADR-0035 (no implicit coercion — the constraint), ADR-0041 (per-target representation / observable contract), ADR-0042 (protocols — an abstract may `impl`), ADR-0050 (one typed Core IR — erasure happens in the emitters), ADR-0055 (capability rides the base), ADR-0064 (`Int53`/fixed-width — a candidate to *demote* from compiler-builtin to library abstract)
**Owners:** Maya Lin (emitters / erasure) · Elena Rostova (Rust zero-cost) · Arthur Pendelton (type system) · Samir Patel (totality / coherence) · Kira Neri (no hidden coercion) · Rachel Okafor (PM)
**Origin:** the Gleam/Haxe borrow debate (2026-06-14) — consensus #1, rated **5/5**, the single highest-value mechanism to borrow.

## Context

Rian keeps hand-rolling the same shape: *a type that is just `T` at runtime but is distinct to the
checker.* It appears as at least three separate, unrelated mechanisms today:

- **`Int53`** is a **compiler builtin** with bespoke per-emitter handling (ADR-0064 §2a — JS `number`,
  `i64`/`Long` elsewhere). The compiler special-cases one wrapper type.
- **`opaque T := Base`** (ADR-0043) gives nominal distinctness + a total `T.of(x)` constructor +
  base representation at runtime — but a `Meters` opaque over `Float64` **cannot be added** without
  unwrapping to its base and re-wrapping, because `opaque` defines no operator surface.
- **`range`** (ADR-0036) is "representation, not newtype" — a fourth bespoke variant.

Haxe's **`abstract`** is the proven generalization: a compile-time type over an underlying
representation, with **operator overloading** and **controlled implicit casts**, that **erases** to
the underlying type on every backend at zero runtime cost. Haxe ships this across ~10 targets; the
erasure model is exactly Rian's one-IR-many-emitters thesis (ADR-0050) — the abstraction lives in the
checker, the representation is the base type each emitter already lowers.

ADR-0043 already gave us the hard half (nominal distinctness + zero-cost base representation). What it
*declined* to specify was operators and casts. This ADR adds them, turning `opaque` into a full
abstract — **without** importing Haxe's two mistakes (silent implicit casts everywhere, and abstracts
as a backdoor for `Dynamic`-style escapes), both of which collide with ADR-0035.

## Decision

### 1. `abstract` is `opaque` + an operator/cast surface (one keyword, superset semantics)

`opaque T := Base` stays exactly as ADR-0043 defined it (nominal, zero-cost, `T.of` constructor, no
operators, no casts). `abstract` is the richer form that *adds* declarations:

```rian
abstract Meters := Float64 do
  op +(a Meters, b Meters) Meters       # forwards to the base `+`, emitted on Float64
  op *(a Meters, k Float64) Meters       # scaling: Meters × scalar → Meters
  # casts are explicit and named (ADR-0035): no implicit decay to the base
  to base() Float64                      # `m.base()` exposes the underlying value
end
```

- **Erasure (inherited, made explicit).** A `Meters` is a `Float64` on **every** target at runtime —
  no wrapper, no box (ADR-0043 zero-cost, ADR-0050 the emitters already erase `opaque`). The Core IR
  carries the abstract type for checking; each emitter lowers it to the base it already handles.
- **Operators forward to the base.** A declared `op` lowers to the **base operator on the underlying
  representation** — `m1 + m2` emits exactly `f1 + f2` (the `Float64` `+`) per target. Zero cost,
  and it composes with ADR-0064's per-target integer story for an `abstract … := Int53`.

### 2. Casts are explicit and directional (ADR-0035 is the guardrail)

- **No implicit coercion, in either direction, by default.** A `Meters` does **not** silently become a
  `Float64`, and a `Float64` does **not** silently become a `Meters`. This is the bright line ADR-0035
  draws and the place Haxe over-reached (`@:from`/`@:to` implicit casts are a known footgun source).
- **Construction** is the existing total `T.of(x)` (ADR-0043) — checked, never silent.
- **Exposure** is an explicit, named `to`-cast (`m.base()`), emitting as identity (the value already
  *is* the base at runtime).
- An **implicit** cast may be declared only behind an explicit opt-in marker, and is the rare
  exception, not the default — to be specified separately if a real need (e.g. a literal adopting an
  abstract numeric width) appears. Default abstracts have **no** implicit casts.

### 3. `Int53` and the fixed-width integers become library abstracts (the payoff)

ADR-0064's `Int53` is the motivating case: today it is a **compiler builtin** threaded through every
emitter. As an `abstract Int53 := <per-target integer>` in the portable prelude (ADR-0047), the
per-target representation rule moves out of the compiler and into one library declaration. This is a
**simplification** of ADR-0064, not a new burden — pursued once abstracts land.

## Rationale

- **One mechanism replaces three.** `Int53`-builtin, `opaque`, and `range` collapse toward a single
  `abstract`/`opaque` family. Less compiler surface, fewer special cases.
- **The expensive half is already done.** ADR-0043 proved zero-cost nominal distinctness; this only
  adds the operator/cast layer on top.
- **Haxe is the existence proof** that erased wrappers with operators work across a large target
  matrix — and the cautionary source for *where* to stop (no implicit-cast sprawl).

## Consequences

- **`Rian.Check`** gains operator resolution for abstracts (an `op` declaration adds a typed rule:
  `Meters + Meters → Meters`), and cast checking (only declared casts type-check).
- **Emitters** (`Beam`/`Lower`/`JS`/`JVM`) erase the abstract to its base — most of this is the
  existing `opaque` erasure path (ADR-0050).
- **Capabilities** ride the base unchanged (ADR-0055 default-to-base).
- **Protocols** (ADR-0042): an `abstract` may `impl` a protocol like any nominal type.
- **ADR-0064** can be *simplified* later by demoting `Int53`/fixed-width from builtin to library
  abstracts (tracked as an open item there).

## Open items

- **Operator declaration surface** — exact syntax (`op +(…)`), which operators are eligible, and
  overloading rules (e.g. `Meters * Float64` vs `Meters * Meters`). Must stay within the frozen
  operator table (ADR-0065) — abstracts *reuse* operators, they do not add new tokens.
- **Implicit casts** — whether *any* implicit cast is ever allowed (ADR-0035 leans hard against). The
  literal-width-adoption case (ADR-0064) is the only candidate; resolve with that work.
- **`Int53` demotion** — sequencing the move from builtin to prelude abstract without regressing the
  JS number-mode contract (ADR-0064 §2a).
- **Coherence** — an abstract's `op`/`impl` set is module-scoped; confirm the orphan rule (ADR-0042)
  applies unchanged.
