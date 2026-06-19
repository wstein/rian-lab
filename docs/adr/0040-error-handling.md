# ADR-0040 — Error handling: `Result(T, E)`, the `T | E` return sugar, `with` propagation, error-set composition

**Status:** Accepted (direction) · **Depends on:** ADR-0039 (`<-` failable-bind) · **Implements:** ADR-0034 §2
**Implemented:** partial — `Result`/`T | E` return sugar and `with` (`EWith`) parse, check, and lower to the BEAM (`Rian.Check`, `Rian.Core`, `Rian.Beam`; `test/rian/check_test.exs`); full error-set composition/Rust+JS lowering not exhaustively covered
**Refs:** ADR-0032 (family; `?` reserved for predicates), ADR-0033 (vocabulary), ADR-0034 §1/§2 (inference, error sets), ADR-0035 (errors are values; no hidden control flow), ADR-0036/0037 (existing error sets), ADR-0026 (precise `-spec`)
**Owners:** Arthur Pendelton (inference/composition) · Elena Rostova (Rust lowering) · Chloe Bennett (parser) · Samir Patel (exhaustiveness) · Rachel Okafor (PM)

## Context

ADR-0034 §2 fixed errors-as-values over **typed error sets** and said the propagation-form question
was "now answerable" — meaning the foundation (a typed error set to propagate) now exists, *not*
that the form was decided. This ADR decides it. The removed `?` (ADR-0032, reserved for predicates)
is replaced by the **family `with`-form**, not a propagation operator. The foundation is already in
use: `RangeError` (ADR-0036) and `DecodeError` (ADR-0037) are sealed error sets today.

## Decision

### 1. An error set is a sealed sum in error position — no new type former

An error set is an ordinary `type` (sealed nominal sum, ADR-0034 Debate-1 outcome) whose variants
are error tags — 0-arity or constructor-with-payload:

```elixir
type LookupError = NotFound | Timeout
type DecodeError = Truncated(needed Int64, got Int64) | TrailingBytes(extra Int64)
```

### 2. `Result(T, E)` — explicit (the `T | E` return sugar was **removed**, ADR-0083)

A fallible function returns `Result(T, E)` **explicitly**:

```elixir
def find(id Int64) Result(User, NotFound)        # ok-type, then the error set
def lookup(id Int64) Result(User, LookupError)   # error set may be named
```

> **Superseded.** This ADR originally introduced a return-position **`T | E` sugar**
> for `Result(T, E)`. **ADR-0083 removed it:** `|` is now a *value union* in **every**
> position (Crystal-style), so a fallible return is spelled `Result(T, E)`. The Result
> *model* below is unchanged — only the `|` shorthand is gone.

| Rule | Decision |
|---|---|
| fallible return | written **explicitly** as `Result(ok, error)` — first arg the ok-type, second the error set |
| `\|` in a type | a **value union** (ADR-0083), in every position — never `Result` sugar |
| inline multi-tag | a value union `User \| NotFound \| Timeout` is now *legal* (it's a union, not an error set); a `Result` error set stays a **named** sealed sum |
| lowering | BEAM `{:ok, v}` / `{:error, tag}` tagged tuples; Rust `Result<T, E>` |

### 3. Propagation = `with` (Elixir) — the `?` successor

```elixir
def transfer(from Account, to Account, amt Money) Receipt | TransferError
  with {:ok, debited}  <- withdraw(from, amt),
       {:ok, credited} <- deposit(to, amt) do
    receipt(debited, credited)
  else
    {:error, e} -> compensate(from, e)
  end
end
```

- Each `pattern <- expr` (ADR-0039 failable-bind): match the ok-pattern → bind + continue; otherwise
  **short-circuit** to the error value.
- **No `else`** ⇒ an unmatched error **propagates unchanged** (this is the per-expression `f()?`
  generalized to a happy-path block).
- **`else`** handles / converts / recovers; it must be **exhaustive over the errors it claims to
  handle** (the Maranget engine already in the repo checks this).

### 4. Error-set composition (resolves the ADR-0034 §2 open item)

Mirrors the ADR-0034 §1 infer-local / declare-public line:

- **Private functions / `:=`: inferred.** `E` = the union of the error-sets of the propagated callee
  expressions, minus errors exhaustively handled in an `else`. No annotation; a body edit can't change
  a caller because there is no exported inferred error type.
- **`pub` functions: declared.** The error set is explicit in the signature; the checker verifies the
  body's inferred set is **⊆** the declared set (decided 2026-06-12 — over-declaration is allowed, so
  a public API may reserve future error tags ahead of producing them; forward-compatible). Preserves
  precise `-spec` emission (ADR-0026).

### 5. Lowering — same source, two idiomatic shapes

| | BEAM | Rust |
|---|---|---|
| `with` | native Elixir `with`/`else` (1:1) | nested `match` with early `return Err(...)` — exactly the `?` expansion |
| `T \| E` | `{:ok, v}` / `{:error, tag}` | `Result<T, E>` |

The Rust target gets `?`-ergonomics **in the emitter** without `?` in the surface — the ADR-0037
"same source, two idiomatic shapes" thesis, applied to control flow.

## Ratings

| Decision | Rating |
|---|---|
| Error set = sealed sum (no new type former) | 5/5 |
| `T \| E` = `Result` sugar, `\|` not general union | 4/5 |
| Propagation form = `with` (by elimination; family-correct) | 5/5 |
| Composition: infer-local / declare-public union | 5/5 |
| `with` lowers BEAM-native / Rust-`?` | 5/5 |
| Require named error set for inline multi-tag | 3/5 (ergonomic cost; revisit with anonymous sets) |

## Consequences

- **ADR-0034 §2 is design-complete.** The `?` successor ships as `with`.
- **Hard dependency on ADR-0039** — `with` cannot be spelled until `<-` is the failable-bind arrow.
- **Parser (Stage 0.1):** `with` / `else` clause parsing; `T | E` desugar in the checker + emitters.
- **Pairs with the existing error sets** (ADR-0036 `RangeError`, ADR-0037 `DecodeError`) — they are
  now first-class citizens of `with`.

## Considered: capability-guarded exceptions (rejected 2026-06-18)

A proposal to add `try`/`catch`/`raise` to Rian, gated behind a capability/effect so the control
flow is "visible," was debated and **rejected**. The deciding arguments:

- **Portability of *semantics*, not syntax (ADR-0050).** All four targets have exception *syntax*,
  but not compatible *semantics*. Rust has no idiomatic catchable exception: `std::panic::catch_unwind`
  requires `UnwindSafe` bounds our generics won't satisfy, and is a hard abort under
  `panic = "abort"` (a standard release profile). A Rian `catch` that works on BEAM/JS/JVM would
  silently *abort the process* on Rust — a runtime-semantics divergence Reach can't paper over.
- **`catch` is exactly the non-local transfer ADR-0035 forbids.** A capability makes the *possibility*
  visible in the signature but not the *flow*; the `raise` site stays invisible at the handler, which
  is the property `<-`/`with` exist to give.
- **A sound `throws E` effect is the error-set fixpoint we already have** (`Check.solve_error_sets`),
  relabelled — more machinery for weaker guarantees than `Result`.

What we adopted instead:

- **`Prim.panic` (uncatchable abort)** — see §1 below and ADR-0035 §1. Portable *because* it has no
  handler (no hidden routing); for invariant violations only.
- **Host-raise is an FFI effect, not a surface exception.** The few genuinely-irreducible boundaries
  (`Code.format_string!`, ad-hoc compilation, file I/O, evaluating arbitrary loaded code) call into
  host runtimes that only raise; converting their raise to a value needs a `try/rescue` *at that
  host boundary*. These are tracked as host/FFI effects (like any non-portable host call) and are
  excluded from the `mix rian.transpile --check` construct gate — they are honest non-portability,
  not a Rian-concept clash.
- **Algebraic effects (ADR-0048)** remain the only principled long-term home if recoverable host
  errors are ever wanted — never the ownership-capability lattice (keep the axes separate).

### `Prim.panic(msg) : T forall T`

The diverging, uncatchable abort (implemented as a `Prim` intrinsic, ADR-0047). Types as `:unknown`
(well-typed in any position, never returns); lowers to `erlang:error` / `panic!` (`!`) / a `throw`
IIFE / Kotlin `throw` (`Nothing`); `Rian.Reach` reports a panicking function as all-target. It is the
honest spelling of a defensive "can't happen," distinct from a `Result` (an *expected* error).

## Resolved (decision-lock 2026-06-12)

- **`pub` error-set strictness → ⊆ declared.** Over-declaration is allowed: a public API may reserve
  future error tags ahead of producing them (forward-compatible). (§4.)
- **Error value surface shape → tagged tuples** `{:ok, v}` / `{:error, tag}` (family-canonical;
  lowers 1:1 to BEAM `with`, and to `Result<T, E>` on Rust). `Ok(v)` / `Err(e)` constructors were
  considered and rejected as a family divergence.
- **`with` with no `else` propagates unchanged; `else` must be exhaustive over what it handles.** (§3.)
- **`for`-comprehensions deferred** to their own ADR; they share the `<-` arrow (ADR-0039).

## Open items

- ~~**`with` guard clauses** — include in v1 or defer?~~ **Resolved 2026-06-12:** v1 `with` supports
  two clause kinds — `pattern <- expr` (failable bind) and `name := expr` (total intermediate bind) —
  plus `do`/`else`. **`when` guards and bare-boolean clauses are deferred** (expressible today via a
  `case` or a `<-` against a boolean-returning expr; adding them later is backward-compatible).
- **Anonymous inline error sets** — relax §2's "must be named" once the checker can synthesize and
  name an anonymous union safely.
- **`for`-comprehensions** — share the `<-` arrow (ADR-0039); their full syntax is a separate ADR.
