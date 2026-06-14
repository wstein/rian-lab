# ADR-0068 — `@external`: target-scoped FFI bodies, Reach-honest

**Status:** Accepted (direction) — unimplemented; gated on the declaration parser (ADR-0031 Stage 0.1) and `Rian.Reach`
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

## Open items

- **Spec string format per target** — a raw expression (as above) vs a structured `module`/`function`
  reference (Gleam uses the latter for Erlang/JS). Raw is more flexible but less checkable; decide per
  target.
- **Capabilities through an external** — what `iso`/`ref` mean across an FFI boundary (linearity is not
  enforced in foreign code); likely restrict `@external` params to `val`/`tag` initially.
- **Partial-coverage ergonomics** — a lint when an `@external` set is narrower than the module's
  `@targets(…)` (ADR-0058) build default, so a missing target body is surfaced early, not at emit.
