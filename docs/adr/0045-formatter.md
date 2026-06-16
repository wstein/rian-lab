# ADR-0045 — Formatter: one canonical zero-config style, comment-preserving, deterministic

**Status:** Accepted · **v1 implemented** as a token-stream pretty-printer over [`Rian.Lexer`](../../lib/rian/lexer.ex) (no second parser, no reparse)
**Implemented:** yes (v1) — [`Rian.Format`](../../lib/rian/format.ex) + [`mix rian.format`](../../lib/mix/tasks/rian.format.ex) (in-place · `--check` · `--stdout`/stdin); invariants are property-tested over the whole `.rian` corpus ([`format_test.exs`](../../test/rian/format_test.exs)). Deferred to a later rung: line-wrapping/soft-wrap, the LSP backend, and the standalone `rian fmt` escript (§5, open items)
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

### 2. `mix rian.format` + `--check`; the LSP delegates to it

- `mix rian.format FILE…` rewrites files in place; `--check` exits non-zero on any unformatted file —
  a **deterministic CI gate** (same input → same bytes, every platform, every run; Kira). `--stdout`
  and `-` (stdin) serve editor/pipe integration. (The standalone `rian fmt` escript ships with the
  packaging work, ADR-0031; the `mix` task is the v1 entry point.)
- ADR-0038's `lsp/formatting` and format-on-save **delegate** to this formatter. The formatter is the
  **canonical owner**; the LSP is a consumer. (Closes the ADR-0038 formatter-ownership open item.)
- Built on the compiler's **own lexer** (`Rian.Lexer`) — not a second parser.

### 3. Token-stream pretty-printer (the enabling mechanism)

The v1 formatter does **not** build a CST and **never reparses**. It consumes the compiler's own
lexer in a **trivia-preserving mode** (`Rian.Lexer.tokenize_trivia/1`) that keeps `{:comment, …}`
tokens at their authored position, uncollapsed `{:nl}` separators (so blank lines survive), and raw
`{:heredoc, …}` tokens. It then re-derives **indentation and intra-line spacing only**, while
**preserving newline placement exactly** (collapsing only blank-line runs).

This is sounder than a CST for v1: because indentation is never tokenized and the compiler depends on
newline *placement*, preserving newlines means the formatter **cannot change meaning by construction**,
and it **degrades gracefully** on any construct the parser doesn't fully model (the tokens pass through
with default spacing) — a CST would have to model every node. The cost is that v1 does not *reflow*
lines (no soft-wrap); see §5. A comment-attaching CST remains the right substrate **if/when** line
wrapping is added.

### 4. Invariants (the formatter's correctness spec)

- **Idempotence:** `fmt(fmt(x)) == fmt(x)`.
- **Semantic preservation**, in the concrete form the token-stream design makes checkable:
  **re-lex equivalence** — `tokenize(fmt(x)) == tokenize(x)`. Equal compiler-token streams ⇒ same
  program (the analog of `Rian.FormsEquiv` for the BEAM backend).
- **Comment fidelity:** every comment survives at its authored position; heredocs are reproduced
  verbatim.

All three are property-tested over every `examples/rian/*` and `compiler/*` file
([`format_test.exs`](../../test/rian/format_test.exs)); together they *are* the formatter's correctness
specification.

### 5. v1 style rules (family-aligned; numbers tunable, principle fixed)

Implemented in v1:

- **2-space indentation**, one level per `do`-block / block-form `def` body / open bracket; closer-led
  lines (`end`/`)`/`]`/`}`/`else`/`when`) dedent; operator-led continuation lines (a leading `|`/`|>`)
  and trailing-operator continuations indent one step.
- **One space** around binary operators and after `,`/`;`; **none** after an opener, before a closer,
  around `.`, after a unary `-`/`+`, or inside `f(x)`/`xs[0]`. Map/keyword colons hug the key (`x: 0`);
  atom colons hug the atom (`:lists`).
- **At most one blank line** anywhere; no leading/trailing blank lines; file ends in one newline.
- **Trailing comments** sit two spaces off the code; own-line comments keep their place at context
  indent.
- snake_case values / PascalCase types are *lexical* (ADR-0033), not the formatter's job; it does not
  rename.

Deferred (require line reflow, which v1 does not do — it preserves newline placement):

- **~98-column** soft wrap, **pipe chains** broken one-per-line when wrapped, and **trailing-comma**
  expansion of multiline literals. These need a CST (§3) and are the natural v2 increment.

## Ratings

| Decision | Rating |
|---|---|
| One canonical style, zero config (`gofmt`); fixed line width | 5/5 |
| `mix rian.format` + `--check` CI gate; LSP delegates | 5/5 |
| Token-stream pretty-printer (no reparse; meaning-safe by construction) | 5/5 — v1 mechanism; CST deferred to wrapping |
| Idempotence + re-lex-equivalence + comment-fidelity property tests | 5/5 |
| v1 rules (2-space, `do…end`, spacing, blank-line, comment placement) | 5/5 — shipped |
| Line wrapping (~98-col, pipe-per-line, trailing comma) | deferred to v2 (needs a CST) |
| Configurable style (`rustfmt` model) | 1/5 (rejected — fragmentation) |

## Consequences

- **Closes the ADR-0038 formatter-ownership open item** once the LSP lands; `lsp/formatting` has a
  canonical backend to delegate to (`Rian.Format`).
- **Lexer change (shipped):** `Rian.Lexer` now emits formatter-only trivia in `tokenize_trivia/1`;
  the compiler pipeline is unaffected (`tokenize/1`/`expr_tokens/1` strip comments and map the raw
  heredoc back to `{:str, …}`).
- **CI parity (ADR-0026):** `mix rian.format --check` is a deterministic, cross-platform gate.
- Pairs with the future packaging work (ADR-0031): `rian fmt` will ship in the self-contained escript,
  wrapping the same `Rian.Format`.

## Open items

- **Line wrapping** — soft-wrap width (`~98`), pipe-per-line breaking, and trailing-comma expansion.
  This is the v2 increment and is what motivates building the **comment-attaching CST** (§3); v1
  preserves newline placement and does not reflow.
- **Format-on-save granularity in the LSP** — whole-file only, or range formatting (ADR-0038 Tier).
- **Self-host port** — re-implement `Rian.Format` as `compiler/format.rian` (a pure, JS-reachable
  pass, well suited to the playground); gate on v1 staying green.

## Resolved (v1)

- **Comment attachment** — comments are preserved at their authored token position (trailing comments
  stay on their line, two spaces off the code; own-line comments keep their place). No leading/trailing/
  floating taxonomy is needed because the formatter never moves tokens across newlines.
- **Blank-line normalization** — runs of blank lines collapse to one; leading/trailing blanks trimmed.
