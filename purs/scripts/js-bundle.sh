#!/bin/sh
# Bundle the stock-purs JS build (`output-js/`) into a single browser ESM artifact (ADR-0090) — the
# compiler the live playground loads. Runs the JS build first (so `output-js/` is fresh), then
# esbuild-bundles `playground-entry.mjs` (which re-exports `compile`/`compileTypes`) + all its
# transitive deps into `site/public/rian-compiler.mjs`. The Astro site serves that at `/`.
#
# `--check`: bundle to a temp file and assert it is byte-identical to the committed
# `site/public/rian-compiler.mjs` — the freshness gate (à la `mix rian.tour --check`, ADR-0090).
# esbuild `--minify` is deterministic, so equal source ⇒ equal bytes; a stale committed bundle fails.
set -eu

cd "$(dirname "$0")/.."          # purs/
export PATH="$PWD/node_modules/.bin:$PATH"

ESBUILD="../site/node_modules/.bin/esbuild"
OUT="../site/public/rian-compiler.mjs"
[ -x "$ESBUILD" ] || { echo "✗ esbuild not found at $ESBUILD — run: cd site && npm install"; exit 1; }

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

echo "→ JS build (output-js/)"
./scripts/js-build.sh

if [ "$CHECK" = 1 ]; then
  TMPD=$(mktemp -d)
  trap 'rm -rf "$TMPD"' EXIT
  DEST="$TMPD/rian-compiler.mjs"
  SPEC="file://$DEST"
else
  mkdir -p ../site/public
  DEST="$OUT"
  SPEC="../site/public/rian-compiler.mjs"
fi

echo "→ esbuild: bundle → $DEST"
"$ESBUILD" scripts/playground-entry.mjs --bundle --format=esm --minify --outfile="$DEST" --log-level=warning

echo "→ smoke: load the bundle + compile a sample (node)"
node --input-type=module -e '
  import { compile } from "'"$SPEC"'";
  const js = compile("pub def add(x Int53, y Int53) Int53 := x + y");
  if (!js.includes("export function add")) { console.error("✗ bundle compile failed\n" + js); process.exit(1); }
  console.log("✓ rian-compiler.mjs bundles + compiles");
'

if [ "$CHECK" = 1 ]; then
  if cmp -s "$DEST" "$OUT"; then
    echo "✓ committed bundle is fresh — $OUT matches a clean rebuild"
  else
    echo "✗ $OUT is STALE — run: purs/scripts/js-bundle.sh, then commit the regenerated bundle"
    exit 1
  fi
else
  echo "✓ bundle: $(wc -c < "$OUT" | tr -d ' ') bytes → $OUT"
fi
