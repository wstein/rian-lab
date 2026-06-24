# Pipeline phases — the pre-check / post-check contract

This is the **phase-ordering contract** for the compile pipeline: what each phase may assume about the
program it receives, and what it may **not** destroy. It exists so an ordering question
("can this fold run earlier?", "why is inlining post-check?") is answered by reference, not re-debated.
It is the written form of the boundary discovered twice already — once when pre-check inlining masked an
argument-type error, once when the interpolation bake and inlining couldn't compose (ADR-0046 §5).

The one rule everything below follows:

> **`Check` is the gate. Any transform that could hide a type error from the checker must run *after*
> `Check`. Any transform that the checker depends on seeing must run *before* it.**

## The phases

| # | Phase | Module(s) | Kind |
|---|---|---|---|
| 1 | Lex + parse (declarations, expressions, patterns) | `Rian.Lexer` / `Rian.Decl` / `Rian.Pratt` | build |
| 2 | Program-tail rewrites (macro expand, `comptime`, constant fold, interpolation resolve + bake) | `Rian.Macro` / `Rian.Comptime` / `Rian.Interp` (`Decl.run_program_tail`) | **pre-check** |
| 3 | **Type check** (inference + error sets) | `Rian.Check` | **gate** |
| 4 | Semantic simplification (#2 dead-`if`, #3 const-`case`, #4 bool identities, #5 call inlining, interp re-bake) | `Rian.Optimize` (`Lower.All.prepare`) | **post-check** |
| 5 | Exhaustiveness + capability gates | `Rian.Exhaustiveness` / `Rian.Capability` | gate |
| 6 | Reachability / portability matrix | `Rian.Reach` | analysis |
| 7 | Emit (BEAM / Rust / JS / JVM) | `Rian.Beam` / `Rian.Lower` / `Rian.JS` / `Rian.JVM` | sink |

## Phase 2 — pre-check rewrites: **type-preserving and variable-neutral**

These run before the checker, so they may rewrite **only** in ways that cannot change what the checker
would conclude. Concretely a phase-2 pass MAY:

- Fold a **fully constant** expression to its literal (`2 + 3 * 4` → `14`, `"a" <> "b"` → `"ab"`). A
  constant has exactly one value and one type; folding it is invisible to inference.
- Resolve a surface form to the canonical node the checker expects (`${…}` → a `<>`/stringify concat;
  `Prim.x` → `__prim_x`; a macro call → its expansion).

A phase-2 pass MUST NOT:

- **Eliminate a branch or an operator over a variable.** `if c do 1 else "x" end` is a type error the
  checker reports; folding the dead branch away pre-check would mask it. (This is why dead-`if` is
  phase 4, not phase 2.)
- **Inline a function call.** `f(2 + 1)` where `f` expects a `String` is an argument-type error;
  inlining `f` to its body pre-check erases the call and hides the mismatch. (This is the bug that put
  #5 in phase 4.)
- **Drop an operand** in a way that loosens an inferred type (`x and true` → `x` un-pins `x : Bool`,
  which `InferLocal` relied on; it also loses the operator's `Reach` pin). Evaluation-preserving boolean
  identities are therefore phase 4.

The litmus: *folding a constant is variable-neutral; eliminating or substituting code that mentions a
variable is not.* Variable-neutral → phase 2; otherwise → phase 4.

## Phase 4 — post-check simplification: **may eliminate, must stay well-typed**

By the time these run, `Check` has validated the **whole** program — every branch, every call's
argument types, every arm. So phase 4 MAY do the things phase 2 may not: drop a now-dead branch, select
a constant `case` arm, inline a constant call, re-bake an interpolation hole. The checker already
caught anything ill-typed; eliminating validated code masks nothing.

A phase-4 pass MUST still:

- **Produce only well-typed results.** A post-check fold that yields a string literal (the interp
  re-bake) is trivially safe — a literal cannot introduce a type the checker missed. The safety of a
  phase-4 transform is judged by *what it can produce*, not by what it consumes.
- **Be build-time-bounded** (ADR-0046 boundary B). One pass, or a *declared* finite iteration count —
  never an unbounded fold-until-convergence loop. The interp re-bake is one pass and idempotent.
- **Respect boundary A** (ADR-0046): do **semantic** optimization, not **machine** optimization. The
  re-bake finishes an *interpolation hole* (a surface feature Rian owns); it does not fold arbitrary
  runtime concatenation — rustc/LLVM/V8/the BEAM-JIT do that.

## Two consequences worth stating

- **`Reach` runs on the phase-4 output** (the simplified program), so the portability matrix is honest
  about the code actually emitted — not the pre-simplification shape.
- **The bare parity path skips phase 4.** `Decl.parse → emit` (used by the cross-emitter parity
  fixtures) does **not** run `Rian.Optimize`; only the `Lower.All.prepare` front-end (and the tour
  `build_cell`) composes it. So a parity fixture sees un-simplified code, and the playground/tour see
  simplified code — by design.

## When you add a transform

Ask the two questions in order:

1. **Does the checker need to see this rewrite to do its job?** (e.g. it must type the resolved
   interpolation concat.) → phase 2, and it must be type-preserving.
2. **Could this rewrite hide a type error, or does it eliminate/substitute code over a variable?** → it
   must be phase 4, after the gate.

If a transform answers "yes" to both — it needs the checker's output *and* it could mask an error — it
cannot be a single pass. Split it: the part the checker needs (phase 2) and the part that consumes the
checker's verdict (phase 4). The interpolation bake is exactly this split — resolve + bake constants in
phase 2, re-bake the inlining-exposed constants in phase 4.
