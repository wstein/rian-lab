# ADR-0025 — Memory capabilities: `val` / `iso` / `ref` / `tag`

**Status:** Accepted (§1–§3 implemented; §4 — the move-on-last-use clone-elision optimization — **proposed, not yet implemented**)
**Implemented:** §1–§3 yes — `Rian.Capability` (Rust parameter lowering + BEAM use-once linearity + `beam_legal!/1` rejecting `ref`); `test/rian/capability_test.exs`. The owned↔borrow **coercion** at the emit seams (§4.1) is implemented in `Rian.Lower` (~22 `.clone()`/`.to_vec()` sites against ~162 borrow sites). The **clone-elision optimization** (§4.2) is proposed — there is no liveness pass today. *(Retroactively documented 2026-06-14: this foundational decision was referenced by ADR-0034/0035/0041/0046/0048/0055 but never had its own file — the corpus-review honesty pass gave it one. §4 added 2026-06-21.)*
**Refs:** ADR-0034 (capabilities × types; flow narrowing), ADR-0055 (capabilities through dispatch / opaque), ADR-0035 (no hidden control flow), ADR-0041 (per-target representation), ADR-0057 (concurrency/FFI native-per-target), ADR-0070 (proposed: make `val` the inferred default), ADR-0000 (charter — the capability model is half of Rian's distinctive pairing)
**Owners:** Elena Rostova (Rust ownership) · Arthur Pendelton (type system) · Samir Patel (linearity/totality) · Maya Lin (multi-target) · Kira Neri (no hidden coercion) · Rachel Okafor (PM)

## Context

Rian lowers the *same source* to ownership-checked Rust and to the GC'd BEAM/JS/JVM (ADR-0000, ADR-0050).
Rust needs to know, per parameter, whether a value is borrowed, owned/moved, or mutably borrowed —
information Rust normally carries in `&`/owned/`&mut` + lifetimes. Rather than make the author write
Rust lifetimes (which mean nothing on the BEAM), Rian carries that intent in **one capability
annotation per signature position**, and each target derives what it needs from it. This is half of
Rian's distinctive pairing (the other half is *inferred* portability, ADR-0058): **ownership-checked
Rust without hand-written lifetimes, from a single annotation that also gives the BEAM use-once
linearity.**

## Decision

### 1. Four capabilities, one per signature position

| Capability | Meaning | Rust parameter | BEAM/GC targets |
|---|---|---|---|
| **`val`** | shared, read-only borrow (the common case) | `&[T]` / `&T` (or by-value if `Copy`) | ordinary value; reusable |
| **`iso`** | isolated, owned/linear — **use-once** | owned `Vec<T>` / `T` (moved) | **use-once** linearity-checked |
| **`ref`** | unique mutable borrow | `&mut T` | **rejected on the BEAM** (`beam_legal!`) |
| **`tag`** | shared, by-reference tag (read-only, never owned) | `&T` over the owned form | ordinary value |

(See `Rian.Capability.rust_param/2` for the exact Rust spellings, ADR-0067 for how an `abstract`'s
capability rides its base, and ADR-0055 for capabilities on a protocol-method receiver.)

### 2. `iso`/`ref` are use-once on the BEAM; `ref` is BEAM-illegal

The linearity check (`Rian.Capability`, ADR-0029-era) counts uses of an `iso`/`ref` binding; using one
more than once is a compile error — the BEAM analog of Rust's move-checking. `ref` (`&mut`) has no
sound BEAM representation (no in-place mutation in the immutable runtime), so `beam_legal!(:ref)`
**rejects it on the BEAM target**, a compile error rather than a silent value-copy (ADR-0041 §2).

### 3. Capabilities are a *Rust+BEAM* concern; JS/JVM lower to value semantics

On JS/JVM there is no ownership to check, so a capability lowers to an ordinary value binding. This is
sound **only because Rian's surface is return-based** (no in-place mutation operator), so `ref` never
changed observable behaviour off-Rust — it only shaped the Rust signature. `Rian.JS`/`Rian.JVM` lock
this value-lowering with a test so a future in-place-mutation primitive can't silently break the
assumption.

### 4. Owned↔borrow coercion at the seams, and the move-on-last-use optimization

The §1 mapping is **borrow-by-default**: `val` params are `&[T]`/`&str`/`&T` (zero-copy), so the
hot path — passing data *in* — never copies. Ownership only flips at a small set of **seams**,
where a *borrowed* value must reach an *owned* position.

**§4.1 — Coercion (implemented).** At each seam the emitter inserts a coercion rather than thread
a lifetime — the whole point of §1 is to avoid surface lifetimes (`Rian.Lower`):

- a return derived from a borrowed input → `.clone()` (a borrow of a temporary cannot escape);
- an owned `Vec<T>` materialised from a borrowed `&[T]`/`&Vec<T>` → `.to_vec()`;
- an owned value fed to a `&[T]`/`&str` parameter → a `&`-borrow;
- a closure capturing a value → `.clone()` (or, for closure-bearing enum fields, an `Rc<dyn Fn>`
  whose "clone" is a refcount bump, ADR-0061).

This keeps the Rust **lifetime-elidable** (single input borrow, owned outputs) at the cost of a
copy at the seam. The copy is **free for `Copy` types** (`i64`/`Bool`/`Char`) and **O(n) for
`String`/`Vec<T>`** — so a large-heap clone inside a hot loop is a real cost, and the only one
worth optimising. Note that **many seam clones are semantically required**: a function returning a
value built from a borrowed input genuinely needs an owned result, exactly as hand-written Rust
would — the portable value model (BEAM copies/shares; JS GCs) is what the clone pays for, not
backend waste.

**§4.2 — Move-on-last-use (proposed, the high-value optimization).** The emitter currently clones
**unconditionally** at a seam because deciding whether a *move* would suffice needs liveness — and
there is no such pass today (the only "dead" analysis is for dead *clauses*). Decision: add a
**local, intraprocedural last-use pass** that, when the value being cloned is **dead after the
clone** (its final use in the clause), emits a **move** instead of `.clone()`/`.to_vec()`. This is
*far* cheaper than borrow inference (no aliasing/lifetime reasoning — just "is this the variable's
last mention on this path"), and it eliminates the bulk of avoidable `String`/`Vec` copies: an
`iso x := transform(input); x` should move `x` out, not clone it. Secondary, lower-priority
mitigations on the same axis: **`Cow<T>`** for maybe-owned returns (borrow when unchanged), and
**wider `Rc`/`Arc`** for shared immutable data (cheap refcount clone — the closure path already
does this).

**Soundness bar (non-negotiable):** the optimization may only turn a clone into a move when the
source binding is provably unused afterward on *every* path — a false move is a use-after-move
compile error from `rustc`, which is the backstop, but the pass must not rely on it. Verify with
the existing `rustc --test` honesty lane (`reach_rust_honesty_test`): every elided-clone program
must still compile and produce identical results to its non-optimised form (and to the BEAM/JS
build). The optimization is **observable-behaviour-preserving** — it changes only the number of
allocations, never the result.

## Rationale

- **One annotation, two payoffs** (Rust ownership + BEAM linearity) — the novel thing the charter
  (ADR-0000 §4) names.
- **No lifetimes in the surface** — the author states *intent* (`iso`/`val`), the Rust emitter derives
  the borrow form.
- **Fail loud, never silent** — an illegal `ref` on the BEAM is a compile error, not a quiet copy.
- **Correct-and-portable first, peak-perf later** (§4) — borrow-by-default makes the common path
  zero-copy and lifetime-elidable; the residual seam clones are correct everywhere, and the
  move-on-last-use pass recovers the avoidable ones without giving up the no-surface-lifetimes
  property. The trade is explicit, not hidden.

## Consequences

- Every parameter currently carries an explicit capability — which is a surface tax on targets that
  ignore it (JS/JVM). **ADR-0070 proposes making `val` the inferred default**, so only `iso`/`ref`/`tag`
  need spelling; this ADR documents the model, 0070 the ergonomics.
- The capability is part of the signature the type checker and Reach see (ADR-0034/0058).

## Open items

- **Default `val`** — deferred to ADR-0070 (corpus-review consensus #5).
- **Capabilities across an FFI boundary** — `@external` restricts params to `val`/`tag` (ADR-0068),
  since linearity can't be enforced in foreign code.
- **Move-on-last-use clone elision (§4.2)** — proposed, not yet implemented. Needs a local
  last-use/liveness pass over the clause body in `Rian.Lower`, gated by the `rustc --test` honesty
  lane and an "identical results to the non-optimised + BEAM/JS builds" check. Highest-value Rust
  perf work; `Cow`/wider-`Rc` are follow-ons on the same axis. (Surfaced 2026-06-21.)
