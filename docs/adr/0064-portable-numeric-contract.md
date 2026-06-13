# ADR-0064 — Portable numeric contract: `Int` (arbitrary precision) + fixed-width wrap

**Status:** Proposed · **Supersedes:** the numeric/overflow decision of **ADR-0034 §1** ("Int* declare intent, not a portable overflow contract"), **ADR-0041 §"native-per-target representation"** *as applied to integers*, and the **ADR-0035** overflow-scope clarification
**Refs:** ADR-0036 (subrange types), ADR-0047 (portable prelude — `Int.checked/saturating/wrapping_add` live here), ADR-0049/0050 (emitters / core IR), ADR-0057/0058 (portability is the thesis)
**Owners:** Samir Patel (numeric rigor) · Maya Lin (emitters) · Tomás (BEAM performance) · Mira (totality/semantics) · Kira Neri (honesty) · Rachel Okafor (PM)

## Context

ADR-0034 §1 / ADR-0041 / ADR-0035 settled integers as **"width is intent, not a contract"**: `Int64`
declares *minimum precision*, and each target uses its **native** integer semantics — BEAM promotes to
bignum, Rust panics-debug/wraps-release, JS uses `BigInt`, JVM/Go wrap. Bit-identical cross-target
arithmetic was pushed to an opt-in library.

The 2026-06 design review (P2) judged this a **bug, not a feature**: *"width as intent, not contract"
directly contradicts the portability thesis* (ADR-0057). The whole premise of Rian is "share the same
sequential logic across BEAM/Rust/JS"; an `Int64` that silently means *unbounded bignum* on the BEAM
and *64-bit wrap* on Rust is not shared logic — it is four behaviours wearing one type name, the exact
"we'll figure it out per target" mistaken for a design that the review called out. (This is also Julia's
lesson the prior review took *half* of: we borrowed Julia's promotion concern but skipped its good
idea — promotion as an explicit, portable thing.)

The objection that kept the room honest (Tomás): a *portable* fixed-width contract forces **masking**
arithmetic on the BEAM (the BEAM has no native fixed-width int; two's-complement wrap needs a
`band` + sign-fixup per op), eroding BEAM-native performance. Per the review, this was gated on a
measurement **before** committing.

### The spike (measured 2026-06-14, `bench/numeric_masking.exs`)

The self-host lexer's hot path — fold a digit lexeme `acc*10 + d` — over a 12-digit number, 5M times:

| Path | Time | Per lexeme |
|---|---|---|
| **native** BEAM integer arithmetic | 89.7 ms | 17.9 ns |
| **fixed-width wrap** (mask to signed-64 each op) | 1325.7 ms | ~265 ns |
| **overhead** | **14.8×** | +247 ns |

So Tomás is right: per-op masking is **~15× slower** on the BEAM's hot integer paths. This does **not**
reject a portable contract — it tells us **which type must be the default**.

## Decision

Replace "native-per-target integers" with **two integer types, each with a portable contract**:

### 1. `Int` — arbitrary precision (the default)

`Int` is a **mathematical integer**: no overflow, no wrap, **identical semantics on every target**.
It is the default for an integer literal and for "I'm doing arithmetic, not bit-twiddling." Per-target
representation:

| Target | `Int` |
|---|---|
| BEAM | native integer (bignum promotion) — **free**, this is the BEAM's native model |
| JS | `BigInt` — free |
| Rust | a bignum (`num-bigint::BigInt`, or `i128` with checked-promotion for the common small case) — **the cost lands here** |
| JVM | `BigInteger` (or `long` + promotion) |

### 2. `Int8/16/32/64` + `UInt8/…/64` — fixed-width, **defined two's-complement wrap**

A fixed-width type has a **portable wrap contract**: arithmetic wraps two's-complement at the width, the
**same on every target**. It is the opt-in for bit-exact / hashing / serialization / performance-on-Rust:

| Target | `Int64` |
|---|---|
| Rust | native `i64` — **free** |
| JVM/Go | native 64-bit — free |
| JS | `BigInt.asIntN(64, …)` per op |
| BEAM | `band` + sign-fixup per op — **the ~15× cost the spike measured** |

**No type is cheap on every target** — that is inherent (the BEAM has no fixed width; Rust has no free
bignum). The resolution is **intent**: `Int` is cheap where math is native (BEAM/JS) and the default;
fixed-width is cheap where bits are native (Rust/JVM/Go) and opt-in. The programmer picks the type whose
*contract* they need, and pays the representation cost only on the target that doesn't share it — and
never silently: the cost is visible in the chosen type, not hidden in "native-per-target."

This **pays Tomás's concern directly**: the default (`Int`) is masking-free on the BEAM; masking is
confined to code that explicitly asked for a fixed width.

### 3. Migration of the existing ops

`Int.checked_add` / `saturating_add` / `wrapping_add` (ADR-0047, already shipped) become the **explicit
crossings**: `wrapping_*` *is* the fixed-width contract spelled at the call site; `checked_*` surfaces
overflow in the type (`Option`); arbitrary `Int` simply never overflows. Subrange types (ADR-0036) stay
the in-domain idiom over either.

## Consequences

- **`Int` becomes the default integer** (was `Int64`, ADR-0033/0034) — a literal `42` is an `Int`. A
  width is now an explicit, portable choice (`n Int64`), not a silently-per-target one.
- **The portability gate gets honest about integers** — `Int` and fixed-width both reach all targets
  with *identical* semantics; the divergence ADR-0035 documented is gone (paid in representation cost,
  not behaviour).
- **Implementation (follow-up, large):** add `Int` to the checker/emitters (BEAM/JS native; **Rust
  bignum** is the real new work); add fixed-width wrap lowering (BEAM `band`/sign-fixup; JS `asIntN`).
  The Rust-bignum and BEAM-masking emitters are each gated on their own conformance tests.
- Supersedes the numeric clauses of ADR-0034 §1 / ADR-0041 / ADR-0035; those get a "superseded by
  ADR-0064" note rather than deletion.

## Open items

- **Default-precision ergonomics on Rust** — when can an `Int` provably fit `i64` (small-loop induction
  vars, indices) so we emit native `i64` not a bignum? A range/escape analysis, future.
- **Mixed-width arithmetic** — `Int + Int64`: require an explicit cast (no implicit coercion, ADR-0035),
  or define a promotion rule? Lean explicit.
- **Float** — this ADR is integers only; `Float64`/`Float32` IEEE-754 semantics are already portable and
  unchanged.
