# ADR-0025 — Memory capabilities: `val` / `iso` / `ref` / `tag`

**Status:** Accepted
**Implemented:** yes — `Rian.Capability` (Rust parameter lowering + BEAM use-once linearity + `beam_legal!/1` rejecting `ref`); `test/rian/capability_test.exs`. *(Retroactively documented 2026-06-14: this foundational decision was referenced by ADR-0034/0035/0041/0046/0048/0055 but never had its own file — the corpus-review honesty pass gave it one.)*
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

## Rationale

- **One annotation, two payoffs** (Rust ownership + BEAM linearity) — the novel thing the charter
  (ADR-0000 §4) names.
- **No lifetimes in the surface** — the author states *intent* (`iso`/`val`), the Rust emitter derives
  the borrow form.
- **Fail loud, never silent** — an illegal `ref` on the BEAM is a compile error, not a quiet copy.

## Consequences

- Every parameter currently carries an explicit capability — which is a surface tax on targets that
  ignore it (JS/JVM). **ADR-0070 proposes making `val` the inferred default**, so only `iso`/`ref`/`tag`
  need spelling; this ADR documents the model, 0070 the ergonomics.
- The capability is part of the signature the type checker and Reach see (ADR-0034/0058).

## Open items

- **Default `val`** — deferred to ADR-0070 (corpus-review consensus #5).
- **Capabilities across an FFI boundary** — `@external` restricts params to `val`/`tag` (ADR-0068),
  since linearity can't be enforced in foreign code.
