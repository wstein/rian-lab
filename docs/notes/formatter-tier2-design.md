# Formatter Tier 2 — line wrapping via a lossless CST + Wadler/Lindig pretty-printer

Design note backing the v2 work on ADR-0045. Records the algorithm choice, the
Rian-specific safety argument, and the scope boundary. Sources read:

- Wadler, *A prettier printer* (1997/98) — the `Doc` algebra (`nil`/`text`/`concat`/`nest`/`line`/`group`).
- Lindig, *Strictly Pretty* (2000) — the **linear-time strict** rendering: a worklist of
  `(indent, mode, doc)` triples + a bounded `fits` lookahead. This is the engine we implement.
- Prettier `commands.md` — the production vocabulary: `softline`, `hardline`, `line-suffix`
  (trailing comments), `ifBreak` (trailing commas), and **break propagation** (a hardline forces every
  enclosing group to break).
- Rowan / Roslyn / Swift libsyntax — lossless **concrete** syntax trees (every token + trivia kept).

## The engine: `Rian.Format.Doc`

Lindig's strict algorithm. `Doc` constructors: `empty`, `text/1`, `concat/1`, `nest/2`,
`line` (→ space when flat), `softline` (→ "" when flat), `hardline` (always breaks),
`group/1`, `line_suffix/1` (deferred to line end — comments), `if_break/2` (broken vs flat form).

- `fits?(width_left, worklist)` — scan in the candidate mode; `text` subtracts, a break in `:break`
  mode (or a hardline) ends the line → fits, `group` is measured flat. Bounded by the line width.
- `render(width, doc)` — worklist of `{indent, mode, doc}`; a `group` renders **flat** iff it has no
  propagated hardline *and* `fits?` the remaining width, else **break**. `line_suffix` content is
  buffered and flushed just before the next newline (so a trailing comment lands at end-of-line).
- `propagate_breaks` — any group transitively containing a `hardline` is marked `must-break`.

## The Rian safety argument (why reflow can't change meaning)

Two facts, both verified against the compiler:

1. **`Rian.Decl.detokenize` is whitespace-invariant** — declaration bodies/types/etc. are stored as
   single-space-joined token strings, so changing whitespace/newlines never changes them.
2. The parser is **newline-tolerant inside unbalanced brackets** (P1), and trailing commas parse to
   the identical AST (`f(a,) ≡ f(a)`, `[1,2,] ≡ [1,2]` — checked in `Rian.Pratt`).

⇒ **`Rian.Decl.parse(format(src)) == Rian.Decl.parse(src)`** for any change that (a) only touches
whitespace/newlines and (b) at most adds/removes a trailing comma before a closer. This full-AST
equality is the **semantic-preservation oracle**, asserted over the whole corpus and in property tests.
It is strictly stronger than the MVP's re-lex equivalence for everything except the deliberate
trailing-comma token (handled by stripping `comma-before-closer` on both sides before comparing).

## Scope boundary (v1 of Tier 2)

- **Reflow happens inside bracket groups only** — `( )`, `[ ]`, `{ }`, `%{ }`: call args, collection
  and map literals, tuples, parenthesized exprs. A group collapses to one line if it fits in the width
  budget (98 cols), else breaks **one item per line** with a hanging indent, with an `if_break`
  trailing comma. A group whose content contains a line comment is forced to break (a `#` comment can't
  sit mid-line).
- **The statement/block skeleton keeps the source's newline placement** (hardline where the source had
  a newline), exactly like the formatter MVP. We do **not** collapse or expand `do…end` blocks, and we
  do **not** reflow pipe/operator chains yet — those need continuation-newline reasoning and are the
  next increment. Documented, not silently skipped.

Width: **98 columns** (ADR-0045 §5).
