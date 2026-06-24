defmodule Rian.OptimizeTest do
  use ExUnit.Case, async: true

  alias Rian.{Optimize, Pratt}

  defp simp(src), do: Optimize.simplify_expr(Pratt.parse(src))

  describe "post-check dead-`if` elimination (ADR-0046 §3, #2)" do
    test "a constant condition selects its branch" do
      # `if false do A else B end` → B ; `if true do A else B end` → A
      assert simp("if false do 10 else 20 end") == {:block, [expr: {:num, "20"}]}
      assert simp("if true do 10 else 20 end") == {:block, [expr: {:num, "10"}]}
    end

    test "a variable condition is left untouched" do
      assert {:if, {:id, "x"}, _, _} = simp("if x do 1 else 2 end")
    end

    test "elimination recurses (nested dead branches collapse)" do
      assert simp("if true do if false do 1 else 2 end else 3 end") ==
               {:block, [expr: {:block, [expr: {:num, "2"}]}]}
    end
  end

  describe "the program-wide pass runs only post-check (composed by the lower front-end)" do
    test "simplify/1 rewrites every clause body" do
      # the condition is folded to `false` at parse (fold_constants), then dead-`if` selects `else`
      prog =
        Optimize.simplify(Rian.Decl.parse("pub def f() Int53 := if 2 > 3 do 10 else 20 end\n"))

      [%{clauses: [%{body: body}]}] = prog.funcs
      # the `if` is gone — the body is just the selected branch
      refute match?({:block, [expr: {:if, _, _, _}]}, body)
    end
  end
end
