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
macro unless(cond, body) := if not cond do body else 0 end
macro square(x)          := x * x
```

> **Amendment (2026-06-13):** the template separator is **`:=`**, not the `=>` originally sketched
> here. `=>` was never lexable, and `:=` is already Rian's "defined as" operator (`def f := body`,
> binds) — reusing it keeps the surface consistent and adds no token. The macro declaration reuses the
> `def` head/body grammar verbatim (`Rian.Decl`).

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

## Portable-core discipline (2026-06-13 design review)

A review raised the "debugging a ghost" failure: a one-line macro call whose template expands into
hidden failable binds produces type/ownership errors pointing at nodes the caller never wrote. The
proposed fix — a raw macro-depth cap (e.g. ≤ 2) for portable code — was **reframed**: depth is a poor
proxy (a benign macro calling a benign helper is not "soup"), and the thing actually worth forbidding
is the **introduction of caller-invisible control flow**. So for shared / `@targets`-declared code
(ADR-0058) a macro template **may not introduce a failable bind** (`with … <- …`, ADR-0039) — the
no-hidden-control-flow rule (ADR-0035) applied to expansion. Implemented in `Rian.Macro.expand/3` as
`portable: true` (rejection by macro name; `@max_depth` stays a separate runaway backstop). The
companion tooling half — **expand-macro-on-hover** — is an ADR-0038 capability, honestly tiered as
**Tier 3** (needs a resolved semantic model to map expanded spans back to source), not Tier 1.

*Pipeline integration (shipped 2026-06-13):* user `macro name(params) := template` declarations are
now parsed by `Rian.Decl`, collected into a per-scope env, and expanded into call sites in
`assemble/3` — a pure AST→AST pass *before* the checker and every emitter. The expanded `{:block, …}`
AST is stored back into each clause's `body`; `Pratt.parse_body/1` passes an AST through unchanged, so
all body consumers (Check, Reach, Beam, Lower, JS) see expanded code with no per-consumer threading.
Macros are scope-local and emit no IR. In a `@targets` module the `portable:` guard above is active
(a failable-bind template is rejected at parse). Verified end-to-end on the BEAM (`Beam.load`) and to
Rust (`Decl.compile`). Still open: macro *fragment kinds* and macro calls inside clause *guards*.

## Direction: derivation is comptime's job, not AST macros (2026-06-14 Gleam/Haxe debate)

The Gleam/Haxe borrow debate (consensus #4, rated 4/5) settled a standing tension between two
established macro cultures, and it bears on *which way this ADR grows*:

- **Gleam ships with no macros at all** — and pays for it in user-side boilerplate (hand-written
  JSON encoders/decoders per type; no derivation). Its minimalism is honest but moves work onto users.
- **Haxe has fully reified AST macros** (write Haxe to rewrite typed Haxe) — powerful, and the single
  largest source of "miscompile" / IDE-breakage reports in that ecosystem. A hygiene minefield.

The synthesis the team reached: **kill the boilerplate (Gleam's weakness) without importing AST
surgery (Haxe's hazard).** The boilerplate use-cases — `derive` for equality/ordering/show/encode —
are a **comptime** problem (run code *over a type* at compile time) routed through **protocols**
(ADR-0042), **not** a pattern→template macro problem. Concretely:

1. **Macros stay minimal** (the Gleam restraint): declarative pattern→template, hygienic, scope-local,
   no reified-AST host API. We explicitly **do not** adopt Haxe-style "manipulate the typed AST in
   Rian." Every macro remains a place where what-you-read and what-runs diverge, so the surface is
   kept deliberately small.
2. **Derivation grows on comptime + protocols, not macros.** A future `derive Eq`/`derive Show`
   reflects over a type's fields at compile time (the `comptime`-as-generics evaluator below is the
   foundation) and emits a protocol `impl` — checkable, hygienic-by-construction, no AST rewrite.
3. The likely consequence: as derivation moves to comptime, **the macro surface may shrink toward
   near-nothing** — a partial move toward Gleam's no-macros position without losing the power, which
   is the outcome to aim for, not to resist.

## Open items
- **`comptime`-as-generics**: monomorphize a function over a comptime type/const parameter
  (emit one specialized fn per instantiation). The evaluator built here is the foundation.
- **`derive` via comptime + protocols** (the direction above): reflect over fields at compile time,
  emit an `impl` — the boilerplate-killer that keeps macros minimal (ADR-0042).
- **Macro fragment kinds** (expr vs pattern vs type position), à la `macro_rules!`
  `$x:expr`/`$t:ty`, once the declaration parser exists.
- **Build capability** to allow a vetted, effectful `comptime` (currently always pure).
- ~~Float constants in comptime~~ — **done**: comptime now folds float literals and `/`
  (`comptime(3.14 * 2)` ⇒ `6.28`); `div`/`rem` stay integer-only.
