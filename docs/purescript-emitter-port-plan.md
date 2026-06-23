# PureScript emitter port plan — JS (+ `.ts`), JVM, Rust, Elixir, and portable Beam

Implementation plan for porting the five Rian emitters to PureScript/purerl under the ADR-0084
migration, grounded in the established patterns (parity-gated stages, reflection-free Core
traversal, `@rian_sig`, run-the-output verification for emitters). Companion to
`docs/purescript-migration.md`.

> **The gate on everything here is `Check.annotate` + the whole-program inference context
> (`ic`).** All four *source* emitters depend on it; it is not yet ported. See the callout below
> and §0 of the sequencing.

Targets, by difficulty:

- **Part A — `Rian.JS` + `.ts` sidecars.** Direct Core→string emitter plus a new
  TypeScript-declaration-sidecar feature. Well-bounded.
- **Part B — portable `Rian.Beam`.** Research-grade; **conflicts with ADR-0084 as written**
  (§B.0).
- **Part C — `Rian.JVM` (Kotlin).** A second direct Core→string emitter, ~80% shared shape with
  JS (§C).
- **Part D — `Rian.Rust`.** The deep one — ownership lowering, the bulk of `Rian.Lower`, gated on
  `Rian.Capability` (§D).
- **Part E — `Rian.Elixir` (text).** A *secondary*, non-run-path target (live consumers:
  `Rian.Roundtrip`'s cross-check + the protocol-dispatcher display) whose roundtrip role is
  `Rian.Beam`-subsumed — last / optional (§E).

> ## The prerequisite that gates ALL of these: `Check.annotate`
>
> **Every source emitter (JS, JVM, Rust, Elixir) calls `Check.annotate` + `Check.program_ic` +
> `Check.clause_env`** — the pass that fills each typed-Core node's type (ADR-0050 §3) —
> verified in `js.ex:180/224/502`, `jvm.ex:196/256/533`, `lower.ex:249/417`. None of these are
> ported (only `Check.infer` stages 1–3 are). `annotate`/`program_ic`/`clause_env` need the
> whole-program **inference context (`ic`)** that the Check port has deferred. So **the emitter
> phase opens with the `ic` + `annotate` + `program_ic` + `clause_env`, full stop** — no emitter
> work is real before it. (An earlier draft of §A.0 said "JS is largely portable now"; that was
> wrong — corrected below.)

---

## Part A — `Rian.JS` → PureScript, with `.ts` sidecars

### A.0 What it is today

`lib/rian/js.ex` (1053 LOC) is a **direct Core→JS-string emitter** (ADR-0049 Tier 1):
`compile/1 :: String -> String`. It threads a whole-program boolean `i53` (native `number` vs
`BigInt`, ADR-0064), lowers a multi-clause function to a positional **dispatcher** with guarded
fall-through blocks, lowers sum variants to tagged arrays (`["Ctor", …]`), and raises
`Rian.JS.Unsupported` for staged forms (bitstrings, non-atom map keys, wide ints, FFI without a
`:js` body). **Dependency correction:** beyond the IR and the ported `Core`, JS calls
`Check.program_ic`/`annotate`/`clause_env` (`js.ex:180/224/502`), so it is **gated on
`Check.annotate`/`ic`** like every other emitter — *not* portable before that prerequisite lands
(see the callout above). The int-mode `reject_wide_int!` reads signatures, but the per-node types
come from `annotate`.

### A.1 Verification model

Source emitters can't use the s-expr parity oracle — they are verified by **running the emitted
JS through `node`** and asserting *values* (see `js_test.exs`). Two streams:

- **`jss`** — byte-equal the emitted JS source string against the Elixir reference (cheap, no
  toolchain; catches emitter drift).
- **`jsr`** — compile a small program, run `node` on both the Elixir- and PS-emitted JS, assert
  identical stdout (the behavioral gate; `@tag` it to the toolchain lane like `:jvm`/`:rust`,
  batched into one `node` invocation per the `jvm_test` pattern).

`jss` is the workhorse; `jsr` is the truth.

### A.2 Stages (each a parity-gated commit)

1. **`js1` — function core.** `compile`, the dispatcher shape, single/multi-clause `def`,
   params/vars, unary/binary ops, `if`, literals (the `i53` mode threading), local calls,
   tuples→arrays, `when` guards.
2. **`js2` — sum variants + patterns.** Construction → tagged arrays; clause patterns checking
   the tag + recursing into fields (nested + literal); the `reject_wide_int!` /
   `reject_mixed_int_mode!` rejections (confirm the needed `Check` slice is ported; if not, port
   that helper first).
3. **`js3` — the rest of the supported subset.** Type-patterns (`x Int53 | String` → `typeof`
   narrowing), `@external(:js, …)` bodies, strings/concat, lists, atom-key map objects. Keep the
   same `Unsupported` raises for the genuinely-staged forms — faithfully.
4. **`jsr`** — wire the `node`-run behavioral gate over a handful of end-to-end programs.

### A.3 The new feature — `.ts` sidecar emission

Not in the Elixir reference, so this is **new, ADR-governed work** (write a short ADR-0049
amendment — it changes the JS backend's output contract). Design:

- A new `compileTs :: Prog -> String` (alongside `compile`) that emits a **`.d.ts` declaration
  sidecar** from the **typed IR**, not the JS text:
  - a **sum** `type Shape := Circle(r Float64) | Square` → a TS **discriminated union**
    `type Shape = ["Circle", number] | ["Square"]` (matching the tagged-array runtime rep), a
    nominal alias, and per-ctor constructor decls `declare function Circle(r: number): Shape`.
  - a **struct** → a TS `interface` / tuple type matching the runtime shape.
  - each **`pub` function** → `declare function name(a0: T0, …): R` over the Rian→TS bridge:
    `Int53`/`Int32`→`number`, `Int`→`bigint`, `Float64`→`number`, `Bool`→`boolean`,
    `String`→`string`, `Vec(T)`→`T[]`, `Fn(A,R)`→`(a: A) => R`, `Option(T)`→`["Some", T] |
    ["None"]`, a `forall T`→a TS generic `<T>`. The int-mode (`i53`) decides `number` vs `bigint`,
    consistent with the runtime.
- **Honesty constraint:** the `.ts` types must describe the *actual runtime representation*
  (tagged arrays), not an idealized nominal model — otherwise the declarations would lie about
  the values. State this in the ADR.
- **Parity:** a `tsd` stream byte-equals the emitted `.ts` against an Elixir reference. This means
  **adding `.ts` emission to `lib/rian/js.ex` first** (so there is an oracle), then porting it —
  same "reference is the oracle" discipline as everything else. Optionally a `tsc --noEmit` lane
  (like the rustc lane) asserting the `.ts` type-checks against the emitted `.js`.

### A.4 Risk / effort

- **Effort:** ~4 stages (A.2) + ~3 for `.ts` (Elixir oracle, port, `tsc` lane) ≈ **7–8
  parity-gated commits**. Well-bounded.
- **Risks:** the `Check` slice JS needs for `reject_*` — verify ported (low). The `.ts`
  runtime-shape fidelity (medium — easy to emit pretty-but-wrong types; the `tsc --noEmit` lane
  mitigates).

---

## Part B — `Rian.Beam` → PureScript, **portable** BEAM bytecode

### B.0 The honest framing (read first)

This is the **most ambitious item in the migration**, and it **conflicts with ADR-0084 as
written**. Three facts held in tension:

1. **Today's architecture is already half-portable.** The Beam emitter lowers Core → a
   **portable `Form` sum** (`Rian.Beam`'s `FInt/FStr/FVar/FAtom/FCtor/FOp1/FOp2/FConcat/
   FBinAll/FCharBin/…`, carrying ops/names as *strings*). Only the *last mile* — `Form → real
   Erlang abstract forms → :compile.forms/2 → .beam` — is FFI (`:compile.forms` is the Erlang
   compiler).
2. **ADR-0084 deliberately keeps `:compile.forms` as the FFI boundary**, because the project's
   flagship result is **byte-identical `.beam` (v1==v2)** produced *by* `:compile.forms`. A
   from-scratch portable BEAM backend will **not** produce byte-identical output (a different
   compiler emits different — though semantically equivalent — bytecode). So pursuing the
   bytecode track **redefines the flagship invariant** from "byte-identical `.beam`" to
   "**behaviorally-identical `.beam`** (same results when run on the BEAM VM)". Defensible, but it
   must be an explicit ADR decision, not silent drift.
3. **Reimplementing `:compile.forms` in full is out of scope** — it is the entire Erlang compiler
   (abstract forms → Core Erlang → Kernel → BEAM SSA → asm → bytecode). The tractable target is a
   **direct compiler for the constrained subset the Rian Beam emitter actually produces**
   (function clauses, simple patterns, literals, tuples/cons, calls, guards) → BEAM bytecode → the
   `.beam` chunk container.

### B.1 Recommended decomposition (de-risk by staging)

**Stage B0 — Port the portable `Form` layer first (faithful to ADR-0084, immediate value).**
Port `Core → Form` to PureScript (a pure, reflection-free, string-carrying Core pass —
another Core consumer like `Shadow`). Keep `Form →
:compile.forms → .beam` as a **thin checked-in `.erl` FFI module** (the existing ADR-0084
boundary). **Parity:** a `bem` stream serializing the `Form` sum (a shared `formSexpr`), exactly
like `cor`/`dcl`. **~3 stages, low risk** — delivers a working PS Beam emitter that still produces
byte-identical `.beam`, just moving the portable part into PS and shrinking the FFI to one
function. **Do this regardless of whether the bytecode track proceeds.**

**Stage B1 — A BEAM-bytecode *model* + `.beam` chunk encoder (portable, no compilation yet).**

- Define the BEAM instruction set as a PS sum (the opcodes the subset needs: `label`,
  `func_info`, `move`, `call`/`call_ext`/`call_only`, `return`, `allocate`/`deallocate`/
  `test_heap`, `get_tuple_element`/`put_tuple2`, `is_eq_exact`/`is_tuple`/`test_arity`,
  `select_val`, `badmatch`/`if_end`, `gc_bif`/`bif` for operators, `put_list`, …).
- Write the **`.beam` container encoder** (pure, the most spec-mechanical part): the IFF wrapper
  (`"FOR1"` + size + `"BEAM"`) and the chunks — `AtU8` (atom table; first atom = module name),
  `Code` (header + the **compact term encoding** of the instruction stream), `ExpT`/`LocT`/`ImpT`
  (function tables), `StrT`, `LitT` (the `beam_lib`-style compressed literal table), `FunT`,
  `Line`, `Attr`, `CInf`. The compact opcode encoding (tag bits for small-int/atom/x-reg/y-reg/
  label/literal operands) is well-documented (the BEAM book / `beam_asm`).
- **Validation:** round-trip — encode a hand-built tiny module, write `mymod.beam`,
  `:code.load_binary` it on the BEAM, call it, assert the result. **The BEAM loader is the spec
  oracle** — if it loads and runs correctly, the encoding is right. This is the insight that makes
  B1 tractable without re-deriving the spec from prose.

**Stage B2 — The `Form → BEAM-instructions` compiler (the hard core).**

- **Pattern-match compilation:** the Rian dispatcher is already a decision structure; lower each
  clause head to `test`/`get_tuple_element`/`is_eq_exact` + `select_val` jumps, with `func_info` +
  `if_end`/`badmatch` fallthrough. `Rian.PatternLower`/`Exhaustiveness` (already ported) give the
  matrix structure to drive this — reuse them.
- **Expression compilation + register allocation:** a simple linear/stack allocator over X (arg/
  temp) and Y (stack/persistent) registers — operators → `gc_bif`/`bif`, calls → `call`/`call_ext`
  with the import table, literals → the literal table, tuples/cons → `put_tuple2`/`put_list`.
- **`-spec`/`-type` Dialyzer forms** do not live in the bytecode path — they are the
  `:debug_info` / `Dbgi` Erlang-term chunk. Emit it from the `Form`/IR types if
  Dialyzer-checkability must be preserved; otherwise drop it and note the loss.
- **Verification:** the `beam_module_fixpoint_test` discipline, inverted — for every fixture, (a)
  compile via the portable backend → load → run; (b) compile via `:compile.forms` → load → run;
  **assert identical observable results** (not identical bytes). This behavioral-equivalence gate
  replaces byte-identicality.

### B.2 Scope boundary for B2

Match the emitter's *current* subset only: multi-clause `def`, integer/float/bool/string/atom
literals, variables, binary/unary ops, tuples, cons/list patterns, sum-variant construction + tag
patterns, local + remote calls, `when` guards. **Exclude** (raise/stage, as the emitter already
does): bitstrings, maps-beyond-simple, closures/funs (`FunT` + `make_fun2` is a sub-project),
exceptions/`try`, receive/concurrency. Be explicit — a `.beam` backend that silently mis-compiles
a fun is far worse than one that refuses it.

### B.3 Risk / effort (realistic)

- **B0:** ~3 stages, low risk, high value — **start here; worth doing on its own.**
- **B1 (encoder + model + loader round-trip):** ~4–6 stages, medium risk (the compact encoding +
  literal-table compression are fiddly; the BEAM loader is an unforgiving but precise oracle).
- **B2 (the Form→bytecode compiler):** **large, research-grade — 10+ stages**, high risk
  (pattern-match compilation + register allocation are real compiler-backend work; could expand).
- **Cross-cutting:** BEAM bytecode is **versioned** — the instruction set changes across OTP
  releases (the `Code` chunk carries an opcode-max). The portable backend must target a specific
  OTP opcode set and assert the host matches, or it will not load. Pin it.

### B.4 Recommendation

Do **B0 now** — a clean, faithful, valuable port that shrinks the FFI to one function and keeps
byte-identical `.beam`. Treat **B1+B2 as a separate, ADR-gated research track**, and **before
starting B2, write an ADR** that (a) explicitly downgrades the flagship invariant from
byte-identical to behaviorally-identical `.beam`, (b) records the OTP-opcode-version pin, and (c)
scopes the supported instruction subset. Without that ADR the work would silently contradict
ADR-0084's central claim.

---

## Part C — `Rian.JVM` → PureScript (Kotlin)

### C.0 What it is today

`lib/rian/jvm.ex` (1249 LOC) is a **direct Core→Kotlin emitter** (ADR-0049 Tier 2):
`compile/1 :: String -> String`. Same shape as JS — a multi-clause `def` lowers to a positional
**dispatcher**; a sum lowers to a Kotlin `sealed interface` + `data class` + smart-cast `is`
patterns; it raises `Rian.JVM.Unsupported` for the Tier-2 staged forms (arity-≥4 tuples, tagged
tuples, maps/structs/FFI). It is coupled to `Rian.Reach` (`jvm.ex:161`, `assoc_blocks_jvm?` — an
associated-type shape that pins a function off `:jvm`).

### C.1 Plan

- **Gated on `Check.annotate`/`ic`** (`jvm.ex:196/256/533`), identical to JS.
- **Port as a paired track with JS** — the dispatcher lowering, clause→guarded-block, and
  pattern→structural-test logic are ~80% shared. Factor the common part into **`Rian.Emit.Common`**
  so JS and JVM don't fork it (and Rust later reuses pieces). This roughly **halves** the JVM
  port.
- **Verification:** the `jvm` source-equality stream (byte-equal the emitted Kotlin against
  `Rian.JVM.compile`) + a `kotlinc`+`java` **run lane** (`jvk`). The run lane is the **slowest in
  the suite** — the reference batches ~20 cases into a single `kotlinc -include-runtime` compile
  (`jvm_test.exs` `setup_all`); the port must reuse that batching or the lane dominates wall-clock.
- **Stages (~3–4):** `jvm1` function core + dispatcher (shared with JS), `jvm2` sum `sealed
  interface`/`data class` + smart-cast patterns, `jvm3` lists/`Vec(Char)` Str/Char + `${float}`,
  `jvk` run lane.

---

## Part D — `Rian.Rust` → PureScript (extracted from `Rian.Lower`)

### D.0 What it is today

Rust lives inside `Rian.Lower` (3275 LOC) — **413 `rust`/`Rust` references**, the bulk of the
module — alongside the Elixir-text emitter (Part E). It is the **only emitter coupled to
ownership**: `lower.ex:408` calls `Rian.Capability.beam_legal!`, and the Rust path does
owned↔borrow coercion, parametric-type instantiation, `Fn` closures (`&impl Fn` / `Box<dyn Fn>` /
`Rc<dyn Fn>` enum fields), and the protocol→trait UFCS rewrite. This is the densest code in the
compiler — **a project, not "an emitter."**

### D.1 Plan

- **Prerequisite chain:** `Check.annotate`/`ic` → **`Rian.Capability`** (BEAM linearity over Core,
  ~290 LOC, a Core-consuming *gate* — discrete and parity-able, not backend magic) → **`Rian.Rust`**.
- **Extraction:** port the `to_rust`/`rust_program`/`rust_protocols` functions (`lower.ex:1280/
  1343/1302`) into a new **`Rian.Rust`** module, with the shared pattern-lowering / bound-name
  threading in **`Rian.Emit.Common`**. The split is **oracle-neutral** — parity is on the emitted
  Rust *string*, diffed against `Lower.to_rust` (the `rst` stream); the PS module structure is
  invisible to the oracle (see the debate consensus).
- **Verification:** the `rst` source-equality stream is the cheap drift-catcher; the truth is the
  existing **`rustc --test`** honesty bar (`reach_rust_honesty_test.exs:85`) — emitted Rust must
  *compile*, not merely byte-match. Reuse that lane.
- **Stages (large, ~6–8):** rust core + dispatcher; capabilities→signatures (`val`→`&[T]`,
  `iso`→owned, `tag`→`&T`); sum/struct→`enum`/`struct`; owned↔borrow coercion; parametric types;
  `Fn` closures; protocol traits. Each is its own parity-gated commit.

---

## Part E — `Rian.Elixir` (text) → PureScript — last / optional

### E.0 What it is

The Elixir-text half of `Rian.Lower` (`to_elixir/5`, `lower.ex:346`). The reference's **own
moduledoc** frames it as a *secondary* target: **never the run path** — `Rian.Beam` (Part B) is the
real BEAM backend — but **not "debug only."** It has live consumers: `Rian.Roundtrip`'s path-3
differential cross-check, the protocol-dispatcher display (`mix examples`), and
`mix rian.compile --show-elixir`. Its roundtrip role is `Rian.Beam`-subsumed (so it is not
load-bearing for the port).

### E.1 Plan

- **Lowest priority — possibly never.** Completion of "emitters ported" is defined by the
  **run-path** targets (Beam, Rust, JS, JVM); the Elixir *text* is an inspection artifact whose
  parity is a nice-to-have, not a gate.
- If ported: extract `to_elixir` into **`Rian.Elixir`** (reusing `Rian.Emit.Common`), parity via
  an `elx` stream vs `Lower.to_elixir`, and **mirror the reference's secondary-target callout** (not
  the run path, but with live consumers) in the PS moduledoc so the artifact's status is clear.

---

## Team decision (debate consensus, 2026-06-21)

A controversial review of this plan settled five points:

1. **The emitter phase is gated on `Check`.** All four source emitters call
   `Check.annotate`/`program_ic`/`clause_env`; none are ported. **Land the `ic` + `annotate` +
   `program_ic` + `clause_env` first** — *the* prerequisite. (The earlier "JS portable now" claim
   was a factual error, now corrected.)
2. **Order:** `Check.annotate`/`ic` → **JS + JVM as a pair** → **`Capability`** → **Rust** →
   **Elixir-text last/optional**.
3. **Split `Rian.Lower` into `Rian.Rust` + `Rian.Elixir` + a shared `Rian.Emit.Common`.** Parity
   is on the emitted **output** (`rst`/`elx` streams vs `Lower.to_rust`/`to_elixir`), so the split
   is oracle-neutral and idiomatic. Shared helpers must be a real module, not copy-paste.
4. **Verification = run the output** per target — `node` (JS), `kotlinc`+`java` batched (JVM),
   `rustc --test` (Rust); the source-equality streams are the cheap drift-catchers, the toolchain
   lanes are the truth.
5. **Completion does not require the Elixir-text emitter** — it is the reference's own admitted
   debug view.

**Future developments.** Once `annotate` lands, JS/JVM are ~80% shared (a common dispatcher
lowering in `Rian.Emit.Common` ≈ halves the JVM port). The toolchain-run lanes (`node`/`kotlinc`/
`rustc`/`tsc --noEmit`) are one pattern → a single parameterized batched runner harness. Porting
`Capability`/`Reach` *before* Rust also tightens the reach matrix's PS-side honesty (the `rch`
stream exists from concurrent work) — sequence for that synergy.

**Concrete suggestions (rated).** Open the emitter phase with `Check.annotate`/`ic` (10/10);
JS + JVM paired, sharing the dispatcher (9/10); Rust gated on `Capability`, honesty via
`rustc --test` (9/10); split `Lower` → `Rust`/`Elixir`/`Emit.Common` (8/10); Elixir-text
last/optional, labelled a secondary non-run-path target (7/10); one parameterized toolchain-run harness (7/10).

---

## Suggested sequencing

0. **PREREQUISITE — `Check.annotate` + the `ic` + `program_ic` + `clause_env`.** Gates *all four*
   source emitters (JS/JVM/Rust/Elixir). Nothing in Parts A/C/D/E is real before this. ~several
   stages (it is the deferred whole-program inference context).
1. **Part A** (JS) **+ Part C** (JVM) as a **paired track** sharing `Rian.Emit.Common`'s
   dispatcher lowering — ~8 + ~3 commits, two Tier-relevant targets, output-run lanes
   (`node` / `kotlinc`).
2. **Part B0** (portable Beam `Form` layer, keep `:compile.forms` FFI) — ~3 commits, faithful to
   ADR-0084; independent of the `Check` prerequisite (the `Form` layer is a Core pass like
   `Shadow`), so it can run **in parallel** with step 1.
3. **`Rian.Capability`** (the Rust prerequisite gate) → **Part D** (Rust) — the deep track, ~6–8
   commits, honesty via `rustc --test`.
4. **Part A's `.ts` sidecars** — after the JS core (needs an Elixir `.ts` oracle first; ADR-0049
   amendment).
5. **Part E** (Elixir-text) — last / optional; the reference's own debug view.
6. **Part B1/B2** (portable bytecode) — the big bet, only after an ADR ratifies the
   byte-identical → behavioral shift.

All parts also need, per the migration conventions: `@rian_sig` on every public function (caps +
type bridge, no `_Unk` where a concrete type is known), and `@rian_host` on the genuinely
host-effectful functions (`Beam.load`/`compile` touch `:code`/files → host; the pure
`compile :: Prog -> String` / `Prog -> BeamBinary` cores do not).
