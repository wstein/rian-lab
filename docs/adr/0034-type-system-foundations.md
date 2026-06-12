# ADR-0034 — Type-System Foundations: unification, error sets, protocol bounds, flow narrowing

**Status:** Accepted (direction) · implementation gated on the declaration parser (ADR-0031 Stage 0.1)
**Refs:** ADR-0030 (comptime), ADR-0032 (family / concept-borrowing), ADR-0033 (vocabulary), ADR-0035 (no hidden control flow)
**Owners:** Arthur Pendelton (inference) · Elena Rostova (polymorphism) · Maya Lin (multi-target) · Samir Patel (rigor) · Rachel Okafor (PM)

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

Inference is **local, with the signature boundary explicit** (the infer-local / declare-public line
from the defaults and return-inference debates):

- **`pub` functions and multi-clause signature lines: types are mandatory and explicit** — the
  contract is the explicit surface (precise `-spec` per ADR-0026; correct Rust signatures).
- **Private functions, `:=` bindings, and lambda bodies: inferred.** A body edit can't change a
  caller because there is no exported inferred type.

**Integer-literal width:** a bare integer literal defaults to **`Int64`** (ADR-0033 vocabulary);
other widths require an annotation (`n Int32`). Cross-target overflow/precision semantics (BEAM
bignums vs. fixed-width Rust/WASM) is a **target-model** open item, not settled here.

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

- **Structural unions (Crystal) vs. nominal sums.** Rian has nominal sealed sums; Crystal-style
  `Int64 | String` structural unions overlap them. Decide which is canonical (and how flow
  narrowing treats each) — Chloe's dissent from the concept review.
- **Inference algorithm specifics:** classic HM vs. bidirectional checking (the latter pairs better
  with mandatory signatures and gives better error locations).
- **Error-set composition:** how a caller's inferred set unions its callees' sets; declared vs.
  inferred boundaries.
- **Capabilities × types:** how `val`/`iso`/`ref`/`tag` interact with inference and protocol bounds
  (an `iso` returned from a protocol method, etc.).
- **Target model for `Symbol`/error tags and integer overflow** on non-BEAM targets.
