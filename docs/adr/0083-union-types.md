# ADR-0083 — Union types: anonymous structural unions `A | B`, narrowed by type

**Status:** Proposed (direction)
**Implemented:** none yet — this ADR decides the design; implementation is staged (see "Plan")
**Depends on:** ADR-0034 (type-system foundations — *defers* union types), ADR-0042 (protocol dispatch / `when is` machinery this reuses), ADR-0040 (`T | E` return sugar — the `|` this must reconcile with)
**Refs:** ADR-0035 (errors are values; no hidden control flow), ADR-0049/0050 (per-target emitters + typed Core IR), ADR-0041 (idiomatic-per-target lowering), ADR-0057/0058 (reach is inferred over a target set), ADR-0000 (the honesty bar — the matrix matches the emitters)
**Owners:** Arthur Pendelton (inference / narrowing) · Elena Rostova (Rust enum synthesis / coherence) · Maya Lin (emitters) · Mira (totality / conservative checker) · Kira Neri (Reach honesty) · Samir Patel (exhaustiveness) · Chloe Bennett (parser) · Rachel Okafor (PM)

## Context

Today, to accept "one of several types" at a parameter, field, or binding, a Rian author must **declare a named sum type for the occasion**:

```rian
type Node := BlockE(Vec(Stmt)) | Expr(Surface)   # a name invented just to union two shapes
def lower_body(body Node) Block := …
```

That is the **nominal-sums-canonical** decision of ADR-0034 (a value's type is a *named* `type`, never an anonymous shape), and it is load-bearing for portability: a named sum maps 1:1 to a Rust `enum` and a JVM `sealed interface`. But it is verbose at the use site, and the self-host corpus shows the pain directly — `compose_real_sum.rian`'s `def lower_body(body)` legitimately matches **one untyped param at several shapes** (`{:block_e, stmts}` and a fallthrough `e`), and ADR-0034 had to *revert* an attempt to constrain such a param because there was no way to spell "this is a union" (so the param stays untyped, `:unknown`, BEAM-only).

ADR-0034 named the fix and **deferred it**: *"introduce union types — … a larger design step, deferred."* This ADR is that step. The ask (verbatim user request): a Crystal-style union usable directly in a signature, so `def f(x Int32 | String)` needs no throwaway `type`.

Two tensions make this non-trivial, and both must be decided here:

1. **The `|` is already taken (ADR-0040).** `T | E` in **return position** is sugar for `Result(T, E)` (tagged `{:ok, v}`/`{:error, e}`), and ADR-0040 explicitly says `|` is **not** general union syntax elsewhere. A value union `Int32 | String` reuses that glyph with a *different* meaning (an untagged value that is one of the members).
2. **Structural vs nominal targets.** On the **dynamic** targets (BEAM, JS) a union is free — the value carries its own tag, and a `case` narrows by runtime type (`is_integer`/`typeof`). On the **nominal** targets (Rust, JVM) there is *no* structural union: each distinct `A | B` must be lowered to a **synthesized** nominal type (a Rust `enum`, a JVM `Any`/sealed shape), with name-mangling and member-wrapping. This is exactly why ADR-0034 chose named sums — they skip the synthesis. A union feature must pay that cost honestly or pin off the nominal targets (ADR-0000).

## Decision

### 1. Anonymous structural union types — `A | B | C`

A **union type** is the set of its member types; a value of `A | B` is a value of `A` *or* a value of `B`, carrying its own runtime identity. Members are any types (primitives, named sums/structs, parametric types, other unions — flattened and de-duplicated: `(A | B) | A` = `A | B`). A union is **anonymous and structural** — two `A | B` written in different files are the *same* type (unlike a named sum, which is nominal).

It is a **first-class type**, valid wherever a type is: parameters, fields, bindings, and (subject to §3) returns.

```rian
def lower_body(body BlockE | Expr) Block := case body do
  b BlockE -> Block(lower_stmts(b.stmts))
  e Expr   -> Block([SExpr(lower_surface(e))])
end
```

### 2. Narrowing is by **type-pattern** (new), reusing the protocol-dispatch machinery

A union is consumed by `case` (or a clause head) whose arms carry a **type-pattern** `name Type` — bind `name`, matching only when the scrutinee's runtime type is `Type`:

```rian
case x do
  n Int53  -> n + 1
  s String -> Str.length(s)
end
```

This is a **new pattern form** (`{:typed, name, Type}` in `Rian.Pratt.parse_pat`). It lowers to exactly the runtime discriminator the protocol dispatcher already emits (ADR-0042): a `when is_integer(_)`/`is_binary(_)` guard on the BEAM, a `typeof`/tag test on JS, an `if let`/`match` on the Rust enum, an `is T` smart-cast on the JVM. Inside an arm, the binding is **narrowed** to the arm's type (ADR-0034 §"refined after a `case` arm"), so member operations type-check. The checker reuses the discriminator-coherence rule from ADR-0042 §5 — two members that share a runtime discriminator (`Int32 | Char`, both `is_integer`) are rejected in a union *that must reach a runtime-dispatch target*, same as overlapping impls.

### 3. The `|` overload — resolved by **position**, staged

To avoid a breaking change to error handling, `|` keeps two readings, disambiguated by position (this is the cheap, non-breaking resolution; §"Alternatives" records the unifying one):

| Position | `A | B` means | Why |
|---|---|---|
| **parameter / field / binding / type-arg** | a **value union** (this ADR) | the `|`-as-union conflict does not exist here — ADR-0040's sugar was return-position only |
| **return** | **unchanged** — `Result(ok, error)` sugar (ADR-0040) when the tail is an error set | preserves `with`/`<-` propagation (ADR-0039), which relies on the `{:ok}/{:error}` tagging; no break |

So **the user's stated pain (multi-type *parameters*) is solved immediately and with zero conflict.** A value union in *return* position is intentionally **not** introduced in the first increments — it would force a decision between the tagged `Result` and an untagged union, which ripples into ADR-0039/0040. That decision is split out (see Alternatives → "Unify errors and unions") and is **not** a prerequisite for the parameter/field win.

### 4. Per-target lowering (the honest cost)

| Target | Representation | Narrowing |
|---|---|---|
| **BEAM** (`Rian.Beam`) | the bare value (untyped) | a `case`/clause guard — `is_integer`/`is_binary`/tag tests (the dispatcher's `guard_for!`) |
| **JS** (`Rian.JS`) | the bare value | `typeof` / array-tag test (the JS dispatcher) |
| **Rust** (`Rian.Lower`) | a **synthesized `enum`** per distinct union, name-mangled & order-canonical (`enum U_I64_String { I64(i64), String(String) }`); construction wraps at the boundary, an arm `match`es | the synthesized `match` |
| **JVM** (`Rian.JVM`) | `Any` + `when (x) { is Long … is String … }` — **not** a synthesized sealed interface, because a primitive member (`Long`/`String`) cannot be made to implement one (the exact constraint that put protocol dispatch on `when is`, ADR-0042) | the `when is` |

The Rust **enum synthesis** is the load-bearing new machinery (mangling, the wrap-at-boundary coercion, exhaustiveness over the synthesized variants — a coercion pass like the associated-type `List<Any>` cast). Until it lands, a union-typed function **pins off `:rs`** in `Rian.Reach` (a `:union` blocker), honestly — the matrix never green-lights a union the emitter can't synthesize. JVM's `Any`-erasure is cheaper but loses static typing inside the union (acceptable — narrowing recovers it per arm).

### 5. Exhaustiveness & Reach

- **Exhaustiveness** (`Rian.Exhaustiveness`): a `case` over `A | B` must cover every member (a missing arm is the same uncovered-witness the gate already reports for a sum). A catch-all `_` closes it; a non-exhaustive union `case` follows ADR-0036 (BEAM/JS/JVM throw at runtime; Rust gets a `_ => panic!()` fallthrough, per 2026-06-19).
- **Reach** (`Rian.Reach`): a union reaches a target iff **every member** reaches it *and* the union representation lowers there — `:ex`/`:js` always (dynamic), `:rs` once enum synthesis lands, `:jvm` via `Any` once it lands. A discriminator clash (two members sharing a runtime tag) pins off the runtime-dispatch targets, exactly as overlapping impls do.

## Plan (staged, each a verifiable increment)

1. **Parse + represent** — `Rian.Pratt`/`Rian.TypeStr` parse `A | B | C` (flatten/dedup/canonical-order) into a `Union([...])` type; `Rian.Check` carries it as a first-class type string. The **type-pattern** `name Type` parses (`parse_pat`). *No emit yet* — Reach pins a union off every nominal target until its emitter lands, so the matrix stays honest.
2. **BEAM + JS** — lower the type-pattern `case` to the existing runtime-discriminator guards (`Rian.Beam`, `Rian.JS`); narrow the binding per arm; exhaustiveness over members. Value unions reach `[:ex, :js]`. This alone delivers the self-host ergonomics (`lower_body`).
3. **Checker narrowing + coherence** — refine the arm binding to the member type; reject discriminator clashes for unions required to reach a runtime-dispatch target (reuse ADR-0042 §5); assignability `A ⊑ A | B` (a member is assignable into the union).
4. **Rust** — synthesize the name-mangled `enum`, the wrap-at-boundary coercion, and the `match` narrowing (a coercion pass sibling to the associated-type cast). Unions reach `:rs`.
5. **JVM** — `Any` parameter + `when is` narrowing. Unions reach `:jvm`. Update the reach matrix, ADR-0034 (retire the "deferred" note), and SELFHOST.md.

## Alternatives considered

- **Inline *named* sum sugar** (`def f(x (A | B))` desugars to a fresh hidden `type`) — keeps everything nominal (free Rust/JVM lowering, no synthesis), but anonymous-yet-nominal types are surprising (two identical `A | B` are *different* types → no structural equality, the thing the user wants). Rejected as a half-measure.
- **`Union(A, B)` as a parametric type** — sidesteps the `|` overload entirely and reads like the existing `Result(T, E)`/`Vec(T)`. Viable and *non-controversial*; the only loss is the Crystal-familiar `|` spelling the user asked for. **Kept as the fallback** if the `|` overload proves too subtle in review.
- **Unify errors and unions** (make `T | E` a value union *everywhere*, drop `{:ok}/{:error}` tagging, narrow errors by type) — the cleanest Crystal-faithful end-state and arguably better than `Result`, but it **breaks** ADR-0039/0040 `with`/`<-` propagation and every `{:ok, _}`-matching site. Deferred to its own ADR; explicitly **not** required for the parameter/field win.
- **Status quo (named sums only)** — the portability-cleanest, but it is the verbosity the user (and the self-host corpus) is pushing back on; ADR-0034 already flagged it as a gap.

## Honest assessment (the principal-engineer view, not a rubber stamp)

Value unions are a **real ergonomic win on the dynamic targets and in the self-host corpus**, and Phases 1–3 are cheap and non-breaking (they reuse the dispatcher's discriminator machinery and touch nothing in error handling). The **cost is concentrated in Phase 4 (Rust enum synthesis)** — name-mangling, boundary coercion, and exhaustiveness over synthesized variants are genuinely new emitter machinery, and a structural union is a worse fit for a nominal target than a named sum is (that trade is *why* ADR-0034 chose named sums). The recommendation: **adopt the `|` value-union in non-return positions (Phases 1–3) now** — it solves the stated pain with no risk — and treat the **Rust/JVM lowering (Phases 4–5) and the error-handling unification as separately-gated decisions**, each landing only when its emitter is proven (ADR-0000). If the `|` overload is judged too subtle in review, fall back to `Union(A, B)`; the semantics are identical.
