# Rian Language Specification — Precedence Validation

**Status:** Validated by reference parser · **Refs:** ADR-0023
**Owner:** Chloe Bennett (parser) · Samir Patel (tests)
**Validates:** `rian-spec-expressions.md` §2 (operator precedence)
**Implementation:** `lib/rian/pratt.ex` · **Tests:** `test/rian/pratt_test.exs` (22/22 pass)

The operator table was *asserted* in the expressions spec. This makes it *executable*: a
precedence-climbing (Pratt) parser parses expressions and renders them as fully-parenthesized
S-expressions, so grouping and associativity are unambiguous, and non-associativity is enforced
by raising rather than by prose.

---

## 1. Method

Each operator carries `{level, assoc}`; binding power is `(13 − level) * 10`, split into
`(left_bp, right_bp)` as `(b, b+1)` for left-assoc, `(b+1, b)` for right-assoc, and `(b, b+1)`
for non-assoc — with an explicit **same-level-root check** that rejects chaining a non-assoc
operator with another of its own precedence level. Postfix `call`/`.`/`::` are parsed inside the
primary, making them tightest; unary `-`/`not` are prefix at bp 110 (tighter than every infix).

S-expression rendering: `(op lhs rhs)` for binary, `(op x)` for unary, `(call f args…)`,
`(. obj field)`, `(:: mod name)`.

---

## 2. Validated parses (machine-produced)

```
a + b |> f             => (|> (+ a b) f)
x |> f < y             => (< (|> x f) y)
not a and b            => (and (not a) b)
x <~ a or b            => (<~ x (or a b))
a + b * c              => (+ a (* b c))
a - b + c              => (+ (- a b) c)
a <> b <> c            => (<> a (<> b c))
a <~ b <~ c            => (<~ a (<~ b c))
a and b or c           => (or (and a b) c)
a |> f |> g            => (|> (|> a f) g)
a <> b |> f            => (|> (<> a b) f)
a in b or c            => (or (in a b) c)
a < b == c             => (== (< a b) c)
-a.b                   => (- (. a b))
Geometry.area(x)       => (call (. Geometry area) x)
```

Each line confirms a table decision: pipe looser than arithmetic and concat; pipe tighter than
comparison; unary tighter than `*`; `+`/`-` left-assoc; `<>` and `<~` right-assoc; `and` tighter
than `or`; `in` tighter than `or`; comparison tighter than equality (cross-level chaining
allowed); postfix `.`/`::`/call tightest.

---

## 3. Enforced rejections (non-associativity)

```
a < b < c              => REJECTED (`<` is non-associative; parenthesize)
a == b == c            => REJECTED (`==` is non-associative; parenthesize)
a <= b > c             => REJECTED (`>` is non-associative; parenthesize)
```

Same-level comparison/equality chaining is a parse error (matches Rust; avoids the
`1 < 2 < 3` footgun). Cross-level pairs such as `a < b == c` are accepted and grouped by
precedence.

---

## 4. Status & scope
- 22/22 assertions pass; the table in the expressions spec is now machine-verified.
- This is a *validation* parser (expressions only) — not the production parser, which also
  produces a lossless CST (ADR formatter requirement) and handles statements, blocks, `if`,
  `match`, and declarations.
- Open: extend the harness to statement/block grammar once the production lexer exists, so the
  precedence table is checked in the context of full bodies.
