# ADR-0045 — Formatter: one canonical zero-config style, comment-preserving, deterministic

**Status:** Accepted · **implemented incl. line wrapping** — a bracket-structured lossless CST + a Wadler/Lindig pretty-printer over [`Rian.Lexer`](../../lib/rian/lexer.ex) (no second parser, no reparse)
**Implemented:** yes — [`Rian.Format`](../../lib/rian/format.ex) (engine [`Rian.Format.Doc`](../../lib/rian/format/doc.ex), tree [`Rian.Format.Cst`](../../lib/rian/format/cst.ex)) + [`mix rian.format`](../../lib/mix/tasks/rian.format.ex) (in-place · `--check` · `--diff` · `--stdout`/stdin). **Line wrapping ships**: bracket interiors reflow to a 98-column budget; a **magic trailing comma** keeps a group expanded; and a top-level `:=` body that is an operator chain (full `@cont_ops`) wraps leading-operator, **precedence-aware** (breaks at the loosest level). `format/1` is total (never corrupts on malformed input). Invariants — significant-token equivalence (meaning), parse-still-valid, idempotence, comment fidelity — are asserted over the whole corpus and in a seeded property/fuzz suite. The **LSP formatting + rangeFormatting** backend ([`Rian.LSP.Formatting`](../../lib/rian/lsp/formatting.ex)) and the **`rian fmt` escript** (`Rian.CLI`/`Rian.Format.CLI`) ship; the Doc engine is **self-hosted** in [`compiler/format.rian`](../../compiler/format.rian), fixpoint-locked to `Rian.Format.Doc`. Design note: [`docs/notes/formatter-tier2-design.md`](../notes/formatter-tier2-design.md)
**Refs:** ADR-0035 (one obvious way; no hidden control flow as a *discipline*), ADR-0038 (LSP — closes its formatter-ownership open item), ADR-0026 (toolchain / CI parity), ADR-0032/0033 (family surface), ADR-0077 (the **linter** — the advisory, semantics-aware half; owns what the formatter can't reformat, e.g. an over-long `def` head, until the parser allows wrapping it)
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

### 3. Bracket-structured lossless CST + a Wadler/Lindig pretty-printer (the mechanism)

The formatter **never reparses** (no semantic AST). It runs in three stages:

1. **Lex with trivia** — `Rian.Lexer.tokenize_trivia/1` keeps `{:comment, …}` at their authored
   position, uncollapsed `{:nl}` separators (so blank lines survive), and raw `{:heredoc, …}`.
2. **Bracket-structured lossless CST** — [`Rian.Format.Cst`](../../lib/rian/format/cst.ex) (inspired by
   Rowan / Roslyn / Swift libsyntax) preserves **every** token and nests only on matched
   `( ) · [ ] · { } · %{ }`. `do`/`end` stay flat tokens (block/statement indentation is the line
   skeleton's job). Building is total — an unbalanced opener degrades to a plain token.
3. **Pretty-print** — each logical line is lowered to a document and rendered by
   [`Rian.Format.Doc`](../../lib/rian/format/doc.ex), a Wadler-style algebra
   (`text`/`line`/`softline`/`hardline`/`group`/`nest`/`line_suffix`/`if_break`) with **Lindig's
   linear-time strict renderer** (*Strictly Pretty*, 2000) and Prettier-style break propagation.

The statement/block **skeleton preserves the source's newline placement** (significant newlines →
hardlines); only **bracket interiors reflow**. That split is the safety boundary (§4).

### 4. Invariants (the formatter's correctness spec)

- **Idempotence:** `fmt(fmt(x)) == fmt(x)`.
- **Semantic preservation = significant-token equivalence:** dropping the changes the formatter is
  *allowed* to make — comments, `{:nl}` **inside brackets** (Rian is newline-tolerant there), blank-line
  runs, and a trailing comma before a closer — the remaining token stream is **identical**.
  `Rian.Decl.detokenize` is whitespace-invariant and the parser accepts those exact changes, so equal
  significant streams ⇒ same parse. (This supersedes the earlier *re-lex equivalence*, which a reflowing
  formatter cannot satisfy — reflow moves newlines; it is the analog of `Rian.FormsEquiv` for BEAM.)
- **Comment fidelity:** every comment survives at its authored position; heredocs reproduced verbatim.
- **Totality:** `format/1` never raises; unlexable input is returned unchanged.

All four are asserted over every `examples/rian/*` and `compiler/*` file and in a seeded property/fuzz
suite ([`format_test.exs`](../../test/rian/format_test.exs),
[`format_property_test.exs`](../../test/rian/format_property_test.exs)); together they *are* the
formatter's correctness specification.

### 5. Style rules (family-aligned; numbers tunable, principle fixed)

- **2-space indentation**, one level per `do`-block / block-form `def` body; closer-led lines
  (`end`/`else`/`when`) dedent; operator-led continuation lines (a leading `|`) and trailing-operator
  continuations indent one step.
- **One space** around binary operators and after `,`/`;`; **none** after an opener, before a closer,
  around `.`, after a unary `-`/`+`, or inside `f(x)`/`xs[0]`. Map/keyword colons hug the key (`x: 0`);
  atom colons hug the atom (`:lists`).
- **Line wrapping (98 columns):** a bracket interior (call args, list/map/tuple, parenthesized expr)
  **collapses onto one line when it fits**, else **breaks one item per line** with a hanging indent and
  an `if_break` **trailing comma**; an already-multiline literal that now fits is collapsed. A comment
  inside a bracket forces a full break. **Declaration heads never reflow** (`def` params / `when`
  guards) — `Rian.Decl`'s head parser is not newline-tolerant inside its parens — so wrapping is
  confined to the body zone (after the top-level `:=`, or in non-declaration lines).
- **Magic trailing comma:** a trailing comma the author leaves before a closer keeps the group expanded
  even when it would fit (Black/Prettier). Idempotent (a broken group re-emits its comma); cons groups
  are exempt (they can't carry one).
- **Operator-chain wrapping (depth-0 continuation):** a top-level `:=` body that is a flat operator
  chain **collapses when it fits**, else breaks **leading-operator, one stage per line** with a
  one-level hanging indent. Covers the full `Rian.Decl` `@cont_ops` set — the operators the parser
  treats as newline-insignificant in a `:=` body (`take_line`, P1), so breaking before one is
  meaning-safe — and is **precedence-aware**: a chain breaks only at its **loosest** level, so
  `a * b + c` breaks at `+` and keeps `a * b` intact. Confined to **declaration bodies** — a
  block-internal bind's newline becomes a `;` (`detok_block`), so those chains are left intact. A merge
  pass rejoins a source-multiline chain into one unit before deciding, which makes wrapping idempotent.
  `|` (cons/sum) is excluded.
- **At most one blank line** anywhere; no leading/trailing blanks; file ends in one newline. Trailing
  comments sit two spaces off the code; own-line comments keep their place at context indent.
- snake_case values / PascalCase types are *lexical* (ADR-0033), not the formatter's job.

## Ratings

| Decision | Rating |
|---|---|
| One canonical style, zero config (`gofmt`); fixed 98-col width | 5/5 |
| `mix rian.format` + `--check`/`--diff` CI gate; LSP delegates | 5/5 |
| Bracket CST + Wadler/Lindig pretty-printer (no reparse; meaning-safe by construction) | 5/5 — shipped |
| Idempotence + significant-token-equivalence + comment-fidelity + totality (corpus + fuzz) | 5/5 |
| Style rules (2-space, spacing, blank-line, comments, 98-col bracket wrap + trailing comma, precedence-aware chain wrap, magic comma) | 5/5 — shipped |
| LSP formatting + rangeFormatting backend; `rian fmt` escript; Doc engine self-hosted | 5/5 — shipped |
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

- **GenLSP transport** — `Rian.LSP.Formatting` is the data-level backend (returns `TextEdit[]` for
  whole-document and range formatting); the actual JSON-RPC server (ADR-0038 Tier 0) is still to be
  built and would call it.
- **`rangeFormatting` granularity** — formats the selection as a fragment (re-indented to context); best
  on whole-declaration/statement selections, total but possibly odd on a cut-across-`do…end` selection.

## Resolved

- **Magic trailing comma**, **operator-chain wrapping** (precedence-aware, full `@cont_ops`), and the
  **`rian fmt` escript** + **LSP formatting/rangeFormatting backend** all ship (see headers above).
- **Comment attachment** — comments are preserved at their authored token position (trailing comments
  stay on their line, two spaces off the code; own-line comments keep their place). No leading/trailing/
  floating taxonomy is needed because the formatter never moves tokens across a *significant* newline.
- **Blank-line normalization** — runs of blank lines collapse to one; leading/trailing blanks trimmed.
