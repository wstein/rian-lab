# ADR-0052 — Documentation Site: Astro/Starlight portal + native per-target API reference

**Status:** Accepted (direction) · **Lightweight/tooling** (not on the implementation critical path)
**Amended 2026-06-21 (ADR-0088):** the live-playground engine is **no longer "self-host → JS only".** The reference interpreter (`Rian.Eval`, ADR-0088) compiled to **WASM/JS** is a second engine that ships the playground **ahead** of the `v1==v2` bootstrap — self-host → JS remains the *eventual* whole-compiler-in-browser engine, but it is no longer the *only* one or a precondition for shipping. Wherever this ADR says "self-host → JS only / nothing else", read "the interpreter engine first, self-host → JS later" (ADR-0088 §3).
**Implemented:** partial — an Astro/Starlight portal exists (`site/astro.config.mjs` with `@astrojs/starlight`, `site/src/content`); the in-browser Rian playground (engine = the **`Rian.Eval` interpreter → WASM/JS** first (ADR-0088), **self-host → JS** later; the latter gated on the `v1==v2` bootstrap + JS-reachability, ADR-0063) is not built
**Refs:** ADR-0026 (ExDoc/EEP-48), ADR-0041/0046 (native-per-target; "don't simulate"), ADR-0049 (Tier-1 ECMAScript — enables the playground), ADR-0051 (doc-comment extraction — the *other* layer), ADR-0027/0063 (self-host → JS — the playground engine + its `v1==v2` gate), ADR-0047 (portable prelude — the JS-reachability prerequisite)
**Prior-art blueprint:** [github.com/wstein/flatbars](https://github.com/wstein/flatbars) — a same-author PureScript monorepo with an Astro Starlight MDX spec site and a client-side `lab/` playground (engine compiled to a committed JS bundle + a WASM core). It already runs the patterns below in production; the playground open items adopt its architecture — **except the engine substrate**: Rian's bundle is self-host → JS, **not** a WASM core (see "Playground architecture").
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
- **MDX enables an in-browser Rian playground** — "edit this example, see it run" on the language's
  own site is the differentiator, and it exists *only because* ECMAScript is Tier 1. "Live" means the
  reader **edits the source and re-compiles** — which requires the compiler itself to run client-side,
  so the **whole compiler is lowered to JS by its own backend (self-host → JS)** and shipped as a
  committed bundle; an edited snippet then compiles in the browser with no backend (see "Playground
  architecture" for the gate). The playground is one of the interactive surfaces over the shared eval
  engine of [ADR-0053](0053-repl-interactive-surfaces.md) (REPL · Livebook · Jupyter · playground) —
  so it cannot drift from the real compiler.

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
| Live-playground engine = the `Rian.Eval` interpreter → WASM/JS first (ADR-0088), self-host → JS later (no BEAM-in-WASM bridge, no server-side); the self-host engine gated on `v1==v2` + JS-reachability | 5/5 |
| API reference → native per target (EEP-48/ExDoc, rustdoc, JSDoc), linked | 5/5 |
| Keep ExDoc for the compiler's own Elixir/BEAM API | 4/5 |
| Sphinx as the portal | 3/5 (reST friction vs the Markdown corpus; strengths are layer-1, already solved) |
| One monolithic generator re-extracting all API docs | 1/5 (the Doxygen mistake, at the site layer) |

## Consequences

- The implicit ExDoc-as-portal becomes an explicit **Starlight portal**; the existing Markdown corpus
  moves in unconverted.
- **The *live* playground is gated on self-host → JS** (the *whole compiler* lowered to JS, ADR-0063) —
  not merely on the ECMAScript emitter, which has landed. So the portal starts as static docs **plus a
  no-drift gallery** now, and gains live in-browser compilation once `v1==v2` + JS-reachability land. A
  concrete downstream payoff of the bootstrap, not a parallel engine effort.
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
- **In-browser *evaluation* ships first on the reference interpreter** (`Rian.Eval` → WASM/JS,
  ADR-0088): a small total tree-walker over Core, compiled to the browser, runs an edited snippet
  ahead of any self-host. **In-browser *whole-compiler* compilation** then requires the compiler
  itself to run client-side, and that engine is self-host → JS (ADR-0027/0063) — later, not a
  precondition. FlatBars compiles trivially (PureScript→JS
  is native); Rian's compiler is Elixir-hosted, so the Rian-in-Rian compiler is lowered to a committed
  JS bundle via the ECMAScript target (ADR-0049) — FlatBars' "engine as a JS bundle", minus its WASM
  core. The two alternatives once floated are **rejected**: **BEAM-in-WASM** (AtomVM/Firefly/Popcorn)
  — no effort to be spent building an interim WASM engine to then discard; and **server-side compile**
  — the playground is static, no backend. The gate is therefore the **bootstrap fixed point `v1==v2`
  (ADR-0063) *plus* JS-reachability**: the portable-prelude breadth (ADR-0047, the `@selfhost_ffi`
  ledger driven to zero) and the `Fn` Reach gap closed — exactly the ADR-0063 §4 "portable
  self-hosting" prerequisites. Keeping the self-host on the *portable* path (no BEAM-only/host-FFI
  shortcuts) makes `v1==v2` and the JS engine land together rather than as a second slog.
- **Until then there is no *live* playground — only a static gallery.** A build-time `tour.json` of
  already-emitted multi-target output (real compiler output, the no-drift LivePane) renders *now*
  without in-browser compilation, but the reader **cannot edit and re-run** it. "Live" means
  edit-and-recompile, which is the self-host → JS engine above; the gallery is the honest interim, not
  a playground. The remaining playground work that is *engine-independent* — the editor, the `LivePane`,
  the multi-target output panel — can be built against the gallery first and gain live compilation when
  the engine lands.

## Open items

- **Portal hosting / CI** — static host (GitHub Pages / Cloudflare / Netlify) and the pinned, reproducible
  docs build (Kira); Playwright screenshot tests for the playground UI (FlatBars' `lab/test`).
- **Versioned docs** — per-release doc snapshots; align with the language-versioning policy (still open).
- **ADR rendering** — surface the design corpus in the portal (a "design" section) vs keep ADRs
  repo-only. (FlatBars renders its ADRs as Starlight pages.)
- ~~**Playground execution path** — settle (a)/(b)/(c) above.~~ **Resolved (amended by ADR-0088):** the
  `Rian.Eval` interpreter → WASM/JS ships the live engine **first** (ahead of self-host), with self-host
  → JS as the later whole-compiler engine; BEAM-in-WASM and server-side compile stay rejected. Only the
  self-host engine is gated on `v1==v2` + JS-reachability (ADR-0063 §4) — the interpreter engine is not.
  The remaining open work is the engine-independent front-end (editor / `LivePane` / multi-target panel),
  which can proceed against the static gallery now.
