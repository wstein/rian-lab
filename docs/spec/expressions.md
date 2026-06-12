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

- A value-position `if` **must** have `else`. An `else`-less `if` is a unit-typed effect
  statement (matches Rust's `if` typing).
- `:=` bindings are **single-assignment** and **irrefutable** (tuple/struct destructuring is
  fine; `Some(x) := opt` is refutable → compile error, use `match`). Rebinding a name is
  shadowing, not mutation. Mutation is `<~` (capability-gated; BEAM-illegal unless local).

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
| 12 | `<~` | right | mutation; yields unit |

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

## 4. Open items
- Operator-as-value sections (`(+)`) — rejected in favour of `&`-captures (above); not planned.
- `let else` for refutable bindings with an early-exit arm — deferred (use `match` for now).
- Whether `<>` generalizes beyond `str` (e.g. list concat) or stays string-only.
