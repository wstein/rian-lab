// JS FFI stub for `Rian.Beam` (ADR-0090) — the Erlang abstract-forms / BEAM emitter is
// purerl-only; its real FFI is `Beam.erl`. BEAM lowering needs Erlang's `:compile.forms`, which
// has no JS-backend equivalent, so `Rian.Beam` never reaches the JS target (and esbuild
// tree-shakes it out of the playground bundle). The stock-purs JS build nevertheless compiles
// every `src/**` module, so these symbols must EXIST for it to link — they are never called on
// the JS backend, and throw if they somehow are, to surface the misuse.
const unavailable = (name) => () => {
  throw new Error("Rian.Beam." + name + " is purerl-only — not available on the JS backend");
};

export const mkAtomTerm = unavailable("mkAtomTerm");
export const mkIntStr = unavailable("mkIntStr");
export const mkIntI = unavailable("mkIntI");
export const mkFloatStr = unavailable("mkFloatStr");
export const mkBinary = unavailable("mkBinary");
export const strBytes = unavailable("strBytes");
export const mkTuple = unavailable("mkTuple");
export const mkList = unavailable("mkList");
export const runModulesImpl = unavailable("runModulesImpl");
