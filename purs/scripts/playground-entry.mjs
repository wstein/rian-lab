// Browser-bundle entry (ADR-0090): re-export the Rian compiler's public JS API from the
// stock-purs JS build (`output-js/`). `esbuild` inlines this + its transitive deps into one ESM
// artifact the playground loads. `compile` lowers Rian source to an ECMAScript module string;
// `compileTypes` the `.d.mts` TypeScript declaration sidecar; `compileTs` a native typed `.ts` module.
export { compile, compileTypes, compileTs } from "../output-js/Rian.JS/index.js";
