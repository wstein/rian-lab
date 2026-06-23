# Elixir → PureScript migration roadmap

The phase plan for porting the reference compiler (`lib/`) to PureScript/purerl
(`purs/`). Governed by **ADR-0084**. Order is **dependency order = build order**: a
module is ported only after everything it depends on has reached parity.

> **Target reframe (ADR-0090).** The port's *primary* deliverable is the **JS compiler**
> (browser playground + npm/node CLI), built by stock `purs`'s native **JS backend**. **purerl /
> BEAM is recast as the parity oracle** (byte-equality vs the Elixir reference, the DoD below) plus
> the self-host / BEAM-retention path (ADR-0063). The type-safety-over-Dialyzer win of ADR-0084
> stands as a *means*, not the motive. Concretely: **`Rian.JS` (Phase 5) is the priority emitter** —
> it is both the next migration step *and* the live-playground engine (ADR-0090 §1, §7). **The JS-backend
> build profile has landed** (`purs/spago-js.dhall` + `packages-js.dhall` over the standard JS package
> set; `HostRef.js` the conservative-accept FFI stub; `scripts/js-build.sh`): the whole PureScript
> compiler compiles to JS via stock `purs` and `Rian.JS.compile` runs in node — the in-browser
> playground's compiler prerequisite. (One wide-int build-parity caveat remains (ADR-0090 §6):
> `Check`'s `Int8`…`UInt128` range bounds compare in `Number` — exact through 2⁵³, i.e. every type up
> to `Int53`/`UInt32` — but the `Int64`/`Int128`/`UInt64`/`UInt128` bounds exceed it, so a literal at
> the far edge of those widths is not range-checked on the JS backend.)

## Definition of done (per module)

A module is **migrated** — not merely "ported" — when all hold:

1. Idiomatic PureScript in `purs/src/Rian/…` (sums over tagged tuples; types where
   `check.ex` used `:unknown`). A 1:1 transliteration does not count.
2. `./scripts/purerl-build.sh` is green — `spago build` (purs typecheck + purerl codegen)
   then the module compiles to BEAM and runs on Erlang/OTP.
3. A **parity harness** (`purs/test/*.erl`) asserts byte-equality against fixtures
   generated from the Elixir reference (`gen_fixtures.exs`) — the parity discipline (a
   port is a regression test, not a demo) — and runs inside the gate. (`spago test`'s spec/aff stack does not run under
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
| `Rian.IR`       | 262 | ✅ all data-type records ported (`Field`/`Variant`/`Type`/`Struct`/`Prog` plus `Param`/`Clause`/`Func`/`Mod`/`Const`/`Protocol`/`ImplDecl`/`MacroDef`). A clause body is the `Body = Raw String \| Expanded Surface` ADT (read through `bodySurface`), mirroring the reference's `String \| ast` body while keeping the idempotent re-parse. The Rian `type` field is `ty` in PS (reserved word), bridged by `@rian_sig`. |
| `Rian.Core`     | 717 | ✅ ported (`fromExpr`/`fromPat` + the desugarings: pipe `\|>`→call, range `..`→`List.seq`, comprehension→`flat_map`); parity-gated via the `cor` stream (37 records) composing `lexer → Pratt → Core` through a shared `coreSexpr` oracle. `CExpr` is a sealed sum; rather than a `nil`-defaulted per-node `type` field (the DoD's rejected "1:1 transliteration"), the inferred type lives in a *separate* annotated tree `TExpr` that `Check.annotate` produces (see the `Rian.Check` row). Staged out (excluded): pins, for-pattern generators, bitstrings, and map update. (`struct_lit`/`EStruct` for `Name(f: v)` construction and `EConstRef`/`PTyped` landed in Phase 5 — see the `Rian.JS` row.) |

### Phase 3 — Parsers

| Module        | LOC  | Notes / status                                                 |
| ------------- | ---- | -------------------------------------------------------------- |
| `Rian.Pratt`  | 1218 | **Ported (parity-gated, `psx` stream):** the full operator-precedence core, prefix/primary/postfix, calls/dots, parens/tuples/lists/maps, captures, labels, atoms, patterns, `if`/`case`/`lambda`/blocks, **`with`/`for`/`${}` interpolation**, and **error-propagation `<-` + speculative destructuring binds**. **Remaining (raise a clear message, excluded from the corpus — none are in the portable surface):** bitstrings (+pattern, BEAM-only), and map *update* + type-patterns (no reference `sexpr` clause → not parity-testable). **`parseBody`** (the `;`-separated statement-block body parser) is exposed — the prerequisite for re-parsing a function body (`Shadow`/`Check.infer_return_type`). |
| `Rian.Decl`   | 1901 | **All declaration forms ported** (parity-gated, `dcl` + `prc` streams, 74 records): **data-type declarations** (`type`/`struct`), **`def`** (single-/multi-clause, `:=` bodies, capabilities, `build_func` grouping, head patterns, `forall`), **`mod`/`const`/`use`/`alias`** (nested `assemble`, alias subst), and **`range`/`opaque`** (ordinal bounds; range name substitutes to its `base`), `const` (explicit + literal-inferred type), `use` (qualified + selective), **alias substitution** (whole-word, transitive to a fixpoint, over all type positions), **`def` block bodies** (`def … Ret <nl> body <nl> end` — `take_block` depth-counts the matching `end`; `block_seps`/`detok_block` rewrites a top-level newline to a `;` while tracking nested `do`/`end`, brackets, and `with`-headers), and **`@external(:target, spec)`** (ADR-0068 — target-scoped FFI bodies on a bodiless `def`: a string spec, a `Mod.fun`/`:erlang.fun` reference, or a `"path", "fun"` file ref), and **`abstract Name := Base do … end`** (ADR-0067 — an `opaque` carrying `op`/`to` operator/cast rules, parsed via `extractParens`/`parseParams` and rendered to a canonical per-member string), plus **`protocol`/`impl`** (program-global, hoisted out of any `mod`; the `prc` stream serializes the protocol/impl IR **synthesis-free** — the reference's `Protocol.expand` dispatcher/`impl_*` injection is the assemble tail, now ported in **`Rian.Assemble`**, `asm` stream) and **`macro`** (`macro` defs preserved on `Prog.macros` for the `lower_meta` tail; **`Rian.Assemble`** expands them into `Expanded` clause bodies, `mxb` stream). |

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
| `Rian.InferLocal`     | 250  | ✅ ported — `fillReturns` fills both the **returns** and the **parameters** every un-annotated *private* function leaves undeclared (`pub` boundaries kept). Returns infer from the body via `Check.fill_local_rets`' fixpoint, defaulting the uninferable to `Any` (ADR-0034); `ilr` stream. Parameters use the full `fixpoint :unknown → Int53 → generalize → Int53` (`ilp` stream): each `:infer` param filled from `Check.infer_param_type` (conflict → `Any`), and a wholly-unconstrained pass-through param generalized to a fresh `forall T` (`add(x,y)` → `Int53,Int53=>Int53`, `id(x)` → `T=>T[T]`). `num_default` is threaded through `infer`'s `numHint`. |
| `Rian.PatternLower`   | 149  | ✅ ported — Core `CPat` → checker patterns (`plw` stream). |
| `Rian.Exhaustiveness` | 290  | ✅ ported — Maranget usefulness/witness/unreachable + `program_env` (`exh`/`pge` streams). |
| `Rian.Coherence`      | ~280 | ✅ ported — protocol/impl coherence rules (ADR-0061 §5): unknown-protocol, method-set/arity, runtime-discriminator presence + non-overlap, duplicate (`coh`/`cohrs` streams). **Enriched for `Protocol`:** the `Registry` carries sum variants and `classify` returns the **real BEAM guard string** (`sumGuard`/`structGuard`) — same overlap outcome as the old equivalence class, now also the dispatcher's discriminator — plus `guardFor`/`registry`. |
| `Rian.Capability`     | 290  | ✅ ported — Rust capability lowering (`rustParam`: val/iso/ref/tag + Copy/borrow/owned, `Fn`→`&impl`, Vec/Map/tuple/parametric/nested) + BEAM linearity (`countUses`: branch-aware free-var occurrence count; iso/ref use-once). Pure. `cap`/`lin` streams. |
| `Rian.Check`          | 2724 | ✅ **type algebra + inference + the `ic` + the gate + annotate ported** — `unify`/`join`, `infer`/`inferBody` (expression core), and the **whole-program inference context `ic`**: `program_ic`'s 9 tables (`pic`), threaded through `infer` so a constructor / program-function / cross-module call (`ifc`), **ECase flow-narrowing** (`ic.tdefs`), generic-return instantiation (`ic.fsigs`), and `.of` range/opaque construction all resolve; **`infer_return_type` + `fill_local_rets`** (`irt`/`flr`); **`infer_param_type`** (`ipt`, the bidirectional parameter constraint, consumed by `InferLocal`); the **full `assignable?`** (value-union membership/mismatch, `Any`-wildcard, bare-sum head, constructed→opaque, numeric widening); and **`check_program`**'s gate (`gate` stream), which runs **all 12** of the reference `check_func` checks in order — **`check_unk` → `check_external_caps` → `check_labels` → `check_union_clash` → return-assignability → `check_binds` → `check_bounds` → `check_numeric_mix` → `check_call_args` → `check_value_position` → `check_effects` → error-sets** (ADR-0040, `efs`) — so the first-error message matches. `check_binds` carries the full literal-width-adoption + range-bind machinery (`litExprAdopts`/`litRangeError`/`widthBounds` — the wide two's-complement bounds are plain literals, since purerl `Int` is an Erlang bignum and the purs frontend accepts arbitrary-precision `Int` literals on this backend); `check_effects` verifies the `@effects(…)` declaration (now parsed by `Decl`, stored on `Func.effects`) against `Reach.effect_sets`. `check_external_caps` also resolves each `Mod.fun`/`:erlang.fun` reference's arity through the port's first **Erlang-FFI boundary** (`Rian.HostRef`, `code:ensure_loaded`/`erlang:function_exported`) — a loaded module missing the `fun/arity` is rejected, a not-yet-loadable one conservatively accepted. **`annotate`** (the typed Core IR the emitters consume, ADR-0050 §3) is ported as a **separate annotated tree `TExpr`** (1:1 with `CExpr`; the inferred type lives there, not in a `nil`-field on every node — the idiomatic, additive choice from the design debate); `ann` stream, faithfully partial (typed nodes vs the reference's `type: nil` catch-alls). `uni`/`joi`/`inf`/`bdy`/`ann`/`pic`/`ifc`/`irt`/`flr`/`ipt`/`gate`/`efs` streams. **`Rian.Check` is now fully ported** — the whole checker (inference + the 12-check gate + annotate). **reframe, not lift**. |
| `Rian.Reach`          | 1235 | ✅ ported — target-set portability inference (ADR-0057/58, `rch` stream). `analyze` + the call-graph reach fixpoint; the signature pins (ref→off`:ex`, Int→off`:rs`/`:jvm`, wide-int→off`:js`, Any→off`:rs`), the body scan (host FFI/concurrency, Result, map literal/update, BEAM-only prims + local-call edges), the emitter-gap detectors (value-union narrowability, Any-in-JVM-operator, clause-head pin), and the **parametric-`:rs` monomorphic subset** (the `expandPtypes`/`emittableMap` fixpoints + the F1/F2/F3 builder-shape gate). **`preludeDefines`** (a snapshot of `Rian.Prelude.defines?`) makes a `List`/`Dict`/`Str`/`Int` portable-prelude module call portable by construction rather than host FFI. `dispatch`/`bitstr` detectors moot in PS (no `Func.dispatch`; no bitstr in portable Core). |

### Phase 5 — Emitters

| Module       | LOC  | Notes / FFI                                          |
| ------------ | ---- | --------------------------------------------------- |
| `Rian.JS`    | 1053 | ✅ **Tier-1 subset complete** — `compile` (runtime module) + `compileTypes` (the `.d.mts` sidecar) + `compileTs` (native typed `.ts` source) — three print modes over one Core lowering (ADR-0086 §5). A direct JS source emitter on the typed Core (works on plain `CExpr`; node types are unused by JS, only signature types + a whole-program number/BigInt mode, ADR-0064). `compile`: functions/clauses/patterns, operators (`div`→`Math.trunc`, `in`, `<>`→`+`), `if`/`case`(→IIFE)/sum/list/tuple/struct/map/string/lambda/capture/`with`(local `desugarWith`) + `__prim_*`/stdlib calls. `compileTypes`: the JS-valid type subset → faithful TS carriers (prims/`Vec`/`Fn`/`Option`/`Result`/`Map`/tuple/`forall T`; else `unknown`). `compileTs`: the same runtime bodies + the typed headers (incl. private functions), tsc-clean standalone. `js`/`jsdts`/`jsts` streams (oracle = `Rian.JS.compile`/`compile_types`/`compile_ts`). All Tier-1 features lower: module `const`s + references (`resolveConsts`/`EConstRef`, ADR-0033), `@external` bodies (`externalFn`/`importsJs`, ADR-0068), value-union discrimination (`bakeUnionDisc`/`PTyped` disc, ADR-0083), protocol dispatch (`protocolDispatchersJs`/`Func.dispatch`, ADR-0061), struct construction (`bakeStructs`/`EStruct`, ADR-0050), and string interpolation (the program tail, ADR-0069). |
| `Rian.JVM`   | 1249 | Kotlin source emitter (pure).                       |
| `Rian.Lower` (Rust) | 3275 | **Rust emitter port in progress** (`Rian.Lower.Rust`, the `rust` stream). Inc. 1: single-clause portable core — primitive `val` params (capability signatures via the ported `Rian.Capability.rustParam`/`owned`), the precedence-aware operator algebra (`+`/`-`/`*`/`div`/`rem`/float-`/`, comparisons, `and`/`or`, unary `-`/`not`), `if`, local calls (recursion). Inc. 2a: **total** multi-clause functions (a var/catch-all clause or full variant coverage → Rust-exhaustive, no shim), sum `type` → `#[derive(Clone, Debug, PartialEq)] enum` (re-emitted per unit) + construction + `Enum::Variant`/`{ label: … }` patterns (named where declared), and `case` → a nested `match`. Inc. 3: strings/chars/symbols — `String` → `&str` param + owned-`String` return (`.to_string()`), `<>` → `format!`, `Char` → native `char` literal, `Symbol` → `&str`. Next: the partial/total `match` shim (`_ => panic!`/`unreachable!()` — needs the exhaustiveness/`partial` flag), structs, lists, strings/chars, capability borrows, generics/monomorphization, protocol traits. The **Elixir-text half is not ported** (not load-bearing — see `Rian.Roundtrip`'s subsumption note). |
| `Rian.Beam`  | 1355 | **Erlang abstract forms → `.beam`**; the core FFI.  |

### Phase 6 — Prim & stdlib support

`Prim` (97) **✅ ported** — `Prim.*`→`__prim_*` rewrite + bare `panic`, a structural
`normalize` over the surface AST (a separate pass; `Pratt.parse` stays normalize-free to
avoid a module cycle, callers compose it). Parity-gated via the `prm` stream (13 records,
oracle = the reference `parse_sexpr`).
`Range` (73) **✅ ported** — the `Name.of(n)` → in-bounds `if`-`Result` rewrite over the
typed Core (the leaf-gate pattern: a structural Core→Core pass); parity via the `rng` stream
(9 records, composing `lexer → Pratt → Core → expand_of → coreSexpr` over a fixed table).
`Macro` (251) **✅ ported** — declarative hygienic macros (ADR-0030): `expand`/`mapNode`/
`substitute`/`freshen` over the surface AST + the portable-core gate. Parity via the `mac` stream
over a fixed binder-free macro env (the reference gensym is non-deterministic, so hygiene is ported
but not byte-tested), serialized through the shared `coreSexpr` oracle.
`Protocol` (388) **✅ ported** — `protocol`/`impl` → guarded BEAM dispatcher + mangled `impl_*`
methods (ADR-0042 §4): `expand`/`dispatcher`/`implMethods` + `mangle`/`substSelf`/`substAssoc`/
`wordReplace`. Consumes the Coherence guard codegen; parity via the `pex` stream (serializes the
generated def maps). Unblocks the Decl assemble tail (with `Macro`).
`Comptime` (79) **✅ ported** — `comptime(e)` compile-time const folding (the other half of
`lower_meta`, wired into `Assemble`; `mxb` stream). `Opaque` (159) **✅ ported** — opaque→base
type substitution + `.of`/cast body stripping (ADR-0067; `opq` stream). Remaining: `ShowStdlib`
(29, blocked on `Decl.inject_stdlib` — no consumer yet), the BEAM-coupled rest of `External`
(279 — only `render` is ported), `Manifest` (315).
`Builtins` (204) **✅ ported** — the host/stdlib foreign-call signature table (`ret`/`known`/`polySig` over `{module,fun,arity}`; `bui` stream). Consumed by `Check`/`Reach`.
`Shadow` (114) **✅ ported** — capture-avoiding `:=` shadow rename over Core (ADR-0034): a rebind
`x := …; x := …` is renamed for targets that forbid same-scope re-declaration (JS `let`, Kotlin
`val`); `dedup`, parity via the `shd` stream.
`Prelude` (115) **✅ ported** (pure part) — `types` (the built-in `Option(T) = Some(T) | None`,
ADR-0047 §3) + `with_prelude`; parity via the `prl` stream. The BEAM/Reach-coupled function
linkage (`module_names`/`defines?`/`atom`/`beams`/`load` — bundles `prelude_*.rian` and compiles
them via `Rian.Beam`) stays at the Erlang-FFI boundary.
`PatternLower` (149) + `Exhaustiveness` (290) **✅ ported** (Phase 4 gates, consuming the
ported Core) — `PatternLower.lower` (Core `CPat` → Maranget checker patterns), the full
usefulness engine (`base_env`/`add_type`/`add_range`/`useful?`/`analyze`/witness/`render`), and
**`program_env`** (now that `Prelude.with_prelude` landed — the prelude `Option` is prepended so
a `case` over it is total). The heterogeneous-atom signature env becomes a `CtorId` sum over
small association lists (no `Data.Map` in the purerl set). Parity via the `plw`/`exh`/`pge`
streams (composing `lexer → Pratt → Core → lower → analyze`, and `Decl → program_env`).

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

## Gap scoreboard — every unported `lib/rian` module

The front-end + gates + inference + `Reach` + assemble tail are **done** (26 PS modules,
parity-gated). What's left, by category — `lib/rian/*.ex` with **no** `purs/src/Rian` twin:

| Category | Elixir modules (unported) | Status / why |
| --- | --- | --- |
| **⛔ Emitters — the compile-spine gap** | `jvm`, `lower`, `beam` | The value backend. **`Rian.JS` is complete for its Tier-1 subset** (all three print modes + const refs, `@external`, value-union discrimination, protocol dispatch, struct construction, string interpolation — `js`/`jsdts`/`jsts` streams). **`Rian.Lower`'s Rust half is in progress** (`Rian.Lower.Rust`, the `rust` stream — increment 1: single-clause portable core); its Elixir-text half is not ported (not load-bearing, see `Rian.Roundtrip`). `JVM` is the other display-pane emitter (unstarted); `Beam` is FFI-heavy → Phase 8. |
| **✅ Pipeline desugars — ported** | ~~`interp`~~, ~~`show_stdlib`~~ | `Interp` (`${}` resolution, ADR-0069) and `ShowStdlib` (the portable `Show.float`) are ported and wired into `Rian.Assemble.runProgramTail` (composed by `Rian.JS.compile` before the gate); `itp`/`shs` parity streams. |
| **⚙️ Execution & self-host (FFI-heavy, Phase 8)** | `run`, `repl`, `fixpoint`, `self_host`, `roundtrip`, `forms_equiv`, `doctest`, `test` | Wrap `:compile.forms` / code-loading / `GenServer`. Expected-late: they need the BEAM emitter + Erlang FFI. For the **JS** build these are skipped in-browser. |
| **📐 Formatter (Phase 9)** | `format` (+ `format/{Doc,CST,CLI}`), `lsp/*` | Zero-config formatter (ADR-0045). A real feature, off the compile spine; ports after the emitters. |
| **📦 CLI / packaging / integrations (Phase 10)** | `cli`, `build`, `manifest`, `pkg/*`, `tour`, `livebook/*`, `application` | Host shims + build toolchain. `Manifest` (`rian.toml` reader) gates the Phase 7–10 build. Becomes a thin Elixir/escript or node-CLI shell over the ported core. |
| **🚫 Superseded / out of scope** | `transpile` (+ `transpile/*`), `ann` (reader) | **Not ported by design.** Elixir→Rian `Transpile` is *re-aimed* to **PureScript → Rian** (Phase 7), not lifted. `Ann`'s reader is dropped; the `@rian_sig` *comment convention* is retained. |

**One-line read:** the compile spine now **emits** — `Rian.JS`'s runtime mode has landed (ADR-0090's
JS-first order), so a checked program lowers to JS. What's left to *complete* the value backend:
the JS sub-features above, the two pure desugars (`Interp`/`ShowStdlib`), then `Lower`/`JVM`
(display panes) and `Beam` (FFI, Phase 8). Plus the new ADR-0090 deliverable — a JS-backend build
profile (stock `purs`→JS) to ship that emitter in the browser. Everything else unported is host
tooling that rides *behind* the emitters or is deliberately superseded.

## Status

Phases 0–1 complete. **Phase 2**: `Rian.TypeStr` + **`Rian.Core`** ported (parity-gated);
`Rian.Ann` reader dropped (annotation convention retained); **`Rian.IR`** (data structs) ported.
**Phase 3**: `Rian.Pratt` ported (expression core + patterns + `if`/`case`/`lambda`/blocks +
`with`/`for`/interpolation, via `psx`); remaining: bitstrings, map-update + type-patterns,
error-propagation. **Phase 6**: `Rian.Prim` ported. **`Rian.IR`** + **`Rian.Decl` — every declaration form**
(`type`/`struct`/`def`/`mod`/`const`/`use`/`alias`/`range`/`opaque` + `def` block bodies +
`@external` + `abstract` + `protocol`/`impl`/`macro`) ported, plus **`Rian.Prelude`** (the pure
`Option`/`with_prelude` part). **Phase 4 gates:** **`Rian.PatternLower`** + **`Rian.Exhaustiveness`**
ported (Maranget usefulness over the ported Core, incl. `program_env`; `plw`/`exh`/`pge` streams).
**`Rian.Check` ported through inference** — the `unify`/`join` type algebra (the `Ty` sum;
`uni`/`joi` streams) **and `infer`** over the expression core + **`inferBody`** (re-parse + infer
a function body; `inf`/`bdy` streams). **`Rian.Shadow`** (capture-avoiding `:=` rename, ADR-0034;
`shd` stream), **`Rian.Macro`** (`mac`) + **`Rian.Protocol`** (`pex`, with the Coherence guard
enrichment), **`Rian.Reach`** (`rch`, COMPLETE — all detectors incl. the parametric-`:rs` subset),
and **`Rian.Capability`** (`cap`/`lin`) ported. **The Check `ic` landed:** `program_ic`'s 9 tables
(`pic`), threaded through `infer` — a constructor / program-function / cross-module call (`ifc`),
**ECase flow-narrowing** + generic-return instantiation + `.of` construction — plus
`infer_return_type`/`fill_local_rets` (`irt`/`flr`), **`Rian.InferLocal.fill_returns`** (`ilr`), and
**`check_program`'s gate** (`gate`) — **all 12** of the reference's `check_func` checks in order:
`check_unk`, `check_external_caps`, `check_labels`, `check_union_clash`, return-assignability (the
FULL `assignable?`: value unions / `Any`-wildcard-at-depth / bare-head / constructed-opaque /
numeric widening), `check_binds` (literal-width-adoption + range-bind), `check_bounds`
(`forall T: Bound`), `check_numeric_mix`, `check_call_args`, `check_value_position`, `check_effects` (`@effects` vs the
inferred set), **and error sets** (ADR-0040 — a `Result(T,E)`'s produced error set ⊆ `E`, by a
call-graph fixpoint). Plus `infer_param_type` (`ipt`) and `effect_sets` (`efs`, in Reach). **`Rian.Assemble`** (new top module) runs the whole
`lower_meta` assemble tail `Decl.parse` does but PS `parseToProg` defers — **protocol synthesis**
(`asm`, `Protocol.expand` → `prog.funcs`, sidestepping the `Decl`↔`Protocol` cycle), **macro
expansion** (`mxb`, `Macro.expand`) **and `Rian.Comptime`** (`comptime(e)` → a sandboxed const fold,
also in `mxb`) → `Expanded` clause bodies. The clause body is now `data Body = Raw String | Expanded
Surface` with a `bodySurface` accessor (the reference's `String | ast`, idempotent re-parse
restored); `lower_meta` change-detects via the canonical `sexpr` so an untouched body stays `Raw`.
**Next:** the **emitters** — **`JS` first** (ADR-0090: the playground engine), then `Lower`/`JVM`
(display panes) and `Beam` (FFI, Phase 8) — the value backend. **Phase 5 has begun:** `Rian.JS`'s
runtime emitter (`compile`) is ported and `js`-stream parity-gated (ADR-0049 Tier 1). The checker spine, its
erase passes, and `Reach` (now incl. `preludeDefines`) are all complete; the remaining unported
modules are either emitters or leaves blocked on an unported consumer — `ShowStdlib` (no
`Decl.inject_stdlib` yet) and `Manifest` (the `rian.toml` reader for the Phase 7-10 build toolchain).
Total **979/979** parity records across Lexer/TypeStr/Pratt/Core/Prim/Decl/Range/PatternLower/
Exhaustiveness/Prelude/External/Coherence/Check/Builtins/Shadow/Macro/Protocol/Reach/Capability/
InferLocal/Assemble/Comptime/Opaque/**JS**/**Lower.Rust** (the count is the harness's own `N/N` total — `parity.erl`
reports `length(Results)`, so it tracks the fixture file and cannot drift from it). This prose figure,
and the "all 12 `check_func` checks" / "deferred" notes below, are pinned to the code by
`Rian.PursMigrationDocTest` — a stale count or a deferral note that outlived its port fails `mix test`.
Each module is parity-gated and committed on its own
(Conventional Commits, ADR-0084). The branch is rebased onto `berta` (ADR-0085 included).

The parity gate is **local** (`scripts/purerl-build.sh`, run per ported module before its
commit); it is **not yet wired into CI** — fetching the pinned `purerl` release + dhall package
set is a network step the CI image does not perform today (ADR-0084, "Consequences"). So a ported
module's parity is enforced at authoring time, not re-checked on the default `mix`/CI gate.

**What "ported" means here — read this before trusting the module count.** The **entire
front-end is ported and cross-checked**: lex → parse → typed Core IR → the refutation gates
(`PatternLower`/`Exhaustiveness`) → leaf passes (`Range`/`Prelude`/`External.render`/`Coherence`/
`Builtins`/`Shadow`). **The portability + capability + expansion gates are now ported too**:
`Reach` (target reachability, complete), `Capability` (Rust lowering + BEAM linearity), and the
expansion/synthesis passes `Macro` + `Protocol.expand`. **The inference + return gate now hold too**:
the Check `ic` is built and threaded (so flow-narrowing, generic-return, and user/cross-module calls
type), `infer_return_type`/`fill_local_rets` recover un-annotated returns, `InferLocal` writes them
back, and `check_program` enforces return-assignability (the full `assignable?`: value unions /
`Any`-wildcard / bare-head / opaque / numeric widening) **and error sets** (ADR-0040). `infer_param_type`
(`ipt`) and `effect_sets` (`efs`) are ported, and **InferLocal infers parameters + generalizes to
`forall T`** (`ilp`). **And the assemble tail is ported**: `Rian.Assemble` runs `lower_meta` —
`Protocol.expand` synthesis (`asm`) plus `Macro.expand` + `Comptime.fold` into `Expanded` clause
bodies (`mxb`). **Phase 4 is closed.** **What remains before end-to-end compile**: the **emitters**
(`JS` first per ADR-0090, then `Lower`/`JVM`/`Beam`) — the value backend. **`Rian.Check` is now fully ported** (inference +
the complete 12-check `check_program` gate + `annotate` as a separate `TExpr` tree), and the port has
its first Erlang-FFI boundary (`Rian.HostRef`, for `@external` ref-arity reflection). The parity-record count measures
front-end + inference + gate + assemble-tail *fidelity*, not compiler completeness; the **emitters** are now the
gate that flips "checks a program" to "emits one."

**Known parity-corpus gaps (low severity, named not hidden).** The fixed-scenario streams cover
every `lower`/`analyze`/`parse` branch *except*: `PMap` pattern lowering (BEAM-only, refutable);
`Exhaustiveness.render`'s `inspect`-style escaping of a witness string/atom containing quotes
(diagnostic text only — the PS `render` wraps raw where Elixir `inspect` escapes). The
`@targets(:rs)`-exempt branch of `Coherence` is now covered by the **`cohrs`** stream (a
Rust-only scope suppresses `shared_discriminator` while `duplicate`/`method_set` still fire).
These remaining gaps are tracked, not asserted away.
