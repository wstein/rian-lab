# ADR-0066 — Error-propagation sugar: a spelling shootout (not `?`, not `!`)

**Status:** Proposed (design / shootout) · **Option C (bare `<-`) implemented for the BEAM** (2026-06-14)
**Implemented:** partial — bare `<-` propagation on the BEAM (`Rian.Pratt` `desugar_propagation`, `Rian.Beam`; `test/rian/propagation_test.exs`); Option A (`try` inline form) and JS/Rust lowerings not
**Refs:** ADR-0040 (error handling — `Result(T, E)` over typed error sets), ADR-0039 (failable bind `<-` in `with`/`for` headers), ADR-0034 §1 (untyped `?` propagation *removed*), ADR-0032 (`?` is a boolean predicate; borrow surface only from the family), ADR-0035 (no hidden control flow), ADR-0065 (P7 — surface freeze; this operator is *not* yet frozen)
**Owners:** Maya Lin (surface) · Samir Patel (error sets / totality) · Mira (totality) · Kira Neri (honesty) · Rachel Okafor (PM)

## Context

Errors are values (`Result(T, E)` over a **typed error set**, ADR-0040). Composing them today means a
`with` block (ADR-0039): `with {:ok, x} <- f(a), {:ok, y} <- g(x) do … else … end`. That is correct and
exhaustive, but heavy for the common "call a fallible thing, bail on error, keep its error type" case —
the niche a per-call propagation operator fills in Rust (`?`) and Swift (`try`).

ADR-0034 §1 **removed** an untyped `?`: with no `Result`/`Option` to propagate it had nothing to type.
Now the type system exists, so the sugar *can* return — but two hard constraints bound the design:

1. **The error set stays typed at the `pub` boundary (the invariant).** Propagating an error must
   *unify that error into the enclosing function's declared error set* — checked, never an untyped
   escape. A `pub def f(…) T | E` that propagates a `G` is a **compile error** unless `G ⊆ E` (or `E` is
   inferred to include it for a non-`pub`, infer-local function, ADR-0034). Propagation must not punch a
   hole in the error-set discipline that makes "errors are values" checkable.
2. **It must be visible (ADR-0035).** Propagation *is* control flow — an early return on the error
   branch. "What you read is what runs" means the bail-out is spelled at the call site, not hidden in a
   postfix speck. This is a second, independent reason the Rust `?` postfix is a poor fit here.
3. **Not `?`, not `!` (ADR-0032).** `?` is the family's boolean-predicate suffix (`empty?`); `!` is
   reserved. Repurposing either breaks the surface-lineage rule that ADR-0032 exists to protect.

## The shootout

Candidate spellings for "evaluate `e`; if it's an error, return it (after the error-set check); else bind
its success value." Scored against: **visible** (ADR-0035), **family-native** (ADR-0032), **types the
error set** (the invariant — all pass by construction), **reads well composed**.

| # | Spelling | Example | Visible | Family-native | Notes |
|---|---|---|---|---|---|
| A | `try` prefix | `let x = try f(a)` | ✅ keyword, leads the expr | ✅ (Swift/Zig lineage; reads as English) | A leading keyword is unmissable; composes `try g(try f(a))`. **Lead candidate.** |
| B | `use` prefix | `let x = use f(a)` | ✅ | ⚠ `use` is already a keyword (imports, ADR-0033) — overload risk | rejected: keyword collision |
| C | `<-` outside `with` | `x <- f(a)` as a statement | ✅ (operator, leads the bind) | ✅ (reuses ADR-0039's failable bind) | attractive — *no new token* — but `<-` currently means "fail to the `else`/propagate" only inside `with`/`for`; lifting it to a bare statement is the smallest surface delta. **Strong second.** |
| D | postfix word, e.g. `f(a) orelse` | `let x = f(a) orelse` | ⚠ trails (less visible than a prefix) | ⚠ | weaker on visibility (ADR-0035) |
| E | sigil prefix (e.g. `~f(a)`) | — | ✅ | ❌ new punctuation, not family | rejected: violates ADR-0032 surface-lineage |

**Direction (to confirm):** narrow to **A (`try` prefix)** vs **C (bare `<-` bind)**. Both are visible
and family-consistent and type the error set; they differ in token economy (C adds *no* operator, reusing
`<-`) vs readability (A reads as English and nests cleanly). Recommendation: **C as the statement form**
(`x <- f(a)` propagates to the function's error set when outside a `with`), with **A (`try`) as the
inline-expression form** (`g(try f(a))`) where a bind is awkward — they are complementary, not rivals.

**Excluded:** `?` (B-predicate), `!` (reserved). No exceptions — the family surface is the whole point.

## Consequences

- **Checker work (the load-bearing part):** whichever spelling, the propagation site must unify the
  propagated error type into the enclosing function's error set and **fail at the `pub` boundary** if it
  widens it undeclared. This is the same error-set machinery ADR-0040 already uses for `with`/`else`;
  the sugar is a new *surface*, not a new *semantics*.
- **Exhaustiveness/totality preserved (Mira):** propagation is sugar over the `Result` match `with`
  already desugars to; it adds no partiality (the error branch returns, the ok branch binds).
- **Not frozen (ADR-0065):** this operator is explicitly outside the P7 surface freeze until this ADR
  settles its spelling.

## Implementation (option C, the bare `<-` statement — 2026-06-14)

The statement form is implemented and runs on the BEAM: `Rian.Pratt` parses a bare `name <- expr`
statement (outside a `with`) into a `{:bind_arrow, name, expr}`, and `parse_block` **desugars** a block
carrying one into a `Result` `case` — `{:ok, name}` binds and continues; `{:error, e}` short-circuits,
returning `{:error, e}` unchanged. It is pure surface→surface sugar over the same `case` `with` already
produces, so the existing checker/exhaustiveness/BEAM machinery handle it with no new node. Because a
`<-` "binds and continues," a **trailing** `<-` (nothing follows it) is a compile error rather than
silently evaluating its ok branch to `nil` — use `:=` to just return a `Result`. Verified
end-to-end (`test/rian/propagation_test.exs`): a two-step `calc` returns the value when both binds
succeed and propagates the first `{:error, …}` otherwise. **Remaining:** the `try` prefix (option A,
inline form); the **pub-boundary error-set check** (the desugared `case` types the error, but the
explicit "propagated error ⊆ declared `| E`" gate is the checker follow-up); and JS/Rust support
(blocked on those emitters handling atoms/`Result`, an independent limitation).

## Open items

- **Confirm A-vs-C** (or both, as recommended) with a few real fallible pipelines (the self-host
  parser's `Result`-threading is a good corpus).
- **Inferred vs declared error sets** at the boundary: a non-`pub` function infers its set (ADR-0034);
  a `pub` one must *declare* it — propagation tightens the case for requiring `| E` on `pub` fallibles.
- **Interaction with `with`** — once `<-` is a bare statement (C), is `with` still needed, or does it
  become the multi-clause/`else`-handling form only? Likely the latter.
- **Generalized continuation form (Gleam `use`) — spike only, do not commit.** *(2026-06-14
  Gleam/Haxe borrow debate, consensus #5, rated 3/5.)* Gleam's `use x <- f(...)` rewrites the rest of
  the block into a callback passed to `f`, so it generalizes to **any** callback-taking function —
  resource acquisition (`use file <- with_file(...)`), `defer`, iteration — not just `Result`. Our
  bare `<-` (option C) solves only the `Result` slice. The tension the debate surfaced and did **not**
  resolve: `use` is strictly more general, but the early-return-on-error it desugars is **hidden
  control flow** (ADR-0035) unless the continuation is constrained — visible at the call site (it is,
  via the leading `use`), tail-position-only, and with the callback's effect carried in the type.
  Samir argues a typed, restricted form clears ADR-0035; Kira is unconvinced the rewrite is ever
  "what-you-read-is-what-runs." **Action: spike a typed/visible continuation form; keep `<-` as the
  `Result`-only statement; commit nothing until it provably satisfies ADR-0035** (reuses ADR-0039's
  `<-` bind, so no new token either way).
