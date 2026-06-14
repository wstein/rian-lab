# ADR-0068 — `@external`: target-scoped FFI bodies, Reach-honest

**Status:** Accepted — **implemented (2026-06-14)** across `Rian.Decl` (parse), `Rian.Reach` (honest target set), `Rian.Check` (signature + `val`/`tag` restriction), and all four emitters (`Rian.Beam`/`Rian.JS`/`Rian.JVM`/`Rian.Lower`); `test/rian/external_test.exs`
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

- **Embedded quotes in a spec** — a spec containing `"` (e.g. a Rust `format!("{:.6}", x)`) needs the
  Rian lexer to support `\"` string escapes (a separate, general lexer gap; tracked). Until then specs
  must be quote-free.
- **Structured spec form** — a `module`/`function` reference (Gleam-style) as an optional, more
  checkable alternative to the raw expression, if a need appears.
