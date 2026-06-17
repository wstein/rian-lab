# ADR-0033 — Surface Vocabulary: `def`, juxtaposed types, `case`/`when`, Crystal primitives

**Status:** Accepted
**Implemented:** yes — `def`/`case`…`do`/`when` guards/juxtaposed types/`:=` binding parsed in `Rian.Decl` + `Rian.Pratt` (`test/rian/decl_test.exs`)
**Refs:** ADR-0032 (surface belongs to the Elixir/Ruby/Crystal family), ADR-0029 (dot syntax), ADR-0031 (bootstrap)
**Supersedes:** the "reject `:`-typed params" debate; ADR-0032's *primitive type spelling* open item
**Owners:** Chloe Bennett (parser) · Julian Vance (grammar) · Maya Lin (emitters) · Rachel Okafor (PM)

## Context

ADR-0032 fixed the *principle* (surface follows the Elixir/Ruby/Crystal family, not the
compilation targets). This ADR fixes the *vocabulary* — the concrete keyword and primitive-name
choices — in one coordinated pass, so the surface stops being a family/Rust-Go-ML hybrid. The
governing design value, on top of "follow the family," is **reduced punctuation noise**: where the
family offers a lower-punctuation form, prefer it.

The target surface (`fn` → `def`, etc.):

```elixir
def perform_action(action Symbol) Int64
  case action do
    :start -> 1
    :stop  -> 2
    _      -> 0
  end
end

perform_action(:start)

a Int64 := 33
a <- 55
```

## Decision

| Construct | Decision | Rationale |
|---|---|---|
| **Named function** | `def name(...) Ret … end` | Ruby/Elixir/Crystal use `def`; `fn` was a Rust import that also collides with the family's `fn` = *anonymous* function. |
| **Param / return types** | **juxtaposition**, `name Type` and `) Ret` — no `:` | Lowest punctuation. The colon form (Crystal `name : Type`) was reconsidered after Crystal proved `:Symbol`/`x : Type` coexist, but **rejected for noise**: juxtaposition is justified by a Rian *value* (minimal punctuation), not borrowed from Go. |
| **Match construct** | `case x do  pat [when guard] -> body  …  _ -> body  end`; `match` retired | **Elixir** `case`/`do`/`->`. This *renames* Rian's existing `match` (types-match §5) to `case` — the construct is otherwise unchanged: `do … end`, `pattern [when guard] -> body` arms, `_` catch-all, implicit-block bodies, static exhaustiveness, first-match. Keeps `->` (consistent with Rian lambdas) and, decisively, keeps `when` free as the guard keyword. |
| **Primitive type names** | `Int64`, `Int32`, `Float64`, `Float32`, `String`, `Bool`, `Symbol` | Crystal vocabulary (PascalCase). Width-explicit is kept for cross-target precision; only the *spelling* moves from Rust's `i64` to Crystal's `Int64`. Resolves ADR-0032's open item. |
| **Binding** | `name [Type] := expr` (type optional, juxtaposed) | `:=` retained — single-assignment is a real Rian distinction from `<-`. |
| **Mutation** | `name <- expr` → **re-spelled, see ADR-0039** | The `<-` token is reassigned to the family failable-bind/generator (`with`/`for`); capability-gated mutation moves to a new spelling (semantics unchanged). Decision-lock 2026-06-12. |
| **Predicate/bang names** | an identifier may carry a single trailing `?` or `!` — `empty?`, `gate!` | The family convention (Elixir/Ruby/Crystal): `?` reads "predicate", `!` "stricter/effecting variant". `?` is otherwise unused in the grammar (zero ambiguity); a trailing `!` is part of the name only when it does not begin the `!=` operator (`a!=b` ≡ `a != b`). The codepoint survives to each target's symbol table (BEAM `empty?/1`). |
| **Keyword field labels** | a reserved keyword may label a field — `Field(type: t)`, `%{case: c}` | In label position (`word :`) the keyword cannot be a declaration, so it is unambiguously a field name. Matches Elixir (`%{type: 1}`) and avoids forcing renames of common Elixir/IR field names (`type`, `def`) on the way into Rian. Applies to named construction, map literals, and the symmetric patterns. |
| **As-patterns** | `name @ pat` binds the whole value while matching `pat` (Core `PAs`) | The capture every AST walk needs (`node @ {:bin, op, l, r}`). `@` is the operator (spaced — `@name` without a space stays the annotation lane); the binder is a plain variable. Lowers to Erlang `Name = Pat`, Elixir `pat = name`, Rust `name @ pat`. |

### Guards keep `when` — resolved by the Elixir `case` form

Choosing Elixir's `case x do pattern -> body end` (over Ruby/Crystal `case … when pattern`) means
the arm is introduced by the **pattern**, not by `when`. So `when` never appears in arm-header
position and stays available as the **guard** keyword, exactly as today:

```elixir
case t do
  JNum(n) when n == 0.0 -> "zero"
  JNum(_)               -> "number"
  _                     -> "other"
end
```

No change to guards (function clauses *or* case arms): both keep `pattern when guard`. The earlier
proposal to migrate guards to `if` is **dropped** — the construct choice dissolves the collision.

## Primitive lowering (verified-on-paper; to be re-asserted in tests)

| Rian | Elixir | Rust |
|---|---|---|
| `Int64` / `Int32` | `integer()` | `i64` / `i32` |
| `Float64` / `Float32` | `float()` | `f64` / `f32` |
| `String` | `String.t()` | `String` / `&str` (capability-driven) |
| `Bool` | `boolean()` | `bool` |
| `Symbol` | `atom()` | (target-model: enum / interned id) |

Source spelling decouples from the targets: `Int64` is *Rian's* name and **maps** to each backend,
rather than `i64` happening to match Rust/WASM. That is exactly the ADR-0032 stance.

### Numeric overflow is target-native — documented, never silent

The width-explicit integers (`Int8`…`Int128`, `UInt8`…`UInt128`) name a Rian *domain*, not a
guaranteed cross-target overflow rule. **Bare `+`/`-`/`*` use each target's native integer
semantics** (the ADR-0034 decision-lock, scoped in by ADR-0035): the BEAM and JS promote past the
declared width (bignum / `BigInt`), while Rust's `i64` panics in debug and wraps in release. This
divergence is a *documented* property of every numeric primitive, not a silent surprise — and Rian
gives two first-class ways to avoid relying on it:

- **Prefer a subrange (ADR-0036).** When a value's bound is known, put it in the type —
  `type Digit := 0..9`, `Digit.of(n) : Digit | RangeError`. The compiler proves the bound; no
  runtime overflow question arises. This is the promoted idiom.
- **Otherwise, request a deterministic rule explicitly.** For genuinely-unbounded `Int64`
  arithmetic, `Int.checked_add` (→ `Option(Int64)`, overflow in the type), `Int.saturating_add`
  (clamp), and `Int.wrapping_add` (two's-complement) give one answer on every backend
  ([prelude_int.rian](../../examples/rian/prelude_int.rian), ADR-0035, ADR-0047 §2).

`Int53` is the related ECMAScript carve-out: a native JS `number` is exact only to 2⁵³, so `Int53`
names the JS-safe integer domain (`i64` on BEAM/Rust, native `number` in JS) — choose it over
`Int64` when a value must round-trip through JavaScript without `BigInt`.

## Consequences

- **Exhaustiveness on open types.** `Symbol`, `Int64`, `String` are open universes, so a `case` on
  them can never be structurally exhaustive — it **requires** a `_ ->` catch-all arm. Only sealed
  `type` sums reach exhaustiveness by full coverage. The example's `_ -> 0` is mandatory; without
  it the `case` is a compile error under the exhaustiveness gate.
- **`match` is retired.** One construct (`case`), pattern-led arms (`pattern -> body`), `when`
  guards, `_ ->` catch-all.
- **Implementation is mostly declaration-parser-level**, which does not exist yet (ADR-0031 Stage
  0.1). So this lands in slices: (a) **emitter primitive vocabulary** (`Int64` → `i64`/`integer()`,
  etc., in the capability matrix and `prim_*` maps) is implementable and testable *now*; (b) the
  **spec + example rewrites** to `def`/`case`/`when`/`Int64` land now as the authoritative surface;
  (c) **parsing** `def`/`case`/`when`/typed bindings lands with the declaration parser. The Pratt
  *expression* parser is largely unaffected (it has `if`, not `case`/`def`).
- **Pairs with the pending ADR-0032 cleanup** (remove the Rust-imported `?`). Both are "make the
  surface match the family."

## Open items

- ~~**Atom/`Symbol` lowering** to non-atom targets (JVM/Go/JS/WASM).~~ **Resolved by
  [ADR-0041](0041-target-model.md).**
- **`<-` intra-family collision** — **resolved by ADR-0039**: `<-` is reassigned to the family
  failable-bind/generator (`with`/`for`); capability-gated mutation is re-spelled. Lands before
  comprehensions/`with`.
