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
# full gate (needs the bootstrapped toolchain + package set):
cd purs && npx spago build && npx spago test

# offline (no package set): typecheck the Prim-only modules + emit the corefn
# JSON that purerl consumes — proves the compile chain end-to-end short of codegen:
cd purs && ./node_modules/.bin/purs compile --codegen corefn 'src/**/*.purs'
```

The offline `purs compile` is what currently gates `Rian.Token`; every module that
only uses built-in `Prim` types is checkable this way before the package set lands.
Modules importing the library set (anything past `Token`) are gated by `spago test`.
