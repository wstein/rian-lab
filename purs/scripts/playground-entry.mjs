// Browser-bundle entry (ADR-0090): re-export the Rian compiler's public JS API from the
// stock-purs JS build (`output-js/`). `esbuild` inlines this + its transitive deps into one ESM
// artifact the playground loads.
//
// The live engine lowers via the **parse-once** front door (`Rian.Lower.All`): `prepare` runs the
// shared front-end (lex → Pratt → Core → assemble → tail → type-gate) ONCE and returns an opaque
// checked program; `lowerJs`/`lowerTs`/`lowerRust`/`lowerJvm` then lower it per target (each may
// raise its own target-specific rejection — caught per pane). BEAM stays out: `Rian.Beam` needs
// `:compile.forms`, an Erlang/OTP runtime API with no browser equivalent.
export { prepare, lowerJs, lowerTs, lowerRust, lowerJvm } from "../output-js/Rian.Lower.All/index.js";
// One-shot `String -> String` emitters kept for back-compat + the build/bundle smoke checks.
export { compile, compileTypes, compileTs } from "../output-js/Rian.JS/index.js";
