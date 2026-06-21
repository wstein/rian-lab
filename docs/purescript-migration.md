# Elixir → PureScript migration roadmap

The phase plan for porting the reference compiler (`lib/`) to PureScript/purerl
(`purs/`). Governed by **ADR-0084**. Order is **dependency order = build order**: a
module is ported only after everything it depends on has reached parity.

## Definition of done (per module)

A module is **migrated** — not merely "ported" — when all hold:

1. Idiomatic PureScript in `purs/src/Rian/…` (sums over tagged tuples; types where
   `check.ex` used `:unknown`). A 1:1 transliteration does not count.
2. `./scripts/purerl-build.sh` is green — `spago build` (purs typecheck + purerl codegen)
   then the module compiles to BEAM and runs on Erlang/OTP.
3. A **parity harness** (`purs/test/*.erl`) asserts byte-equality against fixtures
   generated from the Elixir reference (`gen_fixtures.exs`) — the `Rian.Fixpoint`
   discipline — and runs inside the gate. (`spago test`'s spec/aff stack does not run under
   purerl, so the Erlang harness is the test path.)
4. FFI (if any) is a typed PureScript signature over a checked-in `.erl` foreign module.
5. The Elixir counterpart stays as the **parity oracle** until no Elixir module depends
   on it. Build order is leaf-first; **removal is root-first** — a foundational module
   (`Lexer`, `Core`) is the most-depended-on, so its Elixir twin is dropped *last*, once
   its dependents are ported. `lib/` is therefore retired in reverse-dependency order at
   the end, not module-by-module from the leaves. (The fixture generator
   `purs/test/gen_fixtures.exs` needs the Elixir `Lexer` alive, too.)

## Phases

Sizes are the Elixir source LOC (the work, not the target LOC).

### Phase 0 — Foundation ✅ (purerl chain verified end-to-end)

- `Rian.Token` — the lexer-token data spine. **Builds + runs on the BEAM** via the full
  purerl chain (`purs/scripts/purerl-build.sh`: purs → corefn → purerl → erlc → run).
- `purs/` workspace, toolchain pinning (purs 0.15.16, spago 0.93.45, purerl 0.0.24),
  ADR-0084, this roadmap.

### Phase 1 — Lexer

**Task 1a — wire the package set ✅.** Resolved with **legacy spago 0.21 + the purerl
*dhall* package set** (`packages.dhall`); `./scripts/purerl-build.sh` builds the sources
*and* the library set through purerl and runs them on the BEAM. Library-dependent modules
can now build (`strings`/`arrays`/`maybe` are available; regex FFI for the Lexer is next).

**Task 1b — port the lexer ✅.**

| Module        | LOC | Notes                                                          |
| ------------- | --- | -------------------------------------------------------------- |
| `Rian.Lexer`  | 566 | Pure port (no regex/FFI); scans a decoded `List Int` codepoint stream. |

All three streams (`tokenize`/`exprTokens`/`tokenizeTrivia`) + `detokenize`/`detokenizeWith`,
the full escape/`Char`/interpolation/`:`-atom/number grammar, in `purs/src/Rian/Lexer.purs`.
**No regex or FFI** — the scanners are hand-rolled over codepoints, which also dodges
purerl's byte-wise `Data.String.CodePoints.uncons` (only `toCodePointArray`/`singleton` are
UTF-8-correct there). **Parity:** `purs/test/gen_fixtures.exs` emits canonical token streams
from the Elixir reference; the Erlang harness — the generalized, module-dispatched
`purs/test/parity.erl` — re-lexes with the purerl build and asserts byte-equality (the lexer's
204 records, of 327 total across all ported modules), wired into `scripts/purerl-build.sh`.
The Elixir `Lexer` stays (parity oracle + all of `lib/` still depends on it — see the DoD
removal-order note).

### Phase 2 — Core IR (the spine)

| Module          | LOC | Notes / status                                                  |
| --------------- | --- | --------------------------------------------------------------- |
| `Rian.Ann`      | 173 | **Reader dropped; convention retained.** The Elixir `Rian.Ann` module (reads `@rian_sig` from Elixir AST/`.beam`) is obsolete, but `@rian_sig` annotation *comments* live on in PureScript source — they carry the **capabilities** (`val`/`iso`/`ref`/`tag`) and **type bridge** (`Int`→`Int53`, `Array`→`Vec`, …) that PS types underdetermine, read by the Phase-7 PS→Rian transpiler. See `purs/README.md`. |
| `Rian.TypeStr`  | 155 | ✅ ported (`splitTopCommas`/`splitTopPipes`/`normalize`); parity-gated (48 fixtures). |
| `Rian.IR`       | 262 | ✅ data-type records ported (`Field`/`Variant`/`Type`/`Struct`/`Prog`); the rest (`Param`/`Clause`/`Func`/`Mod`/`Const`/…) land with `Decl`'s further stages. The Rian `type` field is `ty` in PS (reserved word), bridged by `@rian_sig`. |
| `Rian.Core`     | 717 | ✅ ported (`fromExpr`/`fromPat` + the desugarings: pipe `\|>`→call, range `..`→`List.seq`, comprehension→`flat_map`); parity-gated via the `cor` stream (37 records) composing `lexer → Pratt → Core` through a shared `coreSexpr` oracle. The inferred `type` field + per-node `@rian_sig` arrive with `Rian.Check`. Staged out (excluded): pins, for-pattern generators, bitstrings, map update. |

### Phase 3 — Parsers

| Module        | LOC  | Notes / status                                                 |
| ------------- | ---- | -------------------------------------------------------------- |
| `Rian.Pratt`  | 1218 | **Ported (parity-gated, `psx` stream):** the full operator-precedence core, prefix/primary/postfix, calls/dots, parens/tuples/lists/maps, captures, labels, atoms, patterns, `if`/`case`/`lambda`/blocks, **and `with`/`for`/`${}` interpolation**. **Remaining (raise a clear message, excluded from the corpus):** bitstrings (+pattern, BEAM-only), map *update* and type-patterns (no reference `sexpr` clause → not parity-testable), and error-propagation `<-` + speculative destructuring binds. |
| `Rian.Decl`   | 1901 | **Stage 1 ported** (parity-gated, `dcl` stream, 16 records): the **data-type declarations** — `type` (sum) + `struct` (product), with `@doc`/`pub`, the `[label] [cap] Type` field grammar (caps parsed-and-dropped), union-type fields, and multi-line decls. Stage 2 (raise/excluded): `def` (signatures/clauses/bodies/`forall`), `mod`, `const`, `alias`, `range`, `opaque`/`abstract`, `use`, `protocol`/`impl`, `macro`, and the tail passes (interp/stdlib/infer-local — need `Check`/`InferLocal`/`Protocol`). |

**Parity oracle (Pratt → Core).** Pratt is verified via its built-in `parse_sexpr/1` (the
`psx` stream — output-only, no surface round-trip). `Core.from_expr`/`from_pat` then composes
on the ported Pratt (`lexer → Pratt → Core`): since Core has no built-in renderer, a shared
`coreSexpr` serializer (matching halves in `gen_fixtures.exs` and `purs/src/Rian/Core.purs`)
canonicalizes the typed Core, and the `cor` stream diffs it. The desugarings `from_expr` does
(pipe `|>` → call, range `..` → `List.seq`, comprehension → nested `flat_map`) are exactly
what the Core oracle confirms over the surface form.

### Phase 4 — Gates

| Module                | LOC  | Notes                                          |
| --------------------- | ---- | ---------------------------------------------- |
| `Rian.InferLocal`     | 250  | local inference helper.                         |
| `Rian.PatternLower`   | 149  | pattern compilation.                            |
| `Rian.Exhaustiveness` | 290  | Maranget usefulness; drives Rust `_ =>`.        |
| `Rian.Capability`     | 290  | BEAM linearity (`iso`/`ref`); FFI-adjacent.     |
| `Rian.Check`          | 2724 | unification inference — **reframe, not lift**.  |
| `Rian.Reach`          | 1235 | target-set portability inference (ADR-0057/58). |

### Phase 5 — Emitters

| Module       | LOC  | Notes / FFI                                          |
| ------------ | ---- | --------------------------------------------------- |
| `Rian.JS`    | 1053 | ECMAScript source emitter (pure).                   |
| `Rian.JVM`   | 1249 | Kotlin source emitter (pure).                       |
| `Rian.Lower` | 3275 | Elixir-text + Rust source emitter (pure).           |
| `Rian.Beam`  | 1355 | **Erlang abstract forms → `.beam`**; the core FFI.  |

### Phase 6 — Prim & stdlib support

`Prim` (97) **✅ ported** — `Prim.*`→`__prim_*` rewrite + bare `panic`, a structural
`normalize` over the surface AST (a separate pass; `Pratt.parse` stays normalize-free to
avoid a module cycle, callers compose it). Parity-gated via the `prm` stream (13 records,
oracle = the reference `parse_sexpr`). Remaining: `Prelude` (115), `Builtins` (204),
`Protocol` (388), `ShowStdlib` (29), `Range` (73), `Shadow` (114), `Opaque` (159),
`Comptime` (79), `Macro` (251), `External` (279), `Manifest` (315).

### Phase 7 — Transpiler: **PureScript → Rian** (re-aimed, not ported)

The Elixir `Transpile` (2525) + `Transpile.Infer` (1195) consume **Elixir AST → Rian**;
they are **not ported**. Instead the transpiler is re-aimed at **PureScript → Rian**: it
reads the ported PS modules plus their `@rian_sig` comments (the capability + type-bridge
info PS types underdetermine, see `purs/README.md`) and emits Rian source, so the compiler
self-hosts and the Rust/BEAM/JS backends compile it. This is why every module ported in
Phases 1–6 carries `@rian_sig` annotations on its public functions and struct/sum fields:
they are the transpiler's input, and they let the **Rust backend work from day one** on the
transpiled output (correct ownership/borrowing instead of a guessed default). Likely reads
PureScript's `corefn` JSON (already emitted by `purs`) rather than re-parsing source.

### Phase 8 — Execution & self-host (FFI-heavy)

`Interp` (252), `FormsEquiv` (245), `Roundtrip` (293), `Fixpoint` (64), `Run` (161),
`Repl`+`Repl.History` (538+89), `SelfHost` (502), `Doctest` (190), `Test` (232). These
wrap `:compile.forms`/code-loading/`GenServer` — the bulk of the Erlang FFI.

### Phase 9 — Formatter

`Format` (568), `Format.Doc` (213), `Format.CST` (67), `Format.CLI` (162),
`LSP.Formatting` (162).

### Phase 10 — CLI, Mix tasks, packaging, integrations

`CLI` (86), `Build` (458), `Pkg`+`Pkg.{Cargo,Gradle,Npm,Rebar}`, `Tour` (273),
`Livebook`+`Livebook.SmartCell`, `Application` (30), `RianLab` (38), and the
`lib/mix/tasks/*` entry points. The Mix tasks become a thin Elixir/escript shim over the
purerl-built BEAM modules (ADR-0031), or native `rian` CLI subcommands.

## Status

Phases 0–1 complete. **Phase 2**: `Rian.TypeStr` + **`Rian.Core`** ported (parity-gated);
`Rian.Ann` reader dropped (annotation convention retained); `Rian.IR` (data structs) remains.
**Phase 3**: `Rian.Pratt` ported (expression core + patterns + `if`/`case`/`lambda`/blocks +
`with`/`for`/interpolation, via `psx`); remaining: bitstrings, map-update + type-patterns,
error-propagation. **Phase 6**: `Rian.Prim` ported. **`Rian.IR`** (data-type records) + **`Rian.Decl` stage 1**
(`type`/`struct` declarations) ported. **Next:** `Rian.Decl` stage 2 — `def` (the biggest
sub-grammar: signatures with capabilities, multi-clause grouping, newline-tolerant bodies,
`forall`/bounds), then `mod`/`const`/`alias`. Total **393/393** parity records across
Lexer/TypeStr/Pratt/Core/Prim/Decl. Each module is parity-gated and committed on its own
(Conventional Commits, ADR-0084).
