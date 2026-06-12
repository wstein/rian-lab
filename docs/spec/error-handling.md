# Spec — Error handling: `Result`, `T | E`, `with` propagation

Normative behaviour for ADR-0040 (errors as values) and ADR-0039 (the `<-`
failable-bind arrow). Errors are ordinary values — there are no exceptions in the
portable core (ADR-0035).

## 1. Error sets

An **error set** is an ordinary sealed sum `type` whose variants are error tags
(0-arity or constructor-with-payload):

```
type LookupError := NotFound | Timeout
type DecodeError := Truncated(needed Int64, got Int64) | TrailingBytes(extra Int64)
```

## 2. `Result` and the `T | E` return sugar

A fallible function returns `Result(T, E)`. In **return position only**, `T | E`
is sugar for `Result(T, E)` — the first operand is the ok-type, the second the
error set:

```
def find(id Int64) User | NotFound        # = Result(User, NotFound)
def lookup(id Int64) User | LookupError    # error set may be named
```

| Form | Rule |
|---|---|
| `\|` in return position | sugar for `Result(ok, error)` |
| `\|` elsewhere | not general union syntax (nominal sums are canonical, ADR-0034) |
| inline multi-tag (`T \| A \| B`) | rejected — the error set must be **named** |

## 3. Value shape and lowering

A result value is a tagged tuple; the `{:ok, v}` / `{:error, tag}` shapes are the
canonical surface (ADR-0040 §"Resolved"). Lowering is "same source, two idiomatic
shapes" (ADR-0041 §3):

| Surface | BEAM | Rust |
|---|---|---|
| `{:ok, v}` | `{:ok, v}` | `Ok(v)` |
| `{:error, tag}` | `{:error, tag}` | `Err(tag)` |
| `T \| E` | (tagged tuple value) | `Result<T, E>` |
| other `{a, b}` | tuple | tuple `(a, b)` |

## 4. `with` propagation

```
with pattern <- expr, … do
  body
else
  error_pattern -> handler
end
```

- Each `pattern <- expr` (the ADR-0039 failable-bind) matches and binds, or
  **short-circuits** on the first non-match.
- **No `else`** ⇒ the non-matching value **propagates unchanged**.
- **`else`** handles/converts; it is matched against the short-circuited value.

| Target | Lowering |
|---|---|
| BEAM | native `with`/`else` (1:1) |
| Rust | right-nested `match`; each clause matches its ok-pattern or falls to the `else` arms / yields the non-matching value — the `?`-expansion |

## 5. Error-set composition (the declared boundary)

A `T | E` return type **declares** the error set `E`. The checker
([`Rian.Check`](../../lib/rian/check.ex)) verifies the set of error tags the body
**constructs** (`{:error, Tag}`) is a **subset** of `E` (over-declaration is
allowed — a public API may reserve future tags). A named `E` expands to its
variant tags. A lowercase binding in error position (`{:error, e}`) is
*re-propagation*, not a newly-constructed tag.

*Not yet implemented:* inferring a private function's error set from the sets of
the callees it propagates (the infer-local half of ADR-0040 §4).
