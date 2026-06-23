// Shared live-evaluation helpers for the in-browser Rian compiler (ADR-0090),
// used by both the playground (`pages/playground.astro`) and the by-example
// tutorial (`pages/by-example.astro`). The compiler is the real Rian → JS
// compiler, compiled to JS by stock purs and served from `public/`.

// An opaque, parsed + type-checked program (`Rian.Lower.All.Prepared`) — produced once by
// `prepare`, then lowered to each target. Callers only thread it through.
export type Prepared = unknown;

export type Compiler = {
  // parse-once front door (ADR-0090): run the shared front-end (lex → parse → Core → type-gate)
  // a single time; throws on a parse / shared type-gate error (the buffer is invalid everywhere).
  prepare: (src: string) => Prepared;
  // per-target lowerings of a prepared program; each may throw its own target-specific rejection.
  lowerJs: (p: Prepared) => string; // the runtime ECMAScript module (.mjs)
  lowerTs: (p: Prepared) => string; // a native, typed TypeScript module (.ts)
  lowerRust: (p: Prepared) => string; // whole-program Rust (== the `rs` tour pane)
  lowerJvm: (p: Prepared) => string; // Kotlin/JVM source (== the `jvm` tour pane)
  // one-shot String->String emitters (back-compat; e.g. the build smoke checks).
  compile: (src: string) => string;
  compileTs: (src: string) => string;
};

// The deploy base, slash-safe: `/rian-lab` on GitHub Pages (configure-pages emits
// no trailing slash), `/` locally. `BASE_URL` is build-time replaced.
const base = import.meta.env.BASE_URL.replace(/\/$/, "");
const compilerUrl = base + "/rian-compiler.mjs";

// lazy, shared singleton — the ~300KB module loads once across every editor on a page.
let compilerP: Promise<Compiler> | null = null;
export const loadCompiler = (): Promise<Compiler> =>
  (compilerP ??= import(/* @vite-ignore */ compilerUrl));
export const compilerLoaded = (): boolean => compilerP != null;

// A cheap "is the buffer obviously mid-edit?" check — NOT a parser, just enough to
// keep live eval quiet while a line is being written (the Rian parser is not yet
// error-recovering, so a half-typed line throws). Unbalanced delimiters/strings, an
// unclosed `do`, a dangling operator/keyword, or empty all read as incomplete.
export function looksIncomplete(srcText: string): boolean {
  const code = srcText.replace(/#[^\n]*/g, " "); // drop line comments
  if (code.trim() === "") return true;
  // single walk: balance delimiters AND collapse each string literal to a `0`
  // placeholder so the `do`/`end` and trailing-operator checks see only real code.
  let inStr = false,
    q = "",
    par = 0,
    brk = 0,
    brc = 0,
    bare = "";
  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    if (inStr) {
      if (c === q && code[i - 1] !== "\\") inStr = false;
      continue;
    }
    if (c === '"' || c === "'") (inStr = true), (q = c), (bare += "0");
    else {
      if (c === "(") par++;
      else if (c === ")") par--;
      else if (c === "[") brk++;
      else if (c === "]") brk--;
      else if (c === "{") brc++;
      else if (c === "}") brc--;
      bare += c;
    }
  }
  if (inStr || par > 0 || brk > 0 || brc > 0) return true;
  const doN = (bare.match(/\bdo\b/g) || []).length;
  const endN = (bare.match(/\bend\b/g) || []).length;
  if (doN > endN) return true;
  return /(:=|<~|<-|->|\|>|<>|[-+*\/<>=.,]|\b(?:and|or|not|when|do|else|div|rem|in)\b)\s*$/.test(bare.trim());
}

export type RunResult = { ok: boolean; text: string };

// Execute an emitted ECMAScript module in a sandboxed iframe (`allow-scripts`,
// opaque origin — no page access). Imports it from a blob URL; captures `console.log`
// (so `puts(…)` output shows), then calls `main()` if exported. The result text is the
// captured stdout, plus `main()`'s value when it returns one (a string verbatim; else
// `main() = <json>` — a `Unit`/undefined return contributes nothing).
export function runInSandbox(jsModule: string, timeoutMs = 4000): Promise<RunResult> {
  return new Promise((resolve) => {
    const frame = document.createElement("iframe");
    frame.sandbox.add("allow-scripts");
    frame.style.display = "none";
    let done = false;
    const finish = (r: RunResult) => {
      if (done) return;
      done = true;
      window.removeEventListener("message", onMsg);
      frame.remove();
      resolve(r);
    };
    const onMsg = (ev: MessageEvent) => {
      if (ev.source === frame.contentWindow && ev.data && ev.data.__rian) finish(ev.data.r);
    };
    window.addEventListener("message", onMsg);
    const runner =
      '<!doctype html><script type="module">' +
      "const code = " +
      JSON.stringify(jsModule) +
      ";" +
      "(async () => { let r; try {" +
      "  const __out = [];" +
      "  const __cap = (...a) => { __out.push(a.map(x => typeof x === 'string' ? x : (() => { try { return JSON.stringify(x); } catch { return String(x); } })()).join(' ')); };" +
      "  console.log = __cap; console.info = __cap; console.warn = __cap; console.error = __cap;" +
      "  const url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }));" +
      "  const mod = await import(url);" +
      "  let val = '';" +
      "  if (typeof mod.main === 'function') { const v = mod.main();" +
      "    if (typeof v === 'string') val = v;" +
      "    else if (v !== undefined && v !== null) val = 'main() = ' + JSON.stringify(v); }" +
      "  let text = __out.join('\\n');" +
      "  if (val) text = text ? text + '\\n' + val : val;" +
      "  if (!text) text = (typeof mod.main === 'function') ? '(no output)' : 'module loaded · exports: ' + Object.keys(mod).join(', ') + ' (define `main()` or call `puts(…)` to see output)';" +
      "  r = { ok: true, text };" +
      "} catch (e) { r = { ok: false, text: String((e && e.message) || e) }; }" +
      "  parent.postMessage({ __rian: true, r }, '*'); })();" +
      "<\/script>";
    frame.srcdoc = runner;
    document.body.appendChild(frame);
    setTimeout(() => finish({ ok: false, text: "timed out (" + timeoutMs + "ms) — a runaway loop?" }), timeoutMs);
  });
}

// strip the leading `Kind: ` an exception message often carries, for terser output.
export const cleanError = (e: unknown): string =>
  String((e && (e as any).message) || e).replace(/^\w+: /, "");

// ── shareable source state (the `#code=` permalink, ADR-0090) ────────────────
// A lab buffer round-trips through the URL *hash* (never the query — the source
// stays client-only, off the server/Pages logs). Encoding is synchronous
// base64url(utf8): no async on the load path, no dependency, and the tour cells
// are well under any URL limit. The build-time half (the by-example "Open in
// Lab" hrefs) computes the same string in Astro via `Buffer.toString("base64url")`,
// so the two sides agree byte-for-byte. (Deflate would shorten big pastes but is
// async + Safari-gated — deferred until sharing large buffers is a real need.)
export function encodeSource(src: string): string {
  const bytes = new TextEncoder().encode(src);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decodeSource(frag: string): string | null {
  try {
    const b64 = frag.replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "===".slice((b64.length + 3) % 4);
    const bin = atob(padded);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch {
    return null;
  }
}

// Read a shared buffer out of `location.hash` (`#code=<base64url>`), or null.
export function sharedFromHash(hash: string): string | null {
  const m = /^#code=(.+)$/.exec(hash);
  return m ? decodeSource(m[1]) : null;
}
