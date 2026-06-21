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
  spago.yaml          workspace + purerl backend + (purerl) package set
  package.json        pins purs + spago (via npm)
  src/Rian/           the migrated compiler modules (Elixir lib/rian/* -> here)
  test/               spec suites + parity fixtures vs the Elixir reference
```

## Toolchain

| Tool        | Version  | Source                                  |
| ----------- | -------- | --------------------------------------- |
| `purs`      | 0.15.16  | npm (`purescript`)                      |
| `spago`     | 0.93.45  | npm (`spago`)                           |
| `purerl`    | 0.0.24   | GitHub release (purerl/purerl)          |
| Erlang/OTP  | 27+      | system (`erl`)                          |

`purs` and `spago` are installed from npm and committed via `package.json`:

```sh
cd purs && npm install
```

`purerl` is a separate Erlang-emitting backend distributed as a platform binary from
GitHub releases — it is **not** an npm package. Bootstrap it once (network required):

```sh
# 1. fetch the purerl binary for your platform from
#    https://github.com/purerl/purerl/releases/tag/v0.0.24
#    and put it on PATH (the `backend.cmd: purerl` in spago.yaml invokes it)
# 2. fetch the purerl package set + build (spago reads spago.yaml)
cd purs && npx spago build
```

> The purerl **package set** (`workspace.packageSet.url` in `spago.yaml`) ships
> Erlang-FFI versions of `prelude`, `strings`, `arrays`, … — the default JS registry
> set will not link under purerl. Pin a matching `erl-*` tag for `purs` 0.15.x.

## Verifying

```sh
# package-set-free slice (Rian.Token today): the FULL chain, no spago needed —
# purs → corefn → purerl → erlc → run on the BEAM. Verified end-to-end:
cd purs && ./scripts/purerl-build.sh
#   → ✓ Rian.Token runs on the BEAM via purerl

# library-dependent modules (Lexer onward) — gated by spago once the package set
# is wired (see the OPEN note below):
cd purs && npx spago build && npx spago test
```

`scripts/purerl-build.sh` is the working gate for every module that uses only built-in
`Prim` types; it drives the whole purerl chain and smoke-tests the result on Erlang/OTP.

### Two known caveats

1. **Compiler-version skew.** purerl 0.0.24 was built against purs 0.15.x and prints
   `Found externs for wrong compiler version (continuing anyway)` against purs 0.15.16.
   It is harmless for codegen today; pin `purs` to purerl's exact target if it ever bites.
2. **Package set (OPEN — Phase 1 blocker).** purerl's package set is a legacy *dhall*
   set; spago 0.93 expects a registry (`packages.json`) set and cannot consume it
   directly. Resolving this — legacy spago (0.21, dhall) or `extraPackages` git deps
   generated from the dhall set — is the first task of Phase 1, since the Lexer needs
   `strings`/`arrays`/`maybe`/regex. The `Prim`-only slice is unaffected.
