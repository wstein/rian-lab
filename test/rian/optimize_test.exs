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

  describe "post-check boolean identities (#4) — evaluation-preserving only" do
    test "an identity operand drops, the variable operand stays" do
      assert simp("true and x") == {:id, "x"}
      assert simp("x and true") == {:id, "x"}
      assert simp("false or x") == {:id, "x"}
      assert simp("x or false") == {:id, "x"}
    end

    test "a value-dropping case is left to the backend's short-circuit" do
      assert simp("false and x") == {:bin, "and", {:id, "false"}, {:id, "x"}}
      assert simp("x or true") == {:bin, "or", {:id, "x"}, {:id, "true"}}
    end
  end

  describe "post-check constant-`case` arm selection (#3)" do
    test "a constant scrutinee selects the matching literal arm" do
      assert simp("case 2 do 1 -> a\n2 -> b\n_ -> c end") == {:id, "b"}
      assert simp("case 9 do 1 -> a\n_ -> c end") == {:id, "c"}

      assert simp(~S|case "y" do "x" -> 1| <> "\n" <> ~S|"y" -> 2| <> "\n_ -> 3 end") ==
               {:num, "2"}
    end

    test "a non-constant scrutinee / a var or guarded arm keeps the case" do
      assert {:case, {:id, "s"}, _} = simp("case s do 1 -> a\n_ -> c end")
      assert {:case, {:num, "1"}, _} = simp("case 1 do n -> n end")
      assert {:case, {:num, "1"}, _} = simp("case 1 do 1 when x -> a\n_ -> b end")
    end
  end

  describe "post-check constant function-call inlining (#5)" do
    defp inlined_body(src) do
      prog = Optimize.simplify(Rian.Decl.parse(src))
      body = prog.funcs |> List.last() |> Map.get(:clauses) |> hd() |> Map.get(:body)
      # an unchanged body keeps its source-string form — normalize to AST for the assertion.
      if is_binary(body), do: Pratt.parse_body(body), else: body
    end

    test "a pure single-clause function with constant args is evaluated at compile time" do
      # `sq(2, 3)` over `def sq(a, b) := (a + b) * (a + b)` → 25
      assert inlined_body(
               "def sq(a Int53, b Int53) Int53 := (a + b) * (a + b)\npub def m() Int53 := sq(2, 3)\n"
             ) == {:block, [expr: {:num, "25"}]}
    end

    test "a non-constant argument leaves the call" do
      assert {:block, [expr: {:call, {:id, "sq"}, _}]} =
               inlined_body(
                 "def sq(a Int53, b Int53) Int53 := a * b\npub def m(x Int53) Int53 := sq(x, 3)\n"
               )
    end

    test "a recursive function is not inlined (no infinite expansion)" do
      # `fact(5)` doesn't fully reduce (the `else` branch keeps a `fact` call) → left as a call
      assert {:block, [expr: {:call, {:id, "fact"}, _}]} =
               inlined_body(
                 "def fact(n Int53) Int53 := if n == 0 do 1 else n * fact(n - 1) end\npub def m() Int53 := fact(5)\n"
               )
    end

    test "an effectful/non-foldable body is left a call (purity self-enforced)" do
      # `shout`'s body is host FFI → never folds to a constant → never inlined
      assert {:block, [expr: {:call, {:id, "shout"}, _}]} =
               inlined_body(
                 "def shout(s String) String := String.upcase(s)\npub def m() String := shout(\"hi\")\n"
               )
    end
  end

  describe "interpolation re-bake after inlining (ADR-0046 §5)" do
    test "a hole made constant by inlining bakes into the surrounding literal" do
      # `${sq(2, 3)}` resolves to `__prim_int_to_string(sq(2, 3))` pre-check; post-check inlining
      # makes it `25`, then the re-bake stringifies + merges → the single literal `"r=25"`. The body
      # is one `{:str, …}`, so ALL FOUR emitters print the literal — never `"r=" <> str(25)`.
      assert inlined_body(
               "def sq(a Int53, b Int53) Int53 := (a + b) * (a + b)\npub def m() String := \"r=${sq(2, 3)}\"\n"
             ) == {:block, [expr: {:str, "r=25"}]}
    end

    test "a runtime hole keeps its concat (the re-bake never folds a runtime value — boundary A)" do
      # `${x}` over a variable stays `__prim_int_to_string(x)` inside the concat: Rian finishes the
      # interpolation hole it can settle, but merging a *runtime* value is the backend's job.
      assert {:block,
              [
                expr:
                  {:call, {:id, "__prim_str_concat_all"},
                   [{:str, "v="}, {:call, {:id, "__prim_int_to_string"}, [{:id, "x"}]}]}
              ]} = inlined_body("pub def f(x Int53) String := \"v=${x}\"\n")
    end

    test "the re-bake is idempotent (running simplify twice == once)" do
      src =
        "def sq(a Int53, b Int53) Int53 := (a + b) * (a + b)\npub def m() String := \"r=${sq(2, 3)}\"\n"

      once = Optimize.simplify(Rian.Decl.parse(src))
      assert once == Optimize.simplify(once)
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
