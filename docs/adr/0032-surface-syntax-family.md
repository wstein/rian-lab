# ADR-0032 — Surface Syntax Belongs to the Elixir/Ruby/Crystal Family

**Status:** Accepted · **Refs:** ADR-0026 (no fork / ecosystem), ADR-0029 (dot syntax), ADR-0031 (bootstrap)
**Owners:** Chloe Bennett (parser) · Julian Vance (grammar) · Maya Lin (architecture/emitters) · Rachel Okafor (PM)
**Corrects framing in:** the spec headers that describe a target as a "superset"

## Context

Rian is a **multi-target** language. The intended backends are **JVM, Rust, Go, BEAM, JS, and
WASM**; Rust and the BEAM are merely the *first two* proof-of-concept targets (ADR-0026). The
front-end (lex → parse → check) is already backend-agnostic, but several recent design questions
— `:`-typed params, default values, `?` propagation, `&` captures, return inference — were argued
*by analogy to whichever PoC target a construct resembles*. That is backwards. Designing the
surface to **read like Rust** (or like the BEAM) privileges today's two backends and risks
importing a target's spelling that will **collide with a different meaning on a future target**:
a postfix `?` taken from Rust reads as optional-chaining to a JS-target user, and as a *predicate
suffix* to anyone from the language family Rian actually belongs to.

Two things were conflated:

1. **Where the surface's family resemblance comes from** — a deliberate aesthetic *lineage*.
2. **What the surface compiles to** — the *backends*.

## Decision

**Rian's surface syntax belongs to the Elixir / Ruby / Crystal family.** That lineage —
`do … end` blocks, `:symbol`/`:atom` literals, `|>`, `<>`, `&`-captures, snake_case values with
PascalCase types/modules, trailing-`?` predicate names — is the chosen *feel*, picked for **human
familiarity**, independent of any backend.

The compilation **targets** (JVM, Rust, Go, BEAM, JS, WASM) are **lowering destinations only**.
Their surface syntax is **not** a source of Rian syntax.

Two rules follow:

- **Borrow *concepts* from anywhere; borrow *surface* only from the family.** Pattern matching
  (ML), reference capabilities (Pony), exhaustiveness (the Rust *idea*) are fine to adopt as
  *semantics*. A *spelling* may enter the surface only if it is idiomatic in Elixir/Ruby/Crystal —
  **never because a target spells something that way**.
- **Collision test for every sigil/keyword.** A token may be added only if (a) its meaning is
  defined by Rian semantics, (b) it has a defined lowering to *every* declared target, and (c) it
  does not clash with an established, *different* meaning the **family itself** already gives that
  token.

### Re-grade of the current surface

| Surface | Family source | Verdict |
|---|---|---|
| `do … end`, `if/else`, `match` | Ruby / Elixir | family-core — keep |
| `:atom`, `:lists.sum` | Ruby symbols / Elixir atoms | family-correct — keep (lowering *atoms* to non-atom targets is a backend concern) |
| `\|>`, `<>` | Elixir | family-correct — keep |
| `&fun/1`, `&(&1 + &2)` | Elixir captures | **family-correct — keep** — an earlier review wrongly flagged `&` as a Rust/Go address-of import; the family spells captures with `&`, and what Rust does with `&` is irrelevant |
| snake_case values, PascalCase types/modules/ctors | Ruby / Elixir / Crystal | family-correct — keep |
| `:=` binding, `<-` mutation | divergence from family `=` | **acceptable** — justified by Rian *semantics* (single-assignment vs. capability-gated mutation), not by a target |
| **`?` postfix propagation** | **Rust / Swift — NOT family** | **violation** — the family spells `?` as a *predicate suffix* (`empty?`, `nil?`, `valid?`); a propagation *operator* both imports a target idiom and preempts the family convention |

## Rationale

- **The family is a lineage, not a backend.** Borrowing the *feel* of Elixir/Ruby/Crystal is a
  concept-borrow (allowed); borrowing `?` from Rust is a target-borrow (forbidden). That
  distinction is the entire decision.
- **Predicate `?` is load-bearing in the family.** Ruby, Elixir, and Crystal all use a trailing
  `?` to name boolean queries (and Crystal uses `arr[i]?` for nilable access). Rian should reserve
  `foo?` for *that*, not spend it on an operator.
- **`&` was mis-judged earlier.** Under a naive "avoid all target collisions" rule it looked
  unsafe (Rust/Go `&` is address-of, JS `&` is bitwise-and). Under the *correct* principle —
  follow the family — `&` captures are exactly Elixir, and the targets' use of `&` does not
  matter. This is the clearest illustration of why the rule is "family-source," not
  "collides-with-no-target."

## Ratings

| Decision | Rating |
|---|---|
| Surface = Elixir/Ruby/Crystal family | 5/5 |
| Targets are lowering destinations only; no target-surface imports | 5/5 |
| Borrow concepts from anywhere; surface only from the family | 5/5 |
| Keep `&`, `:atom`, `\|>`, `<>`, `do…end`, snake/Pascal case | 5/5 |
| Remove/re-spell `?` propagation | 4/5 (remove — the family uses `?` for predicates) |
| "Rust superset" framing in spec headers | 1/5 (reject; rewrite) |

## Consequences

- **`?` propagation is non-conforming and will be removed**, returning `?` to the family's
  predicate-suffix role. Error handling stays in the family idiom Rian already has — tagged
  results (`{:ok, v}` / `{:error, e}`), `match`, and a future `with`-style form — not a
  Rust-style operator. (`?` was added earlier this session; reverting it is the first action
  under this ADR.)
- **`&`, `:atom`/`:lists.sum`, `|>`, `<>`, `do…end`, and snake/Pascal case are reaffirmed** as
  family-correct; earlier doubts about them are withdrawn.
- **Spec headers stop calling any target a "superset."** Expression/clause/type specs read
  "lowers to each target; the surface is family-defined," with an open target list.
- **New-syntax proposals must pass the collision test** and name the family idiom they follow,
  recorded in the proposing ADR/PR.

## Open items

- **Primitive type spelling.** `i64`/`f64`/`str` are Rust/WASM-flavored; Crystal (a family member)
  spells them `Int64`/`Float64`/`String`/`Bool`. Decide the primitive vocabulary against the
  *family*, not against Rust — width-explicit naming stays desirable for cross-target precision;
  the open question is `i64` vs. `Int64`.
- **Atom lowering** to non-atom targets (JVM/Go/JS/WASM) — interned strings / symbols / enums /
  `i32` tags. Belongs in a target-model ADR.
- **`<-` intra-family collision.** Elixir spells generator/`with` clauses `pattern <- source`; if
  Rian adds comprehensions or a `with`-form, `<-` (currently mutation) collides *within* the
  family. Resolve before either lands.
- **Reserve trailing `?`** as a predicate-name affordance (`empty?`) once the lexer is taught to
  treat `?` as a name character rather than an operator.
