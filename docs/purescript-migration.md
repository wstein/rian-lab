# Elixir → PureScript migration roadmap

The phase plan for porting the reference compiler (`lib/`) to PureScript/purerl
(`purs/`). Governed by **ADR-0084**. Order is **dependency order = build order**: a
module is ported only after everything it depends on has reached parity.

## Definition of done (per module)

A module is **migrated** — not merely "ported" — when all hold:

1. Idiomatic PureScript in `purs/src/Rian/…` (sums over tagged tuples; types where
   `check.ex` used `:unknown`). A 1:1 transliteration does not count.
2. `npx spago build` is green (typechecks under purerl).
3. A spec in `purs/test/` asserts **parity** against the Elixir reference's recorded
   fixtures (the `Rian.Fixpoint` discipline). `npx spago test` is green.
4. FFI (if any) is a typed PureScript signature over a checked-in `.erl` foreign module.
5. The Elixir counterpart is removed from `lib/` in the **same** phase (no dead
   duplicate), and its docs/ADR references are repointed.

## Phases

Sizes are the Elixir source LOC (the work, not the target LOC).

### Phase 0 — Foundation ✅ (purerl chain verified end-to-end)

- `Rian.Token` — the lexer-token data spine. **Builds + runs on the BEAM** via the full
  purerl chain (`purs/scripts/purerl-build.sh`: purs → corefn → purerl → erlc → run).
- `purs/` workspace, toolchain pinning (purs 0.15.16, spago 0.93.45, purerl 0.0.24),
  ADR-0084, this roadmap.

### Phase 1 — Lexer

**Task 1a — wire the package set (blocker).** purerl's package set is a legacy *dhall*
set spago 0.93 cannot consume; the Lexer needs `strings`/`arrays`/`maybe`/regex. Resolve
via legacy spago (0.21, dhall) or `extraPackages` git deps generated from the dhall set,
then `npx spago build`/`spago test` becomes the gate for all library-dependent modules.

**Task 1b — port the lexer.**

| Module        | LOC | Notes / FFI                                            |
| ------------- | --- | ----------------------------------------------------- |
| `Rian.Lexer`  | 566 | `~r//` → `Data.String.Regex`; codepoint scan via FFI. |

The three streams (`tokenize`/`expr_tokens`/`tokenize_trivia`) + `detokenize`. First
real FFI surface (regex, `String.next_codepoint`). Parity fixtures: token streams for
the existing lexer test corpus.

### Phase 2 — Core IR (the spine)

| Module          | LOC | Notes                                             |
| --------------- | --- | ------------------------------------------------- |
| `Rian.Ann`      | 173 | annotation model.                                 |
| `Rian.TypeStr`  | 155 | type pretty-printer.                              |
| `Rian.IR`       | 262 | shared IR structs.                                |
| `Rian.Core`     | 717 | `from_expr`/`from_pat`; the sealed-sum Core IR.   |

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

Phase 0 complete (the purerl chain is verified end-to-end on `Rian.Token`). Phases 1–10
proceed one module at a time, each parity-gated and committed on its own (Conventional
Commits, ADR-0084 cited). Phase 1 begins by wiring the purerl package set.
