# Effective Rian

Tips for writing clear, idiomatic Rian. This guide **augments the ADRs and the
specs — read those first**; the ADRs define what is *legal*, this guide
describes what is *idiomatic*. Where the two disagree, the ADR wins (and this
guide is a bug to fix).

It is modelled on Go's *Effective Go*: formatting is a solved problem the
machine handles, so the interesting material is everything above formatting —
naming, control flow, errors, capabilities, and the design judgment of *which
construct to reach for*. A straightforward transliteration of an Elixir or Rust
program into Rian is unlikely to read well; the goal here is to think about a
problem *from a Rian perspective*.

**Five idioms carry most of the language. Internalize these and the rest
follows:**

> 1. **Errors are values** — return them, don't raise them.
> 2. **No hidden control flow** — if it allocates, branches, or fails, you can see it.
> 3. **Capabilities are inferred; you annotate the exception.**
> 4. **Shadow with `:=`, mutate with `<~`** — and reach for the second rarely.
> 5. **Prove portability, don't assert it.**

**The standard library is the style guide that runs.** When a convention here is
ambiguous, read the annotated tour in [examples/rian/](../examples/rian/) and the
`prelude_*.rian` sources — they are written to be exemplary, and they compile.
Match them.

**Run this before every commit** — it owns all whitespace, so you never argue
about it:

```sh
mix rian.format FILE…            # canonical formatter (98-col, 2-space, zero-config)
mix rian.format FILE… --check    # CI gate
rian fmt FILE…                   # toolchain-free escript equivalent
```

---

## 1. Formatting (solved — ADR-0045)

Like Go, Rian takes formatting off the table: there are **no options**. The
formatter re-derives every byte of whitespace, so the only rule you need is *run
it*. If your code looks different afterward, the formatter is right. Knowing the
rules below just lets you write code that survives it unchanged.

| Rule | Value |
| --- | --- |
| **Line width** | wrap at **98 columns** |
| **Indentation** | **2 spaces** per level; never tabs |
| **Blank lines** | at most **one**; none leading/trailing; file ends in one `\n` |
| **Trailing comment gap** | exactly **two spaces** before `#` |

Spacing is mechanical: one space around binary operators and after `,`/`;`; none
just inside brackets (`f(x)`, `[1, 2]`, `%{a: 1}`), none around `.`, none after
unary `-`/`not`; colons hug their key (`host: 8080`, `:lists`).

A bracketed group collapses to one line when it fits, else breaks **one item per
line**. Declaration heads (`def` params, `when` guards) **never reflow** — a head
too long to fit is a design smell (see §15), not a wrap. Operator chains break
**leading-operator, one stage per line** at the loosest precedence:

```rian
def pipeline(xs Vec(Int53)) Vec(Int53) := xs
  |> List.map((x) -> x * 2)
  |> List.filter((x) -> x > 0)
  |> List.reverse()
```

A **trailing comma** before a closer pins a group vertical on purpose; drop it to
let the formatter collapse:

```rian
def stays_vertical() := %{
  host: "localhost",
  port: 8080,
}                       # trailing comma after 8080 keeps this multiline
```

---

## 2. Commentary

Comments start with `#`; doc attributes (`@doc`, `@moduledoc`, `@typedoc`) carry
**Markdown** and precede the declaration they document. The formatter keeps
comments verbatim — so their *quality* is entirely on you.

A good doc comment is worth more than a long name. Lead with a verb describing
what the function does, state the contract and the errors it can return, and
**prefer a doctest to prose** — a `expr #=> result` line cannot drift, because a
drifted example fails the build (ADR-0060 tier B):

```rian
@doc """
Divide `a` by `b`, returning `DivByZero` rather than trapping.

    checked_div(6, 2) #=> {:ok, 3}
    checked_div(1, 0) #=> {:error, DivByZero}
"""
pub def checked_div(a Int53, b Int53) Int53 | DivError
```

Don't restate the obvious. A comment should explain *why*, or a non-obvious
contract — not narrate what the code already says:

```rian
i <~ i + 1     # BAD: increment i — the code says that
i <~ i + 1     # GOOD (when true): skip the sentinel row; row 0 is the header
```

Use an own-line `#` block to open a file or module with its *character* and the
ADR it follows — the tour files are the model (`# Spec: docs/spec/expressions.md`).

---

## 3. Names

Naming is a semantic decision, not a cosmetic one — the case of a name changes
what it *means* to the parser (a lowercase head is a value or field; a PascalCase
head is a type, module, or variant). Get the case right first; then optimize for
the reader.

| Kind | Case | Examples |
| --- | --- | --- |
| values, functions, params, bindings | `snake_case` | `count`, `loud_greeting` |
| types, constructors, modules, structs, variants | `PascalCase` | `Int64`, `User`, `Some` |
| type variables (in `forall`) | `PascalCase`, short | `T`, `U`, `K`, `V` |
| the implementing type inside `impl` | `Self` | `def compare(a Self, b Self)` |

Beyond case, the conventions that make Rian read well (family idiom from
Elixir/Crystal — not parser-enforced, but expected):

- **Length tracks scope.** A loop or one-liner binding is `x`, `n`, `acc`; a
  module-level function earns a descriptive name. Long names don't make code more
  readable — a good doc comment usually beats an extra word.
- **`?` is a contract, not decoration.** A trailing `?` means *returns `Bool`*
  (`empty?`, `valid?`). Don't name a non-predicate with `?`. `!` marks a stricter
  or effecting variant (`gate!`). (ADR-0033 reserves `?` for predicates — it is
  **never** error-propagation, unlike Elixir/Ruby instinct.)
- **Don't stutter.** Inside `mod Dict`, name the function `get`, not `dict_get` —
  callers already write `Dict.get`. The qualifier carries the namespace.
- **Name a getter for the noun**, not the verb: `point.x` and `User.name(u)`,
  not `get_x` / `get_name`. Reserve `get` for fallible lookups returning
  `Option` (`Dict.get`).

```rian
def getUserName(u User) String := u.name   # BAD: camelCase + get-prefix + stutter
def name(u User) String := u.name          # GOOD: snake_case, noun, no stutter
```

---

## 4. Control structures

Rian's control flow is deliberately small and **everything is an expression** —
`if`, `case`, and blocks all yield a value, so they compose into other
expressions and lower cleanly to Rust (`if`/`match`) and Elixir alike. The cost
of that uniformity is a few hard rules the checker enforces.

**`if` in value position requires `else`** — both arms must have a type, because
an `else`-less `if` is a unit-typed *effect*, legal only as a statement:

```rian
x := if cond do a end            # BAD: no else → unit in value position → error
x := if cond do a else b end     # GOOD
```

**`case` arms use `->` and must be exhaustive.** On a sealed sum, cover every
variant and stop — *don't* add a `_ ->` that silently swallows a variant you
later add. On an **open** type (`Int53`, `String`, `Symbol`) a `_ ->` catch-all
is required:

```rian
case b do
  0 -> {:error, DivByZero}
  _ -> {:ok, a div b}
end
```

**The last line of a block is an expression, never a binding** (ADR-0035 §6) — a
trailing `:=` has no value to return:

```rian
def f(x Int53) Int53           # BAD: block ends on a binding
  y := x * 2
end
def f(x Int53) Int53           # GOOD: ends on the value
  y := x * 2
  y
end
```

**Guards are a restricted, pure, total sublanguage** (comparisons, arithmetic,
`in`, `is_*`/`len`/`abs`) so they stay portable — don't try to call an arbitrary
function in a `when`. Guarded clauses **don't count** toward exhaustiveness, so a
guard-only function needs an unguarded backstop:

```rian
def max2(Int53, Int53) Int53
def max2(a, b) when a >= b := a
def max2(a, b)             := b     # the unguarded fallback makes it total
```

**Partiality is opt-in and never silent.** Reach for `@partial` rarely — it's an
admission the function can fail to match. Prefer returning `Option`/`Result`:

```rian
def head(Vec(T)) T               # WRONG: missing the empty case → compile error
def head(Vec(T)) Option(T)       # RIGHT: model absence in the type
def head([]) := None
def head([h | _]) := Some(h)
```

---

## 5. Functions

A function is `def name(params) Ret …`. Types are **juxtaposed — no `:`**
(`def add(x Int53, y Int53) Int53`), and there is **no `return` keyword**: a
body's value is its final expression.

Pick the body form by size. Prefer the **one-liner** for a single expression;
switch to a **block** the moment you need an intermediate binding:

```rian
def add(x Int53, y Int53) Int53 := x + y      # one-liner — the typed head IS the boundary

def double_then_inc(n Int53) Int53            # block — last expression is the value
  d := n * 2
  d + 1
end

(x) -> x * 2                                  # lambda — anonymous, single-expression
```

**Multi-clause functions** are a bodiless signature line followed by
**contiguous** pattern-head clauses; first match wins, top to bottom. Keep them
contiguous (Elixir and the BEAM emitter require same-name/arity clauses grouped)
and let the formatter align the `:=`:

```rian
def classify(Int53) String
def classify(0)            := "zero"
def classify(n) when n > 0 := "positive"
def classify(_)            := "negative"
```

Thread data left-to-right with `|>` — `x |> f(y)` *is* `f(x, y)`. There is **no
method-call syntax**; `x.f` accesses a field, so to call write `f(x)` or
`x |> f`:

```rian
String.upcase(greet(name))          # OK, but reads inside-out
name |> greet |> String.upcase      # idiomatic: left-to-right
```

---

## 6. Errors are values

> **Errors are values. Return them, don't raise them.**

There are no exceptions in the portable core (ADR-0035, ADR-0040). A fallible
function returns `Result(T, E)` where `E` is a **sealed error set** — an ordinary
`type` sum of tags. The `T | E` return sugar spells it:

```rian
type DivError := DivByZero | Overflow            # an error set is just a sealed sum

pub def checked_div(a Int53, b Int53) Int53 | DivError    # `T | E` == Result(T, E)
  case b do
    0 -> {:error, DivByZero}
    _ -> {:ok, a div b}
  end
end
```

Coming from a language with exceptions, the instinct is to fail loudly and catch
later. In Rian you thread the happy path with **`with`**; each `<-` binds on
success or short-circuits on the first error. Omit `else` to let the error
propagate unchanged:

```rian
# BAD instinct — there is no try/catch, and `?` is NOT propagation in Rian (§3)
# GOOD — `with` is the per-call `?` generalized to a block:
pub def ratio(a Int53, b Int53, c Int53) Int53 | DivError
  with {:ok, x} <- checked_div(a, b),
       {:ok, y} <- checked_div(x, c) do
    {:ok, y}
  else
    {:error, e} -> {:error, e}
  end
end
```

Conventions: **name multi-tag error sets** (`User | LookupError`, not
`User | NotFound | Timeout` inline); **public** functions declare their error set
(checked against the body), **private** ones infer it (don't annotate). Reserve
`Prim.panic` for genuine invariant violations — never for control flow.

---

## 7. Data: choosing the right type

Rian gives you three type-definition forms and two ways to model "this or that."
Choosing well is most of good Rian design.

```rian
type Color := Red | Green | Blue            # sealed sum (ADT) — a closed set of shapes
struct Point(x Float64, y Float64)          # product / record — fixed named fields
alias Id := Int64                           # transparent synonym — zero new semantics
```

**Which to reach for:**

- **`struct`** when a value always has the *same* fields — a record. `Point`,
  `Config`, `Request`.
- **`type … | …`** (sealed sum) when a value is *one of several shapes* —
  `Color`, an AST node, a wire message. This is the default for "or," and a
  `case` over it is checked exhaustive, so adding a variant flushes out every
  site that must handle it. Prefer it over a struct with a `kind` tag.
- **`alias`** only to name a primitive for readability (`Id := Int64`); it adds
  no checking. If you want a *distinct* type the compiler keeps separate, you
  want an opaque type, not an alias.

**Model absence with `Option`, never `nil`** — there is no `nil` (ADR-0047). And
prefer encoding failure in the return type over `@partial`:

```rian
def find(d Dict(K, V), k K) V          # BAD: what if it's missing? @partial trap
def find(d Dict(K, V), k K) Option(V)  # GOOD: the absence is in the type
```

`T | E` in return position is the *Result* sugar (§6) — it is **not** a general
union type. Sums are sealed and nominal; there is no structural union.

A **reserved keyword may label a field** in unambiguous positions
(`Field(type: t)`, `%{case: c}`), so you needn't rename a natural field.

---

## 8. Capabilities and mutation

> **Capabilities are inferred; you annotate the exception.**

Every parameter has a memory capability that drives Rust ownership and BEAM
linearity (ADR-0025) — but **`val` (shared, read-only) is the default and is
inferred**, so the idiomatic signature writes *nothing*:

```rian
def area(s Shape) Float64 := …        # GOOD: `val` is implicit
def area(s val Shape) Float64 := …    # noisy: don't spell the default
```

Annotate only the exception:

| Cap | Meaning | Reach for it when |
| --- | --- | --- |
| `val` | shared read-only borrow (**default**) | the common case — leave it off |
| `iso` | owned, **linear / use-once** | you hand off ownership, or mutate-then-return |
| `tag` | shared by-reference, identity only | protocol-dispatch receivers |
| `ref` | mutable `&mut` | **last resort** — see below |

**`ref` is BEAM-illegal** and pins the function off `:ex` (ADR-0025 P5). When you
need mutation, prefer `iso` + rebind — it stays portable, where `ref` does not:

```rian
def push(xs ref Vec(T), x T) Unit      # BAD for portable code: &mut → off :ex
def push(xs iso Vec(T), x T) Vec(T)    # GOOD: own it, return the new value
```

**Shadow with `:=`, mutate with `<~`.** Re-using a name with `:=` binds a *fresh*
value (the old one is untouched); `<~` is a capability-gated statement that
actually mutates and yields unit (so it can't sit in value position). Default to
`:=` shadowing — reach for `<~` only when you genuinely need in-place update:

```rian
x := n + 1
x := x * 10     # shadow: a NEW x; nothing mutated
total <~ expr   # mutation: capability-gated, BEAM-illegal unless local
```

---

## 9. Numbers

Integer width is a portability decision, so make it deliberately. A bare literal
infers the portable **`Int53`** (JS `number`, `i64` elsewhere) — the right
default for cross-target code. `Int` is arbitrary-precision but reaches only
`[:ex, :js]`; fixed-width `Int8…Int128`/`UInt*` are for bit-exact or all-target
work, pinned at the binding (`n Int32 := 66`). On JS, only `Int`, `Int53`, and
`Int32`-and-narrower are valid — wider types are rejected, never silently
widened.

No silent coercion, ever:

```rian
x Float64 := 66        # BAD: int literal into a float type → error
x Float64 := 66.0      # GOOD
avg := total / count   # `/` is FLOAT division; use `div` for integer division
```

Overflow of fixed-width types is **explicit** — call `Int.wrapping_add` /
`checked_add` (→ `Option`) / `saturating_add` rather than relying on a target's
native behavior. When a bound is known, prefer a subrange type
(`type Digit := 0..9`, ADR-0036) over a wide integer.

---

## 10. Protocols and generics

Polymorphism in Rian is explicit. Type variables are introduced with `forall`,
and bounds attach to the `forall`, **not** to `when` (which is for value guards):

```rian
def sort(xs Vec(T)) Vec(T) forall T: Comparable
def lookup(d Dict(K, V), k K) Option(V) forall K: Eq
```

Function types are `Fn(Arg1, …, ArgN, Return)` — last element is the return, no
arrow. A `protocol` lists **signatures only** (no bodies); receivers default to
`val`. One `impl` per `(protocol, type)` pair — the orphan rule — placed in the
module owning the protocol or the type.

**Default to static dispatch**; it monomorphizes and stays portable. Declare a
`Protocol`-typed binding only when you genuinely need runtime dispatch over an
open set — dynamic dispatch by a constructor tag pins a consumer off `:rs`/`:jvm`
(ADR-0061), so it's a portability cost, not just a style choice.

---

## 11. Comprehensions

Eager and list-producing (ADR-0079). A generator binds a full pattern — a
non-match **skips** the element silently, which is the idiomatic way to filter
*and* destructure at once; filters are boolean expressions between generators:

```rian
for {:ok, v} <- results, v > 5 do v * 2 end     # keeps only oks > 5, unwrapped
```

There is no `into:`/`reduce:` — use `List.reduce` / `List.fold` explicitly.

---

## 12. Concurrency is native, not portable

Where *Effective Go* devotes its centerpiece to goroutines and channels, Rian
makes the opposite design statement, and it is a load-bearing idiom: **there is
no portable concurrency surface.** Concurrency and OTP are native *per target*
(ADR-0057) — a BEAM program uses processes and `GenServer`, a JS program uses its
event loop, a Rust program uses its own runtime. Rian's portable core is
**sequential logic** you share across targets; the concurrent shell is written in
each target's idiom and *calls into* that shared core.

Practically: don't look for a Rian `spawn`/`channel`/`async`. If your code is
concurrent, that part lives in the host (and pins to `:ex` like any FFI, §13);
keep the portable logic it orchestrates pure and target-agnostic. Likewise
laziness is a per-target evaluation concern — the prelude reducers are eager by
design.

---

## 13. Portability

> **Prove portability, don't assert it.**

Portability is **inferred, not annotated** (ADR-0058): a function is portable iff
it reaches every target it claims. Keep portable code in the portable core
(`val`/`iso`/`tag`, `Int53`/fixed-width, no host FFI). Host FFI and all
concurrency pin a function to `:ex` *by design*. Declare a module's contract with
`@targets(ex, rs, js)` and let `mix rian.targets` gate it — a function reaching
only `[:rs, :js]` is a *compile error* for a BEAM consumer, by design: the matrix
is honest, not aspirational.

Qualification is the universal `.`, disambiguated by case (ADR-0029);
`::` is not Rian syntax:

```rian
Geometry.area(x)     # Rian module function   (Pascal head, lowercase name)
Value.Num(n)         # variant / type path     (Pascal head, Pascal name)
point.x              # field access            (lowercase head)
:lists.sum(xs)       # Erlang FFI              (atom head) — pins to :ex
String.upcase(s)     # Elixir-module FFI       (Pascal head)
```

The **prelude is unqualified** (`Int64`, `Result`, `Option`, `Vec`, operators,
core protocols); **everything else is qualified** (`List.map`, `Dict.get`). No
wildcard imports. And **never write `Prim.*`** — it's the reserved intrinsic
namespace; use the `Str`/`Char`/`Dict` wrappers.

---

## 14. Tests and docs

Tests are functions annotated **`@test`**, returning `Bool` or
`Outcome := Pass | Fail(String)`. True to §6, **assertions are values, not
exceptions**:

```rian
@test def divides_evenly() := expect_eq(checked_div(6, 2), {:ok, 3})
```

Use the `expect_*` matchers (`expect_eq`/`expect_neq`/`expect_true`/
`expect_false`) when you want a named diagnostic on failure
(`Fail("expected 42, got 41")`); use plain `assert`/`refute` (→ `Bool`) when you
don't. For documentation that cannot drift, prefer doctests (§2) over prose
examples.

---

## 15. Lint smells (ADR-0077, advisory)

The linter flags these; fix them rather than suppress:

- over-long `def` heads (heads never wrap — a long one is a design smell);
- naming-convention violations (§3); a `pub` declaration missing a declared type;
- unused or shadowing bindings (`--fix` prefixes with `_`);
- `if`/`case`/`with` nested past depth **4** — extract a helper;
- residual `TODO_PORT(…)` / `_Unk` markers in non-draft source;
- a function pinned off a Tier-1 target by FFI where portability was plausible.

---

### The whole thing in a breath

Run `mix rian.format`. Name values `snake_case`, types `PascalCase`, and keep
names short where scope is small. Default to one-liner bodies; make the last line
of a block an expression; keep multi-clause groups contiguous. **Errors are
values** — return `Result`/`T | E` and thread with `with`, never exceptions or
`?`. Reach for a sealed sum over a tagged struct, `Option` over `@partial`, and
`nil` never. **Capabilities are inferred** — annotate only `iso`/`ref`/`tag`;
shadow with `:=`, mutate with `<~` rarely. Default integers to `Int53`, coerce
nothing silently, make overflow explicit. Concurrency is native per target, not a
Rian surface. **Prove portability, don't assert it.** When unsure, read
[examples/rian/](../examples/rian/) — it's the style guide that compiles. The
ADRs are the law; this is their idiom.
