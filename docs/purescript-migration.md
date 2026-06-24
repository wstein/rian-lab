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
> playground's compiler prerequisite. **The playground + by-example tutorial now lower all four
> *source* targets live** (JS/TS/Rust/JVM are pure-PureScript emitters): `Rian.Lower.All.prepare`
> runs the shared front-end (lex → Pratt → Core → assemble → tail → type-gate) **once** and
> `lower{Js,Ts,Rust,Jvm}` branch per target off the checked program — parse-once, lower-many, with
> per-target rejection caught per pane. Only **BEAM** stays out (`Rian.Beam` needs `:compile.forms`,
> an Erlang/OTP API). (One wide-int build-parity caveat remains (ADR-0090 §6):
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
| `Rian.Check`          | 2724 | ✅ **type algebra + inference + the `ic` + the gate + annotate ported** — `unify`/`join`, `infer`/`inferBody` (expression core), and the **whole-program inference context `ic`**: `program_ic`'s 9 tables (`pic`), threaded through `infer` so a constructor / program-function / cross-module call (`ifc`), **ECase flow-narrowing** (`ic.tdefs`), generic-return instantiation (`ic.fsigs`), and `.of` range/opaque construction all resolve; **`infer_return_type` + `fill_local_rets`** (`irt`/`flr`); **`infer_param_type`** (`ipt`, the bidirectional parameter constraint, consumed by `InferLocal`); the **full `assignable?`** (value-union membership/mismatch, `Any`-wildcard, bare-sum head, constructed→opaque, numeric widening); and **`check_program`**'s gate (`gate` stream), which runs **all 12** of the reference `check_func` checks in order — **`check_unk` → `check_external_caps` → `check_labels` → `check_union_clash` → return-assignability → `check_binds` → `check_bounds` → `check_numeric_mix` → `check_call_args` → `check_value_position` → `check_effects` → error-sets** (ADR-0040, `efs`) — so the first-error message matches. `check_binds` carries the full literal-width-adoption + range-bind machinery (`litExprAdopts`/`litRangeError`/`widthBounds` — the wide two's-complement bounds are plain literals, since purerl `Int` is an Erlang bignum and the purs frontend accepts arbitrary-precision `Int` literals on this backend); `check_effects` verifies the `@effects(…)` declaration (now parsed by `Decl`, stored on `Func.effects`) against `Reach.effect_sets`. `check_external_caps` also resolves each `Mod.fun`/`:erlang.fun` reference's arity through the port's first **Erlang-FFI boundary** (`Rian.HostRef`, `code:ensure_loaded`/`erlang:function_exported`) — a loaded module missing the `fun/arity` is rejected, a not-yet-loadable one conservatively accepted. **`annotate`** (the typed Core IR the emitters consume, ADR-0050 §3) is ported as a **separate annotated tree `TExpr`** (1:1 with `CExpr`; the inferred type lives there, not in a `nil`-field on every node — the idiomatic, additive choice from the design debate); `ann` stream, faithfully partial (typed nodes vs the reference's `type: nil` catch-alls). `uni`/`joi`/`inf`/`bdy`/`ann`/`pic`/`ifc`/`irt`/`flr`/`ipt`/`gate`/`efs` streams. **`Rian.Check` is ported** — the whole checker (inference + the 12-check gate + annotate), with **one known inference gap**: a *return-position* list literal does not yet adopt a declared element width. `def f() Vec(Int8) := [1, 2, 3]` is accepted by the Elixir reference (which adopts `Int8` through `fill_local_rets`), but the port infers `Vec(Int53)` and the return-assignability gate rejects it — a `gate`-stream divergence (bind-position adoption via `litExprAdopts`'s `SListLit` case is complete; this is the return path). The JVM/Rust list corpora use `Vec(Int53)` element types to sidestep it. **reframe, not lift**. |
| `Rian.Reach`          | 1235 | ✅ ported — target-set portability inference (ADR-0057/58, `rch` stream). `analyze` + the call-graph reach fixpoint; the signature pins (ref→off`:ex`, Int→off`:rs`/`:jvm`, wide-int→off`:js`, Any→off`:rs`), the body scan (host FFI/concurrency, Result, map literal/update, BEAM-only prims + local-call edges), the emitter-gap detectors (value-union narrowability, Any-in-JVM-operator, clause-head pin), and the **parametric-`:rs` monomorphic subset** (the `expandPtypes`/`emittableMap` fixpoints + the F1/F2/F3 builder-shape gate). **`preludeDefines`** (a snapshot of `Rian.Prelude.defines?`) makes a `List`/`Dict`/`Str`/`Int` portable-prelude module call portable by construction rather than host FFI. `dispatch`/`bitstr` detectors moot in PS (no `Func.dispatch`; no bitstr in portable Core). |

### Phase 5 — Emitters

| Module       | LOC  | Notes / FFI                                          |
| ------------ | ---- | --------------------------------------------------- |
| `Rian.JS`    | 1053 | ✅ **Tier-1 subset complete** — `compile` (runtime module) + `compileTypes` (the `.d.mts` sidecar) + `compileTs` (native typed `.ts` source) — three print modes over one Core lowering (ADR-0086 §5). A direct JS source emitter on the typed Core (works on plain `CExpr`; node types are unused by JS, only signature types + a whole-program number/BigInt mode, ADR-0064). `compile`: functions/clauses/patterns, operators (`div`→`Math.trunc`, `in`, `<>`→`+`), `if`/`case`(→IIFE)/sum/list/tuple/struct/map/string/lambda/capture/`with`(local `desugarWith`) + `__prim_*`/stdlib calls. `compileTypes`: the JS-valid type subset → faithful TS carriers (prims/`Vec`/`Fn`/`Option`/`Result`/`Map`/tuple/`forall T`; else `unknown`). `compileTs`: the same runtime bodies + the typed headers (incl. private functions), tsc-clean standalone — **plus the `@external` host-macro** (ADR-0068/0030, the doc-view *only*): a statement-position call to an inlinable single-clause `@external(:js)` (raw-string body, no string literal, each param used once) is spliced inline (host body with the lowered args substituted, `wordReplace` = the reference's `\b…\b`), and a now-uncalled *private* wrapper is DCE'd — so `puts("…")` becomes `console.log("…")`. A `pub` wrapper is kept (exported API); the runtime `.mjs` (`compile`) keeps every named wrapper unchanged (S5: idiomatic view, faithful runtime). `js`/`jsdts`/`jsts` streams (oracle = `Rian.JS.compile`/`compile_types`/`compile_ts`). All Tier-1 features lower: module `const`s + references (`resolveConsts`/`EConstRef`, ADR-0033), `@external` bodies (`externalFn`/`importsJs`, ADR-0068), value-union discrimination (`bakeUnionDisc`/`PTyped` disc, ADR-0083), protocol dispatch (`protocolDispatchersJs`/`Func.dispatch`, ADR-0061), struct construction (`bakeStructs`/`EStruct`, ADR-0050), and string interpolation (the program tail, ADR-0069). |
| `Rian.JVM`   | 1249 | 🚧 **Kotlin/JVM emitter port in progress** (`Rian.JVM`, the `jvm` stream). A direct Kotlin source emitter on the typed Core, mirroring `Rian.Lower.Rust`. Inc 1: single-clause portable core — primitive params via `ktType` (`Int64`/`Int53`→`Long`, `Float64`→`Double`, `Bool`→`Boolean`, `Char`→`Long` codepoint, `Symbol`→`String`; `Int` rejected, ADR-0064), the operator algebra (`L`-suffixed int literals, `div`/`rem`/float-`/`, comparisons, `and`/`or`, `<>`→`+`, unary `-`/`not`), `if`-expressions, local calls/recursion. Inc 2: the **multi-clause dispatcher** — an `if`-chain over the positional `a<i>` params (`clauseLines`/`clauseMatch`/`patMatch`), literal tests (`a0 == 0L`/`== "s"`, `&&`-joined), variable binds (`val n = a0;`) + wildcards, `when` guards (a structural-test clause → conditional `if`, a guard-only clause → a scoped `run { … }`), and the trailing `throw RuntimeException("…: no clause matched")` when the clause set is non-total. Inc 3: **sum variants** — a `type` → `sealed interface Name` + a `data class Ctor(val f0: T, …)`/`object Ctor` per variant (named fields where declared, ADR-0049 §3b; a single variant whose ctor IS the type name is a newtype-style `data class`), construction `Ctor(args)` (same shape as a call), clause patterns that smart-cast (`a0 is Ctor`) and recurse into positional/named fields (`a0.f0`/`a0.radius`, via a ctor→labels `meta`), and `case` → a labelled `run rcase@{ … }` whose arms reuse the dispatcher's test/bind/guard machinery (`return@rcase`). Inc 4: **strings/chars/symbols** — the `Prim.*` intrinsics (`str_concat`/`str_concat_all` for `<>`+interpolation, `char_to_string`, `str_chars`/`str_from_chars` over codepoints, `int_to_string`/`to_string`), `Char` literal values+patterns (`97L`), and `Symbol`/atom patterns (`== "ok"`). Dual-gated: `jvm` byte-parity (oracle = `Rian.JVM.compile`) **and** the output `kotlinc`-compiles. Inc 5: **lists / `Vec(T)`** → Kotlin `List<T>` — a literal `[a, b]` → `listOf(a, b)`, a cons `[h, … \| t]` → `(listOf(h, …) + t)`; clause/`case` patterns test `size` (exact for a closed list, `>=` for a cons), match fixed elements at `acc[i]`, and bind the rest with `acc.drop(n)`; nested `Vec(Vec(T))` → `List<List<…>>`. Inc 6: **structs** → Kotlin `data class Name(val f: T, …)` (named fields); field access `p.x`, labeled construction `Point(x = 0L, …)` (and resolved `EStruct`), and struct clause patterns that smart-cast (`a0 is Point`) + read `(a0 as Point).f`. Inc 7: **generics + `Fn` + lambdas + tuples** — a `forall T` function → `fun <T : Any> …`; `Fn(a…, r)` → a Kotlin function type `(a…) -> r`; a lambda `(n) -> body` → `{ n -> body }`; a 2-/3-tuple value/type → `Pair`/`Triple` (+ constructor and `componentN()` patterns). Inc 8: **protocols** — a synthesized dispatcher → `fun name(a0: Any, …): Ret = when (a0) { is <Type> -> impl_…(…); … else -> throw }` over the receiver type (ADR-0042); `impl` methods stay regular funs, a `Self` arg is `as`-cast, a bounded-generic consumer (`forall T: Eq`) erases the bound to `<T : Any>`. Associated types (ADR-0074): an assoc `Elem` in a covariant `Vec(...)` return erases to `List<Any>` (`substAssocAny`); a dispatcher with an assoc in a non-erasable position is dropped (`assocBlocksJvm`). The `coerce_casts` use-site cast inserts `as List<T>` where an erased `List<Any>` flows into a concrete `Vec(T)` param — both a DIRECT call (`sum_l(to_list(c))` → `sum_l((to_list(c) as List<Long>))`, `castedArgs`/`castArg` over `meta.sigs`/`erased`) and a local BOUND to an erased result (`xs := to_list(b); sum_l(xs)` → `sum_l((xs as List<Long>))`, via the `meta.env` of erased-bound locals threaded across block statements, `envStep`). **ADR-0074 fully covered**, kotlinc-verified. **Ctor-pattern impl heads fixed** (shared, all targets): `def sz(Bag(n))` in an `impl` used to synthesize a corrupted `Bag(n)Bag` param type *and* drop the pattern (leaving the body's `n` unbound) — `Rian.Protocol.impl_clause` (Elixir + PS twin) now binds a fresh receiver typed by the protocol and moves the pattern into a `case`, so it lowers to valid `a0: Bag` + a smart-cast `case` (kotlinc-clean; var-head impls unchanged). `ktType` also maps `Dict(K,V)` → `Map<K,V>` and `Union(…)` → `Any`. **Dict / map operations** (Phase-5 add-on): a map literal `%{k: v, …}`/`%{}` → `mapOf("k" to v, …)`/`mapOf()`, `Map.get`/`put`/`has` → `(m).getValue("k")`/`((m) + ("k" to v))`/`(m).containsKey("k")`, and a `%{k: p}` pattern → a `containsKey` guard + a `getValue` bind (a non-atom/computed key stays BEAM-only, ADR-0033) — all dual-gated (parity + `kotlinc`). **Captures + `with`** (Phase-5 add-on): an anonymous capture `&(&1 * 2)` → a lambda `{ _1 -> (_1 * 2L) }` (params `_1.._N` from `Core.capArity`), a named `&fn/arity` → a `::fn` reference (a remote `&Mod.fun/arity` → a `{ _a0, … -> path(_a0, …) }` forwarding lambda), and `with … else …` → nested `case`s via `Core.desugarWith` — both helpers **lifted from `Rian.JS` into `Rian.Core`** so JS and JVM share them (JS parity unchanged). Inc 9: **multi-statement body blocks** — a `:=` bind before the value (`name := who ; …`) → a scoped `run { val name = who; … }` (`stmtKt`/`stmtValue`); shadow-rename + the associated-type cast pass stay deferred (a shadow-free, cast-free body — the portable common case — matches the reference). |
| `Rian.Lower` (Rust) | 3275 | **Rust emitter port in progress** (`Rian.Lower.Rust`, the `rust` stream). Inc. 1: single-clause portable core — primitive `val` params (capability signatures via the ported `Rian.Capability.rustParam`/`owned`), the precedence-aware operator algebra (`+`/`-`/`*`/`div`/`rem`/float-`/`, comparisons, `and`/`or`, unary `-`/`not`), `if`, local calls (recursion). Inc. 2a: **total** multi-clause functions (a var/catch-all clause or full variant coverage → Rust-exhaustive, no shim), sum `type` → `#[derive(Clone, Debug, PartialEq)] enum` (re-emitted per unit) + construction + `Enum::Variant`/`{ label: … }` patterns (named where declared), and `case` → a nested `match`. Inc. 3: strings/chars/symbols — `String` → `&str` param + owned-`String` return (`.to_string()`), `<>` → `format!`, `Char` → native `char` literal, `Symbol` → `&str`. Inc. 4: the partial/total `match` shim — a partial function (`Rian.Exhaustiveness.analyze` via `programEnv`/`lowerMany`, no `partial` flag needed) → `_ => panic!(…)`, a range-total literal match → `_ => unreachable!()`. Inc. 5: structs — `struct Name(f T,…)` → `#[derive(Clone, Debug, PartialEq)] struct Name { f: T,… }`, `val Name` → `&Name` param, field access `p.x`, construction `Name { f: v }` (struct PATTERNS unsupported in both text emitters). Inc. 6: lists (ADR-0047) — `Vec(T)` literal → `vec![…]`, `val Vec(T)` → `&[T]` slice, cons `[x \| xs]` → prepend onto `xs.to_vec()`, `case` over a list → `match &(xs)[..] { [] …, [h, t @ ..] … }`. Inc. 7a: generics (ADR-0061) — a bare-tvar pass-through `forall T` → `fn id<T: Clone>(x: &T) -> T` with the borrowed `&T` cloned to the owned return. Inc. 7b: bounded generics + protocol traits — `forall T: Eq` → `<T: RianEq + Clone>`, a `protocol P` → `trait RianP { fn m(&self,…) }`, a protocol-method call `eq(a, b)` → `a.eq(b)` (UFCS receiver rewrite). Inc. 7c: the **`rustprog` stream** (oracle = `Rian.Lower.rust_program`) — the whole-program assembly (struct/enum/trait/impl/fn each emitted ONCE, vs the per-unit-repeating `rust` stream) + protocol `impl` blocks (`impl RianP for <T> { fn m(&self,…) { let recv = self; … } }`). Inc. 7d: parametric-type monomorphization + the owned-element clone — `parametric_param_map` (a type-graph fixpoint) → `enum Box<T: Clone>`/`enum Pair<K: Clone, V: Clone>`, `pinst`/`word_replace` rewriting signatures (`Box`→`Box<T>`), and the borrowed-payload clone (`B(x)` → `Box::B { v: x.clone() }`, via a per-clause `borrowed`-var set), in the `rustprog` stream. Inc. 7e: closures (ADR-0061) — a `Fn(...)` param → `&impl Fn(…) -> …` (a closure call clones its args), a `Fn(...)` return → `Box<dyn Fn(…) -> …>` (the value-position lambda is `Box::new(move …)`). Inc. 7f: the deeper capability borrows (ADR-0047 Gap D/E) — a clause-head cons binder under a slice match is a `&T` rebound `let h = h.clone();` at arm entry (only if the body uses it — `usedIds`/`armRebinds`), an `iso Vec` param destructured by a cons pattern matches via `xs.as_slice()` with its tail rebound `let t = t.to_vec();` (`isoConsPositions`/`rustScrut`), and a `Vec`-returning body coerces a borrowed `&[T]` slice leaf to the owned `Vec` its signature promises — pushed into if/case tails (`coerceOwnedVecAst`/`sliceBinders`) or wrapping a slice-id arm (`(…).to_vec()`). rustc-verified (`keep`/`sum`/`dup`). Inc. 7g: string-interpolation + stringify prims (ADR-0069) — `__prim_str_concat`/`__prim_str_concat_all` → one `format!("{}…", …)`, `__prim_int_to_string`/`__prim_char_to_string` → `.to_string()`, `__prim_to_string`/`__prim_float_repr`/`__prim_int_to_float`/`__prim_panic` → their native forms; and a `:=` bind owns its RHS (`rust_owned_elem`/`stmtRs`: a string/`Symbol` literal → `.to_string()`, a `&[T]` slice → `.to_vec()`, a borrowed binder → `.clone()`). **Mop-up** (Phase 5): the `Map(K,V)` HashMap prims (`__prim_map_new`/`get`/`has`/`put` → `HashMap::new()` / `.get(k).cloned().unwrap()` / `.contains_key(k)` / a clone-and-insert functional update), captures (`&(&1*2)` → `\|a1\| …`, `&fn/arity` → `\|a0,…\| fn(a0,…)`, `&N` → `aN`, arity from the shared `Core.capArity`), and `with` → a nested `match` chain (`withChainRs`); a map *literal*/update stays BEAM-only (a clean crash). The HashMap prims are rustc-verified; captures-in-return + `with` bodies mirror the reference's output, which has known boxing/borrow gaps (parity, not rustc-valid — Reach pins those off `:rs`). The **Elixir-text half is not ported** (not load-bearing — see `Rian.Roundtrip`'s subsumption note). |
| `Rian.Beam`  | 1355 | 🚧 **Erlang abstract forms → `.beam`** (the keystone, in progress; the `beam` EXECUTION stream — 48 records). Forms are pure PureScript over an opaque `ETerm`; the Erlang-FFI tail (`Beam.erl`) is the term constructors + `compile:forms`/`code:load_binary`/run. Inc 1-12 (see the Phase 8 note): literals/operators/vars/`:=`/local-calls/`if`, multi-clause dispatch + `when` guards + `case`, sums/lists/tuples/strings, structs/maps, the self-contained `Prim.*` intrinsics, the 64-bit overflow ops, `const` decls + refs, **value-union type-pattern discrimination** (ADR-0083 — `PTyped` → `PVar` + a runtime type-test guard via the `desugarTyped` pre-pass + the threaded sum/struct registry), **`@external` host-body splice + module-qualified calls** (ADR-0068 — `beamFunc` synthesizes a clause from the rendered `:ex` spec, off-`:ex` externals emit nothing; `Mod.fun`/`:erlang.fun` → an Erlang remote call via `moduleAtom`), and **cross-module / aux-mod loading** — `runMain` compiles the top-level funcs (`rian_main`) + each sibling `mod` (`Elixir.<Name>`) and loads all before running `main/0` (`runModulesImpl`), landing **`${float}`** (the injected `Show` aux mod; the String⇄charlist prims lower to pure-Erlang `unicode:*`/`erlang:*` so no Elixir runtime is needed), and **lambdas / captures / variable application** (`expr_form` threads a bound-name `scope` so a call over a fun-valued binding lowers to a var application; `ELambda`/`ECapture`/`&fn/n` → an Erlang `fun`), and the **portable-prelude linkage** (the bundled `List`/`Dict`/`Str`/`Int` `.rian` sources → private `Elixir.Rian.Prelude.<Name>` modules, loaded once per VM; `moduleAtom` redirects a `List.fun(…)` call per `Reach.preludeDefines`). |

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
`Prelude` (115) **✅ ported** — `types` (the built-in `Option(T) = Some(T) | None`,
ADR-0047 §3) + `with_prelude` (`prl` stream). The **function linkage** (`defines?`/`atom`/`beams`/
`load` — bundle the `prelude_*.rian` sources and compile them to `Elixir.Rian.Prelude.<Name>` modules)
now lives in **`Rian.Beam`** (Phase-8 inc 12): the sources are bundled as `Rian.PreludeSrc` (generated
by `scripts/gen_prelude_src.exs`), `Beam.preludeForms` compiles them, `runModulesImpl` loads them once
per VM, and `moduleAtom` redirects per `Reach.preludeDefines` (the snapshot of `defines?`).
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

### Phase 8 — Execution & self-host (FFI-heavy) — **started**

`Interp` (252, done — Phase 5), `FormsEquiv` (245), `Roundtrip` (293), `Fixpoint` (64), `Run` (161),
`Repl`+`Repl.History` (538+89), `SelfHost` (502), `Doctest` (190), `Test` (232). These
wrap `:compile.forms`/code-loading/`GenServer` — the bulk of the Erlang FFI.

**`Rian.Beam` (1519) — the keystone — is in progress** (`purs/src/Rian/Beam.purs` + `Beam.erl`).
The abstract-forms construction is **pure PureScript over an opaque `ETerm`**; the Erlang-FFI tail
(`Beam.erl` = `rian_beam@foreign`) is just the term constructors (`mkAtomTerm`/`mkIntStr`/`mkTuple`/
`mkList`/…) plus `compile:forms` → `code:load_binary` → run. Parity is **by EXECUTION** — the new
`beam` stream compiles + loads + runs each program's `main/0` on purerl and compares the
`~p`-rendered result against the Elixir reference running the same program (so a match proves the
forms actually *run the same*, not merely look alike). **Inc 1-12 (landed):** literals (int/float/char/
atom/bool), the operator algebra, variables, `:=` binds, local calls, `if`, single-clause var-headed
functions, plus multi-clause dispatch, `when` guards (function-clause + case-arm), and `case` — verified on `42`/`add`/precedence/`:=`/float/bool/`fact(5)=120`/multi-clause/guard/`case`, plus sums (=25)/lists/list-recursion (=60)/strings/tuples, plus structs (=7)/struct-patterns/maps, plus the self-contained prims (interpolation/`<>`/membership), plus the 64-bit overflow ops, `const` decls + refs, **inc 8: value-union type-pattern discrimination (ADR-0083)** — a `case`-arm `name Type` (`PTyped`) desugars to a `PVar` bound under a runtime type-test guard (a `desugarTyped` pre-pass over the body Core, the sum/struct registry threaded like `cnames`), reusing the protocol-dispatch discriminator: a primitive BIF (`is_integer`/`is_binary`/…), a sum tag-membership (`is_tuple` + `element(1,…)`), or a struct `__struct__` test (`erlang:map_get`) — verified on the primitive/sum/struct member unions; and **inc 9: `@external` host-body splice (ADR-0068)** — `beamFunc` synthesizes a clause from the rendered `:ex` spec (a raw host string, or a `Mod.fun`/`:erlang.fun` reference → a positional call), an off-`:ex` external emits nothing, and module-qualified `Mod.fun(args)`/`:erlang.fun(args)` calls lower to an Erlang remote call (`moduleAtom`: PascalCase → `Elixir.Mod`, lowercase/atom → an Erlang module) — verified on a raw-string body, an `:erlang.abs` ref, a lowercase Erlang-module ref, and an off-`:ex` drop (a PascalCase Elixir-module call also lowers but is not execution-testable in the plain-Erlang harness); and **inc 10: cross-module / aux-mod loading** — `runMain` compiles the top-level funcs into the main `rian_main` module *and* each sibling `mod` into its own `Elixir.<Name>`, loading all before running `rian_main:main()` (`runModulesImpl`, mirroring `load_aux_mods`), so a cross-module call resolves. This lands **`${float}`**: `runProgramTail` injects a `Show` module for a `Float64` hole, which now compiles + loads as an aux mod and runs end-to-end — verified on `"v = ${1.5}"` → `"v = 1.5"`, a negative float through the recursive `Show` path, and a user multi-`mod` program (`Math.sq`). The one deliberate emit divergence: the String⇄charlist prims (`__prim_str_chars`/`_from_chars`/`_to_atom`) lower to the pure-Erlang `unicode:*`/`erlang:*` BIFs rather than the reference's `Elixir.String.*` (which delegate to exactly those) — an equivalent result with no Elixir runtime loaded, which is what lets `Show` run in the harness; and **inc 11: lambdas / captures / variable application** (the higher-order foundation) — `expr_form` now threads a `scope` (the bound-name set: clause-head pattern vars via `patVars` + `:=` binds via `blockForms` + lambda/capture params), so a call `f(args)` over a bound fun-valued name lowers to a **variable application** (`{call, {var,F}, args}`) instead of a local call; an `ELambda`/`ECapture` → an Erlang `fun` (params extend the scope), `&name/arity`/`&Mod.fun/arity` → a `fun …/arity` reference, and a generic-callee `ECall` applies the callee form — verified on a user HOF (`apply2`), `my_map` over a lambda → `[1,4,9]`, an anonymous capture `&(&1 * 2)`, and a named capture `&dbl/1`; and **inc 12: the portable-prelude linkage** (ADR-0047 §2) — the bundled `List`/`Dict`/`Str`/`Int` `.rian` sources (`Rian.PreludeSrc`, generated from `examples/rian/prelude_*.rian` by `scripts/gen_prelude_src.exs`) each compile to a private `Elixir.Rian.Prelude.<Name>` module (`preludeForms`), loaded **once per VM** by `runModulesImpl` (idempotent via the `Elixir.Rian.Prelude.List` sentinel, mirroring `Rian.Prelude.load`); `moduleAtom` redirects a `List.fun(…)` call (per the exported `Reach.preludeDefines`) to its linked module rather than an Elixir/Erlang same-named stdlib — verified on `Int.wrapping_add` → `i64_min`, `List.map([1,2,3], (n) -> n*n)` → `[1,4,9]`, `List.sum`/`List.length`, `List.all`, and `Str.length("hello")` → `5`. (The one Beam pattern this needed: an as-pattern `all @ [h | t]` in `List.insert_by` → `patForm (PAs …)`.) Deferred to later
increments: `-spec`/`type` attrs (Dialyzer contracts; do not affect the execution result).

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
| **⛔ Emitters — the compile-spine gap** | `jvm`, `lower`, `beam` | The value backend. **`Rian.JS` is complete for its Tier-1 subset** (all three print modes + const refs, `@external`, value-union discrimination, protocol dispatch, struct construction, string interpolation — `js`/`jsdts`/`jsts` streams). **`Rian.Lower`'s Rust half is in progress** (`Rian.Lower.Rust`, the `rust` stream — increment 1: single-clause portable core); its Elixir-text half is not ported (not load-bearing, see `Rian.Roundtrip`). **`Rian.JVM`'s port is in progress too** (the `jvm` stream — inc 1: single-clause portable core, dual-gated on byte-parity + `kotlinc`); `Beam` is FFI-heavy → Phase 8. |
| **✅ Pipeline desugars — ported** | ~~`interp`~~, ~~`show_stdlib`~~ | `Interp` (`${}` resolution, ADR-0069) and `ShowStdlib` (the portable `Show.float`) are ported and wired into `Rian.Assemble.runProgramTail` (composed by `Rian.JS.compile` before the gate); `itp`/`shs` parity streams. |
| **⚙️ Execution & self-host (FFI-heavy, Phase 8)** | ~~`run`~~ (eval), `repl`, `fixpoint`, `self_host`, `roundtrip`, `forms_equiv`, `doctest`, `test` | Wrap `:compile.forms` / code-loading / `GenServer`. **`Rian.Run.eval` is ported** (the `run` stream): gate → load every module (+ prelude) → resolve the zero-arg entry across modules → apply, errors-as-values — over `Rian.Beam.runEntry`'s `runEntryImpl` FFI. The **file/Manifest half** (`run_file`/`bundle_and_load`/`cli`) stays at the filesystem boundary; **`repl`** is interactive/stateful; **`roundtrip`** needs the Elixir→Rian transpiler (unported); **`forms_equiv`** deconstructs Erlang forms as *data* (the port builds them as opaque `ETerm`, so it would need a forms-as-ADT redesign). For the **JS** build these are skipped in-browser. |
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
Total **1149/1149** parity records across Lexer/TypeStr/Pratt/Core/Prim/Decl/Range/PatternLower/
Exhaustiveness/Prelude/External/Coherence/Check/Builtins/Shadow/Macro/Protocol/Reach/Capability/
InferLocal/Assemble/Comptime/Opaque/**JS**/**Lower.Rust**/**JVM**/**Beam**/**Run** (the count is the harness's own `N/N` total — `parity.erl`
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
