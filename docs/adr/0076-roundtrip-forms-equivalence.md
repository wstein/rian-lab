# ADR-0076 — Elixir→Rian→Elixir roundtrip: forms-level equivalence, two BEAM paths

**Status:** Accepted
**Implemented:** yes — `Rian.Roundtrip` (the dashboard), `Rian.FormsEquiv` (the equivalence oracle), driven by `mix rian.roundtrip FILE|DIR`; `Rian.Transpile` produces the Rian draft, `Rian.Beam`/`Rian.Lower` are the two BEAM backends
**Refs:** ADR-0026 (ecosystem — why source emit is not shippable), ADR-0031 (the two BEAM backends: abstract forms vs Elixir source), ADR-0063 (the *self-host* `v1==v2` fixed point — a distinct fixed point), ADR-0075 (transpiler type inference)
**Owners:** Maya Lin (architecture) · Samir Patel (rigor) · Arthur Pendelton (compilers)

## Context

Rian must let teams **migrate existing Elixir** into Rian incrementally (ADR-0026). That raises a
verification question with no obvious answer: when we transpile `foo.ex` to `foo.rian` and compile
it back, how do we know the result still *means the same thing*?

The tempting bar — **byte-identical `.beam`** — is unreachable between two different frontends, and
not because of a bug we could fix. The Elixir compiler injects `__info__/1`, `ExCk`/`Docs`/`LitT`
chunks, its own atom ordering, `Dbgi`/`CInf` encodings, and makes independent codegen choices that a
from-scratch Rian backend will not reproduce. Chasing byte-identity would mean reverse-engineering
Elixir's compiler, not validating a translation.

Separately, there are **two** ways a Rian draft reaches the BEAM (ADR-0031): `Rian.Beam` (Erlang
abstract forms → `:compile.forms`, the canonical path) and `Rian.Lower`'s Elixir-source emitter fed
back through `elixirc`. A migration story should exercise both — if they disagree, one is wrong.

> **Not the self-host fixed point.** ADR-0063's `v1==v2` is *the Rian compiler compiling itself*.
> This ADR is *arbitrary Elixir round-tripping through Rian*. Different inputs, different oracle —
> do not conflate them.

## Decision

**Verify the roundtrip at the level of normalized Erlang abstract function forms, not bytes; and
require the two BEAM backends to agree at that same level.**

### The equivalence bar (`Rian.FormsEquiv`)

Two modules are equivalent iff their **sorted, normalized abstract function forms are equal**.
`normalize/1` quotients out exactly three classes of difference that provably do not change meaning;
everything else is compared verbatim.

1. **Annotations** — line/column metadata is zeroed everywhere.
2. **Variable names** — alpha-renamed to `:V1`, `:V2`, … in order of first appearance, fresh per
   function (Elixir's `:_x@1` vs Rian's `:X` carry no meaning).
3. **Provably-safe lowering choices** — a *whitelist* of semantics-preserving rewrites, currently:
   - a `case` over exactly the two guardless literal clauses `true`/`false` is canonicalized to
     `true`-first (Elixir lowers `if` to `[false, true]`, Rian to `[true, false]`; the clauses are
     mutually exclusive and exhaustive, so order is meaningless here — and *only* here);
   - a negated numeric literal (`-1` as unary-minus-on-`1` vs the folded `{:integer, -1}`) is folded
     (BEAM integers are bignums, float negation is exact — same constant).

The whitelist is the load-bearing discipline: it **never** blindly sorts `case` clauses (order is
first-match-wins in general), drops guards, or hides a difference that could change behaviour. A
construct where Elixir and Rian make *different but equivalent* lowering choices with **no
whitelisted rewrite** honestly reports as **not equivalent** — a TODO for a future, justified rule,
never papered over. Equivalence means "equal modulo a justified quotient", never "close enough".

### The dashboard (`Rian.Roundtrip`)

```
foo.ex ──Transpile──▶ foo.rian ─┬─ Rian.Beam ───────────▶ BEAM   (path 2)
                                 └─ Rian.Lower(Elixir) ──▶ foo.ex′ ─▶ BEAM (path 3)
```

`run/1` reports five honest stages over one Elixir source (forms from *all* clauses are merged, so
nothing is silently dropped):

| Stage | Question |
|---|---|
| `beam_direct` | does the draft compile through `Rian.Beam`? |
| `elixir` | does it re-render to Elixir source (`Rian.Lower`)? |
| `beam_via_elixir` | does that Elixir source compile? |
| `equiv_two_paths` | do the two BEAM backends agree (forms-equivalent)? |
| `equiv_vs_origin` | does the roundtripped module match the *original* Elixir, at forms level? |

An unresolved-port draft (a `TODO_PORT("…")` marker the transpiler emits for what it could not yet
lower) fails the BEAM stages by design — it must not be reported as a finished port (the marker scan
is deliberately fail-safe; see `Rian.Roundtrip.marker?/1`).

## Consequences

- The migration track has a published, honest oracle: "equal modulo a justified quotient." Adding a
  new safe-rewrite is a deliberate act with a written justification, reviewable against this ADR.
- `Rian.Lower`'s Elixir-source emitter earns a permanent role as the **second verification backend**
  (`equiv_two_paths`), even though it is not a shippable target (ADR-0026/0031).
- Byte-identical `.beam` is explicitly **out of scope** for the transpile roundtrip (it remains the
  bar only for the *self-host* `v1==v2` under `:deterministic`, ADR-0063 — same compiler both sides).
- A construct with no whitelisted rewrite surfaces as "not equivalent", flagging real translation
  gaps instead of hiding them.

## Open items

- **Grow the safe-rewrite whitelist** as new equivalent-but-divergent lowerings are found, each with
  a recorded justification (never a blind sort/drop).
- **`equiv_vs_origin` coverage** widens as `Rian.Transpile` lowers more Elixir (fewer `TODO_PORT`
  drafts); the dashboard measures the marching boundary.
