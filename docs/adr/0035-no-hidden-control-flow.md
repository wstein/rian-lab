# ADR-0035 — No Hidden Control Flow

**Status:** Accepted · **Refs:** ADR-0032 (concept-borrowing), ADR-0034 (type-system foundations)
**Owners:** Julian Vance (grammar) · Maya Lin (multi-target) · Samir Patel (rigor)
**Borrows the *discipline* of:** Zig (no hidden control flow), Go / V (one obvious way)

## Context

The concept review (Rust/Go/Julia/Kotlin/Crystal/Ruby/Zig/V/Oz/Prolog) asked what would make Rian
*more focused*. Most borrows make a language **bigger**. The one that makes it **smaller** is a
discipline: **what you read is what runs.** It is the only borrow adoptable *today*, before the
type checker, and it constrains every later feature decision.

## Decision

Rian adopts **No Hidden Control Flow** as a standing design principle. Concretely:

1. **No exceptions in the portable core.** Errors are values — `Result(T, E)` over a typed error
   set (ADR-0034). Control does not jump invisibly up the stack. (The BEAM target may still surface
   `FunctionClauseError` for explicitly `@partial` functions; that is opt-in, never silent.)
2. **No hidden allocation on non-GC targets.** On Rust/WASM, allocation is visible in the lowering;
   capability-driven ownership (ADR-0025) governs it. The GC targets (BEAM/JVM/JS) allocate as
   their runtimes do.
3. **No operator-overload surprises.** Operators have fixed, total meanings (the precedence table);
   they are not user-redefinable to run arbitrary code. (`comptime` and macros are the *explicit*
   metaprogramming channels — ADR-0030 — not operators.)
4. **No silent partiality.** A non-total function is a compile error unless marked `@partial`
   (clauses-guards §6). `case` over an open type requires a `_ ->` arm (ADR-0033/0034).
5. **No implicit coercions.** `/` is float division, `div` is integer (expressions spec); promotion
   is explicit. Numeric widths convert only via an explicit cast/annotation.

The litmus test for any future feature: **can a reader predict where control goes and what
allocates, from the source alone?** If not, it does not enter the portable core.

## Rationale

- This is the discipline behind Rian's *existing* best ideas — the exhaustiveness gate, explicit
  `@partial`, `/`-vs-`div`, mandatory signature capabilities. The ADR names the principle they
  already follow, so it stops being re-derived per debate.
- It is what *rejected* the dilutive borrows in the concept review: exceptions (hidden jumps),
  open multiple dispatch (unpredictable target), CSP/coroutine concurrency on top of OTP (two
  control models). Those rejections now trace to one rule.

## Ratings

| Principle | Rating |
|---|---|
| Errors are values; no exceptions in the portable core | 5/5 |
| No hidden allocation on non-GC targets | 5/5 |
| No operator-overload surprises | 5/5 |
| No silent partiality | 5/5 |
| No implicit coercions | 4/5 |

## Consequences

- New-syntax / new-feature proposals must pass the litmus test, recorded in their ADR/PR.
- Pairs with ADR-0034: error sets are *how* "errors are values" is made checkable.
- Reinforces existing decisions (exhaustiveness, `@partial`, `/`-vs-`div`) rather than changing
  them.

## Open items

- **`@partial` on the BEAM** — exact diagnostic (generated raising clause vs. `FunctionClauseError`).
- **Allocation visibility** — how explicit it must be on Rust/WASM at the surface vs. inferred from
  capabilities; settle with the target-model ADR.
