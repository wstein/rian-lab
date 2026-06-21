# ADR-0085 — Haxe-style dynamic backends (Lua, PHP, Neko) — candidate targets

**Status:** Proposed (exploratory) · **Candidates only — NOT adopted.** No `Rian.Lua`/`Rian.Php`/`Rian.Neko` emitter exists; `:lua`/`:php`/`:neko` are **not** in the `Rian.Reach` `@targets` vocabulary; each is subject to the ADR-0049 §5a admission gate **and** the target budget. Debated 2026-06-21. Sequenced *after* the Tier-1 self-host work (ADR-0063) and the already-proposed Python/Swift backends (ADR-0071/0072).
**Implemented:** no — direction-of-exploration only.
**Refines:** ADR-0049 (backend tiers — adds three *candidate* targets beyond the list, governed by its §5a target budget), ADR-0026 (target list).
**Refs:** ADR-0041 (target model), ADR-0042 (dispatch), ADR-0050 (Core IR is the emitter spine), ADR-0058 (reachability + `@targets`; **CI parity**), ADR-0064 (portable numeric contract), ADR-0071 (Python — the dynamic-target *template* this reuses), ADR-0034 (`Option(T)`, no `nil`), ADR-0069 (interpolation), ADR-0000 (honesty: the matrix matches what is *verified*).
**Owners:** Maya Lin (emitters/tiers) · Arthur Pendelton (dispatch / sum lowering) · Kira Neri (CI parity / Reach honesty) · Elena Rostova (numerics) · Marcus Chen (supply chain / toolchains) · Rachel Okafor (PM)

## Context

[Haxe](https://haxe.org) is the standing proof that **one typed source can lower to many dynamic
targets in production**: its compiler ships idiomatic emitters to JS, **PHP**, **Lua**, **Neko**,
Python, C++, C#, Java, and HashLink from a single front-end. Three of those — **Lua**, **PHP**, and
**Neko** — are the *dynamic, GC, scripting/web* triad Rian has no story for, and Haxe has already
walked the construct-mapping for each (sum types → tagged structures, exhaustiveness without a host
checker, atoms → strings, capabilities irrelevant under GC). Borrowing that *demonstrated reach* is
the cheap part: all three are the **same shape as Rian's existing dynamic targets** (JS, and Python
in ADR-0071), so each is one Core arm (ADR-0050) with no new type machinery — the Python lowering is
the template, not a fresh design.

The expensive part is **discipline, and this ADR's whole job is to keep it.** ADR-0049 §5a already
cites Haxe as the *cautionary tale*: ~10 backends with **no admission gate**, so the common standard
library frayed toward the lowest common denominator and per-target escape hatches multiplied until
"write once" became marketing. Adding the very targets that lesson came from is therefore only honest
if it is done *under* that lesson, not in spite of it. So this ADR borrows Haxe's **target reach as
proof-of-viability** while explicitly refusing Haxe's **sprawl**: the three enter as **Tier-3
candidates**, counted against the §5a *target budget*, graduating only on sustained green conformance,
and **never widening** the frozen portable core (§5a rule 3) — they ride the existing portable surface
or pin off, honestly.

These are **audience/embedding** targets, not performance targets (Rust owns speed):

- **Lua** — the *embedding* reach: game engines, OpenResty/nginx, Redis, Neovim, and any host that
  embeds a small VM. "Drop validated Rian logic into a Lua-scriptable host."
- **PHP** — the largest *legacy-web* install base. "Share the same typed, tested domain rules with a
  PHP monolith" — the web analogue of the Swift/Kotlin mobile pitch (ADR-0072).
- **Neko** — Haxe's own tiny *reference VM* (Nicolas Cannasse). Its value here is not audience but
  **cheapness of verification**: a minimal dynamically-typed bytecode VM is the fastest dynamic host
  to stand up in CI, so it is the natural *conformance canary* for the dynamic lowering before
  committing to the heavier Lua/PHP toolchains.

## Decision

### 1. Placement — dynamic, GC, capabilities erased (the Python/JS family)

All three sit with **BEAM/JS/Python**: garbage-collected, dynamically typed at runtime, so the
`val`/`iso`/`tag`/`ref` capabilities are **erased for codegen** (no Rust borrow machinery; `iso`→value,
`ref`→a value binding, sound while the Rian surface is return-based — the same argument as JVM/Swift,
ADR-0049/0072). Each emitter (`Rian.Lua`/`Rian.Php`/`Rian.Neko`) consumes the **typed Core IR**
(ADR-0050) — no new fork — and is structurally a re-skin of `Rian.JS`/the Python emitter (ADR-0071),
which is what keeps the marginal cost a re-skin and not a rewrite.

### 2. Construct mapping

| Rian | Lua (5.3+) | PHP (8.x) | Neko | Note |
|------|-----------|-----------|------|------|
| `Bool` / `Char` / `String` | `boolean` / int / `string` (bytes) | `bool` / int / `string` (bytes) | `bool` / int / `string` (buffer) | `Char` = codepoint int; `String` is bytes (codepoints via the host utf8 lib) |
| `Symbol` (atom) | `string` | `string` | `string` | no atom analog (as on JS/Python/JVM) |
| `Vec(T)` / `Dict(K,V)` | sequence `table` / hash `table` | `array` (list) / `array` (assoc) | `array` / object/hash | one host collection, two uses |
| `type T := A \| B(Int)` | `{tag="b", _0=…}` table | tagged class / `["tag"=>…]` | tagged object | a runtime-tagged structure (§3) |
| `struct P(x Int)` | field `table` | class / assoc `array` | object | named fields |
| `Option(T)` | tagged `none`/`some(v)` | tagged | tagged | **not** host `nil`/`null` — Rian rejects `nil` (ADR-0034) |
| `Fn(A,R)` | closure | `Closure` | closure (`function`) | captures natively (GC) |

### 3. Sums & dispatch — runtime-tagged, with a trailing `raise` (the inverse of Swift)

A `type` lowers to a runtime-**tagged structure**; a multi-clause function lowers to a tag/shape
dispatch with **one arm per clause and a trailing `raise`** for the impossible case — because **none
of these hosts check exhaustiveness** (the exact opposite of Swift's compiler-checked `switch`, where
the trailing default is dead code — ADR-0072 §3). This is identical to the Python lowering (ADR-0071
§3): Rian's `Rian.Exhaustiveness` gate is the *only* exhaustiveness authority, and the trailing throw
is the honest runtime backstop, never a silent fallthrough. `if` is an expression (or lowers to one);
operators map directly.

### 4. Numerics — three different honest floors (this is a feature, not a gap)

The triad does **not** share a numeric story, and ADR-0064's per-target reach is built to say so:

| Target | Native integer | `Int` (arbitrary precision) | Notes |
|--------|----------------|------------------------------|-------|
| **Lua** | 64-bit integer subtype (5.3+); doubles only (53-bit safe) on 5.1/5.2/LuaJIT | **pins off `:lua`** (no stdlib bignum) | `Int53` native everywhere; fixed widths 8–64 via masking on 5.3+; pre-5.3 caps at `Int53` — **record the floor** |
| **PHP** | 64-bit `int` (platform) | **pins off `:php`** unless GMP/BCMath assumed (non-core extension) — default: pins off | `Int53`/`Int64` native; fixed-width wrap via masking |
| **Neko** | **31-bit** tagged `int` + `float` | pins off | Weakest: `Int53`/`Int64` exceed 31 bits → would need `float` (lossy >2³¹) → **pin off**; Neko is a *structural/dispatch* target, not a numeric one |

So the portable all-target integer `Int53` (ADR-0064) reaches **Lua and PHP** but **not Neko** (31-bit
ceiling); `Int` (BEAM/JS-only bignum) reaches **none** of the three; fixed widths reach Lua/PHP via
masking. The 64-bit overflow ops (`__prim_wrapping_add`, …) lower to the host's masking arithmetic on
Lua/PHP and **pin off Neko**. Float *interpolation* stays deferred per ADR-0069 §6 (each host's float
`tostring`/`Std.string` diverges from Rust/JS digits).

### 5. Reach (`:lua`/`:php`/`:neko`) — does not exist until the interpreter runs in CI

Per ADR-0058/0000, a target's reach is whatever is **mechanically verified**, so **none of these three
join the `Rian.Reach` vocabulary on the strength of this ADR.** A `:lua`/`:php`/`:neko` reach may be
*claimed* only once the conformance harness compiles-and-runs that host in CI (the `:rust`/`:js`
pattern). Until then there is no `@targets` entry to set and no reach to assert — asserting one would
be the precise gate-lie ADR-0000 forbids. When a host *is* wired in, its reach is the honest
intersection of §2/§4: e.g. `:lua` reaches `Int53`/fixed-widths/`Vec`/`Dict`/sums/structs/`Option`/
`Result`/`Fn` and pins off `Int`, host FFI, `ref`, and concurrency.

### 6. Verification & sequence — Neko first (cheapest), then Lua, then PHP

Each emitter's conformance shells out to its interpreter (`neko`, `lua`, `php`) to compile+run the
portable-core corpus, mirroring the `rustc`/`node`/`kotlinc` harnesses, plus a fixpoint diff. Sequence
by **cost-to-verify**, not audience size:

1. **Neko** — smallest VM, fastest CI stand-up; proves the dynamic tag-dispatch lowering end-to-end as
   a *canary* (structural only — numerics pin off at 31 bits).
2. **Lua** — broad embedding reach; the first *numerically useful* dynamic candidate (`Int53`+).
3. **PHP** — largest audience; same lowering, heaviest toolchain.

No two are built in parallel (two half-emitters bleed into the unfinished self-hosting Stage 3 —
ADR-0071/0072's sequencing argument). Each stays a Tier-3 candidate until its conformance lane is
green on every commit (§5a rule 2 — graduate on sustained green, never the reverse).

### 7. Anti-sprawl — the §5a contract applies in full, by name

This ADR is adopted *under* ADR-0049 §5a, not as an exception to it:

1. **Target budget (§5a rule 4).** Three candidates is an explicit cost decision, made here, with the
   standing order of business unchanged: **self-host the BEAM+JS core first** (ADR-0063); these wait.
   They are *candidates*, so they cost roadmap attention, not LCD width, until one graduates.
2. **The portable core stays frozen (§5a rule 3).** None of Lua/PHP/Neko may *widen* what "portable"
   means — no new prelude op or intrinsic is added "because it's easy on Lua." They ride the existing
   portable surface or pin off (§4 is full of honest pins). This is the single rule whose violation
   *is* the Haxe failure mode.
3. **Enter at Tier 3, graduate on green (§5a rules 1–2).** A candidate that cannot pass the
   portable-core conformance matrix on a host stays Tier 3, honestly — exactly as JVM stays Tier 2.

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — dynamic/GC, capabilities erased; re-skin of the JS/Python emitter on Core | 5/5 | low marginal cost; no new type machinery |
| 3 — runtime-tagged sums + trailing `raise` (hosts don't check exhaustiveness) | 5/5 | identical to Python (ADR-0071); Rian's gate is the authority |
| 4 — three divergent numeric floors (Lua/PHP 64-bit, Neko 31-bit, `Int` pins off all) | 5/5 | the per-target reach honesty (ADR-0064) working as designed |
| 5 — no `:lua`/`:php`/`:neko` reach until the interpreter runs in CI | 5/5 | the ADR-0000/0058 precondition; non-negotiable |
| 6 — Neko-first by cost-to-verify, then Lua, then PHP, never in parallel | 4/5 | right ordering; −1 because Neko's audience is ~nil (it earns its slot purely as a CI canary) |
| 7 — adopted *under* §5a (target budget + frozen LCD + Tier-3 entry) | 5/5 | borrows Haxe's reach, refuses Haxe's sprawl — the whole point |
| Three *candidate* backends at all, pre-self-host | 3/5 | honest as exploration; −2 because resourcing is real and self-hosting outranks them |

## Consequences

- **Reach breadth, on paper, with honest gates.** Rian gains a credible "scripting + legacy-web +
  reference-VM" story (the Haxe niche) without the Haxe outcome — every claim is gated on CI parity
  and counted against the target budget.
- **Drift tax (CLAUDE.md).** Up to three more emitters; each new Core node needs a Lua/PHP/Neko arm.
  Mitigated by all three being re-skins of the JS/Python dynamic lowering — the cheapest emitter
  family Rian has.
- **Neko earns its slot as a canary, not an audience.** It is the cheapest dynamic host to verify, so
  it de-risks the Lua/PHP lowering first; nobody ships production Neko.
- **`Int` still reaches only BEAM/JS** (ADR-0064); the triad adds `Int53`/fixed-width reach on Lua/PHP
  and (structurally) Neko — never bignum.
- **Concurrency stays BEAM-only** (ADR-0031/0057): every dynamic candidate gets the sequential core.

## Open items

- **Interpreters in CI** — the blocking precondition for *any* reach claim (§5). Wire `neko` first,
  then `lua` (pick the 5.3+ floor), then `php`; only then add the `@targets` entries and drop the
  `@tag` no-op lanes.
- **Lua version floor.** 5.3+ buys native 64-bit integers (so the fixed-width contract holds); 5.1/
  5.2/LuaJIT cap at `Int53`. Decide whether to support pre-5.3 at a reduced reach or require 5.3+.
- **PHP bignum.** Whether to assume GMP/BCMath (→ `Int` could reach `:php`) or treat them as absent by
  default (→ `Int` pins off, the conservative honest default). Lean: absent by default.
- **Neko's numeric ceiling.** Confirm the 31-bit `int` width and decide whether `Int53` may lower via
  `float` (lossy, rejected by default) or strictly pins off (default).
- **String/codepoint host libs.** Lua `utf8`, PHP `mb_*`, Neko's string API — the per-host `Char`/
  `Str` prim lowering (ADR-0047), kept codepoint-exact (ADR-0036).

## Alternatives considered

- **One ADR per target (à la Python/Swift).** Rejected: Lua/PHP/Neko share a *single* rationale (the
  dynamic Haxe triad) and a *single* lowering shape, so three ADRs would triplicate the same decision.
  When one graduates toward Tier 2, it earns its own focused ADR then.
- **Adopt now / add to `@targets` and verify later.** Rejected: an unexecuted reach claim is the
  matrix-lies-about-the-emitter failure ADR-0000/0058 exist to prevent — and adopting *Haxe's* targets
  without Haxe's-lesson discipline would be the §5a anti-pattern by name.
- **Skip Neko (no audience).** Rejected: Neko is the cheapest dynamic host to stand up in CI, so it
  pays for itself as the conformance canary that de-risks Lua/PHP — its value is verification cost, not
  reach.
- **Lower `Option(T)` → host `nil`/`null`.** Rejected (default): ergonomic on each host but breaks
  Rian's no-`nil` contract (ADR-0034); use a tagged `none`/`some`, as on every other target.
