# ADR-0074 — Associated types for protocols (element-generic bounds)

**Status:** Accepted (direction) · **Stage 1 (parse + IR) implemented; Check resolution + lowering staged.** Debated 2026-06-15 as the unblocker named in ADR-0073. A type-system feature that touches the (deliberately conservative) checker, so it is sequenced as the staged plan below, not landed in one drop.
**Implemented:** partial — **Stage 1 (parse + IR) shipped**: `Rian.Decl` parses a bodiless `type Elem` in a `protocol` (→ `protocol.assoc = ["Elem"]`) and `type Elem := Concrete` in an `impl` (→ `impl.assoc = %{"Elem" => "Int53"}`), the associated type is erased on the BEAM desugar (the program still compiles + runs), and a protocol without associated types is unchanged (`assoc: []`) — `test/rian/protocol_test.exs`. **Not yet:** Stage 2 `Check` resolution (binding the `Self.Elem` projection from the impl), Stage 3 Rust `trait { type Elem; }` lowering, Stage 4 the element-generic `Foldable` rewrite. So ADR-0073's consumer is still pinned to a concrete `Int53` element until Stage 2.
**Refines:** ADR-0042 (protocols/impls/bounded generics — adds an associated-type member to the protocol surface + impl), ADR-0061 (multi-target protocol lowering — adds the Rust `type Elem` projection and the BEAM/JS erasure).
**Refs:** ADR-0073 (`Foldable` — the motivating consumer this unblocks), ADR-0050 (one typed Core IR — the projection is a Core type node), ADR-0055 (capability on the receiver — survives projection), ADR-0057 (laziness/concurrency native-per-target — bounds the scope: associated types are *typing*, not a runtime iterator), ADR-0034 (totality), ADR-0000 (honesty: the matrix matches the emitters).
**Owners:** Arthur Pendelton (bounds / type-directed resolution) · Elena Rostova (Rust traits / coherence) · Maya Lin (emitters) · Kira Neri (Reach honesty) · Mira (totality / conservative checker) · Samir Patel (coherence rigor) · Rachel Okafor (PM)

## Context

ADR-0073 shipped `Foldable` but pinned its element to a concrete `Int53`, because the
ADR-0042/0061 protocol mechanism is **single-`Self`** — a protocol method can mention only
`Self` and concrete types, never "the element type of `Self`". So `to_list(self Self)
Vec(Int53)` is expressible; the wanted `to_list(self Self) Vec(Elem)` — with `Elem` a
function of the implementing type (`Bag`→`Int53`, `Tree(String)`→`String`) — is not.

The element is **determined by the container type**, not a free choice of the caller. That
is exactly what an *associated type* models (Rust `Iterator::Item`); it is NOT what a free
method-level `forall T` models (that would let any caller pick the element, which is
unsound — a `Bag` of `Int53` cannot yield `String`).

## Decision

**Add a single associated type per protocol — a `type` member resolved by each impl.**

Surface syntax (minimal, mirrors the existing `type`/`def` vocabulary):

```
protocol Foldable do
  type Elem                        # the associated type — named, no body
  def to_list(self Self) Vec(Elem) # methods may project `Elem`
end

impl Foldable for Bag do
  type Elem := Int53               # each impl fixes it
  def to_list(b) := case b do Bag(xs) -> xs end
end
```

A bound then carries the projection at the use site:

```
def fsum(x C) C.Elem forall C: Foldable, C.Elem: Num := …   # C.Elem is the element
```

**One associated type, not many, for v1** — it covers `Foldable`/`Iterator`-shaped
protocols (the demand) without opening the full associated-item design. Multiple/where-
clause-bounded associated types are a later ADR if a real consumer needs them.

### Per-stage specification

1. **Parse + IR (`Rian.Decl`).** `protocol_struct` gains `assoc: [name]` (the `type Elem`
   line); each impl gains `assoc: %{name => concrete_type}` (the `type Elem := T` line).
   `Self.Elem` parses as a Core projection type node (`{:proj, "Self", "Elem"}`). The BEAM
   desugar still discards the structured IR; the projection is erased (runtime dispatch is
   unchanged — types don't exist at BEAM runtime).
2. **Check (`Rian.Check`) — the real work.** Today bounds "contribute no bindings (a later
   pass)". This is that pass for the associated type: at a call `fsum(b)` where `b: Bag`,
   resolve `C = Bag`, look up `impl Foldable for Bag`'s `Elem := Int53`, and **bind
   `C.Elem = Int53`** so the return type and the `C.Elem: Num` sub-bound check concretely.
   Coherence (ADR-0061 §5 — exactly one impl per `(protocol, type)`) guarantees the
   projection is **unambiguous**, so no functional-dependency machinery is needed.
   **Constraint:** keep the checker conservative — infer `:unknown` when the impl/projection
   isn't resolvable, never reject valid concrete code (CLAUDE.md).
3. **Lowering.**
   - **BEAM / JS** — erase. Associated types are typing only; the runtime dispatcher
     (guarded `def` / `typeof`) is unchanged.
   - **Rust (`Rian.Lower.rust_protocols`)** — emit `trait Rian<P> { type Elem; … }` and
     `impl … { type Elem = <rust(T)>; … }`; a `Self.Elem` projection renders `<Self as
     RianP>::Elem` (or the concrete type where monomorphised). This is the only target that
     materialises the associated type.
   - **JVM** — defer (Tier-2 protocol dispatch is itself not yet lowered).
4. **Element-generic `Foldable`** — replace ADR-0073's concrete `to_list(self) Vec(Int53)`
   with `Vec(Elem)`, and generalise `fsum`/`fall`/… to `forall C: Foldable, C.Elem: Num/…`.
   The concrete example becomes the generic one; the ADR-0073 "concrete element" caveat is
   retired.

### Reach interaction (no false promise)

Associated types are **erased** on runtime targets, so they do **not** change the
sum-dispatch reach story: a `Foldable` impl'd over a sum type still reaches `[:ex, :js]`
(the constructor-tag atom, ADR-0061), element-generic or not. This ADR does **not** claim
to widen reach — closing the sum-dispatcher's `:rs`/`:jvm` gap is the separate ADR-0061
dispatcher item. The win here is *expressiveness* (one generic reducer over many element
types), not portability.

## Alternatives considered

- **Multi-parameter type classes** — `protocol Foldable(E) do … end` + `impl Foldable(Int53)
  for Bag`. Rejected: the element is *determined* by the container, so making it an
  independent class parameter invites incoherent pairs (`impl Foldable(String) for Bag`
  alongside the `Int53` one) and needs functional dependencies to recover uniqueness —
  strictly more machinery than an associated type, which gets uniqueness free from the
  existing one-impl-per-type coherence rule.
- **Higher-kinded `Self`** (`Foldable f` over a type constructor) — far heavier (kind
  system); unjustified by current demand.
- **A free method-level `forall T`** on `to_list` — unsound (lets the caller pick an element
  the container can't produce). Rejected outright.

## Consequences

- Unblocks element-generic `Foldable(T)` and, with it, a generic eager stdlib over
  arbitrary containers (`Dict` values, user trees) — the Tier-2 goal of ADR-0073 without
  the `Int53` pin.
- The cost is concentrated in **Check** (associated-type *resolution*), the most delicate
  pass — it must bind the projection from the impl while staying conservative. That, not
  the surface or the emitters, is the gating work, which is why this lands staged (1→4)
  with a typing/equivalence test at each stage, not in one commit.
- Coherence already does the hard part: one impl per `(protocol, type)` ⇒ a single,
  unambiguous `Elem` per container, so no functional-dependency or overlap resolution.
