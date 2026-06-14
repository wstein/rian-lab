# ADR-0051 — Doc Comments: `@moduledoc`/`@doc`/`@typedoc`, documented self-hosting from day one

**Status:** Accepted (direction) · **Day-one / Stage-1 prerequisite** (not a deferred surface item)
**Implemented:** partial — `@doc`/`@moduledoc`/`@typedoc` + heredoc `"""…"""` parse and attach as the `doc` field (`Rian.Lexer`, `Rian.Decl`, `Rian.IR`; `test/rian/decl_test.exs`, `test/rian/lexer_test.exs`), lowered to Elixir-text and rustdoc `///`/`//!` (`Rian.Lower`); but **no EEP-48 BEAM doc chunks** (`Rian.Beam` emits no doc attribute) and **no JSDoc** (`Rian.JS`)
**Refs:** ADR-0026 (EEP-48 doc-chunk *output* — this is its missing *input* surface), ADR-0027/0031 (self-hosting), ADR-0032 (family surface), ADR-0035/0037/0044 (the `@`-annotation lane), ADR-0041 (per-target lowering), ADR-0045 (formatter / CST), ADR-0046 (compile-time metadata), ADR-0049 (Tier-1 doc contract), ADR-0050 (declaration structs carry the doc)
**Owners:** Julian Vance (doc surface) · Arthur Pendelton (self-hosting) · Chloe Bennett (parser/lexer) · Maya Lin (per-target lowering) · Liam Davis (EEP-48/ExDoc) · Samir Patel (doctests deferral) · Rachel Okafor (PM)

## Context

ADR-0026 promised doc **output** — "EEP-48 doc chunks; `h` in IEx, ExDoc, `code:get_doc/1` work on
Rian modules" — but never defined the doc **input surface**. Native Rian has only `#` line comments;
no example carries a doc. That was acceptable as a deferred item *until* the self-hosting requirement
sharpened it: **you cannot self-host a *documented* compiler in an *undocumented* language.** The
current Elixir-hosted compiler documents every module (`@moduledoc` on `Rian.IR`, `Rian.Decl`,
`Rian.Lower`, …); its Rian rewrite (ADR-0027 Stage 1) must carry the equivalent or self-hosting
**regresses documentation**. Doc comments are therefore a **Stage-1 prerequisite**, landing with the
declaration parser — not a v2 nicety.

## Decision

### 1. Doc attributes, not doc comments

| Form | Attaches to | Example |
|---|---|---|
| **`@moduledoc`** | a `mod` | `@moduledoc "The core IR."` |
| **`@doc`** | a `def` / `const` | `@doc "Lower a declaration to the target."` |
| **`@typedoc`** | a `type` / `struct` / `alias` / `opaque` / `range` | `@typedoc "A sum-type variant."` |

Family-correct (Elixir spells these **identically**), collision-free (ADR-0032 passes trivially), and
on the established `@`-annotation lane (`@wire`/`@partial`/`@behaviour`). **Attribute form, not Rust's
`///` comment form** — a doc attribute is *structured* (a string attached to a declaration), so it lives
in the CST (ADR-0045) and the typed core IR (ADR-0050), not as a magic comment. `///` is a *target
spelling* (below), never the surface.

### 2. Content is Markdown; multi-line via heredoc strings

Doc content is **Markdown** (the EEP-48 / ExDoc convention). Real module docs are multi-line, so this
adds a **heredoc string** form `"""…"""` to the lexer (single-line `"…"` is insufficient). The heredoc
is an ordinary `String`; only the doc *use* is special.

### 3. A doc is compile-time metadata on the following declaration

A doc attribute attaches to the **declaration that follows it** and is carried as an **optional `doc`
field on the declaration structs** already in [`Rian.IR`](../../lib/rian/ir.ex) (`Mod`, `Def`, `Type`,
`Struct`, `Const`, …) — one field, no new node kind (ADR-0050). Docs are **pure compile-time metadata**
(ADR-0046): erased into the target's doc artifact, zero runtime effect.

### 4. Per-target doc lowering (Tier-1 contract, ADR-0049)

| Target | Doc lowering |
|---|---|
| **BEAM** | **EEP-48 doc chunks** — fulfills ADR-0026 (`h Foo` in IEx, ExDoc, `code:get_doc/1`, Hex docs) |
| **Rust** | **rustdoc `///`** (and `//!` for module docs) |
| **ECMAScript** | **JSDoc** `/** … */` |
| **JVM** | Javadoc (Tier 2) |

Doc lowering is part of the **Tier-1 support contract** (ADR-0049): a Tier-1 target emits docs to its
native doc system. This is the ADR-0041 "same source, idiomatic per target" pattern, applied to docs.

### 5. Day-one obligations

- `@moduledoc`/`@doc`/`@typedoc` **parse with the declaration parser** (ADR-0031 Stage 0.1), not later.
- The **tour examples** gain module/function docs; the **self-host examples**
  (`examples/rian/selfhost_lexer.rian`) are documented — demonstrating documented self-hosting code from
  day one.
- The **formatter** (ADR-0045) treats doc attributes as structured CST nodes — preserved and canonically
  formatted (easier than free comments, because they're structured).

### 6. Doxygen considered and rejected — Markdown content, native doc systems

Doxygen (a cross-language doc tool + `@param`/`@return`/`@brief` tag markup) was weighed as the doc
system and **rejected**, for the reasons running through the corpus:

- **It bypasses each target's *native* doc ecosystem.** ADR-0026's "first-class BEAM citizen" requires
  **EEP-48** so `h Foo` / ExDoc / Hex docs work; Rust devs use **rustdoc**; JS devs use **JSDoc**.
  Doxygen output is none of these — a parallel, lowest-common-denominator artifact no target's community
  actually uses. This is the doc analogue of ADR-0041/0046's *"emit idiomatic output, let the target's
  tooling handle it; don't simulate."*
- **Its `@param`/`@return` tags duplicate the typed signature.** Rian already carries param/return types,
  error sets (ADR-0040), and effect sets (ADR-0048) in the **signature**; `@param x Int64` restates them,
  and tag-`@` collides conceptually with the `@`-annotation lane.
- **Markdown is native on two of three Tier-1 targets** (EEP-48 and rustdoc are Markdown; only JSDoc is
  tag-based).

Therefore **doc content is Markdown.** Structured sections (arguments, returns, errors, examples) follow
a **Markdown convention** (rustdoc-style `# Arguments` / `# Errors` headers), and the **ECMAScript emitter
maps those sections to JSDoc `@param`/`@returns` tags** — so the JS target gets idiomatic tag docs
*without* Doxygen, its tool, or its tag syntax in the Rian source.

## Ratings

| Decision | Rating |
|---|---|
| `@moduledoc`/`@doc`/`@typedoc` attributes (family-correct; `@`-lane); not `///` comments | 5/5 |
| Doc content = **Markdown**; structured sections → JSDoc tags on JS (Doxygen rejected) | 5/5 |
| Day-one / Stage-1 prerequisite — self-hosting must not regress docs | 5/5 |
| Doc = optional `doc` field on declaration structs (ADR-0050) | 5/5 |
| Per-target lowering: EEP-48 / rustdoc / JSDoc (fulfills ADR-0026, Tier-1 contract) | 5/5 |
| Markdown content; heredoc `"""…"""` strings | 4/5 |
| Doctests deferred (ties to the testing-framework gap) | 4/5 |

## Consequences

- **Closes the doc-comment surface gap** and gives ADR-0026's EEP-48 output its input.
- **Self-hosting (ADR-0027) keeps its docs** — the compiler-in-Rian is documentable in Rian.
- **Parser (Stage 0.1):** `@moduledoc`/`@doc`/`@typedoc` + heredoc strings; doc attaches to the next
  declaration as the `doc` field (ADR-0050 core IR).
- **Emitters:** doc lowering per target (EEP-48 / rustdoc / JSDoc), a Tier-1 obligation (ADR-0049).
- **Examples:** the tour and `selfhost_lexer.rian` get documented as authoritative surface.

## Open items

- **Doctests** — runnable examples embedded in docs (Elixir's `iex>` doctests); valuable, but ties to
  the still-undesigned **testing framework** — deferred to that ADR.
- **`@typedoc` granularity** — per-variant / per-field docs, or type-level only? v1 is type-level.
- **Other metadata attributes** — `@deprecated`, `@since`, `@spec`-as-doc; align with the EEP-48 metadata
  map (ADR-0026) incrementally.
- **Heredoc details** — interpolation in heredocs (probably **no** for docs), indentation stripping
  (Elixir strips to the closing-delimiter column); settle in the lexer.
