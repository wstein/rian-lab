# ADR-0069 — String interpolation that auto-stringifies via a portable `Show`

**Status:** Accepted · **Implemented (partial, 2026-06-14)** — the `\(expr)` surface (decision A) + auto-stringify for `Int*`/`Bool`/`String` holes, portable across all four targets. `Char`/`Float64`/user-type & derived `Show`/runtime dispatch are deferred (see *Open items* and *Implementation* below).
**Implemented:** partial — `\(expr)` lexing (`{:istr}`), Pratt (`{:str_interp}`), `Rian.Interp` static resolution, `__prim_int_to_string` on Beam/JS/Lower(Rust+Elixir)/JVM; `Int*`/`Bool`/`String` holes reach all four targets, honestly via `Rian.Reach` (an `Int` hole inherits ADR-0064's `[:ex,:js]`). `test/rian/interp_test.exs`. Deferred: `Char` (dispatch-guard collision), `Float64` (round-trip), user/derived `Show`, runtime dispatch.
**Refs:** ADR-0042 (protocols & bounded generics — the dispatch this leans on), ADR-0061 (multi-target protocol lowering — BEAM/Rust/JS dispatch, the Rust owned-return gap), ADR-0047 (portable prelude/stdlib — the `Prim.*` intrinsic layer), ADR-0051 §"Open items" (interpolation deferred for doc heredocs — "probably no"), ADR-0035 (no hidden control flow — the central tension), ADR-0033 (surface vocabulary), ADR-0064 (portable numeric contract — `Int53` is the portable integer; `Int`/wide ints are off some targets), ADR-0057/0058 (target-environment sets; reachability), ADR-0065 (P7 surface freeze — this surface is *not* frozen).
**Owners:** Maya Lin (surface / emitters) · Samir Patel (types / protocol bounds) · Kira Neri (honesty) · Mira (totality) · Tomás (BEAM performance) · Rachel Okafor (PM)

## Context

Rian has no string interpolation. A string literal is lexed straight to a flat, escape-resolved
binary (`Rian.Lexer.lex_string/2` returns `{decoded, rest}`), parsed to a single `{:str, s}` token
([pratt.ex:198](../../lib/rian/pratt.ex)), and carried in Core as `EStr{value}` with no internal
structure ([core.ex:111](../../lib/rian/core.ex)). The sanctioned way to build a string from parts is
explicit concatenation with `<>`, and turning a non-string into a string is FFI today
(`Integer.to_string(n)` — which pins the function to `:ex`, see
[09_capstone_calc.rian:51](../../examples/rian/09_capstone_calc.rian)).

That FFI dependency is the real problem this ADR addresses. "Print a number into a message" is the
single most common reason a function falls *out* of the portable core: there is no portable
`to_string`, so every formatting function is BEAM-only. We have a `Show` protocol in the tour
([13_protocols.rian:23](../../examples/rian/13_protocols.rian)) but it is a toy — not in the prelude,
not portable, its `Int64` impl literally returns `"an integer"`.

This ADR proposes the **auto-stringify** direction: interpolation accepts arbitrary values and
stringifies each hole through a real, portable `Show` protocol. (The narrower **pure-sugar**
direction — interpolation accepts only `String`, desugaring to `<>` with zero new semantics — is
recorded under *Alternatives*; it is a weekend of plumbing but solves nothing about portability.)
Auto-stringify is the larger commitment because it requires a stdlib protocol that lowers honestly to
all four targets. The interpolation *syntax* is the small part; **the load-bearing decision is
shipping a portable `Show`.**

## Decision

### 1. Surface — a spelling shootout

A hole is an expression embedded in a `"…"` literal. Scored against: **visible** (the hole is
unmissable, ADR-0035), **family-native** (ADR-0033 surface lineage), **minimal lexer delta**, **no
collision** with existing in-string syntax.

| # | Spelling | Example | Visible | Family | Lexer delta | Notes |
|---|----------|---------|---------|--------|-------------|-------|
| A | `\(expr)` | `"hi \(name), age \(age)"` | ✅ | ✅ Swift-lineage; backslash already *is* the in-string escape sigil | **smallest** — `\` already dispatches into `char_escape/1`; add one `\(` arm that hands off to the expr lexer | recommended — reuses the existing escape hatch, so `\\(` is a literal `(` for free |
| B | `${expr}` | `"hi ${name}"` | ✅ | ⚠ JS/shell, not Elixir/Gleam | new: `$` is otherwise unused, must special-case inside strings | familiar to most readers; `$` is free elsewhere in the grammar |
| C | `#{expr}` | `"hi #{name}"` | ✅ | ✅ Elixir-native | new + **adjacency hazard**: `#` is the line-comment sigil; readers must learn `#` means two things | rejected — overloading the comment sigil costs more than it buys |

**Direction (to confirm):** **A (`\(expr)`)**. It is the smallest lexer change by construction —
`\` is *already* the codepoint that diverts `lex_string/2` into escape handling, so interpolation
becomes one more escape arm rather than a new scanning mode, and `\\(` already means "literal
backslash then `(`" so the escape-the-escape story is free. B is the acceptable fallback if
familiarity wins over lineage; C is excluded for overloading the comment sigil.

A hole may contain any expression the Pratt parser accepts (it re-enters `expr_tokens`); nesting a
string inside a hole is allowed but discouraged by the formatter (ADR-0045). An empty hole `\()` is a
compile error.

### 2. Semantics — desugar to `Show.show` + `<>`

`"a \(x) b \(y)"` desugars, at the parse boundary, to the concatenation chain

```
"a " <> show(x) <> " b " <> show(y) <> ""
```

where `show` is the `Show` protocol method (ADR-0042 dispatch). A literal `String` hole still goes
through `show` — `impl Show for String` is the identity ([13_protocols.rian:37](../../examples/rian/13_protocols.rian)),
so it is a no-op the optimizer can elide. **This is sugar over existing machinery:** `<>` already
type-checks and lowers everywhere, and `show` is an ordinary bounded-generic call. No new Core node is
strictly required — the desugaring can emit `ECall`/`EStr` directly — though a thin `EStrInterp{parts}`
node is worth keeping through `Check` so error messages point at the hole, not the desugared chain.

The whole expression has type `String`. Each hole imposes a `Show` bound on its expression's type: a
hole `\(e)` type-checks iff `typeof(e)` has an `impl Show`. A type with no `Show` impl is a **compile
error at the hole** (`no impl Show for <T> — interpolation requires it`), never a silent
`inspect`-style fallback.

### 3. The portable `Show` protocol (the actual work)

Promote `Show` from tour toy to prelude protocol, with **portable impls for every primitive**, backed
by two new intrinsics in the `Prim.*` layer (ADR-0047 §2, `Rian.Prim.@prims`):

| Prim | BEAM | JS | Rust | JVM |
|------|------|----|----|-----|
| `__prim_int_to_string` | `erlang:integer_to_binary/1` | `String(n)` / `n.toString()` | `n.to_string()` | `n.toString()` |
| `__prim_float_to_string` | `io_lib_format` shortest-round-trip | `String(n)` | `format!("{}", n)`† | `n.toString()`† |

```rian
# prelude_show.rian  (sketch)
protocol Show do
  def show(self Self) String
end

impl Show for String  do def show(s) := s end
impl Show for Int53   do def show(n) := Prim.int_to_string(n) end
impl Show for Bool    do def show(b) := if b do "true" else "false" end end
impl Show for Char    do def show(c) := Str.from_chars([c]) end
# Float64 impl gated — see Open items (round-trip divergence)
```

User sum/struct types get `Show` by writing an `impl` (as `Expr` does at
[13_protocols.rian:69](../../examples/rian/13_protocols.rian)); there is **no derived/auto `Show`** in
this ADR (see Open items — derivation is the obvious follow-up but a separate decision).

### 4. Portability & Reach — honest, not aspirational

Interpolation is **as portable as the `Show` impls its holes touch**, propagated by `Rian.Reach`
exactly like any other call (ADR-0057/0058). Concretely:

- A hole whose type is **`Int53`/`Bool`/`Char`/`String`** with portable impls keeps the function in
  the `:ex/:rs/:js/:jvm` core, *provided* the two `__prim_*_to_string` intrinsics are implemented on
  all four emitters. **If an emitter lacks the intrinsic, Reach must pin the function off that target
  with a `:prim` blocker** — same honesty rule ADR-0064 applies to wide-int prims (`wide_prim_blocker`).
- A hole typed **`Int`** (arbitrary precision) inherits ADR-0064: reachable only `[:ex, :js]`, so a
  message interpolating an `Int` is off `:rs`/`:jvm` — correctly, not silently.
- **The Rust generic gap (ADR-0061 Open items) mostly does not bite here.** That gap is "a generic
  returning an *owned tvar* needs a borrow→owned clone." `show` returns a concrete `String`, not a
  `T`, and at each hole the receiver type is *known* (interpolation is monomorphic per call site), so
  Rust dispatch monomorphizes to a concrete `impl` with no owned-tvar return. The one place it *would*
  bite — interpolating a value of a still-generic `T: Show` inside a `forall T: Show` function — is
  the same pre-existing limitation, and Reach already pins those with `:generic`. **The interpolation
  feature adds no new Rust gap; it inherits the existing one.**
- **Coherence (ADR-0061 §5):** one `impl Show` per type, and on runtime-dispatch targets (`:ex`,
  `:js`) no two impls may share a dispatch guard — `Int53` and `Char` both test `is_integer` on the
  BEAM, so they **cannot both** have a guard-colliding `Show` on those targets. This is a real
  constraint the impl set above must respect (it does: `Char` shows via `Str.from_chars`, but the
  *dispatcher* still needs a discriminator — flagged in Open items, this is the sharpest hidden cost).

### 5. The ADR-0035 tension, stated plainly

Interpolation **hides a protocol dispatch and a concatenation chain** behind string syntax. That is
in tension with "what you read is what runs" (ADR-0035). The defense: the *hole markers are visible*
(you can see `\(x)` runs *something* on `x`), and the something is a single, total, value-returning
`show` — no control flow, no early return, no effect. This is unlike the error-propagation case
(ADR-0066) where the hidden thing was *control flow*; here the hidden thing is a *pure function call*,
which ADR-0035 has never objected to (every operator desugars to a call). The line we hold:
interpolation may hide a **pure `Show.show`** and nothing else — never an effectful or partial
operation, never an `inspect`-style reflective fallback for un-`Show`-able types.

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — `\(expr)` surface | 4/5 | smallest lexer delta and family-native; −1 because `${}` familiarity is a real pull and the call is close |
| 2 — desugar to `show` + `<>` | 5/5 | zero new semantics, reuses checked/lowered machinery; error-locating node is cheap |
| 3 — portable `Show` + 2 prims | 4/5 | the genuine payoff (kills the #1 portability leak); −1 for the float round-trip divergence and the four-emitter prim cost |
| 4 — Reach honesty | 5/5 | inherits existing blockers; adds only a `:prim` blocker that follows the established ADR-0064 pattern |
| 5 — ADR-0035 stance | 3/5 | defensible (pure call, visible markers) but it *is* hidden dispatch; reasonable people will push back |

## Consequences

- **The portability win is the point.** Once `Show` is portable, every "format a value into a message"
  function joins the portable core instead of being pinned to `:ex` by `Integer.to_string` FFI. This is
  a larger payoff than the syntax — the syntax is the on-ramp.
- **Drift tax (CLAUDE.md):** a (thin) `EStrInterp` node threads lexer → Pratt → Core → Check →
  Beam/Lower/JS/JVM; the two `__prim_*_to_string` intrinsics need an arm in each emitter
  (`Rian.Beam`, `Rian.JS`, `Rian.Lower`/Rust, `Rian.JVM`) plus registration in `Rian.Prim`. Missing
  one surfaces as the usual `FunctionClauseError`/`Unsupported`.
- **Formatter (ADR-0045):** must learn to format inside holes and decide a house style for nested
  interpolation (lean: forbid nesting strings in holes, suggest a `let`).
- **Surface freeze (ADR-0065 P7):** `\(…)` is explicitly *outside* the freeze until this ADR settles.
- **Detokenizer round-trip:** the lexer's re-escape path (`escape_str`/`char_source`) must round-trip
  `\(` as interpolation, not as a literal — a test the self-host lexer fixpoint (`Rian.Fixpoint`) will
  catch if missed.

## Implementation (partial, 2026-06-14)

Shipped the settled core; deferred the items this ADR itself flagged "resolve
before implementing" (the `Char`/`Int` dispatch collision) and "gate off" (`Float`):

- **Surface (decision A).** `Rian.Lexer` scans `\(expr)` as one more arm of its
  existing `\` escape dispatch, producing an `{:istr, parts}` token (literal
  segments + raw hole source); `\\(` stays a literal backslash + paren for free.
  `Rian.Pratt` re-parses each hole into a `{:str_interp, parts}` node; an empty
  hole `\()` is a parse error. The detokenizer round-trips `\(…)`.
- **Static resolution, not runtime dispatch.** Because interpolation is
  **monomorphic per call site** (§4), `Rian.Interp` resolves each hole to a plain
  `<>`/stringify chain in the declaration pass — *where the clause's parameter
  types are in scope* — by the hole's **statically inferred type**: `String` →
  identity, `Int*`/`UInt*` → `__prim_int_to_string`, `Bool` → an `if`. This is the
  key simplification: no runtime `Show` dispatcher is generated, so **the
  Char/Int53 dispatch-guard collision (the sharpest open cost) does not arise**,
  and Rust gets the monomorphic concrete `impl` for free. There is **no new Core
  node and no per-emitter `{:str_interp}` handling** — the checker and all four
  emitters see an ordinary `<>` tree.
- **The one new intrinsic.** `__prim_int_to_string` lowers natively on all four
  emitters (`erlang:integer_to_binary` / `String(n)` / `n.to_string()` /
  `.toString()`), so an `Int53`/`Bool`/`String` interpolation reaches **all four
  targets** — the portability win, replacing the `:ex`-only `Integer.to_string`
  FFI. `Rian.Reach` needs no new blocker: a hole inherits its value type's reach
  (an `Int` hole is `[:ex,:js]` per ADR-0064; a wide-int hole is off `:js`).
- **Deferred (compile errors, never silent):** a `Char` hole, a `Float64` hole,
  and a hole whose type can't be statically inferred each raise a clear error at
  the hole — no `inspect`-style fallback (ADR-0035). User-type / derived `Show`
  through the full protocol (so a sum/struct can be interpolated) is the next
  increment; until then a user-type hole is the "no `Show`" error.

## Open items

- **Confirm A (`\(expr)`) vs B (`${expr}`).** Lexer-minimalism vs familiarity; decide before any code.
- **The `Char`/`Int53` dispatch-guard collision on `:ex`/`:js` (the sharpest cost).** Both test
  `is_integer`; ADR-0061 §5 forbids guard-sharing impls on runtime-dispatch targets. Resolve before
  implementing — likely the dispatcher needs a finer discriminator (range/tag) for the numeric vs char
  split, or `Char`'s `Show` routes differently. This is the one place the design could fail to lower.
- **`Float64` round-trip divergence.** BEAM, JS `String(n)`, and Rust `format!("{}", …)` disagree on
  shortest-round-trip float formatting (`0.1`, `1.0` vs `1`, exponent thresholds). A portable `Show for
  Float64` must *specify* the format (likely shortest-round-trip, ECMAScript `Number.prototype.toString`
  as the reference) or stay off the portable core until it does. Gate it off until specified.
- **Derived `Show`.** Auto-deriving `Show` for sums/structs (field-by-field) is the obvious ergonomics
  follow-up but a separate decision — it reopens the "is the derived output a *stable contract*?"
  question and risks an `inspect`-by-the-back-door. Spike only; commit nothing here.
- **Pure-sugar fallback.** If portable `Show` proves too costly (the float/coherence items above), fall
  back to the *Alternatives* design — interpolation over `String`-typed holes only — which needs none
  of §3/§4 and ships immediately. Keep it on the table until §3 is proven.

## Alternatives considered

- **Pure-sugar, `String`-only interpolation (the other direction).** `\(e)` requires `typeof(e) ==
  String`; desugars to a bare `<>` chain with no `show`. Pros: zero new protocol, zero new prim, fully
  portable on day one, no ADR-0035 tension (it hides only `<>`, already an operator). Cons: solves
  *none* of the formatting-FFI portability problem — you still write `Int.to_string(n)` by hand, and
  that call is still `:ex`-only until a portable `Show` exists. It is a strictly smaller feature that
  postpones the real work. **Recorded as the fallback (Open items), not the recommendation.**
- **`inspect`-style reflective stringification** (stringify *anything*, no `Show` impl needed). Rejected:
  it has no portable, stable cross-target output contract, and it is exactly the "magic" ADR-0035 and
  the explicit-by-design philosophy exist to prevent. A type with no `Show` impl is an error, full stop.
- **`#{expr}` (Elixir-native).** Rejected for overloading the `#` comment sigil (shootout row C).
