# ADR-0084 — Re-platform the reference compiler from Elixir to PureScript (purerl)

**Status:** Accepted (in progress — Phase 5 underway: `Rian.JS` emitter ported; `Lower`/`JVM`/`Beam` remain)
**Implemented:** the **entire front-end + inference + gate stack is ported** and verified at
**byte-for-byte parity** against the Elixir reference — lex → `Pratt`/`Decl` parse → typed
`Core` IR → the refutation gates (`PatternLower`/`Exhaustiveness`) → the portability/capability/
expansion gates (`Reach`, `Capability`, `Macro`, `Protocol.expand`, `Coherence`) → the inference
+ return gate (`Check` `ic`/`assignable?`/error-sets, `InferLocal`, `infer_param_type`,
`effect_sets`) → the assemble tail (`Assemble`/`Comptime`). **Phase 4 is closed.** The full
purerl chain is verified end-to-end through the real library set: legacy `spago` 0.21 + the
purerl *dhall* package set → `purs` typecheck → `purerl` 0.0.24 codegen of the sources **and** the
package set → `erlc` → runs correctly on Erlang/OTP 29 (`purs/scripts/purerl-build.sh`, a
reproducible **local** gate). This proves the architecture with a runnable artifact, not an
assertion (ADR-0000). **Phase 5 (the value backend) is underway:** `Rian.JS` is ported (the
ECMAScript emitter — both print modes, Tier-1 subset; ADR-0049/0086 §5), and `Check` is fully ported
(inference + the 11-check gate + `annotate`). **What remains:** the `Lower`/`JVM`/`Beam` emitters.
The Elixir reference stays as the
parity oracle until each module's PureScript counterpart reaches parity (removal is root-first).
The per-module status table, the live parity-record count (the harness's own `N/N` total), and
the remaining work live in **`docs/purescript-migration.md`** — the single source of truth, so this
header carries no number to drift; see also `purs/README.md`. **Honesty
caveat:** the parity gate runs **locally per commit**, not in CI — fetching the pinned `purerl`
release + dhall set is a network step the CI image does not perform today (see "Consequences").
**Refs:** ADR-0000 (honesty bar — no asserted-not-proven build claims), ADR-0050
(typed Core IR as the spine the migration follows; per-target emitter structure),
ADR-0031 (toolchain-free `rian` CLI — the purerl build is a BEAM artifact, same as
today), ADR-0049 (JS/JVM/Rust backends — unchanged source emitters, now driven from
PureScript), ADR-0055/0025 (capabilities → BEAM linearity, a `Rian.Capability` FFI
concern), ADR-0057/0058 (target-set portability — the port is BEAM-hosted, so the
matrix is unchanged), ADR-0068/0081 (`@external`/effects — FFI is the same boundary)
**Owners:** Maya Lin (architecture) · Kira Neri (honesty/toolchain) · Elena Rostova
(FFI/BEAM bridge) · Samir Patel (rigor/parity) · Rachel Okafor (PM)
**Supersedes (tooling):** the Dialyzer dependency on `mix dialyzer` for the ported
modules (the type system subsumes success typing); does **not** supersede the language
ADRs — behaviour is preserved, only the implementation language changes.

## Context

`lib/rian/` is a ~29.5k-LOC compiler written in Elixir: a shared `Lexer`, the
`Decl`/`Pratt` parsers, the typed `Core` IR, the `Check`/`Exhaustiveness`/`Capability`
gates, and the `Beam`/`Lower`/`JS`/`JVM` emitters (ADR-0050). It has two structural
weaknesses that compound as the language grows:

1. **No static types.** Correctness leans on `mix dialyzer` (success typing — finds
   only *provable* contradictions, late) plus hand-written `@spec`/`@type` and the
   `@rian_sig` bridge annotations (ADR-0081). The per-feature "thread a new AST node
   through Pratt → Core → Check → every emitter" drift tax (see CLAUDE.md) is exactly
   the class of error a real type system catches at the boundary, not at runtime via a
   `FunctionClauseError`.
2. **The transpiler tail.** A second copy of the compiler exists as Rian-in-Rian
   (`compiler/*.rian`) plus a generated `rian/src` mirror; keeping the Elixir reference
   and the self-host port in step is ongoing manual work.

A decision was taken (2026-06-21) to **port the reference compiler from Elixir to
PureScript**, file by file, preserving behaviour. Two backend targets were weighed:

- **PureScript → JavaScript** (the default, mature backend). Gives static types and a
  browser-deliverable compiler (serves the playground strategy), but **cannot call
  `:compile.forms`** or load `.beam` — it would delete `Rian.Beam`, `Run`, `Repl`,
  `Roundtrip`, `Fixpoint`, and the entire BEAM self-hosting bootstrap (the project's
  flagship result: byte-identical `.beam`, v1==v2).
- **PureScript → Erlang** via **purerl**. The compiler keeps running on the BEAM; the
  five `:compile.forms` sites and the 26 modules touching `:erlang`/`:code`/`:file`/
  `:os` become **Erlang FFI** (`.erl` foreign modules), so the self-host bootstrap
  survives. Cost: purerl is a smaller ecosystem (its own package set, version-matched
  binary) and FFI is hand-written Erlang.

## Decision

**Port to PureScript with the purerl (Erlang) backend.** Static types replace the
Dialyzer crutch; purerl keeps the BEAM execution path and self-hosting bootstrap intact
through a thin, explicit Erlang-FFI boundary. The language ADRs are unchanged — this is
a re-platforming of the *implementation*, verified by behavioural parity against the
Elixir reference, not a redesign.

### Principles

- **Migrate along the Core spine, leaf-first — not alphabetically.** The dependency
  order is the build order (see `docs/purescript-migration.md`): `Token` → `Lexer` →
  `Core`/`Pratt`/`Decl` → `Check`/`Exhaustiveness` → the emitters. A module is ported
  only after everything it depends on is.
- **Reframe, don't transliterate.** Elixir tagged tuples (`{:str, s}`) become real sum
  types; `check.ex`'s `:unknown`-or-bust inference becomes types where it can. The goal
  is *idiomatic* PureScript, so a 1:1 syntactic port is explicitly rejected.
- **Parity is the gate (ADR-0000).** Each ported module ships a spec suite that asserts
  its output against the Elixir reference's recorded fixtures (the `Rian.Fixpoint`
  discipline: a port is a regression test, not a demo). A module is "migrated" only when
  the parity harness is green **and** parity holds; "compiles" is not "correct".
- **Annotate for the Phase-7 PS→Rian transpiler as you port.** The endgame transpiler is
  re-aimed from Elixir→Rian to **PureScript→Rian** (Phase 7): it lowers the ported PS
  implementation back to Rian so the compiler self-hosts and the Rust/BEAM/JS backends
  compile it. PureScript's types **underdetermine** the Rian signature — reference
  **capabilities** (`val`/`iso`/`ref`/`tag`, ADR-0025; not expressible in PS, yet they
  drive Rust ownership and BEAM linearity) and **type width/shape** (`Int`→`Int53`,
  `Array`→`Vec`, `Boolean`→`Bool`). So every ported module carries `@rian_sig` annotation
  *comments* on its public functions and struct/sum fields (form + mental model in
  `purs/README.md`). This is the surviving half of the old Elixir `@rian_sig` bridge: the
  *reader* module `Rian.Ann` is obsolete (Phase 7 reads PS `corefn` + these comments, not
  Elixir AST/`.beam`), but the **annotation convention is retained** — it is what lets the
  Rust backend lower transpiled code correctly from day one instead of defaulting `val`
  everywhere and miscompiling the owned/moved cases. Effects use the sibling marker
  `@rian_host` (→ `@effects(host)`, ADR-0048/0081), but asymmetrically: PureScript *already*
  signals effectfulness via the `Effect`/`Aff` type, so `@rian_host` only supplies the effect
  **granularity** (host vs fs vs io) at `pub` boundaries — and pure modules (the lexer's
  panics are portable `Prim.panic`, not host effects) carry none.

### FFI boundary (the BEAM-coupled modules)

purerl emits Erlang, so the VM primitives stay reachable via foreign modules:

| Elixir coupling                                   | purerl strategy                              |
| ------------------------------------------------- | -------------------------------------------- |
| `:compile.forms` (`Beam`, 5 sites)                | `.erl` FFI wrapping `compile`/`code`         |
| `:erlang`/`:code`/`:file`/`:os` (26 modules)      | typed PureScript signatures over `.erl` FFI  |
| `GenServer` (`Repl`, `Application`)               | native Erlang process modules behind FFI     |
| Regex (`Rian.Lexer` `~r//`)                       | `Data.String.Regex` (purerl `re` FFI)        |

The FFI surface is small and lives at the leaves of the dependency graph; the bulk of
the compiler (lexer → Core → checker → source emitters) is pure PureScript with no FFI.

## Consequences

- **Hybrid repo during the migration.** `lib/` (Elixir) and `purs/` (PureScript)
  coexist until the port completes; the Elixir reference is the parity oracle and is
  removed module-by-module only as its PureScript counterpart reaches parity.
- **Dialyzer retires for ported modules**; `mix dialyzer` stays meaningful only for the
  shrinking Elixir remainder.
- **Toolchain gains a non-npm dependency** (the purerl binary + its package set). The
  bootstrap is documented in `purs/README.md` and pinned in `spago.yaml`; CI must fetch
  the purerl release and package set (a network step the CI image does not perform today).
  Until it does, **the parity gate is local-per-commit, not CI-enforced** — the one
  honesty caveat on the status above: ported modules are parity-checked at authoring time,
  not re-verified on the default `mix`/CI gate.
- **The language ADRs and the by-example tour are unaffected** — same source, same
  targets, same Reach matrix. Only the compiler's host language changes.

## Risks & mitigations

- **purerl ecosystem maturity** (smaller package set, version-matched binary). *Mitigate:*
  pin exact versions; keep the FFI surface minimal; the Erlang the port runs on is the
  same OTP the Elixir tree already targets.
- **Multi-session scope** (~29.5k LOC). *Mitigate:* the leaf-first phase plan makes every
  step independently shippable and parity-gated; no big-bang cutover.
- **Parity drift** while both trees live. *Mitigate:* fixtures are generated from the
  Elixir reference and checked in; a ported module's spec fails if the reference moves.
