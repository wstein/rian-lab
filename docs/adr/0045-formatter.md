# ADR-0045 — Formatter: one canonical zero-config style, comment-preserving, deterministic

**Status:** Accepted (direction) · implementation rides the lexer/parser ([`Rian.Lexer`](../../lib/rian/lexer.ex) / [`Rian.Decl`](../../lib/rian/decl.ex)) plus a comment-preserving CST
**Refs:** ADR-0035 (one obvious way; no hidden control flow as a *discipline*), ADR-0038 (LSP — closes its formatter-ownership open item), ADR-0026 (toolchain / CI parity), ADR-0032/0033 (family surface)
**Owners:** Liam Davis (conventions) · Kira Neri (CI/determinism) · Julian Vance (style rules / CST) · Chloe Bennett (parser) · Samir Patel (invariants) · Maya Lin (LSP integration) · Rachel Okafor (PM)

## Context

ADR-0038 left open "is there a canonical Rian formatting style yet to back `lsp/formatting`?" Family
languages live or die on an opinionated formatter (Go `gofmt`, Elixir `mix format`, Rust `rustfmt`).
The governing decision is **how much style is configurable** — and for a young language, the answer
that ends style fragmentation before it starts is **none**.

## Decision

### 1. One canonical style, zero config (the `gofmt` model)

There is **exactly one** Rian formatting style and **no style configuration**. A single style ends
every formatting debate permanently, guarantees ecosystem consistency, and is the "one obvious way"
discipline (ADR-0035 / Go-V) applied to layout. **Line width is fixed, not configurable.** The
configurable-formatter model (`rustfmt`) is **rejected** — it fragments the ecosystem into style
camps and makes "formatted" ambiguous (so the CI gate below is worth less).

### 2. `rian fmt` + `--check`; the LSP delegates to it

- `rian fmt` rewrites files in place; `rian fmt --check` exits non-zero on any unformatted file — a
  **deterministic CI gate** (same input → same bytes, every platform, every run; Kira).
- ADR-0038's `lsp/formatting` and format-on-save **delegate** to this formatter. The formatter is the
  **canonical owner**; the LSP is a consumer. (Closes the ADR-0038 formatter-ownership open item.)
- Built on the **same lexer/parser** as the compiler (ADR-0038's "tolerant layer over the compiler
  library") — not a second parser.

### 3. Comment-preserving CST (the enabling requirement)

The formatter consumes a **concrete syntax tree that attaches comments (and trivia) to nodes**, not
the compiler's trivia-dropping AST. A formatter that loses comments is dead on arrival; the CST is
part of this ADR's deliverable.

### 4. Invariants (the formatter's correctness spec)

- **Idempotence:** `fmt(fmt(x)) == fmt(x)`.
- **Semantic preservation:** `parse(fmt(x)) ≡ parse(x)` — formatting never changes meaning.

Both are property tests (Samir); together they *are* the formatter's correctness specification.

### 5. v1 style rules (family-aligned; numbers tunable, principle fixed)

- **2-space indentation.**
- **`do … end`** blocks (not brace/inline) for multi-statement bodies.
- **~98-column** soft wrap.
- **Pipe chains** `|>` break **one per line** when wrapped.
- **Trailing comma** in multiline collection/argument literals.
- snake_case values / PascalCase types are *lexical* (ADR-0033), not the formatter's job; it does not
  rename.

## Ratings

| Decision | Rating |
|---|---|
| One canonical style, zero config (`gofmt`); fixed line width | 5/5 |
| `rian fmt` + `--check` CI gate; LSP delegates | 5/5 |
| Comment-preserving CST (deliverable) | 4/5 |
| Idempotence + semantic-preservation property tests | 5/5 |
| v1 rules (2-space, `do…end`, ~98-col, pipe-per-line, trailing comma) | 4/5 |
| Configurable style (`rustfmt` model) | 1/5 (rejected — fragmentation) |

## Consequences

- **Closes the ADR-0038 formatter-ownership open item;** `lsp/formatting` has a canonical backend.
- **New deliverable: a comment-preserving CST** over the existing lexer/parser — also useful to the
  LSP's tolerant analysis (ADR-0038).
- **CI parity (ADR-0026):** `rian fmt --check` is a deterministic, cross-platform gate Kira can wire
  into the build.
- Pairs with the future packaging work (ADR-0031): `rian fmt` ships in the self-contained escript.

## Open items

- **Exact line width and a few wrap heuristics** — `98` is a starting point; lock against a corpus.
- **Comment attachment rules** — leading vs trailing vs floating comments, and blank-line
  normalization (how many blank lines are preserved between defs).
- **Format-on-save granularity in the LSP** — whole-file only, or range formatting (ADR-0038 Tier).
- **Magic trailing comma** (Black/Prettier-style: a trailing comma forces a multiline expansion) —
  adopt or not.
