# ADR-0073 — `Foldable`: eager polymorphic reduction over a protocol

**Status:** Accepted · **ELEMENT-GENERIC** via ADR-0074's associated types — the `Int53` pin is retired. Debated 2026-06-15.
**Implemented:** yes (eager) — `Foldable` with an associated `type Elem` (ADR-0074): one `fcount` reduces a `Bag` of `Int53` **and** a `Words` of `String` (`examples/rian/foldable.rian`, `test/rian/prim_test.exs`), running on the BEAM, reach-gated honestly (`[:ex, :js]` for the sum-dispatch consumer), and the Rust lowering rustc-verified (ADR-0074 Stage 3). The **lazy-iterator** surface remains deliberately unimplemented (per Decision §2 — laziness is native-per-target, ADR-0057).
**Refines:** ADR-0047 (portable prelude — Tier 2 over the Tier-1 `List` reducers), ADR-0042 (protocols/impls/bounded generics — the mechanism this rides), ADR-0061 (multi-target protocol lowering — the reach reality below).
**Refs:** ADR-0057 (concurrency/laziness native-per-target — the *principle* for rejecting lazy iterators), ADR-0034 (no `nil`; totality), ADR-0064 (portable `Int53`), ADR-0035 (no hidden control flow), ADR-0000 (honesty: the matrix matches the emitters).
**Owners:** Arthur Pendelton (bounds / dispatch) · Maya Lin (emitters) · Elena Rostova (Rust traits / coherence) · Kira Neri (Reach honesty) · Mira (totality) · Rachel Okafor (PM)

## Context

`prelude_list.rian` (ADR-0047 Tier 1) provides eager reducers — `sum`/`product`/`any`/
`all`/`length` — over a concrete `Vec`. They reach all four targets because a list is
pure cons. The open question (the "iterable-accepting tools" ask): should those reducers
work over *any* container — a user `Bag`, a `Span`, `Dict` values — the way Python's
`sum`/`any`/`all` accept any iterable?

Python answers with a **lazy** duck-typed iterator protocol (`__iter__`). Rian cannot
copy that: laziness has no portable lowering across BEAM `Stream` / Rust `Iterator` / JS
iterators / JVM `Sequence` (ADR-0057 already made laziness's sibling, concurrency,
native-per-target rather than a portable surface). What Rian *can* offer is the **typed,
eager** analogue: a protocol that bridges any container to a concrete list, with the
reducers written once over the protocol.

## Decision

**1. `Foldable` is a one-method protocol that materialises a container's elements.**

```
protocol Foldable do
  def to_list(self Self) Vec(Int53)
end
```

Reducers are written **once** against the bound and dispatch by first-arg type
(ADR-0042): `def fsum(x T) Int53 forall T: Foldable := sum_l(to_list(x))`. One `fsum`
serves `Bag` and `Span`; a non-`Foldable` argument is a compile error (`requires
T: Foldable`).

**2. Eager only — no lazy `Iterator`.** `to_list` materialises. A lazy generator protocol
is **rejected** for the same reason ADR-0057 rejected portable concurrency: laziness is a
per-target *evaluation* concern, not portable sequential *logic*. A portable lazy model
either collapses to eager (pointless) or drags a Stream runtime into each backend. Write
lazy pipelines in the native, target-pinned region instead.

**3. The reducers live in the prelude over `Foldable`, not duplicated per container.**
Tier 1's `List.*` are the concrete folds `to_list` bottoms out in; `Foldable` is the thin
polymorphic layer above them.

## Two honest constraints (and what they cost)

**A. Concrete element today — no associated type.** ADR-0042/0061 protocols are
single-`Self` with **no associated/element type**: `Self` is one concrete type, so
`to_list` must name a concrete element (`Vec(Int53)` here). A fully element-generic
`Foldable(T)` — `to_list(self Self) Vec(Elem)` with `Elem` an associated type — is
**deferred**; it needs a protocol-mechanism extension (associated types or higher-kinded
`Self`). The concrete-element form is the implementable subset and is what ships.

**B. Sum-dispatch reaches `[:ex, :js]`, not Rust/JVM — and that is consistent, not new.**
Dispatching a protocol over **sum types** encodes the constructor tag as a bare atom in
the BEAM/JS dispatcher, which `Rian.Reach` pins off `:rs`/`:jvm` (the `bare atom literal`
blocker, ADR-0061). Measured:

| dispatch over | example | reach |
|---|---|---|
| primitives (`Int53`/`Bool`/`String`) | `Eq`/`Ord`, `contains` | `:ex :rs :js :jvm` |
| **sum types** | `Show`-over-`Expr`, **`Foldable`-over-`Bag`** | `:ex :js` |

So `Foldable` over user sums has **exactly** the reach of the already-shipped
`Show`-over-`Expr` — no better, no worse. The underlying concrete fold (`sum_l`) is
all-target; only the dispatcher gates it. (Closing this — letting the Rust trait path's
sum dispatch count in Reach — is ADR-0061's dispatcher-reach item, out of scope here.)

## Alternatives considered

- **A `fold(self, acc B, combine Fn(B,A)→B)` method** (the Haskell `Foldable`): more
  general, but puts a **higher-order function in the protocol method**, which complicates
  the Rust lowering (closures-as-values) and adds reach risk for little gain over the
  eager `to_list` bridge. Rejected for v1; revisit with the associated-type extension.
- **A lazy `Iterator` protocol** (Python/Rust): rejected — see Decision §2.
- **Duplicate `sum`/`any`/`all` per container type**: rejected — that is the boilerplate
  `Foldable` exists to remove.

## Consequences

- One reducer set, many containers — the eager, typed "iterable-accepting" ergonomic,
  total (each reducer has an empty identity; no `Option`, no crash), bound-enforced.
- Honest portability: all-target when impl'd for primitives; `[:ex, :js]` when impl'd for
  sums (matching `Show`). Documented, reach-gated, not silently degraded.
- A clear, named extension path: associated types unlock element-generic `Foldable(T)`
  and fold over `Dict` values / arbitrary `T` containers.
