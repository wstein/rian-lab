# ADR-0048 — Effect Tracking: fine-grained, inferred, ambient (not object-capability)

**Status:** Accepted (direction) · **Resolves:** the ADR-0047 effects/IO open item
**Implemented:** no — no effect-tracking module or test; `Rian.Check` infers no effects
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
`random`, `net`, `spawn`** (process creation; BEAM). **A function is pure iff its effect set is empty.**
Fine-grained (not just pure/impure) so a signature shows *which* world it touches — `clock`/`random`
mark nondeterminism explicitly, distinct from `fs`/`net`.

**Host-raise is a candidate effect — this is the principled home for recoverable host errors.**
Rian rejects catchable `try`/`catch` (ADR-0040 "Considered: capability-guarded exceptions"): the only
sanctioned exception flow is `Prim.panic` (diverging, uncatchable — not an effect, it terminates). But
the few **irreducible host boundaries** that *catch* a host-runtime raise into a value — `Code.format_string!`,
ad-hoc compilation, file I/O — are exactly an effect: "this call may fault in the host." Today those are
marked with the **interim `@rian_host` attribute** (`Rian.Ann`; excluded from `mix rian.transpile --check`
and Reach-pinned like any host call). When this effect system lands, a `host`/`fault` row is where they
would attach — a `@rian_host`-tagged function becomes one whose inferred effect set includes `host`,
composed and declared by the §3 rules. Until then, `@rian_host` is the honest, greppable placeholder; it
is **not** a new exception mechanism, just a marker for where the effect will live.

Because the boundary is *sanctioned* (not unfinished work), `mix rian.transpile` renders a
`@rian_host`-tagged def as its **portable happy path** under a `# @rian_host: <reason>` note — the
recovery clause lives host-side, so emitting a `TODO_PORT("… restructure to Result/Option")` for it
would falsely imply a pending port. An *un*-tagged `rescue`/`catch`/`after` still surfaces as that
marker. (`@rian_host` is not a Rian surface annotation, so the note is a comment.)

### 3. Composition mirrors error sets (ADR-0040 §4)

Effect sets compose exactly like error sets, on the same infer-local/declare-public line (ADR-0034 §1):

- **Private functions / `:=`: inferred** — effect set = the **union** of the effect sets of the
  functions they call.
- **`pub` functions: declared** — the effect set is explicit in the signature; the checker verifies the
  body's inferred set is **⊆** the declared set (over-declaration allowed, as for error sets).
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

- **Effect-set surface spelling** — `!io` / a `with effects` clause / an annotation; pick the concrete
  syntax against the family and the collision test (ADR-0032). (Illustrative `!io` above is not final.)
- **Taxonomy granularity** — split `io` into `stdin`/`stdout`/`stderr`? Is `spawn` one effect or
  per-concurrency-primitive? Ties to the non-BEAM concurrency gap (ADR-0031).
- **Optional cap-injection layer for tests** — can an *opt-in* capability/handle layer recover C's
  inject-a-fake mocking for `clock`/`random`/`fs` **without** making capabilities mandatory? The
  highest-value follow-up.
- **Mutation-as-effect boundary** — confirm `<~` mutation (ADR-0039) stays in the capability lane and is
  *not* folded into the effect taxonomy.
- **Effect-set composition with `with`/error propagation** — a `with` body's effect set unions its
  clause expressions' effects (same as error-set union, ADR-0040).
