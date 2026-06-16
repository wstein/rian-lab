# ADR-0038 — Language Server (LSP): a tolerant analysis layer over the compiler library

**Status:** Accepted (direction) · implementation sequenced with ADR-0031 Stages 0.1→0.3
**Implemented:** no — no language-server code exists (no LSP module/test); only the syntactic TextMate grammar under `editors/vscode/` ships
**Refs:** ADR-0026 (BEAM/ecosystem, no fork) · ADR-0030 (declarative/sandboxed macros) · ADR-0031 (bootstrap; reuse the runtime, not the compiler) · ADR-0033/0034 (vocabulary, type-system foundations) · editors/vscode (existing TextMate grammar)
**Owners:** Kira Neri (toolchain, server) · Maya Lin (architecture/library boundary) · Chloe Bennett (parser / error recovery) · Arthur Pendelton (incremental checking) · Marcus Webb (sandbox/security) · Samir Patel (rigor/conformance) · Elena Rostova (semantic features) · Liam Davis (ecosystem) · Rachel Okafor (PM)

## Context

Rian wants to be a first-class, best-in-class IDE citizen: diagnostics, hover types,
go-to-definition, completion, document/workspace symbols, semantic highlighting, rename, and
formatting — in any editor, via the Language Server Protocol (LSP).

We already ship **syntactic** highlighting: a TextMate grammar and VSIX
([editors/vscode/rian/syntaxes/rian.tmLanguage.json](../../editors/vscode/rian/syntaxes/rian.tmLanguage.json)).
We do **not** ship anything *semantic*. The front-end that an LSP would stand on is real but young:
[`Rian.Lexer`](../../lib/rian/lexer.ex), [`Rian.Decl`](../../lib/rian/decl.ex) (parses `type`/`struct`/
`alias`/`def`; `mod` in progress), [`Rian.Check`](../../lib/rian/check.ex) (one conservative inference
increment), and [`Rian.Exhaustiveness`](../../lib/rian/exhaustiveness.ex).

Two structural facts collide and frame the entire debate:

1. **The compiler is a *gate*, not an *analyzer*.** The exhaustiveness pass **refuses to emit** on a
   non-total or dead match; `Rian.Decl` is fail-fast recursive descent. An editor, by contrast, sees
   *broken, half-typed code 100% of the time*. A tool that aborts on the first error is useless in an
   editor.
2. **We are mid-bootstrap (ADR-0031).** The front-end is written in Elixir today and will be rewritten
   in Rian at Stage 1. Anything we build on the front-end *now* inherits that future swap.

This ADR fixes the **architecture and sequencing** of the language server. It does not specify every
LSP method. What follows is the team debate, recorded, because the disagreements are load-bearing.

---

## The debate

### Round 1 — framing and the first fight: when, and in what language

**Rachel Okafor (PM):** I'll be the skeptic up front. We cannot parse `mod` yet. The surface is four
declaration forms. `Rian.Check` infers `:unknown` for almost everything. Building a "best-in-class"
LSP now is gold-plating a language that can't yet compile a real program. My proposal: **defer the
LSP entirely until Stage 0.3.** Rating of "full LSP now": **1/5**.

**Kira Neri (toolchain):** I'll push back hard, and not with vibes. The evidence cuts the other way:
the languages with the best tooling co-evolved the tooling *with* the language — rust-analyzer was
built alongside Rust's maturation, not bolted on a decade later; gopls and TypeScript's `tsserver`
shaped their languages' ergonomics. The languages that deferred tooling (the long tail of "we'll do
the IDE later") shipped servers that are *still* second-class because the compiler was never designed
to be re-entrant or tolerant. **Tooling is a design constraint on the compiler, not a downstream
consumer.** If we wait until Stage 0.3, the front-end will have hardened around fail-fast assumptions
that are expensive to reverse. Rating "start the LSP now, scoped to what the compiler can support":
**4/5**.

**Maya Lin (architecture):** Both of you are arguing about *timing* and skipping the question that
actually determines cost: **where does the server live, and what does it consume?** There are three
candidate answers and they are not equal:

- **(A)** Server in Elixir, calling the existing front-end *as a library*.
- **(B)** Server in Rust (`tower-lsp`), reimplementing a tolerant Rian front-end for speed.
- **(C)** Wait for self-host, write the server in Rian (dogfooding).

(B) is a trap we already named in ADR-0031: it forks the front-end. We would maintain *two* Rian
parsers and they would drift — and we already have a documented drift problem between the emitter and
the linearity checker. (C) is circular: no LSP until self-host, but self-host is exactly the kind of
large Rian program whose authors would *want* an LSP. So the answer is **(A)** — but only if we are
disciplined about the boundary. Rating (A): **5/5**; (B): **2/5**; (C): **1/5 as a starting point**.

**Liam Davis (ecosystem):** (A) has a bonus the others miss, and it's not generic "BEAM is nice." An
LSP server is a **long-lived, stateful, concurrent process** handling overlapping requests with
cancellation — that is *precisely* the workload OTP exists for. rust-analyzer had to hand-roll an
async cancellation runtime; `tsserver` is single-threaded and has fought that for years. We get
supervised processes, per-document actors, and backpressure **for free** from the runtime we already
target (ADR-0026). The Elixir LSP lineage proves it runs — ElixirLS, and the newer GenLSP-based
servers (Next LS, Lexical). Reuse **GenLSP** for transport; do **not** inherit ElixirLS's monolithic
architecture or its reputation for latency. Rating "GenLSP transport + OTP per-document actors":
**4/5**.

**Maya Lin:** Agreed on OTP-as-runtime, with one guardrail: that's a *runtime* advantage, not a
license to couple the analysis logic to OTP. The analysis must be a pure-ish library the server
*drives*, so Stage 1 self-host can re-target it.

### Round 2 — the real problem: the gate vs. the editor

**Arthur Pendelton (compilers):** Here's the uncomfortable part nobody's said plainly. My
exhaustiveness pass is *designed to refuse*. That's a feature for `mix compile` and a disaster for an
editor. An LSP needs the front-end to run **to completion on invalid input** and return *partial*
results plus diagnostics — a non-total `case` should surface as a squiggle, not abort the analysis of
the other 200 functions in the file. The compiler today has exactly one mode: succeed-or-raise. I do
**not** think we can hand-wave this. Demand-driven, resilient analysis is a different engine.

**Chloe Bennett (parser):** And it starts at *my* layer, before yours. `Rian.Decl` is fail-fast
recursive descent: first unexpected token, it raises. Error recovery — synchronizing to the next
`def`/`type`, emitting an error node, continuing — is genuine work, and it is the single most
important LSP feature, because **error recovery is what makes every other feature work while you
type.** rust-analyzer's entire design thesis is a *lossless, error-resilient* syntax tree (rowan);
Roslyn's is red-green trees for the same reason. So I'll put the controversial proposal on the table:
**build a separate resilient CST parser for the LSP**, leave `Rian.Decl` as the strict compiler
parser. Two parsers, each good at its job. Rating: **3/5** — and I'm rating my own idea a 3 on
purpose, because…

**Maya Lin:** …because it's the drift trap again. Two parsers for one grammar is exactly the failure
mode the corpus already warns about ("no single typed core IR"). When the grammar changes — and it
will, constantly, through Stage 0.3 — the strict and tolerant parsers fall out of sync and the LSP
starts lying about a language the compiler no longer accepts. **Veto on two parsers.** Counter-
proposal: make `Rian.Decl` *itself* error-recovering — one parser, two modes (`strict` raises;
`tolerant` collects diagnostics and emits partial/error nodes). Rating: **4/5**.

**Chloe Bennett:** I'll concede the drift point is stronger than my separation point — *if* the
tolerant mode can produce a tree that's actually lossless enough for ranges and incremental reparse.
Recursive-descent error recovery is harder to get good than a hand-written CST, and bad recovery
produces *worse* squiggles than no recovery. So my concession is conditional: one parser, but the
tolerant mode is a **first-class requirement with its own test corpus**, not a flag we bolt on and
hope. If we under-invest, we ship a server that cascades twelve fake errors from one missing paren —
the classic LSP failure. Revised rating for "single parser, tolerant mode as a first-class subproject":
**4/5**.

**Julian Vance (grammar):** Backing Chloe on the rigor, opposing her original split. Error-recovery
quality is a *grammar* property — synchronization points (`def`, `type`, `mod`, `end`, newline-at-
column-0) must be designed, not discovered. The good news: Rian's family surface (ADR-0032) has
strong, unambiguous declaration keywords, which are *excellent* recovery anchors — better than C's
brace soup. We should exploit that. Rating "keyword-anchored recovery": **5/5** on feasibility.

**Arthur Pendelton:** Fine — if the parser yields partial trees, my analyses can be made tolerant:
each `def` is checked independently, a failure in one is a diagnostic scoped to that node, the rest
proceed. But I want to **separate the gate from the analyzer cleanly**: the *same* exhaustiveness
logic runs in both, but in compiler mode a non-total match is a hard error (no emission) and in LSP
mode it's a `Diagnostic` with a witness as the message. One algorithm, two *severities*, not two
implementations. That keeps the editor and the compiler telling the *same truth*. Rating: **5/5**.

### Round 3 — incrementality: how much engine do we actually need

**Kira Neri:** The architecture I'd *love* is full demand-driven incremental computation — Salsa, the
way rust-analyzer does it: every query (parse, resolve, infer) is memoized and invalidated by
fingerprint, so a keystroke recomputes the minimum. It's why rust-analyzer feels instant on huge
crates. Proposal: **adopt a Salsa-style query engine from day one.** Rating: **3/5** — and I'll argue
*against* my own 5-star instinct here.

**Rachel Okafor:** Good, because I was about to. A query engine is months of infrastructure to make a
four-declaration-form language feel instant on files that are 40 lines long. That is the definition of
premature optimization. What's the corpus size we're optimizing for — the whole `lib/rian/` is what,
a few thousand lines?

**Samir Patel (rigor):** This is where I want **numbers, not adjectives**, because "best-in-class" is
unfalsifiable otherwise. The LSP performance contract that actually matters to users is *latency
percentiles*: keystroke-to-diagnostic under ~100 ms, completion under ~50 ms (the figures the LSP
community treats as the "feels instant" threshold). I propose we **set those budgets as test
assertions** and only add incrementality *when a budget is violated on a representative corpus*.
Re-analyzing a single changed file synchronously will hold those budgets until files get large or
cross-file resolution gets deep. Rating "latency budgets as CI gates; incrementality is demand-
driven *by the budget*": **5/5**.

**Maya Lin:** That's the synthesis. **Per-file batch analysis now**, behind a query-shaped *interface*
(functions keyed by document URI + version) so that swapping in memoized incrementality later is an
implementation change, not an API break. Design for the seam, don't build the engine. Rating: **5/5**.

**Kira Neri:** I'll take it. Design the query interface so Salsa-ification is a drop-in; ship batch.
That actually de-risks my 3/5 — I get the architecture without the upfront cost. Agreed.

**Arthur Pendelton:** One caveat for the record: cross-file resolution (go-to-def across modules,
workspace symbols) is where batch falls over, because one edit can invalidate dependents. We will hit
the incrementality wall *there* first, not within a file. Let's not pretend per-file batch is the end
state — it's the honest *start* state.

### Round 4 — how smart can it actually be, and the security one nobody likes

**Elena Rostova (semantic features):** A reality check on "best-in-class," because I own the features
that would justify the phrase and I can't deliver them yet. Hover-types, signature help, and type-
aware completion are only as good as `Rian.Check`, which currently infers `:unknown` for nearly
everything and rejects only provable mismatches (ADR-0034 is "direction," not an engine). If we
advertise rich semantic hover today, we lie. So I want LSP capabilities **explicitly tiered to
compiler maturity**, advertised honestly over the protocol:

- **Tier 0 (works off the parser + exhaustiveness, today):** diagnostics, document symbols, folding,
  semantic tokens, formatting hooks.
- **Tier 1 (needs name resolution):** go-to-definition, find-references, workspace symbols, basic
  completion.
- **Tier 2 (needs real inference, ADR-0034):** hover types, type-aware completion, signature help,
  flow-narrowed information.
- **Tier 3 (needs a resolved semantic model):** rename, extract-function, code actions.

Rating "capability tiering bound to compiler maturity, declared truthfully in `ServerCapabilities`":
**5/5**. The server should announce *only* what it can actually do at each stage.

**Marcus Webb (sandbox/security):** Now the part everyone wants to skip. Several of those features —
hover-through-macro, go-to-def into an expansion, completion inside a `comptime` block — require
**running macro/comptime expansion on every keystroke, on untrusted code, inside the editor process.**
That is a live attack surface. rust-analyzer's proc-macro server executes arbitrary build-time code
and has been a documented supply-chain and DoS vector — open a malicious repo, the LSP runs its
macros. I will **block** any design that expands macros eagerly in the editor without a sandbox.

**Arthur Pendelton:** ADR-0030 helps you more than you're crediting. Rian macros are *declarative,
hygienic, pattern→template* and comptime is *pure* — by construction they're not the arbitrary-native-
code model that bit rust-analyzer. There's no `quote`/`unquote` escape hatch into the host.

**Marcus Webb:** "Pure" still isn't "free" or "bounded." A pattern→template expansion can still be
pathological — exponential expansion, non-termination if comptime gains any recursion. So my proposal
stands, just calibrated: **expansion in the LSP is opt-in, resource-limited (time + memory + expansion-
depth fuel), and runs in a separate supervised OTP process that can be killed without taking the
server down.** OTP makes this *cheap* — that's a concrete BEAM advantage Liam can bank. Rating: **5/5**,
and this is a gate, not a suggestion.

**Liam Davis:** Confirmed cheap on OTP — isolated process, `Task` with timeout, supervisor restart. I'll
own that. And it doubles as crash isolation: a parser bug on weird input kills one document actor, not
the session.

### Round 5 — the syntactic/semantic highlighting fight, and editor reach

**Liam Davis:** Smaller but real: we already ship a TextMate grammar. LSP **semantic tokens** are more
precise (they know `foo` is a type vs. a function). Do semantic tokens make the TextMate grammar
obsolete? I say **no, keep both**: TextMate paints instantly on file-open with *no server*, and is the
fallback when the server is down or starting. Semantic tokens refine it once analysis lands. Editors
that compose the two (VS Code does) get the best of both. Deleting the grammar to "do it properly in
LSP" would be a regression in first-paint latency. Rating "keep TextMate as fast-path + fallback,
layer semantic tokens on top": **4/5**.

**Kira Neri:** Agreed, and it generalizes to editor reach: one **generic LSP server speaking standard
protocol** gets us VS Code, Neovim, Helix, Zed, Emacs (eglot), JetBrains — *every* editor — from a
single implementation. That's the actual mechanism for "first-class in every IDE": not N extensions,
but one conformant server + thin per-editor shims. The VS Code extension we have becomes a thin client
that launches the server. Rating: **5/5**.

**Samir Patel:** Which only holds **if we test against the protocol, not against one editor.** I want a
conformance harness that drives the server with raw LSP JSON-RPC and asserts on responses + latency,
editor-independent. Otherwise "works in VS Code" silently means "broken in Helix." Rating "protocol-
level conformance corpus + latency budgets in CI": **5/5**.

### Round 6 — the bootstrap collision

**Maya Lin:** Last load-bearing issue, and it's the ADR-0031 collision. If we write the server's
analysis in Elixir coupled to today's front-end, then at Stage 1 (self-host in Rian) we either
maintain two analyzers forever or rewrite the LSP. That is *the exact mistake ADR-0031 forbade for the
backend* — coupling to the interim host. The discipline that saves us: the server consumes the front-
end through a **stable library API** (`analyze(uri, version, src) -> {diagnostics, symbols, tokens,
…}`), the *same* API the future Rian-hosted front-end will expose. The server is a thin protocol
adapter over that API. Swap the implementation language under the API and the server is unchanged —
identical to the backend-swap logic in ADR-0031's roadmap. Rating "server depends only on a stable
analysis API, never on internal Elixir structs": **5/5**.

**Chloe Bennett:** Concretely that means the tolerant parser and the analyses return **plain data**
(positions, ranges, severities, symbol kinds) — not `Rian.IR` structs the server reaches into. The API
is the contract; the IR stays private. I'm in.

**Rachel Okafor:** I came in at 1/5 on "full LSP now" and I'll move — *conditionally*. What changed my
mind: nobody is actually proposing "full LSP now." The proposal that emerged is **a thin, honestly-
tiered server over a stable API, starting at Tier 0, with the expensive pieces (incrementality, rich
inference, refactors) explicitly deferred and budget-gated.** That's not gold-plating; that's building
the seam early so the language is shaped by tooling pressure, which Kira's evidence supports. My
revised rating for *that* scoped proposal: **4/5**. I still hold the line that Tier 2/3 features must
not be started before `Rian.Check` earns them.

---

## Decision

Build a Rian language server as a **thin LSP protocol adapter over a stable compiler *analysis API*** —
not a fork, not a second front-end. Six pillars, each carrying its debate's consensus.

### 1. Library boundary, not a fork (Maya; consensus)
The server consumes the front-end through a **stable, data-only analysis API** keyed by `(uri,
version, src)`, returning plain diagnostics/symbols/tokens/ranges — never internal `Rian.IR` structs.
This makes the Stage 1 self-host swap invisible to the server, exactly as ADR-0031 makes the backend
swap invisible to the language. **No second parser** (Maya's veto on Chloe's split, Chloe concurring).

### 2. One parser, two modes; one gate, two severities (Chloe + Arthur; consensus)
`Rian.Decl` gains a **tolerant mode**: keyword-anchored error recovery (`def`/`type`/`mod`/`end`/
column-0), partial trees, error nodes, collected diagnostics — `strict` mode still raises for the
compiler. The exhaustiveness/type logic is **one implementation run at two severities**: hard error
(no emission) for `mix compile`, `Diagnostic` (with witness) for the LSP. Editor and compiler tell the
**same truth**. The tolerant mode is a first-class subproject with its own corpus, not a flag.

### 3. Host in Elixir on OTP; reuse GenLSP; per-document actors (Liam; consensus)
The server runs on the BEAM (ADR-0026): GenLSP for JSON-RPC transport, **one supervised actor per open
document**, OTP cancellation/backpressure. We reuse the *transport* lineage, **not** ElixirLS's
monolith. The long-lived-concurrent-stateful-server workload is OTP's home turf — a structural
advantage over hand-rolled async runtimes.

### 4. Per-file batch now, behind a query-shaped interface (Kira + Rachel + Samir; synthesis)
Ship **per-file batch analysis**, but expose it through a query-shaped, version-keyed interface so a
Salsa-style memoized incremental engine is later a drop-in, not an API break. **Latency budgets are CI
assertions** (~100 ms keystroke→diagnostics, ~50 ms completion); incrementality is added **only when a
budget is violated** on a representative corpus. Cross-file resolution is the acknowledged first place
batch will break (Arthur's caveat).

### 5. Capabilities tiered to compiler maturity, declared honestly (Elena; consensus)
The server advertises in `ServerCapabilities` **only** what the compiler can back:
- **Tier 0 (now):** diagnostics, document symbols, folding, semantic tokens, formatting.
- **Tier 1 (name resolution):** go-to-def, find-refs, workspace symbols, basic completion.
- **Tier 2 (real inference, ADR-0034):** hover types, type-aware completion, signature help, flow-
  narrowed info.
- **Tier 3 (resolved semantic model):** rename, extract-function, code actions.
No feature is advertised before the compiler earns it (Rachel's standing condition).

### 6. Macro/comptime expansion is sandboxed and opt-in (Marcus; gate, not suggestion)
In-editor expansion runs **opt-in**, in a **separate supervised OTP process**, **resource-limited**
(time, memory, expansion-depth fuel), killable without dropping the session. ADR-0030's declarative/
pure model shrinks the surface but does **not** waive the limits.

### Highlighting & reach (Liam + Kira; consensus)
Keep the **TextMate grammar** as the zero-server fast-path and fallback; **layer semantic tokens** on
top once analysis lands. Ship **one generic protocol-conformant server** + thin per-editor shims (VS
Code extension becomes a launcher) — that is the mechanism for "first-class in every IDE," not N
bespoke integrations.

## Ratings

| Proposal | Rating | Whose call |
|---|---|---|
| Thin server over a stable data-only analysis API (no fork) | 5/5 | Maya |
| One parser, tolerant mode as a first-class subproject | 4/5 | Chloe (revised up from 3) |
| One gate algorithm, two severities (error vs. diagnostic) | 5/5 | Arthur |
| Host on OTP; GenLSP transport; per-document actors | 4/5 | Liam |
| Per-file batch behind a query-shaped interface; budget-gated incrementality | 5/5 | Maya/Kira/Samir |
| Latency budgets as CI assertions | 5/5 | Samir |
| Capability tiers bound to compiler maturity, declared honestly | 5/5 | Elena |
| Sandboxed, opt-in, fuel-limited in-editor expansion | 5/5 (gate) | Marcus |
| Keep TextMate fast-path + layer semantic tokens | 4/5 | Liam |
| One generic server + thin per-editor shims | 5/5 | Kira |
| *Rejected:* fork a Rust/`tower-lsp` front-end | 2/5 | (Maya: drift) |
| *Rejected:* separate CST parser for the LSP | 3/5 | (Chloe withdrew; Maya veto) |
| *Rejected:* full Salsa query engine on day one | 3/5 | (Kira withdrew; premature) |
| *Rejected:* defer the LSP entirely to Stage 0.3 | 1/5 | (Rachel moved to conditional yes) |
| *Rejected:* eager in-editor macro expansion, unsandboxed | 1/5 | (Marcus block) |

## Consequences

- **A new compiler obligation:** `Rian.Decl` must grow a **tolerant parse mode** with keyword-anchored
  recovery. This is now the highest-leverage LSP prerequisite and should be designed *into* the parser
  as `mod` lands (ADR-0031 Stage 0.1), not retrofitted later.
- **The analysis passes gain a "diagnostic" severity path.** Exhaustiveness and `Rian.Check` must
  return structured findings (range + severity + witness/message) in addition to their gate behavior —
  same logic, reporting layer added.
- **A stable `analyze/3`-shaped API becomes a maintained contract** (data-only), which the Stage 1
  self-hosted front-end must also satisfy. This *constrains* the self-host rewrite — deliberately.
- **OTP is load-bearing for the toolchain, not just the runtime** — per-document actors, sandboxed
  expansion workers, supervised crash isolation. A genuine, specific BEAM advantage (ADR-0026), not
  generic praise.
- **The VS Code extension evolves** from a TextMate-only package into a thin LSP client launching the
  server; the grammar stays as fast-path/fallback.
- **"Best-in-class" is now falsifiable:** it means meeting the latency budgets and passing the
  protocol-conformance corpus at each tier — not a slogan.

## Future developments

- **Salsa-style incremental engine** swapped in behind the query interface once cross-file resolution
  or corpus size violates a latency budget (Arthur: cross-file is where it bites first).
- **Lossless CST** (rowan/red-green-tree style) if recursive-descent recovery proves insufficient for
  Tier 3 refactors — revisits Chloe's original idea on evidence, not preference.
- **`mix`/Hex integration** (ADR-0026): project model, dependency symbols, workspace-wide analysis.
- **Self-hosted server (Stage 1+):** re-implement the analysis library in Rian under the same API; the
  protocol adapter is untouched — the dogfood payoff.
- **DAP (debugging)** and **test-explorer** integration once a runtime/test story exists.
- **Formatter** as a shared library backing both `lsp/formatting` and a CLI `rian fmt`. **Shipped**
  ([ADR-0045](0045-formatter.md)): [`Rian.Format`](../../lib/rian/format.ex) is the canonical owner —
  meaning-preserving, idempotent, comment-preserving, wraps to 98 columns, and **total** (never raises;
  unlexable input returned unchanged, which is exactly the format-on-save "never corrupt the buffer"
  contract). `lsp/formatting` becomes a thin `format/1` call; `rangeFormatting` (format a sub-region
  inheriting surrounding indent) is the remaining LSP-side work.

## Concrete next steps (sequenced)

1. **Tolerant parse mode in `Rian.Decl`** (keyword-anchored recovery, partial trees, diagnostics) —
   designed in alongside `mod`. *Prerequisite for everything else.*
2. **`analyze(uri, version, src)` data-only API** returning diagnostics + document symbols + semantic
   tokens — Tier 0, off the existing parser + exhaustiveness.
3. **GenLSP server skeleton** on OTP: per-document actor, `initialize` advertising *only* Tier 0
   capabilities, wired to (2).
4. **Protocol-conformance harness + latency budgets** in CI (Samir) — raw JSON-RPC, editor-independent.
5. **Semantic tokens** layered over the TextMate grammar; VS Code extension becomes an LSP client.
6. **Tier 1** (go-to-def/refs/symbols) once name resolution lands; **Tier 2** gated on `Rian.Check`
   maturity (ADR-0034); **sandboxed expansion worker** (Marcus) before any expansion-dependent feature.

## Open items

- **Recovery-quality bar:** what counts as "good enough" error recovery (max cascaded fake diagnostics
  per real error)? Needs a metric in the conformance corpus (Chloe + Samir).
- **Name resolution model** for ADR-0029 dot syntax in a *tolerant* tree (Rian module vs. Elixir-stdlib
  vs. field) — unresolved, and Tier 1 depends on it.
- **Cross-file invalidation** strategy when batch hits its wall (Arthur) — coarse (whole workspace) vs.
  dependency-tracked.
- **Expansion fuel limits** — concrete time/memory/depth defaults for the sandbox (Marcus).
- ~~**Formatter ownership** — is there a canonical Rian formatting style yet to back `lsp/formatting`?~~
  **Resolved & shipped by [ADR-0045](0045-formatter.md):** one canonical zero-config style; the
  formatter (`Rian.Format`, a bracket CST + Wadler/Lindig pretty-printer) is the canonical owner.
  `lsp/formatting` delegates to its total `format/1`. Remaining LSP-side: `rangeFormatting`.
- **Structural-union hover** (the ADR-0034 open item) — how Tier 2 hover renders narrowed/union types.
