# rebar3_rian — compile Rian sources inside a rebar3 project

A [rebar3](https://rebar3.org) plugin that compiles `.rian` sources to BEAM `.beam`
files, so Rian modules build alongside Erlang in an existing rebar3 project — the
"Erlang citizen" deliverable of [ADR-0026](../../docs/adr/0026-ecosystem-integration.md)
(and the driver story of [ADR-0031](../../docs/adr/0031-bootstrap-strategy.md)).

It is a **thin orchestrator**: on `rebar3 compile` it shells out to the toolchain-free
`rian build FILE -o <ebin>` escript (`Rian.Build`) for each `.rian` source — rebar3 owns
deps/build/release, the `rian` compiler owns codegen. No dependency management is
reimplemented.

## Requirements

- `rebar3` (3.x).
- The `rian` escript on `PATH` (or an absolute path via `{rian, [{bin, "…"}]}`). Build it
  from this repo with `mix escript.build` (produces `./rian`).

## Use it in a rebar3 project

`rebar.config`:

```erlang
{plugins, [rebar3_rian]}.                              %% from Hex (once published)
{provider_hooks, [{post, [{compile, rian}]}]}.         %% run after the Erlang compile
{rian, [{bin, "rian"}, {src_dir, "rian_src"}]}.        %% both optional (defaults shown)
```

Put `.rian` sources in `rian_src/` (configurable). `rebar3 compile` then writes
`Elixir.<Mod>.beam` into the app's `ebin/`, on the code path like any other module.

## Local development (this repo, before Hex publish)

rebar3 loads a local plugin from `_checkouts/`:

```sh
mix escript.build                                   # build ./rian at the repo root
cd your_project
mkdir -p _checkouts
ln -s /abs/path/to/rian_lab/integration/rebar3_rian _checkouts/rebar3_rian
PATH="/abs/path/to/rian_lab:$PATH" rebar3 compile   # rian on PATH
```

## Demo + verification

`examples/hello/` is a minimal app with `rian_src/hello.rian`. `verify.sh` reproduces
the end-to-end check (sets up a clean project via `_checkouts`, runs `rebar3 compile`,
loads the built module, asserts `Hello.answer() == 42`):

```sh
./verify.sh
```

## How it works

`rebar3_rian_prv` registers a `rian` provider (after `app_discovery`). For each app it
globs `<app>/<src_dir>/*.rian` and runs `rian build <src> -o <app-ebin>`; a `rian build`
failure aborts the rebar3 run with the compiler's error. Wire it to `compile` with the
`provider_hooks` above, or invoke it directly with `rebar3 rian`.
