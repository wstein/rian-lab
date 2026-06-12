# ADR-0034 — Type-System Foundations: unification, error sets, protocol bounds, flow narrowing

**Status:** Accepted (direction) · implementation gated on the declaration parser (ADR-0031 Stage 0.1)
**Refs:** ADR-0030 (comptime), ADR-0032 (family / concept-borrowing), ADR-0033 (vocabulary), ADR-0035 (no hidden control flow)
**Owners:** Arthur Pendelton (inference) · Elena Rostova (polymorphism) · Maya Lin (multi-target) · Samir Patel (rigor) · Rachel Okafor (PM)
**Amended 2026-06-12 (decision-lock review):** structural-unions, inference-algorithm, error-set-composition, and integer-overflow open items are **resolved** (see §1, §4, and Open items). The §2 propagation form is decided (`with`) and split into **ADR-0039** (`<-` reassignment) + **ADR-0040** (error handling). §3 (protocol-bounded generics) remains open and gets its own ADR.

## Context

Rian has no type checker yet — it is the single artifact that **four** recent design debates all
dead-end into:

- **default parameter values** need a type to attach to and an integer-literal width;
- **`?` propagation** was removed because, untyped, it has no `Result`/`Option` to propagate;
- **return-type inference** needs an inference engine and an infer-local/declare-public boundary;
- **polymorphism / bounded generics** (`T: Ord`, deferred in types-match §7) need a constraint model.

The concept review (Rust/Go/Julia/Kotlin/Crystal/Ruby/Zig/V/Oz/Prolog) concluded that three of the
most valuable concept-borrows are not features to bolt on — they *are* the type system. This ADR
fixes its **foundations** (direction and shape), so those debates stop being re-litigated. It does
**not** specify the full type theory; that lands incrementally once the declaration parser exists.

ADR-0032 licenses these borrows: they are **concepts**, drawn from wherever they are strongest, and
do not touch the Elixir/Ruby/Crystal surface.

## Decision

Four pillars.

### 1. Inference is unification-based (Prolog), local-by-default

Type inference is built on **unification** (Hindley-Milner / Algorithm W — unification of type
terms is the algorithmic heart, and Prolog is its home). This also unifies two things Rian already
does: **pattern matching is one-way unification at runtime; inference is unification at compile
time** — one idea, two phases.

**Checking strategy: bidirectional** (decision-lock 2026-06-12, resolving the inference-algorithm
open item). Mandatory public signatures (below) are *checked against*; private / `:=` / lambda
holes are *inferred*. Unification stays the solver; bidirectional is the strategy over it — chosen
for better error localization (blame at the checking site, not at a downstream unification failure)
and clean interaction with protocol bounds (§3).

Inference is **local, with the signature boundary explicit** (the infer-local / declare-public line
from the defaults and return-inference debates):

- **`pub` functions and multi-clause signature lines: types are mandatory and explicit** — the
  contract is the explicit surface (precise `-spec` per ADR-0026; correct Rust signatures).
- **Private functions, `:=` bindings, and lambda bodies: inferred.** A body edit can't change a
  caller because there is no exported inferred type.

**Integer-literal width:** a bare integer literal defaults to **`Int64`** (ADR-0033 vocabulary);
other widths require an annotation (`n Int32`). **Overflow/precision is native-per-target**
(decision-lock 2026-06-12): `Int*` types declare representation *intent* / minimum precision, **not
a portable overflow contract**; each target uses its native integer semantics (BEAM bignum promotion;
Rust panic-debug/wrap-release; JVM/Go wrap; JS `BigInt`); Rian does not simulate one runtime on
another. Subrange types (ADR-0036) are the promoted in-domain safety idiom; bit-identical
cross-target arithmetic is an opt-in library. See the ADR-0035 scope clarification.

**Typed bindings — implemented.** A block binding may carry the annotation between the name and
`:=` (`x Int32 := 66`). Per the bidirectional strategy above, the declared type is the expected
type *pushed down* into the value:

- a **numeric literal adopts** the annotation — `x Int32 := 66` gives `x : Int32` (this is the
  "other widths require an annotation" mechanism; a literal takes the declared width). Adoption is
  *same-kind*: an integer literal takes any `Int*`/`UInt*`, a float literal any `Float*`; a
  cross-kind annotation (an integer literal into a `Float`) is **not** adopted — write an explicit
  float literal — and falls through to exact unification;
- an **already-typed RHS must unify exactly** — `x Int32 := someInt64` is a *proven* mismatch and
  is rejected (no implicit narrow/widen; blame is localized at the binding site). An `:unknown`
  RHS is left unchecked (the gate reports only provable clashes).

The binding then carries its **declared** type downstream (display, `-spec`, later checks), not the
inferred one. Every backend **erases** the annotation when lowering — consistent with native-per-target
representation (the value compiles unchanged). Parsed as `{:typed_bind, name, type, expr}`
(`Rian.Pratt`); enforced by `Rian.Check.check_binds/2`. Parametric annotations (`Vec(Int64)`) are
future work.

### 2. Errors are values, typed as error sets (Zig)

There are **no exceptions** in the portable core (ADR-0035). A fallible function returns a
`Result(T, E)` whose **`E` is an error set** — a closed sum of error tags, *inferred* from the
body or *declared*. This makes:

- `case` over a result **exhaustively checkable** (`{:ok, v} -> … | {:error, NotFound} -> … |
  {:error, Timeout} -> …` with the gate proving totality over the error set), and
- a **future propagation form sound** — the reason `?` was removed (ADR-0032) was that, untyped, it
  had nothing to propagate. A typed error set is that missing foundation. Whether propagation
  returns as `?` (no — family uses `?` for predicates) or a `with`-style form is a later, *now
  answerable*, question.

Error sets are a sum type, so they lower to every target (no exception machinery required).

### 3. Bounded polymorphism via protocols (Rust traits, Elixir-protocol surface)

Parametric generics gain **bounds through protocols** — the family-idiomatic spelling of a
typeclass/trait (Elixir protocols *are* typeclasses). `T` bounded by a protocol (`Comparable`,
`Hashable`) may use that protocol's operations. Protocols are **opted into per type**, so — unlike
Julia's open multiple dispatch — they **do not break exhaustiveness/totality** (the reason multiple
dispatch was rejected). This fills the `T: Ord` gap deferred in types-match §7.

### 4. Flow narrowing (Kotlin smart-casts)

After a `case` arm or a guard narrows a union/`Option`/result, the binding's type is **refined for
that branch** — no re-annotation, no re-match. This is a property of the checker, not a separate
feature; it rides along with pillars 1–2.

Narrowing is **robust under Rian's single-assignment `:=`**: a `:=` binding cannot be reassigned, so
a narrowing established in a branch cannot be silently invalidated by later mutation — the Kotlin
smart-cast failure mode does not occur. A `<~`-mutable binding (ADR-0039) *does* invalidate
narrowing, exactly as Kotlin invalidates a smart-cast on `var` reassignment.

### Folded-in rules

- **Open-type exhaustiveness (from ADR-0033):** `case` on an open type (`Symbol`, `Int64`,
  `String`) requires a `_ ->` catch-all; sealed `type` sums reach totality by coverage.

## Ratings

| Decision | Rating |
|---|---|
| Unification-based inference | 5/5 |
| Local inference, explicit `pub`/signature boundary | 5/5 |
| Typed error sets; errors-as-values; no exceptions | 5/5 |
| Protocol-bounded generics (opted-in, totality-safe) | 4/5 |
| Flow narrowing | 3/5 (rides with the checker) |
| Default integer literal = `Int64` | 4/5 (overflow semantics deferred) |
| Open multiple dispatch (rejected — breaks totality) | 1/5 |

## Consequences

- **`?`/propagation becomes answerable** once error sets exist — revisit with a family-correct
  spelling (not `?`).
- **Return-type inference** is admitted *for private functions only*; `pub` stays explicit.
- **Constant default parameter values** become typeable (their type is read off the constant).
- **Precise `-spec` emission** (ADR-0026) is preserved because public signatures stay explicit.
- The checker's **implementation is sequenced after the declaration parser** (ADR-0031 Stage 0.1);
  this ADR is the design it implements.

## Open items

**Resolved in the 2026-06-12 decision-lock review:**

- **Structural unions vs. nominal sums → nominal is canonical.** Untagged structural unions are
  *not* a general user-facing type former. `T | E` in **return position** is sugar for the tagged
  `Result(T, E)` / error-set union (§2, ADR-0040); `|` is **not** general union syntax. Flow
  narrowing (§4) narrows the *nominal* variants. (Closes Chloe's dissent.)
- **Inference algorithm → bidirectional** over a unification solver (§1).
- **Error-set composition → infer-local / declare-public union** (full surface in ADR-0040):
  private functions infer `E = ⋃ propagated callees' sets − handled`; `pub` functions declare `E`
  explicitly and the body's inferred set must be ⊆ the declared set.
- **Integer overflow → native-per-target** (no cross-target simulation): `Int*` declares
  representation intent / minimum precision, not a portable overflow contract; subrange types
  (ADR-0036) are the in-domain safety idiom; deeper compat is an opt-in library. See §1 and ADR-0035.

**Still open:**

- ~~**Protocol/generics surface** (§3) — type-variable introduction site, `protocol` declaration form,
  and the bound spelling (which collides with the `when` *guard* keyword).~~ **Resolved by
  [ADR-0042](0042-protocol-bounded-generics.md):** `forall T: Bound` binder (Crystal), `protocol`/`impl`
  declarations, Rust orphan rule, static-by-default dispatch; the `when` collision dissolves. **All four
  §-pillars are now design-complete.**
- **Capabilities × types:** how `val`/`iso`/`ref`/`tag` interact with inference and protocol bounds
  (an `iso` returned from a protocol method, etc.).
- ~~**Target model for `Symbol` / error-tag representation** on non-atom targets (JVM/Go/JS/WASM).~~
  **Resolved by [ADR-0041](0041-target-model.md):** error tags are closed sums → tagged union per
  target; `Symbol` lowers closed→enum / open→`&'static str`, equality-only.
