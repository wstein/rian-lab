#!/bin/sh
# Bundle the stock-purs JS build (`output-js/`) into a single browser ESM artifact (ADR-0090) — the
# compiler the live playground loads. Runs the JS build first (so `output-js/` is fresh), then
# esbuild-bundles `playground-entry.mjs` (which re-exports `compile`/`compileTypes`) + all its
# transitive deps into `site/public/rian-compiler.mjs`. The Astro site serves that at `/`.
set -eu

cd "$(dirname "$0")/.."          # purs/
export PATH="$PWD/node_modules/.bin:$PATH"

ESBUILD="../site/node_modules/.bin/esbuild"
OUT="../site/public/rian-compiler.mjs"
[ -x "$ESBUILD" ] || { echo "✗ esbuild not found at $ESBUILD — run: cd site && npm install"; exit 1; }

echo "→ JS build (output-js/)"
./scripts/js-build.sh

echo "→ esbuild: bundle → $OUT"
mkdir -p ../site/public
"$ESBUILD" scripts/playground-entry.mjs --bundle --format=esm --minify --outfile="$OUT" --log-level=warning

echo "→ smoke: load the bundle + compile a sample (node)"
node --input-type=module -e '
  import { compile } from "../site/public/rian-compiler.mjs";
  const js = compile("pub def add(x Int53, y Int53) Int53 := x + y");
  if (!js.includes("export function add")) { console.error("✗ bundle compile failed\n" + js); process.exit(1); }
  console.log("✓ rian-compiler.mjs bundles + compiles");
'
echo "✓ bundle: $(wc -c < "$OUT" | tr -d ' ') bytes → $OUT"
