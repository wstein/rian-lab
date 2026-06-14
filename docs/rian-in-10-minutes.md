# Rian in 10 minutes

A fast tour of the surface for someone who already programs. For the *why*, see the
[charter (ADR-0000)](adr/0000-charter.md); for the full annotated walkthrough, the
[by-example tour](../examples/rian/README.md).

> **The one idea to keep in mind:** Rian is *one source* that lowers to the **BEAM, JavaScript, Rust,
> and the JVM**. You write typed **sequential** logic once; concurrency is native-per-target (you call
> the logic from a native process/task/worker), and the compiler **infers** which targets each function
> can reach — you don't annotate portability.

## Expressions, bindings, blocks

Everything is an expression that yields a value — `if`, `case`, and blocks included.

```rian
def add(x Int53, y Int53) Int53 := x + y      # one-clause fn: the typed head IS the signature

def double_inc(n Int53) Int53                  # block body opens after the return type, closes `end`
  d := n * 2                                   # `:=` is single-assignment binding (never mutation)
  d + 1                                        # the LAST expression is the value (implicit return)
end

def sign(n Int53) Int53 := if n >= 0 do 1 else -1 end   # value-position `if` REQUIRES `else`
```

`:=` is single-assignment; reusing a name **shadows** (a fresh value), it does not mutate. Mutation is a
different, capability-gated operator (`<~`).

## Types and pattern matching

Sum types, structs, and exhaustive `case`:

```rian
type Shape := Circle(radius Float64) | Square(side Float64)   # sum type (tagged variants)
struct Point(x Int64, y Int64)                                 # product type (record)

def area(s Shape) Float64
  case s do
    Circle(r) -> 3.14159 * r * r
    Square(w) -> w * w
  end
end
```

Exhaustiveness is a **gate**: a non-exhaustive `case` (or set of clauses) refuses to compile.

## Multi-clause functions and guards

A function can be several clauses; the head repeats, patterns and `when` guards select:

```rian
def fib(n Int64) Int64
def fib(0) := 0
def fib(1) := 1
def fib(n) when n > 1 := fib(n - 1) + fib(n - 2)
```

## Capabilities (the one annotation that's distinctive)

Each parameter carries a **memory capability** ([ADR-0025](adr/0025-memory-capabilities.md)) — `val`
(shared/read-only, the common case), `iso` (owned/linear, use-once), `ref` (`&mut`, BEAM-illegal),
`tag`. *One* annotation gives ownership-checked Rust **and** BEAM use-once linearity, with no
hand-written lifetimes:

```rian
def sum(xs val Vec(Int64)) Int64 := ...        # &[i64] on Rust, reusable on the BEAM
def take(buf iso Vec(Byte)) Vec(Byte) := ...   # owned/moved on Rust, use-once-checked on the BEAM
```

*(Proposed — [ADR-0070](adr/0070-default-val-capability.md): `val` becomes the inferred default, so a
bare `xs Vec(Int64)` means `val` and only `iso`/`ref`/`tag` need spelling.)*

## Errors are values

`Result`-shaped errors with a **typed error set** at the boundary ([ADR-0040](adr/0040-error-handling.md)).
Compose with `with`, or propagate with a bare `<-` ([ADR-0066](adr/0066-error-propagation-sugar.md)):

```rian
def parse_add(a String, b String) Int64 | ParseError
  x <- to_int(a)        # `<-` binds the ok value, or returns the error (early, but VISIBLE)
  y <- to_int(b)
  {:ok, x + y}
end
```

There is **no nil** — absence is `Option` ([ADR-0047](adr/0047-portable-prelude-stdlib.md)).

## Modules, visibility, collections, pipes

```rian
mod Geometry do
  pub def area(s Shape) Float64 := ...   # `pub` exports; unmarked is module-private
  const Pi Float64 := 3.14159
end

xs |> map(double) |> sum                 # `|>` pipes left-to-right
"hello" <> " " <> name                   # `<>` concatenates strings
[h | t]   %{key: value}                  # cons list / map literals; lambdas: (x) -> x + 1
```

## Compile-time

- `comptime(expr)` folds a constant expression to a literal (a pure sandbox).
- `macro name(params) := template` — declarative, hygienic pattern→template macros (no `quote`/`unquote`).
  ([ADR-0030](adr/0030-macros.md); derivation is moving to comptime, not AST macros.)

## The multi-target model (what makes it Rian)

- **Portability is inferred.** `Rian.Reach` computes each function's reachable target set; a host-FFI
  call or a target-specific type *narrows* it, honestly. You never write `@shared`
  ([ADR-0058](adr/0058-configurable-target-environments.md)).
- **Need a per-target host body?** `@external(:ex, "…")` / `@external(:js, "…")` declares one per target
  ([ADR-0068](adr/0068-external-target-bodies.md)) — the only place target-conditionality is allowed,
  and Reach reads it.
- **Concurrency is native-per-target** — OTP on the BEAM, async on Rust, Promises on JS. It is *not* a
  Rian surface ([ADR-0057](adr/0057-concurrency-and-otp-are-native-per-target.md)).
- **Numbers:** `Int` is arbitrary-precision (the default); `Int53` is the portable all-target fixed
  width; wider fixed widths are off some targets ([ADR-0064](adr/0064-portable-numeric-contract.md)).

## Where to go next

The [by-example tour](../examples/rian/README.md) (`examples/rian/01_basics.rian` … `09_capstone_calc.rian`)
walks every feature with runnable code, and [the design corpus](README.md) (ADRs) explains every
decision. Status of what's actually built: the [Status at a glance](README.md) table.
