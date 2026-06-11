# Rian Language Specification — Capability Lowering

**Status:** Verified — Rust matrix compiled, linearity tested · **Refs:** ADR-0025
**Owner:** Elena Rostova (Rust) · Marcus Chen (BEAM typestate) · Samir Patel (tests)
**Implementation:** `rian_capability.ex` · **Tests:** `rian_capability_test.exs` (15/15)
**Realizes:** the "reference capabilities, not lifetimes" decision (ADR-0001)

This is where the language's central idea touches codegen. A parameter's **reference
capability** drives its Rust signature (owned vs borrowed vs `&mut`) and its BEAM-side
**linearity** (use-once) guarantee. The programmer never writes a lifetime; the capability
produces the right Rust automatically.

---

## 1. Rust parameter-type matrix (compiled)

| capability | Copy prim | `str` | `Vec(T)` | nominal (`Shape`) |
|---|---|---|---|---|
| `val`  | `i64` (by value) | `&str` | `&[f64]` | `&Shape` |
| `iso`  | `i64` (move) | `String` | `Vec<f64>` | `Shape` |
| `ref`  | `&mut i64` | `&mut String` | `&mut Vec<f64>` | `&mut Shape` |
| `tag`  | `&i64` | `&String` | `&Vec<f64>` | `&Shape` |

Rationale: `val` borrows and uses the idiomatic borrowed forms (`&str` not `&String`, `&[T]`
not `&Vec<T>`), passing `Copy` primitives by value; `iso` owns/moves; `ref` is `&mut` over the
owned form. Every cell above was emitted and **compiled by rustc 1.75** as a real function
signature.

`val` is the **default** capability (read-only borrow — the common, safe case), matching Rust's
"take `&T` unless you need ownership" idiom.

---

## 2. Capability changes the emitted signature (verified)

`area` with `val Shape` (the default) lowers to a borrow — and still compiles & runs:

```rust
fn area(shape: &Shape) -> f64 {
    match shape {
        Shape::Circle { radius: r } => std::f64::consts::PI * r * r,  // r: &f64 (match ergonomics)
        Shape::Square { side: s } => s * s,
    }
}
```

The same function with `iso Shape` lowers to owned `fn area(shape: Shape) -> f64`. Both compile
and produce identical results (`12.566…`, `9`). The body is untouched — only the capability
changes the signature.

---

## 3. BEAM-side typestate: linearity (verified)

The BEAM has no borrow checker, so capabilities become a **use-once** check:

| capability | BEAM rule |
|---|---|
| `val` | freely shareable — any number of uses |
| `iso` | **at most once** along any path (use-once handle) |
| `ref` | **rejected** on the BEAM target (no process-local proof in PoC) |
| `tag` | identity only (pid/ref); shareable |

Verified behavior:
- `iso f` used once → ok; used twice (`pair(f, f)`) → `{:error, [{"f", 2}]}`.
- `ref x` used twice → error.
- `val r` used many times (`pi * r * r`) → ok — *this is why `area`'s `r * r` is legal*.
- Block form: consuming an `iso` once across bindings → ok; consuming it twice → error.
- Emitting a `ref`-parameter function to Elixir is **refused**:
  `` `ref` is not permitted on the BEAM target (no process-local proof in PoC) ``.

The checker counts variable occurrences in the expression AST and flags any `iso`/`ref`
binding used more than once. For straight-line bodies the occurrence count is the path count;
branch-aware counting (max over `if`/`match` arms) is the extension when those bodies land (§5).

---

## 4. Why this matters

This closes the loop opened in round one: rather than exposing Rust lifetimes, Rian exposes
Pony-style capabilities that lower to ownership on Rust and to a typestate guarantee on the
BEAM — the same source-level discipline catching the "use a handle after it's consumed" bug on
*both* targets, while emitting idiomatic Rust with zero lifetime annotations.

---

## 5. Open items / next
- Branch-aware linearity (max uses over `if`/`match` arms; consumed-in-all-branches = consumed once).
- Capability on **fields** flowing to ownership of bound sub-patterns (e.g. `iso` field → owned `Box`).
- Closure-capture capability → `Fn` / `FnMut` / `FnOnce` (specified in the expressions/types
  specs; not yet lowered).
- `ref` process-local escape analysis to admit safe local mutation on the BEAM.
- Lifetime elision edge cases when a `val` borrow must outlive the call (returning a borrow).
