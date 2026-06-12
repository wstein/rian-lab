# ADR-0037 — Binary Wire-Format Records: `@wire` structs with derived `decode`/`encode`

**Status:** Accepted (direction) · **Refines:** ADR-0033 (adds the `Bytes` builtin and the `@wire` annotation)
**Refs:** ADR-0032 (surface decouples from target representation), ADR-0034 (error sets), ADR-0035 (errors are values; no hidden control flow), ADR-0029 (dot qualifier)
**Owners:** Maya Lin (emitters) · Chloe Bennett (parser) · Arthur Pendelton (compilers) · Rachel Okafor (PM)

## Context

Rian needs to parse and emit **binary wire formats** — network packets, file headers, on-disk
records. The naive request ("packed records", à la Pascal `packed record` / Rust `#[repr(packed)]`)
is the wrong frame: packing exposes *in-memory layout*, which has **no meaning on the BEAM** (terms
are boxed; an Elixir struct is a tagged map) and violates ADR-0032's "surface decouples from target
representation." The real need is **serialization**: a declared byte layout with derived
encode/decode, not control over how the value sits in RAM.

The BEAM already owns the best-in-class answer — bitstring matching (`<<magic::32, len::16>>`).
Rust has no equivalent language construct, so its codec must be *generated*. That asymmetry is the
design's center of gravity, and it is exactly Rian's "same source, two idiomatic shapes" thesis.

Two scoping decisions were taken up front:

- **Declarative over raw bitstrings.** A `@wire` annotation on a `struct` derives a symmetric
  `decode`/`encode` pair for *both* targets, rather than exposing BEAM `<<>>` syntax that has no
  idiomatic Rust shape. Portability and encode/decode symmetry win for v1.
- **Byte-aligned only.** Fields sit on byte boundaries (fixed-width ints, floats, byte blocks,
  length-prefixed bytes, nested wire structs). Sub-byte bit fields (`Bits(n)`) are deferred — they
  are BEAM-native but force bit-shifting/masking codegen on Rust.

The primitive vocabulary is already largely present: `Int8…128` / `UInt8…128` exist in the
capability matrix ([`Rian.Capability`](../../lib/rian/capability.ex), `UInt32` → Rust `u32`), and
`Vec(UInt8)` is already used ([04_capabilities.rian](../../examples/rian/04_capabilities.rian)).
This ADR adds only `Bytes` and the `@wire` machinery on top.

## Decision

Annotate a `struct` with `@wire` to derive a byte-exact binary codec.

```elixir
@wire(big_endian)                      # endianness is the annotation's argument
struct Header(magic UInt32, flags UInt8, len UInt16, body Bytes(len))
```

| Aspect | Decision | Rationale |
|---|---|---|
| **Trigger** | `@wire(endianness)` annotation on a `struct` | Reuses the existing annotation surface (`@partial`); the struct stays an ordinary in-memory record — `@wire` only *adds* the codec and constrains field types. |
| **Endianness** | `@wire(big_endian)` (default, = network order) / `@wire(little_endian)`; struct-level | Big-endian is the network/file default. Per-field override is deferred (open items). |
| **`Bytes` builtin** | added: BEAM `binary()`, Rust `Vec<u8>` (`iso`) / `&[u8]` (`val`) — capability-driven like `String` | A first-class byte sequence; `Bytes` and `Vec(UInt8)` are interchangeable. |
| **Field types** | fixed-width `Int*`/`UInt*`, `Float32/64` (IEEE-754), `Bool` (1 byte, `0`/`1`), `Bytes(n)`, trailing `Bytes`, nested `@wire` structs | The closed set that has an unambiguous byte image on both targets. |
| **Length-prefixed** | `body Bytes(len)` — `len` is an **earlier numeric field** of the same struct | Covers the dominant length-prefixed case without a sub-language; forward reference only. A trailing `Bytes` (no size) greedily takes the remainder and is allowed **only** as the last field. |
| **Derived `decode`** | `Type.decode(bytes Bytes) Type \| DecodeError` — **strict** (exact consumption); plus `Type.decode_prefix(bytes Bytes) {Type, Bytes} \| DecodeError` for streaming | Decode is partial → an ADR-0035 error value, never an exception. `decode_prefix` returns the unconsumed tail for composition. |
| **Derived `encode`** | `value.encode() Bytes` — **total** | Every well-typed wire value has a valid byte image (fixed-width fields always fit), so `encode` cannot fail and carries no error type. The asymmetry (total encode, partial decode) is a feature. |
| **`DecodeError`** | a sealed error set (ADR-0034): `Truncated(needed, got) \| TrailingBytes(extra) \| BadLength(field Symbol)` | Structured, exhaustive-checkable failures; honors "errors are values." |

### Validation (compile-time)

- A `@wire` struct's fields must **all** be wire-serializable types from the set above; a non-wire
  field (function, open map, arbitrary `Vec(T)`) is a compile error.
- A `Bytes(len)` length source must be a **numeric field declared earlier** in the same struct.
- An unsized `Bytes` is legal **only** as the final field.

## Lowering — same source, two idiomatic shapes

For `@wire(big_endian) struct Header(magic UInt32, flags UInt8, len UInt16, body Bytes(len))`:

| | BEAM (idiomatic bitstrings) | Rust (generated, `byteorder`-style) |
|---|---|---|
| `decode` | one `<<magic::big-unsigned-32, flags::8, len::big-unsigned-16, body::binary-size(len), rest::binary>>` match → `%Header{}`; `rest != <<>>` → `TrailingBytes` | cursor over `&[u8]`: `u32::from_be_bytes` / `u16::from_be_bytes` / slice `body`, bounds-checked (`.ok_or(Truncated)?`); leftover → `TrailingBytes`; returns `Result<Header, DecodeError>` |
| `encode` | build `<<m::big-unsigned-32, f::8, l::big-unsigned-16, b::binary>>` | push `to_be_bytes()` / bytes into a `Vec<u8>` |

The in-memory `Header` stays each target's ordinary struct (`%Header{}` / `struct Header`) — the
byte image lives **only** in the codec, so ADR-0032's representation-decoupling is preserved. This
is why `@wire` is the right answer to "packed records": it gives byte-exact serialization without
ever exposing target memory layout.

## Consequences

- **`Bytes` builtin** joins the primitive vocabulary (ADR-0033 amendment): BEAM `binary()`, Rust
  `Vec<u8>`/`&[u8]` (capability-driven, mirroring `String`).
- **`@wire` is orthogonal to `struct`.** The decorated type is a normal record everywhere; the
  annotation only derives the codec and tightens field-type checking. No new runtime type.
- **ADR-0035 honored:** `decode` is total and explicit (`Type | DecodeError`); `encode` is total.
  No exceptions on either target; the only failures are reified `DecodeError` values.
- **Lands in slices** (as ADR-0033/0036): (a) the **codec emitter** (BEAM bitstring + Rust
  byteorder generation) and the `Bytes` capability entry are implementable/testable now against
  hand-built IR; (b) this ADR + the example are the authoritative surface now
  ([11_wire_formats.rian](../../examples/rian/11_wire_formats.rian)); (c) `@wire`/`Bytes(len)`
  **parsing** lands with the declaration parser (ADR-0031 Stage 0.1).

## Open items

- **Sub-byte bit fields** (`Bits(n)`, non-byte-aligned) — the deferred granularity; BEAM-native,
  needs bit-shift/mask codegen on Rust.
- **Per-field endianness** for mixed-endian formats (`@little flags UInt16`).
- **Counted collections** — `Vec(T, count: n)` / arrays of `n` records; v1 has only `Bytes(len)`.
- **Tagged unions on the wire** — a discriminant field (`tag UInt8`) selecting a `type` variant
  (enum-on-the-wire), with exhaustiveness over the tag.
- **Computed/checksum fields** — fields whose value derives from others on encode and validate on
  decode (CRC, length auto-fill).
- **Alignment/padding** fields, and zero-copy `decode` borrowing from the input on Rust (`&[u8]`).
