# ADR-0043 — Opaque Types: module-scoped nominal distinctness over a base, zero-cost

**Status:** Accepted (direction) · implementation gated on the declaration parser (ADR-0031 Stage 0.1)
**Refs:** ADR-0032 (family / concept-borrowing), ADR-0033 (declaration keywords; `alias`), ADR-0034 (nominal types; capabilities × types), ADR-0035 (no implicit coercion), ADR-0041 (target model), ADR-0042 (protocols; orphan-rule escape)
**Generalizes:** ADR-0036's "representation, not newtype" range mechanism
**Owners:** Maya Lin (Scala model/emitters) · Elena Rostova (Rust/zero-cost) · Arthur Pendelton (abstraction boundary) · Marcus Chen (encapsulation) · Samir Patel (exhaustiveness) · Julian Vance (grammar) · Rachel Okafor (PM)

## Context

Three accepted decisions were quietly leaning on a primitive Rian had not named:

- **ADR-0036** chose, for `range`, "lowers to its base primitive … not a wrapper struct" — a
  compile-time-distinct type with base representation at runtime. That *is* an opaque type.
- **ADR-0042** named "wrap the type in an opaque type you own" as the orphan-rule escape hatch.
- **Encapsulation** — `Token`, `Password`, `UserId` distinct from their `Bytes`/`String`/`Int64`
  base — had no mechanism.

The primitive is the **Scala 3 opaque type**: nominally distinct at compile time, base representation
at runtime, zero cost. Per ADR-0032 the *concept* comes from Scala; the *surface* from the family
(own keyword + `:=`, pairing with `alias`).

## Decision

### 1. `opaque Name := Base` — the opaque counterpart of `alias`

```elixir
opaque UserId := Int64
opaque Email  := String
opaque Token  := Bytes
```

A fifth declaration keyword, paired with `alias`: **`alias` is the transparent synonym
(interchangeable with its base); `opaque` is the opaque one (nominally distinct).** Same base, two
encapsulation levels. `Base` may be any single type (primitive, `struct`, …).

| Layer | Keyword | Distinct? | Construction | Finite? |
|---|---|---|---|---|
| transparent synonym | `alias T := Base` | no — interchangeable | none | as base |
| **opaque** | **`opaque T := Base`** | **yes — nominal** | **`T.of(x)` — total** | **as base (not finite over open base)** |
| bounded ordinal | `range T := lo..hi` (ADR-0036) | yes — nominal | `T.of(x)` — fallible (`T \| RangeError`) | **yes — finite signature** |

### 2. Module-scoped transparency (the Scala-3 abstraction boundary)

The abstraction boundary is the **defining module**:

- **Inside** the `mod` that declares `opaque T := Base`: `T` and `Base` are **transparent** —
  interchangeable, base operations usable directly. The implementer writes `a.value + b.value`
  without ceremony.
- **Outside**: `T` is **opaque** — construct with `T.of(x)`, project to base with `.value`. A bare
  `Base` is **not** assignable to a `T` (no implicit coercion, ADR-0035 §5), and vice-versa.

This is what makes opaque types zero-ceremony to *implement* and fully abstract to *consume*.

### 3. No auto-inheritance — operations come from `impl` (ADR-0042)

An opaque type has **no operations** beyond what is explicitly granted via a protocol `impl`.
Auto-inheriting the base's operations is **rejected**: it would let `user_id + order_id` typecheck and
leak the representation, defeating the point. This is the matched pair with ADR-0042 — **`opaque` gives
nominal distinctness, `impl` gives operations**:

> **One principled exception: `range` (ADR-0036).** A `range` is a *numeric/ordinal* opaque type, so it
> exposes its base's ordinal arithmetic — **widening to the base** (`Digit + Digit : Int64`), which
> honestly escapes the bounded representation rather than leaking it, and auto-derives `Comparable`.
> A *general* `opaque T := Base` still inherits nothing.

```elixir
impl Comparable for UserId do
  def compare(a, b) Int64.compare(a.value, b.value)   # transparent inside the defining module
end
```

(A `derives`-style convenience to forward selected base operations is deferred — open items.)

### 4. Opacity is not finiteness

`opaque UserId := Int64` is over an **open** base, so a `case` on a `UserId` still requires a `_` arm —
it is exactly as infinite as `Int64`. **Only `range` (bounded) registers a finite signature** and
reaches exhaustiveness without `_` (ADR-0036). Opacity grants nominal distinctness; it says nothing
about coverage. Construction totality follows the invariant: `UserId.of(42)` is **total** (no
invariant); `Digit.of(n)` is **fallible** (bounds).

### 5. Lowering (per ADR-0041) — distinction erases, representation is the base

| Target | Representation |
|---|---|
| BEAM | the **base term** — compile-time distinction only (an `Int64` is an integer) |
| Rust | **`#[repr(transparent)] struct UserId(i64)`** — real, zero-cost newtype (genuine type safety for FFI/debug) |
| JS | **branded type** (`number & { __brand: "UserId" }`) — compile-time only, bare `number` at runtime |
| Go / JVM | a defined type / wrapper over the base |

**Capability** (ADR-0034 capabilities × types): an opaque type inherits its base's capability
(`opaque Token := Bytes` is `iso`/`ref` as `Bytes` is) — opaque is representation-transparent for
capability purposes. Confirmed default; see open items.

## Ratings

| Decision | Rating |
|---|---|
| `opaque Name := Base` keyword, pairs with `alias` | 5/5 |
| Module-scoped transparency (Scala 3) | 5/5 |
| No auto-inheritance; operations via `impl` | 5/5 |
| `.of` construction (total) / `.value` projection | 4/5 |
| `range` = bounded, finite opaque type (cross-ref ADR-0036) | 5/5 |
| Opacity ≠ finiteness — open base still needs `_` | 5/5 |
| Rust `repr(transparent)` / JS branded / BEAM bare base | 4/5 |
| Opaque = the ADR-0042 orphan-rule escape hatch | 5/5 |
| Auto-inherit base operations | 1/5 (rejected — representation leak) |

## Consequences

- **`range` (ADR-0036) is reframed as a bounded, finite opaque type** — no rewrite of 0036; this ADR
  is its general mechanism. The "representation, not newtype" wording in 0036 *is* opacity.
- **ADR-0042's orphan-rule escape is realized**: you own the opaque type, so you may `impl` an external
  protocol for it.
- **Encapsulation primitive** for `Token`/`Password`/`UserId` — base never leaks; `.value` is the
  single, greppable, auditable unwrap (Marcus).
- **Parser (Stage 0.1):** `opaque Name := Base`; `.of`/`.value` are ordinary dot calls (ADR-0029).
- **Checker:** module-scoped transparency (the boundary is the declaring `mod`); nominal
  non-assignability across the boundary.

## Open items

- **`derives` convenience** — forward selected base operations (`opaque Meters := Float64 derives
  Comparable, Addable`) without hand-writing each `impl`. v1 is explicit `impl`.
- **Capability inheritance** — confirm `opaque T := Base` always inherits `Base`'s capability, and how
  an opaque-over-`struct` interacts with field capabilities (ADR-0034 capabilities × types).
- **`.value` vs an explicit unwrap keyword** — `.value` reads as field access (ADR-0029); confirm it
  does not collide with an opaque-over-`struct` whose base genuinely has a `value` field.
- **Opaque over a generic base** (`opaque Id(T) := Int64`?) — deferred; v1 is opaque over a concrete
  base type.
