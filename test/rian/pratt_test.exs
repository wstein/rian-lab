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

  describe "char literals (ADR-0036) — desugar to codepoint integers" do
    test "in expression position a char literal becomes its codepoint" do
      assert Pratt.parse_body("c == '0'") ==
               {:block, [expr: {:bin, "==", {:id, "c"}, {:num, "48"}}]}
    end

    test "in pattern position a char literal matches its codepoint" do
      assert Pratt.parse_pats("'+'") == [{:lit, 43}]
      assert Pratt.parse_pats("['(' | rest]") == [{:list, [lit: 40], {:tail, {:var, "rest"}}}]
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
  end
end
