# Rian Language Specification — Expressions & Operators

**Status:** Locked (PoC) · **Refs:** ADR-0016..ADR-0018 · **Owner:** Julian Vance
**Targets:** Elixir (BEAM, complete) · Rust (idiomatic, superset)

Everything in Rian is an **expression** that yields a value — `if`, `match`, and blocks
included. This matches both targets natively (Rust if/match are expressions; Elixir evaluates
everything to a value).

---

## 1. Forms

```
# block (binding sequence) — value is the last expression
fn norm(v Vec(f64)) f64
  total := v |> sum          # binding (single-assignment)
  n     := len(v)
  total / n                  # final expression = value
end

# if — value position REQUIRES else (both arms same type)
sign := if x >= 0 do "pos" else "neg" end

# else-if chains
grade :=
  if s >= 90 do "A"
  else if s >= 80 do "B"
  else "C" end

# match (see rian-spec-types-match.md)
```

- A block's value is its **final expression**. A block whose last statement is a *binding*
  (`x := e`) is a **compile error** (ADR-0035): a binding has no portable value — the BEAM
  would return its RHS, but Rust lowers `let x = e;` to a `()`-typed block, a silent
  cross-target divergence. Make the value the final line (add `x`), or use the `:= expr`
  one-liner. (ML-family rule: OCaml/Haskell/F#/Rust all require a trailing expression.)
- A value-position `if` **must** have `else` — **enforced** by `Rian.Check` (ADR-0035 §6): an
  `if` whose value is used (return / binding RHS / argument / a branch feeding a used value) is a
  compile error without `else`. An `else`-less `if` is legal only as a unit-typed effect statement
  — a non-final statement of a block whose value is discarded (matches Rust's `if` typing).
- `:=` bindings are **single-assignment** and **irrefutable** (tuple/struct destructuring is
  fine; `Some(x) := opt` is refutable → compile error, use `match`). Rebinding a name is
  shadowing, not mutation. Mutation is `<~` (capability-gated; BEAM-illegal unless local).
- A binding may carry a **declared type** between the name and `:=` — `x Int32 := 66`,
  `xs Vec(Int64) := [1, 2, 3]`. A numeric literal *adopts* the annotation (`x : Int32`); any other
  value (including a parametric one like `Vec(Int64)`) must *unify exactly* with it
  (`x Int32 := someInt64` and `xs Vec(Bool) := [1, 2, 3]` are type errors — no implicit narrow/widen).
  The binding then carries its declared type downstream. See ADR-0034 §1.

---

## 2. Operator precedence (tightest → loosest)

| Lvl | Operators | Assoc | Notes |
|---|---|---|---|
| 1 | `f(…)` · `.field` / `.path` | left | call · `.` — the universal qualifier (field, module path, variant) |
| 2 | unary `-`, `not` | — | |
| 3 | `*` `/` `rem` `div` | left | `/` = float div; `div` = integer div |
| 4 | `+` `-` | left | |
| 5 | `<>` | right | string/binary concat |
| 6 | `in` | non-assoc | membership (mostly in guards) |
| 7 | `\|>` | left | pipe — threads value as first argument |
| 8 | `<` `<=` `>` `>=` | **non-assoc** | `a < b < c` is a syntax error |
| 9 | `==` `!=` | **non-assoc** | |
| 10 | `and` | left | short-circuit, boolean operands |
| 11 | `or` | left | short-circuit |
| 12 | `<~` | right | mutation; yields unit — statement-only, rejected in value position (ADR-0035 §6) |

Worked consequences: `a + b \|> f` = `(a + b) \|> f`; `x \|> f < y` = `(x \|> f) < y`;
`not a and b` = `(not a) and b`; `x <~ a or b` = `x <~ (a or b)`.

Parsed with precedence climbing (Pratt). `.` accesses fields only — there is **no method-call
syntax** (`x.f(a)`); call via `f(x, a)` or `x |> f(a)`.

---

## 3. Operator & form lowering

| Rian | Elixir | Rust |
|---|---|---|
| `a \|> f(b)` | `a \|> f(b)` | `f(a, b)` |
| `a <> b` (str) | `a <> b` | `format!("{}{}", a, b)` |
| `a / b` | `a / b` (float) | `(a as f64) / (b as f64)` |
| `a div b` | `div(a, b)` | `a / b` (int) |
| `a rem b` | `rem(a, b)` | `a % b` |
| `and` / `or` / `not` | `and` / `or` / `not` | `&&` / `\|\|` / `!` |
| `==` `!=` `<` … | same | same (derived `PartialEq`/`PartialOrd`) |
| `if c do a else b end` | `if c, do: a, else: b` | `if c { a } else { b }` |
| `name := e` | `name = e` | `let name = e;` |
| `name T := e` | `name = e` (type erased) | `let name: T = e;` |
| `{a, b} := p` | `{a, b} = p` | `let (a, b) = p;` |
| `total <~ e` | (local rewrite / error) | `total = e;` (on a `mut` binding) |
| block (last expr is value) | `do … end` body | `{ …; final }` |

`/` always producing float and `div` for integer division mirrors Elixir exactly and removes
the "is `/` integer or float?" ambiguity; the Rust lowering makes the promotion explicit.

### Numeric literals

| Rian | Kind | Elixir | Rust |
|---|---|---|---|
| `42`, `1_000` | integer (`_` digit separators) | same | same |
| `3.14`, `1_000.5` | float | same | same |
| `2.5e-3` | float with exponent | same | same |
| `1e9` | exponent, no point | `1.0e9` | `1.0e9` |

`_` separators are accepted in integers and floats. An exponent written without a decimal point
(`1e9`) is **not** valid Elixir, so the lexer normalizes it to `1.0e9` — valid on both targets —
keeping the literal's value while staying idiomatic. Floats also flow through the `comptime`
sandbox (`comptime(3.14 * 2)` ⇒ `6.28`); `div`/`rem` there remain integer-only.

### String & char literals — escapes

A `"…"` `String` and a `'…'` `Char` (ADR-0036) share **one** escape vocabulary — the full Elixir
set, which is a strict superset of Gleam's. An unescaped `"` ends a string and an unescaped `'`
ends a char; everything else is a literal codepoint unless introduced by `\`.

| Escape | Codepoint | Meaning |
|---|---|---|
| `\a` | `0x07` | alert / bell |
| `\b` | `0x08` | backspace |
| `\d` | `0x7F` | delete |
| `\e` | `0x1B` | escape |
| `\f` | `0x0C` | form feed |
| `\n` | `0x0A` | newline |
| `\r` | `0x0D` | carriage return |
| `\s` | `0x20` | space |
| `\t` | `0x09` | tab |
| `\v` | `0x0B` | vertical tab |
| `\0` | `0x00` | null |
| `\\` `\'` `\"` | — | literal backslash / quote |
| `\xH`, `\xHH` | 1–2 hex | codepoint by hex (Elixir byte escape) |
| `\uHHHH` | 4 hex | Unicode codepoint |
| `\u{HEX}` | 1–6 hex | Unicode codepoint (braced; the only Gleam form) |

A codepoint must be a Unicode scalar value — surrogates (`\u{D800}`–`\u{DFFF}`) and anything above
`\u{10FFFF}` are lex errors, as is a numeric escape with no/too-few hex digits. The same value
re-renders re-lexably on detokenization (`Rian.Lexer.detokenize/2`): the common escapes round-trip
by name and any other control codepoint falls back to `\u{HEX}`.

Each emitter re-escapes the **decoded value** into a literal valid for its target, so an embedded
quote, newline, or control codepoint is never mis-emitted: `Rian.Lower` (Elixir + Rust) and
`Rian.JS` use `\\ \" \n \r \t` plus a `\u{HEX}`/`\uHHHH` control fallback; `Rian.JVM` (Kotlin)
additionally escapes `$` (string templates) and uses fixed four-digit `\uHHHH`. `Rian.Beam` builds
the BEAM binary from the raw bytes directly, so it needs no textual escaping.

### Atom literals — `Symbol`

An **atom** (type `Symbol`, ADR-0041) is written `:name` for a bare identifier (`:ok`, `:error`,
`:Foo`) or in **quoted** form `:"…"` for any other name — operators (`:"+"`), reserved keywords
(`:"if"`), or names with non-identifier characters. The quoted form reuses the string-escape
vocabulary above and accepts an empty atom (`:""`); an *interpolated* `:"${e}"` is not a literal and
is a parse error. Both forms also appear in pattern position (`case t do :"+" -> … end`).

A `Symbol` is **equality-only** — there is no portable ordering (atom term-order is BEAM-specific,
ADR-0041 §1). It lowers per target: a native interned atom on the BEAM, a string elsewhere (Rust
`&'static str`, JS string, JVM interned `String`). To build an atom from a **runtime** string, use
the BEAM-only intrinsic `Prim.str_to_atom` (ADR-0047) — `Rian.Reach` pins a caller to `:ex`.

### `&` — function captures

A prefix `&` builds a function value, in the BEAM-consonant style (not Haskell operator sections):

| Rian | Elixir | Rust |
|---|---|---|
| `&(&1 + &2)` | `&(&1 + &2)` | `\|a1, a2\| a1 + a2` |
| `&abs/1` | `&abs/1` | `\|a0\| abs(a0)` |
| `&String.upcase/1` | `&String.upcase/1` | `\|a0\| string::upcase(a0)` |

- **`&( … )`** is an anonymous capture whose `&N` placeholders are the parameters; the highest
  index sets the arity. Elixir has this syntax natively; Rust gets an explicit closure `|a1, …|`.
- **`&name/arity`** (bare, dotted, or atom-headed path) captures a named function. Elixir is
  native; Rust forwards through a closure.

Operator **sections** (`(+)`, `(+ 1)`) are deliberately **not** added — `&(&1 + &2)` covers the
need without making `(` tri-ambiguous (group vs. lambda vs. section).

---

## 4. Spec by example (executed)

The fence below is **run as a doctest** (ADR-0060 tier B, `Rian.Doctest`): each
`expr #=> expected` is compiled and evaluated on every build, so these claims
cannot drift from the implementation.

```rian
@doc """
Operator precedence — `*` and `/` bind tighter than `+`/`-` (§2).

    precedence()  #=> 14
    mixed()       #=> 7
"""
def precedence() Int64 := 2 + 3 * 4
def mixed() Int64 := 1 + 12 / 2

@doc """
`if` is an expression; both arms yield a value, and comparisons are `Bool` (§1).

    sign(5)       #=> 1
    sign(0 - 3)   #=> 0 - 1
    sign(0)       #=> 1
"""
def sign(n Int64) Int64 := if n >= 0 do 1 else 0 - 1 end
```

## 5. Open items
- Operator-as-value sections (`(+)`) — rejected in favour of `&`-captures (above); not planned.
- `let else` for refutable bindings with an early-exit arm — deferred (use `match` for now).
- Whether `<>` generalizes beyond `str` (e.g. list concat) or stays string-only.
