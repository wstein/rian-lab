# ADR-0071 — Python backend (the reach target)

**Status:** Accepted (direction) · **Not yet implemented** — debated 2026-06-14; the first new backend after the original ADR-0026 six. Sequenced *before* ADR-0072 (Swift).
**Refines:** ADR-0049 (backend tiers — adds Python as a new tier beyond the original JVM/Rust/Go/BEAM/JS/WASM list), ADR-0026 (target list).
**Refs:** ADR-0041 (target model), ADR-0042 (dispatch), ADR-0047 (Prim layer / stdlib), ADR-0050 (Core IR is the emitter spine), ADR-0058 (reachability + `@targets`), ADR-0064 (portable numeric contract), ADR-0069 (interpolation / `__prim_*_to_string`), ADR-0035 (no hidden control flow), ADR-0034 (no `nil`; `Option(T)`), ADR-0000 (honesty: the matrix matches the emitters).
**Owners:** Liam Davis (dynamic-target emitter) · Maya Lin (tiers) · Samir Patel (conformance / type hints) · Kira Neri (CI parity / Reach honesty) · Elena Rostova (numerics/prims) · Mira (totality) · Rachel Okafor (PM)

## Context

Rian's four targets reach web (JS), systems (Rust), enterprise+Android (JVM/Kotlin), and the
BEAM. The conspicuous unreached audience is **data science / ML / scripting / education / Django-Flask
web** — the largest population Rian does not touch. Python is the single highest-reach backend
available, and mechanically it is the *cheapest*: a dynamic, GC'd, runtime-dispatch target — the
shape of the existing `Rian.JS` emitter (ADR-0049 Tier 1).

`Rian.Crystal`/`Julia` were assessed as smoother *engineering* adds but *narrower* audiences (niche /
scientific-computing, the latter overlapping Python). Python is the inverse: modest, well-understood
emitter work for an audience that moves the needle. The team decided to build **Python first, Swift
second** (ADR-0072), not in parallel, so neither bleeds into the unfinished self-hosting Stage 3.

These are **audience targets, not performance targets** — Rust already owns speed. The generated
Python is optimized for **readability and byte-identical correctness**, not throughput.

## Decision

### 1. Placement — a GC'd, dynamically-typed, JS-shaped target

Python sits in the same quadrant as JS and the BEAM: garbage-collected, no ownership model, runtime
dispatch. The emitter is a fresh module `Rian.Python` consuming the **typed Core IR** (`Rian.Core`,
ADR-0050) — never the surface tuples — and closely mirrors `Rian.JS`. Capabilities (`val`/`iso`/`tag`/
`ref`) are **erased for codegen** exactly as on BEAM/JS/JVM: Python is GC'd, so the Rust-specific
signature lowering does not apply.

### 2. Construct mapping

| Rian | Python | Note |
|------|--------|------|
| `Int` (arbitrary precision) | `int` | **native bignum — `Int` *reaches* Python** (unlike Rust/JVM) |
| `Int53` / `Int8…128`, `UInt*` | `int` | one runtime type; the **wrap contract** is enforced by masking (§4) |
| `Float64/32` | `float` | (`Float32` is `float` at runtime; width is a Rian-side check) |
| `Bool` | `bool` | |
| `Char` | `str` (length-1) | a codepoint's single character (ADR-0036 / ADR-0069) |
| `String` | `str` | UTF-8 |
| `Symbol` (atom) | `str` | atoms have no Python analog → interned-string convention (as on Rust/JS/JVM) |
| `Vec(T)` | `list` | |
| `Dict(K,V)` | `dict` | |
| `Option(T)` | explicit `Some`/`None` classes | **not** `Optional[T]`/`None` — Rian rejects `nil` (ADR-0034); see *Open items* |
| `type T := A \| B(Int)` | a base class + `@dataclass(frozen=True)` subclasses | dispatched by `match`/`case` (§3) |
| `struct P(x Int)` | `@dataclass(frozen=True)` | |

### 3. Functions, dispatch, and totality — `match` with a trailing raise

A multi-clause function lowers to a single Python `def` whose body is a `match` over the parameter
tuple (Python **≥3.10**, decision below), one `case` per clause with structural/class patterns and
`if`-guards for `when`. Sum variants are class patterns (`case B(n):`). Because **Python does not
enforce `match` exhaustiveness** — a fall-through silently yields `None` — the emitter appends a
**`case _: raise`** encoding the totality that `Rian.Exhaustiveness` already proved (the same trailing
-throw discipline as `Rian.JVM`). `if` is an expression-position ternary; operators map directly; local
calls are calls.

**Python floor: ≥3.10.** `match`/`case` is the clean structural fit; the pre-3.10 `isinstance`
fallback is uglier *and* loses structural checking. 3.10 shipped 2021 and 3.8/3.9 are EOL/near-EOL, so
a single `match`-based lowering with a documented floor beats carrying two pattern lowerings.

### 4. Numerics — the broadest non-BEAM Reach, via masking

Python `int` is arbitrary precision, so unlike every other non-BEAM target Python can implement the
**full** numeric core *correctly*:

- `Int` reaches Python natively (native bignum) — closes the gap that pins `Int` off Rust/JVM.
- Fixed-width values fit in `int`; the **two's-complement wrap contract** (ADR-0064) is honored by
  **masking** at each width — `wrap_u(n, bits) = n & (2**bits - 1)`, `wrap_i(n, bits)` with sign
  fixup. The explicit 64-bit overflow prims (`__prim_wrapping_add`/`saturating_add`/`checked_add`)
  lower to these masks — so **Python reaches the overflow ops that pin off `:js`** (which cannot
  represent 64 bits). These are the same prim shape Elena already wrote for JS, with masks instead of
  refusal.

Net: Python's numeric reach is the most complete after the BEAM. Correctness-first; the mask cost is
irrelevant for a reach target (Tomás).

### 5. Type hints + mypy in conformance (the dynamic-typing safety net)

Python is the one target where "it type-checked in Rian" does **not** imply the *output* is
type-correct — dynamic typing erases Rian's guarantees at the boundary. So the emitter emits **type
hints** from the types Rian already carries on every Core node (params, returns, sum fields,
collection element types), and the conformance harness runs **`mypy --strict`** alongside execution.
The hints are *load-bearing*, not cosmetic: they are the only mechanism by which the Python
conformance test catches what the other four targets catch for free.

### 6. Reach (`:py`) — honest blockers

Add `:py` to the `Rian.Reach` `@targets` vocabulary. Python is the **most permissive** target after
the BEAM:

- **Reaches:** `Int`, all fixed widths, the 64-bit overflow ops (§4), `Char`, `String`, `Symbol`,
  `Vec`/`Dict`, sums/structs, `Option`/`Result`.
- **Pins off `:py`:** host FFI (Erlang/Elixir `:mod.fun` / `Mod.fun`), `ref`/`&mut` (not in the
  portable core), concurrency (native-per-target, not a Rian surface). `Float64` *interpolation* stays
  a compile error per ADR-0069 §6 (Python `repr` diverges — `repr(1e-7) == "1e-07"` — from the other
  targets, same deferral).

### 7. Verification

A `Rian.Python` conformance corpus shells out to `python3` (ubiquitous in CI — the deciding advantage
over Swift) and `mypy`, mirroring the existing `node`/`rustc`/`kotlinc` harnesses, plus a fixpoint
diff against the reference behaviour. `python3`-in-CI makes `:py` reach **verifiable on day one**,
satisfying the gate-honesty contract (ADR-0058/0000).

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — JS-shaped Python emitter | 5/5 | lowest-marginal-cost new backend; reuses the dynamic-dispatch shape |
| 3 — `match` + trailing raise, ≥3.10 | 4/5 | clean fit; −1 for the version floor (acceptable) |
| 4 — masking → full numeric reach | 4/5 | makes Python the broadest non-BEAM numeric target; −1 for per-prim mask work |
| 5 — type hints + mypy in conformance | 4/5 | the only honesty net for a dynamic target; −1 for the extra harness |
| 6 — `:py` Reach | 5/5 | most permissive after BEAM; blockers follow the established pattern |

## Consequences

- **Drift tax (CLAUDE.md):** a fifth emitter — every new Core node now needs a Python arm or it
  raises the usual `Unsupported`. Mitigated by the JS-clone shape.
- **Biggest audience unlocked:** share one typed, tested logic core into a Python data pipeline *and*
  the JS frontend *and* a Rust service — Rian's thesis, aimed at its largest possible crowd.
- **CI gains a `python3`/`mypy` dependency** for the conformance lane (already implies Python present).

## Open items

- **`Option(T)` representation.** Faithful `Some`/`None` classes (preserves the no-`nil` contract,
  ADR-0034) vs idiomatic `Optional[T]`/`None` (Pythonic but reintroduces the `nil` Rian rejects).
  Lean: faithful classes; revisit if Python-idiom pressure is strong.
- **`Float32`/fixed-width are runtime-erased.** Python has one `int` and one `float`; width/precision
  are Rian-side checks, not runtime distinctions. Document that Python is value-faithful, not
  representation-faithful, for sub-`Int` widths.
- **Async/await.** Out of scope — concurrency is native-per-target (ADR-0057), not a Rian surface.

## Alternatives considered

- **No type hints (plain dynamic output).** Rejected: removes the only conformance safety net for a
  dynamically-typed target; a type error the other backends catch would ship silently.
- **Support Python 3.8+ via `isinstance` dispatch.** Rejected: two pattern lowerings to maintain, and
  the fallback loses `match`'s structural checking; 3.8/3.9 are EOL/near-EOL.
- **Pin fixed-width-overflow off `:py`.** Rejected: Python's bignum makes faithful masking *correct*
  (unlike JS), so refusing it would forfeit a real Python advantage (the 64-bit overflow ops).
