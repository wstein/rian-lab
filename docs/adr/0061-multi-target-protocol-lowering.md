# ADR-0061 — Multi-target protocol & generics lowering: native-per-target dispatch, target-relative coherence

**Status:** Proposed (design) · BEAM dispatch is **shipped** (ADR-0042 MVP — runtime guarded dispatcher + `check_bounds`); this ADR specifies the **Rust** (static traits) and **JS** (runtime dispatch) lowerings and **reconciles the coherence rules** across the three so one source compiles everywhere it is allowed to. **Foundation landed** (§1): structured protocol/impl IR is preserved (`prog.protocols`/`prog.impl_decls`) and the BEAM runtime-dispatch desugaring is tagged on `IR.Func` (`dispatch: :dispatcher` for the dispatcher, `:impl` for the impl methods) so the Rust path drops its text and the JS emitter skips the dispatcher (regenerating its own). The **JS dispatcher (§3) is shipped** — `Rian.JS` regenerates the dispatcher from the protocol IR with JS-native guards (`typeof` for primitives, tagged-array head for sums); verified in node, including the `Eq`/`Ord` stdlib (`sort`/`contains`/`maximum`). The **Rust trait path (§2) is shipped** — `Rian.Lower.rust_protocols` emits a fresh `trait Rian<P>` + `impl Rian<P> for <rust(T)>` (receiver → `&self`), bounded generics become `fn f<T: RianEq + …>`, and protocol-method calls rewrite to UFCS (`RianEq::eq(..)`); rustc-verified for primitives (Eq/Ord) and sums (Show-for-Expr with a `case` body). **Target-relative coherence (§5) is shipped** — the runtime-discriminator rule (`Int64`+`Char` share a guard) now applies only to runtime-dispatch targets (`:ex`/`:js`, and unannotated = all); a Rust-only `@targets(rs)` module allows both. The orphan rule is enforced implicitly: protocols/impls are processed per scope, so an `impl` must be co-located with its protocol. **Remaining:** struct protocol dispatch on JS raises `Unsupported` (gate via `@targets` once a JS-excluding set is declared); composing several `Decl.compile` units into one Rust module needs type-def dedup (`to_rust` emits all types per unit); dynamic (`dyn`) dispatch.
**Refs:** ADR-0042 (protocols/impls/bounded generics — what this lowers), ADR-0057 (concurrency is native-per-target — the *principle* this borrows: a feature can be one source, three native mechanisms), ADR-0058 (configurable `@targets` — coherence is gated by the declared target set), ADR-0049 (backend tiers — Rust/JS are Tier-1), ADR-0050 (one typed core IR — emitters consume it), ADR-0041 (target model — per-target representation), ADR-0047 (stdlib written over protocols — the first multi-target consumer), ADR-0055 (capability on the protocol-method receiver — survives `dyn` erasure), ADR-0035 (no hidden control flow)
**Owners:** Maya Lin (multi-target/emitters) · Elena Rostova (Rust traits / coherence) · Arthur Pendelton (bounds / type-directed dispatch) · Kira Neri (determinism) · Samir Patel (coherence rigor) · Liam Davis (ergonomics) · Rachel Okafor (PM)

## Context

Protocols, bounded generics (`forall T: Eq + Ord`), and the first stdlib over them
(`List.contains`/`sort`/`maximum`) have all landed — **BEAM-only**. The implementation desugars a
`protocol` into a **runtime guarded dispatcher** (`Rian.Protocol`): one `def m` clause per impl,
selecting on the first argument's runtime *shape* (`is_integer`/`is_binary`, a sum's constructor tag
via `element/2`, a struct's `:__struct__`). A bounded generic just calls that dispatcher;
`Check.check_bounds` enforces the bound *statically* at the call site, then erases it.

This is at odds with Rian's whole reason to exist — **the same source on BEAM, Rust, and JS**
(ADR-0057). Two problems block the other targets:

1. **The dispatch *mechanism* is not portable.** The BEAM dispatcher is a runtime type-test. Rust
   dispatches on **static type** (monomorphization / vtables) and has no runtime type to test; JS has
   no static types and *must* dispatch at runtime. Emitting "the dispatcher" verbatim fits neither.
2. **The coherence *rules* are not the same per target.** Rian's MVP rejects "two impl types that
   share a runtime dispatch guard" (`Int64` and `Char` both `is_integer`). That ambiguity is real on
   BEAM/JS (runtime dispatch) and **non-existent on Rust** (`i64` and `char` are distinct static
   types). Conversely Rust enforces the **orphan rule** and forbids **overlapping impls**, which Rian
   does not yet check. A single set of rules is either too strict for Rust or too loose for BEAM/JS.

## Decision

### 1. Protocol dispatch is **native-per-target** (the ADR-0057 move, applied to dispatch)

One Rian `protocol`/`impl`/bounded-generic source lowers to **each target's native dispatch
mechanism**, not a single emitted artifact:

| Target | Dispatch | What is emitted |
|---|---|---|
| **BEAM** | runtime, first-arg shape | the guarded dispatcher `def m` + mangled `impl_*` funcs (shipped) |
| **JS** | runtime, first-arg shape | a dispatcher function switching on `typeof`/tag (mirrors BEAM) |
| **Rust** | **static**, type-directed | a `trait` + `impl`s; bounded generics become `fn f<T: P>(…)`; rustc dispatches |

Like concurrency (ADR-0057), the *concept* is shared and the *mechanism* is idiomatic per host. The
typed core IR (ADR-0050) already carries `protocols`/`impls`/`bounds`; each emitter consumes them
differently rather than consuming a pre-desugared dispatcher. (Concretely: `Rian.Protocol.expand` —
which desugars to BEAM `def`s — becomes BEAM-and-JS-specific; the Rust emitter reads the protocol IR
directly and emits traits.)

### 2. Rust — protocols are traits (the idiomatic, type-directed mapping)

- `protocol P do def m(self Self, …) R end` → `trait P { fn m(&self, …) -> R; }`. The `Self`
  receiver maps to `&self` (receiver capability per ADR-0055 picks `&self`/`&mut self`/`self`).
- `impl P for T do …` → `impl P for <rust(T)> { … }`, with `T` mapped through `Rian.Capability`
  (`Int64 → i64`, a sum → its `enum`, a struct → its `struct`).
- `def f(x T, …) R forall T: Eq + Ord` → `fn f<T: Eq + Ord>(x: …, …) -> R`. Monomorphized by rustc;
  **no dispatcher is emitted**.
- **Fresh, Rian-namespaced traits — not `std` traits.** A Rian `protocol Eq` lowers to a Rian trait
  (e.g. `RianEq`), **not** `std::cmp::PartialEq`. Reusing `std` traits is more idiomatic but drags in
  `std`'s coherence (orphan rules against `std` impls, blanket impls) and forces Rian's method
  *names/signatures* to match `std`'s exactly. The fresh-trait choice keeps Rian's surface authoritative
  and its coherence self-contained; std-trait *bridging* (a blanket `impl std::cmp::PartialEq for T where T: RianEq`) is a future opt-in, not the default.

### 3. JS — a runtime dispatcher (mirrors BEAM)

JS has no static types, so dispatch is runtime, structurally identical to BEAM: a dispatcher function
selects the impl by the first argument's shape — `typeof x === "bigint"` (Int64), `=== "string"`
(String), `=== "boolean"` (Bool), the tagged-array head (a sum, ADR-0049 `["Ctor", …]`), or
`__struct__`. A bounded generic is a plain function; the bound is **erased** at runtime (it was
checked statically). This reuses the BEAM dispatcher *strategy* with JS guard expressions.

### 4. Bounds are a static check everywhere; a real bound only on Rust

`Check.check_bounds` (shipped) is the **portable** gate — it runs once, target-independent, and
rejects an unsatisfiable concrete instantiation on every target. Additionally, **on Rust** the bound
becomes a real `T: P` trait bound that rustc re-verifies (defense in depth + enables monomorphization).
On BEAM/JS the bound is erased after the check (runtime dispatch needs no static bound).

### 5. Coherence is **target-set-relative** (the ADR-0058 reconciliation — the heart of this ADR)

There is no single coherence rule set; there is a **lattice of rules, selected by the module's
`@targets`**. A module is checked against the **union** of the rules its declared targets require, so
a program that passes is valid on *every* target it claims:

| Rule | Required by | Why |
|---|---|---|
| **One `impl` per `(protocol, type)`** | all | unambiguous on every dispatch model |
| **Method-set matches the protocol** | all | the contract |
| **Orphan rule** (an `impl` lives in the protocol's *or* the type's defining module) | all (Rust *needs* it) | Rust rejects foreign-trait-for-foreign-type; adopting it universally keeps Rust lowering always legal. **New constraint** — Rian is single-program today. |
| **No two impl types share a runtime discriminator** (`Int64` + `Char` → both `is_integer`) | `:ex`, `:js` only | runtime dispatch can't tell them apart; on Rust `i64`/`char` are distinct static types, so this is *not* a Rust error |
| **No overlapping impls** | `:rs` (subsumed by one-per-`(proto,type)` above) | rustc forbids overlap |

Consequences of target-relativity:

- A module `@targets(ex, rs, js)` (the portable default) must satisfy **all** rows — including the
  runtime-discriminator rule — so `impl Eq for Int64` **and** `impl Eq for Char` together is a
  **portability error** there, even though Rust alone would accept it.
- A module `@targets(rs)` (Rust-only) is **not** bound by the runtime-discriminator rule — it may
  carry both `Int64` and `Char` impls, because Rust dispatches statically.
- This is the same shape as ADR-0058's FFI gating: *the constraints follow from which targets you
  picked.* Coherence stops being one global rule and becomes a reachability-gated contract.

## Ratings

| Decision | Rating | Note |
|---|---|---|
| Dispatch native-per-target (runtime BEAM/JS, static Rust) | 5/5 | the only mapping that is idiomatic on all three; mirrors ADR-0057 |
| Rust protocols → **fresh** Rian-namespaced traits | 4/5 | safe (no `std` coherence entanglement); less idiomatic than std-trait reuse, which is a future opt-in |
| JS dispatcher mirrors the BEAM dispatcher | 5/5 | both runtime; near-identical guard logic, low new surface |
| Bounds: portable static check + a real Rust trait bound | 5/5 | one gate everywhere; rustc as defense-in-depth |
| **Coherence target-set-relative (ADR-0058)** | 4/5 | the reconciliation; powerful but adds a rule-selection step the checker must thread through `@targets` |
| Adopt the **orphan rule** universally | 4/5 | a genuinely new constraint (Rian is single-program today); the price of always-legal Rust |
| Reuse `std::cmp` traits on Rust directly (rejected default) | 2/5 | idiomatic but orphan/blanket-impl hazard, and forces Rian method shapes onto `std`'s |
| One global coherence rule set (rejected) | 2/5 | either too strict for Rust or too loose for BEAM/JS |

## Consequences

- **The multi-target promise is restored for the new stack.** `List.sort forall T: Ord` written once
  runs on BEAM (dispatcher), JS (dispatcher), and Rust (`fn sort<T: Ord>`), so ADR-0047's stdlib is
  genuinely portable, not a BEAM artifact.
- **`Rian.Protocol.expand` is reframed** as the BEAM/JS (runtime-dispatch) path; the Rust emitter
  grows a trait/impl path that reads the protocol IR directly. The core IR (ADR-0050) is the shared
  contract; the *desugaring* is no longer target-agnostic.
- **Coherence checking moves into the `@targets`-aware gate** (ADR-0058): `Rian.Reach`/the checker
  selects the rule set from a module's declared targets. The runtime-discriminator rule becomes
  conditional rather than always-on.
- **Rian gains the orphan rule** — a real new restriction on where `impl`s may live, paid so that
  every well-formed program lowers to legal Rust.
- **`@targets(ex)` stays an escape hatch**: a BEAM-only module may use BEAM-only dispatch shapes
  (and skip Rust-coherence), exactly as a BEAM-only module may use OTP FFI (ADR-0057/0058).

## Open items

- **`Self` and associated types.** This ADR maps `Self` as the receiver only; protocols with
  `Self`-returning methods (`def add(a Self, b Self) Self`) and associated types are a further Rust
  mapping question (return-position `Self`, generic associated types).
- **Dynamic dispatch / `dyn`.** A protocol-typed *value* (`x P`) → Rust `Box<dyn P>` / `&dyn P`,
  interacting with the receiver capability (ADR-0055). The MVP is static (monomorphized) bounds; the
  `dyn` path is deferred.
- **`std`-trait bridging.** Whether/when a Rian `Ord` should also `impl std::cmp::Ord` so Rian values
  drop into Rust's `sort`/`BTreeMap` — a future opt-in with its own coherence design.
- **JS BigInt vs number for the receiver test.** `Int64 → bigint`, but `Int53 → number` (ADR-0049):
  the JS dispatcher's numeric guard must match the chosen representation per function.
- **Generic monomorphization blow-up on Rust.** Heavily-bounded generics over many types monomorphize
  widely; whether to offer a `dyn`-backed mode for code size is a perf decision, not a correctness one.
- **Migration order.** JS dispatcher first (reuses the BEAM strategy, low risk), then the Rust trait
  path (new surface); the coherence rule-selection lands with whichever target needs it first.
