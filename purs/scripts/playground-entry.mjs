// Browser-bundle entry (ADR-0090): re-export the Rian compiler's public JS API from the
// stock-purs JS build (`output-js/`). `esbuild` inlines this + its transitive deps into one ESM
// artifact the playground loads. `compile :: String -> String` lowers Rian source to an ECMAScript
// module string; `compileTypes` produces the `.d.mts` TypeScript sidecar.
export { compile, compileTypes } from "../output-js/Rian.JS/index.js";
