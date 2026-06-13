# ADR-0055 — Capabilities through dynamic dispatch and opaque types

**Status:** Accepted (direction) — implements with Stage 0.1 (`protocol`/`impl`/`opaque` parsing)
**Resolves:** ADR-0034 "Capabilities × types" open item (an `iso` returned/consumed through a protocol method); ADR-0042 "Protocol-typed values (`dyn`)" capability half; ADR-0043 "Capability inheritance" — opaque-over-`struct` × field capabilities
**Refs:** ADR-0025 (memory capabilities), ADR-0034 (capabilities × types; flow narrowing), ADR-0035 (no hidden control flow — dynamic dispatch only when visible), ADR-0041 (per-target dispatch table), ADR-0042 (protocols; static-by-default dispatch; orphan rule), ADR-0043 (opaque types; default-to-base capability)
**Owners:** Elena Rostova (dispatch/lowering) · Arthur Pendelton (type system) · Samir Patel (linearity/totality) · Maya Lin (multi-target) · Kira Neri (determinism) · Rachel Okafor (PM)

## Context

Two open items have sat unresolved across three ADRs because they only *bind* once dynamic dispatch
and opaque types exist:

1. **Capability through a protocol method / vtable.** ADR-0042 fixed *dispatch* (static by default,
   `dyn`-vtable when a value is protocol-typed) but never said how a memory capability rides on a
   method **receiver** — what an `iso self` consumed through a vtable means, and whether erasing the
   concrete type behind `dyn P` also erases its capability. An `iso self` duplicated by a JS vtable
   call, or dropped twice by a Rust `dyn`, is a **soundness bug** — use-once (ADR-0025) is exactly
   the invariant a careless dispatch lowering breaks.
2. **Opaque over a struct with capability'd fields.** ADR-0043 confirmed an opaque inherits its
   base's capability (`opaque Token := Bytes` is `iso` iff `Bytes` is) but left
   `opaque T := struct{ a iso A, b val B }` open: the opaque hides its representation, so which
   single capability does it present to the outside?

Neither is reachable today — `protocol`/`impl`/`opaque` have no parser or lowering (Stage 0.1). But
the **expensive order** is to ship dynamic dispatch and opaque types first and *then* discover the
hole, having already bolted vtables and field layouts to an unspecified contract. We locked
default-to-base (ADR-0043) before opaque lowering existed for the same reason. Spec now; implement
with the feature.

## Decision

### 1. The capability lives on the protocol *method receiver*, not on the type

A protocol method declares its receiver's capability, exactly like any parameter (ADR-0025 — every
signature position is capability-annotated):

```elixir
protocol Drain do
  def peek(self val) Int64          # reads — shared, the default
  def drain(self iso) Vec(Int64)    # consumes — linear, opt-in and visible
end
```

The receiver capability is **part of the method signature**. It binds **every** `impl Drain for T`
identically and **every** call site, static or dynamic. The capability is therefore a property of
**`Drain.drain`**, not of `T` and not of the concrete representation behind a `dyn` — so **type
erasure does not erase the capability.** This is sound precisely because of ADR-0042's coherence
(orphan) rule: there is exactly one `impl` per `(protocol, type)`, so every vtable entry for
`drain` has the *same* receiver capability. The vtable carries the method; the method carries the
capability.

**Default receiver capability is `val`** (shared, read-only) — least privilege, and the common case
(most protocol methods read). `iso`/`ref` receivers are opt-in and appear in the signature, so a
consuming or mutating dispatch is **never silent** (ADR-0035).

### 2. Dynamic dispatch preserves the linearity contract per target

A protocol-typed binding `d Drain` (dynamic — concrete type erased) honours the receiver capability
of whichever method is called:

| Receiver cap | Rust (`dyn`) | BEAM | JS (tag-keyed vtable) |
|---|---|---|---|
| `val self` | `&dyn Drain` — method takes `&self` (borrow) | linearity: `d` stays usable | vtable call, `d` not consumed |
| `iso self` | `Box<dyn Drain>` — method takes `self: Box<Self>`, the value **moves** | use-once: `d` consumed, reuse is a linearity error | vtable call **moves** `d` — use-once enforced as for any `iso` binding |
| `ref self` | `&mut dyn Drain` — method takes `&mut self` | `ref` is **BEAM-rejected** (ADR-0025) — a `ref self` method is not callable on a BEAM `dyn` value | mutation through the boxed value |

The rule (**"capability erasure through a vtable"**): an `iso self` dynamic call **consumes the
protocol-typed value** — it may be called once, after which the binding is dead, identically to
calling an `iso` free function on the value. Rust expresses this with a by-value boxed receiver
(`self: Box<Self>`), which requires `Box<dyn Drain>` (not `&dyn`) at the call site; the checker
therefore requires an `iso self` method to be called only on an **owned** (`iso`) protocol-typed
binding, never a borrowed (`val`) one. BEAM/JS reuse the existing use-once linearity check (ADR-0025
`lin_check`) on the binding — no new mechanism, the protocol-typed value is just another `iso` value.

`ref self` through `dyn` is **rejected on the BEAM target** at the call site (consistent with
ADR-0025's blanket `ref`-on-BEAM rejection), a compile error, never a silent downgrade (ADR-0041).

### 3. Opaque-over-`struct` presents the *join* of its field capabilities

For `opaque T := struct{ … }`, the opaque's externally-visible capability is the **most-restrictive
join** of its fields' capabilities:

```
join(caps) = iso   if any field is iso or ref   (the struct contains a linear resource)
           = val   otherwise                     (all fields freely shareable)
```

- **Outside** the defining module the field capabilities are **erased** (opaque is
  representation-hidden, ADR-0043) — the type presents exactly *one* capability, the join. Copying
  or sharing the opaque is governed by that single capability.
- **Inside** the defining module, fields keep their own capabilities and are checked normally
  (flow narrowing, ADR-0034).

This is **sound and conservative**: if any field is linear, copying the opaque would copy a linear
resource, so the whole opaque must be linear (`iso`) to the outside — the join is the *weakest*
external capability that cannot violate any internal field's use-once. An all-`val` struct stays
`val` (freely shareable), so the common case keeps zero ceremony. For `opaque T := Base` where
`Base` is a scalar/`Vec`/another opaque (not a struct), §3 degenerates to ADR-0043's existing
"inherit the base's capability" — this ADR only *adds* the struct case.

### 4. Inference and narrowing interaction (ADR-0034 §1, §4)

- A method-call expression's result capability is the method's **return** capability (default `val`),
  independent of the receiver's — calling `peek(self val)` on an `iso` binding returns a `val`
  `Int64` and **does not** consume the receiver; calling `drain(self iso)` consumes it and returns
  whatever `drain` declares.
- Flow narrowing (ADR-0034 §4) is **capability-preserving**: narrowing a `dyn Drain` binding inside
  a guard does not change its capability, only its (still-erased) type knowledge.

## Rationale

- **Capability-on-the-method, not the type**, is the only placement that survives erasure: a `dyn P`
  has no concrete type to read a capability from, but it always has the method being called. Coherence
  (one impl per pair) makes "the method's capability is the same in every vtable slot" a theorem, not
  a hope.
- **`val` default receiver** matches ADR-0043's default-to-base / least-privilege stance and keeps
  the 90% read-only case ceremony-free; the dangerous cases (`iso` consume, `ref` mutate) are the
  ones that must be written down, and they are.
- **The join rule** is the same conservative move as borrow/linearity everywhere else: when in doubt,
  take the most-restrictive that cannot be unsound. It also means an opaque author can *deliberately*
  expose a linear handle (wrap one `iso` field) or a shareable token (all `val`) by choosing fields —
  the capability is a designed property, not an accident.
- **No new runtime mechanism**: dynamic-dispatch linearity reuses `lin_check`; the join is a compile-
  time computation over the struct's already-annotated fields. The cost is in the checker and the
  per-target receiver lowering, both of which Stage 0.1 must write anyway.

## Ratings

| Decision | Rating |
|---|---|
| Capability on the protocol method receiver (survives erasure via coherence) | 5/5 |
| `val` default receiver; `iso`/`ref` opt-in and visible | 5/5 |
| `iso self` dynamic call consumes the protocol-typed value (use-once through `dyn`) | 4/5 |
| `ref self` through `dyn` rejected on BEAM (no silent downgrade) | 4/5 |
| Opaque-over-struct presents the join of field capabilities | 4/5 |
| Capability on the *type-erased value* instead of the method | 1/5 (rejected — nothing to read it from after erasure) |
| Opaque-over-struct = always `val` (ignore fields) | 1/5 (rejected — would let a linear field be silently copied) |

## Consequences

- **ADR-0034 §"Capabilities × types"**, **ADR-0042 §"Protocol-typed values (`dyn`)"** (capability
  half), and **ADR-0043 §"Capability inheritance"** (struct case) are **design-complete**; their open
  items point here.
- **Checker (Stage 0.1):** a receiver-capability column on protocol method signatures; the `iso self`
  call-site owned-binding requirement; the field-capability join for opaque-over-struct; `ref self`
  BEAM rejection.
- **Emitters (Stage 0.1):** per-target receiver lowering (`&dyn` / `Box<dyn>` / `&mut dyn` on Rust;
  use-once linearity on the protocol-typed binding for BEAM/JS), wired into ADR-0041's dispatch table.
- **No effect on totality** (ADR-0042 §6): capabilities are orthogonal to dispatch arms; this ADR adds
  no `case` behaviour and touches no exhaustiveness.

## Open items

- **`iso self` + protocol *default methods*** (ADR-0042 open item): a defaulted method body that
  consumes `self` — interaction with override; deferred with default methods themselves.
- **Capability on associated types** (ADR-0042 v2): when associated types land, whether they carry
  capabilities; out of scope for v1 (methods-only protocols).
- **Re-exposing an inner field's capability** from an opaque (a deliberate "this opaque *is* the
  linear handle" projection beyond the join) — possible future `opaque T := iso struct{…}` annotation;
  not needed for v1 (choose fields to get the join you want).
