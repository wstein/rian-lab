# Rian Language Specification — End-to-End Lowering (`area/1`)

**Status:** Verified — Elixir executed, Rust compiled & run · **Refs:** ADR-0024
**Owner:** Maya Lin (pipeline) · Kira Neri (toolchain) · Samir Patel (tests)
**Implementation:** `rian_lower.ex` · **Tests:** `rian_lower_test.exs` (10/10) · **Runner:** `lower_run.exs`

The first run of the *whole* pipeline as one unit: a Rian function from source to emitted
idiomatic Elixir **and** Rust, gated by exhaustiveness. Both outputs were verified by running
them — the Elixir via `Code.eval_string`, the Rust via `rustc` — and both produce identical
results.

---

## 1. The pipeline

```
type/func data → build type env (Exhaustiveness)
              → lower patterns (PatternLower)
              → EXHAUSTIVENESS GATE (Exhaustiveness.analyze)   ← refuses to emit on failure
              → parse clause bodies (Pratt, precedence-aware)
              → emit Elixir   |   emit Rust
```

Every component locked in earlier ADRs participates: the Gleam tagged-tuple encoding (types
spec), positional→labelled variant mapping (Rust struct variants), the operator table
(expressions spec), and the verified exhaustiveness checker.

---

## 2. Input and output

**Rian source:**
```
type Shape := Circle(radius f64) | Square(side f64)

fn area(Shape) f64
fn area(Circle(r)) := pi * r * r
fn area(Square(s)) := s * s
```

**Emitted Elixir** (executes; `area({:circle, 2.0}) = 12.566…`, `area({:square, 3.0}) = 9.0`):
```elixir
@type shape :: {:circle, float()} | {:square, float()}
def area({:circle, r}), do: :math.pi() * r * r
def area({:square, s}), do: s * s
```

**Emitted Rust** (compiles on rustc 1.75; same results):
```rust
#[derive(Clone, Debug, PartialEq)]
enum Shape {
    Circle { radius: f64 },
    Square { side: f64 },
}

fn area(shape: Shape) -> f64 {
    match shape {
        Shape::Circle { radius: r } => std::f64::consts::PI * r * r,
        Shape::Square { side: s } => s * s,
    }
}
```

Same source, two idiomatic lowerings: multi-`def` clauses + tagged tuples on Elixir; one `fn` +
`match` + struct-variant patterns on Rust; `pi` → `:math.pi()` vs `std::f64::consts::PI`.

---

## 3. The exhaustiveness gate (verified)

Removing the `Square` clause makes the pipeline **refuse to emit**:

```
non-exhaustive `area`: pattern `Square(_)` not covered
```

A wildcard-before-specific clause is rejected as `unreachable`. The gate is the verified
checker (ADR-0015) fed by the verified lowering pass (ADR-0022) — emission cannot proceed past
a non-total or dead-clause match.

---

## 4. Operator table lowering (verified gallery)

| Rian | Elixir | Rust |
|---|---|---|
| `a + b * c` | `a + b * c` | `a + b * c` |
| `n div 2` | `div(n, 2)` | `n / 2` |
| `a / b` | `a / b` | `(a as f64) / (b as f64)` |
| `x \|> f(y) \|> g` | `x \|> f(y) \|> g` | `g(f(x, y))` |
| `s <> t <> u` | `s <> t <> u` | `format!("{}{}{}", s, t, u)` |
| `a and not b` | `a and not b` | `a && !b` |

Pipe is native on Elixir but a **structural call-rewrite** on Rust; `<>` chains **flatten** into
one `format!`; `/` is float division (explicit `as f64` on Rust) while `div` is integer.
Emission is precedence-aware: `a + b * c` carries no redundant parens; `(a + b) * c` keeps them.

---

## 5. Verification summary

- **Elixir:** emitted module evaluated; `area/1` returns the correct values (10/10 tests, incl.
  an executed-result assertion).
- **Rust:** emitted source compiled by `rustc 1.75` with no errors and run; output matches the
  Elixir to 1e-9.
- **Gate:** non-exhaustive and unreachable inputs are refused with actionable messages.
- **Project total:** 67 host-language tests, 0 failures, across checker / lowering / precedence /
  end-to-end.

---

## 6. Open items / next
- Multi-argument functions → tuple-`match` scrutinee on Rust (single-arg done here).
- Block-bodied clauses (`do … end`) and `if`/`match` expression bodies (only `:=` expression
  bodies exercised here).
- Capability lowering: `iso`/`val` → owned/borrowed in the Rust signature (here all `val`/Copy).
- A real lexer/parser for declarations + statements, replacing the data-shaped function input.
