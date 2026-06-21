# `purs/` — the Rian compiler, ported to PureScript (purerl)

This workspace holds the **PureScript port of the Elixir reference compiler** in
[`../lib/rian/`](../lib/rian/). It is a long-running, dependency-ordered migration
(ADR-0084); see [`../docs/purescript-migration.md`](../docs/purescript-migration.md)
for the phase plan and per-module status.

**Why PureScript / why purerl.** PureScript's type system replaces the Dialyzer
success-typing crutch the Elixir tree leans on (the `@spec`/`@rian_sig` annotations
become real types). The **purerl** backend compiles PureScript to **Erlang**, so the
compiler keeps running on the BEAM and can FFI to the Erlang machinery the BEAM-coupled
modules need (`:compile.forms`, code loading, the REPL) — preserving the self-hosting
bootstrap that a PureScript→JS port would have lost. See ADR-0084 for the full rationale
and the FFI boundary.

## Layout

```
purs/
  spago.dhall         project + purerl backend (legacy spago / dhall)
  packages.dhall      the purerl (Erlang-FFI) package set
  package.json        pins purs + legacy spago (via npm)
  src/Rian/           the migrated compiler modules (Elixir lib/rian/* -> here)
  test/               parity harness (.erl) + fixtures + generator (.exs) vs the reference
  scripts/            build + smoke-test + parity gate
```

## Toolchain

| Tool        | Version  | Source                                  |
| ----------- | -------- | --------------------------------------- |
| `purs`      | 0.15.16  | npm (`purescript`)                      |
| `spago`     | 0.21.0   | npm (`spago`, legacy/dhall — purerl)    |
| `purerl`    | 0.0.24   | GitHub release (purerl/purerl)          |
| Erlang/OTP  | 27+      | system (`erl`)                          |

> **Why legacy spago 0.21, not 0.93?** purerl ships its package set as a *dhall* set
> (`packages.dhall`). The current spago (0.93) consumes only registry (`packages.json`)
> sets and cannot link purerl libraries; the dhall-based legacy spago (0.21) is the
> supported purerl build tool.

`purs` and legacy `spago` install from npm (committed via `package.json`):

```sh
cd purs && npm install
```

`purerl` is a separate Erlang-emitting backend distributed as a platform binary from
GitHub releases — **not** an npm package. Bootstrap it once (network required):

```sh
# fetch the purerl binary for your platform from
#   https://github.com/purerl/purerl/releases/tag/v0.0.24
# verify its checksum, then put it on PATH (spago's `backend = "purerl"` invokes it).
# This repo vendors it under purs/.toolchain/ (gitignored); the build script adds it to PATH.
```

The first `spago build` fetches the purerl **package set** (`packages.dhall`) into
`.spago/` (network); subsequent builds are offline.

## Verifying

```sh
cd purs && ./scripts/purerl-build.sh
#   → ✓ Rian.Token builds + runs on the BEAM via purerl
```

`scripts/purerl-build.sh` is the gate for every migrated module: it runs the full chain —
`spago build` (purs typecheck + purerl codegen of the sources **and** the package set) →
`erlc` (Erlang → BEAM) → runs the result on Erlang/OTP, then the **lexer parity check**.
Raw `spago build` typechecks + emits `.erl` without the run step.

### Parity testing (the real gate)

A ported module is "migrated" only when it matches the Elixir reference behaviourally,
not just when it compiles. The pattern (see `Rian.Lexer`):

1. `mix run purs/test/gen_fixtures.exs` (from the repo root) runs the Elixir reference over
   a corpus and writes canonical fixtures to `purs/test/fixtures/`. Re-run this when the
   reference changes; the fixtures are committed.
2. `purs/test/*.erl` is an Erlang harness that re-runs the purerl-compiled module over the
   same inputs and asserts byte-equality with the fixtures.
3. `scripts/purerl-build.sh` runs the harness as part of the gate.

### Known caveats

1. **Compiler-version skew.** purerl 0.0.24 was built against purs 0.15.x and prints `Found
   externs for wrong compiler version (continuing anyway)` against purs 0.15.16. Harmless for
   codegen today; pin `purs` to purerl's exact target if it ever bites.
2. **purerl `Data.String.CodePoints` is byte-wise.** In this `strings` version, `uncons`/
   `drop`/`splitAt` iterate UTF-8 *bytes*, not codepoints — only `toCodePointArray`,
   `singleton`, and `take` are Unicode-correct. Decode to a codepoint `Array`/`List` once at
   the boundary and scan that (as `Rian.Lexer` does); do not `uncons` a `String` directly.
