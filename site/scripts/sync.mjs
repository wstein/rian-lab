// Copy the generated docs (../doc, written by `mix docs` via Rian.DocFormatter)
// into the Starlight content collection. This is a plain file sync — NOT a
// transform. The formatter already emits site-ready MDX + sidebar + redirects.
import { cpSync, rmSync, mkdirSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const DOC = join(root, "..", "doc"); // rian_lab/doc
const DOCS = join(root, "src", "content", "docs");
const GEN = join(root, "src", "generated");

if (!existsSync(DOC)) {
  console.error(`No ${DOC} — run \`mix docs\` in rian_lab first.`);
  process.exit(1);
}

rmSync(DOCS, { recursive: true, force: true });
mkdirSync(DOCS, { recursive: true });
mkdirSync(GEN, { recursive: true });

// recursively copy every .mdx, preserving the formatter's folder structure
// (overview/, architecture-decisions/, api/, tasks/, …); skip ExDoc's html
// assets dir (doc/dist) and anything non-mdx
let n = 0;
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === "dist") continue;
    const src = join(dir, entry);
    if (statSync(src).isDirectory()) {
      walk(src);
    } else if (entry.endsWith(".mdx")) {
      const dest = join(DOCS, relative(DOC, src));
      mkdirSync(dirname(dest), { recursive: true });
      cpSync(src, dest);
      n++;
    }
  }
}
walk(DOC);

for (const f of ["sidebar.mjs", "redirects.mjs", "meta.mjs"]) {
  cpSync(join(DOC, f), join(GEN, f));
}
console.log(`synced ${n} pages + sidebar + redirects -> ${DOCS}`);
