defmodule Rian.FeaturesTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  setup_all do
    fns = [
      {"dbl_all", "xs", "Enum.map(xs, (x) -> x * 2)"},
      {"sum", "xs", ":lists.foldl((x, acc) -> x + acc, 0, xs)"},
      {"sign", "n", "if n >= 0 do 1 else 0 - 1 end"},
      {"step", "n", "if n > 0 do a := n * 2; a + 1 else 0 end"},
      {"nums", "_x", "[10, 20, 30]"},
      {"pre", "p", "[p | [1, 2]]"},
      {"rec", "_x", "%{a: 1, b: 2}"}
    ]

    defs =
      Enum.map_join(fns, "\n", fn {name, param, body} ->
        f = %{
          name: name,
          params: [%{name: param, type: "term", cap: :val}],
          ret: "term",
          clauses: [%{pats: [{:var, param}], body: body}]
        }

        Lower.compile_beam([], f).elixir |> String.split("\n") |> List.last()
      end)

    Code.eval_string("defmodule Feat do\n#{defs}\nend")
    :ok
  end

  describe "lambda lowering" do
    test "Elixir anonymous fn / Rust closure" do
      assert Lower.emit_expr("(x) -> x * 2", :elixir) == "fn x -> x * 2 end"
      assert Lower.emit_expr("(x) -> x * 2", :rust) == "|x| x * 2"
      assert Lower.emit_expr("(x, acc) -> x + acc", :elixir) == "fn x, acc -> x + acc end"
    end

    test "lambda inside an FFI call" do
      assert Lower.emit_expr(":lists.foldl((x, acc) -> x + acc, 0, xs)", :elixir) ==
               ":lists.foldl(fn x, acc -> x + acc end, 0, xs)"
    end
  end

  describe "if / block lowering" do
    test "if-expression" do
      assert Lower.emit_expr("if n >= 0 do 1 else 0 - 1 end", :elixir) ==
               "if n >= 0 do 1 else 0 - 1 end"

      assert Lower.emit_expr("if n >= 0 do 1 else 0 - 1 end", :rust) ==
               "if n >= 0 { 1 } else { 0 - 1 }"
    end

    test "block with a binding" do
      assert Lower.emit_expr("if n > 0 do a := n * 2; a + 1 else 0 end", :elixir) ==
               "if n > 0 do a = n * 2; a + 1 else 0 end"

      assert Lower.emit_expr("if n > 0 do a := n * 2; a + 1 else 0 end", :rust) ==
               "if n > 0 { let a = n * 2; a + 1 } else { 0 }"
    end
  end

  describe "list / map literal lowering" do
    test "list literal" do
      assert Lower.emit_expr("[1, 2, 3]", :elixir) == "[1, 2, 3]"
      assert Lower.emit_expr("[1, 2, 3]", :rust) == "vec![1, 2, 3]"
    end

    test "cons construction (BEAM-only)" do
      assert Lower.emit_expr("[h | t]", :elixir) == "[h | t]"
      assert_raise RuntimeError, ~r/BEAM-only/, fn -> Lower.emit_expr("[h | t]", :rust) end
    end

    test "map literal (BEAM-only)" do
      assert Lower.emit_expr("%{a: 1, b: 2}", :elixir) == "%{a: 1, b: 2}"
      assert_raise RuntimeError, ~r/BEAM-only/, fn -> Lower.emit_expr("%{a: 1, b: 2}", :rust) end
    end
  end

  describe "all three features execute on the BEAM" do
    test "lambdas (Enum.map / foldl)" do
      assert Feat.dbl_all([1, 2, 3]) == [2, 4, 6]
      assert Feat.sum([1, 2, 3, 4]) == 10
    end

    test "if and blocks" do
      assert Feat.sign(-5) == -1
      assert Feat.sign(7) == 1
      assert Feat.step(3) == 7
      assert Feat.step(-1) == 0
    end

    test "list and map literals" do
      assert Feat.nums(0) == [10, 20, 30]
      assert Feat.pre(0) == [0, 1, 2]
      assert Feat.rec(0) == %{a: 1, b: 2}
    end
  end
end
