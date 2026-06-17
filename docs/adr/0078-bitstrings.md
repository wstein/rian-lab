# ADR-0078 — Bitstrings/binaries: a BEAM-first surface for `<<seg::spec, …>>`

**Status:** Accepted (direction)
**Implemented:** partial — **Stage 1 (construction)** and **Stage 2 (patterns)** shipped: lexer
(`<<`/`>>`/`::`), `Rian.Pratt` (expr + `parse_pat`), `Core.EBitstr`/`PBitstr`, `Rian.Check`,
`Rian.PatternLower` (refutable), `Rian.Beam` native bitstring construction + pattern forms +
`Rian.Lower`'s Elixir-text path; `Rian.Decl` arity/clause splitters count `<<>>` depth; Rust/JS/JVM
raise `Unsupported` and `Rian.Reach` pins bitstring functions (body **or** clause-head) BEAM-only.
**Stage 3 (transpiler emit)** is not yet done.

> **Exhaustiveness is conservative (Stage 2).** A bitstring pattern is refutable to the Maranget gate
> (`{:wild, true}`), so `<<c, rest::binary>>` + `<<>>` is **not** recognized as covering all binaries —
> a bitstring-matching function needs an explicit `_`/catch-all clause (or `@partial`). Sound (no
> silent partiality, ADR-0035) but less ergonomic than Erlang; binary-aware coverage is a Stage-3/
> future refinement, relevant because the lexer idiom often omits the catch-all.
**Refs:** ADR-0041 (`String` is a UTF-8 binary — bitstrings are the general form), ADR-0075/0076
(transpiler/roundtrip — the motivating consumer), ADR-0035 (no hidden control flow), ADR-0050 (typed
Core IR), ADR-0000/0058 (reach honesty: the matrix matches the emitters).
**Owners:** Arthur Pendelton (parser/Core) · Maya Lin (emitters) · Kira Neri (reach honesty) · Samir Patel (rigor)

## Context

The Elixir→Rian transpiler (ADR-0075/0076) cannot roundtrip `lib/rian/*.ex` because Rian has **no
bitstring surface at all** — no lexer token, no parser, no Core node, no emitter. Yet `lib/rian`'s
lexer/string/char code is built on Erlang bitstring matching and construction
(`<<c::utf8, rest::binary>>`, `<<cp::utf8>>`): bitstrings are the single largest `TODO_PORT` bucket
(~90 of ~235 markers when transpiling `lib/rian`), and they gate every string-heavy module.

ADR-0041 already commits `String` to be a UTF-8 binary; a bitstring is its general form. So this is
filling in a construct the language implicitly depends on, not adding a novel one.

## Decision

**Adopt an Elixir-compatible bitstring surface, lower it natively on the BEAM, and honestly pin it off
the other targets until faithful bit-level lowering exists.**

### Surface (Elixir-compatible)

```
<<seg, seg, …>>            # construction (expression) and pattern (clause head / case)
seg  := value
      | value :: spec      # spec is a single specifier or `-`-joined list
spec := utf8 | utf16 | utf32 | binary | bytes | bitstring | integer | float
      | size(n) | <int>    # a bare integer size, e.g. `x::8`
```

Matching Elixir's spelling is deliberate: the transpiler maps Elixir `{:<<>>, …}` straight across,
minimizing transpiler work, and it is the syntax the porting audience already knows. **Scope of the
first implementation is the subset `lib/rian` actually uses:** `::utf8`, `::binary`, a bare byte, and
a sized integer (`::n` / `::size(n)`); other specifiers parse but may be rejected by the checker until
needed.

### Targets — BEAM-native, others gated (the honesty bar)

- **BEAM:** native — `Rian.Beam` emits Erlang bitstring abstract forms (`{:bin, …}` /
  `{:bin_element, …}`) for both construction and patterns. This is the real, tested path.
- **Rust / JS / JVM:** **not lowered initially.** Faithful bit-level semantics (endianness, sizes,
  UTF validation, sub-byte alignment) differ per target and are a large, separate effort. The emitters
  raise `Unsupported`, and **`Rian.Reach` pins any bitstring-using function off `:rs`/`:js`/`:jvm`**
  (BEAM-only) — the matrix reports what the emitters actually lower (same principle as bare atoms /
  maps, ADR-0000). This keeps the gate honest rather than green-lighting code the emitters reject.

This BEAM-only stance is acceptable because the motivating consumer (round-tripping the *compiler's*
Elixir source, which targets the BEAM) needs exactly the BEAM path.

### Staging (incremental, each a committed, verified slice)

1. **Construction** — lexer (`<<` `>>` `::`), `Rian.Pratt` primary, `Core.EBitstr`, `Rian.Check`
   (result type `String`/`Binary`; conservative on segments), `Rian.Beam` construction forms; other
   emitters `Unsupported`; `Rian.Reach` blocker. Tests + roundtrip delta.
2. **Patterns** — `Rian.Pratt.parse_pat`, `Core.PBitstr`, `Rian.PatternLower` (segment binders; a
   variable-`binary` tail is an open match), `Rian.Exhaustiveness` (a bitstring pattern is refutable —
   never "covers everything"), `Rian.Beam` pattern forms.
3. **Transpiler emit** — `Rian.Transpile` lowers Elixir `{:<<>>, …}` (expr + pattern) to the new
   surface, replacing the `TODO_PORT` markers (`transpile.ex:806` + the pattern catch-all).

## Consequences

- The lexer/string-heavy `lib/rian` modules become roundtrip-able (the dominant `TODO_PORT` bucket
  clears) — but only on the BEAM path, which is exactly what the transpiler roundtrip exercises.
- Rian gains a permanently BEAM-pinned construct; the reach matrix stays honest (ADR-0000). Lifting it
  onto Rust/JS/JVM later is a follow-on ADR (faithful bit-level lowering), not a prerequisite here.
- This is a self-hosting-sensitive change (the compiler's own lexer/parser/Core gain bitstring
  support) — every slice is gated on the `selfhost_*`/`compose_*` fixpoint tests staying green.

## Open items

- **Cross-target lowering** (Rust `&[u8]`/`bytes`, JS `Uint8Array`/`DataView`, JVM `ByteArray`) — a
  later ADR; until then, BEAM-only and reach-pinned.
- **Specifier coverage** — endianness/`float`/`utf16`/`utf32`/unit are parsed-but-deferred until a
  real consumer needs them; the checker rejects an unsupported specifier rather than mis-lowering.
