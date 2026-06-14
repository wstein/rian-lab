# ADR-0067 — Abstract types: zero-cost wrappers with operators and controlled casts

**Status:** Accepted (direction) — unimplemented; gated on the declaration parser + `opaque` lowering (ADR-0043 / ADR-0031 Stage 0.1)
**Implemented:** no — design only; gated on `opaque`/`abstract` parsing in `Rian.Decl` (ADR-0043, itself not yet built)
**Extends:** ADR-0043 (opaque types — nominal distinctness over a base, zero-cost). This ADR adds the *operator* and *cast* surface that ADR-0043 deliberately left out.
**Refs:** ADR-0036 (`range` — "representation, not newtype"), ADR-0033 (surface vocabulary), ADR-0035 (no implicit coercion — the constraint), ADR-0041 (per-target representation / observable contract), ADR-0042 (protocols — an abstract may `impl`), ADR-0050 (one typed Core IR — erasure happens in the emitters), ADR-0055 (capability rides the base), ADR-0064 (`Int53`/fixed-width — stays a **builtin**; *not* demotable to an abstract, §3)
**Owners:** Maya Lin (emitters / erasure) · Elena Rostova (Rust zero-cost) · Arthur Pendelton (type system) · Samir Patel (totality / coherence) · Kira Neri (no hidden coercion) · Rachel Okafor (PM)
**Origin:** the Gleam/Haxe borrow debate (2026-06-14) — consensus #1, rated **5/5**, the single highest-value mechanism to borrow.

## Context

Rian keeps hand-rolling the same shape: *a type that is just `T` at runtime but is distinct to the
checker.* It appears as at least three separate, unrelated mechanisms today:

- **`opaque T := Base`** (ADR-0043) gives nominal distinctness + a total `T.of(x)` constructor +
  base representation at runtime — but a `Meters` opaque over `Float64` **cannot be added** without
  unwrapping to its base and re-wrapping, because `opaque` defines no operator surface.
- **`range`** (ADR-0036) is "representation, not newtype" — a second bespoke single-base variant.

(A third builtin, **`Int53`**, *looks* like the same pattern but is **not** unifiable here: it is
per-target — JS `number`, `i64`/`Long` elsewhere (ADR-0064 §2a) — and carries a whole-program JS
number-mode invariant. A single-base erasure cannot express either, so it stays a builtin — §3.)

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
  representation** — `m1 + m2` emits exactly `f1 + f2` (the `Float64` `+`) per target. Zero cost. An
  abstract *over* the builtin `Int53` (`abstract Count := Int53`) is fine — its single base is the
  builtin, whose own per-target lowering is unchanged; that is the opposite of making `Int53` itself
  an abstract (§3).

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

### 3. `Int53` is **not** a library abstract — it stays a builtin (corrected 2026-06-14)

An earlier draft proposed demoting `Int53`/fixed-width integers from compiler builtins to library
abstracts "as the payoff." **That was wrong, and it is withdrawn.** An `abstract` here erases to a
**single** base (`abstract T := Base`, §1) — but `Int53` is exactly the type a single base cannot
express:

1. **`Int53` is per-target, not one base.** It is JS `number`, `i64`/`Long`/native elsewhere (ADR-0064
   §2a). The draft even wrote `abstract Int53 := <per-target integer>` — quietly assuming a *per-target
   base*, a feature §1 does **not** define. Demoting `Int53` first needs **per-target abstract bases** —
   net-new design beyond this ADR.
2. **`Int53` carries a whole-program invariant a type substitution cannot hold.** On JS, BigInt and
   `number` cannot mix, so a *module-wide* number-mode is forced and a module mixing `Int` with
   `Int53` is rejected (`Rian.JS.program_number_mode?` / `reject_mixed_int_mode!`, "a WHOLE-PROGRAM
   decision"). That is cross-function coherence enforced in the emitter — not a property of any one
   type's erasure rule, and a library `abstract` declaration has no way to express it.
3. **The reward is cosmetic; the risk is the numeric subsystem.** The integer model (ADR-0064) is
   built and tested across four emitters + Reach. Demotion buys a *pure simplification* (no new
   capability) while risking that working subsystem. Bad trade.

So the boundary this ADR draws: **abstract types are for single-base zero-cost wrappers** — units,
branded ids, opaque-with-operators. `Int53`'s irreducibly per-target representation *and* its global
number-mode invariant are precisely why it is **not** one, and stays a compiler builtin.

## Rationale

- **One mechanism replaces two.** `opaque` and `range` (both single-base nominal-over-base) collapse
  toward a single `abstract`/`opaque` family. (`Int53` does **not** join them — §3.)
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
- **ADR-0064 is unaffected.** `Int53`/fixed-width stay compiler builtins (§3) — abstract types do not
  touch the numeric subsystem.

## Open items

- **Operator declaration surface** — exact syntax (`op +(…)`), which operators are eligible, and
  overloading rules (e.g. `Meters * Float64` vs `Meters * Meters`). Must stay within the frozen
  operator table (ADR-0065) — abstracts *reuse* operators, they do not add new tokens.
- **Implicit casts** — whether *any* implicit cast is ever allowed (ADR-0035 leans hard against). The
  literal-width-adoption case (ADR-0064) is the only candidate; resolve with that work.
- **Per-target abstract bases (a separate, future ADR — the prerequisite §3 lacks).** An abstract with
  a *different representation per target* (what `Int53` would need) is net-new design beyond this ADR's
  single-base model, and would *additionally* need a way to express a whole-program invariant like JS
  number-mode. Only if that lands — and only if it proves worth the risk to the numeric subsystem —
  could `Int53` demotion be reconsidered. Not planned.
- **Coherence** — an abstract's `op`/`impl` set is module-scoped; confirm the orphan rule (ADR-0042)
  applies unchanged.
