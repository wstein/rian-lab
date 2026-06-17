# ADR-0079 — Comprehensions: `for p <- src, filter, … do body end` as eager prelude sugar

**Status:** Accepted (direction)
**Implemented:** yes — lexer (`for` keyword; `<-` is the existing `:bind_arrow`, ADR-0039),
`Rian.Pratt` (`parse_for` → a surface `{:comprehension, clauses, body}` node; a clause is a generator
iff a top-level `<-` precedes the clause boundary), `Core.from_expr` desugars it to nested
`List.flat_map`/`if`/`case`/`[body]` over the portable prelude (ADR-0047), so **every emitter, the
checker, and exhaustiveness consume it for free** (no new Core node, no emitter clause). Generators
bind a **full pattern** (a non-match *skips* the element). `Rian.Transpile` lowers an Elixir `for` into the surface,
and desugars the Elixir-only `into:`/`reduce:` forms to portable `List.reduce` folds (see *Non-goals* —
no Rian surface for those). Verified on the BEAM (`test/rian/beam_test.exs`: map/filter/nested +
destructuring + pattern-filtering + the `into:`/`reduce:` fold shapes) and at the
parse/desugar/transpile/Reach boundaries.

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
* The Rian **surface** result is always a **list**. The Elixir `into:` (build a collection) and
  `reduce:` (fold to an accumulator) forms are **not Rian surface** — `Rian.Transpile` desugars them
  to portable prelude folds (see *Non-goals* below); they are never parsed by `Rian.Pratt`.
* A generator binds a **full pattern** (`{:mod, name, inner} <- decls`, `Ok(v) <- rs`, `[k, _] <- ps`).
  Per the Elixir comprehension contract, an element that **does not match** the pattern is *skipped*,
  not an error — implemented via a `case`-wrapped callback whose wildcard arm yields `[]`.

### Desugar (in `Core.from_expr`, ADR-0050 §"emitters as pure consumers")

Right-to-left over the clause list, with the body as a singleton list at the leaf:

```
⟦ [] , body ⟧                =  [body]
⟦ (var <- src) :: rest ⟧     =  List.flat_map(src, (var) -> ⟦ rest ⟧)
⟦ (pat <- src) :: rest ⟧     =  List.flat_map(src, (__gᵢ) -> case __gᵢ do
                                  pat -> ⟦ rest ⟧ ; _ -> [] end)     # non-match SKIPS
⟦ (filter)     :: rest ⟧     =  if filter do ⟦ rest ⟧ else [] end
```

A **plain-variable** generator always matches, so it lowers to a direct lambda binding; any other
pattern wraps the continuation in a `case` whose wildcard arm yields `[]`, dropping non-matching
elements (`__gᵢ` is index-fresh so nested pattern generators don't shadow). `flat_map` + a singleton
leaf gives the uniform, correct semantics for any mix of generators and filters (a
single-generator/no-filter comprehension is `flat_map(xs, (x) -> [body])`, equivalent to `map`).
Because the desugar emits only ordinary Core nodes (`ECall`/`EDot`/`ELambda`/`EIf`/`ECase`/`EList`),
**no downstream pass changes** — `Rian.Check` types it through the prelude signatures, the emitters
lower it as calls, and `Rian.Reach` needs no comprehension blocker: a `for` is exactly as portable as
`List.flat_map` + the body. `Rian.Beam` already links the portable prelude, so it runs on the BEAM;
`map`/`filter`/`flat_map` reach `:rs`/`:js`/`:jvm` (ADR-0061), so a pure comprehension is portable.

## Consequences

* **One real portable surface gap closed** with zero emitter churn — the ADR-0050 thesis (a typed Core
  spine lets sugar land once) paying off again, as bitstrings/pins did not (those needed native forms).
* The transpiler stops flagging `for` (incl. `lib/rian`'s destructuring `{:tag, …} <- decls` form,
  the dominant residual); idiomatic Rian (and `compiler/*.rian`) can use comprehensions.
* **Not** a laziness or stream surface — eager, list-producing only (ADR-0057 keeps laziness
  native-per-target).

## Non-goals: `into:` / `reduce:` are transpiler lowerings, not Rian surface

The Elixir `into:` and `reduce:` comprehension forms are **deliberately not** added to the Rian
grammar. There is no `into:`/`reduce:` token, no `Core` node, no parser clause. Instead
`Rian.Transpile` desugars them to the **portable `List` prelude** (the forms are already expressible —
adding surface would only import an Elixir-ism we don't want, and `reduce:`'s accumulator-clause body
is a parser hazard):

* `for clauses, into: c, do: body` → `List.reduce(<list-comprehension>, <empty c>, (e, acc) -> insert)`
  where `insert` is `acc <> e` for `into: ""` (String — portable) and `Dict.put` (via a `{k,v}` `case`)
  for `into: %{}` (Map — **`Rian.Reach` inherits the map blocker**, pinning the function off
  `:rs`/`:jvm`, because the desugar routes through the *real* prelude op — the honesty guarantee,
  ADR-0000). `into: []` is the identity (the list comprehension itself).
* `for clauses, reduce: acc do acc_pat -> e … end` → a **nested** `List.reduce` threading the
  accumulator through each generator (filters pass it through; reduce-arms apply at the leaf via a
  `case` on the accumulator).
* **Still markers** (honest, no faithful lowering): a **binary generator** `<<b <- bin>>`, an
  unrecognized `into:` target (a struct, `MapSet.new()`, a variable), or any extra option (`uniq:`).
* The `into: ""` left-fold is O(n²) on immutable strings — acceptable for a reviewed migration draft;
  a future builder/iolist prelude type is the fast path.

**Escalation path (deferred):** if a Rian author ever needs `into:` over their *own* types, the
sanctioned mechanism is a **`Collectable` protocol** (ADR-0042/0061 machinery), not a hardcoded
collection switch. No demand today; revisit when it appears.
