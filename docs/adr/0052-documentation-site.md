# ADR-0052 — Documentation Site: Astro/Starlight portal + native per-target API reference

**Status:** Accepted (direction) · **Lightweight/tooling** (not on the implementation critical path)
**Implemented:** partial — an Astro/Starlight portal exists (`site/astro.config.mjs` with `@astrojs/starlight`, `site/src/content`); the in-browser Rian playground (gated on the ECMAScript emitter / self-host) is not built
**Refs:** ADR-0026 (ExDoc/EEP-48), ADR-0041/0046 (native-per-target; "don't simulate"), ADR-0049 (Tier-1 ECMAScript — enables the playground), ADR-0051 (doc-comment extraction — the *other* layer)
**Prior-art blueprint:** [github.com/wstein/flatbars](https://github.com/wstein/flatbars) — a same-author PureScript monorepo with an Astro Starlight MDX spec site and a client-side `lab/` playground (engine compiled to a committed JS bundle + a WASM core). It already runs the patterns below in production; the playground open items adopt its architecture.
**Owners:** Liam Davis (site/JS) · Julian Vance (content) · Kira Neri (build/CI) · Maya Lin (architecture) · Marcus Chen (supply chain) · Rachel Okafor (PM)

## Context

Documentation has **two layers** that must not be conflated:

1. **API reference extraction** — docs pulled *from source* (`@doc`/`@moduledoc`, ADR-0051). Settled:
   **native per target** — EEP-48/ExDoc (BEAM), rustdoc (Rust), JSDoc (JS). (Doxygen was rejected here
   for bypassing the native tools — ADR-0051 §6.)
2. **The documentation *site / portal*** — hand-written guides, the language reference, the
   "by example" tour, and the ADRs, rendered as a browsable website. This was **implicit** — the repo
   currently renders it with **ExDoc** (`doc/*.html`). Sphinx and Astro/Starlight are **layer-2** tools.

The native-per-target / "don't simulate" principle (ADR-0041/0046) that killed Doxygen at layer 1
**does not apply** at layer 2: the portal is **target-agnostic prose** — you want *one* language guide,
not six. So the portal choice is a DX/ecosystem-fit decision, not a semantic one.

## Decision

### 1. Public language portal → Astro/Starlight

The public `rian-lang` portal (guides, language reference, the by-example tour, ADRs) is built with
**Astro/Starlight**:

- **Markdown/MDX-native** — ingests the existing Markdown corpus (ADRs, specs, README, tour) with **zero
  conversion**. (Sphinx is reStructuredText-first; Markdown only via the MyST bridge — a friction tax for
  benefits that are layer-1 and already solved natively.)
- Built-in **search, versioning, i18n**, modern DX.
- **MDX enables an in-browser Rian playground** — compile Rian → JS *in the browser* via the Tier-1
  **ECMAScript** target (ADR-0049). "Edit this example, see it run" on the language's own site is the
  differentiator, and it exists *only because* ECMAScript is Tier 1. The playground is one of the
  interactive surfaces over the shared eval engine of [ADR-0053](0053-repl-interactive-surfaces.md)
  (REPL · Livebook · Jupyter · playground) — so it cannot drift from the real compiler.

### 2. API reference → native per target, linked from the portal

The portal **links out** to each target's native API docs (ExDoc/Hex for BEAM, rustdoc/docs.rs for Rust,
the JSDoc site for JS) rather than re-extracting them into one generator. Re-extracting everything into a
single tool would repeat the Doxygen mistake (ADR-0051 §6) at the site layer.

### 3. Keep ExDoc for the compiler's own Elixir/BEAM API

ExDoc is retained for the **compiler's own host (Elixir) and BEAM-target API** — zero-config given the
Elixir host, already working. Starlight replaces ExDoc only as the **public language portal**, not as the
BEAM/host API reference.

## Ratings

| Decision | Rating |
|---|---|
| Public portal → Astro/Starlight (Markdown-native; search/versioning; in-browser playground) | 5/5 |
| API reference → native per target (EEP-48/ExDoc, rustdoc, JSDoc), linked | 5/5 |
| Keep ExDoc for the compiler's own Elixir/BEAM API | 4/5 |
| Sphinx as the portal | 3/5 (reST friction vs the Markdown corpus; strengths are layer-1, already solved) |
| One monolithic generator re-extracting all API docs | 1/5 (the Doxygen mistake, at the site layer) |

## Consequences

- The implicit ExDoc-as-portal becomes an explicit **Starlight portal**; the existing Markdown corpus
  moves in unconverted.
- **The playground is gated on the ECMAScript emitter** (ADR-0049 Tier 1) — so the portal can start as
  static docs now and gain the interactive playground once that emitter lands. A nice payoff from the
  Tier-1 roadmap call.
- **Supply chain (Marcus):** Astro pulls a large npm dependency tree; the docs build must be
  pinned/reproducible (Kira) — an ordinary static-site CI concern, isolated from the compiler build.
- Not on the implementation critical path (core-IR migration → `area/1` spike → ECMAScript emitter still
  come first); the portal can be stood up in parallel whenever.

## Playground architecture (adopted from the FlatBars blueprint)

The FlatBars `lab/` + `spec/` proves the stack; Rian adopts its patterns, with one Rian-specific gate.

- **No-drift live panes (the key idea).** A `LivePane`-style MDX component runs the **same committed
  compiler bundle the implementation ships** — so the by-example tour's live examples are *executable
  and guaranteed-correct*, never hand-checked prose (FlatBars' `LivePane.jsx` importing the vendored
  engine bundle). This subsumes ADR-0051's deferred doctests for the *site*.
- **Multi-target output panel (the Rian-specific differentiator).** Show one Rian source lowered to
  **BEAM + Rust + JS side-by-side** — something no template-engine lab can do, and a direct payoff of
  the multi-target design (ADR-0041/0049). FlatBars' modular `app/dock/*` panels are the pattern.
- **Byte-identity conformance gate.** Playground/JS output is gated against the **BEAM reference**
  (FlatBars' ADR-0011 dual-path byte-identity gate) — the playground cannot diverge from the real
  compiler. Ties to the ADR-0041 conformance matrix.
- **Reuse the existing TextMate grammar** (`editors/vscode/rian`) registered as a Shiki/Expressive-Code
  language for ```rian fences (FlatBars registers its grammar in `astro.config.mjs`). Zero new work.
- **In-browser *compilation* is gated on self-host + ECMAScript Tier 1.** FlatBars compiles trivially
  (PureScript→JS is native); Rian's compiler is Elixir-hosted and larger, so three paths:
  **(a)** self-host (ADR-0027) → compile the Rian-in-Rian compiler to JS via the ECMAScript target
  (ADR-0049) = the clean analogue; **(b)** BEAM-in-WASM (AtomVM/Firefly) interim; **(c)** server-side
  compile (not static). Until self-host, a **partial** playground runs *already-emitted* JS examples —
  the no-drift LivePane works *now* without in-browser compilation. The full playground is a concrete
  downstream payoff of self-hosting + ECMAScript-Tier-1.

## Open items

- **Portal hosting / CI** — static host (GitHub Pages / Cloudflare / Netlify) and the pinned, reproducible
  docs build (Kira); Playwright screenshot tests for the playground UI (FlatBars' `lab/test`).
- **Versioned docs** — per-release doc snapshots; align with the language-versioning policy (still open).
- **ADR rendering** — surface the design corpus in the portal (a "design" section) vs keep ADRs
  repo-only. (FlatBars renders its ADRs as Starlight pages.)
- **Playground execution path** — settle (a)/(b)/(c) above once self-host + the ECMAScript emitter land.
