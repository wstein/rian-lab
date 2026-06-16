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

⇒ for any change that (a) only touches whitespace/newlines and (b) at most adds/removes a trailing
comma before a closer, the **significant token stream is unchanged**. That is the
**semantic-preservation oracle** (`sig/1` in `Rian.FormatTest`, ADR-0045): tokenize, drop what reflow
is *allowed* to move — comments, newlines inside brackets, blank-line runs, a trailing comma before a
closer — and assert the rest is identical on both sides. Equal significant streams ⇒ same parse. It
supersedes the MVP's raw re-lex equivalence, which a reflowing formatter cannot satisfy (it moves
newlines), while still ruling out any reflow that reorders or drops a meaningful token.

### Why significant-token equivalence, not full-AST equality

The tempting stronger bar is `Rian.Decl.parse(format(src)) == Rian.Decl.parse(src)`. It is **rejected**
for two concrete reasons:

1. **Parse is not deterministic.** Macro expansion mints a fresh `__h<n>` hygiene counter on each call
   (`tmp__h4228`; see `06_macros_comptime.rian`), so two parses of *identical* source already differ.
   A full-AST oracle would need alpha-renaming of every hygienic name to be even *well-defined* — an
   awkward, ongoing canonicalization tax for no extra safety over the token bar.
2. **Tokens already pin reassociation.** A whitespace-only reflow that kept every significant token in
   order, separated by the same significant newlines, but parsed differently, does not exist — `sig/1`
   already catches token reordering and movement across significant newlines.

The token bar's one blind spot is the trailing comma it *strips*: it cannot see a reflow that emits
**non-parsing** source (e.g. a comma after a cons tail, `[a | xs,]`, which the parser rejects). That
gap is closed by a separate, lighter guard — **format every parseable corpus file and assert the
result still parses** (`Rian.FormatTest`, "formatted output stays parseable"). Files the core parser
does not fully model (FFI `extern`, custom `@`-annotations) are excluded there; `sig/1` still covers
them. Together: `sig/1` (tokens preserved) + parseability (output is valid) + idempotence + comment
fidelity + fuzz totality are the corpus-wide contract.

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
