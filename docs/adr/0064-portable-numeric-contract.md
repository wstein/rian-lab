# ADR-0064 — Portable numeric contract: `Int` (arbitrary precision) + fixed-width wrap

**Status:** Proposed · **`Int` (arbitrary precision) implemented for BEAM + JS** (2026-06-14) · **Supersedes:** the numeric/overflow decision of **ADR-0034 §1** ("Int* declare intent, not a portable overflow contract"), **ADR-0041 §"native-per-target representation"** *as applied to integers*, and the **ADR-0035** overflow-scope clarification
**Implemented:** partial — `Int` arbitrary precision adopted for BEAM + JS (BigInt) (`Rian.Check`, `Rian.JS`; `test/rian/numeric_test.exs`); the **fixed-width literal range-check is in** (`width_bounds/1` + `lit_range_error/3`, `Rian.Check`; `test/rian/check_test.exs`) — a literal outside a declared width's two's-complement range is a compile error. Open by explicit scope decision: the **generic-from-literals** case is OUT (a tvar inferred purely from literals stays `Int64`, the literal-polymorphism gap); fixed-width wrap helpers and Rust/JVM/Go contract gaps remain
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
| JS | **unsupported** — see §2a |
| BEAM | `band` + sign-fixup per op — **the ~15× cost the spike measured** |

### 2a. JS supports only the integer types it can represent natively

A JS `number` is an IEEE-754 double: integers are exact only to **2^53**. JS has exactly two integer
carriers — `number` and `BigInt` — so only three Rian integer types are JS-valid:

| Rian type | JS representation |
|---|---|
| `Int` (arbitrary precision) | `BigInt` (literals `42n`) |
| `Int53` (the portable fixed-width ceiling) | native `number` (`42`) — exact to 2^53, lowers to `i64` off-JS |
| `Int32` and smaller (`Int8/16/32`, `UInt8/16/32`) | native `number` |

**`Int64`/`Int128`/`UInt64`/`UInt128` are NOT supported on JS.** Their two's-complement-at-width contract
can't fit in a `number`, and an earlier draft lowered them to `BigInt.asIntN(64, …)`. That is rejected:
silently promoting a *bounded* fixed-width type to *arbitrary-precision* BigInt changes its type. So a
function whose signature names a wide fixed-width type is **refused by the JS emitter**
(`Rian.JS.reject_wide_int!`) and **pinned off `:js` by `Rian.Reach`** (a `:numeric` blocker). The 64-bit
wrap prelude (`Int.wrapping_add` etc.) is therefore portable across BEAM/Rust/JVM but not JS.

**Portable all-target integer code uses `Int53`** (or `Int32`): a native `number` on JS, an `i64`/`Long`
elsewhere — the integer that reaches every target. `Int` reaches `[:ex, :js]` only (the bignum gap on
Rust/JVM); wide fixed-width reaches `[:ex, :rs, :jvm]` only (no JS). Integer mode on JS is whole-program:
a module that mentions any `number`-width type emits all integers as `number`, never mixing with `BigInt`.
Because the two carriers cannot coexist, a module that mixes `Int` (BigInt) with a `number`-width type
(`Int53`/`Int32`) is **refused by the JS emitter** (`Rian.JS.reject_mixed_int_mode!`) rather than silently
demoting `Int` to a bounded `number` — the same "never change a type's precision" rule as §2a.

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
  bignum** is the real new work); add fixed-width wrap lowering (BEAM `band`/sign-fixup). **JS does NOT
  get fixed-width-64 lowering** (§2a) — wide fixed-width is rejected on JS, not `asIntN`-masked.
  The Rust-bignum and BEAM-masking emitters are each gated on their own conformance tests.
- Supersedes the numeric clauses of ADR-0034 §1 / ADR-0041 / ADR-0035; those get a "superseded by
  ADR-0064" note rather than deletion.

## Implementation status (2026-06-14)

**`Int` (arbitrary precision) is implemented where it is native — BEAM + JS** (`test/rian/numeric_test.exs`):
- **BEAM:** a native integer (bignum) — `Int` arithmetic stays exact past 64 bits (`fact(30)` ≈ 2.65e32 is
  exact); the `-spec` is `integer()`.
- **JS:** `BigInt` (literals `2n`).
- **Rust / JVM (the bignum gap, honest):** `Int` needs `i128`/`BigInteger`-style bignum, not implemented —
  so it **fails loudly** (`Capability.owned("Int")` / `Rian.JVM` raise) instead of mis-mapping to a
  bounded type, and `Rian.Reach` pins `Int` **off `:rs`/`:jvm`** (a `:numeric` blocker), so `Int` reaches
  `[:ex, :js]` and the portability gate says so.
- **Fixed-width contract:** already realized by the explicit ops — `__prim_wrapping_add` two's-complement
  wraps on the BEAM (`wrap(MAX64, 1) == MIN64`), distinct from `Int`'s exactness, both verified.

**JS integer types are implemented (§2a, `test/rian/js_test.exs` · `reach_test.exs`):**
- **JS-valid:** `Int` → `BigInt`; `Int53` / `Int32`-and-smaller → native `number`. Mode is whole-program
  (a module mentioning a `number`-width emits all integers as `number`, never mixed with `BigInt`); a bare
  literal base case (`count([]) := 0`) adopts the declared `Int53`/`Int32` return width in the checker.
- **JS-rejected:** `Int64`/`Int128`/`UInt64`/`UInt128` raise in `Rian.JS` (`reject_wide_int!`) and are
  pinned **off `:js`** by `Rian.Reach` (a `:numeric` `width_blocker`). The portable corpus that targets all
  four backends (`prelude_str`/`prelude_dict`/`selfhost_*`/stdlib) now uses **`Int53`**, not `Int64`; the
  64-bit `wrapping_*` prelude stays `Int64` and is honestly off-`:js`.

**Not yet done (the larger follow-ups the ADR itself scoped):** the **Rust/JVM bignum emitters**; making
the **default integer literal `Int`** (a breaking migration — currently still `Int64`); and making
fixed-width `Int64` *implicitly* wrap on the BEAM (the ~15× change — today the wrap is opt-in via the
`wrapping_*` ops).

**Integer-literal polymorphism (mostly landed).** A literal still *infers* `Int64`, but a **constant of
literals is width-flexible** and adopts a narrower declared/neighbour width across the contexts the
corpus needs (`Rian.Check`):

- return bodies — a bare literal, an arithmetic of literals, an `if`/`case` of literal branches, or a
  list literal (`def small_primes() Vec(Int53) := [2,3,5,7]`) — via `lit_expr_adopts?`;
- arithmetic inference — a literal operand takes a concrete-integer neighbour's width, so `13 - lvl`
  and the nested `(13 - lvl) * 10` over an `Int53` var stay `Int53` (`arith_type`);
- `div`/`rem` — operand-based, so `Int53 div Int53` is `Int53`;
- `if`/`case` branches — a literal branch adopts the non-literal branches' integer width (`branch_join`);
- generic returns — a return that doesn't use a tvar infers concretely even when that tvar is unbound,
  so `length(xs Vec(T)) Int53 forall T` recurses as `Int53` (`instantiate_ret`).

All bounded for soundness: adoption is integer-only (`1 + 2.0` stays `:unknown`), and only a *constant
of literals* adopts — a real `Int64` value is never flexible. So the **portable corpus is now `Int53`**.

A literal that adopts a fixed-width type must also **fit that width's two's-complement range**
(`width_bounds/1` + `lit_range_error/3`): `def f() Int8 := 9999` is rejected (`literal 9999 is out of
range for Int8 (-128..127)`), as are out-of-range negated literals, list elements, and `if`/`case`
branches — the same check ADR-0036 applies to subrange types. Arithmetic of literals is left to the
runtime wrap contract (a `wrapping_*` op), not range-scanned.

**Still open:** a type variable inferred *purely* from literals — `contains([1, 2, 3], 2)` makes
`T = Int64`, and no `impl Eq` for a JS-valid width can match — so the integer-generic stdlib
(`13_protocols` / `17_stdlib_eq_ord` / `18_dict_eq`) stays `Int64` and off `:js`. Closing it needs
literals to carry a flexible integer type that unifies with the bound's impl width; until then those
files are honestly reported off-`:js` by `Rian.Reach`.

## Open items

*Scope decisions on the two gaps the 2026-06-14 corpus-review debate flagged (consensus #6 — name them
explicitly rather than leave them silently open):*

- **Literal-vs-declared-width range check — IN SCOPE, bounded follow-up (soundness).** Today a literal
  that *exceeds* its declared fixed-width adopts the width unchecked (`def f() Int8 := 9999` and
  `Int8 := x + 9999` both type-check; `Vec(Int8) := [9999]` too). This is the one place the otherwise
  conservative checker *accepts* something it can prove wrong. Decision: add a bounds check to
  `literal_adopts?`/`lit_expr_adopts?` (reject a literal provably outside the declared width's range);
  not blocking, but tracked as a real soundness item, not "acceptable."
- **Generic type-var inferred purely from literals — OUT OF SCOPE for now (documented limitation).**
  `contains([1,2,3], 2)` makes `T = Int64` from the literals, so no `impl` for a JS-valid width matches,
  and integer-generic stdlib stays `Int64` (off `:js`, honestly reported by Reach). Closing it needs
  literals to carry a flexible integer type that unifies with the bound's impl width — a larger
  inference change. Until then portable all-target code uses `Int53` explicitly (see the
  literal-polymorphism section above).
- **Default-precision ergonomics on Rust** — when can an `Int` provably fit `i64` (small-loop induction
  vars, indices) so we emit native `i64` not a bignum? A range/escape analysis, future.
- **Mixed-width arithmetic** — `Int + Int64`: require an explicit cast (no implicit coercion, ADR-0035),
  or define a promotion rule? Lean explicit.
- **Float** — this ADR is integers only; `Float64`/`Float32` IEEE-754 semantics are already portable and
  unchanged.
