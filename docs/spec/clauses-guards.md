# Rian Language Specification — Multi-Clause Functions & Guards

**Status:** Locked (PoC) · **Refs:** ADR-0005..ADR-0010 · **Owner:** Julian Vance
**Targets:** Elixir (BEAM, complete) · Rust (idiomatic, superset)
**Scope:** Function-clause grammar, pattern language, guard sublanguage, exhaustiveness,
and the normative lowering to idiomatic Elixir and Rust. The same pattern+guard grammar
governs `match` expressions.

---

## 1. Function forms

A function is either a **single clause** (its head carries the types) or a **multi-clause
group** (a bodiless signature line followed by contiguous pattern-head clauses).

```
# single clause — typed head IS the boundary annotation
fn add(x int, y int) int := x + y

# single clause, block body, implicit return (last expression)
fn norm(v Vec(f64)) f64
  total := v |> sum
  total / len(v)
end

# multi-clause — bodiless signature + pattern clauses
fn classify(int) str
fn classify(0)            := "zero"
fn classify(n) when n > 0 := "positive"
fn classify(_)            := "negative"
```

**Clause grouping rule.** A `fn` head with no body (no `:=`, no block) is a **signature**.
All clauses of a multi-clause function share `name`/arity, are **contiguous**, and follow
the signature immediately. One-token lookahead (`fn` + same name on the next logical line)
distinguishes a signature from a single-clause block body.

**Arity overloading.** Clauses group by `{name, arity}`, not name alone (like Elixir/Erlang):
two heads with the **same name but different arity** (`fn f(x)` and `fn f(x, y)`) are **distinct
functions** — `f/1` and `f/2` — each with its own signature and clauses, exported and reached
independently. The whole compiler keys functions by `{name, arity}`: the checker's
return/generic-signature tables, the error-set fixpoint, the `Rian.Reach` matrix (reported as
`"name/arity"`), the Rust call-site borrow pass, and the per-function compile units. Arity is
counted from the parameter list's depth-0 commas (robust to nested types and `[',' | rest]`
literals).

**Signature param names are optional documentation:** `fn area(s Shape) f64` ≡ `fn area(Shape) f64`.

**A block body ends in an expression, never a binding (ADR-0035).** The implicit return is the
final *expression* (`body = ":=" expr | NEWLINE { stmt } expr "end"`, §2). A block whose last
statement is a binding (`label := "positive"`) is a compile error — a binding has no portable
value (the BEAM returns its RHS; Rust lowers `let x = e;` to `()`, a silent divergence). Make the
value the final line, or use the `:= expr` one-liner. This matches OCaml/Haskell/F#/Rust.

---

## 2. EBNF grammar

```ebnf
function       = single_clause | multi_clause ;

single_clause  = "fn" name "(" typed_params? ")" type body ;

multi_clause   = signature clause { clause } ;
signature      = "fn" name "(" sig_params? ")" type NEWLINE ;
clause         = "fn" name "(" patterns? ")" guard? body ;

typed_params   = typed_param { "," typed_param } ;
typed_param    = name type ;                       (* juxtaposition, no colon *)

sig_params     = sig_param { "," sig_param } ;
sig_param      = [ name ] type ;                   (* optional doc name *)

patterns       = pattern { "," pattern } ;
guard          = "when" guard_expr ;

body           = ":=" expr
               | NEWLINE { stmt } expr "end" ;     (* block: implicit return *)

(* ---- patterns (shared with `match`) ---- *)
pattern        = literal
               | wildcard                          (* "_" *)
               | binding                           (* lowercase name *)
               | as_pattern                        (* name "@" pattern *)
               | pin                               (* "^" expr — match exprs only *)
               | ctor_pattern                      (* Circle(r), Some(x), Ok(v) *)
               | tuple_pattern                     (* "{" patterns? "}" *)
               | list_pattern                      (* "[" ... "]" with cons "|" *)
               | struct_pattern                    (* Name "{" field_pats "}" *)
               | map_pattern ;                      (* "%{" ... "}"  — BEAM-only *)

list_pattern   = "[" [ patterns [ "|" pattern ] ] "]" ;   (* "|" = cons here *)
struct_pattern = TypeName "{" field_pat { "," field_pat } "}" ;
field_pat      = name [ ":" pattern ] ;

(* ---- guards: restricted, pure, total ---- *)
guard_expr     = guard_or ;
guard_or       = guard_and { "or"  guard_and } ;
guard_and      = guard_not { "and" guard_not } ;
guard_not      = [ "not" ] guard_cmp ;
guard_cmp      = guard_add [ cmp_op guard_add ] ;
cmp_op         = "==" | "!=" | "<" | "<=" | ">" | ">=" ;
guard_add      = guard_mul { ("+"|"-") guard_mul } ;
guard_mul      = guard_atom { ("*"|"/"|"rem"|"div") guard_atom } ;
guard_atom     = literal | name | guard_call
               | name "in" range_or_list
               | "(" guard_expr ")" ;
guard_call     = guard_fn "(" [ guard_expr { "," guard_expr } ] ")" ;
guard_fn       = "is_int" | "is_float" | "is_str" | "is_bool" | "is_atom"
               | "is_tuple" | "is_list" | "is_nil"
               | "len" | "size" | "abs" ;
```

---

## 3. Pattern language — portability

| Pattern | Example | Elixir | Rust | Portable? |
|---|---|---|---|---|
| literal | `0`, `"x"`, `true` | literal | literal | ✅ |
| wildcard | `_` | `_` | `_` | ✅ |
| binding | `n` | `n` | `n` | ✅ |
| as-pattern | `p @ Circle(r)` | `p = %Circle{...}` | `p @ Shape::Circle{..}` | ✅ |
| constructor | `Some(x)`, `Ok(v)` | tagged tuple / struct | `enum` variant | ✅ |
| tuple | `{a, b}` | `{a, b}` | `(a, b)` | ✅ |
| list (cons) | `[h \| t]` | `[h \| t]` | slice patterns | ✅* |
| struct (nominal) | `Circle{radius: r}` | `%Circle{radius: r}` | `Shape::Circle{radius: r}` | ✅ |
| open map | `%{key: v}` | `%{key: v}` | — | ❌ BEAM-only |
| pin (match expr) | `^expected` | `^expected` | guard `if v == expected` | ✅ |

\* Cons lowers to Rust slice patterns (`[h, rest @ ..]`); document the linked-vs-contiguous
cost difference (Elixir list O(1) prepend, Rust `Vec` is contiguous).

---

## 4. Guard sublanguage

Guards must be **pure, total, side-effect-free** and built **only** from the operations in
§2 `guard_expr`. This is the **intersection** of Elixir guards (a fixed whitelist) and Rust
match guards (arbitrary, but we restrict to the safe subset). **Arbitrary function calls are
rejected in guards.**

| Rian | Elixir guard | Rust guard |
|---|---|---|
| `and` / `or` / `not` | `and` / `or` / `not` | `&&` / `\|\|` / `!` |
| `==,!=,<,<=,>,>=` | same | same |
| `+ - * / rem div` | `+ - * / rem div` | `+ - * / %` / `div` |
| `x in 1..10` | `x in 1..10` | `(1..=10).contains(&x)` |
| `x in [a, b, c]` | `x in [a,b,c]` | `matches!(x, a \| b \| c)` |
| `is_int(x)` etc. | `is_integer(x)` etc. | **lowers to a pattern arm** (see §5.3) |
| `len(xs)` | `length(xs)` / `byte_size` | `xs.len()` |
| `abs(n)` | `abs(n)` | `n.abs()` |

---

## 5. Semantics & lowering

### 5.1 Matching order
Clauses are tried **top to bottom; first match wins** (Elixir `def` order; Rust `match`
arm order). Identical for both targets.

### 5.2 Multi-argument clauses
Elixir → one `def` per clause. Rust → one `fn` item that `match`es on the **tuple of
arguments**.

```
fn cmp(int, int) Order
fn cmp(a, b) when a <  b := Less
fn cmp(a, b) when a == b := Equal
fn cmp(_, _)             := Greater
```
```elixir
def cmp(a, b) when a <  b, do: :less
def cmp(a, b) when a == b, do: :equal
def cmp(_, _),             do: :greater
```
```rust
fn cmp(a: i64, b: i64) -> Order {
    match (a, b) {
        (a, b) if a <  b => Order::Less,
        (a, b) if a == b => Order::Equal,
        (_, _)           => Order::Greater,
    }
}
```

### 5.3 Union narrowing: guard ⇄ pattern
A guard that narrows a union argument lowers to a **guard on Elixir** and a **pattern arm on
Rust**, because Rust narrows enums structurally.

```
fn show(int | str) str
fn show(x) when is_int(x) := "int: " <> to_str(x)
fn show(x) when is_str(x) := "str: " <> x
```
```elixir
def show(x) when is_integer(x), do: "int: " <> Integer.to_string(x)
def show(x) when is_binary(x),  do: "str: " <> x
```
```rust
fn show(x: Value) -> String {
    match x {
        Value::Int(x) => format!("int: {x}"),
        Value::Str(x) => format!("str: {x}"),
    }
}
```

### 5.4 Boolean & comparison operators
`and/or/not` → Elixir `and/or/not`, Rust `&&/||/!`. Comparisons map 1:1.

---

## 6. Exhaustiveness, reachability, partiality

**Exhaustiveness — static, required (stricter than Elixir).**
- A non-exhaustive function is a **compile error** (matches Rust).
- **Guarded clauses do not count** toward exhaustiveness. A function using guards must have
  an unguarded fallback (`_` or full structural coverage), exactly as Rust requires.
- On Elixir the compiler's own check is the guarantee (BEAM does not enforce it); on Rust the
  emitted `match` is provably exhaustive.

**Reachability.**
- **Warning:** a clause fully shadowed by earlier clauses is unreachable.
- **Error:** two clauses with identical heads + guards (true duplicate).

**Partiality — opt-in, never silent.**
```
@partial
fn unwrap(Option(T)) T
fn unwrap(Some(x)) := x
```
- Rust: emits `_ => panic!("unwrap: None")`.
- Elixir: relies on `FunctionClauseError` (optionally a generated raising clause).
- Without `@partial`, the above is a **compile error** (`None` unhandled).

---

## 7. Worked example (end to end)

```
type Tree(T) := Leaf | Node(left: Tree(T), value: T, right: Tree(T))

fn depth(Tree(T)) int
fn depth(Leaf)        := 0
fn depth(Node(l, _, r)) := 1 + max2(depth(l), depth(r))

fn max2(int, int) int
fn max2(a, b) when a >= b := a
fn max2(a, b)             := b
```
```elixir
def depth(:leaf), do: 0
def depth({:node, l, _v, r}), do: 1 + max2(depth(l), depth(r))

def max2(a, b) when a >= b, do: a
def max2(_a, b), do: b
```
```rust
enum Tree<T> { Leaf, Node(Box<Tree<T>>, T, Box<Tree<T>>) }

fn depth<T>(t: Tree<T>) -> i64 {
    match t {
        Tree::Leaf => 0,
        Tree::Node(l, _, r) => 1 + max2(depth(*l), depth(*r)),
    }
}

fn max2(a: i64, b: i64) -> i64 {
    match (a, b) {
        (a, b) if a >= b => a,
        (_, b)           => b,
    }
}
```
Notes: recursive types box on Rust automatically (`Box`); `Tree(T)` generic via paren
application lowers to `Tree<T>`; `max2`'s guarded clause is backed by an unguarded fallback,
so the function is exhaustive on both targets.

---

## 8. Rejected / deferred forms

| Form | Status | Reason |
|---|---|---|
| Typed bindings in pattern heads (`Circle(r) Shape`) | Rejected | Use signature line + pattern clauses |
| Or-patterns (`A \| B =>`) | Deferred | Overloads `\|` (cons/union); write multiple clauses |
| Arbitrary function calls in guards | Rejected | Not Elixir-guard-safe; breaks portability |
| Open map patterns to Rust | BEAM-only | No idiomatic Rust equivalent |
| Early `return` in portable core | Deferred | Elixir lacks it; Rust-superset only |
| Silent partial functions | Rejected | Must be `@partial`; partiality is explicit |

---

## 9. Open items for next ADR
- Slice-pattern lowering for `[a, b | rest]` on Rust (`[a, b, rest @ ..]`) — confirm binding modes.
- Whether `len/size` in guards is portable for *all* sequence types or restricted to `Vec`/`str`.
- `match`-expression exhaustiveness messages should reuse the function-clause diagnostic engine
  (Samir: one engine, no second approximation).
