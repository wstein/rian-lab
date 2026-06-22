# ADR-0034 — Type-System Foundations: unification, error sets, protocol bounds, flow narrowing

**Status:** Accepted (direction) · implementation gated on the declaration parser (ADR-0031 Stage 0.1)
**Implemented:** partial — unification-based bidirectional inference + error sets + flow narrowing shipped (`Rian.Check`, `test/rian/check_test.exs`); protocol-bounded generics (§3) deferred to its own ADR
**Refs:** ADR-0030 (comptime), ADR-0032 (family / concept-borrowing), ADR-0033 (vocabulary), ADR-0035 (no hidden control flow)
**Owners:** Arthur Pendelton (inference) · Elena Rostova (polymorphism) · Maya Lin (multi-target) · Samir Patel (rigor) · Rachel Okafor (PM)
**Amended 2026-06-12 (decision-lock review):** structural-unions, inference-algorithm, error-set-composition, and integer-overflow open items are **resolved** (see §1, §4, and Open items). The §2 propagation form is decided (`with`) and split into **ADR-0039** (`<-` reassignment) + **ADR-0040** (error handling). §3 (protocol-bounded generics) remains open and gets its own ADR.

## Context

Rian has no type checker yet — it is the single artifact that **four** recent design debates all
dead-end into:

- **default parameter values** need a type to attach to and an integer-literal width;
- **`?` propagation** was removed because, untyped, it has no `Result`/`Option` to propagate;
- **return-type inference** needs an inference engine and an infer-local/declare-public boundary;
- **polymorphism / bounded generics** (`T: Ord`, deferred in types-match §7) need a constraint model.

The concept review (Rust/Go/Julia/Kotlin/Crystal/Ruby/Zig/V/Oz/Prolog) concluded that three of the
most valuable concept-borrows are not features to bolt on — they *are* the type system. This ADR
fixes its **foundations** (direction and shape), so those debates stop being re-litigated. It does
**not** specify the full type theory; that lands incrementally once the declaration parser exists.

ADR-0032 licenses these borrows: they are **concepts**, drawn from wherever they are strongest, and
do not touch the Elixir/Ruby/Crystal surface.

## Decision

Four pillars.

### 1. Inference is unification-based (Prolog), local-by-default

Type inference is built on **unification** (Hindley-Milner / Algorithm W — unification of type
terms is the algorithmic heart, and Prolog is its home). This also unifies two things Rian already
does: **pattern matching is one-way unification at runtime; inference is unification at compile
time** — one idea, two phases.

**Checking strategy: bidirectional** (decision-lock 2026-06-12, resolving the inference-algorithm
open item). Mandatory public signatures (below) are *checked against*; private / `:=` / lambda
holes are *inferred*. Unification stays the solver; bidirectional is the strategy over it — chosen
for better error localization (blame at the checking site, not at a downstream unification failure)
and clean interaction with protocol bounds (§3).

Inference is **local, with the signature boundary explicit** (the infer-local / declare-public line
from the defaults and return-inference debates):

- **`pub` functions and multi-clause signature lines: types are mandatory and explicit** — the
  contract is the explicit surface (precise `-spec` per ADR-0026; correct Rust signatures).
- **Private functions, `:=` bindings, and lambda bodies: inferred.** A body edit can't change a
  caller because there is no exported inferred type.

**Implementation status (infer-local).** A private function's **return type AND parameter types** are
now inferred and need not be declared (`Rian.InferLocal` + `Rian.Check.infer_return_type/2` +
`infer_param_type/3`). `def f(x) := x + 1` type-checks, lowers, and runs, with `x : Int53` and the
return `Int53` both recovered. `Rian.Decl.parse` runs the pass after assembly; a fixpoint fills
**params first, then returns** (a return needs its param types) and resolves private→private chains;
`pub` still must declare its boundary; and a type that cannot be recovered (self-recursion, an
`@external` with no body, an unmodelled body, or a param used at *conflicting* types) raises a clear
*"annotate it"* error rather than guessing.

- **Parameter inference is bidirectional** (Dunfield–Krishnaswami "checking", realized locally): an
  arithmetic/compare operator, a string concat, a typed callee parameter, or a clause-head/`case`
  pattern pushes its *expected* type onto the variable flowing into it. A parameter the body leaves
  *unconstrained* (a pass-through, `def id(x) := x`) is **generalized to a fresh `forall T`**, so generic
  helpers work without annotation.
- **The grammar conflict is resolved by a casing rule, not new syntax.** A lone **lowercase** parameter
  token (`def f(x)`) is a NAME whose type is inferred (`:infer`); a **PascalCase** token (`def flip(Bit)`)
  stays an anonymous-typed param (a TYPE) — Rian's existing PascalCase-type / lowercase-value convention.
  `pub`/`@external` boundaries keep the legacy permissive reading, so the self-hosted dispatchers
  (`pub def lower_pat(p) Pat`, raw-AST params with no nominal type) are untouched; the prior "deferred,
  needs dedicated syntax" blocker is closed. (The token-based `parse_program` is a separate parser.)
- **Inference widens portability**: a recovered concrete param type lets a private helper reach
  `:rs`/`:jvm` (`Rian.Reach` reads the now-concrete signature) instead of forcing an annotation.

**Deliberate conservative limitations (decision-lock 2026-06-17).** Two gaps in parameter inference
are intentionally left conservative rather than "fixed", because the sound fix needs machinery this
ADR does not yet have (target-aware enforcement or union types):

- **A structural clause-head pattern (`[h|t]`, `{a, b}`, `%{…}`) contributes no param-type
  constraint** (`Rian.Check.pattern_type` returns `:unknown` for it). Making it contribute a
  constraint — so a scalar-vs-list clause clash is a conflict — was implemented and **reverted**: it
  rejected valid **dynamically-typed, BEAM-only code** that legitimately matches one untyped
  param at several shapes (a union), e.g. a `lower_body(body)` that dispatches on the body's shape. The
  inference is conservative by design (it infers `:unknown` rather than guess), so it generalizes such
  a param rather than inventing a false conflict. A sound version would enforce the conflict **only for
  functions required to reach a statically-typed target** (`:rs`/`:js`/`:jvm` via an `@targets`
  contract / `Rian.Reach`) and leave BEAM-only code alone, or introduce union types — either is a
  larger design step, deferred. **The union-type path is taken up by ADR-0083** (anonymous
  structural `A | B`, narrowed by a type-pattern), which makes exactly this `lower_body`-shaped
  multi-shape param spellable.
- **A generic param introduced via a *destructuring* clause head is not surfaced to return inference**
  (`bind_tvar_params` re-binds only bare-variable params to their tvar). This is the same
  incomplete-coverage family — its principled resolution depends on the structural-pattern typing
  above — and is low-reachability (a destructured `forall T` param is itself near-incoherent).

The Elixir→Rian transpiler emits private `defp`s without a return hole (one fewer `_Unk` per private
function).

**`Any` (the top type) vs `_Unk` (a placeholder) — never conflated.** Since the same source lowers to
Rust, which has no untyped values, an *unknown* type and a *deliberately-dynamic* type must be distinct:

- **`_Unk`** is a **fill-me marker**, not a type — "this still needs to be defined" (an inference hole
  the transpiler leaves). It is a TODO to be driven to zero, **not** a synonym for `any`. Internally the
  checker carries un-inferable *expression* results as `:unknown` (unifies with anything, errors only on
  a *provable* clash), but a **declared `_Unk` in a signature is REJECTED by the gate** (`Rian.Check`
  `check_unk`) with a clear fix — you must give it a concrete type or `Any`. (This reverses the earlier
  ADR-0069 "a `_Unk` draft defers" leniency: a draft no longer *compiles*; it must be filled first. The
  raw `Beam.load` bootstrap path skips the gate, so BEAM-only draft loading is unaffected.)
- **`Any`** is the **deliberate top type** — "this legitimately accepts any value," for genuinely
  dynamic host artifacts (Elixir quoted AST, Erlang abstract forms, a `.beam` binary). It is a real,
  named type: `Rian.Check.unify` makes it the top (`unify(Any, t) = t`), and `Rian.Reach` reports its
  reach honestly — it **reaches every target but `:rs`**: BEAM erases it (`term()`), JS is dynamic (an
  untyped value), JVM maps it to Kotlin `Any`; only Rust has no ergonomic top value, so `Any` pins off
  `:rs` alone (node/kotlinc-verified). Capabilities don't gate it — they're a Rust-ownership mechanism,
  and `Any` is exactly the Rust-excluded type, so a capability on an `Any` param is a no-op on its
  reachable targets. **If you want `any`, write `Any`** — overloading `_Unk` as `any` hides a real type
  behind a placeholder and is rejected.

**Integer-literal width:** a bare integer literal defaults to **`Int64`** (ADR-0033 vocabulary);
other widths require an annotation (`n Int32`). **Overflow/precision is native-per-target**
(decision-lock 2026-06-12): `Int*` types declare representation *intent* / minimum precision, **not
a portable overflow contract**; each target uses its native integer semantics (BEAM bignum promotion;
Rust panic-debug/wrap-release; JVM/Go wrap; JS `BigInt`); Rian does not simulate one runtime on
another. Subrange types (ADR-0036) are the promoted in-domain safety idiom; bit-identical
cross-target arithmetic is an opt-in library. See the ADR-0035 scope clarification.

> **⚠ Superseded by [ADR-0064](0064-portable-numeric-contract.md) (P2, 2026-06-14).** The design
> review judged "width is intent, not a portable contract" to contradict the portability thesis.
> Integers now have **portable contracts**: `Int` (arbitrary precision — the new default literal
> type, identical everywhere) and fixed-width `Int8…64`/`UInt*` (defined two's-complement wrap,
> identical everywhere). The per-target difference is *representation cost*, not behaviour — and the
> BEAM masking cost (~15×, measured) is why `Int` is the default and fixed-width is opt-in.

**Typed bindings — implemented.** A block binding may carry the annotation between the name and
`:=` (`x Int32 := 66`). Per the bidirectional strategy above, the declared type is the expected
type *pushed down* into the value:

- a **numeric literal adopts** the annotation — `x Int32 := 66` gives `x : Int32` (this is the
  "other widths require an annotation" mechanism; a literal takes the declared width). Adoption is
  *same-kind*: an integer literal takes any `Int*`/`UInt*`, a float literal any `Float*`; a
  cross-kind annotation (an integer literal into a `Float`) is **not** adopted — write an explicit
  float literal — and falls through to exact unification;
- an **already-typed RHS may widen losslessly** to the annotation (amended 2026-06-13): the value's
  type must be *assignable* to the declared type, where a numeric type widens **one-directionally**
  to a wider one — `Intₐ ⊑ Int_b` / `UIntₐ ⊑ UInt_b` for `a ≤ b`, `UIntₐ ⊑ Int_b` for `a < b` (the
  unsigned range fits the signed target), `Intₐ ⊑ Float_b` / `UIntₐ ⊑ Float_b` when every value is
  exactly representable (f64 to 2⁵³, f32 to 2²⁴), and `Floatₐ ⊑ Float_b` for `a ≤ b`. So
  `x Int64 := someInt32` and `x Float64 := someInt32` are accepted, while **narrowing or lossy**
  conversions (`x Int32 := someInt64`, `x Float32 := someInt32`, `x Int32 := someUInt32`) stay
  *proven* mismatches, rejected with blame at the binding site. The same one-directional
  `assignable?` rule governs a function body against its declared **return** type. Widening is
  lossless and never silent at runtime (each `Intₙ` is a representation-intent floor, ADR-0035); an
  `:unknown` RHS is left unchecked (the gate reports only provable clashes).
- a **bare constructor head is assignable to the same head parameterized** (added 2026-06-19): a
  variant value whose payload type the inference did not track yields the bare sum head — `Some(x)`
  and `None` both infer `Option`, not `Option(T)` — and that is *under-specified*, not a *provable*
  clash against a declared `Option(Vec(Char))`. So `Option ⊑ Option(Vec(Char))` (the `(` after the
  head pins it exactly — `Option` is **not** the head of `Optional(X)`), while a **different** head
  (`Some(1)` against `Vec(Int64)`) stays a proven mismatch. This keeps the conservative checker from
  rejecting valid `Option`/sum-returning code such as the self-host `strip_prefix` (`Rian.Check`).

The binding then carries its **declared** type downstream (display, `-spec`, later checks), not the
inferred one. Every backend **erases** the annotation when lowering — consistent with native-per-target
representation (the value compiles unchanged). Parsed as `{:typed_bind, name, type, expr}`
(`Rian.Pratt`); enforced by `Rian.Check.check_binds/2`. The annotation may be **parametric** —
`xs Vec(Int64) := […]`, `m Map(String, Int64) := …`, nested — rendered space-free to match the
checker's canonical type strings so it unifies with the inferred parametric type (a `Vec(Bool)`
annotation over a `Vec(Int64)` value is a proven mismatch).

### 2. Errors are values, typed as error sets (Zig)

There are **no exceptions** in the portable core (ADR-0035). A fallible function returns a
`Result(T, E)` whose **`E` is an error set** — a closed sum of error tags, *inferred* from the
body or *declared*. This makes:

- `case` over a result **exhaustively checkable** (`{:ok, v} -> … | {:error, NotFound} -> … |
  {:error, Timeout} -> …` with the gate proving totality over the error set), and
- a **future propagation form sound** — the reason `?` was removed (ADR-0032) was that, untyped, it
  had nothing to propagate. A typed error set is that missing foundation. Whether propagation
  returns as `?` (no — family uses `?` for predicates) or a `with`-style form is a later, *now
  answerable*, question.

Error sets are a sum type, so they lower to every target (no exception machinery required).

### 3. Bounded polymorphism via protocols (Rust traits, Elixir-protocol surface)

Parametric generics gain **bounds through protocols** — the family-idiomatic spelling of a
typeclass/trait (Elixir protocols *are* typeclasses). `T` bounded by a protocol (`Comparable`,
`Hashable`) may use that protocol's operations. Protocols are **opted into per type**, so — unlike
Julia's open multiple dispatch — they **do not break exhaustiveness/totality** (the reason multiple
dispatch was rejected). This fills the `T: Ord` gap deferred in types-match §7.

### 4. Flow narrowing (Kotlin smart-casts)

After a `case` arm or a guard narrows a union/`Option`/result, the binding's type is **refined for
that branch** — no re-annotation, no re-match. This is a property of the checker, not a separate
feature; it rides along with pillars 1–2.

Narrowing is **robust under Rian's single-assignment `:=`**: a `:=` binding cannot be reassigned, so
a narrowing established in a branch cannot be silently invalidated by later mutation — the Kotlin
smart-cast failure mode does not occur. A `<~`-mutable binding (ADR-0039) *does* invalidate
narrowing, exactly as Kotlin invalidates a smart-cast on `var` reassignment.

### Folded-in rules

- **Open-type exhaustiveness (from ADR-0033):** `case` on an open type (`Symbol`, `Int64`,
  `String`) cannot be proven total; a `_ ->` catch-all is conventional but no longer required —
  a non-total `case` lowers with an explicit panic/throw fallthrough like a non-total function
  (ADR-0035 §4, 2026-06-20). Sealed `type` sums still reach totality by coverage.

## Ratings

| Decision | Rating |
|---|---|
| Unification-based inference | 5/5 |
| Local inference, explicit `pub`/signature boundary | 5/5 |
| Typed error sets; errors-as-values; no exceptions | 5/5 |
| Protocol-bounded generics (opted-in, totality-safe) | 4/5 |
| Flow narrowing | 3/5 (rides with the checker) |
| Default integer literal = `Int64` | 4/5 (overflow semantics deferred) |
| Open multiple dispatch (rejected — breaks totality) | 1/5 |

## Consequences

- **`?`/propagation becomes answerable** once error sets exist — revisit with a family-correct
  spelling (not `?`).
- **Return-type inference** is admitted *for private functions only*; `pub` stays explicit.
- **Constant default parameter values** become typeable (their type is read off the constant).
- **Precise `-spec` emission** (ADR-0026) is preserved because public signatures stay explicit.
- The checker's **implementation is sequenced after the declaration parser** (ADR-0031 Stage 0.1);
  this ADR is the design it implements.

## Open items

**Resolved in the 2026-06-12 decision-lock review:**

- **Structural unions vs. nominal sums → nominal is canonical.** Untagged structural unions are
  *not* a general user-facing type former. `T | E` in **return position** is sugar for the tagged
  `Result(T, E)` / error-set union (§2, ADR-0040); `|` is **not** general union syntax. Flow
  narrowing (§4) narrows the *nominal* variants. (Closes Chloe's dissent.)
- **Inference algorithm → bidirectional** over a unification solver (§1).
- **Error-set composition → infer-local / declare-public union** (full surface in ADR-0040):
  private functions infer `E = ⋃ propagated callees' sets − handled`; `pub` functions declare `E`
  explicitly and the body's inferred set must be ⊆ the declared set.
- **Integer overflow → native-per-target** (no cross-target simulation): `Int*` declares
  representation intent / minimum precision, not a portable overflow contract; subrange types
  (ADR-0036) are the in-domain safety idiom; deeper compat is an opt-in library. See §1 and ADR-0035.

**Still open:**

- ~~**Protocol/generics surface** (§3) — type-variable introduction site, `protocol` declaration form,
  and the bound spelling (which collides with the `when` *guard* keyword).~~ **Resolved by
  [ADR-0042](0042-protocol-bounded-generics.md):** `forall T: Bound` binder (Crystal), `protocol`/`impl`
  declarations, Rust orphan rule, static-by-default dispatch; the `when` collision dissolves. **All four
  §-pillars are now design-complete.**
- ~~**Capabilities × types:** how `val`/`iso`/`ref`/`tag` interact with inference and protocol bounds
  (an `iso` returned from a protocol method, etc.).~~ **Resolved by
  [ADR-0055](0055-capabilities-through-dispatch-and-opaque.md):** the capability rides on the protocol
  *method receiver* (survives `dyn` erasure via coherence); `val` default, `iso`/`ref` opt-in.
- ~~**Target model for `Symbol` / error-tag representation** on non-atom targets (JVM/Go/JS/WASM).~~
  **Resolved by [ADR-0041](0041-target-model.md):** error tags are closed sums → tagged union per
  target; `Symbol` lowers closed→enum / open→`&'static str`, equality-only.
