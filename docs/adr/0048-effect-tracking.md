# ADR-0048 — Effect Tracking: fine-grained, inferred, ambient (not object-capability)

**Status:** Accepted · **Resolves:** the ADR-0047 effects/IO open item
**Implemented:** partial — the **`host`/`spawn` effects** are end-to-end: `@effects(...)` grammar
(`Rian.Decl`), call-graph inference (`Rian.Reach.effect_sets/1`, reusing the FFI/concurrency leaf signal
`analyze/1` uses), and **exact** declare-public verification (`Rian.Check.check_effects`, §3 / ADR-0081
§2) — `test/rian/effects_test.exs`. **Not yet:** the neutral effects (`io`/`fs`/`clock`/`random`/`net`,
each needs its own leaf detection — `Rian.Decl` rejects declaring them for now); `comptime`-purity
gating; effect-polymorphism over function parameters; the transpiler emitting `@effects(host)`
**Refs:** ADR-0025 (memory capabilities — *orthogonal*), ADR-0030/0046 (`comptime` purity), ADR-0034 §1 (infer-local/declare-public), ADR-0035 (transparency — "what you read is what runs"), ADR-0039 (`<~` mutation), ADR-0040 §4 (composition — the parallel), ADR-0041 (per-target), ADR-0047 (pure/effectful boundary)
**Owners:** Arthur Pendelton (effect inference) · Marcus Chen (transparency) · Elena Rostova (lowering) · Maya Lin (multi-target) · Samir Patel (testability) · Kira Neri (determinism) · Chloe Bennett (comptime) · Liam Davis (family ergonomics) · Rachel Okafor (PM)

## Context

ADR-0047 set the *pure/effectful boundary* but not the model. Four options were weighed: **A** untracked
(Elixir-style — ruled out, because ADR-0046/0030 require a pure/impure distinction for `comptime`);
**B** purity-tracked with ambient IO; **C** effects-as-capabilities (object-capability, no ambient
authority); and full **algebraic effect rows** (Koka — rejected as too heavy and BEAM-hostile).

**Decision: B, refined.** Effects are *tracked* in signatures at **fine granularity** and enforced
**uniformly** across targets, but performed **ambiently** — no capability value is threaded. This keeps
the family's ambient-IO ergonomics (Elixir calls `IO.puts` with no token) while making a function's
effects **visible** and giving `comptime` a precise purity definition. The object-capability model (C)
was **considered and not chosen**: it offers sandboxing-by-construction and inject-a-fake mocking, but
at the cost of mandatory capability threading and the largest family divergence. C is recorded as the
**named alternative** to revisit if effect *visibility* proves insufficient.

## Decision

### 1. Effects are tracked, not authorized — ambient performance, visible signature

A function may perform an effect **directly** (ambient — no capability argument). What it **cannot** do
is hide it: the effect appears in the function's **declared or inferred** effect set. This is ADR-0035's
"what you read is what runs" extended to effects — **no hidden effects.**

```elixir
def greet(name String) !io               # effect set in the signature (illustrative spelling)
  Console.print("hi " <> name)           # ambient — no Console capability threaded
end

def double(x Int64) Int64                # empty effect set → pure
  x * 2
end
```

### 2. Fine-grained effect taxonomy; pure = empty set

The tracked effects are a small, **fine-grained**, extensible taxonomy: **`io`, `fs`, `clock`,
`random`, `net`, `spawn`** (process creation; BEAM), and **`host`** (calls fallible host FFI — see
below). **A function is pure iff its effect set is empty.** Fine-grained (not just pure/impure) so a
signature shows *which* world it touches — `clock`/`random` mark nondeterminism explicitly, distinct
from `fs`/`net`.

**`host` — calls fallible host FFI (accepted; the home for recoverable host errors).** Rian rejects
catchable `try`/`catch` (ADR-0040 "Considered: capability-guarded exceptions"): the only sanctioned
exception flow is `Prim.panic` (diverging, uncatchable — not an effect, it terminates). But the few
**irreducible host boundaries** that *catch* a host-runtime raise into a value — `Code.format_string!`,
ad-hoc compilation, file I/O, `:code.load_binary` — are exactly an effect: "this call may fault in the
host." Those are currently marked with the **interim `@rian_host` attribute** (`Rian.Ann`; excluded from
`mix rian.transpile --check` and Reach-pinned like any host call); the `host` effect is where they
attach, with an inferred set per the §3 rules. `@rian_host` stays the honest, greppable placeholder until
this lands. It is **not** a new exception mechanism.

**The catch lives in `@external`, not in Rian (settled).** Rian gets **no** catchable construct — that
would reopen ADR-0040. Instead, a host-fault boundary is an **`@external` function (ADR-0068) that
returns a `Result`**: each per-target host body performs the *native* catch (BEAM `try/rescue`, JS
`try/catch`, Rust `Result`/`catch_unwind`) and exposes `{:ok,_} | {:error,_}`; the function has no
portable Rian body. It declares `@effects(host)`, and pure Rian callers **infer** `host` up the call
graph. So the `@rian_host` boundaries become `@external` + `@effects(host)` functions — almost always
`:ex`-only, since they wrap BEAM-specific FFI — *not* portable Rian: that was a category error, these are
host boundaries by nature (a callee in Rian either returns a `Result` or `panic`s — there is no
catchable middle, so "catch a host raise" is inherently host-language code). Ergonomic cost (a host body
per target; the error branch tested host-side or via a stub `@external`) is accepted; a future
`@external`+`Result` *sugar* may reduce it but must **not** become a catch construct. Decided in the
2026-06-18 effect debate.

Because the boundary is *sanctioned* (not unfinished work), `mix rian.transpile` renders a
`@rian_host`-tagged def as its **portable happy path** under a `# @rian_host: <reason>` note — the
recovery clause lives host-side, so emitting a `TODO_PORT("… restructure to Result/Option")` for it
would falsely imply a pending port. An *un*-tagged `rescue`/`catch`/`after` still surfaces as that
marker. (`@rian_host` is not a Rian surface annotation, so the note is a comment.)

### 3. Composition mirrors error sets (ADR-0040 §4)

Effect sets compose exactly like error sets, on the same infer-local/declare-public line (ADR-0034 §1):

- **Private functions / `:=`: inferred** — effect set = the **union** of the effect sets of the
  functions they call.
- **`pub` functions: declared, verified *exact* by default** — the effect set is explicit in the
  signature and the checker verifies the declared set **equals** the body's inferred set. This **differs
  from error sets** (which allow `⊆`/over-declaration): over-declaring an effect is *never* free — it
  forfeits `comptime` (§4: only the empty set is comptime-evaluable, so a spuriously-effectful pure
  function is locked out), and for **Reach-gating effects (`host`, `spawn`)** it also forfeits Reach
  (host/spawn ⇒ off `:rs`/`:js`/`:jvm`, ADR-0057), hand-pinning a portable function off the non-BEAM
  targets — exactly the manual mis-pinning ADR-0058's inferred reachability removes. So "compose like
  error sets" governs the **inference fixpoint** (union over callees, below), *not* the over-declaration
  policy. **`host`/`spawn`: exact, no opt-out** (over-declaration is a portability lie). **Neutral
  effects (`io`/`fs`/`clock`/`random`/`net`): exact by default**, but an **explicit, documented**
  over-declaration is permitted for API forward-compatibility (reserving the right to add the effect
  without a breaking signature change), with the author accepting the `comptime` forfeit — never silent.
  Decided in the 2026-06-18 effect debate.
- **Effect polymorphism:** a higher-order function's effect set **includes the effects of its function
  parameters** (effect variables) — `Iter.each(f, xs)` is effectful **iff `f` is**. This is the direct
  analogue of error-set composition through callbacks and is essential for the stdlib (ADR-0047).

### 4. `comptime` / pure contexts require the empty effect set

This is the precise definition `comptime` (ADR-0030) and Compile-Time-by-Default (ADR-0046) needed:
**pure = empty effect set**, so `comptime` may evaluate exactly the effect-free functions. No separate
`pure` marker is required — purity is read off the effect set.

### 5. Uniform across all targets; compile-time only; erased at runtime

Effect tracking is enforced **uniformly on every target** as a **compile-time discipline** — the effect
labels are *checking metadata*, not runtime tokens. They **erase at runtime**: ambient IO is the
target's native IO (BEAM IO on BEAM, Rust IO on Rust), unchanged by the labels. No codegen change, no
runtime cost (ADR-0041/0046).

### 6. Orthogonal to memory capabilities and mutation

Effect tracking is a **separate dimension** from ADR-0025 memory capabilities (`val`/`iso`/`ref`/`tag`,
the aliasing lane) and from `<~` mutation (ADR-0039, the mutation lane). External-world effects are this
ADR's lane; aliasing and mutation keep theirs. (Under the rejected ocap model C these would have unified
as capability-values; under B they stay distinct.)

### 7. What is gained and what is foregone (the honest trade)

- **Gained — transparency:** effects are visible in signatures ("no hidden effects"); `comptime` purity
  is precise; nondeterminism (`clock`/`random`) is explicit, which still tells a reader and a test that a
  function is non-reproducible.
- **Foregone — authority/injection:** there is **no** sandboxing-by-construction and **no**
  inject-a-fake-by-capability mocking (C's benefits). Mocking nondeterministic effects uses other means
  (a test-provided implementation module, not a threaded capability). If this bites, **C is the recorded
  fallback.**

## Ratings

| Decision | Rating |
|---|---|
| Effects **tracked, ambient** (B) — visible, not authorized | 4/5 |
| Fine-grained taxonomy (`io`/`fs`/`clock`/`random`/`net`/`spawn`); pure = empty set | 4/5 |
| Composition mirrors error sets; effect polymorphism through callbacks | 5/5 |
| `comptime`/pure = empty effect set (precise purity definition) | 5/5 |
| Uniform, compile-time only, runtime-erased, native-per-target IO | 5/5 |
| Orthogonal to memory capabilities + `<~` mutation | 4/5 |
| Object-capability (C) | recorded alternative (not chosen — threading cost / family divergence) |
| Untracked (A) / full algebraic effect rows (Koka) | 1/5 (rejected) |

## Consequences

- **Closes the ADR-0047 effects/IO open item** and gives ADR-0046/0030 the purity definition (empty
  effect set).
- **Effect inference** rides the checker alongside error-set inference (ADR-0040) — same infer-local
  machinery, same `pub`-declares boundary; effect variables parallel error-set propagation through
  callbacks.
- **Stdlib (ADR-0047):** the effectful layer's functions carry effect sets; pure stdlib is the empty-set
  subset. `Iter`/`List` higher-order functions are effect-polymorphic over their function arguments.
- **No runtime cost or codegen change** — effect labels erase; this is checking only.

## Open items

- **Effect-set surface spelling** — *settled by ADR-0081:* the surface is the explicit `@effects(...)`
  row (e.g. `@effects(host)`), with **no** short keyword/sugar (not `@host`/`@foreign`/`!io`). One
  grammar production, no per-effect keyword. (The illustrative `!io` elsewhere in this ADR predates that
  decision and is not the chosen syntax.)
- **Error-path testability of `@external` boundaries** (dissent, Samir Patel) — with the catch host-side
  (§2), the `{:error,_}` branch isn't reachable from a Rian test. Mitigation: a host-level test of the
  `@external(:ex)` body plus a Rian test against a stub `@external`. Document the convention.
- **`@external`+`Result` ergonomics** (dissent, Liam Davis) — a per-target host *string* for a one-call
  catch is verbose and not type-checked by `Rian.Check`. A future terser, checked sugar is possible — but
  it must **not** become a catch construct (§2). Revisit only if the verbosity bites.
- **Taxonomy granularity** — split `io` into `stdin`/`stdout`/`stderr`? Is `spawn` one effect or
  per-concurrency-primitive? Ties to the non-BEAM concurrency gap (ADR-0031).
- **Optional cap-injection layer for tests** — can an *opt-in* capability/handle layer recover C's
  inject-a-fake mocking for `clock`/`random`/`fs` **without** making capabilities mandatory? The
  highest-value follow-up.
- **Mutation-as-effect boundary** — confirm `<~` mutation (ADR-0039) stays in the capability lane and is
  *not* folded into the effect taxonomy.
- **Effect-set composition with `with`/error propagation** — a `with` body's effect set unions its
  clause expressions' effects (same as error-set union, ADR-0040).
