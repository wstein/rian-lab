# Implementation plan — TypeScript `.d.ts` sidecar for the JS backend

**Resolves:** ADR-0086 §5 open item ("`.ts` source vs `.js`+`.d.ts` sidecar; how
capabilities/reach surface in the emitted types; whether `iso`/`val` leave any
TS-visible trace").
**Audience:** a junior developer picking up the work.
**Owner reference:** Maya Lin (emitters / TS view, ADR-0086).

## 1. What we are building and why

The JS emitter (`Rian.JS`) holds the full typed Core IR and **discards every type
at the boundary** — a TypeScript consumer importing the emitted `.mjs` sees `any`
everywhere. ADR-0086 §5 calls this "the one place Rian's type system currently
goes dark."

We close that gap by emitting a **TypeScript declaration sidecar** beside the
existing `<name>.mjs`, so the Rian module's public surface arrives **typed**,
checked by the consumer's own `tsc` across the FFI boundary.

**Sidecar extension — `.d.mts`, not `.d.ts`.** The runtime is ESM (`<name>.mjs`),
and TypeScript resolves an ESM module's declarations from the sibling `.d.mts`
(a `.d.ts` does *not* resolve for a relative `import "./prog.mjs"` — verified with
`tsc`). So the sidecar is `<name>.d.mts`, and the npm `package.json` gains a
`"types"` field pointing at it (for package-name imports). This is the concrete,
actually-resolving form of ADR-0086 §5's "`.js`+`.d.ts` sidecar".

Three decisions, locked (they answer the ADR-0086 §5 open item):

1. **`.js` + `.d.ts` sidecar**, *not* `.ts` source. The runtime `.mjs` is
   untouched; the `.d.ts` is a **second print mode** of the same backend — one
   extra annotation pass, bounded drift-tax (ADR-0086 §5 "one backend, two print
   modes"). Emitting `.ts` source would fuse runtime and types into one artifact
   and complicate the existing JS test/conformance path for no gain.
2. **Capabilities are fully erased — no TS-visible trace.** `val`/`iso`/`tag`/`ref`
   shape Rust signatures and BEAM linearity (ADR-0055); they have **no JS runtime
   meaning** (`Rian.JS` already lowers `ref` to value semantics), so they leave no
   mark in the `.d.ts`. A `Vec(T)` parameter is `T[]` whether it came in as `val`
   or `iso`.
3. **TS types are documentation, not a gate** (ADR-0086 §5 "honest scope limit").
   The reach gate stays `Rian.Reach` + the ADR-0087 property. The `.d.ts` describes
   what the `.mjs` *actually produces at runtime* — that is its only contract.

### Honesty bar (read this before writing the type mapper)

The `.d.ts` must describe the **real runtime values** the `.mjs` emits, never an
aspirational shape. Confirmed runtime representations in `Rian.JS`:

| Rian | JS runtime value | TS declaration |
|------|------------------|----------------|
| `Int` | `bigint` (`42n`) | `bigint` |
| `Int53`/`Int32`/`Int16`/`Int8`/`UInt32`/`UInt16`/`UInt8` | `number` | `number` |
| `Float64`/`Float32` | `number` | `number` |
| `Bool` | `boolean` | `boolean` |
| `String` | `string` | `string` |
| `Char` | `number` (codepoint) | `number` |
| `Symbol` (atom) | `string` | `string` |
| `Any` | dynamic | `unknown` (consumer must narrow — honest, unlike `any`) |
| `Vec(T)` | JS array | `Array<T>` |
| tuple `(A, B)` | JS array | `[A, B]` |
| `Fn(A, …, R)` | function | `(a0: A, …) => R` |
| `Result(T, E)` | `["ok", v]` / `["error", e]` | `["ok", T] \| ["error", E]` |
| `Option(T)` | `["Some", v]` / `["None"]` | `["Some", T] \| ["None"]` |
| `Union(A, B)` (ADR-0083) | a value of either | `A \| B` |
| sum `type C := Red \| Num(Int53)` | `["Red"]` / `["Num", 7]` | `["Red"] \| ["Num", number]` |
| `struct Point(x Int53, y Int53)` | `{__struct__:"Point", x, y}` | `interface Point { __struct__: "Point"; x: number; y: number }` |
| `Map(K, V)` / `Dict(K, V)` | JS object | `Record<K, V>` when K is `string`/`number`, else `unknown` |
| type variable `forall T` | erased | TS generic `<T>` |

Anything outside this set maps to **`unknown`** — honest "I cannot faithfully
describe this" rather than a wrong `any`. The mapper's scope is documented in the
`Rian.JS` moduledoc, mirroring how the emitter already documents its own scope.

## 2. Where the code lives (verified anchors)

- `lib/rian/js.ex` — the emitter. `compile/1` (`js.ex:140`) is the runtime print
  mode; we add `compile_types/1` beside it as the declaration print mode. Reuse:
  `all_funcs/1` (`js.ex:240`), `all_consts/1` (`js.ex:210`), `sum_ctor_map/1`
  (`js.ex:365`), `struct_name_set/1` (`js.ex:348`), and the gate prologue
  (`Decl.parse` → `Check.gate!` → `Rian.Opaque.erase`).
- `lib/rian/ir.ex` — the structs we read: `Func` (`pub?`, `params`, `ret`,
  `clauses`, `tvars`), `Param` (`name`, `type`), `Type`/`Variant`/`Field`,
  `Struct`, `Const`.
- `lib/rian/type_str.ex` — `split_top_commas/1`, `split_top_pipes/1`,
  `normalize/1` (rewrites `A | B` → `Union(A, B)`). Use these; do not hand-roll
  comma/pipe splitting.
- `lib/rian/build.ex` — `build_npm/5` (`build.ex:106`) writes the npm package;
  this is where the sidecar write goes.
- `test/rian/js_test.exs` — test patterns (shape assertions are unconditional;
  `node_eval/2` runs only when `node` is present).

## 3. Phases

### Phase 1 — the `.d.ts` emitter (`Rian.JS.compile_types/1`)

Add a public `compile_types(src) :: String.t()` that runs the **same gate prologue**
as `compile/1` (`Decl.parse` → `Check.gate!` → `Rian.Opaque.erase`) and emits, in
order:

1. `export type <Name> = …;` for every sum type (program-level + every `mod`),
   each variant a fixed-length tagged tuple; parametric types gain `<T, …>` from
   the type vars collected from variant fields.
2. `export interface <Name> { __struct__: "<Name>"; … }` for every struct.
3. `export const <NAME>: <T>;` for every `pub?` const.
4. `export function <name><…generics>(<p>: <T>, …): <Ret>;` for every `pub?`
   function with a non-empty clause list (FFI-only and private functions are not
   part of the module's export surface — exclude them).

Helpers to add (keep clause groups contiguous — `mix compile
--warnings-as-errors` is enforced):

- `ts_type(type_string, known, tvars) :: String.t()` — the type mapper (table
  above). `known` = `MapSet` of all declared type/struct/opaque/range names;
  `tvars` = the in-scope generic names (so a bare `T` renders as `T` here but a
  bare unknown name renders as `unknown`). Special-case `Option`/`Result` so they
  map even when not declared in the compiled program.
- `dts_func/3`, `dts_const/3`, `dts_sum/2`, `dts_struct/2`, `collect_tvars/2`.

Tests (`test/rian/js_test.exs`, new `describe` block): primitives → `number`/
`bigint`; `pub` vs private (private excluded); sum → tagged-union; struct →
interface with `__struct__` literal; `Vec`/`Fn`/tuple/`Option`/`Result`/`Union`;
generics (`forall T` → `<T>`); `Any` → `unknown`; the `unknown` fallback. Run the
emitted `.d.ts` through `tsc --noEmit` **only when `tsc` is available** (mirror the
`node_eval/2` self-skip), tagged `@tag :ts`, excluded from the default loop like
the other toolchain tests (`test/test_helper.exs` + `Rian.TestPolicyTest`).

**Commit:** `feat(js): TypeScript .d.ts sidecar print mode (ADR-0086 §5)`

### Phase 2 — wire the sidecar into the build pipeline

In `build_npm/5` (`build.ex:106`), after writing `<name>.mjs`, write
`<name>.d.ts` (same basename, same `_build/js/` dir) via the existing
`write_file/2`. `Rian.JS.compile/1` runs first, so an invalid-for-JS program fails
before any `.d.ts` is produced. Update the `build_npm` doc-comment and the module
`@moduledoc` to list the sidecar.

Tests: extend the build test to assert the `.d.ts` is written beside the `.mjs`
with matching basename and the expected exported signatures.

**Commit:** `feat(build): emit <name>.d.ts beside <name>.mjs (ADR-0082, ADR-0086)`

### Phase 3 — documentation

- **ADR-0086 §5**: add an `Amended <date>` note resolving the open item with the
  three locked decisions; flip the §5 slice of the `Implemented:` line; strike the
  `§5 TS emit detail` open item. Note the forward-pattern for ADR-0085's dynamic
  triad (a typed view over a dynamic target reuses this print-mode shape) **without
  widening anything or adding a target** — the §5a gate and target budget stand.
- **ADR-0049**: fold the `.d.ts` sidecar into the "ECMAScript module/interop
  conventions" open item.
- **docs/README.md**: reflect the new capability in the ADR-0086 row / status.
- **CLAUDE.md**: one line on the `Rian.JS` TS print mode in the architecture
  section.

**Commit:** `docs: record .d.ts sidecar decision (ADR-0086 §5, ADR-0049)`

## 4. Definition of done

- `mix format`, `mix compile --warnings-as-errors`, `mix dialyzer` clean.
- New tests pass; coverage stays at/above baseline.
- `rian build --js -o OUT` produces `OUT/_build/js/<name>.d.ts` whose declarations
  type-check against the sibling `.mjs` under `tsc`.
- ADR-0086 §5 open item resolved; docs consistent with code.
