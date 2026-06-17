#!/bin/sh
# Reproducible end-to-end check for the rebar3_rian plugin: build the `rian`
# escript, set up a clean rebar3 project (the `examples/hello` demo) with the
# plugin in `_checkouts`, `rebar3 compile`, then load the built module and assert
# `Hello.answer() == 42`. Exits non-zero on any failure.
set -eu

plugin_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$plugin_dir/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "== build the rian escript =="
( cd "$repo_root" && mix escript.build >/dev/null )

echo "== stage a clean rebar3 project with the plugin in _checkouts =="
cp -R "$plugin_dir/examples/hello/." "$work/"
rm -rf "$work/_build"
mkdir -p "$work/_checkouts"
ln -s "$plugin_dir" "$work/_checkouts/rebar3_rian"

echo "== rebar3 compile (rian on PATH) =="
( cd "$work" && PATH="$repo_root:$PATH" rebar3 compile )

beam=$(find "$work/_build" -name 'Elixir.Hello.beam' | head -1)
[ -n "$beam" ] || { echo "FAIL: Elixir.Hello.beam not produced"; exit 1; }
echo "built: $beam"

echo "== load the rebar3-built module and run it =="
ebin=$(dirname "$beam")
out=$(erl -noshell -pa "$ebin" -eval \
  'io:format("~p", ['"'"'Elixir.Hello'"'"':answer()]), halt().')
echo "Hello.answer() = $out"
[ "$out" = "42" ] || { echo "FAIL: expected 42, got $out"; exit 1; }

echo "OK — rebar3 compiled and ran a Rian module"
