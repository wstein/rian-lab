defmodule Rian.DotTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  describe "`.` is the universal qualifier (case-disambiguated)" do
    test "Rian module path: Elixir `.`, Rust `::` (lowercased)" do
      assert Lower.emit_expr("Geometry.area(x)", :elixir) == "Geometry.area(x)"
      assert Lower.emit_expr("Geometry.area(x)", :rust) == "geometry::area(x)"
    end

    test "field access: `.` on both targets" do
      assert Lower.emit_expr("point.x", :elixir) == "point.x"
      assert Lower.emit_expr("point.x", :rust) == "point.x"
    end

    test "type/variant path: Rust keeps PascalCase `::`" do
      assert Lower.emit_expr("Value.Num(n)", :rust) == "Value::Num(n)"
    end

    test "Erlang FFI via atom: Elixir `:mod.fun`, Rust is BEAM-only" do
      assert Lower.emit_expr(":lists.sum(xs)", :elixir) == ":lists.sum(xs)"
      assert_raise RuntimeError, ~r/BEAM-only/, fn -> Lower.emit_expr(":lists.sum(xs)", :rust) end
    end

    test "Elixir-module FFI keeps `.` on Elixir" do
      assert Lower.emit_expr("String.upcase(s)", :elixir) == "String.upcase(s)"
    end
  end

  describe "user example: match on Value.Num(x)" do
    defp types do
      [
        %{
          name: "Value",
          variants: [
            %{ctor: "Num", fields: [%{type: "i64"}]},
            %{ctor: "Zero", fields: []}
          ]
        }
      ]
    end

    defp eval_fn do
      %{
        name: "eval",
        param_name: "v",
        param_type: "Value",
        param_cap: :iso,
        ret: "i64",
        clauses: [
          %{pats: [{:ctor, "Num", [{:var, "n"}]}], body: "n * 2"},
          %{pats: [{:ctor, "Zero", []}], body: "0"}
        ]
      }
    end

    test "Rust: tuple variant + unit variant (no empty parens)" do
      rust = Lower.compile(types(), eval_fn()).rust
      assert rust =~ "Value::Num(n) => n * 2,"
      assert rust =~ "Value::Zero => 0,"
      refute rust =~ "Value::Zero()"
    end

    test "Elixir: tagged tuple + bare atom" do
      el = Lower.compile(types(), eval_fn()).elixir
      assert el =~ "def eval({:num, n}) do n * 2 end"
      assert el =~ "def eval(:zero) do 0 end"
    end

    test "executes on the BEAM" do
      el = Lower.compile(types(), eval_fn()).elixir
      Code.eval_string("defmodule EvT do\n#{el}\nend")
      assert EvT.eval({:num, 21}) == 42
      assert EvT.eval(:zero) == 0
    end
  end
end
