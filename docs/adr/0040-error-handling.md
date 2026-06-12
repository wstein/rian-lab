# ADR-0040 — Error handling: `Result(T, E)`, the `T | E` return sugar, `with` propagation, error-set composition

**Status:** Accepted (direction) · **Depends on:** ADR-0039 (`<-` failable-bind) · **Implements:** ADR-0034 §2
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

### 2. `Result(T, E)` and the `T | E` return sugar

A fallible function returns `Result(T, E)`. Surface sugar in **return position**:

```elixir
def find(id Int64) User | NotFound          # = Result(User, NotFound)
def lookup(id Int64) User | LookupError      # error set may be named
```

| Rule | Decision |
|---|---|
| `\|` in **return position** | sugar for `Result(ok, error)`: first operand is the ok-type, the remainder the error set |
| `\|` elsewhere | **not** general union syntax (consistent with ADR-0034 nominal-sums-canonical) |
| inline multi-tag error | must be a **named** error set (`User \| LookupError`), not `User \| NotFound \| Timeout` — keeps the sugar unambiguous |
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

## Resolved (decision-lock 2026-06-12)

- **`pub` error-set strictness → ⊆ declared.** Over-declaration is allowed: a public API may reserve
  future error tags ahead of producing them (forward-compatible). (§4.)
- **Error value surface shape → tagged tuples** `{:ok, v}` / `{:error, tag}` (family-canonical;
  lowers 1:1 to BEAM `with`, and to `Result<T, E>` on Rust). `Ok(v)` / `Err(e)` constructors were
  considered and rejected as a family divergence.
- **`with` with no `else` propagates unchanged; `else` must be exhaustive over what it handles.** (§3.)
- **`for`-comprehensions deferred** to their own ADR; they share the `<-` arrow (ADR-0039).

## Open items

- **`with` guard clauses** — Elixir allows bare boolean expressions and `when` inside `with`; include
  in v1 or defer?
- **Anonymous inline error sets** — relax §2's "must be named" once the checker can synthesize and
  name an anonymous union safely.
- **`for`-comprehensions** — share the `<-` arrow (ADR-0039); their full syntax is a separate ADR.
