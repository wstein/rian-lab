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
from the Elixir reference over a 60-source corpus; the Erlang harness `lexer_parity.erl`
re-lexes with the purerl build and asserts byte-equality — **204/204 records match**, wired
into `scripts/purerl-build.sh`. The Elixir `Lexer` stays (parity oracle + all of `lib/`
still depends on it — see the DoD removal-order note).

### Phase 2 — Core IR (the spine)

| Module          | LOC | Notes / status                                                  |
| --------------- | --- | --------------------------------------------------------------- |
| `Rian.Ann`      | 173 | **Reader dropped; convention retained.** The Elixir `Rian.Ann` module (reads `@rian_sig` from Elixir AST/`.beam`) is obsolete, but `@rian_sig` annotation *comments* live on in PureScript source — they carry the **capabilities** (`val`/`iso`/`ref`/`tag`) and **type bridge** (`Int`→`Int53`, `Array`→`Vec`, …) that PS types underdetermine, read by the Phase-7 PS→Rian transpiler. See `purs/README.md`. |
| `Rian.TypeStr`  | 155 | ✅ ported (`splitTopCommas`/`splitTopPipes`/`normalize`); parity-gated (48 fixtures). |
| `Rian.IR`       | 262 | shared IR structs (data definitions).                           |
| `Rian.Core`     | 717 | `from_expr`/`from_pat`; the sealed-sum Core IR. Surface-AST input comes from `Pratt` (Phase 3), so its parity test composes with the parser. |

### Phase 3 — Parsers

| Module        | LOC  | Notes / status                                                 |
| ------------- | ---- | -------------------------------------------------------------- |
| `Rian.Pratt`  | 1218 | **Stage 1 ported** (parity-gated, `psx` stream): the full operator-precedence core, prefix/primary/postfix, calls/dots, parens/tuples/lists/maps, captures, labels, atoms — **plus patterns and `if`/`case`/`lambda`/blocks**. **Stage 2** (raises a clear "stage 2" message, excluded from the corpus): `with`, `for`/comprehension, bitstrings (+pattern), `${}` interpolation, map *update*, error-propagation `<-`, speculative destructuring binds, and type-patterns (no reference `sexpr` clause). |
| `Rian.Decl`   | 1901 | declaration parser; newline-tolerant `:=` bodies.              |

**Parity plan (Pratt).** Pratt has a built-in AST→s-expression renderer
(`parse_sexpr/1`); use it as the canonical oracle — add a `psx` stream to
`gen_fixtures.exs` comparing `Pratt.parse_sexpr(src)` against the ported
`parseSexpr`, so the harness only ever serializes output (no surface-AST
round-trip). Dependencies to port alongside: the surface-AST type (Pratt's
output), `parse`/`parse_body`/`parse_pat`, and the relevant slice of
`Rian.Prim.normalize` (`Prim.*` → `__prim_*` rewrite; identity on a `Prim`-free
corpus). Pratt is large and interconnected; if staged, scope the corpus to the
ported forms and document the gap (like the partial JS/JVM emitters). **Then**
`Core.from_expr`/`from_pat` is parity-tested by composing `lexer → Pratt → Core`
(serialize the Core canonically) — its surface-AST input comes from the ported
Pratt in-process, so no surface deserialization is needed.

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

`Prim` (97), `Prelude` (115), `Builtins` (204), `Protocol` (388), `ShowStdlib` (29),
`Range` (73), `Shadow` (114), `Opaque` (159), `Comptime` (79), `Macro` (251),
`External` (279), `Manifest` (315).

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

Phases 0–1 complete. **Phase 2**: `Rian.TypeStr` ported (parity-gated); `Rian.Ann` reader
dropped (annotation convention retained); `Rian.IR`/`Rian.Core` remain. **Phase 3**:
`Rian.Pratt` **stage 1** ported (expression core + patterns + `if`/`case`/`lambda`/blocks,
parity-gated via `psx`); stage 2 (with/for/bitstr/interp/map-update/propagation) + `Rian.Decl`
remain. `Core`'s `from_expr` now composes on the ported Pratt (lexer→Pratt→Core) for its parity
test. Each module is parity-gated and committed on its own (Conventional Commits, ADR-0084).
