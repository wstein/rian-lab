defmodule Rian.LowerTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  defp types do
    [
      %{
        name: "Shape",
        variants: [
          %{ctor: "Circle", fields: [%{label: "radius", type: "f64"}]},
          %{ctor: "Square", fields: [%{label: "side", type: "f64"}]}
        ]
      }
    ]
  end

  defp area do
    %{
      name: "area",
      param_name: "shape",
      param_type: "Shape",
      ret: "f64",
      clauses: [
        %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
        %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}
      ]
    }
  end

  describe "Elixir emission" do
    test "multi-clause defs with tagged-tuple patterns and pi const" do
      out = Lower.compile(types(), area())
      assert out.elixir =~ "def area({:circle, r}) do :math.pi() * r * r end"
      assert out.elixir =~ "def area({:square, s}) do s * s end"
      assert out.elixir =~ "@type shape :: {:circle, float()} | {:square, float()}"
    end
  end

  describe "Rust emission" do
    test "enum + match with struct-variant patterns and PI const" do
      out = Lower.compile(types(), area())
      assert out.rust =~ "enum Shape {"
      assert out.rust =~ "Circle { radius: f64 }"
      assert out.rust =~ "Shape::Circle { radius: r } => std::f64::consts::PI * r * r,"
      assert out.rust =~ "Shape::Square { side: s } => s * s,"
    end
  end

  describe "exhaustiveness gate" do
    test "refuses to emit a non-exhaustive function, naming the witness" do
      bad = %{area() | clauses: [hd(area().clauses)]}

      assert_raise RuntimeError, ~r/non-exhaustive.*Square\(_\)/, fn ->
        Lower.compile(types(), bad)
      end
    end

    test "refuses to emit when a clause is unreachable" do
      dead = %{
        area()
        | clauses: [
            %{pats: [{:var, "any"}], body: "0.0"},
            %{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "r"}
          ]
      }

      assert_raise RuntimeError, ~r/unreachable/, fn -> Lower.compile(types(), dead) end
    end
  end

  describe "expression lowering (operator table)" do
    test "integer div / float div diverge per target" do
      assert Lower.emit_expr("n div 2", :elixir) == "div(n, 2)"
      assert Lower.emit_expr("n div 2", :rust) == "n / 2"
      assert Lower.emit_expr("a / b", :elixir) == "a / b"
      assert Lower.emit_expr("a / b", :rust) == "(a as f64) / (b as f64)"
    end

    test "pipe is native on Elixir, structural call on Rust" do
      assert Lower.emit_expr("x |> f(y) |> g", :elixir) == "x |> f(y) |> g"
      assert Lower.emit_expr("x |> f(y) |> g", :rust) == "g(f(x, y))"
    end

    test "concat is native on Elixir, flattened format! on Rust" do
      assert Lower.emit_expr("s <> t <> u", :elixir) == "s <> t <> u"
      assert Lower.emit_expr("s <> t <> u", :rust) == ~s|format!("{}{}{}", s, t, u)|
    end

    test "boolean operators map to symbols on Rust" do
      assert Lower.emit_expr("a and not b", :elixir) == "a and not b"
      assert Lower.emit_expr("a and not b", :rust) == "a && !b"
    end

    test "precedence is preserved without redundant parens" do
      assert Lower.emit_expr("a + b * c", :rust) == "a + b * c"
      assert Lower.emit_expr("(a + b) * c", :rust) == "(a + b) * c"
    end
  end

  describe "emitted Elixir executes correctly" do
    test "area on real values matches expected" do
      out = Lower.compile(types(), area())
      Code.eval_string("defmodule AreaGenTest do\n#{out.elixir}\nend")
      assert_in_delta apply(AreaGenTest, :area, [{:circle, 2.0}]), :math.pi() * 4, 1.0e-9
      assert apply(AreaGenTest, :area, [{:square, 3.0}]) == 9.0
    end
  end
end
