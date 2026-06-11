defmodule Rian.CaptureTest do
  use ExUnit.Case, async: true

  alias Rian.{Capability, Lower, Pratt}

  describe "anonymous captures `&( … )`" do
    test "parse to a {:capture} node with `&N` placeholders" do
      assert Pratt.parse_sexpr("&(&1 + &2)") == "(& (+ &1 &2))"
    end

    test "Elixir uses native capture; Rust spells out a closure with arity" do
      assert Lower.emit_expr("&(&1 + &2)", :elixir) == "&(&1 + &2)"
      assert Lower.emit_expr("&(&1 + &2)", :rust) == "|a1, a2| a1 + a2"
      assert Lower.emit_expr("&(&1 * 2)", :rust) == "|a1| a1 * 2"
    end

    test "executes on the BEAM" do
      {f, _} = Code.eval_string(Lower.emit_expr("&(&1 + &2)", :elixir))
      assert f.(2, 3) == 5

      {mapped, _} =
        Code.eval_string("Enum.map([1, 2, 3], #{Lower.emit_expr("&(&1 * 2)", :elixir)})")

      assert mapped == [2, 4, 6]
    end
  end

  describe "named captures `&name/arity`" do
    test "parse a bare or dotted path plus arity" do
      assert Pratt.parse_sexpr("&abs/1") == "(&/ abs 1)"
      assert Pratt.parse_sexpr("&String.upcase/1") == "(&/ (. String upcase) 1)"
    end

    test "Elixir uses native capture; Rust forwards through a closure" do
      assert Lower.emit_expr("&abs/1", :elixir) == "&abs/1"
      assert Lower.emit_expr("&abs/1", :rust) == "|a0| abs(a0)"
      assert Lower.emit_expr("&String.upcase/1", :elixir) == "&String.upcase/1"
    end

    test "executes on the BEAM" do
      {f, _} = Code.eval_string(Lower.emit_expr("&abs/1", :elixir))
      assert f.(-7) == 7
    end
  end

  describe "scope of B'" do
    test "operator sections like `(+)` are NOT introduced — they remain a parse error" do
      assert_raise ArgumentError, fn -> Pratt.parse("(+)") end
    end

    test "linearity counts an outer iso captured into a closure body" do
      assert Capability.lin_check(%{"f" => :iso}, Pratt.parse("&(&1 + f)")) == :ok

      assert Capability.lin_check(%{"f" => :iso}, Pratt.parse("pair(&(&1 + f), f)")) ==
               {:error, [{"f", 2}]}
    end
  end
end
