// Browser-bundle entry (ADR-0090): re-export the Rian compiler's public JS API from the
// stock-purs JS build (`output-js/`). `esbuild` inlines this + its transitive deps into one ESM
// artifact the playground loads. `compile` lowers Rian source to an ECMAScript module string;
// `compileTypes` the `.d.mts` TypeScript declaration sidecar; `compileTs` a native typed `.ts` module.
export { compile, compileTypes, compileTs } from "../output-js/Rian.JS/index.js";
// The non-JS *source* emitters also run in-browser (they are pure PureScript, no toolchain): the
// whole-program Rust assembly (`rustProgram`, == the `rs` tour pane's `Rian.Lower.rust_program`) and
// the Kotlin/JVM emitter (`Rian.JVM.compile`, == the `jvm` pane). Aliased to avoid the `compile`
// name clash. (BEAM stays out — `Rian.Beam` needs `:compile.forms`, an Erlang/OTP runtime API.)
export { rustProgram as compileRust } from "../output-js/Rian.Lower.Rust/index.js";
export { compile as compileJvm } from "../output-js/Rian.JVM/index.js";
