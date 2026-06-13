# ADR-0036 — Range (Subrange) Types: finite ordinal subtypes over `Int64` / `Char`

**Status:** Accepted (direction) · **Refines:** ADR-0033 (surface vocabulary — adds `Char` and the `range` keyword), the exhaustiveness spec §4 ("no integer-range machinery")
**Refs:** ADR-0032 (Elixir/Ruby/Crystal family), ADR-0034 (type-system foundations), ADR-0035 (errors are values; no hidden control flow)
**Owners:** Arthur Pendelton (exhaustiveness algorithm) · Maya Lin (emitters) · Chloe Bennett (parser) · Samir Patel (exhaustiveness tests) · Rachel Okafor (PM)

## Context

A request to add **Pascal-style subrange types** —

```pascal
type
  Digit  = 0..9;
  Letter = 'A'..'Z';
```

The *concept* (a bounded ordinal subtype) is wanted; the *spelling* is Pascal and conflicts with
three accepted decisions: ADR-0032/0033 put Rian in the Elixir/Ruby/Crystal family with `:=` (not
`=`), no `;` terminators, no grouped `type` block, and a fixed PascalCase primitive set that
contains **no `Char`** (`'A'..'Z'` has no base type to range over).

Two further tensions had to be resolved, not papered over:

1. **The exhaustiveness spec §4 locks "No integer-range machinery"** — ranges were decided to be
   *guards* (`when x in 1..10`), never patterns, because the base primitives (`Int64`, …) are
   *infinite* universes. A subrange *type*, by contrast, has a **closed, finite** value set. These
   are not the same claim, and this ADR draws the line between them.
2. **Semantics fork.** `0..9`-as-a-type can mean a *refinement* over `Int64` (rep stays `Int64`,
   bounds are a predicate) or a *finite ordinal set* (a closed type the gate can fully cover). This
   ADR takes the **finite-ordinal-set** reading — the Pascal-faithful one, and the one that earns
   its keep against Rian's exhaustiveness gate.

## Decision

Introduce a fourth type-declaration keyword, `range`, for **finite ordinal subrange types**.

| Construct | Decision | Rationale |
|---|---|---|
| **Declaration** | `range Name := lo..hi` | Family idiom: own keyword (like `type`/`struct`/`alias`), `:=` body, newline-delimited. **Not** Pascal's grouped `type … = … ;`. |
| **Base types** | `Int64` and `Char` only | The two *ordinal* primitives. `Float64` is excluded (not discretely enumerable); `String`/`Symbol`/`Bool` are not ordinal intervals. |
| **`Char` primitive** | added to ADR-0033's set; literal `'A'` (single quotes, Crystal-style) | Required for `'A'..'Z'`. Crystal vocabulary already governs the primitive names (ADR-0033); `Char` is the missing ordinal member. |
| **Semantics** | a **distinct, sealed, finite** ordinal type — *not* a transparent `alias` | `alias` is interchangeable with its base (no cost, no constraint). A range is a separate type with a bounds invariant; assigning an out-of-range value is an error, not a coercion. |
| **Bounds** | `lo`/`hi` are **inclusive** compile-time constant ordinals; `lo <= hi` | Inclusive matches Pascal and reads as the value set. Empty/inverted ranges are a compile error. |
| **Construction** | literal → checked at compile time; dynamic → yields the ADR-0035 error set `Name \| RangeError` | No hidden panic/exception (ADR-0035). A literal `d Digit := 7` is statically in-bounds; `Digit.of(n)` on a runtime `Int64` returns a value-or-error. |

### `range` is a sealed finite type — so the exhaustiveness gate covers it

This is the load-bearing decision and the deliberate **refinement of exhaustiveness spec §4**.

§4's "no range machinery" stands **unchanged for the base primitives**: a `case` over a bare
`Int64`/`Char`/`String` still sees an *infinite* signature and still requires `_`. What changes is
narrow: a `range` *type* registers a **finite signature** — its members *are* its constructors,
exactly the `{:lit, value}` 0-arity constructors the engine ([exhaustiveness.ex](../../lib/rian/exhaustiveness.ex))
already models. Covering the full interval is therefore structurally exhaustive, with **no `_`**:

```elixir
range Bit := 0..1

def flip(Bit) Bit
def flip(b)
  case b do
    0 -> 1
    1 -> 0          # total — 0 and 1 exhaust Bit; a `_` arm would be UNREACHABLE
  end
end
```

Contrast a `case` over `Int64`, where `0` and `1` leave the witness `_` and the gate refuses to
emit without a catch-all. The distinction is **finite vs infinite signature**, which the engine
already branches on — not new "range pattern" syntax. **Range patterns in `case` arms remain out of
scope** (ADR-0032/03-clauses): you match a `Digit` by its literal members or `_`, exactly as today.

#### Completeness checking, bounded

The reference implementation (`add_range/4`) **enumerates** the interval's `{:lit, v}` members and
reuses the existing finite-signature subset check — correct, and ample for the small ordinal ranges
Rian targets (`Digit`, `Letter`, a byte). For very large intervals (`0..1_000_000`) the planned
refinement is **endpoint/interval coverage**: fold the arms' literals (and any `_`) into covered
sub-intervals and compare against `[lo, hi]`. That is the *one* piece of "range arithmetic" §4
wanted to avoid — admitted **only for `range` types**, where it is finite and decidable, never for
open primitives. It is a performance optimization, not a correctness gap, and is tracked in the
exhaustiveness spec §7.

## Lowering (implemented — `test/rian/range_test.exs`)

| Rian | Elixir | Rust |
|---|---|---|
| `range Digit := 0..9` | `@type digit :: 0..9` (native typespec range) | base `i64` + checked ctor `Digit::of(i64) -> Result<i64, RangeError>` |
| `range Letter := 'A'..'Z'` | `@type letter :: ?A..?Z` (codepoint integers) | base `char` + checked ctor |
| `Char` literal `'A'` | `?A` (= integer `65`) | `'A'` (`char`) |
| out-of-range construction | `{:error, :range}` / error tuple | `Err(RangeError)` |

**Representation, not newtype.** A range value lowers to its **base primitive** (`i64` / `char` /
codepoint integer), with bounds enforced at construction boundaries — not a wrapper struct. This
keeps pattern-matching and arithmetic friction-free on both targets and matches the finite-ordinal
model (the value *is* the ordinal). The bounds invariant lives at the type boundary, à la the
capability story: same source, two idiomatic shapes.

**Per-target exhaustiveness shim.** Rian decides totality at the Rian level (finite signature). When
emitting **Rust**, where the base `i64`/`char` is open to *its* checker, a totally-covered Rian
`case` emits an `unreachable!()` (or the residual range arm) so `rustc` is satisfied — the same
"insert the arm the target needs" move ADR-0033/03-clauses already uses for guards. **Elixir** leans
on the `@type` spec and first-match clauses; no shim needed.

## Consequences

- **Fourth declaration keyword.** Parser (ADR-0031 Stage 0.1) gains `range Name := lo..hi`. The
  expression lexer gains `Char` literals (`'…'`) and the `..` ordinal-range form in *type* position.
- **ADR-0033 amended:** primitive set becomes `Int64 Int32 Float64 Float32 String Bool Symbol Char`.
- **Exhaustiveness spec §4 refined, not reversed:** finite `range` signatures are coverable; open
  primitives are still infinite and still need `_`. One engine, one new finite-signature source.
- **ADR-0035 honored:** dynamic construction is total and explicit (`Name | RangeError`); no panic
  on the Rian surface. Only the emitted-Rust `unreachable!()` shim can trap, and only on a value the
  type system already proved impossible.
- **Lands in slices** (like ADR-0033): (a) emitter range/`Char` lowering + the finite-signature path
  in `Exhaustiveness` are implementable and testable now against hand-built IR; (b) spec + example
  rewrites land now as authoritative surface (this ADR + [02_types_match.rian](../../examples/rian/02_types_match.rian));
  (c) **`range` parsing + the finite-exhaustiveness path are done** — `range Name := lo..hi` over
  `Int64`/`Char` parses to an `IR.Range`, registers a finite signature (`Exhaustiveness.add_range`),
  and its name substitutes to its ordinal base in every type position. A multi-clause function whose
  heads cover the interval is **total without a catch-all**; an extra `_` clause is flagged
  *unreachable*; the Rust `match` over the open base gets the `unreachable!()` shim. **The `Char`
  literal *and* the distinct `Char` type are done** too — see the implementation note under Open
  items. **Still future:** dynamic construction (`Name.of` → `Name | RangeError`) and the
  large-range interval-coverage optimization.
- **`range` is a bounded, finite opaque type** ([ADR-0043](0043-opaque-types.md)). This ADR's
  "representation, not newtype" mechanism *is* opacity; `range` adds a bounds invariant (fallible
  `T.of`) and a finite signature (exhaustiveness) on top of `opaque T := Base`. No rewrite here —
  ADR-0043 is the general mechanism, `range` the constrained special case.
- **Subrange types are the promoted overflow-safety idiom** (decision-lock 2026-06-12). Per the
  ADR-0035 scope clarification (native-per-target integer semantics), bounding a quantity with a
  `range` type — checked construction, `Name | RangeError`, no panic — is *the* in-domain-by-
  construction tool. "We promote Pascal types" is the overflow strategy, not a stylistic preference.
- **`unreachable!()` is the sole sanctioned trap.** The Rust exhaustiveness shim emits
  `unreachable!()` — **never** `unreachable_unchecked()` (soundness over a micro-optimization) — on a
  value the Rian gate proved impossible. It is documented as the *only* `panic!` Rian emits; a
  property test must assert the arm is never reached (Samir).

## Open items

- ~~**`Char` literal vs Elixir charlist.**~~ **Resolved 2026-06-12:** `'…'` delimits **exactly one
  `Char`** (Crystal); a multi-codepoint single-quoted literal (`'AB'`) is a **lex error** (use a
  `"…"` `String`) — Rian has **no charlists**. Escapes `'\n'`, `'\''`, `'\\'`, `'\u{1F600}'`.
- **Implementation note (`Char` type lands — native per target).** The `Char` literal **and the
  distinct `Char` type** are implemented. `Rian.Lexer` scans `'…'` (the escapes above, single
  codepoint enforced); `Rian.Pratt` parses it to a distinct `{:char, cp}` expression / `{:char_lit,
  cp}` pattern node (`Rian.Core.EChar` / `PChar`), and the checker types it **`Char`** — distinct
  from `Int64`. Lowering is **native per target** (decision-lock 2026-06-13): a codepoint integer on
  the BEAM (charlists are integer lists) and a **BigInt** codepoint in JS, but a native **`char`** on
  Rust (`__prim_str_chars : Vec(Char)` → `Vec<char>`; `Rian.Capability` lowers `Char` → `char`, a
  `Copy` scalar). Ordinal comparison (`==`, `<`, `>=`) works directly on every target (Rust `char`
  is `Ord`+`Eq`). **Arithmetic does not widen implicitly** (ADR-0035 — no hidden coercion): use
  `__prim_char_code(c) : Int64` for the explicit `Char` → codepoint conversion (identity on BEAM/JS,
  `char as i64` on Rust). The self-hosting lexer now reads `lex(cs Vec(Char))` with `when c == '+'`
  / `['(' | rest]` and `acc * 10 + __prim_char_code(c) - __prim_char_code('0')`, lowering and running
  on all three targets. **Still future:** `range` *construction* over `Char` (`'A'..'Z'`) — the
  ordinal-base machinery (ADR-0036 above) builds on this `Char` type.
- ~~**Range arithmetic & coercion.**~~ **Resolved 2026-06-12: arithmetic widens to base.**
  `Digit + Digit : Int64` — *not* `Digit`, because `9 + 9 = 18 ∉ 0..9`; any in-bounds wrap or hidden
  `RangeError` on `+` would be hidden control flow (ADR-0035). Re-narrow explicitly with `Digit.of(18)`
  (fallible → `Digit | RangeError`). `range` auto-derives `Comparable` (ordinal comparison stays
  in-type, returns `Bool`, no widening). This is the principled exception to ADR-0043 §3 ("opaque
  types auto-inherit nothing"): a **general `opaque` gets no `+`** (adding `UserId`s is nonsense), but
  a **`range` is a *numeric/ordinal* opaque**, so it exposes base arithmetic — widening to the base,
  which honestly escapes the bounded representation rather than leaking it.
- **Large-range completeness cap.** Fix the naive-enumeration threshold and the interval-coverage
  fallback in the exhaustiveness reference implementation.
- **Non-zero / non-contiguous bases.** This ADR covers contiguous inclusive intervals only;
  enumerated/set ordinal types (Pascal enums) are a separate future decision.
