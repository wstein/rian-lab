# ADR-0046 — Compile-Time by Default

**Status:** Accepted · **The positive complement to:** ADR-0035 (No Hidden Control Flow)
**Implemented:** partial — `comptime` constant folding + **automatic constant folding** (`Rian.Comptime`, §5 below) and exhaustiveness/checking gates exist; full monomorphization/specialization is not realized
**Refs:** ADR-0030 (pure `comptime` / monomorphization), ADR-0034 (bidirectional checking; infer-local boundary), ADR-0035 (predictability discipline), ADR-0036 (range bounds), ADR-0037 (`@wire` codecs), ADR-0040 (error-set completeness), ADR-0041 (target-conditioned representation), ADR-0042 (static-by-default dispatch), ADR-0043 (zero-cost opaque types), ADR-0025/capability-lowering (linearity)
**Owners:** Arthur Pendelton (comptime/partial eval) · Elena Rostova (specialization/zero-cost) · Maya Lin (BEAM dynamism) · Samir Patel (checks-as-gate) · Marcus Chen (checks-as-posture) · Kira Neri (determinism/build-time) · Rachel Okafor (PM)

## Context

This ADR names a discipline Rian **already follows** but never wrote down — exactly the situation
ADR-0035 was in. The corpus already moves a large amount of work from runtime to compile time:

| Moved to compile time | ADR |
|---|---|
| Exhaustiveness / totality gate | 0034 / 0035 |
| Type checking (bidirectional) | 0034 |
| Capability / linearity (no runtime GC cost on Rust) | 0025 / capability-lowering |
| Error-set completeness | 0040 |
| `comptime` constant folding + monomorphization | 0030 |
| Closed-set `Symbol` → enum (zero runtime cost) | 0041 |
| Opaque-type distinction (erased at runtime) | 0043 |
| Static-by-default protocol dispatch | 0042 |
| `@wire` codec derivation | 0037 |
| Range bounds (checked where literal) | 0036 |

The positive-form name is **Compile-Time by Default**: *what can be settled before it runs, is.* Where
ADR-0035 says **what you read is what runs**, this says **what can be decided ahead of running, is
decided ahead of running** — both are predictability disciplines.

## Decision

Rian adopts **Compile-Time by Default** as a standing principle, in **two parts with two boundaries**.

### 1. Compile-time *checks* are universal — every target, no exceptions

Type checking, exhaustiveness/totality, error-set completeness, and capability/linearity are decided
**at compile time on every target**, with **no runtime cost anywhere**. An error caught at compile time
cannot reach a user (Samir) and is an attack surface removed (Marcus); `comptime` is **pure** (ADR-0030),
so compile-time work is itself never an effectful footgun. This is the spine of Rian's correctness and
security story and is **not** target-conditioned.

### 2. Compile-time *specialization* is idiomatic-per-target

Monomorphization, closed-set→enum lowering, opaque-type erasure, static dispatch, and constant folding
are **aggressive on Rust/WASM** and **conservative on the BEAM** — because the BEAM is a *dynamic*
runtime (late binding, runtime polymorphism, **hot code upgrade**), and over-eager cross-module
specialization **fights** hot-reload and the REPL-driven workflow BEAM users expect (the connected
REPL of [ADR-0053](0053-repl-interactive-surfaces.md) is the cash-in). This is the
ADR-0041 "same source, two idiomatic shapes" pattern, applied to *when* work is done: the surface is
one program; each target specializes as far as its idiom allows, no further.

### 3. Boundary A — semantic optimization only; the backend optimizes machines

Rian does **semantic / representation** optimization (monomorphization, zero-cost opaque types,
closed-set enums, comptime folding, dead-arm elimination). Rian does **not** do **machine** optimization
— instruction scheduling, register allocation, vectorization, inlining heuristics belong to **rustc /
LLVM and the BEAM JIT**, which have spent decades being good at it. Rian emits **idiomatic** code and
lets the backend optimize it. *Reimplementing the backend optimizer is the trap.*

### 4. Boundary B — bounded by purity, determinism, and build time

Compile-time work earns its place only if it is:

- **Pure** — `comptime` has no effects (ADR-0030); no effectful compile-time evaluation.
- **Deterministic** — reproducible across runs/platforms (a CI and supply-chain requirement, Kira).
- **Build-time-bounded** — inference is local (the infer-local / declare-public line, ADR-0034 §1);
  `comptime` needs a fuel limit (the ADR-0038 sandbox open item). Unbounded or non-deterministic
  compile-time work does **not** get to hide behind this principle.

### The litmus test

For any feature or check, mirroring ADR-0035's test:

> **Can this move to compile time without sacrificing the target's idiom or build determinism?**

If yes, it belongs at compile time. If it would freeze the BEAM's dynamism or blow up the build, it
stays at runtime.

## 5. Automatic constant folding (implemented 2026-06-24)

`comptime(expr)` is the *explicit* form (the user demands the fold, and it raises on a non-constant).
Its automatic complement, the §2 "constant folding" specialization, is now realized: **a pure
expression whose operands are all literals is folded to its literal — `2 + 3 * 4` → `14` — with no
`comptime` marker.** Rian is functional, so an all-literal calculation has exactly one answer; settling
it before the program runs is the litmus test passing trivially. Implementation:

- **`Rian.Comptime.fold_constants`** — a program-tail pass (`Rian.Decl.run_program_tail`, before
  interpolation resolution, so a constant `${…}` hole folds too). OPPORTUNISTIC: a non-constant operand
  simply leaves the node, so it never errors like `comptime`. Folds: numeric/comparison `+ - * / div
  rem < <= > >= == !=`; **constant string concatenation** (`"a" <> "b"` → `"ab"`); fully-constant
  `and`/`or`; and the **evaluation-preserving boolean identities** (`true and x` → `x`, `x and true` →
  `x`, `false or x` → `x`, `x or false` → `x` — no operand dropped, so no effect/Reach change; the
  dropping pair `false and x` → `false` is left to the backend's short-circuit `&&`/`||`, boundary A).
- **Constant interpolation holes bake into the string** (`Rian.Interp`, ADR-0069 §6): once the hole is
  a literal, it is stringified at *compile* time and merged into the surrounding text — so
  `"calc = ${2 + 3 * 4}"` becomes the single literal `"calc = 14"` (`console.log("calc = 14")`), not a
  runtime `"calc = " + String(14)`. Int/Bool/Char bake (their repr is unambiguous); a `Float` hole stays
  a runtime `Show.float` call.
- **Type-preserving (the safety boundary).** It folds only when the numeric literals are
  *kind-homogeneous* (all `Int`, or all `Float`), so it can never fold a mixed `Int * Float` — which
  `Check` rejects (ADR-0034/0035) — and thus **never masks a type error** by running before the checker.
  (`6 / 2` → `3.0` is fine: `/` is float division, which the checker also accepts.)
- **Injected stdlib is exempt.** `Show`/IO (`Rian.ShowStdlib`/`Rian.IOStdlib`) parse with `fold: false`
  — they are compiler-provided, not the user's program (and it keeps them byte-identical to the
  PureScript twin, whose `parseToProg` never runs the fold tail).
- **Opt-out for debugging** — the boundary-A escape hatch this ADR's BEAM-conservatism implies: the
  `--no-fold` build flag (`Decl.parse(src, fold: false)`) keeps the emitted source faithful to what you
  wrote, so you can read/step the original arithmetic. Default is fold-on. Boundary A still holds — Rian
  folds the *semantic* constant; it does not reimplement the backend's machine optimizer (rustc/LLVM/
  the BEAM JIT fold the rest at runtime regardless).

## Rationale

- This is the discipline already behind Rian's best ideas (the exhaustiveness gate, capability lowering,
  zero-cost opaque types, static dispatch). Naming it stops it being re-derived per debate — the ADR-0035
  pattern.
- The two boundaries are what keep it from going wrong: **don't fight the BEAM's dynamism** (boundary A
  of the runtime), and **don't reimplement the backend's optimizer** (boundary of the toolchain).

## Ratings

| Principle | Rating |
|---|---|
| Name "Compile-Time by Default" (complement to ADR-0035) | 5/5 |
| Compile-time **checks** universal on all targets | 5/5 |
| Compile-time **specialization** idiomatic-per-target (aggressive Rust/WASM, conservative BEAM) | 5/5 |
| Semantic optimization only; machine optimization is the backend's | 5/5 |
| Bounded by purity + determinism + build-time | 4/5 |
| Litmus test recorded per future feature | 5/5 |
| Unqualified "always specialize at compile time" | 1/5 (rejected — breaks BEAM dynamism) |

## Consequences

- New-feature proposals state, in their ADR/PR, what they push to compile time and **which part** —
  a universal check (§1) or a per-target specialization (§2) — and pass the litmus test.
- Reinforces existing decisions (exhaustiveness, capabilities, monomorphization, opaque types, static
  dispatch) rather than changing them — it is the principle they already follow.
- **Pairs with ADR-0035:** the two are the negative and positive faces of one predictability discipline.
- The BEAM-conservative specialization stance ties to ADR-0044 (hot-code-upgrade callbacks) and the
  ADR-0031 dynamism the runtime preserves.

## Open items

- **`comptime` fuel/limit defaults** (shared with the ADR-0038 sandbox open item) — concrete
  time/memory/depth caps so build time stays bounded.
- **BEAM specialization dial** — exactly how conservative monomorphization must be to stay
  hot-upgrade-safe (per-module? opt-in `@inline`?), settled with the Erlang-native backend (ADR-0031).
- **Cross-module monomorphization on Rust** — how far specialization crosses module boundaries before
  it hurts compile time (boundary B, build-time bound).
