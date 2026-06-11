# Rian Language Specification — Self-Hosting Features (Verified)

**Status:** Verified — BEAM executed, Rust compiled · **Refs:** ADR-0028
**Owner:** Chloe Bennett (parser) · Maya Lin (emitters) · Samir Patel (tests)
**Closes:** the three critical-path items from ADR-0027 (fast track to self-hosting)
**Implementation:** `rian_pratt.ex`, `rian_lower.ex` · **Tests:** `rian_features_test.exs` (10/10)

ADR-0027 identified exactly three language features standing between us and a self-hostable
subset. All three are now built into the parser and both emitters, executed on the BEAM, and
(where applicable) compiled by `rustc`.

---

## 1. Lambdas

Parsed `(x) -> e`, `(x, y) -> e` (lambda-vs-grouping disambiguated by scanning for `->` after
the matching `)`).

| Rian | Elixir | Rust |
|---|---|---|
| `(x) -> x * 2` | `fn x -> x * 2 end` | `\|x\| x * 2` |
| `(x, acc) -> x + acc` | `fn x, acc -> x + acc end` | `\|x, acc\| x + acc` |
| `lists::foldl((x, acc) -> x + acc, 0, xs)` | `:lists.foldl(fn x, acc -> x + acc end, 0, xs)` | — |

Verified on the BEAM: `Enum::map(xs, (x) -> x * 2)` on `[1,2,3]` → `[2,4,6]`;
`lists::foldl((x,acc) -> x+acc, 0, xs)` on `[1,2,3,4]` → `10`. Rust closure `|x| x * 2`
compiled and called.

---

## 2. `if` / blocks

`if c do .. else .. end` is an expression on both targets; blocks are `;`-separated statements
(`name := e` bindings + a final value expression).

| Rian | Elixir | Rust |
|---|---|---|
| `if n >= 0 do 1 else 0 - 1 end` | `if n >= 0 do 1 else 0 - 1 end` | `if n >= 0 { 1 } else { 0 - 1 }` |
| `if n > 0 do a := n * 2; a + 1 else 0 end` | `if n > 0 do a = n * 2; a + 1 else 0 end` | `if n > 0 { let a = n * 2; a + 1 } else { 0 }` |

Verified on the BEAM: `sign(-5)` → `-1`, `sign(7)` → `1`; `step(3)` → `7`, `step(-1)` → `0`.
Both Rust forms compiled and run (`s = -1`, `t = 7`).

---

## 3. List / map literals

| Rian | Elixir | Rust |
|---|---|---|
| `[1, 2, 3]` | `[1, 2, 3]` | `vec![1, 2, 3]` |
| `[h \| t]` (cons construction) | `[h \| t]` | **BEAM-only** (no idiomatic Vec cons) |
| `%{a: 1, b: 2}` | `%{a: 1, b: 2}` | **BEAM-only** (PoC) |

Cons-construction and map literals are correctly **refused** for the Rust target (raise with a
"BEAM-only" message) — consistent with the three-ring model; the Rust backend never emits
non-idiomatic map/cons code. Verified on the BEAM: `[10,20,30]` → `[10,20,30]`,
`[p | [1,2]]` with `p=0` → `[0,1,2]`, `%{a:1, b:2}` → `%{a: 1, b: 2}`. Rust `vec![1, 2, 3]`
compiled.

---

## 4. Self-hosting subset — now complete

| Capability | Status |
|---|---|
| Sum types / records / `match` | ✅ verified |
| Pattern matching + guards (+ exhaustiveness) | ✅ verified |
| Recursion, modules, operator table | ✅ verified |
| FFI to BEAM libs | ✅ verified (ADR-0027) |
| **Lambdas / closures** | ✅ **verified (this ADR)** |
| **`if` / block / `let`-sequencing** | ✅ **verified** |
| **List / map literal construction** | ✅ **verified** |

The subset a compiler needs to express itself is now built and exercised end to end. The
remaining work toward Stage 1 is **engineering, not language design**: a real lexer + lossless
CST, a declaration parser, and rewriting the compiler modules in Rian (using FFI to `:lists`,
`:maps`, `:compile.forms`).

---

## 5. Verification summary

- **Parser:** lambdas, `if`, blocks, list/map literals added; the 22 precedence assertions
  still pass (operator core unchanged).
- **BEAM:** all seven feature functions evaluated and correct.
- **Rust:** closure, if-expression, block-with-binding, and `vec!` literal compiled by
  rustc 1.75 and run.
- **Project total:** 98 host-language tests, 0 failures.

---

## 6. Open items
- Branch-aware linearity now that `if`/`match` arms exist (max uses over arms; consumed-in-all
  branches = consumed once) — the next refinement of capability checking.
- Capability of lambda *captures* → `Fn`/`FnMut`/`FnOnce` (closure literals lower; the trait
  on a closure-typed *parameter* is the remaining piece).
- Rust lowering for maps (when a Rust-target function needs them) via `HashMap`/`BTreeMap`.
- Multi-statement blocks with intermediate effectful expressions (Rust needs `;` after each).
