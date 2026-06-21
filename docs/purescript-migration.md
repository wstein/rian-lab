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
| `Rian.Ann`      | 173 | **Dropped, not ported** — the Elixir `@rian_sig`/`@rian_host` annotation bridge is obsolete under PureScript's real types. |
| `Rian.TypeStr`  | 155 | ✅ ported (`splitTopCommas`/`splitTopPipes`/`normalize`); parity-gated (48 fixtures). |
| `Rian.IR`       | 262 | shared IR structs (data definitions).                           |
| `Rian.Core`     | 717 | `from_expr`/`from_pat`; the sealed-sum Core IR. Surface-AST input comes from `Pratt` (Phase 3), so its parity test composes with the parser. |

### Phase 3 — Parsers

| Module        | LOC  | Notes                                              |
| ------------- | ---- | -------------------------------------------------- |
| `Rian.Pratt`  | 1218 | the **one** expression+pattern parser (ADR-0050).  |
| `Rian.Decl`   | 1901 | declaration parser; newline-tolerant `:=` bodies.  |

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

### Phase 7 — Transpiler (decision point)

`Transpile` (2525) + `Transpile.Infer` (1195) port **Elixir AST → Rian**. Under purerl
this needs Elixir/Erlang-AST FFI. **Open question for ADR-0084:** once the compiler is
self-hosting in PureScript, the Elixir-source transpiler may be retired rather than
ported — decide before starting this phase.

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

Phase 0 complete (purerl chain verified end-to-end on `Rian.Token`). **Phase 1 complete**:
the package set is wired (Task 1a) and `Rian.Lexer` is ported at full parity (Task 1b,
204/204 fixture records). Phases 2–10 proceed one module at a time, each parity-gated and
committed on its own (Conventional Commits, ADR-0084 cited). Next: Phase 2 (the Core IR).
