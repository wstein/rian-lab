# ADR-0047 — Portable Prelude & Stdlib: three tiers, hybrid implementation, `Option` not `nil`

**Status:** Accepted (direction) · the *contents* fill incrementally; this ADR fixes the *model*
**Implemented:** partial — primitive layer (`Rian.Prim`, `test/rian/prim_test.exs`) + portable prelude written in Rian (`examples/rian/prelude_{int,str,dict}.rian`); contents fill incrementally. The `Prim.* → __prim_*` normalization (§2) is itself **self-hosted** — `compiler/prim.rian` (`PrimNorm.normalize`) reproduces `Rian.Prim.normalize`, fixpoint-locked in `test/rian/prim_fixpoint_test.exs` (ADR-0063 #2)
**Refs:** ADR-0027 (free BEAM FFI; self-hosting), ADR-0029 (dot qualifier), ADR-0034 (nominal sums; `Option`), ADR-0035 (no hidden control flow), ADR-0040 (`Result`), ADR-0041 (target model — "Rian prelude provided on every target"; module resolution), ADR-0042 (protocols), ADR-0046 (compile-time by default)
**Owners:** Chloe Bennett (prelude) · Arthur Pendelton (stdlib-in-Rian) · Elena Rostova (primitives/perf) · Maya Lin (tiers/multi-target) · Kira Neri (determinism) · Samir Patel (conformance) · Marcus Chen (effect boundary) · Liam Davis (namespacing) · Rachel Okafor (PM)

## Context

ADR-0041 already *references* "the Rian prelude — provided on every target" as one of three
module-resolution kinds, but the prelude/stdlib was never defined. The multi-target reality
(JVM/Rust/Go/BEAM/JS/WASM) is what kept it open: the BEAM has a rich stdlib (`:lists`, `:maps`,
`Enum`) available as **free FFI** (ADR-0027), but that stdlib is **BEAM-only**. The *portable* surface
must be defined independently of it. This ADR fixes the **model** (tiers, implementation strategy,
observable-semantics policy, and the absence type); it does **not** enumerate every function — that
fills incrementally, like ADR-0041's std-mapping table.

## Decision

### 1. Three tiers

| Tier | Scope | Resolution (ADR-0041) |
|---|---|---|
| **Portable prelude** | auto-in-scope, every module, every target | the Rian prelude — always provided |
| **Portable stdlib** | explicit import, every target, documented semantics | the Rian prelude/stdlib — always provided |
| **BEAM-stdlib FFI** | `:lists`/`:maps`/`Enum` — **free on BEAM**, **map-or-compile-error elsewhere** | BEAM-stdlib module (ADR-0041 §4) |

Tiers 1–2 are the **guaranteed-everywhere** surface, defined independently of the BEAM stdlib. Tier 3
is the BEAM bonus, already governed by ADR-0041 (never a silent stub off-BEAM).

### 2. Hybrid implementation — a thin primitive layer + the stdlib written in Rian

A **small per-target primitive/intrinsic layer** (the irreducible native ops — allocate/index/length a
`Vec`, hash, byte access) underlies a stdlib **written once in Rian** (`List.map`/`filter`/`fold`, …)
over those primitives. This minimizes per-target maintenance, maximizes semantic consistency, is
**self-hosting-aligned** (ADR-0027 — the stdlib compiles like any Rian code under ADR-0046), and lets a
hot primitive **delegate to the target's native lib** where it pays (BEAM `List.map` → `:lists.map`;
Rust → iterator). The all-in-Rian and N-hand-written-native alternatives are **rejected** (no
primitives / a semantic-drift bug farm, respectively).

**Surface of the primitive layer — the reserved `Prim.*` namespace (implemented).** The intrinsics
are spelled `Prim.str_chars`, `Prim.char_code`, `Prim.map_get`, … in source. `Prim` is a **reserved,
target-internal, unstable** namespace: `Rian.Pratt` rewrites a `Prim.<name>(args)` call to the
canonical intrinsic `__prim_<name>(args)` at the parse boundary (one chokepoint, before any
downstream walker), and **only the registered intrinsic names rewrite** (`Rian.Prim.names/0`) — an
unknown `Prim.x` is a hard compile error, never a silently-bogus `__prim_x`. User code never writes
`Prim.*`; it goes through the portable wrappers (`Str.chars/1`, `Char.code/1`, `Dict.get/2`), which
are the stdlib-in-Rian over the primitives. The bare `__prim_*` form is legacy and no longer appears
in tour or self-hosting `.rian` source.

**Not every intrinsic is all-target.** Most primitives lower on every Tier-1 target, but a few are
intentionally target-restricted and `Rian.Reach` pins a caller off the targets that cannot lower them
— keeping the gate honest against the emitters (ADR-0058): the 64-bit overflow ops
(`Prim.wrapping_add`/`saturating_add`/`checked_add`) are off `:js` (no `Int64` representation, ADR-0064 §2a),
and `Prim.str_to_atom` (string→atom interning) is **BEAM-only** — atoms have no Rust/JS/JVM value, so a
body that calls it reaches `:ex` alone. `Prim.to_string` (the runtime-`Show` fallthrough for an
`:unknown`-typed interpolation hole, ADR-0069 §2) is off `:rs` — BEAM `String.Chars.to_string`, JS
`String(x)`, JVM `.toString()` are universal runtime stringifiers, but Rust has no universal `Display`,
so it reaches `:ex`/`:js`/`:jvm`. These power the BEAM self-hosting backends (`selfhost_compose*.rian`),
which emit Erlang abstract forms and are BEAM-pinned by construction.

### 3. No `nil` — absence is `Option(T) = Some(T) | None`

Rian has **no `nil`**. Absence is the nominal sealed sum **`Option(T) = Some(T) | None`** (ADR-0034).
This is a deliberate **divergence from the family** (Elixir/Ruby/Crystal have `nil`; Crystal even has
nilable `String?`), justified by Rian's own principles — exactly as `:=`/`<~` diverged:

- **No hidden control flow / no null-propagation** (ADR-0035): there is no pervasive nullable type that
  silently inhabits every type.
- **Exhaustiveness** (ADR-0034): a `case` on `Option(T)` is total-checkable; a `nil` slipping through
  any type defeats the gate.
- **Nominal sums canonical** (ADR-0034): `String?` = `String | Nil` is structural-union-shaped, which
  Rian already rejected.

`Option` pairs with `Result` (ADR-0040): **`Option` for absence, `Result` for failure** — both sealed
sums, both `with`-compatible (ADR-0040).

### 4. Small prelude; stdlib is qualified

The prelude is **small** (explicit-over-implicit; Go-V minimalism). It auto-imports only:

- **Core types:** `Int*`, `Float*`, `String`, `Bool`, `Symbol`, `Char`, `Bytes`, `Result`, `Option`,
  `Vec`/`Map`.
- **Operators** (the precedence table).
- **Core protocols:** `Comparable`, `Hashable`, `Iterable` (ADR-0042).

Everything else is **qualified** stdlib calls — `List.map`, `String.length`, `Map.get` — family-idiomatic
(ADR-0029). Python-style everything-in-scope is **rejected**.

### 5. Observable semantics — identical where feasible, native where not

Same policy as integers (ADR-0034/0035) and symbols (ADR-0041): the portable stdlib has a **documented
observable contract**, with the genuinely-divergent points marked, not silently relied on.

- **`Map` iteration order is *unspecified*** by default (BEAM maps vs Rust `HashMap` vs JS insertion
  order) — don't depend on it; **explicit ordered variants** are provided (a sorted iterator /
  insertion-ordered map) for when order matters.
- Float formatting, hashing, and similar are **documented-identical where guaranteed, explicitly
  unspecified (with an explicit alternative) where the targets differ.**
- A **conformance matrix** (à la ADR-0041) asserts the guaranteed semantics and asserts the unspecified
  ones are marked (Samir).

### 6. Pure prelude, effectful stdlib — IO is outside the pure core

The **pure prelude has no effects.** IO — even `print` — is **effectful** and lives in an **effectful
stdlib layer**, not the pure core. This ADR fixes the *boundary* (pure core vs effectful stdlib); it
does **not** resolve the full **effects/IO model**, which is a separate, still-open ADR (and the natural
next design thread).

## Ratings

| Decision | Rating |
|---|---|
| Three tiers (prelude / stdlib / BEAM-FFI), portable tiers BEAM-independent | 5/5 |
| Hybrid: per-target primitive layer + stdlib in Rian; native delegation where hot | 5/5 |
| **No `nil`; `Option(T) = Some(T) \| None`** (principled family divergence) | 5/5 |
| Small prelude (types + operators + core protocols); stdlib qualified | 4/5 |
| `Map` order unspecified by default + explicit ordered variants; conformance matrix | 4/5 |
| Pure prelude, effectful stdlib; full effects model deferred | 4/5 |
| Per-target-native stdlib (N hand-written copies) | 2/5 (rejected — semantic-drift) |
| Python-size always-in-scope prelude | 2/5 (rejected — explicit-over-implicit) |

## Consequences

- **Defines the "Rian prelude" ADR-0041 forward-referenced** — module resolution kind 3 now has a
  concrete target.
- **`Option` joins the prelude** as a core nominal sum; `nil` does not exist in Rian.
- **Self-hosting (ADR-0027)** gains its real first client: the stdlib-in-Rian is the first large body of
  Rian code compiled to every target.
- **Surfaces effects/IO** as the clear next design thread (the pure/effectful boundary is set; the
  effect system is not).
- Implementation sequences after the declaration parser + the primitive layer; the conformance matrix
  rides the per-target emitters.

## Open items

- **Prelude/stdlib contents** — the actual module/function catalogue (`List`, `Map`, `Set`, `String`,
  `Iter`, `Result`, `Option`, …), filled incrementally; unimplemented = not-yet-available, never a
  silent stub.
- ~~**Effects/IO model**~~ — **Resolved by [ADR-0048](0048-effect-tracking.md):** effects are *tracked*
  (fine-grained, inferred, `pub`-declared) but performed *ambiently* — no object-capability threading;
  `pure = empty effect set`; uniform compile-time discipline, runtime-erased, native-per-target IO.
- **Collection representation per target** (ADR-0041) — `Vec`/`Map`/`Set` to BEAM lists/maps vs Rust
  `Vec`/`HashMap` vs JS arrays/Maps; capability interaction (`iso`/`ref`).
- **`Iterable` protocol surface** — the iteration protocol the stdlib is written against (lazy vs eager;
  ties to comprehensions, ADR-0039/0040 deferral).
- **Ordered-map variant** — `OrderedMap` (insertion) vs a `SortedMap` (by `Comparable`), or both.
