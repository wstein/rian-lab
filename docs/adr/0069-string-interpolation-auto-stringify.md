# ADR-0069 — String interpolation that auto-stringifies via a portable `Show`

**Status:** Accepted · **Implemented (2026-06-15)** — the `${expr}` surface (decision A) + auto-stringify for `Char`/`Int*`/`Bool`/`String`/**`Float64`** holes, portable and **byte-identical across all four targets** (`:ex`/`:rs`/`:js`/`:jvm`, every double — §6); interpolation lowers to a single-shot join (§6). The lowering strategy is settled in §6 (canonical desugar, not target-native interpolation). User-type & derived `Show`/runtime dispatch remain deferred (see §6, *Open items*, and *Implementation* below).
**Implemented:** partial — `${expr}` lexing (`{:istr}`), Pratt (`{:str_interp}`), `Rian.Interp` static resolution, `__prim_int_to_string` on Beam/JS/Lower(Rust+Elixir)/JVM; `Int*`/`Bool`/`String` holes reach all four targets, honestly via `Rian.Reach` (an `Int` hole inherits ADR-0064's `[:ex,:js]`). `test/rian/interp_test.exs`. **Float64 unlock — foundation landed:** `__prim_float_repr` (each target's native shortest-round-trip string) on Beam/JS/Lower(Rust+Elixir)/JVM, reaching all four; `test/rian/interp_float_conformance_test.exs` proves the premise — the shortest digits are **identical** across BEAM/Rust/JS/JVM (only presentation diverges). **Step 2 landed:** `Show.float` (`examples/rian/stdlib_show.rian`) — the canonical ECMA-262 §7.1.12.1 `Number::toString`, written ONCE in portable Rian over the repr (parse → shortest-digit `(s, n)` → ECMA presentation cases). `test/rian/show_float_test.exs` proves it **byte-identical to ECMAScript `String(x)` on BEAM, JS, Rust, and the JVM** — over a corpus (exponent thresholds, subnormals, ±0, extremes). The Rust-emitter coverage for this collection-heavy shape landed alongside (ADR-0061: `case`-over-`Vec` slice match, owned↔borrow coercion of sum-field/slice binders, `&str`→`String` branch unification); the JVM coverage came with the Tier-2 list/cons emitter (ADR-0049). **Step 3 landed — wired into `${…}`:** a `Float64` hole resolves to `Show.float(value)`, and `Rian.Decl.inject_stdlib/1` **auto-injects** the `Show` module the first time a program interpolates a float (conditional — a non-float program is untouched). On the BEAM `Show` loads as a sibling `Elixir.Show` module (`Rian.Beam.load`); JS and the JVM each flatten it into the one module (`Rian.JS.all_funcs/1` / `Rian.JVM.all_funcs/1`, the cross-module `Show.float` call lowering to a bare `float(…)`); Rust emits it as `mod show`. So a `Float64` interpolation reaches all four targets, **byte-identical on every one**. The JVM needed one extra step: Java's `Double.toString` is JLS-pinned to a *non-shortest* digit string for the tiniest denormals (`4.9E-324` vs ECMA `5e-324`), which would break byte-identity — so the JVM's `__prim_float_repr` searches for the true shortest round-tripping decimal (the smallest `%e` precision that parses back to `x`) instead of trusting `toString`. Verified equal to ECMAScript over the full corpus (denormals included) and a 120k-double fuzz, so there is **no caveat**. **Step 4 landed — user `Show`:** a hole whose static type `T` has an `impl Show for T` lowers to `show(value)` (`Rian.Decl` collects the `Show`-impl type set; `Rian.Interp` routes such holes to the protocol method). Still monomorphic — the static type fixes `T`. Reaches as far as the impl does (a sum-dispatch consumer is `[:ex, :js]`, honestly via Reach). A user type with no `impl Show` stays the `no Show` error. **Field-access + `inspect` inference landed (2026-06):** a `${p.name}` hole now resolves to the field's declared type when `p` is a single-variant struct (a new `Rian.Check` `:fields` table, seeded into `Rian.Decl`'s inline interpolation `ic`); over a `_Unk` draft value the access propagates `_Unk` and so *defers*; `.f` on an un-narrowed sum still infers `:unknown` (narrow with `case`). An `${inspect(x)}` hole resolves to `String` (host `inspect`'s return is unambiguous, though the function pins to `:ex` via Reach). **Program-wide resolution landed (2026-06):** interpolation is now a single post-assembly pass (`Rian.Decl.resolve_interp/1`), so its `ic` carries **every module's** signatures/types/structs/ctors — a `${OtherMod.f(x)}` cross-module call (new `Check.infer` clause: a dotted call resolves by `{name, arity}` against the module-flattened `:funs`) and a cross-module struct field both resolve, not only same-scope holes. Deferred: **derived** `Show` (a separate stable-contract decision), `Char` runtime dispatch, cross-*file* resolution across separately-compiled units (within one compiled program — incl. a concatenated multi-module project — it works; the per-file `mix rian.compile` of one source still sees only that file's modules), and host/foreign call returns beyond `inspect` (`:erlang.*` / pipe-chains over stdlib still infer `:unknown`).
**Refs:** ADR-0042 (protocols & bounded generics — the dispatch this leans on), ADR-0061 (multi-target protocol lowering — BEAM/Rust/JS dispatch, the Rust owned-return gap), ADR-0047 (portable prelude/stdlib — the `Prim.*` intrinsic layer), ADR-0051 §"Open items" (interpolation deferred for doc heredocs — "probably no"), ADR-0035 (no hidden control flow — the central tension), ADR-0033 (surface vocabulary), ADR-0064 (portable numeric contract — `Int53` is the portable integer; `Int`/wide ints are off some targets), ADR-0057/0058 (target-environment sets; reachability), ADR-0065 (P7 surface freeze — this surface is *not* frozen).
**Owners:** Maya Lin (surface / emitters) · Samir Patel (types / protocol bounds) · Kira Neri (honesty) · Mira (totality) · Tomás (BEAM performance) · Rachel Okafor (PM)

## Context

Rian has no string interpolation. A string literal is lexed straight to a flat, escape-resolved
binary (`Rian.Lexer.lex_string/2` returns `{decoded, rest}`), parsed to a single `{:str, s}` token
([pratt.ex:198](../../lib/rian/pratt.ex)), and carried in Core as `EStr{value}` with no internal
structure ([core.ex:111](../../lib/rian/core.ex)). The sanctioned way to build a string from parts is
explicit concatenation with `<>`, and turning a non-string into a string is FFI today
(`Integer.to_string(n)` — which pins the function to `:ex`, see
[09_capstone_calc.rian:51](../../examples/rian/09_capstone_calc.rian)).

That FFI dependency is the real problem this ADR addresses. "Print a number into a message" is the
single most common reason a function falls *out* of the portable core: there is no portable
`to_string`, so every formatting function is BEAM-only. We have a `Show` protocol in the tour
([13_protocols.rian:23](../../examples/rian/13_protocols.rian)) but it is a toy — not in the prelude,
not portable, its `Int64` impl literally returns `"an integer"`.

This ADR proposes the **auto-stringify** direction: interpolation accepts arbitrary values and
stringifies each hole through a real, portable `Show` protocol. (The narrower **pure-sugar**
direction — interpolation accepts only `String`, desugaring to `<>` with zero new semantics — is
recorded under *Alternatives*; it is a weekend of plumbing but solves nothing about portability.)
Auto-stringify is the larger commitment because it requires a stdlib protocol that lowers honestly to
all four targets. The interpolation *syntax* is the small part; **the load-bearing decision is
shipping a portable `Show`.**

## Decision

### 1. Surface — a spelling shootout

A hole is an expression embedded in a `"…"` literal. Scored against: **visible** (the hole is
unmissable, ADR-0035), **family-native** (ADR-0033 surface lineage), **minimal lexer delta**, **no
collision** with existing in-string syntax.

| # | Spelling | Example | Visible | Family | Lexer delta | Notes |
|---|----------|---------|---------|--------|-------------|-------|
| A | `\(expr)` | `"hi \(name), age \(age)"` | ✅ | ⚠ Swift-only; reads like an escaped paren to most | **smallest** — `\` already dispatches into `char_escape/1`; add one `\(` arm | smallest lexer delta, but Swift is the *only* mainstream precedent |
| B | `${expr}` | `"hi ${name}"` | ✅ | ✅ JS/Kotlin/Scala/Dart/shell — incl. two of Rian's own targets | new: `$` is otherwise unused, must special-case `${` inside strings | **chosen** — familiar to the broadest audience and to Rian's JS/Kotlin targets; `$` is free elsewhere |
| C | `#{expr}` | `"hi #{name}"` | ✅ | ✅ Elixir-native | new + **adjacency hazard**: `#` is the line-comment sigil; readers must learn `#` means two things | rejected — overloading the comment sigil costs more than it buys |

**Direction:** **B (`${expr}`)** — *chosen 2026-06-14, reversing the initial pick of A.* The original
call optimised for the **smallest lexer delta** (`\` already diverts `lex_string/2` into escape
handling, so `\(` is one more arm). But that is an implementation virtue, not a reader virtue, and the
deciding axis is **familiarity for Rian's actual population**: `\(…)` is Swift-only and reads as an
*escaped paren* on first sight, whereas Rian lowers to **JS and Kotlin** (both `${…}`) and an enormous
swath of working programmers already know `${…}` from those plus Scala/Dart/shell. `$` is otherwise
unused in the grammar, so the collision cost is one new lexer rule (`$` is special only before `{`; a
bare `$` like `"$5.00"` is an ordinary character) plus a `\$` escape for a literal `${`. C stays
rejected for overloading the `#` comment sigil. (The lexer-minimalism that favoured A is a one-time
cost; the surface is read forever — ADR-0065 P7 left `${…}` outside the freeze precisely so this could
be revisited.)

A hole may contain any expression the Pratt parser accepts (it re-enters `expr_tokens`); the lexer
captures a hole by **brace depth**, so a map/tuple literal inside a hole nests correctly. Nesting a
string inside a hole is allowed but discouraged by the formatter (ADR-0045). An empty hole `${}` is a
compile error.

### 2. Semantics — desugar to `Show.show` + `<>`

`"a ${x} b ${y}"` desugars, at the parse boundary, to the concatenation chain

```
"a " <> show(x) <> " b " <> show(y) <> ""
```

where `show` is the `Show` protocol method (ADR-0042 dispatch). A literal `String` hole still goes
through `show` — `impl Show for String` is the identity ([13_protocols.rian:37](../../examples/rian/13_protocols.rian)),
so it is a no-op the optimizer can elide. **This is sugar over existing machinery:** `<>` already
type-checks and lowers everywhere, and `show` is an ordinary bounded-generic call. No new Core node is
strictly required — the desugaring can emit `ECall`/`EStr` directly — though a thin `EStrInterp{parts}`
node is worth keeping through `Check` so error messages point at the hole, not the desugared chain.

The whole expression has type `String`. Each hole imposes a `Show` bound on its expression's type: a
hole `${e}` type-checks iff `typeof(e)` has an `impl Show`. A type with no `Show` impl is a **compile
error at the hole** (`no impl Show for <T> — interpolation requires it`), never a silent
`inspect`-style fallback.

**Undetermined vs determined (2026-06 debate, refining the rule).** The error above is correct only for
a type the resolver has *determined* and proven non-stringifiable (`Float32`, a user type with no `impl
Show`). It must **not** fire when the type is merely *undetermined* — the resolver hasn't inferred it, so
it cannot prove non-stringifiability, and erroring there violates the checker's own contract ("infer
`:unknown`, error only on a **provable** mismatch"). Two undetermined cases, handled differently
(`Rian.Interp.stringify/3`):

- the **`_Unk` transpiler-draft marker** (a deliberately-unsupplied type in `mix rian.transpile` output)
  — **superseded.** This originally *deferred* (the value passed through `<>` so a draft parsed). Per the
  ADR-0034 revision, a **declared `_Unk` in a signature is now REJECTED by the gate** (`Check.check_unk`):
  `_Unk` is a *fill-me* marker, not a deferrable type — a draft must be completed before it compiles
  (use `Any` for a genuinely-dynamic value). The defer below applies only to a genuine inferred
  `:unknown`, not a declared `_Unk`.
- a genuine **`:unknown`** (the checker actually failed to infer a real program's type — an un-pinned
  generic, an unbound name, a host/pipe-chain return) → **falls through to runtime `Show`** (2026-06
  reversal of the earlier "still a hard error" rule). The hole lowers to **`Prim.to_string`**, the host's
  native runtime stringifier (BEAM `String.Chars.to_string/1` · JS `String(x)` · JVM `x.toString()`),
  which dispatches on the value's *actual* type at run time. Rationale: erroring on a merely-undetermined
  type **proves nothing** and violates the checker's own contract — and the draft compiler sources whose
  port this unblocks are full of legitimately-undetermined holes that a static refusal would freeze out.
  The static guarantee weakens to a *runtime* one (a value with no runtime stringification fails at run
  time, not compile time) — the trade the goal-clarification accepts. **Reach stays honest:** there is no
  universal Rust `Display`, so a body that runtime-stringifies an unknown is pinned **off `:rs`** via the
  `:prim` `to_string_prim_blocker` (`Rian.Reach`) — it reaches `:ex`/`:js`/`:jvm`, exactly the targets
  whose emitters lower `__prim_to_string`. A *determined* non-stringifiable type (`Float32`, a user type
  with no `impl Show`) is unchanged — **still a hard error**, because that is a *provable* verdict.

### 3. The portable `Show` protocol (the actual work)

Promote `Show` from tour toy to prelude protocol, with **portable impls for every primitive**, backed
by two new intrinsics in the `Prim.*` layer (ADR-0047 §2, `Rian.Prim.@prims`):

| Prim | BEAM | JS | Rust | JVM |
|------|------|----|----|-----|
| `__prim_int_to_string` | `erlang:integer_to_binary/1` | `String(n)` / `n.toString()` | `n.to_string()` | `n.toString()` |
| `__prim_float_to_string` | `io_lib_format` shortest-round-trip | `String(n)` | `format!("{}", n)`† | `n.toString()`† |
| `__prim_to_string` (runtime Show, §2) | `String.Chars.to_string/1` | `String(x)` | — (off `:rs`) | `x.toString()` |

```rian
# stdlib_show.rian  (sketch)
protocol Show do
  def show(self Self) String
end

impl Show for String  do def show(s) := s end
impl Show for Int53   do def show(n) := Prim.int_to_string(n) end
impl Show for Bool    do def show(b) := if b do "true" else "false" end end
impl Show for Char    do def show(c) := Str.from_chars([c]) end
# Float64: the standalone portable `Show.float` normalizer (stdlib_show.rian),
# auto-injected into a `${float}` hole — resolved, see Open items.
```

User sum/struct types get `Show` by writing an `impl` (as `Expr` does at
[13_protocols.rian:69](../../examples/rian/13_protocols.rian)); there is **no derived/auto `Show`** in
this ADR (see Open items — derivation is the obvious follow-up but a separate decision).

### 4. Portability & Reach — honest, not aspirational

Interpolation is **as portable as the `Show` impls its holes touch**, propagated by `Rian.Reach`
exactly like any other call (ADR-0057/0058). Concretely:

- A hole whose type is **`Int53`/`Bool`/`Char`/`String`** with portable impls keeps the function in
  the `:ex/:rs/:js/:jvm` core, *provided* the two `__prim_*_to_string` intrinsics are implemented on
  all four emitters. **If an emitter lacks the intrinsic, Reach must pin the function off that target
  with a `:prim` blocker** — same honesty rule ADR-0064 applies to wide-int prims (`wide_prim_blocker`).
- A hole typed **`Int`** (arbitrary precision) inherits ADR-0064: reachable only `[:ex, :js]`, so a
  message interpolating an `Int` is off `:rs`/`:jvm` — correctly, not silently.
- **The Rust generic gap (ADR-0061 Open items) mostly does not bite here.** That gap is "a generic
  returning an *owned tvar* needs a borrow→owned clone." `show` returns a concrete `String`, not a
  `T`, and at each hole the receiver type is *known* (interpolation is monomorphic per call site), so
  Rust dispatch monomorphizes to a concrete `impl` with no owned-tvar return. The one place it *would*
  bite — interpolating a value of a still-generic `T: Show` inside a `forall T: Show` function — is
  the same pre-existing limitation, and Reach already pins those with `:generic`. **The interpolation
  feature adds no new Rust gap; it inherits the existing one.**
- **Coherence (ADR-0061 §5):** one `impl Show` per type, and on runtime-dispatch targets (`:ex`,
  `:js`) no two impls may share a dispatch guard — `Int53` and `Char` both test `is_integer` on the
  BEAM, so they **cannot both** have a guard-colliding `Show` on those targets. This is a real
  constraint the impl set above must respect (it does: `Char` shows via `Str.from_chars`, but the
  *dispatcher* still needs a discriminator — flagged in Open items, this is the sharpest hidden cost).

### 5. The ADR-0035 tension, stated plainly

Interpolation **hides a protocol dispatch and a concatenation chain** behind string syntax. That is
in tension with "what you read is what runs" (ADR-0035). The defense: the *hole markers are visible*
(you can see `${x}` runs *something* on `x`), and the something is a single, total, value-returning
`show` — no control flow, no early return, no effect. This is unlike the error-propagation case
(ADR-0066) where the hidden thing was *control flow*; here the hidden thing is a *pure function call*,
which ADR-0035 has never objected to (every operator desugars to a call). The line we hold:
interpolation may hide a **pure `Show.show`** and nothing else — never an effectful or partial
operation, never an `inspect`-style reflective fallback for un-`Show`-able types.

### 6. Lowering strategy — canonical desugar, not target-native interpolation (amended 2026-06-14)

A recurring proposal is to lower a hole to each target's **native interpolation** — Kotlin
`"hi $name"`, JS `` `hi ${name}` ``, Rust `format!("hi {name}")` — for idiomatic output. **Rejected
as a *semantic* path; admitted only as a cosmetic emitter peephole.** Two facts decide it:

1. **Native interpolation delegates stringification to the target's formatter, and those formatters
   diverge** — which would make the *output string itself* target-dependent and break the equivalence
   contract that is the language's reason to exist (shared logic *and tests* across targets). The
   divergence is not hypothetical; for `Float64`:

   | value | BEAM `float_to_binary(_,[:short])` | Kotlin `toString()` | Rust `format!("{}")` (`Display`) | JS `String(_)` |
   |-------|------|------|------|------|
   | `1.0` | `1.0` | `1.0` | **`1`** | **`1`** |
   | `100.0` | `100.0` | `100.0` | **`100`** | **`100`** |
   | `1.0e21` | `1.0e21` | `1.0E21` | **`1000000000000000000000`** | **`1e+21`** |
   | `1.0e-7` | `1.0e-7` | `1.0E-7` | **`0.0000001`** | **`1e-7`** |

   A shared `@test` asserting `greet(1.0) == "v=1.0"` would pass on BEAM/JVM and **fail on Rust/JS**.
   `Bool`/`Int`/`String` happen to agree, but the rule must hold for the whole type universe.

2. **The BEAM backend emits Erlang abstract forms, which have no interpolation syntax at all** — so a
   native lowering could *never* be universal; the concat/`__prim_*` path is always required on at
   least one target. Maintaining both is pure cost.

**Decision.** Stringification stays Rian-controlled (the `__prim_*_to_string`/`Show` layer), computed
by `Rian.Interp` *before* the checker and `Rian.Reach`, guaranteeing byte-identical output. Reach
sees the real `__prim_*` nodes, so it never claims a portability it cannot verify. Target-native
interpolation *syntax* is a legitimate but purely cosmetic emitter concern; if ever built it must be
an emitter-stage peephole that (a) runs *after* `Interp`/`Reach` on resolved Core, (b) fires only on
holes whose static type is in the proven-identity set `{String, Int*, UInt*, Bool}` and falls back to
the canonical chain otherwise, (c) skips the BEAM. It leads nothing and is the lowest priority.

This also explains why **`Float64` was the hard, principled unlock**: portable float interpolation
needs a *single canonical format* — `Show.float`, the ECMA-262 §7.1.12.1 normalizer written once in
Rian over each target's native shortest-round-trip repr (`__prim_float_repr`) — explicitly *not*
delegating to per-target `Display`/`toString` presentation. That landed (§"Open items", resolved): a
`Float64` hole auto-injects `Show.float` and is byte-identical on **all four targets, every double** —
the contract `__prim_float_repr` carries is "shortest round-trip," which each target honors (the JVM by
a shortest-search, since its `Double.toString` is not always shortest at the denormals).

## Ratings

| Decision | Rating | Note |
|----------|--------|------|
| 1 — `${expr}` surface | 4/5 | chosen for familiarity (JS/Kotlin/Scala/Dart/shell, incl. two targets) over A's smaller lexer delta; −1 for the one-time `${`/`\$` lexer special-case vs A's zero-delta reuse of escape dispatch |
| 2 — desugar to `show` + `<>` | 5/5 | zero new semantics, reuses checked/lowered machinery; error-locating node is cheap |
| 3 — portable `Show` + 2 prims | 4/5 | the genuine payoff (kills the #1 portability leak); −1 for the float round-trip divergence and the four-emitter prim cost |
| 4 — Reach honesty | 5/5 | inherits existing blockers; adds only a `:prim` blocker that follows the established ADR-0064 pattern |
| 5 — ADR-0035 stance | 3/5 | defensible (pure call, visible markers) but it *is* hidden dispatch; reasonable people will push back |

## Consequences

- **The portability win is the point.** Once `Show` is portable, every "format a value into a message"
  function joins the portable core instead of being pinned to `:ex` by `Integer.to_string` FFI. This is
  a larger payoff than the syntax — the syntax is the on-ramp.
- **Drift tax (CLAUDE.md):** a (thin) `EStrInterp` node threads lexer → Pratt → Core → Check →
  Beam/Lower/JS/JVM; the two `__prim_*_to_string` intrinsics need an arm in each emitter
  (`Rian.Beam`, `Rian.JS`, `Rian.Lower`/Rust, `Rian.JVM`) plus registration in `Rian.Prim`. Missing
  one surfaces as the usual `FunctionClauseError`/`Unsupported`.
- **Formatter (ADR-0045):** must learn to format inside holes and decide a house style for nested
  interpolation (lean: forbid nesting strings in holes, suggest a `let`).
- **Surface freeze (ADR-0065 P7):** `${…}` is explicitly *outside* the freeze until this ADR settles.
- **Detokenizer round-trip:** the lexer's re-escape path (`escape_str`/`char_source`) must round-trip
  `${…}` as interpolation, not as a literal — guarded by the detokenizer round-trip tests.

## Implementation (partial, 2026-06-14)

Shipped the settled core; deferred the items this ADR itself flagged "resolve
before implementing" (the `Char`/`Int` dispatch collision) and "gate off" (`Float`):

- **Surface (decision B, `${expr}`).** `Rian.Lexer` recognises `${` inside a string
  as a hole start (a bare `$`, e.g. `"$5.00"`, is an ordinary character) and captures
  the hole's source by **brace depth**, producing an `{:istr, parts}` token (literal
  segments + raw hole source); a literal `${` is written `\${` (the `\$` escape).
  `Rian.Pratt` re-parses each hole into a `{:str_interp, parts}` node; an empty hole
  `${}` is a parse error. The detokenizer round-trips `${…}`.
- **Static resolution, not runtime dispatch.** Because interpolation is
  **monomorphic per call site** (§4), `Rian.Interp` resolves each hole to a
  stringify expression in the declaration pass — *where the clause's parameter
  types are in scope* — by the hole's **statically inferred type**: `String` →
  identity, `Int*`/`UInt*` → `__prim_int_to_string`, `Bool` → an `if`. This is the
  key simplification: no runtime `Show` dispatcher is generated, so **the
  Char/Int53 dispatch-guard collision (the sharpest open cost) does not arise**,
  and Rust gets the monomorphic concrete `impl` for free. There is **no new Core
  node and no per-emitter `{:str_interp}` handling** — the checker and all four
  emitters see an ordinary call tree. The resolver's inference scope is the *whole
  program*: its `ic` is built once over every module's signatures, types, structs and
  ctors (so a cross-module `${A.f(x)}` resolves), it folds in **call-result return
  inference** (`Rian.Check.fill_local_rets/2` — an un-annotated local function's
  return is inferred from its body, so `${tag(n)}` over `def tag(s) := s <> "!"`
  resolves to `String`), and it is **scope-aware**: a hole inside a `case` arm or
  after a block `:=` bind sees those names typed (an arm pattern binds against the
  scrutinee's type), exactly as `Rian.Check.annotate` threads its env.
- **Single-shot join (§6).** The stringified parts are combined by *one*
  `__prim_str_concat_all(parts…)` intrinsic, not a left-nested `<>` cascade that
  would build N−1 intermediate strings. It lowers to one allocation where it pays
  — a single BEAM binary (`<<p1/binary, …>>`) and a single Rust `format!` — and to
  a flat `+` chain on JS/JVM (which their engines already fold into one builder).
  Empty literal segments (the lexer's trailing `{:lit, ""}`, and `""` between
  adjacent holes) are dropped; a single-part interpolation collapses to the bare
  value. The join is portable (no Reach blocker) and `Check` types it `String`.
  The Rust emitter **bakes the literal segments into the `format!` template**
  (`"Hello, ${name}!"` → `format!("Hello, {}!", name)`, not `format!("{}{}{}",
  "Hello, ", name, "!")`) — braces in a literal are doubled (`{` → `{{`). This is a
  *byte-identical* cosmetic peephole, distinct from the rejected hole-native path
  (§6 above): the holes stay pre-stringified `{}` arguments (the `__prim_*`/`Show`
  layer), so no stringification is delegated to Rust's `Display`.
- **The stringify intrinsics.** `__prim_int_to_string` and `__prim_char_to_string`
  lower natively on all four emitters (int: `erlang:integer_to_binary` / `String(n)`
  / `n.to_string()` / `.toString()`; char: `<<cp/utf8>>` / `String.fromCodePoint` /
  `char::to_string` / `String(Character.toChars(_))`), so an
  `Int53`/`Bool`/`String`/`Char` interpolation reaches **all four targets**,
  byte-identical — the portability win, replacing the `:ex`-only `Integer.to_string`
  FFI. `Rian.Reach` needs no new blocker: a hole inherits its value type's reach (an
  `Int` hole is `[:ex,:js]` per ADR-0064; a wide-int hole is off `:js`).
- **`Float64` (resolved):** a `Float64` hole resolves to the auto-injected portable
  `Show.float` (ECMA-262 §7.1.12.1; §6, *Implementation*) — byte-identical on **all four
  targets, every double** (the JVM searches for the shortest round-trip repr, so even the
  denormal extremes match; see below). A **`Float32`** hole (no portable
  formatter) and a hole whose type can't be statically inferred still raise a clear
  error at the hole — no `inspect`-style fallback (ADR-0035).
- **User `Show` (resolved):** a hole whose static type `T` has an `impl Show for T`
  lowers to `show(value)` — statically resolved (the type fixes `T`), routed by the
  program's `Show` dispatcher; it reaches as far as the impl does. A user type with no
  impl stays the "no `Show`" error. **Derived** `Show` (auto-generating the impl)
  remains a separate decision (Open items) — it reopens the stable-contract question.

## Open items

- ~~**Confirm A (`\(expr)`) vs B (`${expr}`).**~~ **Resolved (2026-06-14): B (`${expr}`)** — familiarity for Rian's JS/Kotlin targets and the broad audience won over A's smaller lexer delta (§1).
- ~~**The `Char`/`Int53` dispatch-guard collision on `:ex`/`:js`.**~~ **Resolved (2026-06-14).** The
  collision only exists for *runtime* `Show` dispatch; the implemented design resolves each hole by its
  **static** type (§"Static resolution"), so a `Char` hole emits `__prim_char_to_string` directly with
  no `is_integer` guard in play. The prim lowers natively on every target (BEAM `<<cp/utf8>>`, Rust
  `char::to_string`, JS `String.fromCodePoint`, Kotlin `String(Character.toChars(_))`) and is
  byte-identical (rustc/node/kotlinc-verified, incl. supplementary codepoints). Runtime `Char` dispatch
  remains open *only* for the (deferred) user-`Show`/runtime-dispatch path.
- ~~**`Float64` round-trip divergence.**~~ **Resolved (2026-06-15).** BEAM, JS `String(n)`, and Rust
  `format!("{}", …)` diverge on *presentation*, but the shortest-round-trip **digits are mathematically
  unique** — so a single portable normalizer (`Show.float`, ECMAScript `Number::toString` as the
  reference) over each target's native repr is byte-identical (`show_float_test.exs`). It is auto-injected
  into a `${float}` hole (§6, *Implementation*) and reaches all four targets.
- ~~**JVM denormal-extreme divergence.**~~ **Resolved (2026-06-15) — no caveat.** The portability rests
  on `__prim_float_repr` returning the *shortest* round-trip decimal. BEAM/Rust/JS get that from their
  native formatter; Java's `Double.toString` is JLS-pinned to a **non-shortest** form for the tiniest
  denormals (`4.9E-324` where ECMAScript emits `5e-324`), so the JVM `__prim_float_repr` does **not**
  trust `toString` — it searches for the shortest significant-digit count whose `%e`-rounded value parses
  back to `x` exactly (`Rian.JVM.float_repr_helper/0`, injected only when the prim is used). That is the
  true shortest by construction, so it matches ECMAScript on **every** double — verified over the full
  conformance corpus (denormals included) and a 120k-double fuzz (zero digit divergences). `Reach` reports
  `:jvm` and the matrix is now honest with no asterisk.
- **Derived `Show`.** Auto-deriving `Show` for sums/structs (field-by-field) is the obvious ergonomics
  follow-up but a separate decision — it reopens the "is the derived output a *stable contract*?"
  question and risks an `inspect`-by-the-back-door. Spike only; commit nothing here.
- **Pure-sugar fallback.** If portable `Show` proves too costly (the float/coherence items above), fall
  back to the *Alternatives* design — interpolation over `String`-typed holes only — which needs none
  of §3/§4 and ships immediately. Keep it on the table until §3 is proven.

## Alternatives considered

- **Pure-sugar, `String`-only interpolation (the other direction).** `${e}` requires `typeof(e) ==
  String`; desugars to a bare `<>` chain with no `show`. Pros: zero new protocol, zero new prim, fully
  portable on day one, no ADR-0035 tension (it hides only `<>`, already an operator). Cons: solves
  *none* of the formatting-FFI portability problem — you still write `Int.to_string(n)` by hand, and
  that call is still `:ex`-only until a portable `Show` exists. It is a strictly smaller feature that
  postpones the real work. **Recorded as the fallback (Open items), not the recommendation.**
- **`inspect`-style reflective stringification** (stringify *anything*, no `Show` impl needed). Rejected:
  it has no portable, stable cross-target output contract, and it is exactly the "magic" ADR-0035 and
  the explicit-by-design philosophy exist to prevent. A type with no `Show` impl is an error, full stop.
- **`#{expr}` (Elixir-native).** Rejected for overloading the `#` comment sigil (shootout row C).
