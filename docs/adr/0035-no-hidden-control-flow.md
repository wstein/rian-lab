# ADR-0035 — No Hidden Control Flow

**Status:** Accepted
**Implemented:** n/a — principle, enforced by the gates (`Rian.Exhaustiveness` no-silent-partiality, `Rian.Check` errors-as-values) and cited as a constraint by ADR-0039/0040/0042
 · **Positive complement:** [ADR-0046](0046-compile-time-by-default.md) (Compile-Time by Default — *what can be settled before it runs, is*) · **Refs:** ADR-0032 (concept-borrowing), ADR-0034 (type-system foundations)
**Owners:** Julian Vance (grammar) · Maya Lin (multi-target) · Samir Patel (rigor)
**Borrows the *discipline* of:** Zig (no hidden control flow), Go / V (one obvious way)

## Context

The concept review (Rust/Go/Julia/Kotlin/Crystal/Ruby/Zig/V/Oz/Prolog) asked what would make Rian
*more focused*. Most borrows make a language **bigger**. The one that makes it **smaller** is a
discipline: **what you read is what runs.** It is the only borrow adoptable *today*, before the
type checker, and it constrains every later feature decision.

## Decision

Rian adopts **No Hidden Control Flow** as a standing design principle. Concretely:

1. **No exceptions in the portable core.** Errors are values — `Result(T, E)` over a typed error
   set (ADR-0034). Control does not jump invisibly up the stack. (The BEAM target may still surface
   `FunctionClauseError` for explicitly `@partial` functions; that is opt-in, never silent.)
   **Termination is permitted, recovery is not:** `Prim.panic(msg) : T forall T` is a diverging,
   **uncatchable** abort for invariant violations / unreachable arms (lowers to
   `erlang:error`/`panic!`/`throw`/Kotlin `throw`; portable to every target). It is *not* hidden
   control flow — with no `catch`, control routes nowhere; the process terminates. Use it only for
   "can't happen," never for an expected error (that is a `Result`). **Catchable `try`/`catch` was
   considered and rejected** (decision 2026-06-18, see ADR-0040 §"Considered: capability-guarded
   exceptions"): Rust has no idiomatic catchable exception (`catch_unwind` needs `UnwindSafe` and
   aborts under `panic=abort`), so a Rian `catch` would be a *runtime-semantics* divergence across
   targets — breaking the ADR-0050 "idiomatic per target" thesis, not just a missing API. A
   genuinely-host-raising boundary (`Code.format_string!`, ad-hoc compile, file I/O) is an **FFI
   effect**, tracked by `Rian.Reach` like any host call — not a surface exception.
2. **No hidden allocation on non-GC targets.** On Rust/WASM, allocation is visible in the lowering;
   capability-driven ownership (ADR-0025) governs it. The GC targets (BEAM/JVM/JS) allocate as
   their runtimes do.
3. **No operator-overload surprises.** Operators have fixed, total meanings (the precedence table);
   they are not user-redefinable to run arbitrary code. (`comptime` and macros are the *explicit*
   metaprogramming channels — ADR-0030 — not operators.)
4. **No silent partiality.** A non-total function is a compile error unless marked `@partial`
   (clauses-guards §6). `case` over an open type requires a `_ ->` arm (ADR-0033/0034).
5. **No implicit coercions.** `/` is float division, `div` is integer (expressions spec); promotion
   is explicit. Numeric widths convert only via an explicit cast/annotation.

6. **A block's value is its final *expression* — never a trailing binding.** A block body
   (function body, `if`/`case`/`with` arm, lambda body) whose last statement is a binding
   (`x := e`) is a **compile error** (`Rian.Core.from_expr`), enforced at the one surface→Core
   chokepoint so it also catches macro-expanded blocks. A binding has no portable value: the
   BEAM would return the bound RHS (Elixir's `=` is an expression), but Rust lowers `let x = e;`
   to a `()`-typed block — `rustc` rejects the resulting `().to_string()`. Allowing it would be a
   **silent cross-target divergence** (the same failure mode as the Int↔Float widen above). The
   fix is explicit: make the value the final line (add `x`), or use the `:= expr` one-liner for a
   single-expression body. This is the ML-family discipline — OCaml/Haskell/F#/Rust all require a
   trailing expression, never a bare `let`.

   A **destructuring bind** — a tuple/list *pattern* on the left of `:=` (`{a, b} := e`,
   `[h | t] := e`) — is sugar over a single-arm `case`: `Rian.Pratt` desugars `{a, b} := e ; rest`
   to `case e do {a, b} -> rest end`, so the bound vars scope over the continuation, the refutable
   list shape is the writer's assertion (exactly as Elixir's `=`), and the exhaustiveness gate sees
   it like any `case`. No new Core node; same trailing-bind rule applies (a destructuring bind may
   not be a block's last statement). A simple `name := e` stays a plain `{:bind, …}`.

   > **A unit-yielding expression may not appear in value position (enforced 2026-06-17).**
   > Where a value is **used** — return, binding RHS, function argument, or a branch that itself
   > feeds a used value — the expression must actually yield one. Two constructs yield unit and are
   > therefore a **compile error** in value position (`Rian.Check.check_value_position`): an
   > **`else`-less `if`** (an `if` is an expression; its `then`/`else` must both yield the same type)
   > and a **`<~` mutation** (the expressions spec defines `<~` as yielding unit). Each is legal
   > *only* as an **effect statement** — a non-final statement of a block, whose value is discarded
   > (unit-typed, as in Rust). The gate threads a value/effect *position* through the body: a block's
   > non-final statements are effects, its final statement inherits the block's position, and
   > `if`/`case`/`with` branches inherit the position of the construct they belong to. That position
   > context is why this is a `Check` gate, not a Core or parser rule. (OCaml/Haskell require `else`
   > on *every* `if` because they have no statement position at all; Rian keeps the effect form,
   > matching Rust.)

   > **Amended 2026-06-14 — enforced for Int↔Float arithmetic.** `+`/`-`/`*` whose two operands are
   > concretely one integer-kind and one float-kind is a **compile error** (`Rian.Check.check_numeric_mix`),
   > not a silent widen — e.g. `10.2 * a` with `a : Int64`. A value never silently becomes a float
   > (the widen is lossy past 2⁵³), *and* the construct is non-portable (rustc rejects `i64 * f64`),
   > so allowing it on the BEAM (where Erlang auto-promotes) would be a silent cross-target divergence.
   > An integer literal does **not** adopt `Float` in arithmetic either (consistent with ADR-0034 §1's
   > binding rule: `x Float64 := 66` is rejected). The fix is explicit: a float literal (`3.0`) or the
   > portable conversion **`Prim.int_to_float(n)`** (`erlang:float/1` · `n as f64` · `Number(n)` ·
   > `.toDouble()`). The gate fires only on a *provable* mix (an `:unknown` operand stays conservative).
   > The nicer surface `Float64.of(n)` is a future sugar over the same intrinsic.

The litmus test for any future feature: **can a reader predict where control goes and what
allocates, from the source alone?** If not, it does not enter the portable core.

### Scope: overflow and platform-native behavior (decision-lock 2026-06-12)

> **⚠ Superseded for integers by [ADR-0064](0064-portable-numeric-contract.md) (P2, 2026-06-14):**
> "each target uses its native integer semantics / Rian does not simulate one runtime on another" no
> longer holds for integers — `Int` (arbitrary precision) and fixed-width (defined wrap) now have
> *portable* contracts. The no-hidden-control-flow principle itself is unchanged; only the
> integer-overflow scope clarification below is retired.

"No hidden control flow" governs **Rian's own constructs** (`case`, `with`, operators-as-written)
and the program's **in-domain** semantics. It does **not** require masking a target's native
behavior on **out-of-domain** values. Integer overflow is the canonical case: an *edge case correct
code stays clear of*, not a control-flow feature. Each target therefore uses its **native integer
semantics** (BEAM promotes to bignum; Rust panics-debug/wraps-release; JVM/Go wrap; JS uses
`BigInt`) — Rian does **not** simulate one runtime on another. The discipline this still imposes is
twofold: (1) the cross-target divergence must be **documented, never silent** (now recorded on the
numeric primitives in ADR-0033), and (2) the language must provide first-class tools to **stay
in-domain** — subrange types (ADR-0036) as the promoted idiom, plus explicit overflow ops. As of
2026-06-13 those ops are **shipped**: `Int.checked_add` (→ `Option(Int64)`, overflow surfaced in the
type), `Int.saturating_add` (clamp), and `Int.wrapping_add` (two's-complement) — a portable `mod Int`
over per-target primitives (each backend's native `i64` op on Rust; a bignum/`BigInt` projection on
BEAM/JS), see [prelude_int.rian](../../examples/rian/prelude_int.rian) (ADR-0047 §2). `sub`/`mul`
follow the identical pattern. Bit-identical cross-target arithmetic is therefore an **opt-in
library** call, not a core guarantee. (A Rust `panic!` on a proven-impossible value — e.g. the
ADR-0036 `unreachable!()` shim — is loud, not hidden, and is the sole sanctioned trap.)

## Rationale

- This is the discipline behind Rian's *existing* best ideas — the exhaustiveness gate, explicit
  `@partial`, `/`-vs-`div`, mandatory signature capabilities. The ADR names the principle they
  already follow, so it stops being re-derived per debate.
- It is what *rejected* the dilutive borrows in the concept review: exceptions (hidden jumps),
  open multiple dispatch (unpredictable target), CSP/coroutine concurrency on top of OTP (two
  control models). Those rejections now trace to one rule.

## Ratings

| Principle | Rating |
|---|---|
| Errors are values; no exceptions in the portable core | 5/5 |
| No hidden allocation on non-GC targets | 5/5 |
| No operator-overload surprises | 5/5 |
| No silent partiality | 5/5 |
| No implicit coercions | 4/5 |
| Block value is the final expression, never a trailing binding | 5/5 |
| Unit-yielding expressions (`else`-less `if`, `<~`) rejected in value position | 5/5 |

## Consequences

- New-syntax / new-feature proposals must pass the litmus test, recorded in their ADR/PR.
- Pairs with ADR-0034: error sets are *how* "errors are values" is made checkable.
- Reinforces existing decisions (exhaustiveness, `@partial`, `/`-vs-`div`) rather than changing
  them.

## Open items

- **`@partial` on the BEAM** — exact diagnostic (generated raising clause vs. `FunctionClauseError`).
- **Allocation visibility** — how explicit it must be on Rust/WASM at the surface vs. inferred from
  capabilities; settle with the target-model ADR. **Resolved (2026-06-13 design review):** a
  proposal to surface non-GC memory in the *grammar* — a sigil (`~`/`^`) on `iso`/linear bindings,
  or an allocation prefix on the universal dot (ADR-0029) for heavy Rust structs — was **rejected**.
  It (a) imports a target-specific model into the shared surface, the same move ADR-0032 rejects for
  Rust's `?`; (b) is redundant with information the checker already holds — capabilities are inferred
  and checked (`Rian.Capability`), and the checker deliberately infers `:unknown` rather than guess
  (ADR-0034), so a *mandatory* sigil has no honest rendering for an unknown capability; and (c) is
  meaningless on the BEAM/JS two-thirds of targets. The visibility gap is real but belongs in
  **tooling, not grammar**: capability-on-hover is an ADR-0038 Tier-2 LSP deliverable (needs
  inference), and a provable misuse is already a `Rian.Capability` linearity error. The surface stays
  family-clean; the reality is surfaced where it is computed.
- **Non-BEAM concurrency** — a named gap (see ADR-0031): the non-BEAM targets get the *sequential
  core* only. *If* structured concurrency is ever added there it must be lexically explicit
  (Occam-style scoped parallelism, no detached tasks); OTP/actors stay BEAM-only, no CSP/dataflow.
