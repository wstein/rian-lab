# ADR-0079 — Comprehensions: `for p <- src, filter, … do body end` as eager prelude sugar

**Status:** Accepted (direction)
**Implemented:** yes (MVP) — lexer (`for` keyword; `<-` is the existing `:bind_arrow`, ADR-0039),
`Rian.Pratt` (`parse_for` → a surface `{:comprehension, clauses, body}` node), `Core.from_expr`
desugars it to nested `List.flat_map`/`if`/`[body]` over the portable prelude (ADR-0047), so **every
emitter, the checker, and exhaustiveness consume it for free** (no new Core node, no emitter clause).
`Rian.Transpile` lowers an Elixir `for` into the surface. Verified on the BEAM
(`test/rian/beam_test.exs`) and at the parse/desugar/transpile boundaries.

**Refs:** ADR-0039 (`<-` is the generator/failable-bind arrow — this ADR is its named consumer),
ADR-0047 (portable prelude — `List.map`/`filter`/`flat_map` are the desugar target), ADR-0061 (`Fn`
closures reach `:rs`, so the desugared callbacks are portable), ADR-0057 (laziness is native-per-target
— this surface is **eager** by design), ADR-0035 (no hidden control flow — a comprehension is explicit
sugar, desugared at the Core boundary), ADR-0040 (`T | E`), ADR-0000 (honesty: the matrix matches the
emitters — a comprehension carries no blocker of its own; it is exactly as portable as the prelude ops
and the body it desugars to).

## Context

The Elixir→Rian transpiler left every `for` comprehension as a `TODO_PORT` marker — Rian had no
enumeration surface. It is the last *portable* construct missing from the surface (everything else
still blocking the compiler's own roundtrip is non-portable by design — OTP, host FFI, exceptions —
or a transpiler bug). ADR-0039 already reserved `<-` "for `with` and future `for`-comprehensions", so
the grammar was waiting for this.

## Decision

**A comprehension is eager sugar over the portable `List` prelude — not a new evaluation model.**

### Surface

```
for p <- src do body end                 # map
for p <- src, cond do body end            # map + filter
for p <- src, q <- src2 do body end       # nested (cartesian)
for p <- src, cond, q <- src2 do … end    # filters apply to the generators before them
```

* `<-` is the generator arrow (ADR-0039's `:bind_arrow`), reused verbatim.
* A `,`-separated clause is a **generator** (`p <- src`) or a **boolean filter** (any other expr).
* `do … end` delimits the body (the same block lexeme as `if`/`with`/`case`).
* The result is always a **list**. `into:` (build a string/map) and `:reduce` are **out of MVP** —
  they stay `TODO_PORT` markers (a string-building `for … into: ""` is a different, target-specific
  shape; see ADR-0057 on native-per-target).
* **MVP restriction:** a generator binds a **plain variable** (`x <- xs`), not a destructuring
  pattern. A non-variable generator LHS is a hard parse error (never silently wrong) — pattern
  generators are a documented follow-on (they need a `case`-wrapped callback).

### Desugar (in `Core.from_expr`, ADR-0050 §"emitters as pure consumers")

Right-to-left over the clause list, with the body as a singleton list at the leaf:

```
⟦ [] , body ⟧            =  [body]
⟦ (p <- src) :: rest ⟧   =  List.flat_map(src, (p) -> ⟦ rest ⟧)
⟦ (filter)    :: rest ⟧  =  if filter do ⟦ rest ⟧ else [] end
```

`flat_map` + a singleton leaf gives the uniform, correct semantics for any mix of generators and
filters (a single-generator/no-filter comprehension is `flat_map(xs, (x) -> [body])`, equivalent to
`map`). Because the desugar emits only ordinary Core nodes (`ECall`/`EDot`/`ELambda`/`EIf`/`EList`),
**no downstream pass changes** — `Rian.Check` types it through the prelude signatures, the emitters
lower it as calls, and `Rian.Reach` needs no comprehension blocker: a `for` is exactly as portable as
`List.flat_map` + the body. `Rian.Beam` already links the portable prelude, so it runs on the BEAM;
`map`/`filter`/`flat_map` reach `:rs`/`:js`/`:jvm` (ADR-0061), so a pure comprehension is portable.

## Consequences

* **One real portable surface gap closed** with zero emitter churn — the ADR-0050 thesis (a typed Core
  spine lets sugar land once) paying off again, as bitstrings/pins did not (those needed native forms).
* The transpiler stops flagging `for`; idiomatic Rian (and `compiler/*.rian`) can use comprehensions.
* **Not** a laziness or stream surface — eager, list-producing only (ADR-0057 keeps laziness
  native-per-target). `into:`/`:reduce`/pattern-generators are honest, documented follow-ons.
