# ADR-0075 — Transpiler type inference: filling `_Ty`/`_Ret` holes

**Status:** Accepted (direction) · implemented (MVP: `Rian.Transpile.Infer`, `--infer`)
**Implemented:** partial — Algorithm-J whole-program inference over the Elixir AST with
occurs-check, `[Gen]` generalization, `Int53` cross-target defaulting, two-pass intra-module
sibling propagation; cross-module + error-set/sum-type synthesis (Phase B) deferred
**Refs:** ADR-0034 (type-system foundations / infer-local·declare-public), ADR-0040 (error
handling / `T | E`), ADR-0042 (`Fn(…)`), ADR-0064 (portable numerics / `Int53`), ADR-0063
(self-host porting track)
**Owners:** inference · multi-target · rigor (PM)

## Context

The Elixir→Rian transpiler (`Rian.Transpile`) emits draft Rian where every function carries
placeholder type holes — `_Ty` per parameter, `_Ret` per return — because Elixir is untyped.
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
- **Phase B — the path to 80% on IR code (the hard part).**
  - **Result/error-set inference** (ADR-0040): a function returning `{:ok, x}` / `{:error, tag}`
    across branches infers `X | tag…`. The single biggest lever (tuple+atom ≈ the same idiom).
  - **Sum-type reconstruction**: collect `%Mod{…}` constructions/patterns program-wide, infer
    field types, and **synthesize the `type` declarations** so a struct return is a *valid* fill.
    The genuinely hard, human-judgment piece (which variants belong to which sum); automating it
    safely is its own ADR.
- **Honest ceiling:** 80% is corpus-dependent. Algorithmic code already approaches it; the
  compiler corpus needs Phase B. We will **not** hit 80% by relaxing rule 2 (no guessed structs/
  tuples) — the fill rate is reported alongside a "must type-check" gate so a higher number can
  never come from accidental fills.

## Consequences

- `mix rian.transpile --infer` (and `--infer-report` for a per-hole ledger) fills what's provable;
  the rest stays an honest hole. Existing transpiler behavior is unchanged without the flag.
- Fill rate becomes a tracked, ratcheting metric — but always paired with the type-check gate, so
  it measures *correct* fills only.

## Open items

- Cross-def fixpoint (mutual recursion) beyond the 2-pass approximation.
- Error-set inference and sum-type synthesis (Phase B) — likely a dedicated ADR.
- Whether to run the real `Rian.Check` per module as a hard accident gate once drafts compile.
