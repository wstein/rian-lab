# ADR-0042 — Protocol-Bounded Generics: `forall` binders, `protocol`/`impl`, coherence, static-by-default dispatch

**Status:** Accepted (direction) · implementation gated on the declaration parser (ADR-0031 Stage 0.1) and the checker ([`Rian.Check`](../../lib/rian/check.ex))
**Refs:** ADR-0030 (comptime / monomorphization), ADR-0032 (family / concept-borrowing), ADR-0033 (vocabulary — clean keywords, `when` guards), ADR-0034 §1/§3 (bidirectional checking; protocol direction), ADR-0035 (no hidden control flow), ADR-0041 (target model / per-target dispatch)
**Owners:** Arthur Pendelton (typeclasses/inference) · Elena Rostova (dispatch/coherence) · Maya Lin (two-target lowering) · Chloe Bennett (parser) · Marcus Chen (coherence) · Samir Patel (totality) · Julian Vance (grammar) · Rachel Okafor (PM)
**Implements:** ADR-0034 §3 (the last open pillar) — closes the protocol/generics-surface open item.

## Context

ADR-0034 §3 fixed the *direction*: bounded polymorphism via **protocols** (the Rust-trait *concept*,
the Elixir-protocol *surface*), **opted-in per type**, and **totality-safe** — explicitly chosen over
Julia's open multiple dispatch, which breaks exhaustiveness. What it left open was the **surface**:
how a type variable is introduced, how a bound is spelled (the flagged collision with the `when`
*guard* keyword), and the dispatch/coherence model. This ADR fixes those. Per ADR-0032, the concepts
come from the strongest source (Rust traits + coherence); the surface comes from the family
(Crystal's `forall`, `do…end`).

## Decision

### 1. Type variables are introduced explicitly with `forall` (Crystal)

```elixir
def map(f, xs Vec(T)) Vec(U) forall T, U
```

A name is a **type variable iff it is listed in `forall`**; otherwise it must resolve to a declared
type, or it is an error. This is **family-correct** (Crystal spells generics `def foo(x : T) forall T`)
and closes the only real footgun of the alternative — **implicit-on-first-use**, where a typo'd type
name (`Vec(Usr)` for `Vec(User)`) silently becomes a fresh type variable. Implicit introduction is
**rejected** for that reason and for its order-dependence.

### 2. Bounds ride on `forall` — the `when` collision dissolves

```elixir
def sort(xs Vec(T)) Vec(T) forall T: Comparable
def index(xs Vec(T)) Map(T, Int64) forall T: Comparable + Hashable
```

A bound is written **on the binder**, not in a `when` clause. So a **compile-time type bound** never
appears in `when` position, and **`when` stays purely the runtime value-guard keyword** (`when n > 0`).
This is the same move ADR-0033 used to keep `when` free (choosing the `case` form whose arms are
pattern-led): the construct choice **dissolves** the collision rather than overloading the keyword.

- Multiple bounds on one variable: `T: Comparable + Hashable` (`+` = conjunction).
- Multiple variables, each optionally bounded: `forall T: Comparable, U`.

### 3. `protocol` / `impl` declarations

```elixir
protocol Comparable do
  def compare(a Self, b Self) Order
end

impl Comparable for Int64 do
  def compare(a, b) ... end
end
```

| Aspect | Decision |
|---|---|
| **Protocol** | `protocol Name do <def heads> end` — method *signatures*, no bodies. Clean keyword (ADR-0033 retired `def`-prefixed forms; not Elixir's `defprotocol`). |
| **Impl** | `impl Protocol for Type do <defs> end` — Rust's *concept*, the family's `do…end` *surface*. |
| **Receiver** | `Self` is the implementing type; dispatch is on the **first argument** (the Elixir-protocol convention). |
| **`for` reuse** | `for` after `impl Protocol` is declaration position, never expression position — no ambiguity with comprehension `for` (ADR-0039); pinned in the grammar. |

### 4. Dispatch — static by default, dynamic only when visible (ADR-0035)

Per-target idiomatic, the "same source, two idiomatic shapes" model (ADR-0041):

| Target | Static (type known at the call site) | Dynamic (type erased behind a protocol-typed value) |
|---|---|---|
| **BEAM** | direct call; consolidated protocol dispatch | Elixir protocol runtime dispatch |
| **Rust** | **monomorphized** (the ADR-0030 comptime mechanism) | `dyn`-style vtable |
| **JS** | direct function call | vtable object keyed by the value's runtime tag |

Dispatch is **static where the type is known** — the target is predictable from the source (ADR-0035).
**Dynamic dispatch happens only through an explicitly protocol-typed binding**, so it is never silent.

### 5. Coherence — the Rust orphan rule

`impl P for T` is allowed **only in the module that defines `P` or the module that defines `T`**. This
guarantees **exactly one canonical impl per (protocol, type)** — no last-wins surprises, no ambiguous
dispatch (a correctness and supply-chain hazard, Marcus). The known cost — you cannot impl an
*external* protocol for an *external* type — has a principled escape hatch: **wrap the type in an
opaque type you own** ([ADR-0043](0043-opaque-types.md)).

### 6. Protocols do not reintroduce open dispatch — totality is untouched

A bound `forall T: Comparable` means "`T` has `compare`." It adds **no case-arms**, touches **no
exhaustiveness**. A `case` **never** dispatches on protocol membership. This is precisely why ADR-0034
§3 chose opted-in protocols over Julia's open multiple dispatch, and the reason §3 is totality-safe.
The guarantee is load-bearing and stated verbatim so it is not eroded by a later feature.

## Ratings

| Decision | Rating |
|---|---|
| `forall T, U` explicit binder (Crystal, family-correct) | 5/5 |
| Bounds on `forall`; `when`-collision dissolves | 5/5 |
| `protocol`/`impl … for … do…end`, dispatch on first arg, `Self` | 4/5 |
| Static-by-default dispatch; dynamic only via protocol-typed value | 4/5 |
| Rust orphan rule for coherence; escape via owned opaque type | 4/5 |
| Protocols add no dispatch arms — exhaustiveness untouched | 5/5 |
| Implicit-on-first-use type vars | 1/5 (rejected — typo footgun) |
| Reuse `when` for type bounds | 1/5 (rejected — phase-muddling) |

## Consequences

- **ADR-0034 §3 is design-complete** — all four type-system pillars (unification/bidirectional, error
  sets, protocols, flow narrowing) are now locked.
- **Parser (Stage 0.1):** `forall` clause (with bounds), `protocol`/`impl` declarations, `Self`.
- **Checker:** bidirectional checking (ADR-0034 §1) resolves protocol bounds against the known
  expected type; orphan-rule enforcement at impl sites.
- **Emitters:** monomorphization path (Rust, via ADR-0030 comptime) + protocol runtime dispatch (BEAM);
  the per-target dispatch table lives with ADR-0041.
- **Forward dependency on opaque types** (the orphan-rule escape hatch) — worth doing soon after.

## Open items

- **Associated types** (Rust `type Item`) — deferred to v2; v1 protocols carry methods only.
- **Protocol default methods** (a method with a body in the `protocol`, overridable in `impl`).
- **Protocol-typed values (`dyn`)** — in the portable core, or a per-target capability? Interacts with
  capabilities × types (ADR-0034 open item) and allocation (ADR-0041).
- **Bound on the binder vs the type position** — `forall T: Comparable` is settled; whether an inline
  Scala-style `xs Vec(T: Comparable)` is *also* allowed as sugar is deferred (default: no, one way).
