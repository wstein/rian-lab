# Rian Language Specification — Pattern Exhaustiveness

**Status:** Locked + reference implementation verified · **Refs:** ADR-0015
**Owner:** Arthur Pendelton (algorithm) · Samir Patel (tests)
**Companion to:** `rian-spec-clauses-guards.md`, `rian-spec-types-match.md`
**Implementation:** `rian_exhaustiveness.ex` · **Tests:** `rian_exhaustiveness_test.exs` (18/18 pass)

This mechanizes the exhaustiveness/reachability *rules* stated in the clause and `match`
specs. It is Maranget's usefulness algorithm (*Warnings for pattern matching*, JFP 2007) —
the same basis as OCaml and Rust.

---

## 1. The reduction

A pattern matrix `P` has one row per clause and one column per scrutinee (for a `match`,
one column; for a multi-clause `fn`, one column per parameter). The **usefulness** predicate
`U(P, q)` asks: *is there a value vector matched by `q` but by no row of `P`?* Everything
reduces to it:

| Diagnostic | Query |
|---|---|
| **Exhaustive?** | `U(P, (_, …, _))` is **false** |
| **Clause i unreachable?** | `U(P₁..ᵢ₋₁, pᵢ)` is **false** |
| **Counterexample** | the witness produced by algorithm `I(P, n)` |

---

## 2. Algorithm `U(P, q)`

Let `q = (q₁ | rest)`.

- **Base** (`q` empty): `U(P, ()) = (P has no rows)`.
- **`q₁` is a constructor `c(r₁..rₐ)`:** `U(P, q) = U(S(c, P), (r₁..rₐ | rest))`.
- **`q₁` is `_`:** let `Σ` be the head constructors in column 1 of `P`.
  - If `Σ` is a **complete signature**:
    `U(P, q) = ⋁_{c ∈ Σ} U(S(c, P), (_^arity(c) | rest))`.
  - If `Σ` is **incomplete**: `U(P, q) = U(D(P), rest)`.

**Specialization `S(c, P)`** — per row:
- `c(r₁..rₐ) | ρ` → `r₁..rₐ | ρ`
- `c'(…) | ρ` with `c' ≠ c` → *dropped*
- `_ | ρ` → `_^arity(c) | ρ`

**Default matrix `D(P)`** — per row: drop rows headed by a constructor; for `_ | ρ`, keep `ρ`.

---

## 3. Witness algorithm `I(P, n)`

Returns a counterexample vector or `none`.

- `n = 0`: `{missing, ()}` if `P` empty, else `none`.
- `n > 0`, `Σ` **complete**: for each `c ∈ Σ`, recurse on `S(c, P)` with width
  `arity(c) + n − 1`; rebuild the head as `c(w₁..wₐ)` from the first `arity(c)` witnesses.
- `n > 0`, `Σ` **incomplete**: recurse on `D(P)` with width `n − 1`; prepend a **missing head**
  — a constructor of the type not present in `Σ` (rendered `_` for infinite/empty `Σ`).

Witnesses over infinite types are intentionally over-general (`_`); this matches OCaml/Rust.

---

## 4. Rian-specific signature rules

These determine when `Σ` is "complete" and are where Rian's earlier decisions pay off:

| Type | Signature | Complete when |
|---|---|---|
| sum type (`type`) | its full sealed variant set | all variants present |
| `bool` | `{true, false}` | both present |
| list | `{nil, cons}` | both present |
| tuple / `struct` | single constructor | the constructor is present |
| `i64` / `f64` / `str` | **infinite** | never — requires `_` |
| map (open) | **infinite** | never — requires `_` (BEAM-only anyway) |

Two consequences locked by prior ADRs:

1. **No integer-range machinery.** Ranges are *guards* (`when x in 1..10`), never patterns,
   so primitives are matched only by literals + `_` and their signature is simply infinite.
   Rian needs none of Rust's range-exhaustiveness complexity.
2. **Guards are excluded.** A guarded clause is refutable, so the matrix `P` is built from
   **unguarded clause patterns only** — for both exhaustiveness and for the "preceding
   clauses" in reachability. A guarded clause cannot cover, and cannot shadow a later clause.
   Pins (`^e`) are lowered to guards before this stage, so they never appear as patterns.

---

## 5. Complexity & notes

Worst-case exponential (shared with all usefulness-based checkers); linear-to-quadratic in
practice. Variables and as-patterns normalize to `_` for coverage. Or-patterns (deferred in
Rian) would expand a row into multiple rows; the matrix operations already handle that shape.
The same engine backs both `fn`-clause groups and `match` expressions (Samir's "one engine,
no second approximation" constraint).

---

## 6. Verified behavior (test matrix — 18/18 passing)

| Scenario | Expected |
|---|---|
| `bool`: `true`, `false` | exhaustive |
| `bool`: `true` only | witness `false` |
| `Option`: `Some(_)`, `None` | exhaustive |
| `Option`: `Some(_)` only | witness `None` |
| `Shape`: `Circle(_)` only | witness `Square(_)` |
| list: `[]`, `[_ \| _]` | exhaustive |
| list: `[]` only | witness `[_ \| _]` |
| list: `[_ \| _]` only | witness `[]` |
| `Tree`: `Leaf`, `Node(Leaf,_,_)` | witness `Node(Node(_, _, _), _, _)` |
| `Tree`: `Leaf`, `Node(_,_,_)` | exhaustive |
| ints: `0`, `1` | witness `_` (infinite) |
| ints: `0`, `1`, `_` | exhaustive |
| guarded `Some(_)` + `None` | non-exhaustive, witness `Some(_)` |
| `_` then `Leaf` | clause 1 unreachable |
| guarded `Some(_)` then `Some(_)` | none unreachable (guard can't shadow) |
| `None` then `None` | clause 1 unreachable |
| 2-arg `(0,0)`, `(_,_)` | exhaustive |
| 2-arg `(0,0)` only | non-exhaustive |

---

## 7. Open items
- Reachability witnesses (which values reach an "unreachable" clause) for richer diagnostics.
- Integration point: run on the typed core IR (clause spec §-IR), after pin/guard lowering.
- Or-pattern row expansion, when/if or-patterns are un-deferred.
