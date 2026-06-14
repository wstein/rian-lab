// A small, language-agnostic syntax highlighter for the Rian site's code panes.
// It is deliberately token-shape based (not a real grammar): one pass colors
// comments, strings, numbers, capitalized type/constructor names, function-ish
// call heads, and a keyword set spanning Rian, Elixir, Rust, JS and Kotlin. That
// is enough to read the lowered output across all four targets with one
// consistent palette, and it never invents semantics the compiler did not.

const KEYWORDS = new Set([
  // Rian + shared
  "def",
  "type",
  "struct",
  "alias",
  "range",
  "val",
  "iso",
  "ref",
  "tag",
  "when",
  "do",
  "end",
  "if",
  "else",
  "case",
  "with",
  "forall",
  // Elixir
  "defmodule",
  "defp",
  "fn",
  "match",
  // Rust
  "enum",
  "impl",
  "trait",
  "pub",
  "let",
  "mut",
  // JS / Kotlin
  "function",
  "return",
  "switch",
  "const",
  "var",
  "throw",
  "new",
  "is",
  "when",
  "sealed",
  "interface",
  "data",
  "class",
  "object",
  "private",
  "fun",
  "val",
  "run",
]);

const escapeHtml = (s: string): string =>
  s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

const span = (cls: string, text: string): string =>
  `<span class="${cls}">${escapeHtml(text)}</span>`;

// Match, in priority order: line comments, strings, numbers, identifiers, and a
// catch-all single char so nothing is dropped.
const TOKEN =
  /(#[^\n]*|\/\/[^\n]*)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(\b\d[\d_]*(?:\.\d+)?[a-zA-Z]*\b)|([A-Za-z_][A-Za-z0-9_]*)|([\s\S])/g;

export function highlight(code: string): string {
  let out = "";
  let m: RegExpExecArray | null;
  TOKEN.lastIndex = 0;

  // remember the previous non-space token so an identifier right after `def`/`fn`
  // can be colored as a function name.
  let prevWord = "";

  while ((m = TOKEN.exec(code)) !== null) {
    const [, comment, str, num, ident, other] = m;
    if (comment !== undefined) {
      out += span("sx-com", comment);
    } else if (str !== undefined) {
      out += span("sx-str", str);
    } else if (num !== undefined) {
      out += span("sx-num", num);
    } else if (ident !== undefined) {
      if (KEYWORDS.has(ident)) {
        out += span("sx-kw", ident);
      } else if (prevWord === "def" || prevWord === "defp" || prevWord === "fn" || prevWord === "fun" || prevWord === "function") {
        out += span("sx-fn", ident);
      } else if (/^[A-Z]/.test(ident)) {
        out += span("sx-type", ident);
      } else {
        out += escapeHtml(ident);
      }
      prevWord = ident;
      continue;
    } else if (other !== undefined) {
      out += escapeHtml(other);
    }
    if (comment === undefined && str === undefined && num === undefined) prevWord = "";
  }
  return out;
}

export const TARGET_META: Record<string, { label: string; dot: string }> = {
  ex: { label: "BEAM · Elixir", dot: "#a78bfa" },
  rs: { label: "Rust", dot: "#fb923c" },
  js: { label: "JavaScript", dot: "#7dd3fc" },
  jvm: { label: "JVM · Kotlin", dot: "#2dd4bf" },
};
