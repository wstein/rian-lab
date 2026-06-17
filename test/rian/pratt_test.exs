defmodule Rian.PrattTest do
  use ExUnit.Case, async: true
  alias Rian.Pratt
  alias Rian.Pratt.NonAssocError

  defp p(s), do: Pratt.parse_sexpr(s)

  describe "spec §2 worked consequences" do
    test "a + b |> f  ==  (a + b) |> f" do
      assert p("a + b |> f") == "(|> (+ a b) f)"
    end

    test "x |> f < y  ==  (x |> f) < y" do
      assert p("x |> f < y") == "(< (|> x f) y)"
    end

    test "not a and b  ==  (not a) and b" do
      assert p("not a and b") == "(and (not a) b)"
    end

    test "x <~ a or b  ==  x <~ (a or b)" do
      assert p("x <~ a or b") == "(<~ x (or a b))"
    end
  end

  describe "with / tuples (ADR-0040 surface)" do
    test "tuple literal and `{:ok, _}` parse" do
      assert p("{1, 2}") == "{1 2}"
      assert p("{:ok, x}") == "{:ok x}"
    end

    test "with clauses + else parse" do
      assert p("with {:ok, x} <- f(a) do x else {:error, e} -> e end") ==
               "(with (<- {:ok, x} (call f a)) (block x) (else ({:error, e} -> e)))"
    end
  end

  describe "as-patterns (`name @ pat`)" do
    test "an as-pattern in a case arm parses to a PAs node" do
      assert p("case x do n @ {a, b} -> n end") == "(case x ((@ n {a, b}) -> n))"
    end
  end

  describe "reserved keywords are valid field labels (ADR-0033)" do
    test "a keyword labels a construction field (`type:`, `def:`)" do
      assert p("Foo(type: 1, def: 2)") == "(call Foo type: 1 def: 2)"
    end

    test "a keyword labels a map-literal key" do
      assert p("%{type: 1}") == "%{type: 1}"
    end
  end

  describe "arithmetic precedence & associativity" do
    test "* binds tighter than +" do
      assert p("a + b * c") == "(+ a (* b c))"
      assert p("a * b + c") == "(+ (* a b) c)"
    end

    test "+ and - are left-associative (same level)" do
      assert p("a - b + c") == "(+ (- a b) c)"
    end

    test "* / rem div share a level, left-associative" do
      assert p("a div b * c") == "(* (div a b) c)"
    end

    test "unary minus binds tighter than *" do
      assert p("-a * b") == "(* (- a) b)"
    end
  end

  describe "right-associative operators" do
    test "<> is right-associative" do
      assert p("a <> b <> c") == "(<> a (<> b c))"
    end

    test "<~ is right-associative" do
      assert p("a <~ b <~ c") == "(<~ a (<~ b c))"
    end
  end

  describe "boolean & pipe layering" do
    test "and binds tighter than or" do
      assert p("a and b or c") == "(or (and a b) c)"
    end

    test "|> is left-associative" do
      assert p("a |> f |> g") == "(|> (|> a f) g)"
    end

    test "<> binds tighter than |>" do
      assert p("a <> b |> f") == "(|> (<> a b) f)"
    end

    test "in binds tighter than or" do
      assert p("a in b or c") == "(or (in a b) c)"
    end
  end

  describe "comparison/equality are non-associative across levels" do
    test "< binds tighter than == (different levels chain)" do
      assert p("a < b == c") == "(== (< a b) c)"
    end
  end

  describe "postfix call / field / path are tightest" do
    test "field access binds tighter than unary minus" do
      assert p("-a.b") == "(- (. a b))"
    end

    test "function call" do
      assert p("f(a, b)") == "(call f a b)"
      assert p("g()") == "(call g)"
    end

    test "path then call" do
      assert p("Geometry.area(x)") == "(call (. Geometry area) x)"
    end
  end

  describe "non-associativity is enforced" do
    test "a < b < c is rejected" do
      assert_raise NonAssocError, fn -> p("a < b < c") end
    end

    test "a == b == c is rejected" do
      assert_raise NonAssocError, fn -> p("a == b == c") end
    end

    test "a in b in c is rejected" do
      assert_raise NonAssocError, fn -> p("a in b in c") end
    end

    test "a <= b > c is rejected (same comparison level)" do
      assert_raise NonAssocError, fn -> p("a <= b > c") end
    end
  end

  describe "numeric literals (floats, `_` separators, exponents)" do
    test "plain integers and floats lex verbatim" do
      assert p("42") == "42"
      assert p("3.14") == "3.14"
    end

    test "underscore digit separators are preserved" do
      assert p("1_000") == "1_000"
      assert p("1_000.5") == "1_000.5"
    end

    test "an exponent without a decimal point is normalized to valid-on-both-targets form" do
      # `1e9` is invalid Elixir; normalize to `1.0e9` (also valid Rust f64)
      assert p("1e9") == "1.0e9"
      assert p("2.5e-3") == "2.5e-3"
    end

    test "a float participates in normal precedence" do
      assert p("x + 3.14 * 2") == "(+ x (* 3.14 2))"
    end
  end

  describe "case expressions" do
    test "parses scrutinee and pattern arms" do
      assert p("case x do Circle(r) -> r Square(s) -> s end") ==
               "(case x (Circle(r) -> r) (Square(s) -> s))"
    end

    test "wildcard and literal arms parse" do
      assert p("case n do 0 -> a _ -> b end") == "(case n (0 -> a) (_ -> b))"
    end
  end

  describe "bitstrings `<<seg::spec, …>>` (ADR-0078)" do
    test "segments parse with type/size specifiers" do
      assert Pratt.parse("<<c::utf8, rest::binary, x::8>>") ==
               {:bitstr,
                [
                  {:bitseg, {:id, "c"}, [type: "utf8"]},
                  {:bitseg, {:id, "rest"}, [type: "binary"]},
                  {:bitseg, {:id, "x"}, [size: 8]}
                ]}
    end

    test "a bare segment has no specs; `<<>>` need not collide with `<`/`>`" do
      assert Pratt.parse("<<104, 105>>") ==
               {:bitstr, [{:bitseg, {:num, "104"}, []}, {:bitseg, {:num, "105"}, []}]}

      assert Pratt.parse("a < b") == {:bin, "<", {:id, "a"}, {:id, "b"}}
    end
  end

  describe "parse_body (function bodies: block-or-expression)" do
    test "a single expression becomes a one-statement block" do
      assert Pratt.parse_body("a + b") == {:block, [{:expr, {:bin, "+", {:id, "a"}, {:id, "b"}}}]}
    end

    test "a `;`-separated block parses to bindings + a final expression" do
      assert Pratt.parse_body("x := 2 ; x + 1") ==
               {:block,
                [{:bind, "x", {:num, "2"}}, {:expr, {:bin, "+", {:id, "x"}, {:num, "1"}}}]}
    end

    test "a typed binding `x Int32 := 66` carries its declared type" do
      # `name Type := expr` binds `name` to `expr` and preserves the annotation
      # in a `{:typed_bind, name, type, expr}` node so the checker can enforce it.
      assert Pratt.parse_body("x Int32 := 66 ; x") ==
               {:block, [{:typed_bind, "x", "Int32", {:num, "66"}}, {:expr, {:id, "x"}}]}

      # untyped bindings are unaffected
      assert Pratt.parse_body("y := 1") == {:block, [{:bind, "y", {:num, "1"}}]}
    end

    test "a typed binding accepts a parametric type, rendered space-free" do
      # the type string matches the checker's canonical form (`Vec(Int64)`, no
      # interior spaces) so an annotation unifies with an inferred parametric type
      assert Pratt.parse_body("xs Vec(Int64) := [1]") ==
               {:block, [{:typed_bind, "xs", "Vec(Int64)", {:list_lit, [num: "1"], nil}}]}

      assert {:block, [{:typed_bind, "m", "Map(String,Int64)", _}]} =
               Pratt.parse_body("m Map(String, Int64) := d")

      assert {:block, [{:typed_bind, "v", "Vec(Vec(Int64))", _}]} =
               Pratt.parse_body("v Vec(Vec(Int64)) := xss")
    end
  end

  describe "string literals" do
    test "a string literal lexes and round-trips" do
      assert p("\"zero\"") == "\"zero\""
    end

    test "string concatenation parses with `<>`" do
      assert p("\"a\" <> b") == "(<> \"a\" b)"
    end

    test "an unterminated string is a lex error" do
      assert_raise ArgumentError, ~r/unterminated string/, fn -> Pratt.parse("\"oops") end
    end
  end

  describe "char literals (ADR-0036) — a distinct `Char` node" do
    test "in expression position a char literal is a `{:char, codepoint}` node" do
      assert Pratt.parse_body("c == '0'") ==
               {:block, [expr: {:bin, "==", {:id, "c"}, {:char, 48}}]}
    end

    test "in pattern position a char literal is a `{:char_lit, codepoint}` node" do
      assert Pratt.parse_pats("'+'") == [{:char_lit, 43}]

      assert Pratt.parse_pats("['(' | rest]") == [
               {:list, [char_lit: 40], {:tail, {:var, "rest"}}}
             ]
    end
  end

  describe "atom literals — bare `:id` and quoted `:\"…\"`" do
    test "a bare identifier atom `:foo` is an `{:atom, _}` node" do
      assert p(":foo") == ":foo"
    end

    test "a quoted atom `:\"+\"` spells an operator-named atom (no bare form)" do
      assert Pratt.parse(~s|:"+"|) == {:atom, "+"}
      assert p(~s|:"+"|) == ":+"
    end

    test "a quoted atom can name a reserved keyword `:\"if\"` (subsumes the parser's old crutch)" do
      assert Pratt.parse(~s|:"if"|) == {:atom, "if"}
    end

    test "a quoted atom works in pattern position too" do
      assert Pratt.parse_pats(~s|:"+"|) == [{:atom, "+"}]
    end

    test "a bare operator atom `:+` is still a parse error (use the quoted form)" do
      assert_raise ArgumentError, fn -> Pratt.parse(":+") end
    end
  end

  describe "`.` is the sole qualifier (ADR-0029; no `::` alias)" do
    test "dot lowers to a single {:dot} node" do
      assert p("Geometry.area(x)") == "(call (. Geometry area) x)"
    end

    test "`::` is not Rian syntax — it is a parse error" do
      assert_raise ArgumentError, fn -> Pratt.parse("Geometry::area(x)") end
    end
  end

  describe "struct & map patterns (ADR-0043)" do
    test "a struct pattern `Name(field: p)` parses with its named fields" do
      assert Pratt.parse_pats("Point(x: a, y: b)") ==
               [{:struct, "Point", [{"x", {:var, "a"}}, {"y", {:var, "b"}}]}]
    end

    test "positional args stay a sum-variant (ctor) pattern, not a struct" do
      assert Pratt.parse_pats("Some(n)") == [{:ctor, "Some", [{:var, "n"}]}]
    end

    test "a map pattern `%{k: p}` parses; nested patterns are allowed" do
      assert Pratt.parse_pats("%{tag: :num, val: v}") ==
               [{:map, [{"tag", {:atom, "num"}}, {"val", {:var, "v"}}]}]
    end

    test "map and struct patterns render in the s-expression debug view" do
      # Regression: `sexpr_pat` had no `:map`/`:struct` clause, so a `case` arm over
      # either pattern crashed the debug renderer with a FunctionClauseError.
      assert Pratt.parse_sexpr("case x do %{a: v} -> v end") ==
               "(case x (%{a: v} -> v))"

      assert Pratt.parse_sexpr("case p do Point(x: a, y: b) -> a end") ==
               "(case p (Point(x: a, y: b) -> a))"
    end
  end

  describe "malformed input raises (expression parser)" do
    test "trailing tokens after a parenthesized expression: missing `)`" do
      assert_raise ArgumentError, ~r/expected `\)`/, fn -> Pratt.parse("(a b") end
    end

    test "the error names the offending token (kind + value), not the raw stream" do
      # Regression: `expect_*` and `parse_primary` dumped `inspect(toks)` — the whole
      # remaining stream. The message now points at the first token, e.g.
      # `expected `)`, got identifier `b``.
      err = assert_raise(ArgumentError, fn -> Pratt.parse("(a b") end)
      assert Exception.message(err) =~ "got identifier `b`"
      refute Exception.message(err) =~ "[{:"

      bad = assert_raise(ArgumentError, fn -> Pratt.parse("def") end)
      assert Exception.message(bad) =~ "unexpected token: keyword `def`"
    end

    test "a call argument not followed by `,` or `)`" do
      assert_raise ArgumentError, ~r/expected `,` or `\)`/, fn -> Pratt.parse("f(a b)") end
    end

    test "a list literal element not followed by `,`, `|`, or `]`" do
      assert_raise ArgumentError, ~r/bad list/, fn -> Pratt.parse("[1 2]") end
    end

    test "a tuple literal element not followed by `,` or `}`" do
      assert_raise ArgumentError, ~r/bad tuple/, fn -> Pratt.parse("{1 2}") end
    end

    test "a map literal pair not followed by `,` or `}`" do
      assert_raise ArgumentError, ~r/bad map/, fn -> Pratt.parse("%{a: 1 b: 2}") end
    end

    test "a list literal with a cons tail must close with `]`" do
      assert_raise ArgumentError, ~r/expected `\]`/, fn -> Pratt.parse("[a | b c]") end
    end

    test "an anonymous capture must close with `)`" do
      assert_raise ArgumentError, ~r/expected `\)`/, fn -> Pratt.parse("&(a b)") end
    end
  end

  describe "malformed input raises (lambda / params)" do
    test "more than the matched lambda params is rejected" do
      assert_raise ArgumentError, ~r/bad lambda params/, fn -> Pratt.parse("(x y z) -> x") end
    end
  end

  describe "malformed input raises (function captures)" do
    test "a named capture needs an integer arity after `/`" do
      assert_raise ArgumentError, ~r/expected an integer arity after `\/`/, fn ->
        Pratt.parse("&f/x")
      end
    end

    test "a capture path must start with a name or `:atom`" do
      assert_raise ArgumentError, ~r/bad capture path/, fn -> Pratt.parse("&+/2") end
    end
  end

  describe "malformed input raises (statement bodies)" do
    test "trailing tokens in a body after the final expression raise" do
      # two ids `a b` parse as one expression `a` followed by a stray `b`, which
      # has no statement form, so it surfaces as a trailing-token error.
      assert_raise ArgumentError, ~r/trailing tokens in body/, fn -> Pratt.parse_body("a b") end
    end
  end

  describe "malformed input raises (`expect_*` helpers)" do
    test "an `if` without `do` reports the expected keyword" do
      assert_raise ArgumentError, ~r/expected `do`/, fn -> Pratt.parse("if c x end") end
    end

    test "a `case` arm without `->` reports the expected operator" do
      assert_raise ArgumentError, ~r/expected `->`/, fn -> Pratt.parse("case x do _ x end") end
    end
  end

  describe "malformed input raises (pattern parser)" do
    test "trailing tokens after a pattern in a pattern list" do
      assert_raise ArgumentError, ~r/trailing tokens in pattern list/, fn ->
        Pratt.parse_pats("a b")
      end
    end

    test "a token that begins no pattern is unsupported" do
      assert_raise ArgumentError, ~r/unsupported pattern/, fn -> Pratt.parse_pats("+") end
    end

    test "a map pattern pair not followed by `,` or `}`" do
      assert_raise ArgumentError, ~r/bad map pattern/, fn -> Pratt.parse_pats("%{a: 1 b: 2}") end
    end

    test "a map pattern key must be an identifier followed by `:`" do
      assert_raise ArgumentError, ~r/bad map pattern/, fn -> Pratt.parse_pats("%{1}") end
    end

    test "a struct pattern field not followed by `,` or `)`" do
      assert_raise ArgumentError, ~r/bad struct pattern/, fn ->
        Pratt.parse_pats("Point(x: a y: b)")
      end
    end

    test "a struct pattern with a non-field token raises" do
      assert_raise ArgumentError, ~r/bad struct pattern fields/, fn ->
        Pratt.parse_pats("Point(x: a, 1)")
      end
    end

    test "a tuple pattern element not followed by `,` or `}`" do
      assert_raise ArgumentError, ~r/bad tuple pattern/, fn -> Pratt.parse_pats("{a b}") end
    end

    test "a list pattern element not followed by `,`, `|`, or `]`" do
      assert_raise ArgumentError, ~r/bad list pattern/, fn -> Pratt.parse_pats("[a b]") end
    end

    test "a positional ctor pattern arg not followed by `,` or `)`" do
      assert_raise ArgumentError, ~r/expected `,` or `\)` in pattern/, fn ->
        Pratt.parse_pats("Some(a b)")
      end
    end
  end

  describe "function captures (s-expr round-trip)" do
    test "a `&:mod.fun/arity` capture parses with an atom-rooted dotted path" do
      assert Pratt.parse_sexpr("&:erlang.length/1") == "(&/ (. :erlang length) 1)"
    end

    test "a `&N` placeholder and an anonymous `&( … )` capture parse" do
      assert Pratt.parse_sexpr("&1") == "&1"
      assert Pratt.parse_sexpr("&(a + b)") == "(& (+ a b))"
    end
  end

  describe "lambdas (s-expr printer)" do
    test "an empty-parameter lambda parses" do
      assert Pratt.parse_sexpr("() -> 1") == "(lambda () 1)"
    end

    test "a multi-parameter lambda renders its parameter names" do
      assert Pratt.parse_sexpr("(x, y) -> x + y") == "(lambda (x y) (+ x y))"
    end

    test "a typed lambda parameter `(x Int)` keeps the bare name in the printer" do
      assert Pratt.parse_sexpr("(x Int) -> x") == "(lambda (x) x)"
    end

    test "nested parentheses are not mistaken for a lambda header" do
      assert Pratt.parse_sexpr("((a + b))") == "(+ a b)"
    end
  end

  describe "if / blocks (s-expr printer)" do
    test "an `if` with both branches renders nested blocks" do
      assert Pratt.parse_sexpr("if c do a else b end") == "(if c (block a) (block b))"
    end

    test "an `if` without `else` renders an empty else block" do
      assert Pratt.parse_sexpr("if c do a end") == "(if c (block a) (block))"
    end

    test "a `;`-separated block stops cleanly at `else`" do
      assert Pratt.parse_sexpr("if c do a; b else d end") == "(if c (block a b) (block d))"
    end

    test "a block renders bind and expression statements" do
      assert Pratt.parse_sexpr("if c do x := 1; x else 0 end") ==
               "(if c (block (:= x 1) x) (block 0))"
    end
  end

  describe "case (s-expr printer covers pattern + guard rendering)" do
    test "a single-arm case renders" do
      assert Pratt.parse_sexpr("case x do _ -> 1 end") == "(case x (_ -> 1))"
    end

    test "a `when` guard is parsed (and elided by the printer)" do
      assert Pratt.parse_sexpr("case x do n when n > 0 -> 1 _ -> 0 end") ==
               "(case x (n -> 1) (_ -> 0))"
    end

    test "string, list (closed & cons), and nullary-ctor patterns render" do
      assert Pratt.parse_sexpr(~s|case x do "hi" -> 1 _ -> 0 end|) ==
               "(case x (\"hi\" -> 1) (_ -> 0))"

      assert Pratt.parse_sexpr("case x do [a, b] -> 1 _ -> 0 end") ==
               "(case x ([a, b] -> 1) (_ -> 0))"

      assert Pratt.parse_sexpr("case x do [a | b] -> 1 _ -> 0 end") ==
               "(case x ([a | b] -> 1) (_ -> 0))"

      assert Pratt.parse_sexpr("case x do None -> 1 _ -> 0 end") ==
               "(case x (None -> 1) (_ -> 0))"
    end
  end

  describe "literals & collections (s-expr printer)" do
    test "a labeled call argument renders as `name: value`" do
      assert Pratt.parse_sexpr("f(n: 1)") == "(call f n: 1)"
    end

    test "list literals with and without a cons tail render" do
      assert Pratt.parse_sexpr("[1, 2]") == "[1 2]"
      assert Pratt.parse_sexpr("[a | b]") == "[a | b]"
    end

    test "a map literal renders its `key: value` pairs" do
      assert Pratt.parse_sexpr("%{a: 1, b: 2}") == "%{a: 1 b: 2}"
    end
  end

  describe "empty pattern list" do
    test "parsing an empty string yields no patterns" do
      assert Pratt.parse_pats("") == []
    end
  end

  describe "empty and multi-element collections / patterns" do
    test "empty literals parse to empty nodes" do
      assert Pratt.parse_sexpr("[]") == "[]"
      assert Pratt.parse_sexpr("{}") == "{}"
      assert Pratt.parse_sexpr("%{}") == "%{}"
    end

    test "a comma-separated pattern list parses each pattern" do
      assert Pratt.parse_pats("a, b") == [{:var, "a"}, {:var, "b"}]
    end

    test "empty and multi-element collection patterns parse" do
      assert Pratt.parse_pats("[]") == [{:list, [], :close}]
      assert Pratt.parse_pats("{}") == [{:tuple, []}]
      assert Pratt.parse_pats("%{}") == [{:map, []}]
      assert Pratt.parse_pats("[a, b]") == [{:list, [{:var, "a"}, {:var, "b"}], :close}]
      assert Pratt.parse_pats("{a, b}") == [{:tuple, [{:var, "a"}, {:var, "b"}]}]
    end

    test "a multi-argument ctor pattern and an empty-args ctor pattern parse" do
      assert Pratt.parse_pats("Pair(a, b)") ==
               [{:ctor, "Pair", [{:var, "a"}, {:var, "b"}]}]

      assert Pratt.parse_pats("None()") == [{:ctor, "None", []}]
    end

    test "a list cons-tail pattern parses" do
      assert Pratt.parse_pats("[h | t]") == [{:list, [{:var, "h"}], {:tail, {:var, "t"}}}]
    end

    test "a negative-integer literal pattern parses" do
      assert Pratt.parse_pats("-1") == [{:lit, -1}]
    end
  end

  describe "with: multiple clauses and the no-else form" do
    test "comma-separated `with` clauses parse" do
      assert Pratt.parse_sexpr("with a <- f(x), b <- g(y) do a end") ==
               "(with (<- a (call f x)) (<- b (call g y)) (block a))"
    end

    test "a `with` without an `else` omits the else group" do
      assert Pratt.parse_sexpr("with {:ok, x} <- f(a) do x end") ==
               "(with (<- {:ok, x} (call f a)) (block x))"
    end
  end

  describe "unexpected leading token" do
    test "a token that begins no primary expression raises" do
      assert_raise ArgumentError, ~r/unexpected token/, fn -> Pratt.parse(")") end
    end
  end

  describe "block statement boundaries" do
    test "an empty body is an empty block (statements stop on no tokens)" do
      assert Pratt.parse_body("") == {:block, []}
    end

    test "a trailing `;` leaves the block at its last statement" do
      assert Pratt.parse_body("x := 1 ;") == {:block, [{:bind, "x", {:num, "1"}}]}
    end

    test "a then-branch block stops at `else` (statements stop on a keyword)" do
      assert Pratt.parse_sexpr("if c do a; b else d end") == "(if c (block a b) (block d))"
    end
  end
end
