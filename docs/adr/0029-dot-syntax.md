# ADR-0029 — Dot Syntax as the Universal Qualifier

**Status:** Accepted; implemented & verified · **Supersedes:** ADR-0003 (`::` for paths)
**Owners:** Chloe Bennett (parser) · Maya Lin (emitters) · Arthur Pendelton (disambiguation)
**Tests:** `test/rian/dot_test.exs` (8/8); full suite 106/0

## Context

ADR-0003 reserved `::` for namespace/path access and `.` for field access, to keep them
syntactically distinct. Preference now: use `.` for both. The example given was
`match x { Value.Int(x) => ... }` — a dotted variant path in Rian source.

## Decision

**`.` is the single, universal qualification/access operator in Rian source**, disambiguated
the way Elixir already does it — by the *case* of the operands — with Erlang modules written as
**atoms**. The parser produces one `{:dot, head, name}` node (replacing the former
`{:field}`/`{:path}` split). `::` is **not** Rian-source syntax: the tokenizer does not accept
it and `a::b` is a parse error. The Rust backend still emits `::` (mandatory in Rust); only the
**Rian source** operator changed.

Disambiguation (resolved at emit time):

| Rian source | Meaning | Elixir | Rust |
|---|---|---|---|
| `Geometry.area(x)` | Rian module fn (Pascal head, lower name) | `Geometry.area(x)` | `geometry::area(x)` |
| `Value.Num(n)` | type/variant path (Pascal head, Pascal name) | tagged tuple `{:num, n}` | `Value::Num(n)` |
| `point.x` | field access (lower head) | `point.x` | `point.x` |
| `:lists.sum(xs)` | **Erlang FFI** (atom head) | `:lists.sum(xs)` | BEAM-only (refused) |
| `String.upcase(s)` | Elixir-module FFI | `String.upcase(s)` | BEAM-only* |

\* The Rust backend can't tell an Elixir-stdlib module from a Rian module by name alone; a
symbol-resolution pass (open item) settles this. Elixir/Erlang stdlib FFI is BEAM-only anyway.

This change moves Erlang-module FFI from the old lowercase-`lists::sum` form to the atom form
`:lists.sum`, which is exactly Elixir's own convention — improving BEAM-citizen consistency.

## Why this is sound (not just a preference)

This is precisely Elixir's model: `.` everywhere, head case disambiguates module-vs-value, and
Erlang modules are atoms. Adopting it makes Rian read like a BEAM-native language and removes
the only awkward case (lowercase Erlang module). The Rust backend recovers the namespace/field
distinction it needs by the same case rules at emit time.

## Verified

- Dot lowering: `Geometry.area`→`geometry::area`, `point.x`→`point.x`,
  `Value.Num(n)`→`Value::Num(n)`, `:lists.sum`→BEAM-only.
- User example end to end: `type Value := Num(i64) | Zero`; `eval` matching `Value.Num(n)` /
  `Value.Zero` → emitted Elixir (tagged tuple + atom) executed (`42`, `0`); emitted Rust
  (`Value::Num(n)`, unit `Value::Zero`) compiled by rustc and run (`42`, `0`).
- Caught & fixed a latent bug: nullary variant patterns were emitting `Value::Zero()`; now
  unit variants emit without parens.
- Operator precedence unaffected (22/22). Full suite 106/0.

## Consequences

- Specs/ADRs that wrote `::` (modules, FFI) now read `.` in source. `::` is **removed** from the
  surface entirely — there is no transitional alias; it lexes only as the Rust *output*
  separator, never as Rian input.
- Symbol resolution (which Pascal names are Rian modules vs Elixir-stdlib) becomes a real
  open item for correct Rust emission of module calls.

## Open items
- Symbol-table resolution to distinguish Rian modules from Elixir-stdlib modules for Rust.
- Field-access chains `a.b.c` to the Rust target (currently the nested fallback assumes a path).
