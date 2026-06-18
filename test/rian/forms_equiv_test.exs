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

  describe "verify/2 — per-function gate for the generate-and-verify loop" do
    test "a faithful multi-function port reports all :equiv and verified?" do
      {ex_bin, rian_bin} =
        both(
          "  def a(x), do: x + x\n  def b(x), do: -x",
          "  pub def a(x Int53) Int53 := x + x\n  pub def b(x Int53) Int53 := -x"
        )

      assert FormsEquiv.verify(ex_bin, rian_bin) == [{{:a, 1}, :equiv}, {{:b, 1}, :equiv}]
      assert FormsEquiv.verified?(ex_bin, rian_bin)
    end

    test "a wrong candidate is rejected (:diverges), not accepted" do
      {ex_bin, rian_bin} =
        both("  def a(x), do: x + x", "  pub def a(x Int53) Int53 := x * x")

      assert FormsEquiv.verify(ex_bin, rian_bin) == [{{:a, 1}, :diverges}]
      refute FormsEquiv.verified?(ex_bin, rian_bin)
    end

    test "a partial port marks the unported function :only_oracle" do
      {ex_bin, rian_bin} =
        both(
          "  def a(x), do: x + x\n  def b(x), do: -x",
          "  pub def a(x Int53) Int53 := x + x"
        )

      assert FormsEquiv.verify(ex_bin, rian_bin) == [{{:a, 1}, :equiv}, {{:b, 1}, :only_oracle}]
      refute FormsEquiv.verified?(ex_bin, rian_bin)
    end
  end

  describe "normalization details" do
    test "drops Elixir-injected __info__/module_info and keeps only user funcs" do
      {ex, _ri} = both("  def only(x), do: x", "  pub def only(x Int53) Int53 := x")
      names = FormsEquiv.normalize(ex) |> Enum.map(fn {:function, _, n, _, _} -> n end)
      assert names == [:only]
    end

    test "folds a negated float literal so unary-minus matches Elixir's constant" do
      # the Rian side emits `-1.5` as unary minus on the float literal; the safe
      # rewrite folds it to the literal `-1.5` so it matches the Elixir oracle.
      {ex, ri} = both("  def f, do: -1.5", "  pub def f() Float64 := -1.5")
      assert FormsEquiv.equivalent?(ex, ri)
    end
  end

  describe "abstract_code/1 — failure modes raise (debug_info contract)" do
    test "a .beam compiled without debug_info raises" do
      prev = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, false)
      [{mod, bin}] = Code.compile_string("defmodule FENoDbg do\n  def g, do: 1\nend")
      Code.put_compiler_option(:debug_info, prev)
      :code.purge(mod)
      :code.delete(mod)

      assert_raise RuntimeError, ~r/no abstract_code/, fn -> FormsEquiv.abstract_code(bin) end
    end

    test "a non-beam binary raises with the read error" do
      assert_raise RuntimeError, ~r/could not read abstract_code/, fn ->
        FormsEquiv.abstract_code(<<"not a beam">>)
      end
    end
  end
end
