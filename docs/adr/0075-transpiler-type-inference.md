# ADR-0075 — Transpiler type inference: filling `_Unk` holes

**Status:** Accepted (direction) · implemented (MVP: `Rian.Transpile.Infer`, `--infer`)
**Implemented:** Algorithm-J inference over the Elixir AST with occurs-check, `[Gen]`
generalization, `Int53` cross-target defaulting, two-pass intra-module sibling propagation,
Phase A cross-module sigs, Phase B Result/error-set inference + synthesis, and Phase C `@spec`
harvesting (cross-checked) — all accident-free (type-check-gated). Measured ceiling on the Elixir
compiler corpus is ~31% (corpus-bound; see below); `@spec` harvest adds 51 spec-backed slots with
0 regressions; sum-type reconstruction for struct IR remains the open lever. The exploratory
`port_analysis` / `port.spec` decision-amplification layer was **removed** as unused (see below)
**Refs:** ADR-0034 (type-system foundations / infer-local·declare-public), ADR-0040 (error
handling / `T | E`), ADR-0042 (`Fn(…)`), ADR-0064 (portable numerics / `Int53`), ADR-0026
(Dialyzer `-spec` *emission* — the inverse map), ADR-0063
(self-host porting track)
**Owners:** inference · multi-target · rigor (PM)

## Context

The Elixir→Rian transpiler (`Rian.Transpile`) emits draft Rian where every function carries
a `_Unk` placeholder hole per parameter and per return, because Elixir is untyped.
A human then fills them. This ADR governs the pass that fills them **automatically where
provable**, *producing the explicit signatures the language requires* — it does **not** reverse
ADR-0034's infer-local/declare-public boundary (the compiler still declares `pub` sigs; the pass
just writes the declaration a human otherwise would).

Two hard constraints shape the design:

1. **Cross-target correctness.** A numeric hole must default to `Int53` — the portable
   all-target integer (`:ex/:rs/:js/:jvm`, ADR-0064) — never `Int64` (off `:js`) or `Int` (off
   `:rs/:jvm`), so an inferred function isn't needlessly pinned off a target by `Rian.Reach`.
2. **No accidental fills.** A filled type must be *correct* — better to leave a hole than emit a
   wrong type. A wrong fill produces invalid or mis-typed Rian, which is worse than an honest hole.

## Decision

### Algorithm (the engine, `Rian.Transpile.Infer`)

Algorithm-J-style (Damas–Milner) constraint generation + union-find, over the **Elixir quoted
AST** at the transpiler's rendering seam, reusing `Rian.Check.unify/2` + `join/2`:

- **Terms:** `{:var, id}` | `{:con, name}` | `{:app, head, args}` (`Vec`/`Option`/`Fn`).
- **Constraints** from literals, `+ - * / div rem`, `<> ++`, comparisons/`and`/`or`/`not`, `if`,
  `case`, list/cons, lambdas & captures (closed over the enclosing env), and **calls to typed
  functions** — prelude `fsigs` (loaded once, cached) and intra-module siblings — by freshening
  the callee's tvars and unifying. Per def group: one shared var per parameter and one return var
  (clauses join into it).
- **Occurs-check** before every variable binding (mandatory — recursive code otherwise builds a
  cyclic term `X = Vec(X)` that loops `resolve`/`render`); on failure → conflict → hole.
- **Generalization** = the `[Gen]` rule, *adapted for an incomplete inferer*: quantify only the
  non-numeric free vars that flow a parameter into the return (`id`/`head`/`map` shapes), each its
  own `forall` tvar. A complete HM checker generalizes all free sig vars; ours can't, because a var
  is also free when analysis hit something it doesn't model — generalizing those would over-claim.
- **Defaulting:** numeric-only → `Int53` (rule 1); otherwise the hole stays.
- **Two passes:** pass 1 infers each group in isolation; pass 2 re-infers with the fully-resolved
  sigs as a sibling table (intra-module call edges).

### The no-accidental-fills contract (rule 2, made concrete)

A slot is filled **only** from a *sound anchor* — a literal, an operator, a prelude/sibling
signature, or a parameter→return flow — and any **conflict leaves a hole**. The occurs-check, the
numeric-vs-non-numeric guard, and conflict→hole together mean the pass never emits a type it cannot
prove. Verification: an inferred draft must `Rian.Decl.compile`/`Rian.Check` cleanly (tested). This
is why the pass is honest-partial, not aggressive.

## Measured fill rate & root cause

On `lib/rian` the MVP fills **~31% of type slots** (815/2607). Per-file rates show this is
**corpus-bound, not an engine ceiling**: algorithmic modules lead (`prelude` 60%, `macro` 56%,
`pratt` 47%, `js/jvm` 42%) while pure-IR modules floor out (`ir.ex` 0%, `core.ex` 14%, `opaque` 18%,
`protocol` 19%). No file exceeds ~60%.

> **Re-measure 2026-06-17 (honesty note).** The current `--infer` output over `lib/rian` shows
> **652 printed `_Unk` holes** — far below the 1792 above. **This is *not* an inference gain.** The
> drop is the later **`defp`-omission policy** (a private function no longer prints `_Unk` for an
> unrecovered slot; `Rian.InferLocal` recovers it locally or it is silently omitted, ADR-0034), which
> removed ~1100 *printed* holes that were never *filled*. Reporting the 1792→652 fall as a higher fill
> rate would be the kind of aspirational claim ADR-0000's honesty bar forbids. The remaining 652 are
> overwhelmingly `pub def` slots whose blockers are the same Result/atom/struct-IR walls below. The
> Algorithm-J pass's marginal contribution on today's printed holes is ~29 (turning `infer:true` off
> raises the count to ~681); the clause-guard/type-predicate/Kernel-accessor evidence added in
> `bf54dd4` fills **3** of those printed holes — small because most of its ~140 type-determining
> guards sit in *private* functions whose slots are omitted, not printed. The evidence is sound and
> accident-free; its effect on the *roundtrip-relevant* (public) hole count is marginal, as the
> root-cause analysis below predicts.

Classifying the blocking construct of every unfilled group (counts overlap):

| blocker | groups | why it's a hole |
|---|---|---|
| atom (`:ok`/`:error`/tags) | 1438 | no standalone type; usually a tuple tag |
| 2-tuple `{:ok, x}`/`{:error, e}` | 1387 | the **Result idiom** — Rian type is `T \| E` (ADR-0040), not a tuple type |
| cross-module call (`Core.x`) | 755 | the sibling table is **same-module only** |
| n-tuple / map / struct | ~390 | struct IR needs a synthesized `type` declaration |

**Root cause:** `lib/rian` is a *compiler* — its domain is the tagged-tuple `Result` idiom, atoms,
struct IR, and cross-module calls. Filling those *correctly* requires (a) **error-set inference**
to give `{:ok,_}`/`{:error,_}` its `T | E` type, (b) **sum-type reconstruction** from `defstruct`
usage (the part CLAUDE.md notes "a human chose"), and (c) a **cross-module signature table**. None
are engine tuning; (a) and (b) are real analyses, and guessing them would violate rule 2.

## Roadmap to higher fill

- **Phase A — whole-program cross-module sigs (safe, IMPLEMENTED).** `prime_xmod/1` infers a
  global `{short_module, fun, arity} → sig` table and the cross-module call clause resolves against
  it (verified on a synthetic case: `bar(y) := A.foo(y)` → `bar(y Int53) Int53`). **Measured gain on
  `lib/rian`: ~0** (1792 → 1790 holes) — empirically confirming the root cause: cross-module callees
  in a compiler return structs/tuples (themselves unfillable), so resolving the calls fills nothing.
  Phase A is correct, safe, and additive; the IR floor, not call resolution, is the limit.
- **Phase B — Result/error-set inference (IMPLEMENTED) + the IR wall.**
  - **Result/error-set inference** (ADR-0040): a function whose tails are all `{:ok, v}` /
    `{:error, Tag}` (Capitalized ctor tags, ≥1 of each) infers `Payload | Errors`, **synthesizing**
    the `type Errors := Tag | …` declaration. Verified correct and **accident-free** — the
    `checked_div` example type-checks under `Rian.Decl.compile`. Bare-atom / string / variable
    error tags **bail to a hole** (rule 2). **Measured coverage on `lib/rian`: 0 functions.**
    The reason is fundamental and worth stating: `lib/rian` is *Elixir* source using *Elixir* error
    idioms (`{:error, :atom}`, `{:error, "msg"}`, `{:error, %Struct{}}`), whereas a Rian `Result`
    requires a Capitalized **sum variant**. Bridging them is a **porting transformation**
    (atom→`PascalCase` variant + a body rewrite; atoms are BEAM-only anyway), **not type
    inference**, and it carries real accident risk — so it is out of scope under rule 2.
  - **Sum-type reconstruction** (the IR): collecting `%Mod{…}` and synthesizing `type` decls hits
    the same wall — field types are themselves nested structs/tuples, so synthesizing them safely is
    effectively reconstructing the whole type system (the human-judgment "which sum" part).
  - **`defstruct` skeleton (IMPLEMENTED).** A `defstruct [:x, y: 0]` no longer drops to a
    `TODO[port]` marker — the transpiler emits the **record skeleton** `struct Mod(x _Unk, y _Unk)`
    (named for the enclosing module, field names recovered, defaults dropped). This is the *safe*
    half of struct reconstruction: the field **names** port mechanically; only the field **types**
    stay `_Unk` holes (the IR wall above). A non-literal `defstruct @fields` still falls back to a
    marker rather than emit a wrong decl. This is the field-name half of struct reconstruction on
    the transpiler side.
  - **Nested struct modules (IMPLEMENTED).** The Elixir one-struct-per-module idiom (an outer
    `defmodule` wrapping many `defmodule Sub do @enforce_keys … defstruct … end`, e.g. `lib/rian/ir.ex`'s
    12 IR structs) no longer drops each inner module to a `TODO[port]`. A nested `defmodule` is
    recursed: a **struct-only wrapper flattens** to its `struct Sub(…)` decl (the module is just a
    namespace for the struct), and a submodule with real content nests as `mod Sub do … end`.
    `@enforce_keys` is skipped (subsumed by Rian's typed fields). So `ir.ex` now yields all 12
    `struct` skeletons instead of a wall of markers.
  - **Module-less sources (IMPLEMENTED).** A source that is **not** wrapped in a `defmodule` — a bare
    sequence of top-level `def`s (the shape of the codegen fixtures under `test/fixtures/codegen/` and
    of every hand-written `.rian`, since Rian source needs no module wrapper) — no longer collapses to
    a single `# TODO[port]: top-level is not a single defmodule` blob. It renders **flat**: the
    declarations are emitted with no `mod … do` box and no indentation, exactly as a finished
    module-less `.rian` looks. Inference (`--infer`) runs over the bare statement list just as it does
    inside a module. A statement with no Rian image still drops to its own greppable `TODO[port]`
    marker, so a non-declaration script degrades per-statement rather than as one opaque blob.
  - **ExUnit test modules (IMPLEMENTED).** A `defmodule … use ExUnit.Case … test "…" do … end`
    (detected by `use ExUnit.Case` or any `test`/`describe` block) is **flattened to module-less
    `@test def`s** — not wrapped in a `mod`, because a `mod` hides `@test def`s from `Rian.Test`'s
    discovery and the injected assertion macros from scope (ADR-0060). Each `test "name" do body end`
    becomes `@test def slug() Bool := …`; `assert`/`refute` rewrite to the assertion-macro vocabulary
    (`assert_eq`/`assert_neq` for `==`/`!=`, ADR-0060/ADR-0030); a *match* assertion `assert pat =
    expr` becomes a `case` on the truth of the match (`case expr do pat -> true; _ -> false end`,
    `refute` flips the arms) rather than the old `assert(pat := expr)` bind — the pattern's bindings
    are arm-scoped, not threaded to sibling assertions (Rian has no refutable block bind). Because
    ExUnit runs *every* assertion while a `@test def` returns one `Bool`, a multi-assertion body is
    **`and`-combined** with any non-assertion statements (binds, setup) as the block preamble. `use ExUnit.Case` is dropped
    (pure scaffolding); `assert_raise` and kin have no Rian image (no exceptions, ADR-0035) and stay
    greppable markers. A `describe "group" do … end` flattens to its inner `@test def`s with a
    `group_`-prefixed name (Rian tests don't nest), and a `setup`/`setup_all` block (no Rian fixture
    model) stays a marker. The result runs end-to-end via `Rian.Test` — closing the port loop the
    assertion macros opened.
  - **`@type` harvesting (IMPLEMENTED).** `Rian.Transpile.Infer.collect_types/2` reads every `@type`
    into a **type-env** (local name → Rian term) and a list of synthesized decls. A *union* `@type`
    (`@type ty :: String.t() | atom()`) synthesizes a named `type Ty := String | Symbol` decl; a
    *single-type* alias (`@type m :: module()`) or struct alias (`@type t :: %__MODULE__{}` → the
    module's struct, `@type t :: Session.t()` → `Session`) **inlines** with no decl. The type-env then
    **resolves local refs in `@spec`s** (`@spec unwrap(t()) :: t()` → `unwrap(b Box) Box`), amplifying
    Phase C: specs that mention local types now fill instead of bailing. Untranslatable `@type`s
    (tuples/maps) synthesize nothing and resolve nothing — honest. A consumed `@type` becomes a passive
    `# type:` provenance line. Wired into the transpiler. Like `@spec`, the *mechanism* is general;
    `lib/rian`'s own `@type`s are mostly tuples, so the gain on this corpus is small.
- **Phase C — `@spec` harvesting (IMPLEMENTED, cross-checked).** Elixir is untyped, so inference can
  only *reconstruct* types from usage — but a large fraction of real Elixir carries `@spec`, which
  **is** the human-written type the engine was reconstructing. `Rian.Transpile.Infer.collect_specs/1`
  harvests every `@spec`, `translate_spec/1` maps the Erlang/Elixir spec-type AST → a Rian term (the
  inverse of ADR-0026's `-spec` *emission*: `integer()`→`Int53`, `String.t()`/`binary()`→`String`,
  `[t]`→`Vec(t)`, `t1 | t2`→union, `atom()`/`module()`→`Symbol`, `%Mod{}`→the sum name). Types with
  no clean Rian image — `any()`/`term()`, tuples, maps, pids, local `t()` refs — yield **no hint** (a
  `nil` slot), so the slot stays an honest `_Unk` hole for a human. The seed is
  **cross-checked, never authoritative** (`seed_spec/6`): each sig var is unified with its spec term
  *after* the body pass, so a body-**hole** var **adopts** the spec (the fill) while a body-**concrete**
  var that **conflicts** keeps its proven type (unify reports `:conflict` and leaves it) — a stale or
  wrong `@spec` (e.g. `@spec f(integer()) :: integer()` over `def f(s), do: s <> "!"`) never forces an
  accidental fill, upholding rule 2. The consumed `@spec` is reclassified from a `TODO[port]` action
  marker to a passive `# spec:` provenance line. **Measured gain on `lib/rian`: 51 slots filled,
  0 regressions** — modest because the corpus's specs are param-heavy (`String.t()`/`module()`) with
  *tuple* returns (the `Result` idiom → no hint), but every fill is a real, type-checking recovery.
- **Honest, measured ceiling.** Across `lib/rian`, per-file fill spans 0–60% and aggregates ~31%;
  Phase A (cross-module) and Phase B (Result) each add ~0 *on this corpus* because it is a compiler
  written in Elixir-idiomatic structs + atom/string errors. **80% on this corpus is not safely
  reachable by type inference** — it would require porting transformations that violate rule 2.
  The engine and both phases are *sound and accident-free*; they fill well on **algorithmic /
  Rian-idiom code** and quarantine the rest as honest holes. We will **not** manufacture a higher
  number by relaxing rule 2; the fill rate is always paired with the "must type-check" gate.

## Consequences

- `mix rian.transpile --infer` (and `--infer-report` for a per-hole ledger) fills what's provable;
  the rest stays an honest hole. Existing transpiler behavior is unchanged without the flag.
- Fill rate becomes a tracked, ratcheting metric — but always paired with the type-check gate, so
  it measures *correct* fills only.

## Removed: port-analysis & the `port.spec` decision-amplification layer

An exploratory layer once sat on top of the engine: a read-only generated `PORT.analysis.md`
(`mix rian.port_analysis`, `Rian.PortAnalysis`) that surfaced proposed sum-type groupings
(clustered from cross-module dispatch co-occurrence) and an error-idiom inventory, plus a
`port.spec` *decision-amplification* loop (`Rian.PortSpec`) — a human edits `Placeholder =
RianType` lines once and a dedicated **whole-program** inference pass (`whole_program/4` +
`prime_wp/2`) substitutes the named type program-wide, into both the report and the
`mix rian.transpile DIR --spec port.spec` drafts. It demonstrably reconstructed the two real
`Core` sums (`Expr`/`Pat`) from dispatch evidence and amplified two edits into ~65 resolved slots.

**This layer was removed** (`mix rian.port_analysis`, `Rian.PortAnalysis`, `Rian.PortSpec`, the
`whole_program/4` pass, and the transpiler's `--spec` path): in practice the actual porting was
driven hands-on against `--infer` drafts, the spec-loop never entered the workflow, and a separate
whole-program inference pass duplicating the per-group engine was not worth carrying. The surviving,
**supported** inference surface is `mix rian.transpile --infer` / `--infer-report` — per-def-group
inference with a `prime_xmod/2` cross-module signature cache (Phase A). Sum-type reconstruction
(the human-judgment wall) remains an open lever, to be revisited under a dedicated ADR if pursued.

## Open items

- Cross-def fixpoint (mutual recursion) beyond the 2-pass approximation.
- Error-set inference and sum-type synthesis (Phase B) — likely a dedicated ADR.
- Whether to run the real `Rian.Check` per module as a hard accident gate once drafts compile.
