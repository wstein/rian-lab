# ADR-0075 — Transpiler type inference: filling `_Unk` holes

**Status:** Accepted (direction) · implemented (MVP: `Rian.Transpile.Infer`, `--infer`)
**Implemented:** Algorithm-J whole-program inference over the Elixir AST with occurs-check, `[Gen]`
generalization, `Int53` cross-target defaulting, two-pass intra-module sibling propagation,
Phase A cross-module sigs, Phase B Result/error-set inference + synthesis, and Phase C `@spec`
harvesting (cross-checked) — all accident-free (type-check-gated). Measured ceiling on the Elixir
compiler corpus is ~31% (corpus-bound; see below); `@spec` harvest adds 51 spec-backed slots with
0 regressions; sum-type reconstruction for struct IR remains the open lever
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
    marker rather than emit a wrong decl. `port_analysis` already inventoried struct fields (the §3
    proposed-sum clusters); this closes the matching gap on the transpiler side.
  - **Nested struct modules (IMPLEMENTED).** The Elixir one-struct-per-module idiom (an outer
    `defmodule` wrapping many `defmodule Sub do @enforce_keys … defstruct … end`, e.g. `lib/rian/ir.ex`'s
    12 IR structs) no longer drops each inner module to a `TODO[port]`. A nested `defmodule` is
    recursed: a **struct-only wrapper flattens** to its `struct Sub(…)` decl (the module is just a
    namespace for the struct), and a submodule with real content nests as `mod Sub do … end`.
    `@enforce_keys` is skipped (subsumed by Rian's typed fields). So `ir.ex` now yields all 12
    `struct` skeletons instead of a wall of markers.
  - **`@type` harvesting (IMPLEMENTED).** `Rian.Transpile.Infer.collect_types/2` reads every `@type`
    into a **type-env** (local name → Rian term) and a list of synthesized decls. A *union* `@type`
    (`@type ty :: String.t() | atom()`) synthesizes a named `type Ty := String | Symbol` decl; a
    *single-type* alias (`@type m :: module()`) or struct alias (`@type t :: %__MODULE__{}` → the
    module's struct, `@type t :: Session.t()` → `Session`) **inlines** with no decl. The type-env then
    **resolves local refs in `@spec`s** (`@spec unwrap(t()) :: t()` → `unwrap(b Box) Box`), amplifying
    Phase C: specs that mention local types now fill instead of bailing. Untranslatable `@type`s
    (tuples/maps) synthesize nothing and resolve nothing — honest. A consumed `@type` becomes a passive
    `# type:` provenance line. Wired into both the transpiler and the `whole_program` (port-analysis)
    path. Like `@spec`, the *mechanism* is general; `lib/rian`'s own `@type`s are mostly tuples, so the
    gain on this corpus is small.
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

## Pre-step port-analysis (the human-judgment bridge)

Since the wall is human-judgment-shaped, a team debate converged on a **read-only,
generated `PORT.analysis.md`** (`mix rian.port_analysis`, `Rian.PortAnalysis`) as the
first increment: it surfaces (1) inferred sigs with reach, (2) holes-with-reasons,
(3) **proposed sum-type groupings** clustered from cross-module dispatch
co-occurrence, and (4) an **error-idiom inventory** with proposed variants. It is
regenerable (anti-drift). It earns its keep: run cross-module on `lib/rian` it
reconstructs the two real `Core` sums (`Expr` = the `E*` nodes, `Pat` = the `P*` nodes)
from non-local dispatch evidence — the decision a human cannot make from a single draft.
Generating it also caught a latent bug: a partially-resolved parametric type
(`Vec(<unknown>)`) was rendered `Vec(hole)` (invalid Rian); it now falls back to a
whole-slot hole.

### The `port.spec` feedback loop (IMPLEMENTED, `Rian.PortSpec`)

The report's placeholders aren't hundreds of distinct types — they're a few dozen real
ones, each carrying **one shared name** across the whole program (the whole-program
unification links every site). So the loop is **decision amplification**: the human edits
a `port.spec` of `Placeholder = RianType` lines (`Sum1 = Expr`, `Unk0042 = String`), and
`mix rian.port_analysis --spec port.spec` substitutes program-wide — **one decision per
shared placeholder re-resolves every site**. On `lib/rian`, naming the two dispatch sums
(`Sum1 = Expr`, `Sum2 = Pat`) re-resolves ~90+ `Expr` sites (and the `Pat` sites) from two
edits; `--emit-spec` writes a stub listing every decision to make (sums with members,
unknowns with site counts) as a checklist. A named sum's now-fully-resolved sigs graduate
out of the §2 review list, and the placeholder index shows only the undecided remainder —
so the report doubles as a porting *burndown*. The substitution is a rename of shared
names, not a re-inference, so it cannot introduce an accidental fill (the human owns each
`= RianType` decision). Still deferred: feeding the resolved spec into the transpiler's
emitted drafts (`Rian.Check`-gated), and mapping error idioms through the same file.

## Open items

- Cross-def fixpoint (mutual recursion) beyond the 2-pass approximation.
- Error-set inference and sum-type synthesis (Phase B) — likely a dedicated ADR.
- Whether to run the real `Rian.Check` per module as a hard accident gate once drafts compile.
