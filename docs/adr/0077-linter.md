# ADR-0077 — Linter: advisory, semantics-aware style checks (the gofmt↔vet split)

**Status:** Proposed (direction) · not yet implemented — this ADR lines out the linter and, above
all, fixes the **formatter↔linter boundary** so neither grows into the other.
**Implemented:** no — direction only; `mix rian.lint` and the rule set are not yet built.
**Refs:** ADR-0045 (formatter — the mechanical-layout half this complements), ADR-0034 (declare-public
+ the PascalCase-type / lowercase-value casing rule the linter enforces), ADR-0050 (typed Core IR —
the linter's semantic substrate), ADR-0057/0058 (`Rian.Reach` — portability facts the linter surfaces),
ADR-0035 (one obvious way — the style discipline the linter advises toward)
**Owners:** Liam Davis (style rules) · Samir Patel (invariants/severity) · Chloe Bennett (parser) ·
Maya Lin (LSP integration) · Kira Neri (CI/tooling) · Rachel Okafor (PM)

## Context

ADR-0045 shipped an opinionated, zero-config **formatter** (`Rian.Format`): a lossless bracket CST +
a Wadler/Lindig `Doc` over the lexer, **total** (never refuses, never corrupts), **semantics-free**
(it only moves whitespace/newlines inside zones the parser is insensitive to — proven by the
significant-token oracle), and **diagnostic-free** (it emits code, not warnings). That is exactly
what a formatter should be.

But three classes of concern have no home in it, and the formatter review surfaced them concretely:

1. **Layout the formatter can't safely produce yet.** A `def` head wider than 98 cols is *not*
   wrapped, because `Rian.Decl`'s head parser is not newline-tolerant inside the param parens (and the
   self-hosted `compiler/decl.rian` + the `sig` oracle would have to agree). A long pipeline *inside a
   block body* isn't wrapped either (its newline would become a `;` statement separator). The formatter
   correctly refuses to emit these rather than risk meaning — but a developer still wants to be *told*.
2. **Style that needs the program's meaning.** Naming conventions (ADR-0034: PascalCase types,
   lowercase values), unused or shadowed bindings, dead clauses, excessive nesting — none are layout;
   all need the typed Core IR or scope analysis, which the formatter deliberately never touches.
3. **Honest residue.** Leftover `TODO_PORT(…)` / `_Unk` transpiler markers, and non-portable
   constructs that `Rian.Reach` already classifies (host FFI in code intended to be portable) — facts
   worth a warning, never a hard format-time error.

Every mature ecosystem draws this exact line: **gofmt + `go vet`**, **rustfmt + clippy**, **Prettier +
ESLint**. The formatter is mechanical and always-applied; the linter is advisory and judgment-bearing.
Conflating them is the documented failure mode (a formatter that "lints" starts refusing valid code; a
linter that reformats fights the formatter).

## Decision

### 1. A separate, advisory `Rian.Lint` (`mix rian.lint`) — never the formatter

The linter is a **distinct tool** that consumes the **typed Core IR** (ADR-0050) and `Rian.Reach`
facts. It is **advisory**: it emits ranked **warnings**, it does not rewrite by default, and it is
**not** on the always-green path the formatter is. CI may *opt in* to `--max-severity` gating; local
dev and LSP get diagnostics. A `--fix` flag applies only the **mechanically-safe** subset (see §3).

### 2. The boundary (the load-bearing decision)

| Concern | Owner | Why |
|---|---|---|
| Whitespace, indent, bracket/operator-chain wrapping, magic comma, comment placement | **Formatter** (ADR-0045) | mechanical, meaning-preserving, total |
| Over-long `def` head / block-internal chain (can't wrap safely *yet*) | **Linter (warn)** | parser-gated; migrates formatter-ward when the head parser is newline-tolerant |
| Naming (PascalCase type / lowercase value, ADR-0034), unused/shadowed binding, dead clause, deep nesting | **Linter** | needs scope/types, not layout |
| Leftover `TODO_PORT`/`_Unk`; non-portable construct in portable code (Reach) | **Linter (warn)** | judgment / honesty, not a layout fact |
| Type errors, exhaustiveness, capability/linearity, reachability *gates* | **Checker/Reach** (refuse to emit) | soundness, not style — already hard gates |

**Invariant:** the formatter never warns and never refuses; the linter never reformats beyond its
opt-in `--fix` subset; neither duplicates the checker's *hard* gates.

### 3. Initial check set (each: id · severity · auto-fixable?)

- `long-signature` · warn · no — a `def`/`pub def` head exceeds 98 cols (the formatter can't wrap it).
  The bridge to ADR-0045: when the parser gains newline-tolerant heads, this lint *retires* and the
  formatter wraps instead.
- `naming-convention` · warn · no — a type/constructor not PascalCase, or a value/function not
  lowercase (ADR-0034); a `pub` boundary missing a declared type.
- `unused-binding` / `shadowed-binding` · warn · `--fix` can prefix `_` — a `:=` bind or param never
  read; an inner bind hiding an outer name.
- `deep-nesting` · warn · no — `if`/`case`/`with` nested past a threshold (default 4); a readability
  smell the formatter faithfully but unhelpfully indents.
- `port-marker` · warn · no — a residual `TODO_PORT(…)` / `_Unk` in non-draft source.
- `non-portable` · info · no — a function pinned off a Tier-1 target by host FFI where portability was
  plausibly intended (sourced from `Rian.Reach`, honest — never claims more than the matrix).

Severities: `error` (opt-in CI gate) > `warn` (default surfaced) > `info`. The set is a starting point;
new lints land behind their own id so a project can silence one without disabling the tool.

### 4. Output, LSP, and determinism

Diagnostics carry `{file, line, col, id, severity, message}`; `mix rian.lint` prints them grouped and
exits non-zero only when `--max-severity` is breached. The same engine backs **LSP diagnostics**
(ADR-0038), so an editor shows lints inline. Lint output is **deterministic and order-stable** (same
discipline as the formatter), so it is diff-able and CI-stable.

## Ratings

| Decision | Rating |
|---|---|
| Linter separate from the formatter (gofmt↔vet boundary) | 5/5 |
| Advisory by default; opt-in CI severity gate; `--fix` only for the mechanically-safe subset | 5/5 |
| `long-signature` as a *linter* warning now, migrating to a *formatter* fix once the head parser allows it | 4/5 |
| Consume the typed Core IR + Reach (don't re-derive) | 5/5 |
| Fold these checks into the formatter instead | 1/5 (rejected — breaks totality + the meaning-free guarantee) |
| Make the linter a hard build gate by default | 2/5 (rejected — advice, not soundness; the checker/Reach own hard gates) |

## Consequences

- **Closes the formatter's idiomatic-output gaps honestly:** the formatter stays total and
  meaning-free; the things it can't safely reformat become *visible advice* rather than silent
  >98-col lines.
- **A clear migration path:** `long-signature` (and block-internal chain wrapping) move from
  linter-warning to formatter-fix the day `Rian.Decl` accepts newline-wrapped heads (parser +
  `compose_decl` fixpoint co-change) — the linter is the holding pen, not the permanent home.
- **No new hard gates:** existing CI (`mix test.all`, the portability gate, dialyzer) is unchanged; the
  linter is additive and opt-in.
- **Self-host budget:** like the formatter, the linter's engine can later be ported to Rian; the
  semantic checks ride on the same Core IR the self-hosted checker already consumes.

## Open items

- **Threshold defaults** (nesting depth, signature width vs the 98-col formatter budget) — pick by
  sweeping the real corpus so the defaults don't cry wolf on idiomatic code.
- **`--fix` scope** — exactly which lints are mechanically safe to auto-apply (start with
  `unused-binding` → `_`-prefix only).
- **Overlap with the checker** — keep lint advice strictly disjoint from the checker's hard errors; a
  lint must never restate a compile error.
