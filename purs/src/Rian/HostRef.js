// JS FFI for `Rian.HostRef` (ADR-0090) — the JS-backend counterpart of `HostRef.erl`.
//
// `refExported` resolves an `@external` `Mod.fun`/`:erlang.fun` reference's arity by inspecting the
// BEAM module table (`code:ensure_loaded`/`erlang:function_exported`). A browser or node host has no
// such table, so the reference is **unverifiable** — and the contract (ADR-0068/0041 §2) is to
// conservatively ACCEPT an unverifiable reference (the `.erl`'s "module cannot be loaded → true"
// branch), never a false error. `@external` bodies are `:ex`-pinned by Reach and never reach the JS
// target anyway, so this only affects the gate's acceptance, not emitted code.
//
// curried `Array String -> Boolean -> Int -> Boolean` (purs FFI calling convention).
export const refExported = (parts) => (erlang) => (arity) => true;
