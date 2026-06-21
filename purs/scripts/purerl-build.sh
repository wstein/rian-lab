#!/bin/sh
# Build + smoke-test the package-set-free slice of the PureScript/purerl port
# (ADR-0084). Drives the full chain without spago, so it runs offline once the
# purerl binary is vendored (purs/README.md): purs -> corefn -> purerl -> erlc -> run.
#
# This gates every module that depends only on built-in `Prim` types (currently
# `Rian.Token`). Library-dependent modules (Lexer onward) build through spago + the
# purerl package set instead — see purs/README.md.
set -eu

cd "$(dirname "$0")/.."
BIN="$PWD/node_modules/.bin"
PURERL="$PWD/.toolchain/purerl/purerl"

[ -x "$BIN/purs" ] || { echo "✗ purs not installed — run: cd purs && npm install"; exit 1; }
[ -x "$PURERL" ] || { echo "✗ purerl not vendored — see purs/README.md (bootstrap)"; exit 1; }

echo "→ purs: typecheck + corefn"
rm -rf output
"$BIN/purs" compile --codegen corefn 'src/**/*.purs'

echo "→ purerl: corefn → Erlang"
"$PURERL" --quiet

echo "→ erlc: Erlang → BEAM"
erlc -o output/Rian.Token output/Rian.Token/'rian_token@ps.erl'

echo "→ run: Rian.Token smoke check on the BEAM"
erl -noshell -pa output/Rian.Token -eval '
  M = '\''rian_token@ps'\'',
  MkComment = M:'\''TComment'\''(),
  true  = M:isNewline(M:'\''TNl'\''()),
  false = M:isNewline(M:'\''TComma'\''()),
  true  = M:isTrivia(MkComment(<<"# hi">>)),
  <<"TMapopen">> = M:tokenName(M:'\''TMapopen'\''()),
  io:format("✓ Rian.Token runs on the BEAM via purerl~n"),
  halt(0).' || { echo "✗ Rian.Token smoke check failed"; rm -f output/Rian.Token/erl_crash.dump; exit 1; }
