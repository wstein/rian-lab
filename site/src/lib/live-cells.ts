// Wire every `LoweredCell` on a page into a live editor: edit the source and it re-compiles +
// runs in your browser (the same in-browser Rian compiler the playground uses, ADR-0090),
// forgiving of half-typed input (`looksIncomplete`) and keeping the last good JS pane on a
// transient error. JS/Rust/JVM all re-lower live (pure-PureScript emitters); only BEAM needs the
// Erlang toolchain, so on an edit its pane shows a note.
//
// Shared by `pages/by-example.astro` (the whole tour) and `pages/home.astro` (the hero demo) so
// the front page and the tutorial run the identical, proven live-cell behavior. The ~380KB
// compiler module loads lazily on first edit (inside `liveEval`), so it never taxes initial paint.
import { highlight } from "./highlight";
import type { Compiler, Prepared } from "./rian-live";
import { loadCompiler, looksIncomplete, runInSandbox, cleanError } from "./rian-live";

export function wireLiveCells(root: ParentNode = document): void {
  root.querySelectorAll<HTMLElement>("[data-cell-id]").forEach((cell) => {
    const ta = cell.querySelector<HTMLTextAreaElement>("[data-cell-src]");
    const hlEl = cell.querySelector<HTMLElement>("[data-cell-hl]");
    const outEl = cell.querySelector<HTMLElement>("[data-cell-out]");
    const jsPane = cell.querySelector<HTMLElement>('[data-cell-pane="js"]');
    if (!ta || !hlEl || !outEl || !jsPane) return;
    const rsPane = cell.querySelector<HTMLElement>('[data-cell-pane="rs"]');
    const jvmPane = cell.querySelector<HTMLElement>('[data-cell-pane="jvm"]');
    const exPane = cell.querySelector<HTMLElement>('[data-cell-pane="ex"]');
    const original = ta.value;
    // the verified reference emissions, restored when the buffer matches the original
    const refJs = jsPane.innerHTML;
    const refRs = rsPane?.innerHTML ?? "";
    const refJvm = jvmPane?.innerHTML ?? "";
    const refEx = exPane?.innerHTML ?? "";
    const noteEx =
      "// ⓘ BEAM · Elixir isn't lowered in-browser — it needs the Erlang\n// toolchain (`:compile.forms`). Flip back to the original to see the reference.";
    const noteUnsupported = (label: string) => `// ⓘ the ${label} emitter doesn't lower this construct yet.`;

    let timer = 0;
    let gen = 0;
    const setOut = (kind: string, text: string) => ((outEl.dataset.kind = kind), (outEl.textContent = text));

    async function liveEval() {
      const g = ++gen;
      const source = ta!.value;
      if (source === original) {
        // unedited: restore every verified reference pane.
        jsPane!.innerHTML = refJs;
        if (rsPane) rsPane.innerHTML = refRs;
        if (jvmPane) jvmPane.innerHTML = refJvm;
        if (exPane) exPane.innerHTML = refEx;
        setOut("idle", "▷ edit the source to compile + run it live");
        return;
      }
      if (looksIncomplete(source)) {
        setOut("hint", "▍ keep typing…");
        return;
      }
      let js: string;
      let prep: Prepared;
      let compiler: Compiler;
      try {
        compiler = await loadCompiler();
        if (g !== gen) return; // a newer keystroke superseded this run
        prep = compiler.prepare(source); // parse + type-check ONCE (ADR-0090)
        js = compiler.lowerJs(prep);
      } catch (e) {
        if (g !== gen) return;
        setOut("soft", "… " + cleanError(e)); // keep the last good JS pane
        return;
      }
      jsPane!.innerHTML = highlight(js);
      // JS gated it (the buffer parses + checks), so re-lower the other source targets off the
      // shared result; a Rust/JVM failure is an honest "this construct isn't covered yet". BEAM
      // can't lower here.
      if (rsPane) {
        try {
          rsPane.innerHTML = highlight(compiler.lowerRust(prep));
        } catch {
          rsPane.innerHTML = highlight(noteUnsupported("Rust"));
        }
      }
      if (jvmPane) {
        try {
          jvmPane.innerHTML = highlight(compiler.lowerJvm(prep));
        } catch {
          jvmPane.innerHTML = highlight(noteUnsupported("JVM · Kotlin"));
        }
      }
      if (exPane) exPane.innerHTML = highlight(noteEx);
      setOut("ok", "✓ compiled to JS — running…");
      const res = await runInSandbox(js);
      if (g !== gen) return;
      setOut(res.ok ? "ok" : "soft", res.ok ? "▷ " + res.text : "✗ runtime: " + res.text);
    }

    ta.addEventListener("input", () => {
      hlEl.innerHTML = highlight(ta.value) + "\n";
      clearTimeout(timer);
      timer = window.setTimeout(liveEval, 320);
    });
    ta.addEventListener("scroll", () => {
      hlEl.scrollTop = ta.scrollTop;
      hlEl.scrollLeft = ta.scrollLeft;
    });
  });
}
