#!/bin/sh
# Build the PureScript port to JavaScript via stock `purs` (ADR-0090) — the in-browser playground
# compiler. Same sources as the purerl build (`purerl-build.sh`), but through purs's native JS
# backend with the standard JS package set (`spago-js.dhall` / `packages-js.dhall`) and the JS FFI
# for `HostRef`. Output goes to `output-js/` so it does not clobber the purerl `output/`.
#
# Requires the bootstrapped toolchain (purs/README.md): `npm install` (purs + legacy spago 0.21).
# The first run fetches the standard package set into `.spago` (network), then it is cached.
set -eu

cd "$(dirname "$0")/.."
export PATH="$PWD/node_modules/.bin:$PATH"

command -v purs >/dev/null  || { echo "✗ purs not installed — run: cd purs && npm install"; exit 1; }
command -v spago >/dev/null || { echo "✗ spago not installed — run: cd purs && npm install"; exit 1; }
command -v node >/dev/null  || { echo "✗ node not found"; exit 1; }

echo "→ spago (JS backend): purs typecheck + JS codegen → output-js/"
spago -x spago-js.dhall build --purs-args "--output output-js"

echo "→ smoke: Rian.JS.compile runs on the JS backend (node)"
node --input-type=module -e '
  import { compile } from "./output-js/Rian.JS/index.js";
  const src = "type Color := Red | Green\nstruct Box(v Int53)\npub def add(x Int53, y Int53) Int53 := x + y\npub def mk(n Int53) Box := Box(v: n)\npub def lbl(s String) String := \"hi ${s}\"";
  const out = compile(src);
  const need = ["export function add", "{ __struct__: \"Box\", v: n }", "\"hi \" + s"];
  for (const s of need) {
    if (!out.includes(s)) { console.error("✗ expected substring missing: " + s + "\n--- output ---\n" + out); process.exit(1); }
  }
  console.log("✓ Rian.JS.compile runs on the stock-purs JS backend (struct construction + interpolation lowered)");
'
