# ADR-0039 — Reassign `<-` to the family failable-bind/generator; re-spell capability-gated mutation

**Status:** Accepted (direction) · **Prerequisite for:** ADR-0040 (error handling / `with`)
**Refs:** ADR-0032 (collision test), ADR-0033 (vocabulary — *mutation row superseded here*), ADR-0034 §2 (error sets), ADR-0035 (no hidden control flow)
**Owners:** Julian Vance (grammar) · Chloe Bennett (parser) · Arthur Pendelton (compilers) · Rachel Okafor (PM)

## Context

`<-` currently spells **capability-gated mutation** (ADR-0033). But the Elixir/Ruby/Crystal family
spells the **failable bind** in `with`/`for` as `pattern <- source`, and ADR-0034 §2's propagation
form is "a `with`-style form" — which *requires* `<-` as the failable-bind arrow. ADR-0032's
collision test is explicit: a token's meaning goes to what the **family** already gives it, and the
family gives `<-` to generators/`with`. Mutation is the Rian-invented interloper on this token.

The deciding criterion is **silent misreading** (ADR-0035). A reader who sees `pattern <- expr` and
expects a failable generator bind, but gets a *mutation*, has hit a silent semantic trap — the
cardinal sin. Conversely, a `for x in xs` that a reader expected as `for x <- xs` is a
self-announcing, trivial difference. So `<-` must go to the side that prevents the silent trap: the
failable bind. Mutation yields.

This ADR is the prerequisite that unblocks ADR-0040: you cannot spell `with` until `<-` means
failable-bind.

## Decision

1. **`<-` is the failable-bind / generator arrow.** `pattern <- source` in `with` (ADR-0040) and
   future `for`-comprehensions: the match binds and continues, or — on non-match — **short-circuits**
   (propagates the non-matching value). This is the only assignment-like form that carries failable
   control flow.

2. **Capability-gated mutation is re-spelled `<~`** (decided 2026-06-12). Semantics are unchanged
   from ADR-0033 (a single mutation of a capability-permitted binding): single-token, symmetric with
   `:=`, no family collision. (The `set`/`mut` keyword alternatives were considered and rejected —
   see the candidates table.)

3. **Three assignment-shaped forms stay semantically distinct:**

   | Form | Meaning | Can it fail / redirect? |
   |---|---|---|
   | `name [Type] := expr` | single-assignment **binding** | no — total |
   | `name <~ expr` *(proposed)* | capability-gated **mutation** | no — total |
   | `pattern <- source` | **failable bind** inside `with`/`for` | yes — short-circuits |

**Collision test (ADR-0032).** `<-` failable-bind is idiomatic family (Elixir `with`/`for`) ✓. The
new mutation spelling must not collide with an established family meaning — `<~` is unused in the
family ✓; the keyword alternatives (`set`/`mut`) are checked below.

### Mutation-spelling candidates (decided: `<~`)

| Candidate | Pro | Con | Rating |
|---|---|---|---|
| `x <~ expr` | keeps the "marked arrow" identity; single-token, symmetric with `:=`; no family collision | visual confusion with `<-`; sigil soup | **5/5 — CHOSEN** |
| `set x = expr` | greppable; reads as imperative intent; no sigil | introduces `=` (Rian otherwise uses `:=`); keyword cost | 3/5 |
| `mut x = expr` | aligns with capability vocab | `mut` connotes a *capability qualifier*, not an action; Rust-baggage | 2/5 |
| keep `<-` mutation; spell generators `in` only | zero churn to mutation | loses the family-recognizable `with`/`for` `<-`; Arthur's silent-trap risk; defeats ADR-0040 | 1/5 |

## Lowering

- **`<-` failable-bind** → BEAM: native Elixir `<-` in `with`/`for` (1:1). Rust: `match` with early
  `return Err(...)` — exactly the `?` expansion (ADR-0040 §5).
- **mutation** → BEAM: capability-checked rebinding (as ADR-0033). Rust: `let mut` reassignment under
  the binding's capability.

## Consequences

- **ADR-0033's mutation row is superseded** by this ADR; `:=` (binding) is untouched.
- **Unblocks ADR-0040** (`with` propagation).
- **Parser (Stage 0.1)** lexes the new mutation token and accepts `pattern <- source` in clause-header
  position (`with`/`for`).
- **Flow narrowing (ADR-0034 §4):** a `<~`-mutable binding invalidates narrowing (Kotlin `var` rule);
  `:=` bindings preserve it.
- **Examples/specs** using `<-` for mutation are rewritten to the new spelling.

## Open items

- Whether `for`-comprehensions land alongside `with` (ADR-0040) or in a later ADR.
- `for x <- xs` generator collision-free? — yes (the `<-` is now the family arrow), but comprehension
  *syntax* (filters, `into:`) is deferred to the comprehension ADR.
