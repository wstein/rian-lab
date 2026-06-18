# ADR-0065 — Surface stability: freeze the token + operator surface (not layout, not semantics)

**Status:** Proposed
**Implemented:** partial — token/operator surface present in the parser (`Rian.Pratt` `opinfo`, `Rian.Lexer`); the freeze itself (declaring the surface stable) is a process decision, not landed
**Refs:** ADR-0032/0033 (surface syntax family + vocabulary), ADR-0050 (parser/core IR), ADR-0029 (dot syntax), ADR-0039 (failable bind), ADR-0064 (numeric semantics — *not* frozen), P1 (newline-tolerant bodies — layout *not* frozen), P5 (`ref` portability — *not* frozen)
**Owners:** Maya Lin (surface) · Chloe Bennett (parser) · Samir Patel (rigor) · Kira Neri (honesty) · Rachel Okafor (PM)

## Context

The design review's one-sentence verdict ends "…then **freeze the surface and not a moment before**."
The "not a moment before" was load-bearing: a freeze must come *after* the warts are paid (P1 — the
one-line-body rule, now killed) and must *not* freeze the things still in flux (numeric semantics, P2;
`ref` portability, P5; error-propagation sugar, P4, still unspelled). Freezing a wart, or freezing a
decision still being made, is worse than not freezing at all.

So this ADR makes a **partial, honest freeze**: the parts of the surface that are settled and that
tooling/users most need stable — the **token vocabulary** and the **operator/precedence table** — and
explicitly leaves layout and semantics open.

## Decision

### Frozen (stable; additive-only)

The following are **stable**. New entries may be *added* (a new keyword/operator behind its own ADR);
existing entries may **not** be changed or removed without a superseding ADR. This is the surface a
syntax highlighter, formatter, or third-party tooling can rely on.

**Keywords** (`Rian.Lexer.@keywords`):
`if do else end def type range case when struct alias mod pub const macro use with protocol impl`

**Operators** — spelling **and** precedence/associativity (`Rian.Lexer.@multi`/`@single`/`@op_words`,
`Rian.Pratt.opinfo`). Lower level binds tighter:

| Level | Operators | Assoc |
| --- | --- | --- |
| prefix | `-` `not` (bind tighter than any binary) | — |
| 3 | `*` `/` `rem` `div` | left |
| 4 | `+` `-` | left |
| 5 | `<>` | right |
| 6 | `in` | non-assoc |
| 7 | `\|>` | left |
| 8 | `<` `<=` `>` `>=` | non-assoc |
| 9 | `==` `!=` | non-assoc |
| 10 | `and` | left |
| 11 | `or` | left |
| 12 | `<~` (capability-gated mutation) · `<-` (failable bind, `with`/`for` headers only, ADR-0039) | right |

Non-binary operator spellings also frozen: `:=` (define/bind), `->` (clause arm / lambda), `..`
(range), `.` (dot access / qualification, ADR-0029), `|` (cons / variant separator), `:` (atom / label),
`&` (capture).

**Punctuation & literals:** `( ) [ ] { } %{ , ;`, significant newline; integer / float / string (`"…"`,
heredoc `"""`) / char (`'x'`) / atom literals.

**The two surface rules that carry weight (ADR-0032):** `?` stays a boolean-predicate suffix (never
error-propagation — that's P4's job to spell *without* `?`/`!`), and the dot is universal
(case disambiguates module vs field, ADR-0029).

### Explicitly NOT frozen

- **Layout / whitespace.** Newline-tolerant `:=` bodies (P1) just changed; block-body and continuation
  rules may still evolve. Only *tokens* are frozen, not how they're laid out across lines.
- **Numeric semantics** (P2 / ADR-0064): `Int` vs fixed-width and the default literal type are mid-change.
- **Capability portability** (P5): `ref` is leaving the portable core; the matrix is in motion.
- **Error-propagation sugar** (P4): an unspelled future operator — and it must *not* be `?`/`!`.
- **Anything unimplemented:** macro fragment kinds, `forall` generics surface, etc. — not yet on the
  surface, so not frozen.

## Rationale

- **Tooling needs a stable lexeme/operator surface long before semantics settle** — a highlighter or
  formatter keys off tokens and precedence, not numeric contracts. Freezing exactly that, and no more,
  is the maximum honest commitment.
- **"Not a moment before" is satisfied:** P1 (the wart) landed first; the in-flux items (P2/P5/P4) are
  named as *not* frozen rather than quietly swept in.

## Consequences

- A new operator or keyword is a deliberate, ADR-gated act (additive); a *change* to an existing one is
  a breaking change requiring this ADR's supersession.
- The formatter (ADR-0045) and any editor grammar can target the frozen table as a contract.
- Re-open the freeze only to *extend*; the not-frozen list shrinks as P2/P4/P5 land their own ADRs.

## Open items

- **When does layout freeze?** After the block-body/continuation rules settle (post-P1 follow-ups) — a
  later amendment.
- **Formatter conformance** — a test that the formatter round-trips every frozen operator at its
  precedence, so a precedence change can't slip in unnoticed.

## Post-thaw additive candidates (not frozen, not yet adopted)

The freeze is **additive-only** (see Consequences): adding surface later is permitted; *changing*
frozen surface is not. Candidates parked here are recorded so they are not re-litigated from scratch,
but they are **deliberately deferred** until the higher-priority work lands.

- **Labeled arguments (Gleam-style).** *(2026-06-14 Gleam/Haxe borrow debate, consensus #6, rated
  3/5 — cheap ergonomic win, low risk, but pure surface and the surface is frozen.)* Gleam's
  `f(name: value)` call form (and labeled parameters at the definition) reads well and removes
  positional-argument ambiguity. It is **additive** (new call/param syntax, no change to existing
  tokens), so it is admissible without violating this ADR — but it touches ADR-0033 (surface
  vocabulary) and waits behind the higher-priority mechanism work (ADR-0067 abstract types, ADR-0068
  `@external`). **Adopt later, not now.** *Enforced (2026-06-14):* because the parser already produces
  `{:label, …}` nodes (they are the existing struct/variant *construction* syntax, `Name(field: v)`),
  a labeled argument on any **non-construction** callee — a **plain** lowercase call (`g(a: 1)`) or a
  **qualified** dotted call (`Mod.foo(a: 1)`), neither of which is a constructor — is now a
  **clean compile error** (`Rian.Check.check_labels`, `test/rian/check_test.exs`) rather than a silent BEAM
  miscompile into a bogus struct (lowercase) or a label silently erased (qualified). Lifting the freeze later means turning that error into real labeled-call semantics
  (which also needs labeled *parameters* at the definition — currently unspecified).
