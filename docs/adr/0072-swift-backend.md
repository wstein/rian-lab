# ADR-0072 — Swift backend (the mobile-completion target)

**Status:** Proposed (direction agreed) · **Gated — not adopted until `swiftc` runs in CI** · debated 2026-06-14. Sequenced *after* ADR-0071 (Python).
**Implemented:** no — proposed direction only; gated until `swiftc` runs in CI. No `Rian.Swift` emitter exists and `:swift` is not in the `Rian.Reach` target vocabulary.
**Refines:** ADR-0049 (backend tiers — adds Swift beyond the original list), ADR-0026 (target list).
**Refs:** ADR-0041 (target model), ADR-0042 (dispatch), ADR-0050 (Core IR is the emitter spine), ADR-0058 (reachability + `@targets`; **CI parity**), ADR-0064 (portable numeric contract), ADR-0069 (interpolation), ADR-0036 (`Char`), ADR-0034 (`Option(T)`, no `nil`), ADR-0000 (honesty: the matrix matches what is *verified*).
**Owners:** Arthur Pendelton (dispatch / sum lowering) · Maya Lin (emitter/tiers) · Kira Neri (CI parity / Reach honesty) · Elena Rostova (numerics) · Mira (totality) · Rachel Okafor (PM)

## Context

Rian already emits Kotlin (Android, ADR-0049 Tier 2). Adding **Swift** unlocks **iOS/macOS** and,
paired with the Kotlin backend, the most *differentiated* story in Rian's lineup:

> write your domain logic once → ship the same typed, tested core to **iOS, Android, and web**.

That is the exact duplication Kotlin Multiplatform exists to remove — except Rian's portable core
*also* reaches web (JS), native (Rust), the BEAM, and Python (ADR-0071), which KMP does not. The
target audience is every team maintaining parallel Swift and Kotlin copies of the same business rules.

Technically Swift is the **best algebraic-type fit of any target Rian has** — `enum` with associated
values + exhaustive `switch` maps onto Rian's sum dispatch more cleanly than Rust or Kotlin, with no
ownership ceremony (value types under ARC). The catch is **verification**: the gate-honesty contract
(ADR-0058/0000) requires that a claimed `:swift` reach be *mechanically checked* by compiling and
running Swift in CI — and `swiftc` is **not** in the CI environment today (unlike `rustc`/`node`/
`kotlinc`). This ADR is therefore **adopted in direction but gated on CI parity.**

These are **audience** targets, not performance targets — Rust owns speed.

## Decision

### 1. Placement — a static, nominal, value-semantics target (ARC, not borrow-checked)

Swift sits with Rust/JVM as a static nominal target, but is **garbage-managed by ARC** (reference
counting), so — like BEAM/JS/JVM/Python — capabilities (`val`/`iso`/`tag`/`ref`) are **erased for
codegen**; none of the Rust borrow machinery applies. `iso` lowers to a value copy (Swift base
semantics are copy; the 5.9+ `consuming`/`~Copyable` move model is not required and not used), and
`ref` lowers to a value binding (sound while the Rian surface is return-based — same argument as the
JVM backend, ADR-0049). The emitter `Rian.Swift` consumes the typed Core IR (ADR-0050).

### 2. Construct mapping

| Rian | Swift | Note |
|------|-------|------|
| `Int` (arbitrary precision) | — | **no stdlib bignum → pins off `:swift`** (like Rust/JVM) |
| `Int53` | `Int64` | |
| `Int8…64`, `UInt8…64` | native `Int8…64` / `UInt8…64` | wrap via `&+`/`&-`/`&*` for the overflow ops |
| `Int128`/`UInt128` | `Int128`/`UInt128` (**Swift ≥6.0 only**) | pins off on older toolchains — record the floor |
| `Float64/32` | `Double`/`Float` | |
| `Bool`, `Char`, `String` | `Bool`, `Character`, `String` | `Character` is a grapheme; codepoint via `Unicode.Scalar` |
| `Symbol` (atom) | `String` | no atom analog (as on Rust/JS/JVM) |
| `Vec(T)` / `Dict(K,V)` | `Array<T>` / `Dictionary<K,V>` | |
| `Option(T)` | explicit `enum Option<T> { case some(T), none }` | **not** Swift's native `T?`/`nil` — Rian rejects `nil` (ADR-0034); see *Open items* |
| `type T := A \| B(Int)` | `enum T { case a; case b(Int64) }` | **the best-fit encoding Rian has** (§3) |
| `struct P(x Int)` | `struct P` (value type) | |

### 3. Sums and dispatch — the cleanest target, with NO trailing default

A `type` lowers to a Swift `enum` with associated values; a multi-clause function lowers to a `switch`
over the parameter tuple, one `case .ctor(let x) where g:` per clause — direct binding and guards, no
smart-cast dance (contrast Kotlin's `is`/cast in ADR-0049). The decisive difference from every other
backend: **Swift's `switch` is compiler-checked for exhaustiveness**, so for a Rian sealed sum the
emitter emits **no trailing `default`/`raise`** — it would be dead code Swift *warns* on. This is the
one target where Rian's `Rian.Exhaustiveness` gate and the host's own checker agree natively (the
inverse of Python/JVM, which need the trailing throw because the host won't check — ADR-0071 §3).
`if` is an expression; operators map directly.

### 4. Numerics — strong, with a bignum floor

Native fixed widths `Int8…64`/`UInt8…64` (and `Int128`/`UInt128` on Swift ≥6.0); the two's-complement
overflow ops lower to Swift's masking operators (`&+`/`&-`/`&*`). The gap is **`Int` (arbitrary
precision)**: Swift has no stdlib bignum, so `Int` **pins off `:swift`** exactly as it does off Rust
and the JVM (ADR-0064). On toolchains before Swift 6.0, `Int128`/`UInt128` pin off too. Float
*interpolation* stays deferred per ADR-0069 §6 (Swift's `Double` description diverges from Rust/JS).

### 5. Reach (`:swift`) — honest, and provisional until CI parity

`:swift` joins the `Rian.Reach` `@targets` vocabulary, but with a hard precondition:

- **Reaches:** `Int53`, fixed widths (128-bit only on Swift ≥6.0), `Float`, `Bool`, `Char`, `String`,
  `Symbol`, `Vec`/`Dict`, sums/structs, `Option`/`Result`.
- **Pins off `:swift`:** `Int` and (pre-6.0) the 128-bit widths (no bignum); host FFI; `ref`/`&mut`;
  concurrency.
- **CI-parity precondition (ADR-0058/0000):** `:swift` is **not added to the *default* `@targets`**
  and no function may *claim* verified `:swift` reach until the conformance harness actually compiles
  and runs Swift in CI. Until then the emitter ships with **source-emission unit tests** and a
  `@tag :swift` conformance lane that **no-ops when `swiftc` is absent** (mirroring the existing
  `@tag :rust` pattern). Asserting a reach we cannot execute would be the exact gate lie ADR-0000
  forbids.

### 6. Verification

`Rian.Swift` conformance shells out to `swiftc` (compile + run), mirroring the `rustc`/`node`/
`kotlinc` harnesses, plus a fixpoint diff. **Wiring `swiftc` into CI is the gating deliverable** — the
emitter is buildable and source-testable before then, but Swift is not "Tier-complete" (nor in the
default target set) until the harness runs it. Swift-on-Linux toolchains exist; adopting one in CI is
the precondition this ADR is blocked on.

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — ARC value-semantics, capabilities erased | 5/5 | clean; no borrow machinery, `ref`/`iso` → value (sound for return-based surface) |
| 3 — `enum` + exhaustive `switch`, no trailing default | 5/5 | best algebraic-type fit Rian has; host-checked exhaustiveness |
| 4 — fixed widths native; `Int`/pre-6.0 128-bit pin off | 4/5 | honest bignum floor; −1 for the version-dependent 128-bit |
| 5 — `:swift` Reach, provisional | 3/5 | correct blockers; −2 because the reach is *unverified* until CI parity |
| 6 — `swiftc`-in-CI gating | 5/5 | the honesty precondition; non-negotiable |

## Consequences

- **Differentiated positioning:** with the existing Kotlin backend, Rian can credibly claim the
  "shared logic across iOS + Android + web" niche — broader than KMP (which lacks web/native/BEAM).
- **Drift tax (CLAUDE.md):** a sixth emitter; every new Core node needs a Swift arm. Mitigated by the
  `enum`/`switch` fit being *simpler* than Rust's owned-return machinery.
- **CI cost:** adopting a Swift toolchain in CI is a real infra task and the gate on calling Swift
  done. Until paid, Swift's reach claims are provisional by construction.
- **Sequenced after Python (ADR-0071):** not built in parallel — two simultaneous half-emitters would
  bleed into the unfinished self-hosting Stage 3.

## Open items

- **`swiftc` in CI** — the blocking precondition (§6). Pick a Swift-on-Linux toolchain and wire the
  conformance lane; only then move `:swift` into the default `@targets` and drop the `@tag :swift`
  no-op.
- **`Option(T)` representation.** Faithful `enum Option` (preserves no-`nil`, ADR-0034) vs idiomatic
  Swift `T?`/`nil` (ergonomic but reintroduces `nil`). Lean: faithful enum; the Swift idiom pull here
  is stronger than elsewhere (Swift optionals are first-class), so revisit explicitly.
- **`Character` vs `Unicode.Scalar`.** Rian `Char` is a single codepoint; Swift `Character` is a
  grapheme cluster (may be multiple scalars). Map `Char` via `Unicode.Scalar` to stay codepoint-exact
  (ADR-0036), not `Character`.
- **`Int128` floor.** Decide the minimum supported Swift version; gate the 128-bit reach on ≥6.0.

## Alternatives considered

- **Build Swift before / alongside Python.** Rejected: Swift's *fit* is better but it is **not
  verifiable in CI** today, while Python is (`python3` is ubiquitous) and reaches a larger audience.
  Honesty + reach both favour Python first (ADR-0071); doing both at once risks the Stage-3 work.
- **Map `Option(T)` → `T?` and sums → `enum`-with-`nil`-shortcuts.** Rejected (default): faithful to
  Swift idiom but breaks Rian's no-`nil` contract; recorded as an Open item, not the decision.
- **Claim `:swift` reach now, verify later.** Rejected: an unexecuted reach claim is precisely the
  matrix-lies-about-the-emitter failure ADR-0000/0058 exist to prevent.
