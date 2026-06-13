# ADR-0059 — The join lattice: least-upper-bound for branch/arm types

**Status:** Accepted; **implemented** (numeric LUB + same-constructor covariant join — `Vec`/`Option` — in `Rian.Check.join/2`; the `if`/`case`/list-literal sites consume it). `Result` error-set *union* (§3) is **specified, pending** the checker carrying structured `Result(A,E)` types into inferred type strings — until then a `Result` join falls under the generic covariant rule (equal-or-`:unknown` error component)
**Refs:** ADR-0034 §1 (type-system foundations; the 2026-06-13 lossless-widening amendment that introduced `assignable?`/`num_widens?`), ADR-0033 (Crystal-family numeric vocabulary), ADR-0035 (no hidden control flow — no implicit coercion), ADR-0040 (error sets — the `Result` error component joins by set union), ADR-0042 (protocol bounds will consume this lattice), ADR-0050 (one typed core IR — `node.type` is read by emitters)
**Owners:** Arthur Pendelton (analysis lattice) · Maya Lin (type system / soundness) · Kira Neri (honesty/determinism) · Rachel Okafor (PM)

## Context

The checker (`Rian.Check`) has two distinct operations on types that were being
conflated:

- **Unification** (`unify/2`) — reconcile a *partially inferred* type against a
  *declared* one (`Fn(_, Int64)` vs `Fn(Int64, Int64)`). `:unknown` is a wildcard
  that adopts the other side. This is matching, and it is correct as-is.
- **Join** — combine the types of two **branches that both execute-or-not** into
  the single type of the surrounding expression: the two arms of an `if`, the N
  arms of a `case`, the elements of a list literal.

Today the join sites *borrow* `unify` (`check.ex` `infer(%EIf{})`,
`infer(%ECase{})`, `infer(%EList{})`), so two **different** concrete types
collapse to `:unknown` even when one losslessly contains the other:
`if c do x_Int32 else y_Int64` infers `:unknown`, although a *binding* `n Int64
:= x_Int32` widens fine via `assignable?`. The in-code comment
(`check.ex:231`) flagged this as deliberately deferred "until a least-upper-bound
… is a future ADR item." This is that item.

The amendment already shipped the **partial order** the join needs:
`num_widens?/2` defines `from ⊑ to` ("`from` widens losslessly to `to`"). A join
is just the **least upper bound** over that order. The only real design work is
the cases where the order has *no* upper bound inside Rian's width vocabulary —
the signed/unsigned and int/float "gaps" — which must yield `:unknown`, never a
fabricated wider type.

## Decision

### 1. Join is a separate operation from unification

`Rian.Check.join/2` is introduced. The branch/arm/list-element sites call
`join`, not `unify`. `join` is **commutative** and **associative**, so the N-ary
`case`/list reductions are well-defined regardless of fold order.

The lattice top is `:unknown` and it is **absorbing** for the join:

    join(:unknown, _) = :unknown
    join(_, :unknown) = :unknown

This is the soundness-critical divergence from `unify`. `:unknown` means *"the
checker could not pin this branch down"* — not *"any value."* If one `if` arm is
`Int64` and the other is uninferable, the `if` is **not** soundly `Int64` (the
other arm might be a `String` the checker couldn't read). `unify` would keep
`Int64`; `join` keeps `:unknown`. Because `node.type` is read by emitters for
representation choices (ADR-0050), the join must not over-claim.

`join(t, t) = t`.

### 2. Numeric join — LUB over the `⊑` order

For two numeric types, `join(a, b)` is the **least** `t` with `a ⊑ t` and
`b ⊑ t`, where `⊑` is `num_widens?` (ADR-0034 §1). The vocabulary is the
Crystal-family widths: `Int{8,16,32,64,128}`, `UInt{8,16,32,64,128}`,
`Float{32,64}` (`Int`/`UInt`/`Float` with no width default to `64`/`64`/`64` per
ADR-0033). Concretely:

| `join` | rule | example |
| --- | --- | --- |
| same kind & sign | wider width wins | `Int32 ⊔ Int64 = Int64` · `Float32 ⊔ Float64 = Float64` |
| unsigned ⊔ signed | `UIntₐ ⊔ Int_b` = `Int_c`, `c` = least Int width `> a` and `≥ b` | `UInt8 ⊔ Int8 = Int16` · `UInt32 ⊔ Int32 = Int64` · `UInt64 ⊔ Int64 = Int128` |
| integer ⊔ float | `Intₐ ⊔ Float_b` = least `Float_c ≥ Float_b` with `a-1 ≤ mantissa(c)`; `UIntₐ` uses `a ≤ mantissa(c)` | `Int16 ⊔ Float32 = Float32` · `Int32 ⊔ Float32 = Float64` |
| no representable upper bound | **`:unknown`** | `UInt128 ⊔ Int64` (no Int width `> 128`) · `Int64 ⊔ Float64` (2^63 is not exact in any float — `mantissa` maxes at 53) · `Int128 ⊔ Float64` (likewise) |

The "no representable upper bound" row is the honest gap Maya flagged: the join
**never invents** a width outside the vocabulary, and it never picks a float that
cannot exactly hold the integer (the `mantissa` guard, already in
`float_mantissa/1`). Two operands with no common upper bound resolve to
`:unknown` — the same conservative fallback as today, just reached far less
often. Note the gap bites at the **top** of the towers (`UInt128`, and any
`Int{64,128}`/`UInt{64,128}` joined with a float), not in the common mid-range.

`mantissa(64) = 53`, `mantissa(32) = 24` (exact-integer bits of IEEE-754).

### 3. Sum-type join — covariant, structural, within a constructor

The join recurses **componentwise** for the two parameterized sums Rian's core
relies on:

    join(Option(A), Option(B))      = Option(join(A, B))
    join(Result(A, E), Result(B, F)) = Result(join(A, B), error_union(E, F))
    join(Vec(A), Vec(B))            = Vec(join(A, B))

`Result`'s **error component joins by set union** (ADR-0040 error sets):
`Result(Int64, {Parse}) ⊔ Result(Int64, {IO}) = Result(Int64, {Parse, IO})`.
This is the one place the join *widens* rather than seeking a least element — an
error set is a join-semilattice under `∪` by construction, and a wider error set
is always sound (the caller must still handle every tag).

### 4. No cross-constructor promotion (ADR-0035)

The join does **not** lift across type constructors:
`join(T, Option(T)) = :unknown`, not `Option(T)`. Implicit `Some`-wrapping is
hidden control flow (ADR-0035) — the programmer writes `Some(x)`/`None`
explicitly, so both arms already have constructor `Option(_)` and rule 3 applies.
Likewise two **different nominal sums** (`Shape ⊔ Color`) have no join →
`:unknown`. The lattice only climbs *within* a numeric tower, an error set, or a
shared type constructor.

## Consequences

- **More precise `if`/`case`/list types**, exactly where a binding already
  widens — closes the asymmetry the `check.ex:231` comment documented. That
  comment is replaced with a pointer to this ADR.
- **Protocol bounds (ADR-0042 part 2) build on a real lattice.** A `forall T:
  Ord` dispatch that returns `T` in several arms now has a defined arm-join;
  coherence reasoning does not sit on a missing operation. This was the explicit
  sequencing reason (write E before C) in the 2026-06-13 review.
- **Soundness tightening:** branch joins where one arm is `:unknown` now infer
  `:unknown` instead of silently adopting the other arm's type. This can only
  make `node.type` *less* specific, never wrongly more specific, so no emitter
  that trusted a `node.type` is destabilized.
- **The gaps are explicit, not silent.** `UInt128 ⊔ Int64`, `Int64 ⊔ Float64`,
  and cross-constructor joins resolve to `:unknown` by *rule*, with a test each,
  rather than by accident.

## Not in scope

- **A subtyping relation in declarations.** This lattice governs *inference of
  join points only*. Parameter/return assignability stays `assignable?`
  (directional widening); we are not introducing `Int32 <: Int64` as a general
  subtype with variance everywhere.
- **`Int128`/`UInt128` arithmetic semantics** beyond their place in the order —
  whether the BEAM/Rust/JS targets all carry a native 128-bit integer is an
  emitter question (ADR-0049), not a lattice question.
- **Numeric literal defaulting** — a bare `42`'s adoption of a same-kind
  annotation is `literal_adopts?` (ADR-0034 §1), unchanged.
