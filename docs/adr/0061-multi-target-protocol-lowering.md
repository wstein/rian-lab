# ADR-0061 — Multi-target protocol & generics lowering: native-per-target dispatch, target-relative coherence

**Status:** Proposed (design) · BEAM dispatch is **shipped** (ADR-0042 MVP — runtime guarded dispatcher + `check_bounds`); this ADR specifies the **Rust** (static traits) and **JS** (runtime dispatch) lowerings and **reconciles the coherence rules** across the three so one source compiles everywhere it is allowed to. **Foundation landed** (§1): structured protocol/impl IR is preserved (`prog.protocols`/`prog.impl_decls`) and the BEAM runtime-dispatch desugaring is tagged on `IR.Func` (`dispatch: :dispatcher` for the dispatcher, `:impl` for the impl methods) so the Rust path drops its text and the JS emitter skips the dispatcher (regenerating its own). The **JS dispatcher (§3) is shipped** — `Rian.JS` regenerates the dispatcher from the protocol IR with JS-native guards (`typeof` for primitives, tagged-array head for sums); verified in node, including the `Eq`/`Ord` stdlib (`sort`/`contains`/`maximum`). The **Rust trait path (§2) is shipped** — `Rian.Lower.rust_protocols` emits a fresh `trait Rian<P>` + `impl Rian<P> for <rust(T)>` (receiver → `&self`), bounded generics become `fn f<T: RianEq + …>`, and protocol-method calls rewrite to Rust **method-call** syntax (`recv.m(args)`, which auto-refs the receiver); rustc-verified for primitives (Eq/Ord) and sums (Show-for-Expr with a `case` body). **Whole-program assembly shipped** — `Rian.Lower.rust_program/1` / `mix rian.build --rust` emit one module with each `enum`/`struct`/`trait`/`impl` once, so the stdlib + protocols + generics compose (rustc-verified: a sum + two protocols + a cons-recursive bounded generic, one module); generic params carry `+ Clone`. **Target-relative coherence (§5) is shipped** — the runtime-discriminator rule (`Int64`+`Char` share a guard) now applies only to runtime-dispatch targets (`:ex`/`:js`, and unannotated = all); a Rust-only `@targets(rs)` module allows both. Coherence checking is now extracted to `Rian.Coherence` (single source of truth) and run as an **explicit, per-module `Rian.Check` gate** plus a seeded property test (§5 *Amendment*, 2026-06-21); the orphan rule stays *structurally* enforced (an impl's protocol must be in scope) pending cross-module impls. **Remaining:** struct protocol dispatch on JS raises `Unsupported` (gate via `@targets` once a JS-excluding set is declared); generics that *construct an owned collection from borrowed elements* (`insert`/`sort` building `Vec<T>` from `&T`) need element-cloning at the `vec!`/`to_vec` site for generic `T` (a Rust owned-construction refinement); Rust-keyword identifiers (a Rian var named `as`) need raw-identifier (`r#`) escaping; dynamic (`dyn`) dispatch.
**Extended by:** ADR-0074 — associated types (the Rust `trait { type Elem; }` projection + BEAM/JS erasure, for element-generic protocols).
**Amended 2026-06-21 (§5):** coherence checking is extracted to **`Rian.Coherence`** (single source of truth, structured violations) and run as an **explicit, per-module `Rian.Check` gate** — so `gate!` rejects an incoherent program even off the desugar path — plus a **seeded property test** (`coherence_property_test`). The **orphan rule** is honestly scoped: it stays *structurally* enforced (an impl's protocol must be in scope) and is **not** a firing gate, because cross-module impls are not yet supported (the per-scope dispatcher cannot see impls in other modules), so an orphan is currently unconstructible (see §5 *Amendment* below). ADR-0086 §4 records that the breadth strategy *depends on* this coherence; the rule lives here, the single authority. When the ADR-0087 harness lands, coherence becomes a consumer of it.
**Implemented:** partial — BEAM dispatch (`Rian.Protocol`), JS dispatcher (`Rian.JS`) and Rust trait path (`Rian.Lower.rust_protocols`) shipped (`test/rian/protocol_test.exs`, `test/rian/js_test.exs`, `test/rian/lower_test.exs`); struct dispatch on JS, owned-collection-from-borrowed generics, `r#` escaping and `dyn` dispatch not
**Refs:** ADR-0042 (protocols/impls/bounded generics — what this lowers), ADR-0057 (concurrency is native-per-target — the *principle* this borrows: a feature can be one source, three native mechanisms), ADR-0058 (configurable `@targets` — coherence is gated by the declared target set), ADR-0049 (backend tiers — Rust/JS are Tier-1), ADR-0050 (one typed core IR — emitters consume it), ADR-0041 (target model — per-target representation), ADR-0047 (stdlib written over protocols — the first multi-target consumer), ADR-0055 (capability on the protocol-method receiver — survives `dyn` erasure), ADR-0035 (no hidden control flow)
**Owners:** Maya Lin (multi-target/emitters) · Elena Rostova (Rust traits / coherence) · Arthur Pendelton (bounds / type-directed dispatch) · Kira Neri (determinism) · Samir Patel (coherence rigor) · Liam Davis (ergonomics) · Rachel Okafor (PM)

## Context

Protocols, bounded generics (`forall T: Eq + Ord`), and the first stdlib over them
(`List.contains`/`sort`/`maximum`) have all landed — **BEAM-only**. The implementation desugars a
`protocol` into a **runtime guarded dispatcher** (`Rian.Protocol`): one `def m` clause per impl,
selecting on the first argument's runtime *shape* (`is_integer`/`is_binary`, a sum's constructor tag
via `element/2`, a struct's `:__struct__`). A bounded generic just calls that dispatcher;
`Check.check_bounds` enforces the bound *statically* at the call site, then erases it.

This is at odds with Rian's whole reason to exist — **the same source on BEAM, Rust, and JS**
(ADR-0057). Two problems block the other targets:

1. **The dispatch *mechanism* is not portable.** The BEAM dispatcher is a runtime type-test. Rust
   dispatches on **static type** (monomorphization / vtables) and has no runtime type to test; JS has
   no static types and *must* dispatch at runtime. Emitting "the dispatcher" verbatim fits neither.
2. **The coherence *rules* are not the same per target.** Rian's MVP rejects "two impl types that
   share a runtime dispatch guard" (`Int64` and `Char` both `is_integer`). That ambiguity is real on
   BEAM/JS (runtime dispatch) and **non-existent on Rust** (`i64` and `char` are distinct static
   types). Conversely Rust enforces the **orphan rule** and forbids **overlapping impls**, which Rian
   does not yet check. A single set of rules is either too strict for Rust or too loose for BEAM/JS.

**Why coherence is non-optional for Rian specifically** (the breadth argument, ADR-0086 §4): [Gleam](https://gleam.run)
ships *no* type classes at all and wins its audience — real evidence the friendly-typed niche tolerates
no ad-hoc polymorphism. That choice **does not transfer to Rian**, and the reason is the multi-target
thesis itself. Gleam lowers dispatch to two homogeneous GC'd runtimes (BEAM, JS) where an untyped
dictionary behaves identically on both, so an incoherent instance is at worst a harmless runtime
surprise. Rian lowers the *same* dispatch to **monomorphized Rust**, where an incoherent or overlapping
instance is a type error or a *silently divergent binary* — and the reach matrix (ADR-0086 §2 / the
ADR-0087 harness) **cannot catch a soundness bug it does not model**, because it tests reach, not
instance identity. So Gleam can skip coherence *because* it is narrow; breadth is exactly what makes
coherence mandatory for us. This is why the rule below is a hard gate, not a lint.

## Decision

### 1. Protocol dispatch is **native-per-target** (the ADR-0057 move, applied to dispatch)

One Rian `protocol`/`impl`/bounded-generic source lowers to **each target's native dispatch
mechanism**, not a single emitted artifact:

| Target | Dispatch | What is emitted |
|---|---|---|
| **BEAM** | runtime, first-arg shape | the guarded dispatcher `def m` + mangled `impl_*` funcs (shipped) |
| **JS** | runtime, first-arg shape | a dispatcher function switching on `typeof`/tag (mirrors BEAM) |
| **Rust** | **static**, type-directed | a `trait` + `impl`s; bounded generics become `fn f<T: P>(…)`; rustc dispatches |

Like concurrency (ADR-0057), the *concept* is shared and the *mechanism* is idiomatic per host. The
typed core IR (ADR-0050) already carries `protocols`/`impls`/`bounds`; each emitter consumes them
differently rather than consuming a pre-desugared dispatcher. (Concretely: `Rian.Protocol.expand` —
which desugars to BEAM `def`s — becomes BEAM-and-JS-specific; the Rust emitter reads the protocol IR
directly and emits traits.)

### 2. Rust — protocols are traits (the idiomatic, type-directed mapping)

- `protocol P do def m(self Self, …) R end` → `trait P { fn m(&self, …) -> R; }`. The `Self`
  receiver maps to `&self` (receiver capability per ADR-0055 picks `&self`/`&mut self`/`self`).
- `impl P for T do …` → `impl P for <rust(T)> { … }`, with `T` mapped through `Rian.Capability`
  (`Int64 → i64`, a sum → its `enum`, a struct → its `struct`).
- `def f(x T, …) R forall T: Eq + Ord` → `fn f<T: Eq + Ord>(x: …, …) -> R`. Monomorphized by rustc;
  **no dispatcher is emitted**.
- **Fresh, Rian-namespaced traits — not `std` traits.** A Rian `protocol Eq` lowers to a Rian trait
  (e.g. `RianEq`), **not** `std::cmp::PartialEq`. Reusing `std` traits is more idiomatic but drags in
  `std`'s coherence (orphan rules against `std` impls, blanket impls) and forces Rian's method
  *names/signatures* to match `std`'s exactly. The fresh-trait choice keeps Rian's surface authoritative
  and its coherence self-contained; std-trait *bridging* (a blanket `impl std::cmp::PartialEq for T where T: RianEq`) is a future opt-in, not the default.

### 3. JS — a runtime dispatcher (mirrors BEAM)

JS has no static types, so dispatch is runtime, structurally identical to BEAM: a dispatcher function
selects the impl by the first argument's shape — `typeof x === "bigint"` (`Int`; `Int64` is off-JS per
ADR-0064), `=== "string"`
(String), `=== "boolean"` (Bool), the tagged-array head (a sum, ADR-0049 `["Ctor", …]`), or
`__struct__`. A bounded generic is a plain function; the bound is **erased** at runtime (it was
checked statically). This reuses the BEAM dispatcher *strategy* with JS guard expressions.

### 4. Bounds are a static check everywhere; a real bound only on Rust

`Check.check_bounds` (shipped) is the **portable** gate — it runs once, target-independent, and
rejects an unsatisfiable concrete instantiation on every target. Additionally, **on Rust** the bound
becomes a real `T: P` trait bound that rustc re-verifies (defense in depth + enables monomorphization).
On BEAM/JS the bound is erased after the check (runtime dispatch needs no static bound).

### 5. Coherence is **target-set-relative** (the ADR-0058 reconciliation — the heart of this ADR)

There is no single coherence rule set; there is a **lattice of rules, selected by the module's
`@targets`**. A module is checked against the **union** of the rules its declared targets require, so
a program that passes is valid on *every* target it claims:

| Rule | Required by | Why |
|---|---|---|
| **One `impl` per `(protocol, type)`** | all | unambiguous on every dispatch model |
| **Method-set matches the protocol** | all | the contract |
| **Orphan rule** (an `impl` lives in the protocol's *or* the type's defining module) | all (Rust *needs* it) | Rust rejects foreign-trait-for-foreign-type; adopting it universally keeps Rust lowering always legal. **New constraint** — Rian is single-program today. |
| **No two impl types share a runtime discriminator** (`Int64` + `Char` → both `is_integer`) | `:ex`, `:js` only | runtime dispatch can't tell them apart; on Rust `i64`/`char` are distinct static types, so this is *not* a Rust error |
| **No overlapping impls** | `:rs` (subsumed by one-per-`(proto,type)` above) | rustc forbids overlap |

Consequences of target-relativity:

- A module `@targets(ex, rs, js)` (the portable default) must satisfy **all** rows — including the
  runtime-discriminator rule — so `impl Eq for Int64` **and** `impl Eq for Char` together is a
  **portability error** there, even though Rust alone would accept it.
- A module `@targets(rs)` (Rust-only) is **not** bound by the runtime-discriminator rule — it may
  carry both `Int64` and `Char` impls, because Rust dispatches statically.
- This is the same shape as ADR-0058's FFI gating: *the constraints follow from which targets you
  picked.* Coherence stops being one global rule and becomes a reachability-gated contract.

#### Amendment (2026-06-21) — coherence becomes an explicit, property-tested gate; the orphan rule is honestly scoped

Coherence checking lived incidentally inside the BEAM desugar (`Rian.Protocol.expand`, run per scope at
parse time). The amendment extracts it to a single authority and makes it a first-class gate, while being
honest about what is and is not yet a *firing* rule:

1. **Single source of truth.** `Rian.Coherence` now owns the rule table — one impl per `(proto, type)`,
   method-set + arity match, runtime-discriminator presence and non-overlap, associated-type binding —
   as a pure pass returning structured `%{rule, proto, type, message}` violations. Both the parse-time
   fast-fail (`Rian.Protocol.expand`/`Rian.Decl`) and the type gate consume the *same* logic.

2. **Explicit `Rian.Check` gate.** `Rian.Check.check_program/1` runs `Rian.Coherence` over the whole
   program, **grouped per home module** (`Rian.Decl` attributes each `impl`/`protocol` with its scope)
   and that module's `@targets`, so a `(proto, type)` legitimately repeated in two separate modules is
   never a false duplicate. `gate!` therefore rejects an incoherent program even on a path that bypassed
   the desugar (e.g. a hand-built `Prog`), rather than relying on a parse-time side effect.

3. **Property-tested, not only fixture-tested.** `coherence_property_test` (seeded `:rand`) asserts every
   generated coherent program parses and every planted violation is rejected with its rule — the firing
   rules are exercised generatively, not just by the hand-picked corpus. When the ADR-0087 harness lands,
   coherence becomes a consumer of it (ADR-0087 §5), the natural generalisation of this property.

4. **`@targets`-relative, unchanged.** Enforcement *strength* changed, not the rule *set*: the
   runtime-discriminator rule stays `:ex`/`:js`-only; a `@targets(rs)`-only module may still carry both
   `Int64` and `Char` impls (§5 table).

**The orphan rule is the honest exception.** It remains **structurally enforced**, not a separate firing
gate: an `impl`'s protocol must be in its scope, so an impl is forced to be co-located with its protocol
(an out-of-scope protocol reference is rejected as "unknown protocol"). A standalone, *firing* orphan
diagnostic ("`impl P for T` lives in neither's module") presupposes **cross-module impls**, which Rian
does not yet support (the dispatcher is generated per scope; a protocol's dispatcher cannot see impls in
other modules). Until cross-module impls land, there is no orphan a check could reject, so adding one
would be unreachable code. This ADR records the rule's *intent* (the §5 table) and its *current*
structural enforcement honestly, rather than claiming a gate that cannot fire.

Propagation (per `docs/README.md` "Amending a decision-lock"): the Status-summary wording is corrected
above; the executable pins are `coherence_property_test` and the `Rian.Check` gate tests in
`protocol_test`; the sibling coherence rows moved to the explicit gate together (not piecemeal).

## Ratings

| Decision | Rating | Note |
|---|---|---|
| Dispatch native-per-target (runtime BEAM/JS, static Rust) | 5/5 | the only mapping that is idiomatic on all three; mirrors ADR-0057 |
| Rust protocols → **fresh** Rian-namespaced traits | 4/5 | safe (no `std` coherence entanglement); less idiomatic than std-trait reuse, which is a future opt-in |
| JS dispatcher mirrors the BEAM dispatcher | 5/5 | both runtime; near-identical guard logic, low new surface |
| Bounds: portable static check + a real Rust trait bound | 5/5 | one gate everywhere; rustc as defense-in-depth |
| **Coherence target-set-relative (ADR-0058)** | 4/5 | the reconciliation; powerful but adds a rule-selection step the checker must thread through `@targets` |
| Adopt the **orphan rule** universally | 4/5 | a genuinely new constraint (Rian is single-program today); the price of always-legal Rust |
| Reuse `std::cmp` traits on Rust directly (rejected default) | 2/5 | idiomatic but orphan/blanket-impl hazard, and forces Rian method shapes onto `std`'s |
| One global coherence rule set (rejected) | 2/5 | either too strict for Rust or too loose for BEAM/JS |

## Consequences

- **The multi-target promise is restored for the new stack.** `List.sort forall T: Ord` written once
  runs on BEAM (dispatcher), JS (dispatcher), and Rust (`fn sort<T: Ord>`), so ADR-0047's stdlib is
  genuinely portable, not a BEAM artifact.
- **`Rian.Protocol.expand` is reframed** as the BEAM/JS (runtime-dispatch) path; the Rust emitter
  grows a trait/impl path that reads the protocol IR directly. The core IR (ADR-0050) is the shared
  contract; the *desugaring* is no longer target-agnostic.
- **Coherence checking moves into the `@targets`-aware gate** (ADR-0058): `Rian.Reach`/the checker
  selects the rule set from a module's declared targets. The runtime-discriminator rule becomes
  conditional rather than always-on.
- **Rian gains the orphan rule** — a real new restriction on where `impl`s may live, paid so that
  every well-formed program lowers to legal Rust.
- **`@targets(ex)` stays an escape hatch**: a BEAM-only module may use BEAM-only dispatch shapes
  (and skip Rust-coherence), exactly as a BEAM-only module may use OTP FFI (ADR-0057/0058).

## Open items

- **Rust-generic emitter gaps — both DONE (2026-06-14); `17`/`18` now reach `:rs`.** Reach previously
  reported a `:generic` blocker off `:rs` for code `rustc` rejected; both gaps are now closed, so the
  blocker is gone and the integer-generic stdlib slices compile to and run on Rust (`rustc --test`,
  `reach_rust_honesty_test`). What landed:
    1. **owned-from-borrowed coercion — DONE.** A generic borrows its `T`/`Vec(T)`/`String`
       params as `&T`/`&[T]`/`&str`, so `Rian.Lower` now inserts the owned↔borrow coercion (gated on a
       generic function, so non-generic code is untouched): a returned bare `&T` is `.clone()`d
       (`coerce_owned_tvar`); an owned value (literal, cloned element/field binder, owned-returning call)
       passed to a `&T`/`&[T]`/`&str` param gets `&` (`borrow_arg`/`borrow_value`, keyed on the clause's
       *borrowed-var* set = pattern vars of `&`-params ∪ cons-tail binders); a `&T` element stored into an
       owned `Vec` is `.clone()`d (`rust_owned_elem`); and protocol-method args borrow likewise. This is
       the full coercion the earlier investigation found necessary (`maximum`'s recursive `maximum(t, &h)`
       needs the re-borrow, not just a return clone). **`17_stdlib_eq_ord` now compiles to and runs on
       Rust** (`rustc --test`, `reach_rust_honesty_test`); Reach claims `:rs` for it. `Test.rust` routes
       through the whole-program assembly (`rust_program`) so the cross-function signature table the
       borrow pass needs is present. **Case-arm binders now coerce too (2026-06):** a binder in a `case`
       arm whose **scrutinee is borrowed** (a slice cons `[h | _]`, or a `&`-typed param/tuple) is a
       reference into the scrutinee, so an owned-position use clones it — `rust_case` extends the
       borrowed-var set with the arm's binders (carried on the resolved `{:rpat, str, binders}`), and
       `rust_owned_elem` clones them (`Some(h.clone())`, `(b.clone(), a.clone())`). This **fixed a
       pre-existing over-claim**: `case xs do [h|_] -> Some(h)` reported `:rs` but rustc rejected it, since
       only *clause-head* cons binders had been cloned. **Anonymous tuples reach `:rs`:** `(a, b)` values
       and patterns parse (`Rian.Pratt`, the paren form of `{a, b}`), a tuple type `(A, B)` lowers
       element-wise (`Capability.owned` → `(owned(A), owned(B))`), and a tuple value owns its elements
       (`rust_owned_elem`: a `&T` binder cloned, a `String`/`&str` element `.to_string()`d — `str` is not
       `Clone`). So a generic `swap(p (T,U)) (U,T)` and a `(Int53, String)` builder compile + run on Rust
       (`lower_test`). `Fn` mentioning a tvar in a tuple/nested position is the remaining uncoerced case.
    2. **parametric user types — DONE.** `type Pair := P(k K, v V)` lowers to `enum Pair<K, V>`
       (`enum_generics`/`parametric_param_map`). Rian writes the type bare (`Vec(Pair)`), so `Rian.Lower`
       rewrites each signature/return to its instantiation (`rustify_parametric`): a **generic** function
       reuses the type's param names (`Pair<K, V>`, with any free param tvar — e.g. `has`'s `V` — added to
       the generic list via `fn_all_tvars`); a **non-generic builder** (`sample`/`names`) gets a concrete
       instantiation (`Pair<i64, i64>` / `Pair<String, i64>`) inferred from the body's tail constructor
       call (`infer_concrete_params` binds the callee's tvars from its arg literal types). A borrowed
       field at construction is `.clone()`d, and a string literal fed to a generic `&K` (which resolves to
       owned `String`) becomes `&format!("{}{}", "a", "")` (`owned_str_arg`). **`18_dict_eq` compiles to and
       runs on Rust** (`rustc --test`). The support is a **narrow monomorphic subset**, and `Rian.Reach`
       gates `:rs` to *exactly* that subset (`parametric_rs_ok?`, a default-deny allow-list) so the matrix
       never oversells a shape rustc rejects: a type's tvar fields must each be **lowerable** — a bare tvar
       (`k K`) OR a tvar nested in `Vec`/`Option`/`Result` (recursively): `items Vec(T)` now lowers to
       `enum Stack<T> { S { items: Vec<T> } }` because the enum's generic params are collected from every
       field tvar (`type_param_tvars`), not just bare-tvar fields. A field that is **(exactly) another
       parametric type's name** also lowers — `Wrap(p Pair)` → `enum Wrap<K,V> { W { p: Pair<K,V> } }` —
       its generics propagated by a fixpoint over the type graph (so a chain `Outer→Middle→Pair` resolves
       too). An **`Fn(...)` field** also reaches `:rs` (2026-06): it lowers to a *shared* `Rc<dyn Fn>`
       field, so the enum can `#[derive(Clone)]` (a `Box<dyn Fn>` can't — closures aren't `Clone`), with
       `Rc::new(move …)` construction, the captured tvar param owned + `T: 'static` (a consumer's
       `&Cell<T>` too). Debug/PartialEq are dropped (a closure has no portable show/eq), so `Rian.Reach`
       pins a function that `==`/`!=`s such a value (`compares_fn_field?`) — construction/storage/call
       reach `:rs`. A **recursion cycle** (self- or mutual — an infinitely-sized Rust type that would need
       `Box`) or a parametric type nested in a **compound** (`Vec(Pair)` — no args surfaced) still pins:
       `Rian.Reach` gates these with a monotone emittability fixpoint (`emittable_map` — a leaf resolves
       first, a cycle never bootstraps) over a parametric-type set widened to include *referencing* types
       (`Bag(ps Vec(Pair))` is itself gated). (A `Map`/tuple type as a parametric FIELD is conservatively
       pinned too, though it would lower — an honest under-claim.)
       A **generic** builder's construction
       into a *bare-tvar* field must still match positionally (`P(key, value)` with `key K`, `value V` —
       not `P(a, b)` with `a A`, `b B`), but construction into a *lowerable compound* field accepts any
       well-typed arg (`S([x | items])`, `B(Some(x))` — the construction coercion clones the payload); a
       **non-generic** builder must not construct directly (nothing to infer) and must tail-call a generic
       helper (the one shape `infer_concrete_params` binds). Anything outside this — including the
       previously-silent `i64` fallback — pins off `:rs` with a `:generic` blocker (`reach_rust_honesty_test`
       and `lower_test`, with `@tag :rust` cases proving both the supported shapes run and a pinned shape
       fails rustc).
    3. **compound owned-tvar returns — DONE (2026-06-14).** `Option(T)`, `T | E` (a generic ok-type), and
       a user sum over a tvar now reach `:rs`: the payload is `.clone()`d at construction
       (`rust_owned_elem` on variant fields and on `Ok`/`Err`) — **including a payload reached via a `:=`
       binding** (`y := x; Some(y)`), where the rebind clones the borrowed `&T` to an owned `T`. Nested
       generic returns (`Vec(Option(T))` → `Vec<Option<T>>`) lower correctly too (`Rian.Capability.owned`
       strips exactly the one closing paren per layer). Verified on rustc (`reach_rust_honesty_test`).
  **Closure-as-value lowering landed (2026-06-17).** An `Fn(args.., ret)` callback **parameter** lowers
  to argument-position `&impl Fn(<lowered args>) -> <lowered ret>` (`Rian.Capability.rust_param`) — by
  *reference* so a recursive higher-order fn (`map`/`filter`/`reduce`) can both call it and re-pass it
  without a use-after-move; a closure-call's bare-variable args are `.clone()`d (the callback takes its
  args by value, so a reused element survives and a borrowed `&U` coerces to owned `U`). A **concrete**
  returned closure lowers to `Box<dyn Fn(...)>` + `Box::new(move …)` (`Rian.Capability.owned` +
  `Rian.Lower`). So `map(f Fn(T, U), …)`, `apply_twice(f Fn(Int53, Int53), …)`, and `adder(n Int53)
  Fn(Int53, Int53)` all reach `:rs` (rustc-verified, `reach_rust_honesty_test`); the whole
  `prelude_list.rian` is back on the full `ex,rs,js` CI gate.

  A **returned closure over a type variable** reaches `:rs` too — **top-level OR nested** in the return
  type (`mk(x T) Fn(Int53, T)`, `Option`/`Result`/`Vec(Fn(Int53, T))`). `Rian.Lower` lowers the captured
  tvar param **owned** (`x: T`, not `&T`, so the boxed `dyn Fn` is `'static`), adds a `T: Clone + 'static`
  bound in `rust_generics`, and boxes every **value-position** closure at the `ELambda` emit (driven by
  `fn_ec.fn_box`) — `Box::new(move |n| (x).clone())` — cloning a captured tvar body per call (a reusable
  `Fn`, not a move-out `FnOnce`). Because the boxing is at the closure (not the return tail), a `Fn`
  nested inside a constructor — `Some((n) -> x)` → `Option::Some(Box::new(move …))` — lowers the same
  way. So **no `Fn`-bearing signature is pinned off `:rs`** any more (callback param, top-level return,
  nested return, HOF — all reach `:rs`); rustc-verified (`lower_test`, `reach_rust_honesty_test`). The
  remaining `:rs` gap is the **parametric** shapes still outside the (now-widened) monomorphic subset —
  recursion cycles and compound-nested parametric fields, comparison of an `Fn`-field type, and the
  non-positional/non-tail-call builder shapes. (A
  Copy-primitive *protocol-impl receiver* used as a value — `Show for Bool`'s `if b` — now derefs
  correctly and reaches `:rs`.)
- **`Self` and associated types.** This ADR maps `Self` as the receiver only; protocols with
  `Self`-returning methods (`def add(a Self, b Self) Self`) and associated types are a further Rust
  mapping question (return-position `Self`, generic associated types).
- **Dynamic dispatch / `dyn`.** A protocol-typed *value* (`x P`) → Rust `Box<dyn P>` / `&dyn P`,
  interacting with the receiver capability (ADR-0055). The MVP is static (monomorphized) bounds; the
  `dyn` path is deferred.
- **`std`-trait bridging.** Whether/when a Rian `Ord` should also `impl std::cmp::Ord` so Rian values
  drop into Rust's `sort`/`BTreeMap` — a future opt-in with its own coherence design.
- **JS BigInt vs number for the receiver test.** `Int → bigint`, but `Int53`/`Int32 → number`
  (ADR-0064 §2a; `Int64` is off-JS): the JS dispatcher's numeric guard must match the chosen
  representation per function.
- **Generic monomorphization blow-up on Rust.** Heavily-bounded generics over many types monomorphize
  widely; whether to offer a `dyn`-backed mode for code size is a perf decision, not a correctness one.
- **Migration order.** JS dispatcher first (reuses the BEAM strategy, low risk), then the Rust trait
  path (new surface); the coherence rule-selection lands with whichever target needs it first.
