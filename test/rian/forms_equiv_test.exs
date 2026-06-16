defmodule Rian.FormsEquivTest do
  # async: false — Code.compile_string loads modules into the VM.
  use ExUnit.Case, async: false

  alias Rian.FormsEquiv

  # Compile `ex_body` through the Elixir frontend and `rian_body` through Rian,
  # into the *same* module atom, and return the two `.beam` binaries.
  setup do
    # Elixir strips abstract_code in :test unless debug_info is on; the oracle
    # comparison needs the abstract forms retained in the .beam.
    prev = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, prev) end)
    :ok
  end

  defp both(ex_body, rian_body) do
    mod = :"Elixir.FE"
    :code.purge(mod)
    :code.delete(mod)
    [{^mod, ex_bin}] = Code.compile_string("defmodule FE do\n#{ex_body}\nend")
    {:ok, ^mod, rian_bin} = Rian.Beam.compile("mod FE do\n#{rian_body}\nend", mod)
    {ex_bin, rian_bin}
  end

  describe "equivalent?/2 — Elixir oracle vs Rian-compiled" do
    test "straight-line arithmetic is forms-equivalent" do
      {ex, ri} = both("  def double(x), do: x + x", "  pub def double(x Int53) Int53 := x + x")
      assert FormsEquiv.equivalent?(ex, ri)
    end

    test "multi-clause function is forms-equivalent" do
      {ex, ri} =
        both(
          "  def f(0), do: 1\n  def f(n), do: n",
          "  pub def f(Int53) Int53\n  pub def f(0) := 1\n  pub def f(n) := n"
        )

      assert FormsEquiv.equivalent?(ex, ri)
    end

    test "a negated literal is forms-equivalent via the whitelisted fold" do
      # Elixir folds -1 → {:integer,-1}; Rian emits unary minus on 1. Same constant.
      {ex, ri} = both("  def k(x), do: x * -1", "  pub def k(x Int53) Int53 := x * -1")
      assert FormsEquiv.equivalent?(ex, ri)
    end

    test "`if` is forms-equivalent via the whitelisted boolean-case reorder" do
      # Elixir lowers if→case as [false,true]; Rian as [true,false]. The safe
      # canonicalization makes them match; without it they would differ.
      {ex, ri} =
        both(
          "  def s(x), do: if x > 0, do: 1, else: 0",
          "  pub def s(x Int53) Int53 := if x > 0 do 1 else 0 end"
        )

      assert FormsEquiv.equivalent?(ex, ri)
    end
  end

  describe "the quotient is safe — genuine differences are NOT masked" do
    test "different operator (+ vs *) is reported as non-equivalent" do
      {ex, ri} = both("  def g(x), do: x + x", "  pub def g(x Int53) Int53 := x * x")
      refute FormsEquiv.equivalent?(ex, ri)
      assert {:diff, [{{:g, 1}, _ex_form, _ri_form}]} = FormsEquiv.diff(ex, ri)
    end

    test "boolean-case reorder does not collapse a non-boolean case" do
      # A case on integer literals must keep its clause order — reordering would
      # change first-match semantics, so the canonicalizer must leave it alone.
      forms = [
        {:function, 0, :h, 1,
         [
           {:clause, 0, [{:var, 0, :x}], [],
            [
              {:case, 0, {:var, 0, :x},
               [
                 {:clause, 0, [{:integer, 0, 1}], [], [{:atom, 0, :a}]},
                 {:clause, 0, [{:integer, 0, 2}], [], [{:atom, 0, :b}]}
               ]}
            ]}
         ]}
      ]

      # normalize is idempotent and order-preserving for non-boolean cases
      assert FormsEquiv.normalize(forms) == FormsEquiv.normalize(FormsEquiv.normalize(forms))

      [{:function, 0, :h, 1, [{:clause, 0, _, [], [{:case, 0, _, clauses}]}]}] =
        FormsEquiv.normalize(forms)

      assert [{:clause, 0, [{:integer, 0, 1}], [], _}, {:clause, 0, [{:integer, 0, 2}], [], _}] =
               clauses
    end
  end

  describe "normalization details" do
    test "drops Elixir-injected __info__/module_info and keeps only user funcs" do
      {ex, _ri} = both("  def only(x), do: x", "  pub def only(x Int53) Int53 := x")
      names = FormsEquiv.normalize(ex) |> Enum.map(fn {:function, _, n, _, _} -> n end)
      assert names == [:only]
    end
  end
end
