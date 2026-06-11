defmodule Rian.MacroTest do
  use ExUnit.Case, async: false
  alias Rian.{Pratt, Macro, Comptime, Lower}

  @env Macro.build_env([
         %{name: "unless", params: ["cond", "body"], template: "if not cond do body else 0 end"},
         %{name: "square", params: ["x"], template: "x * x"},
         %{name: "add_tmp", params: ["x"], template: "if true do tmp := 100; x + tmp else 0 end"}
       ])

  defp pipe(src), do: Pratt.parse(src) |> (&Macro.expand(@env, &1)).() |> Comptime.fold()
  defp el(src), do: Lower.emit_ast(pipe(src), :elixir)
  defp rs(src), do: Lower.emit_ast(pipe(src), :rust)

  setup_all do
    defs =
      [
        {"t", "n", "unless(n > 5, n * 10)"},
        {"sq", "m", "square(m + 1)"},
        {"hyg", "tmp", "add_tmp(tmp)"},
        {"c", "_x", "comptime(2 + 3 * 4)"}
      ]
      |> Enum.map_join("\n", fn {name, p, body} -> "def #{name}(#{p}) do #{el(body)} end" end)

    Code.eval_string("defmodule MacT do\n#{defs}\nend")
    :ok
  end

  describe "declarative pattern->template expansion" do
    test "unless expands to an if/not" do
      assert el("unless(n > 5, n * 10)") == "if not (n > 5) do n * 10 else 0 end"
      assert rs("unless(n > 5, n * 10)") == "if !(n > 5) { n * 10 } else { 0 }"
    end

    test "AST substitution avoids the C-preprocessor precedence bug" do
      # SQ(a+b) in C => a+b*a+b; here it must be (a + b) * (a + b)
      assert el("square(a + b)") == "(a + b) * (a + b)"
      assert rs("square(a + b)") == "(a + b) * (a + b)"
    end
  end

  describe "hygiene" do
    test "macro-local binder is gensym-renamed, caller's variable is untouched" do
      out = el("add_tmp(tmp)")
      assert out =~ ~r/tmp__h\d+ = 100/
      assert out =~ ~r/tmp \+ tmp__h\d+/
      refute out =~ "tmp = 100; tmp + tmp"
    end

    test "hygiene gives the correct runtime value (105, not 200)" do
      assert MacT.hyg(5) == 105
    end
  end

  describe "comptime (Zig-style) folding" do
    test "folds a constant expression to a literal" do
      assert el("comptime(2 + 3 * 4)") == "14"
      assert el("comptime((1 + 2) * 5)") == "15"
      assert rs("comptime(2 + 3 * 4)") == "14"
    end

    test "folds a boolean comparison" do
      assert el("comptime(3 > 5)") == "false"
      assert el("comptime(10 == 10)") == "true"
    end

    test "folds float constants (`/` is float division)" do
      assert el("comptime(3.14 * 2)") == "6.28"
      assert el("comptime(1 / 2)") == "0.5"
      assert rs("comptime(1 / 2)") == "0.5"
    end

    test "`div`/`rem` refuse float operands (integers only)" do
      assert_raise RuntimeError, ~r/require integer operands/, fn ->
        pipe("comptime(3.0 div 2)")
      end
    end
  end

  describe "comptime sandbox (ADR-0009)" do
    test "refuses function calls" do
      assert_raise RuntimeError, ~r/calls are not allowed/, fn -> pipe("comptime(foo(3))") end
    end

    test "refuses non-constants" do
      assert_raise RuntimeError, ~r/not a compile-time constant/, fn ->
        pipe("comptime(x + 1)")
      end
    end

    test "refuses FFI" do
      assert_raise RuntimeError, ~r/not allowed/, fn -> pipe("comptime(:lists.sum(xs))") end
    end
  end

  describe "executes on the BEAM" do
    test "macro-expanded functions run correctly" do
      assert MacT.t(3) == 30
      assert MacT.t(7) == 0
      assert MacT.sq(4) == 25
      assert MacT.c(0) == 14
    end
  end
end
