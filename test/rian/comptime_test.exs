defmodule Rian.ComptimeTest do
  use ExUnit.Case, async: true

  alias Rian.{Comptime, Pratt}

  defp fold(src), do: Comptime.fold(Pratt.parse(src))
  defp auto(src), do: Comptime.fold_constants(Pratt.parse(src))

  describe "automatic constant folding (ADR-0046) — no `comptime` marker" do
    test "a pure all-literal expression folds to its literal" do
      assert auto("2 + 3 * 4") == {:num, "14"}
      assert auto("(1 + 2) * 5") == {:num, "15"}
      assert auto("6 / 2") == {:num, "3.0"}
      assert auto("3 > 5") == {:id, "false"}
      assert auto("-5") == {:num, "-5"}
    end

    test "a non-constant operand leaves the node untouched (opportunistic, never raises)" do
      assert auto("x + 1") == {:bin, "+", {:id, "x"}, {:num, "1"}}
      assert auto("f(2)") == {:call, {:id, "f"}, [num: "2"]}
      # a constant sub-expression still folds inside a non-constant context
      assert auto("x + (2 + 3)") == {:bin, "+", {:id, "x"}, {:num, "5"}}
    end

    test "type-preserving: a mixed Int/Float is NOT folded (so it can't mask a checker error)" do
      # the checker rejects `Int * Float`; auto-fold must leave it for the checker to catch
      assert auto("3.14 * 2") == {:bin, "*", {:num, "3.14"}, {:num, "2"}}
      assert auto("2 + 1.5") == {:bin, "+", {:num, "2"}, {:num, "1.5"}}
    end

    test "constant string concatenation folds (`\"a\" <> \"b\"` → `\"ab\"`)" do
      assert auto(~S|"a" <> "b" <> "c"|) == {:str, "abc"}
      assert auto(~S|"x = " <> "1"|) == {:str, "x = 1"}
      # a non-literal operand keeps the `<>` (folded children)
      assert auto(~S|x <> "!"|) == {:bin, "<>", {:id, "x"}, {:str, "!"}}
    end

    test "fully-constant `and`/`or` fold; a variable operand is left untouched" do
      assert auto("true and false") == {:id, "false"}
      assert auto("false or true") == {:id, "true"}

      # an operator over a VARIABLE is NOT simplified pre-check — `x and true` carries the `Bool`
      # constraint InferLocal reads and the operator pin Reach reads; folding it away would change
      # both (those identities belong in a post-check pass, not this variable-neutral one).
      assert auto("x and true") == {:bin, "and", {:id, "x"}, {:id, "true"}}
      assert auto("false and x") == {:bin, "and", {:id, "false"}, {:id, "x"}}
    end
  end

  describe "pure comptime folding (ADR-0009/0030)" do
    test "integer / float / underscore literals fold to a numeric node" do
      assert fold("comptime(42)") == {:num, "42"}
      assert fold("comptime(1_000)") == {:num, "1000"}
      assert fold("comptime(3.14)") == {:num, "3.14"}
    end

    test "arithmetic folds (precedence preserved)" do
      assert fold("comptime(2 + 3 * 4)") == {:num, "14"}
      assert fold("comptime(10 - 3)") == {:num, "7"}
      assert fold("comptime(-5)") == {:num, "-5"}
      # `/` is float division
      assert fold("comptime(6 / 2)") == {:num, "3.0"}
    end

    test "integer `div`/`rem` fold" do
      assert fold("comptime(7 div 2)") == {:num, "3"}
      assert fold("comptime(7 rem 2)") == {:num, "1"}
    end

    test "comparisons and `not` fold to a boolean id" do
      assert fold("comptime(1 < 2)") == {:id, "true"}
      assert fold("comptime(2 <= 2)") == {:id, "true"}
      assert fold("comptime(3 > 10)") == {:id, "false"}
      assert fold("comptime(5 >= 5)") == {:id, "true"}
      assert fold("comptime(1 == 1)") == {:id, "true"}
      assert fold("comptime(1 != 2)") == {:id, "true"}
      assert fold("comptime(not (1 < 2))") == {:id, "false"}
    end

    test "folds a comptime block nested inside a larger expression" do
      assert fold("1 + comptime(2 * 3)") == {:bin, "+", {:num, "1"}, {:num, "6"}}
    end

    test "a non-comptime expression is returned unchanged" do
      assert fold("a + b") == {:bin, "+", {:id, "a"}, {:id, "b"}}
    end
  end

  describe "the sandbox refuses non-constant / effectful nodes" do
    test "division by zero (float and integer) is refused" do
      assert_raise RuntimeError, ~r/division by zero/, fn -> fold("comptime(1 / 0)") end
      assert_raise RuntimeError, ~r/division by zero/, fn -> fold("comptime(1 div 0)") end
    end

    test "`div`/`rem` require integer operands" do
      assert_raise RuntimeError, ~r/require integer operands/, fn ->
        fold("comptime(7.0 div 2)")
      end
    end

    test "an operator with no comptime meaning is refused" do
      assert_raise RuntimeError, ~r/operator `<>` not allowed/, fn -> fold("comptime(1 <> 2)") end
    end

    test "`not` on a non-boolean is refused" do
      assert_raise RuntimeError, ~r/`not` expects a boolean/, fn -> fold("comptime(not 5)") end
    end

    test "calls, identifiers, and field/FFI access are refused" do
      assert_raise RuntimeError, ~r/calls are not allowed/, fn -> fold("comptime(f(1))") end
      assert_raise RuntimeError, ~r/not a compile-time constant/, fn -> fold("comptime(x)") end
      assert_raise RuntimeError, ~r/not allowed in comptime/, fn -> fold("comptime(a.b)") end
    end

    test "an otherwise-unsupported node is refused" do
      assert_raise RuntimeError, ~r/unsupported in comptime/, fn -> fold("comptime([1, 2])") end
    end
  end
end
