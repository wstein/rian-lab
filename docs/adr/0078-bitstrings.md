# ADR-0078 — Bitstrings/binaries: a BEAM-first surface for `<<seg::spec, …>>`

**Status:** Accepted (direction)
**Implemented:** partial — **Stage 1 (construction)** and **Stage 2 (patterns)** shipped: lexer
(`<<`/`>>`/`::`), `Rian.Pratt` (expr + `parse_pat`), `Core.EBitstr`/`PBitstr`, `Rian.Check`,
`Rian.PatternLower` (refutable), `Rian.Beam` native bitstring construction + pattern forms +
`Rian.Lower`'s Elixir-text path; `Rian.Decl` arity/clause splitters count `<<>>` depth; Rust/JS/JVM
raise `Unsupported` and `Rian.Reach` pins bitstring functions (body **or** clause-head) BEAM-only.
**Stage 3 (transpiler emit)** shipped: `Rian.Transpile` lowers Elixir `{:<<>>}` construction
*and* patterns to the new surface, falling back to a `TODO_PORT` marker for any segment/specifier
outside the supported subset. **Stage 4** shipped: `"prefix" <> rest` string-prefix *patterns* lower
to `<<"prefix", rest::binary>>` (a `<>`-chain of literal prefixes ending in a binder), and a
string-literal segment now emits the Erlang `{:string, …}` value (not a nested `{:bin}`, which was an
illegal pattern). Together these took `lib/rian` transpiler markers **250 → 151**. Residual
follow-up: **bitstring comprehension generators** (`for <<x <- s>>`) — out of scope (comprehensions).

> **Exhaustiveness is conservative (Stage 2).** A bitstring pattern is refutable to the Maranget gate
> (`{:wild, true}`), so `<<c, rest::binary>>` + `<<>>` is **not** recognized as covering all binaries —
> a bitstring-matching function needs an explicit `_`/catch-all clause (or `@partial`). Sound (no
> silent partiality, ADR-0035) but less ergonomic than Erlang; binary-aware coverage is a Stage-3/
> future refinement, relevant because the lexer idiom often omits the catch-all.
**Refs:** ADR-0041 (`String` is a UTF-8 binary — bitstrings are the general form), ADR-0075/0076
(transpiler/roundtrip — the motivating consumer), ADR-0035 (no hidden control flow), ADR-0050 (typed
Core IR), ADR-0000/0058 (reach honesty: the matrix matches the emitters).
**Owners:** Arthur Pendelton (parser/Core) · Maya Lin (emitters) · Kira Neri (reach honesty) · Samir Patel (rigor) · Elena Rostova (Rust/numerics) · Marcus Chen (supply chain/toolchains) · Rachel Okafor (PM/sequencing)

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
  later ADR; until then, BEAM-only and reach-pinned. **The Rust slice of this is debated below** (the
  consensus: a *byte-aligned portable subset* over `Vec<u8>`, sub-byte stays BEAM-pinned) — see
  "Debate — Rust bytes/bitvec lowering."
- **Specifier coverage** — endianness/`float`/`utf16`/`utf32`/unit are parsed-but-deferred until a
  real consumer needs them; the checker rejects an unsupported specifier rather than mis-lowering.
- **Sizes are LITERAL only** — `::n` / `::size(<int>)`. A *dynamic* size (`::size(len)` over a bound
  variable, the `<<len::8, body::binary-size(len)>>` idiom) is **not yet parsed** — it raises a clear
  parse error, not a mis-lowering. The round-trip target (`lib/rian`, e.g. the UTF-8 lexer) uses only
  fixed specs, so this is unblocking for now; add variable sizes when a consumer needs them.
- **Formatter: `-`-joined specs render loosely.** `Rian.Format` is token-stream + context-free, so the
  spec separator `-` in `binary-size(4)` formats as `binary - size(4)` (re-lex- and parse-equivalent,
  just not tight). The single-specifier forms (`::8`, `::utf8`, `::binary`, `::size(n)`) format tight
  (`<<x::8, rest::binary>>`, snapshot-locked in `test/rian/fixtures/format/bitstrings.*`). Tightening
  `-` lists needs a CST group with a spec-aware renderer — a later refinement.

## Debate — Rust bytes/bitvec lowering for `<<…>>` (recorded 2026-06-22)

The trigger: `Rian.Reach`'s `bitstr_blocker` pins every bitstring-using function `[:rs, :js, :jvm]`
as **one** construct class. The recurring suggestion is "Rust would need a bytes/bitvec-style
lowering" — so should we build it, and how? This is contested across four axes: **fidelity** (sub-byte
vs byte-aligned), **dependencies** (`bitvec` vs zero-dep), **honesty** (a partial lowering forces a
finer reach gate), and **sequencing** (is anyone actually asking?). The proposals on the table:

- **P1 — `bitvec` crate.** Full BEAM fidelity (arbitrary bit length, sub-byte) by lowering `<<…>>` to
  `BitVec`/`&BitSlice`.
- **P2 — byte-aligned subset over `Vec<u8>`/`&[u8]`** (zero-dep). Lower only the byte-multiple subset
  (`::binary`, `::utf8`, byte-multiple integer sizes); sub-byte (`<<x::1>>`, `::size(3)`) stays
  BEAM-pinned. Patterns become cursor-advance prelude helpers.
- **P3 — hand-rolled zero-dep bit buffer** in the portable prelude (a `bitvec` reimplementation in
  Rian over `Vec<u8>`), full fidelity, no external dep.
- **P4 — defer entirely.** Stay BEAM-only until a concrete portable consumer *and* self-host parity.
- **P5 — make byte-alignment a *surface* contract** (language decision, not just emitter): sub-byte
  `<<…>>` is BEAM-only **by design**; the portable bitstring surface is byte-aligned for all targets.

### Opening positions

**Elena Rostova (Rust).** P1 is a trap. `bitvec`'s `BitSlice` indexing is *not* zero-cost — a sub-byte
read is a shift+mask, and `<<c::utf8, rest::binary>>` over a `BitSlice` re-derives byte boundaries on
every step. Rust is our *speed anchor* (ADR-0049 §2); lowering a hot lexer loop to bit-addressed access
would make the Rust output slower than the JS one, which inverts the whole pitch. The honest Rust type
for a *binary* is `&[u8]`/`Vec<u8>`, byte-granular by construction. **I back P2, and I'll go further to
P5:** sub-byte bitstrings are a BEAM idiom, not a portable one. P2 **4/5**, P5 **4/5**, P1 **1/5**, P3
**2/5** (we'd maintain a `bitvec` clone to no benefit over P2's subset).

**Samir Patel (rigor).** Whatever we lower must match the BEAM *bit-for-bit* or it is a silent
divergence — worse than the current honest refusal. The hidden landmine in P2 is that "byte-aligned" is
not "semantics-free": `<<n::integer-size(16)>>` is byte-aligned but **endianness-sensitive**, and the
BEAM default is **big-endian**, whereas Rust's natural `u16` write is native-endian. P2 without pinned
endianness passes on x86 and corrupts data on big-endian/wasm. And `::utf8` on the BEAM *validates and
rejects* invalid codepoints; `&[u8]` does not. So P2 is only sound specified against the BEAM as an
**oracle** with property tests. P2 **3/5 conditional on a conformance spec**, else **1/5**. P1 **2/5**
(at least `bitvec` is one tested semantics to match, not N hand-rolled ones).

**Marcus Chen (supply chain).** We refused a `purs` dependency on trust-surface grounds (ADR-0049 §3).
`bitvec` is popular, but P1 means *every emitted Rust crate* carries it transitively — a dependency we
own the audit/pinning of for all downstream users, the exact surface we said no to. P1 **2/5**. P3 keeps
the trust surface at zero but spends budget cloning a crate — **2/5**. P2 is zero-dep, `std`-only —
**4/5**.

**Maya Lin (emitters).** Everyone is arguing the *value* representation and ignoring the *pattern* cost,
where the drift tax actually lands. `<<c::utf8, rest::binary>>` is not a Rust `match` arm — there is no
bit-level `match`. It lowers to **imperative cursor code**: read N bytes, validate, advance, bind the
tail slice. That is per-segment codegen I maintain, and the conservative-exhaustiveness rule (Stage 2)
means these never collapse to a tidy `match` anyway. The only way I accept the drift is a **shared
prelude `BitReader`/`BitWriter`** (written once in Rian over `Vec<u8>`, ADR-0047) that all targets call,
so the emitter emits cursor *calls*, not bespoke cursor *code* per target. P2-with-prelude **4/5**;
P2-as-bespoke-per-emitter-codegen **2/5**.

**Kira Neri (reach honesty).** Non-negotiable: today `bitstr_blocker` is one class killing `[:rs, :js,
:jvm]`. A *partial* Rust lowering means the blocker must **split** — byte-aligned → reaches `:rs`,
sub-byte → stays pinned — computed from the *actual segment specs*, not hand-waved. If the gate says
`:rs` for a program the Rust emitter then rejects (or mis-lowers, per Samir), the matrix lies, and the
matrix is the moat (ADR-0086 §2). **No `:rs` reach claim for bitstrings until the ADR-0087 generative
harness emits random byte-aligned bitstring programs and proves `rustc` compiles+runs them.** P2 **4/5
gated on the harness**; ungated **0/5**. P5 **5/5** — byte-alignment as a *surface* property gives me a
syntactic predicate instead of a semantic one, far cheaper to gate honestly.

**Arthur Pendelton (parser/Core).** The Core is already target-agnostic (`EBitstr`/`PBitstr`); none of
this needs new IR. But there is a skipped prerequisite: **dynamic sizes are not even parsed yet**
(`<<len::8, body::binary-size(len)>>`, the open item). That idiom is *the* reason you reach for
bitstrings in a binary protocol — the portable use case Rachel will ask "who needs this" about. Lowering
literal-size bitstrings to Rust while the surface can't express variable sizes ships a toy. **Sequence
surface completion (dynamic sizes) before the Rust backend.** P5 **4/5**, contingent on dynamic-size
parsing first.

**Rachel Okafor (PM).** Name the consumer. The motivating consumer (Context) is round-tripping the
**compiler's own BEAM source** — BEAM-only by definition. Nobody in the backlog needs a portable
bitstring. ADR-0086 §3 is explicit: **depth before breadth, self-host parity outranks targets.** A
speculative Rust bit-lowering spends the budget ADR-0063 parity needs. **P4 (defer) 4/5** — but
movable to a *scoped* P2+P5 if it is cheap, honest, and *sequenced behind* self-host parity, because a
clean byte-aligned subset is also a forcing function that keeps the surface from accreting BEAM-only
idioms unnoticed.

### Cross-rebuttals

- **Elena → Samir.** Agreed on endianness, and it strengthens P2/P5, not P1: the byte-aligned subset
  lets me emit `to_be_bytes()`/`from_be_bytes()` *visibly* and match the BEAM big-endian default. With
  `bitvec` (P1) endianness hides in the crate's `Lsb0`/`Msb0` ordering type — `bitvec`'s own docs flag
  that as the most common correctness bug. That footgun I don't want in generated code.

- **Samir → Elena.** Then P2 must *forbid*, not silently drop, a non-byte-aligned segment: the checker
  rejects `<<x::3>>`-for-`:rs` with a real diagnostic (ADR-0086 §6); it does not emit "close enough"
  bytes. With that I raise P2 to **4/5**. Without it I hold at 1/5 — rounding sub-byte up to a byte is
  the exact silent-divergence class we exist to prevent.

- **Marcus → Maya.** Your shared-prelude `BitReader` is the *good* version of P3: zero-dep **and**
  amortized across targets, so it sidesteps "cloning a crate" because we build only the byte-aligned
  slice P2 needs, not all of `bitvec`. P2's scope + Maya's prelude mechanism is the proposal I can sign.

- **Kira → Arthur.** Dynamic sizes *help* my gate: `binary-size(len)` is still byte-aligned (unit =
  bytes), so it stays in the portable subset and the harness can cover it. What the harness must exclude
  is sub-byte *units*, which P5 makes syntactic. I support "dynamic sizes first" as a *parser*
  prerequisite, not a reason to widen the portable predicate beyond byte-alignment.

- **Rachel → all.** I drop P4 from veto to sequencing constraint **iff**: (1) byte-aligned subset only
  (no `bitvec`, no sub-byte) — bounded cost; (2) ships *after* self-host parity (ADR-0063); (3) Kira's
  harness gates the `:rs` claim. That's P2+P5+Maya's prelude, sequenced. Under those, **4/5**.

- **Elena → Maya.** One caution on the shared `BitReader`: no runtime allocation on the hot path. A
  `&[u8]` cursor (offset + slice) is zero-alloc; if the prelude `BitReader` boxes or copies, we lose the
  speed argument that justified P2 over P1. Constraint: the byte-aligned `BitReader` is a `(&[u8],
  usize)` cursor, monomorphized, no heap. With that, P2+prelude **5/5** from me.

### Ratings summary

| Proposal | Elena | Samir | Marcus | Maya | Kira | Arthur | Rachel | Verdict |
|---|---|---|---|---|---|---|---|---|
| **P1** `bitvec` dep | 1 | 2 | 2 | 2 | 2 | 2 | 1 | **Rejected** — non-zero-cost, trust surface, endianness footgun |
| **P2** byte-aligned `Vec<u8>` subset | 4 | 4* | 4 | 4* | 4* | 4* | 4* | **Adopted** (with starred conditions) |
| **P3** hand-rolled bit buffer | 2 | 3 | 2 | 3 | 3 | 3 | 2 | **Folded into P2** as the byte-aligned-only prelude `BitReader`, not a full clone |
| **P4** defer entirely | 2 | 3 | 3 | 2 | 3 | 3 | 4→constraint | **Demoted to a sequencing constraint**, not a veto |
| **P5** byte-alignment as surface contract | 4 | 4 | 4 | 4 | 5 | 4 | 4 | **Adopted** — sub-byte is BEAM-only *by design* |

`*` = conditional: P2 is "yes" only with (Samir) a BEAM-oracle conformance spec + explicit big-endian
specifiers and a *reject* (not round-up) for sub-byte; (Maya) a shared zero-alloc prelude `BitReader`/
`BitWriter` cursor rather than bespoke per-emitter codegen; (Kira) the ADR-0087 harness green on
byte-aligned bitstring programs before any `:rs` reach claim; (Arthur/Rachel) dynamic-size *parsing*
landed and the whole thing sequenced behind self-host parity.

### Consensus

**Adopt P2 + P5 (byte-aligned portable subset; sub-byte BEAM-only by design), built on Maya's shared
prelude `BitReader`/`BitWriter`, gated by Kira's harness and Samir's conformance spec, sequenced behind
self-host parity.** Concretely:

1. **Surface split (P5).** The *portable* bitstring surface is **byte-aligned**: `::binary`, `::utf8`,
   `::integer` with a byte-multiple size, and `binary-size(len)` (byte unit, dynamic length allowed).
   **Sub-byte** segments (`::size(n)` with `n` not a multiple of 8, bit units) are **BEAM-only by
   design** — a permanent reach pin, documented as such, not "not yet."
2. **Reach gate split (Kira).** `bitstr_blocker` splits into `:bitstring_subbyte` (kills `[:rs, :js,
   :jvm]`, permanent) and a byte-aligned class that *does not* kill `:rs` — but only once the ADR-0087
   harness proves byte-aligned bitstring programs compile+run under `rustc`. Until green, byte-aligned
   stays pinned too (honest under-claim beats a lie).
3. **Value + pattern lowering (Elena/Maya).** Byte-aligned `<<…>>` → `Vec<u8>` (owned) / `&[u8]`
   (borrowed); patterns → a zero-alloc `(&[u8], usize)` cursor in the portable prelude (ADR-0047), the
   emitter emitting cursor *calls*. Integer segments use explicit `to_be_bytes`/`from_be_bytes` (BEAM
   big-endian default), little-endian only when the spec says `little`.
4. **Conformance (Samir).** A BEAM-oracle property suite: random byte-aligned bitstrings, assert the
   Rust output's bytes (and UTF-8 validation/rejection) equal the BEAM's. A non-byte-aligned segment in
   a `:rs`-required function is a **hard checker error** (ADR-0086 §6 diagnostic), never a rounded byte.
5. **Sequencing (Rachel/Arthur).** Land **dynamic-size parsing** first (closes the existing open item),
   then the Rust subset **after** self-host parity (ADR-0063). No `bitvec`, ever (Marcus).

This deliberately does **not** widen the frozen portable core unilaterally (ADR-0049 §5a): byte-aligned
bitstrings either become portable across *all* Tier-1 targets together (JS `Uint8Array`/`DataView`, JVM
`ByteBuffer` mirror the same subset) or they remain a single-target escape hatch — and a single-target
escape hatch is the Haxe `#if` sprawl we refuse (ADR-0085 §7). The consensus is the former.

**Follow-on (2026-06-22): the portable surface is owned by ADR-0089.** A separate question — *what is
the portable surface for byte data?* — was answered against a competing bit *syntax*: the portable
surface is a **`Bytes` type + `BitReader`/`BitWriter` API** (the zero-alloc cursor Maya/Elena specced),
and the byte-aligned `<<…>>` subset **lowers through it**. So `<<…>>` stays the BEAM-first / gold-standard
binary-parsing surface, and **ADR-0089** owns the portable `Bytes`/reader/writer story this consensus
pointed to.

### Future developments

- **Sub-byte portability** could revisit P3 (a real prelude bit buffer) *iff* a concrete consumer needs
  portable sub-byte framing (a wire codec with bit flags) — re-entering under the same gate, never as a
  default.
- **Bitstring comprehensions** (`for <<x <- s>>`, out of scope today) intersect this: a byte-aligned
  generator is a cursor loop the prelude `BitReader` already supports.
- **Endianness as a first-class spec** in the formatter CST (the loose `-`-spec rendering open item)
  gains urgency once `little`/`big` carry portable meaning.

### Concrete next steps (no code lands on this debate alone)

1. Split `bitstr_blocker` into `:bitstring_subbyte` (permanent `[:rs, :js, :jvm]` pin) vs a byte-aligned
   class; the byte-aligned class stays pinned until step 4 — a pure honesty refactor, shippable now.
2. Add the **byte-aligned vs sub-byte** distinction to `Rian.Check` as a diagnostic (ADR-0086 §6) so a
   sub-byte segment in a target-required function fails with `file:line` + cause.
3. Parse **dynamic byte sizes** (`binary-size(len)`), closing the existing open item.
4. Extend the ADR-0087 generative harness with a byte-aligned bitstring generator; only when its `:rs`
   column is green does the byte-aligned reach class stop killing `:rs`.
5. Implement the prelude `BitReader`/`BitWriter` (zero-alloc cursor) + the Rust emitter subset; mirror
   to JS/JVM under the same spec. Sequenced behind self-host parity (ADR-0063).
