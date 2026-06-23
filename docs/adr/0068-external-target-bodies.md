# ADR-0068 — `@external`: target-scoped FFI bodies, Reach-honest

**Status:** Accepted — **implemented (2026-06-14)** across `Rian.Decl` (parse), `Rian.Reach` (honest target set), `Rian.Check` (signature + `val`/`tag` restriction), and all four emitters (`Rian.Beam`/`Rian.JS`/`Rian.JVM`/`Rian.Lower`); `test/rian/external_test.exs`. **Reference form** `@external(:t, Mod.fun)` (the preferred, Gleam-aligned spelling) + boundary resolution added 2026-06-18 (§1b); inline strings demoted to interim, file-references deferred to ADR-0080 §7
**Implemented:** yes — `Rian.Decl`/`Rian.Reach`/`Rian.Check` + all four emitters (`test/rian/external_test.exs`)
**Refs:** ADR-0057 (concurrency & FFI are native-per-target — the principle this gives a surface), ADR-0058 (configurable target environments; **inferred** reachability, *not* a binary `@shared` flag), ADR-0056 (`comptime if target` — the *adjacent but distinct* mechanism; see §4), ADR-0041 §2 (an unmapped host call is a compile error, never a silent stub), ADR-0035 (no hidden control flow / what-you-read-is-what-runs), ADR-0050 (one typed Core IR)
**Owners:** Elena Rostova (FFI / lowering) · Maya Lin (emitters / the anti-`#if` position) · Samir Patel (no-silent-stub guard) · Arthur Pendelton (Reach) · Kira Neri (honesty) · Rachel Okafor (PM)
**Origin:** the Gleam/Haxe borrow debate (2026-06-14) — consensus #2, rated **4/5**. Borrow Gleam's disciplined `@external`, explicitly **reject** Haxe's `#if` scattered through bodies.

## Context

ADR-0057 settled that **concurrency and host FFI are native-per-target**: you write pure logic once in
Rian and call it from a native gen_server / task / worker. But it left a gap for the *sequential* FFI
case — a function whose **whole body is a host call that differs per target**:

- a native scalar formatter, a platform clock, a crypto primitive, a binding to a target library;
- today such a function has no surface to express "BEAM body = `:erlang.foo`, JS body =
  `import {foo}`", so it is written with a single host call and **`Rian.Reach` pins it to `:ex`**
  (ADR-0058) — it silently cannot reach JS/Rust even when an equivalent host function exists there.

Two languages bracket the design:

- **Haxe** uses `#if js … #elseif cpp … #end` *inside* function bodies. The debate **rejected** this
  (1/5): once target-conditionals live in ordinary code, portability stops being a property the
  compiler *proves* (ADR-0058) and becomes one the programmer *asserts* — and `#if` is not
  machine-readable by a reachability pass.
- **Gleam** uses `@external(erlang, "mod", "fun")` / `@external(javascript, "./ffi.mjs", "fun")` — a
  **declaration-site annotation**, one host binding per target, the function having no portable body.
  This is the disciplined version: the conditionality lives at a boundary `Rian.Reach` can read.

This ADR adopts the Gleam mechanism.

## Decision

### 1. `@external(:target, "spec")` declares a per-target host body

A function has **either** a portable Rian body **or** one or more `@external` bodies — never both for
the *same* target:

```rian
@external(:ex, ":erlang.float_to_binary(x, [{:decimals, 6}])")
@external(:js,  "x.toFixed(6)")
@external(:rs,  "format!(\"{:.6}\", x)")
pub def format6(x val Float64) String
```

- The **signature is checked once, portably** (types, capabilities ADR-0055, error set ADR-0040). Only
  the **body** is per-target.
- The **observable contract is uniform** (ADR-0041): every target's body must honour the *same*
  declared in/out types. The compiler checks the signature; the *equivalence* of the host bodies is
  the author's obligation, exactly as for any FFI (this is FFI, not magic).

### 1b. Two spec forms: a **reference** (preferred) or an inline **string** (interim)

The spec after `@external(:target, …)` is one of:

- **A function reference (preferred, the Gleam model — implemented 2026-06-18):** `@external(:ex,
  :erlang.binary_to_list)` (an Erlang MFA) or `@external(:ex, Rian.Beam.load_result)` (an Elixir/Rian
  module function). It lowers to a **positional call** — the Rian params are passed in order:
  `:erlang.binary_to_list(s)`, `Rian.Beam.load_result(src, module)`. The foreign code lives in a **real,
  tooled, testable file** (host highlighting, host type-checking, host unit tests — resolving the
  ADR-0048 error-path-testability dissent), and the reference is **machine-readable at the boundary**:
  `Rian.Check` *resolves* it — a reference to a function/arity that the (loadable) host module does not
  export is a **compile error** (the no-silent-stub guarantee, ADR-0041 §2; best-effort — an
  un-loadable module can't be verified, so it isn't rejected). This is the form the transpiler emits for
  a `@rian_host` boundary (`@external(:ex, Rian.Mod.fun)`, ADR-0081 §5) — delegating to the tested
  original, no escaped host blob.
- **An inline host-expression string (interim):** `@external(:ex, ":erlang.float_to_binary(x)")`. Each
  emitter splices it as the body (the params are in scope by name). Self-contained and unblocked, but
  **opaque** — no host highlighting/checking, escape-fragile for multi-line bodies, and untestable until
  spliced. Retained for raw single expressions and for FFI that *constructs* its arguments
  (`:erlang.error({:type_error, name})`, `:compile.forms(forms, [:return_errors])`) which a positional
  reference cannot express without an authored foreign wrapper.

A **file reference** `@external(:js, "./ffi.mjs", "fun")` (Gleam's non-BEAM form) parses to a
`{:file, path, fun}` spec and is **resolved** at build time (`Rian.External.resolve/2`, wired into
`rian build`): the file must exist beside the source and a `.ex`/`.exs` must export the named function at
the right arity, else the build fails closed (ADR-0080 §7 a/c). It is then **bundled** (ADR-0080 §7 b)
for **all four targets**: **BEAM** (`Rian.External.lower_beam/2` compiles the `.ffi.ex` and rewrites the
`@external` to a module-reference), **JS** (`rian build --js -o DIR` copies the `.ffi.mjs` and emits an
ESM `import`), **Rust** (`--rust -o DIR` copies the `.ffi.rs` and includes it as a `#[path] mod`), and
**JVM** (`--jvm -o DIR` copies the `.ffi.kt` to the same package, compiled together by `kotlinc`). Each
is verified end-to-end against its toolchain.

**Deprecation path for the inline string.** The reference form is the destination; the string form is
demoted to a constrained convenience. The ADR-0080 §7 build integration that wrapper migration needs is
now **complete** (file-references bundle on all four targets), so removal is gated only on that migration
("once references are ergonomic enough" — the 2026-06-18 debate consensus).

The string and module-reference forms lower through **one** emitter helper (`Rian.External.render/2`): a
string passes through; a reference renders to its positional call. A file-reference is bundled per target
by the build (it never reaches `render/2`). `Rian.Reach` and the effect view are unchanged across all
forms (they read the target *keys*, never the spec).

### 2. Reach computes the target set from the annotations (the honesty rule)

`Rian.Reach` reads `@external` annotations directly:

> a function's reachable target set = (the inferred reach of its portable body, if any) ∪ (the set of
> targets that have an `@external` body).

So `format6` above reaches `[:ex, :js, :rs]` and is honestly **off `:jvm`** (no Kotlin body) — the
reach report says so, and the `:jvm` emitter never sees it. A partial set is fine and normal: an
`@external` only for `:ex` reaches exactly `[:ex]` (today's implicit behaviour, now *explicit*).
**There is no `#if` inside portable logic** — target-conditionality exists *only* at this declaration
boundary, which is the whole point.

### 3. Emitters lower the matching external

Each emitter, when it sees a function with an `@external` for its target, emits the host call form it
already knows — a BEAM remote call (`Beam`), a JS import/expression (`JS`), a Rust path/`extern`
(`Lower`), a Kotlin call (`JVM`). An emitter asked to lower a function that has **no** body for its
target is a compile error (ADR-0041 §2 — never a silent stub); Reach prevents that from arising by
pinning the function off that target first.

**Void externals return `Unit`, not `Symbol` (the empty type).** A console-style host call produces no
meaningful value, and its natural per-target result *differs*: BEAM `IO.puts` → `:ok`, JS `console.log`
→ `undefined`, Rust `println!` → `()`, Kotlin `println` → `Unit`. Declaring such a wrapper `Symbol` was
a cross-target lie (only the BEAM result is an atom) **and** pinned it off the typed targets, whose
calls return no `Symbol` (a `fn puts(s) -> Symbol { println!(…) }` is a `rustc` error). The honest type
is **`Unit`** — the empty type: it erases on BEAM/JS, and lowers to Rust `()` and Kotlin `Unit`
(`Rian.Capability.rust_name("Unit") = "()"`, `Rian.JS` TS `Unit → void`). So one host body per target
type-checks everywhere, and a void external like `Console.puts` reaches **all four** targets rather than
being falsely capped at `:ex`/`:js`. The generative tripwire (`Rian.ExternalReachHonestyTest`) compiles
each claimed typed target so a `Unit`-return regression (e.g. an emitter passing `Unit` through as a
literal type) fails CI.

**A polymorphic external states its precondition with `forall T: Bound`.** Host FFI is frequently
generic — `dump(x T) String forall T: Eq`, a `print` over `Show` — and the bound is not decoration: an
external has no Rian body for the checker to read, so the bound is the *only* place its requirement on
`T` is written. `check_bounds` enforces it at **every call site** exactly as for an ordinary bounded
generic (ADR-0042 §2): `dump(noEqValue)` is rejected with `` `dump` requires `T: Eq`, but `NoEq` has no
`impl Eq for NoEq` ``, while `dump(5)` (an `Int53` with an `Eq` impl) passes. The bound rides the
signature (`Func.bounds`), not a clause, so it composes with the empty-`clauses` external shape.
*Reach pinning on the bound's protocol reach is deferred:* it only bites when a bound protocol is
unsatisfiable on a target the function otherwise reaches, which has no current instance (`Eq`/`Ord`/
`Show` reach broadly), and the generative tripwire already fails CI on the downstream symptom (a
generic external whose lowered trait-bounded signature does not compile on a typed target).

### 3b. Auto-injected portable `puts`/`print` (the console front door)

The raw void externals are `line`/`write` (a host line / raw write per target — `IO.puts`/
`console.log`/`println`). On top sit two **portable polymorphic front doors**, `puts`/`print`, that
take a `String | Int53` **value union** (ADR-0083) so a number prints without an explicit conversion
(`puts(2 + 5)` → `7`; the `Int53` arm stringifies via `Prim.int_to_string`, the `${n}` member-narrowing
of ADR-0069). All four are **top-level** (not a `mod`): `puts` calls `line` as a *local* call so Reach
threads `line`'s target set in (a cross-module call is assumed portable), and it avoids a `mod IO`
shadowing the host `IO` on the BEAM.

Unlike the BEAM-linked `Str`/`List`/`Dict` prelude, the IO functions are **emitted into the program**
when referenced: `Rian.Decl.inject_stdlib` (and its PS twin `Rian.Assemble.injectStdlib`) splices in
`Rian.IOStdlib`'s functions for any program that calls `puts`/`print` and doesn't define its own — so
`puts` actually runs on a source target (`console.log`/`println`/`IO.puts`) rather than dangling, with
no import or boilerplate. The bodies are the canonical source `examples/rian/prelude_io.rian`
([`20_io.rian`](../../examples/rian/20_io.rian) is the by-example).

**Reach `[:ex, :js, :jvm]`, honestly OFF `:rs` (for now).** The value-union arm hands `line`'s `&str`
host parameter an owned `String` member, and the Rust owned→borrow coercion across a value-union arm
is a tracked follow-up — so the matrix reports `:rs` off rather than a false claim. (`line`/`write`
themselves carry no `:rs` host body.) The effect annotation `@effects(host, io)` is dropped from
`line`/`write`: the PS effect checker does not yet infer an `@external` as host-effectful and rejects
over-declaration (ADR-0048 §3); the effect is still performed by the host call.

### 4. Relationship to ADR-0056 (`comptime if target`) — distinct, not redundant

- **ADR-0056** selects among **Rian** representations at compile time (two portable bodies, pick one
  per target) — it is *dormant* because the goal clarification (concurrency native-per-target) removed
  its motivation.
- **ADR-0068** declares **host (non-Rian) bodies** — there is no portable Rian body to select; the
  implementation *is* the foreign call. This is the FFI surface ADR-0057 implied and never spelled.

They do not overlap: one is "which Rian code", the other is "which host call".

## Rationale

- **Turns `:ex`-pinned FFI into honestly-multi-target functions** — the reach matrix gets *more*
  accurate, not less.
- **Keeps Reach the single source of truth** (ADR-0058): the annotation is machine-readable; `#if` is
  not. This is *why* Gleam's spelling beats Haxe's for us.
- **No new hidden control flow** (ADR-0035): the per-target body is declared at the signature, visible,
  not woven through logic.

## Consequences

- **`Rian.Decl`** parses one-or-more `@external(:target, "spec")` attributes preceding a bodiless `def`.
- **`Rian.Reach`** unions external targets into the reachable set (a new, simple input alongside the
  body scan).
- **Emitters** gain an `@external` lowering per target (mostly a thin pass-through of the spec string
  into the target's call syntax).
- **`Rian.Check`** verifies the signature once; it does **not** check host-body equivalence (FFI is
  trusted, per ADR-0026/0027 free-FFI).

## Resolved (in the 2026-06-14 implementation)

- **Spec string format per target** — chose a **raw host expression** string per target, with the
  function's parameters in scope by name. `:ex` is a *Rian-surface* FFI expression (an atom-head
  remote call like `:erlang.float_to_list(x, …)`), spliced as the BEAM function body and lowered
  through the normal Core → abstract-forms path (reusing the existing FFI lowering — no Erlang parser).
  `:js`/`:jvm`/`:rs` are *raw target source* injected verbatim (JS/Kotlin bind `const x = a0;`/`val x
  = a0;`; Rust names params directly). Flexible over the structured `module`/`function` form; the
  spec's correctness is the author's obligation, as for any FFI.
- **Capabilities through an external** — restricted to `val`/`tag` (an `iso`/`ref` param is a
  `Rian.Check` error): linearity cannot be enforced across a foreign boundary.
- **Partial-coverage ergonomics** — handled by the existing **`@targets` gate** (ADR-0058): a `pub`
  external whose body set is narrower than the module's required targets fails `Reach.check_contracts`
  with a clear "cannot reach […]" error, surfaced at the gate, before emit.

## Open items

- **Embedded quotes in an inline-string spec** — a string spec containing `"` (e.g. a Rust
  `format!("{:.6}", x)`) needs the Rian lexer's `\"` escape; until then string specs must be quote-free.
  *The reference form sidesteps this entirely* (no host string), which is another reason it's preferred.
- ~~**File-reference bundling (ADR-0080 §7 b)**~~ — *resolved (2026-06-18):* `@external(:t, "./ffi.x",
  "fun")` is parsed, **resolved** (`Rian.External.resolve/2`), and **bundled on all four targets**
  (compile + module-ref / copy + ESM import / copy + `#[path] mod` / copy + same-package compile), each
  toolchain-verified. Removing the inline-string form now hinges only on migrating the self-hosting
  compiler's construct-the-args FFI to authored wrappers.
- ~~**Structured spec form**~~ — *resolved (2026-06-18):* the reference form `@external(:t, Mod.fun)` /
  `:erlang.fun` is implemented (§1b), with boundary resolution in `Rian.Check`.
