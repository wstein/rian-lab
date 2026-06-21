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

## `@rian_sig` capability & type annotations

The endgame (ADR-0084 Phase 7) is a **PureScript → Rian** transpiler — Rian's reference
implementation, written in PureScript, lowered back to Rian source so it self-hosts and the
Rust/BEAM/JS backends compile it. PureScript's type system is rich, but it **underdetermines
the Rian signature** in two ways the transpiler and the Rust backend need, so each ported
module carries `@rian_sig` annotation comments (the convention that replaces the Elixir
`@rian_sig` attribute — only the Elixir *reader* `Rian.Ann` is obsolete, the annotation lives on):

1. **Reference capabilities** — `val` / `iso` / `ref` / `tag` are not expressible in PureScript
   at all, yet they drive the Rust signature (owned vs borrowed vs `&mut`) and BEAM linearity
   (use-once). See [`../docs/spec/capability-lowering.md`](../docs/spec/capability-lowering.md).
2. **Type bridging** — PureScript `Int` does not say `Int53` vs `Int32`; `Array T` → `Vec(T)`,
   `Boolean` → `Bool`, `Maybe T` → `Option(T)`, `String` → `String`.

### Form

A `-- @rian_sig <decl>` line sits immediately before the PureScript declaration it annotates
(a multi-line type continues on following `--` comment lines). It is a plain comment — invisible
to `purs`, read only by the Phase-7 transpiler. The `<decl>` is a Rian declaration head with
capability-annotated parameters/fields (grammar: `[label] [capability] type`,
[types-match.md §3.4](../docs/spec/types-match.md)):

```purescript
-- @rian_sig type Token := … | TStr(val String) | TChar(val Int53) | TIstr(val Vec(StrPart))
data Token = … | TStr String | TChar Int | TIstr (Array StrPart)

-- @rian_sig pub def tokenize(src val String) Vec(Token)
tokenize :: String -> Array Token
```

### Capability mental model (default: `val`)

| keyword | meaning             | Rust (param)        |
| ------- | ------------------- | ------------------- |
| `val`   | borrowed / read-only (default) | `&str` / `&[T]` / `&T`, `Copy` prim by value |
| `iso`   | owned / move (use-once)        | `String` / `Vec<T>` / `T` |
| `ref`   | mutable borrow                 | `&mut T` (BEAM-illegal) |
| `tag`   | shared borrow / identity       | `&T` |

Omit the keyword and it defaults to `val`. The leaf modules ported so far are read-only
throughout, so every annotation is `val` — but they still carry the **type bridge** (e.g.
`Int` → `Int53`), and they establish the pattern for later modules (IR/Core/Decl) where owned
sub-trees and builders take `iso`. Annotate public functions and every struct/sum field.

### Effects (`@rian_host`)

A `-- @rian_host` line tags a function with the **host effect** (ADR-0048/0081 → surface
`@effects(host)`): host-runtime work — I/O, FFI to the BEAM, a `try/rescue`→value boundary.
It is the effect sibling of `@rian_sig`, but the two differ in how much PureScript already
tells the transpiler:

- **Capabilities are invisible** to PS, so `@rian_sig` is the *only* source of truth.
- **Effects are half-visible**: a host-effecting function is typed `Effect a` / `Aff a`, so PS
  already signals *that* it is effectful. PureScript's single `Effect` just doesn't carry the
  *granularity* (host vs fs vs io); `@rian_host` supplies it — and only at `pub` boundaries
  (effects are inferred for private functions, a checked declared assertion for public ones).

**None of the modules ported so far need it.** `Token`/`Lexer`/`TypeStr` are pure (no `Effect`);
the lexer's `unsafeCrashWith` on malformed input is a **portable panic** (`Prim.panic`,
ADR-0035), not a host effect, so it is *not* tagged. `@rian_host` enters when the host-coupled
modules land — `Beam` (`:compile.forms`), `Run`/`Repl`, CLI/file-I/O, the Erlang-FFI boundary —
which are typed `Effect`/FFI in PureScript.

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
3. **Fall-through guards on a `case` pattern can crash under purerl.** A
   `case x of P | guard -> a ; … -> b` where `guard` is false (so it should fall to the next
   branch) compiled to a `function_clause` crash in one observed case (`Rian.Decl.buildFunc`).
   Prefer `if`/`else` (or guards on top-level *function* clauses, which purerl handles
   natively) when a guard can fail and a later branch must catch it.
