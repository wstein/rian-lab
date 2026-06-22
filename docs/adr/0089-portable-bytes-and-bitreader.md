# ADR-0089 — Portable `Bytes` type + `BitReader`/`BitWriter` API (the portable surface for byte data)

**Status:** Accepted (direction)
**Implemented:** no — a *surface + prelude* decision. The portable `Bytes` type and the
`BitReader`/`BitWriter` ops are specified here; the prelude implementation + per-target lowering land
under **ADR-0078's consensus steps** (gated by ADR-0087, sequenced behind self-host parity ADR-0063).
No code lands on the strength of this ADR alone.
**Refines:** ADR-0078 (bitstrings — `<<…>>` stays the BEAM-first surface; this ADR owns the *portable*
slice that its consensus pointed to), ADR-0047 (portable prelude/stdlib — the new type + API live here),
ADR-0049 §5a (frozen portable core / target budget — the subset enters across all Tier-1 *together* or
not at all).
**Refs:** ADR-0041 (`String` is a UTF-8 binary — `Bytes` is the un-validated general form), ADR-0064
(portable numeric contract — integer field widths/endianness), ADR-0061 (`Fn` lowering — the reader's
closures), ADR-0086 §2/§3 (reach honesty gate; depth-before-breadth), ADR-0085 (anti-sprawl — no
per-target escape hatch), ADR-0087 (generative reach-honesty harness — the `:rs`/`:js`/`:jvm` gate),
ADR-0065 (surface stability — why this is a *library*, not new syntax), ADR-0000 (honesty).
**Owners:** Arthur Pendelton (parser/Core) · Maya Lin (emitters) · Kira Neri (reach honesty) · Samir Patel (rigor) · Elena Rostova (Rust/numerics) · Marcus Chen (supply chain) · Rachel Okafor (PM/sequencing)

## Context

ADR-0078 adopted Erlang's `<<seg::spec, …>>` bitstring surface — the **gold standard** for binary
parsing: direct pattern-matching on bit-fields, protocol-shaped, the most intuitive surface there is for
network/binary engineering. But it earns its place via *one* forcing function — round-tripping the
compiler's own BEAM source (the Elixir→Rian transpiler, ADR-0075/0076) — and it is a **BEAM idiom**:
sub-byte fields, endianness-in-spec, UTF validation baked in, destructuring patterns. Its ADR-0078
debate (2026-06-22) concluded that only the **byte-aligned subset** is portable, and that the lowering
mechanism should be a shared prelude `BitReader`/`BitWriter`, not bespoke per-emitter cursor codegen.

That leaves an open question this ADR answers: **what is the *portable* surface for byte data?** A
second `<<…>>`-style bit-literal syntax was rejected — special syntax must earn its weight (ADR-0065),
and the industry pattern for *portable* byte work is a **type + reader/writer API**, not literal syntax:
Rust `&[u8]`/`Vec<u8>` + `bytes`/`Cursor`, JS `Uint8Array`/`DataView`, JVM `ByteBuffer`. Gleam — the
closest precedent (BEAM **and** JS, like us) — keeps the `<<>>` spelling but **restricts it to a portable
subset**; Crystal/Zig use a `Bytes`/`[]u8` *library*, no bit syntax. The dominant portable pattern is a
type + API.

## Decision

**Adopt a portable `Bytes` type and a `BitReader`/`BitWriter` prelude API (ADR-0047) as the portable
surface for byte data. Keep `<<…>>` as the BEAM-first / transpiler / binary-parsing surface; its
byte-aligned subset lowers *through* this same API, so there is one runtime and one reach story.
Sub-byte `<<…>>` stays BEAM-only by design (ADR-0078 P5). Introduce no new bit/bytes literal syntax.**

### 1. `Bytes` — a portable byte-sequence type

A portable type in the prelude (ADR-0047), byte-granular by construction, lowering to each target's
native byte container:

| Target | `Bytes` lowers to |
|---|---|
| BEAM | `binary` (a byte-aligned bitstring) |
| Rust | owned `Vec<u8>` / borrowed `&[u8]` (capability-driven, ADR-0070/0055) |
| JS | `Uint8Array` |
| JVM | `ByteArray` (read via `ByteBuffer`) |

`String` (ADR-0041) is the **UTF-8-validated** refinement of `Bytes`; `Bytes` is the un-validated general
form. Conversions are explicit (`Bytes.to_utf8 : Bytes -> String | DecodeError`).

### 2. `BitReader`/`BitWriter` — a zero-alloc cursor API

The reader is a **monomorphized `(Bytes, offset)` cursor** — no heap, no allocation on the hot path
(Elena's constraint; the speed argument that chose this over `bitvec`). Written once in Rian over
`Bytes` (ADR-0047), each emitter lowers the type + ops to native:

```
BitReader.new(b Bytes) BitReader
.take(r BitReader, n Int53)  (Bytes, BitReader) | Underflow   # n bytes + advanced cursor
.u8 / .u16 / .u32 / .u64(r)  (IntN, BitReader)  | Underflow   # big-endian DEFAULT
.u16_le / .u32_le / …                                          # little-endian variants, explicit
.utf8(r)                     (Char, BitReader)   | DecodeError  # validates, like BEAM ::utf8
.rest(r)                     Bytes                              # remaining tail

BitWriter.new() BitWriter
.bytes(w, b Bytes) / .u8(w, n) / .u16(w, n) / .u16_le(w, n) / .utf8(w, cp Char) …
.finish(w) Bytes
```

Reads return a `Result` (`Underflow`/`DecodeError`) — no silent truncation (ADR-0035). **Endianness is
explicit and big-endian by default** (matching the BEAM ADR-0078 default); a `_le` op is the only way to
get little-endian, so a portable program can never depend on host endianness (Samir's correctness bar).

### 3. `<<…>>`'s byte-aligned subset lowers through this API

The byte-aligned `<<…>>` subset (`::binary`, `::utf8`, byte-multiple integer sizes, `binary-size(len)`)
**desugars to / lowers through** `BitReader`/`BitWriter`, so the two surfaces share one runtime and one
reach predicate. Sub-byte `<<…>>` (bit units, non-byte-multiple sizes) has **no portable form** and
stays BEAM-only by design (ADR-0078 P5) — a permanent reach pin, not "not yet."

### 4. No new literal syntax now; `b"…"` deferred

A portable byte-string literal `b"GET "` (Rust/Python precedent — maps to `&[u8]`/`Uint8Array`/`binary`
trivially and reads far better than `<<71, 69, 84, 32>>`) is **deferred**: cheap and idiomatic, but
added only when a concrete consumer needs byte constants, re-entering under ADR-0065 (surface stability)
+ ADR-0049 §5a — never speculatively. A *competing* `<<…>>`-style portable bit syntax is rejected
outright: two overlapping syntaxes are a "which do I use?" cliff and a doubled drift tax (ADR-0086 §3).

### 5. Portable across all Tier-1 together, gated by the harness

Per ADR-0049 §5a, this subset is **not** a unilateral widening: `Bytes`/`BitReader` either lands across
**all** Tier-1 targets together (BEAM/Rust/JS — JVM as it matures) or it stays honestly pinned. A
single-target escape hatch is the Haxe `#if` sprawl we refuse (ADR-0085 §7). `Rian.Reach` claims
`:rs`/`:js`/`:jvm` for a `Bytes`/`BitReader`-using function **only** once the ADR-0087 generative harness
proves the emitted code compiles + runs on that toolchain; until green, honestly pinned (under-claim
beats a lie, ADR-0000).

### 6. No external dependency

The prelude `BitReader`/`BitWriter` is `std`-only on every target (no `bitvec`, no `bytes` crate) —
Marcus's trust-surface bar (the same reason ADR-0049 §3 refused a `purs` dependency). The byte-aligned
cursor is small enough to own.

## Ratings

| Decision | Rating | Note |
|---|---|---|
| Portable byte surface = a `Bytes` type + reader/writer API, **not** new syntax | 5/5 | matches every target's native idiom; one construct, one reach story |
| Keep `<<…>>` as the BEAM-first / gold-standard binary surface; byte-aligned subset lowers through the API | 5/5 | preserves the transpiler round-trip that justified ADR-0078; no surface duplication |
| Zero-alloc `(Bytes, offset)` cursor, big-endian default + explicit `_le` | 4/5 | the speed + correctness bar; −1 endianness is still a footgun the checker must police |
| `b"…"` byte literal deferred until a real consumer | 3/5 | right call; −2 we may want it sooner than we think for protocol code |
| Reject a competing portable bit *syntax* | 5/5 | avoids the "two syntaxes" cliff and the doubled drift tax |
| Portable across all Tier-1 together, harness-gated; no external dep | 5/5 | the §5a + ADR-0085 anti-sprawl discipline, applied |

## Consequences

- Rian gains a **portable** byte story without a new syntax: protocol/codec code that today is BEAM-pinned
  `<<…>>` can be written against `Bytes`/`BitReader` and reach Rust/JS (and JVM) — the first portable
  binary-handling surface.
- `<<…>>` is now explicitly **two things**: the gold-standard BEAM/transpiler surface (full power,
  sub-byte) *and* a byte-aligned subset that is sugar over the portable API. The reach split from
  ADR-0078's consensus (`:bitstring_subbyte` permanent pin vs byte-aligned class) is the mechanism.
- The portable prelude (ADR-0047) grows a `Bytes`/`BitReader`/`BitWriter` module — written once in Rian,
  lowered per target, conformance-tested against the BEAM as oracle (ADR-0078 step 4).
- No widening of the frozen portable core slips in unilaterally (ADR-0049 §5a): the subset is specified
  once and each Tier-1 emitter implements it or stays pinned.

## Open items

- **Exact API shape** — the op set above is indicative; the final names/signatures are fixed when the
  prelude module is authored (ADR-0078 step 5). Bit-level (sub-byte) reader ops are deliberately absent
  (BEAM-only).
- **`b"…"` literal trigger** — what concrete consumer promotes it from deferred to scheduled (likely the
  first portable wire codec needing byte constants).
- **`Bytes` capability surface** — owned `Vec<u8>` vs borrowed `&[u8]` follows the standard
  `val`/`iso`/`tag` lowering (ADR-0055/0070); confirm the reader cursor borrows (`&[u8]`) so it stays
  zero-alloc under a `val` parameter.
- **Comprehensions** — `for <<x <- s>>` (ADR-0078 out-of-scope) over the byte-aligned subset is a
  `BitReader` loop; revisit when comprehensions (ADR-0079) and this API both exist.
- **JVM** — `ByteBuffer` mirrors the subset but JVM is Tier 2 (ADR-0049); it joins when its conformance
  lane is green, not before.
