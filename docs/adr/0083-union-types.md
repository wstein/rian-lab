# ADR-0083 — Union types: anonymous structural unions `A | B`, narrowed by type

**Status:** Accepted
**Implemented:** **Phases 1–5; a value union of primitive *or* sum members reaches all four targets in parameter AND return position (a *struct*-member union reaches BEAM/JS/Rust but not `:jvm` yet — structs aren't emitted there); a discriminator clash is a hard `Check` error.** The parser accepts `A | B` in param/field positions → canonical `Union(...)` (`Rian.TypeStr.normalize`, flatten/dedup/sort); the type-pattern `name Type` parses → Core `PTyped` (`Rian.Pratt`/`Rian.Core`). BEAM (`Rian.Beam`) desugars a `PTyped` arm to a var bind + a runtime type-test (`is_integer`/`is_binary`/…), JS (`Rian.JS`) to a `typeof` test, and JVM (`Rian.JVM`) erases the union to `Any` + narrows with `is Long`/`is String` (smart-cast) — so a union of **primitive** members (`Int53 | String`) narrows and **runs on `:ex`, `:js`, and `:jvm`** (BEAM-`apply`/node/kotlinc-verified: `describe(41)/describe("hi")` → `42/0`). `Rian.Check` narrows a `PTyped` binding to its member type and makes a member assignable into a union (conservatively). **Rust** (`Rian.Lower`) synthesizes a name-mangled `enum` + a `From<member>` each, narrows a `case` over a union param to `match` arms `Enum::Variant(binder)`, and wraps a member value with `Enum::from(...)` at BOTH the call site (arg) and the return-body tail leaves (pushed into `if`/`case` branches; a leaf already of union type passes through) — so a primitive union reaches **all four targets in both parameter and return position** (rustc-verified). A union of **sum** members narrows on all four targets (BEAM tag test, JVM `is <sealed interface>`, Rust synthesized `enum`, JS `Array.isArray && tag` — all run-verified). A union of **struct** members narrows on **BEAM/JS/Rust** (`__struct__` test / synthesized `enum`; the JS discriminator *baked into the `PTyped` node* before emit, since `expr_js` threads no registry — `apply`/node-verified) but **not `:jvm`**: the JVM emitter does not yet emit a `data class` for a `struct`, so a struct-using function is JVM-blocked regardless of unions (a broader struct-support gap; `Rian.Reach` does not yet pin it — an open honesty gap). On Rust the `case` scrutinee may be a union **parameter, a `x := <union>` binding, or a union-returning call** (`resolve_rust_pats` tracks the union-typed locals + the program's union-returning functions). A **tvar** member or one nested in a generic still pins off **every** target, honestly (ADR-0000); a **discriminator clash** (`Int32 | Char` — both lower to an integer, so the second arm is dead) is a **hard `Rian.Check` error** (`check_union_clash`) with a clear message, not just a silent reach-pin. The **`T | E` return sugar is wiped out** (`|` is uniformly a value union; a fallible return is the explicit `Result(T, E)`): the parser canonicalizes a return `|` too, the checker/transpiler/range/self-host error-set machinery re-keys onto `Result(T, E)`, and the corpus/tests migrated (ADR-0040 §2 superseded). **Status:** feature-complete for value unions of primitive/sum members (struct-member unions reach all but `:jvm`, above). There is **no `:rs` residual** for a union binding nested inside a branch (`if … do x := <union>; describe(x) …`): `union_locals` does not track it, so the call gets a redundant `Enum::from(x)` wrap — but that is an **identity** via Rust's reflexive `From<T> for T`, so it compiles, runs, and reaches `:rs` (rustc-verified). The earlier "pins `:rs`" note was wrong on both counts (it neither pins nor breaks). **Inference now *synthesizes* unions:** `Rian.Check.join_alts/1` (the join over case/if **arms** and a function's **clauses** — distinct from the raw LUB `join/2`, which still gives `:unknown` cross-constructor per ADR-0059) yields `A | B` when the alternatives have distinct discriminators, so an unannotated `case`/multi-clause helper returning e.g. `{name,…}` in one arm and `None` in another **infers** `(String,…) | None` instead of `:unknown` (a genuinely uninferable/self-recursive arm still forces `:unknown`; a primitive-discriminator clash stays `:unknown`, never a dead union). Mirrored over the fixpoint corpus in the self-hosted `compiler/checker.rian` (a documented subset — no nesting/dedup/clash handling there yet).
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

### 3. The `|` overload — resolved by **dropping the `T | E` return sugar**

`|` means **exactly one thing — a value union — in every position, including return.** The ADR-0040 `T | E` *return sugar* is **retired**; a fallible function writes its result type **explicitly** as `Result(T, E)`:

```rian
def find(id Int64) Result(User, NotFound) := …    # was:  …) User | NotFound
```

The **Result *model* is kept in full** — it is *not* redundant with unions (decided in discussion):

- `Result(T, E)` is `Ok(T) | Err(E)`, a **tagged** union; the tag distinguishes `Ok`/`Err` even when `T = E` (`Result(Int, Int)`), which a structural union cannot.
- The **happy/error asymmetry** is what `<-`/`with` propagation (ADR-0039) rides on — a symmetric value union has no inherent "ok" side to bind vs "error" side to short-circuit.
- The tag carries **error *intent*** (this member is the sad path) and drives **error-set composition** (ADR-0040 §4) — both lost by a bare union.

So unions and `Result` are **complementary tools**, and the only thing dropped is the *syntactic shortcut* that overloaded `|`. The checker's error-set machinery (`check_error_set`/`solve_error_sets`, ADR-0040 §4) **re-keys from a `T | E` return onto the explicit `Result(T, E)` form**; `with`/`<-` are unchanged. This is a small, mechanical **breaking change** (migrate `T | E` returns → `Result(T, E)`); the self-host corpus has one site (`11_wire_formats.rian`) plus a handful of tests.

**Staging note:** the parser adopts `|` = value union in **param/field/binding** first (non-breaking — return still reads the `T | E` sugar during the transition), and the sugar is retired in a final, isolated step that carries the error-set re-key + corpus migration. The end state is `|` uniform.

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

1. **Parse + represent** — ✅ **done.** `Rian.TypeStr.normalize` canonicalizes `A | B | C` (flatten/dedup/sort) → `Union(...)`; `param`/`field` accept it (rejecting garbage). The **type-pattern** `name Type` parses (`Rian.Pratt`) → Core `PTyped`. Reach's `:union` blocker keeps the matrix honest with no emit.
2. **BEAM + JS** — ✅ **done (primitive AND sum/struct members).** `Rian.Beam` desugars a `PTyped` arm to a var bind + a runtime test: a primitive BIF (`is_integer`/`is_binary`/…), a sum's tag-membership, or a struct's `__struct__` (the dispatcher's `sum_guard`/`struct_guard`, parsed over the binder; the registry rides the clause scope). `Rian.JS` emits the `typeof` / `Array.isArray && tag` / `__struct__` discriminator — for a sum/struct member it is **baked into the `PTyped` node** before emit (`bake_union_disc`), since JS's `expr_js` recursion threads no registry. Both BEAM (`apply`) and node verified: `kind/describe` over primitive + sum + struct unions.
3. **Checker narrowing + coherence** — ✅ **done.** `Rian.Check.narrow` binds a `PTyped` arm to its **member** type (`s String ->` ⇒ `s : String`, verified via `annotate`), so member operations type-check; `assignable?` gains union clauses — a member flows **into** a union (`Int53 ⊑ Int53 | String`) and a union flows where **all** members do — both conservative (an `:unknown` member stays assignable, per CLAUDE.md). Coherence: a discriminator **clash** (`Int32 | Char`, both `is_integer`) is not narrowable, so `Rian.Reach` declines to claim it reaches `:ex`/`:js` (a hard `Check` rejection with a message is a future refinement).
4. **Rust** — ✅ **done for a primitive union PARAMETER.** `Rian.Lower` synthesizes a name-mangled, de-duplicated `enum` per distinct union (`RUnion_Int53_String { Int53(i64), String(String) }`) + a `From<member>` impl each; `prim_rust`/`cap_param` lower the union type to the enum name; `resolve_rust_pats` narrows a `case` over a union param to `match` arms `Enum::Variant(binder)`; and the call-site coercion (`borrow_arg`) wraps a member arg with `Enum::from(arg)` (the variant selected by the arg's Rust type — a union-typed arg passes through, no double-wrap). A union param **reaches `:rs`** (rustc-verified: `describe(41)/describe("hi")` → `42/0`). A union **return** reaches `:rs` too — `coerce_union_ret_ast` wraps each member-producing tail leaf with `Enum::from`, pushed into `if`/`case` branches (a union-typed leaf passes through). The `case` scrutinee may be a union **param, a `x := <union>` binding, or a union-returning call** (`resolve_rust_pats` tracks union-typed locals + union-returning funcs). A union binding nested inside a branch is not tracked by `union_locals`, so a call passing it gets a redundant `Enum::from(x)` — **harmless**, an identity via Rust's reflexive `From<T> for T` (compiles + runs, rustc-verified). No residual.
5. **JVM** — ✅ **done for primitive members.** `Rian.JVM`: a union type erases to `Any` (`kt_type`), and a `PTyped` arm narrows with `is Long`/`is String` + a smart-cast bind (`pat_match`) — the dispatcher's discriminator. Construction is **free** (a member value *is-a* `Any`, no wrapping). A primitive union narrows and **runs** on `:jvm` (kotlinc-verified: `describe(41L)/describe("hi")` → `42,0`). Unions now reach `[:ex, :js, :jvm]`; only `:rs` stays pinned (Phase 4).

## Alternatives considered

- **Inline *named* sum sugar** (`def f(x (A | B))` desugars to a fresh hidden `type`) — keeps everything nominal (free Rust/JVM lowering, no synthesis), but anonymous-yet-nominal types are surprising (two identical `A | B` are *different* types → no structural equality, the thing the user wants). Rejected as a half-measure.
- **`Union(A, B)` as a parametric type** — sidesteps the `|` overload entirely and reads like the existing `Result(T, E)`/`Vec(T)`. Viable and *non-controversial*; the only loss is the Crystal-familiar `|` spelling the user asked for. **Kept as the fallback** if the `|` overload proves too subtle in review.
- **Unify errors and unions** (make `T | E` a value union *everywhere*, drop `{:ok}/{:error}` tagging, narrow errors by type) — the cleanest Crystal-faithful end-state and arguably better than `Result`, but it **breaks** ADR-0039/0040 `with`/`<-` propagation and every `{:ok, _}`-matching site. Deferred to its own ADR; explicitly **not** required for the parameter/field win.
- **Status quo (named sums only)** — the portability-cleanest, but it is the verbosity the user (and the self-host corpus) is pushing back on; ADR-0034 already flagged it as a gap.

## Honest assessment (the principal-engineer view, not a rubber stamp)

Value unions are a **real ergonomic win on the dynamic targets and in the self-host corpus**, and Phases 1–3 are cheap and non-breaking (they reuse the dispatcher's discriminator machinery and touch nothing in error handling). The **cost is concentrated in Phase 4 (Rust enum synthesis)** — name-mangling, boundary coercion, and exhaustiveness over synthesized variants are genuinely new emitter machinery, and a structural union is a worse fit for a nominal target than a named sum is (that trade is *why* ADR-0034 chose named sums). The recommendation: **adopt the `|` value-union in non-return positions (Phases 1–3) now** — it solves the stated pain with no risk — and treat the **Rust/JVM lowering (Phases 4–5) and the error-handling unification as separately-gated decisions**, each landing only when its emitter is proven (ADR-0000). If the `|` overload is judged too subtle in review, fall back to `Union(A, B)`; the semantics are identical.
