# ADR-0033 — Surface Vocabulary: `def`, juxtaposed types, `case`/`when`, Crystal primitives

**Status:** Accepted (core) · one sub-decision flagged **To confirm** (guard keyword)
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

```
def perform_action(action Symbol) Int64
  case action
  when :start
    1
  when :stop
    2
  else
    0
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
| **Match construct** | `case x` … `when …` … `else …` … `end`; `match` retired | Ruby/Crystal `case`/`when`; drops the Rust word `match` *and* the Elixir `->` arrows (noise). Arm bodies are implicit blocks ending at the next `when`/`else`/`end` (already Rian's arm-body rule, types-match §5). |
| **Primitive type names** | `Int64`, `Int32`, `Float64`, `Float32`, `String`, `Bool`, `Symbol` | Crystal vocabulary (PascalCase). Width-explicit is kept for cross-target precision; only the *spelling* moves from Rust's `i64` to Crystal's `Int64`. Resolves ADR-0032's open item. |
| **Binding** | `name [Type] := expr` (type optional, juxtaposed) | `:=` retained — single-assignment is a real Rian distinction from `<-`. |
| **Mutation** | `name <- expr` | Retained — capability-gated mutation (expressions spec). |

### Guard keyword — **to confirm**

`when` now introduces a `case` arm, but Rian guards also spell `when` (`def max2(a, b) when a >= b`).
`case x … when Pat when guard …` is a collision. Resolution options:

1. **Guards become `if` everywhere** (recommended). `when` is purely the arm introducer; guards on
   both function clauses and case arms use the Ruby/Crystal `if` modifier:
   `def max2(a, b) if a >= b := a`, and `when JNum(n) if n == 0.0`. Internally consistent, fully
   family (Ruby/Crystal use `if`/`unless` modifiers, not `when`-guards), one keyword per job.
2. Keep `when` for function-clause guards; case-arm guards use `if`. Rejected — two guard spellings.
3. Drop per-arm guards in `case`. Rejected — a real expressiveness loss (guarded arms exist today,
   e.g. `JNum(n) when n == 0.0`).

**Recommendation: option 1.** This is the only sub-decision not directly fixed by the snippet, so
it is flagged for explicit confirmation before implementation.

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

## Consequences

- **Exhaustiveness on open types.** `Symbol`, `Int64`, `String` are open universes, so a `case` on
  them can never be structurally exhaustive — it **requires** an `else` (or `_`) arm. Only sealed
  `type` sums reach exhaustiveness by full coverage. The snippet's `case action` therefore needs
  the `else` shown above; the original two-arm form would be a compile error under the
  exhaustiveness gate.
- **`match` is retired.** One construct (`case`), one arm keyword (`when`), one fallback (`else`).
- **Implementation is mostly declaration-parser-level**, which does not exist yet (ADR-0031 Stage
  0.1). So this lands in slices: (a) **emitter primitive vocabulary** (`Int64` → `i64`/`integer()`,
  etc., in the capability matrix and `prim_*` maps) is implementable and testable *now*; (b) the
  **spec + example rewrites** to `def`/`case`/`when`/`Int64` land now as the authoritative surface;
  (c) **parsing** `def`/`case`/`when`/typed bindings lands with the declaration parser. The Pratt
  *expression* parser is largely unaffected (it has `if`, not `case`/`def`).
- **Pairs with the pending ADR-0032 cleanup** (remove the Rust-imported `?`). Both are "make the
  surface match the family."

## Open items

- **Confirm the guard keyword** (option 1: guards → `if`).
- **Atom/`Symbol` lowering** to non-atom targets (JVM/Go/JS/WASM) — target-model ADR.
- **`<-` intra-family collision** (Elixir generators/`with`) — unchanged from ADR-0032; resolve
  before comprehensions/`with` land.
- **`else` vs `_`** as the case fallback spelling — `else` (Ruby/Crystal) chosen here; confirm `_`
  is still accepted in nested patterns.
