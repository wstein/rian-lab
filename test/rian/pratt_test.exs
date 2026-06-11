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

    test "x <- a or b  ==  x <- (a or b)" do
      assert p("x <- a or b") == "(<- x (or a b))"
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

    test "<- is right-associative" do
      assert p("a <- b <- c") == "(<- a (<- b c))"
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

  describe "`.` is the sole qualifier (ADR-0029; no `::` alias)" do
    test "dot lowers to a single {:dot} node" do
      assert p("Geometry.area(x)") == "(call (. Geometry area) x)"
    end

    test "`::` is not Rian syntax — it is a parse error" do
      assert_raise ArgumentError, fn -> Pratt.parse("Geometry::area(x)") end
    end
  end
end
