# ADR-0030 — Macros: Declarative, Hygienic, Pattern→Template (+ sandboxed comptime)

**Status:** Accepted; implemented & verified · **Implements:** ADR-0008 (hygienic macros), ADR-0009 (pure comptime)
**Owners:** Arthur Pendelton (expansion) · Marcus Webb (sandbox) · Chloe Bennett (ergonomics)
**Code:** `lib/rian/macro.ex`, `lib/rian/comptime.ex` · **Tests:** `test/rian/macro_test.exs` (10/10); full suite 116/0

## Context

Macros are essential. The mandate: intuitive and easy for humans, explicitly **not** like
Elixir's `quote`/`unquote` AST construction.

### Survey of established macro systems (rated for *intuitive & safe*)

| System | Model | Rating |
|---|---|---|
| Rust `macro_rules!` | declarative pattern→template, hygienic-ish | **5/5** |
| Scheme `syntax-rules` | declarative pattern→template, fully hygienic | **5/5** |
| Zig `comptime` | no macro DSL — ordinary code at compile time | **5/5** (narrower) |
| Nim `template` | hygienic substitution | 4/5 |
| Crystal macros | `{{ }}`/`{% %}` templating | 4/5 |
| Julia macros | AST + `$` interpolation | 3/5 |
| Template Haskell | typed quote/splice | 3/5 |
| C preprocessor | textual token substitution | 2/5 (unhygienic, precedence bugs) |
| Rust proc-macros | `TokenStream` manipulation | 2/5 |
| Elixir `quote`/`unquote` | AST construction | 2/5 (rejected by mandate) |

## Decision

Two complementary mechanisms, both **pure AST→AST passes that run before typecheck** (so **no
parser changes** were needed):

**1. Declarative pattern→template macros** (the `macro_rules!`/`syntax-rules` model):

```
macro unless(cond, body) => if not cond do body else 0 end
macro square(x)          => x * x
```

The template is **ordinary Rian code**; parameters are substituted as **AST**, not text. There
is **no `quote`/`unquote`**. Calls look like normal calls: `unless(n > 5, log)`. Two guarantees
fall out of substituting at the AST level:

- **No precedence bugs.** `square(a + b)` expands to `(a + b) * (a + b)`, never the
  C-preprocessor `a + b * a + b`. The precedence-aware emitter parenthesizes automatically.
- **Hygiene by default.** Template-local binders are gensym-renamed (`tmp` → `tmp__h4770`) so
  they cannot capture the caller's variables.

**2. `comptime(expr)`** (the Zig model): evaluate a constant expression at compile time and
replace it with its literal. The evaluator is a **pure sandbox** (ADR-0009): literals,
arithmetic, boolean/comparison operators only. Calls, non-constant identifiers, and FFI/effects
are **refused** — no build-time effects without an explicit (deferred) build capability.

## Verified

Lowering (both targets), with the expanded forms compiled by rustc and executed on the BEAM:

| Rian | Elixir | Rust | BEAM result |
|---|---|---|---|
| `unless(n > 5, n * 10)` | `if not (n > 5) do n * 10 else 0 end` | `if !(n > 5) { n * 10 } else { 0 }` | `t(3)=30`, `t(7)=0` |
| `square(a + b)` | `(a + b) * (a + b)` | `(a + b) * (a + b)` | `sq(4)=25` |
| `add_tmp(tmp)` | `if true do tmp__hN = 100; tmp + tmp__hN else 0 end` | `if true { let tmp__hN = 100; tmp + tmp__hN } else { 0 }` | **`hyg(5)=105`** (not 200) |
| `comptime(2 + 3 * 4)` | `14` | `14` | `c=14` |
| `comptime((1 + 2) * 5)` | `15` | `15` | — |
| `comptime(3 > 5)` | `false` | `false` | — |

**Hygiene is decisive:** `hyg(5)` returns `105`, proving the macro-local `tmp` did not capture
the caller's `tmp` (an unhygienic expander would return `200`).

**Sandbox refusals** (all raise at compile time):
- `comptime(foo(3))` → "calls are not allowed in a pure comptime sandbox"
- `comptime(x + 1)` → "`x` is not a compile-time constant"
- `comptime(:lists.sum(xs))` → calls refused (FFI is not pure)

rustc compiled the expanded Rust and ran: `u=30 s=25 h=105 c=14`. Operator precedence
unaffected (22/22). Full suite **116 tests, 0 failures**.

## Consequences
- The metaprogramming story is no longer paper: macros and comptime exist, are hygienic/pure,
  and verify on both targets. This unblocks "generics via comptime" (ADR-0009).
- Because expansion is pre-typecheck and pre-emit, macros work uniformly for the BEAM and Rust
  with no per-target macro logic.

## Open items
- **`comptime`-as-generics**: monomorphize a function over a comptime type/const parameter
  (emit one specialized fn per instantiation). The evaluator built here is the foundation.
- **Macro fragment kinds** (expr vs pattern vs type position), à la `macro_rules!`
  `$x:expr`/`$t:ty`, once the declaration parser exists.
- **Build capability** to allow a vetted, effectful `comptime` (currently always pure).
- Float constants in comptime (integers + booleans only today).
