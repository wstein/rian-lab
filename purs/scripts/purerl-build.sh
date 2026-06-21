#!/bin/sh
# Build + smoke-test the PureScript/purerl port (ADR-0084).
#
# Drives the full chain: spago (purs typecheck + purerl codegen of the sources AND the
# package set) -> erlc (Erlang -> BEAM) -> run the result on Erlang/OTP. This is the gate
# for every migrated module. Requires the bootstrapped toolchain (purs/README.md):
# `npm install` (purs + legacy spago 0.21) and the vendored purerl binary; the first
# run fetches the purerl dhall package set into .spago (network), then it is cached.
set -eu

cd "$(dirname "$0")/.."
export PATH="$PWD/node_modules/.bin:$PWD/.toolchain/purerl:$PATH"

command -v purs >/dev/null   || { echo "✗ purs not installed — run: cd purs && npm install"; exit 1; }
command -v purerl >/dev/null || { echo "✗ purerl not vendored — see purs/README.md (bootstrap)"; exit 1; }
command -v spago >/dev/null  || { echo "✗ spago not installed — run: cd purs && npm install"; exit 1; }

echo "→ spago: typecheck + purerl codegen (sources + package set)"
spago build

echo "→ erlc: emitted Erlang → BEAM"
BUILD=_build/beam
rm -rf "$BUILD"; mkdir -p "$BUILD"
find output -name '*.erl' -exec cp {} "$BUILD/" \;
find output -name '*.hrl' -exec cp {} "$BUILD/" \;
( cd "$BUILD" && erlc *.erl >/dev/null 2>&1 )

echo "→ run: Rian.Token smoke check on the BEAM"
erl -noshell -pa "$BUILD" -eval '
  M = '\''rian_token@ps'\'',
  MkComment = M:'\''TComment'\''(),
  true  = M:isNewline(M:'\''TNl'\''()),
  false = M:isNewline(M:'\''TComma'\''()),
  true  = M:isTrivia(MkComment(<<"# hi">>)),
  <<"TMapopen">> = M:tokenName(M:'\''TMapopen'\''()),
  io:format("✓ Rian.Token builds + runs on the BEAM via purerl~n"),
  halt(0).' || { echo "✗ Rian.Token smoke check failed"; rm -f "$BUILD/erl_crash.dump"; exit 1; }
