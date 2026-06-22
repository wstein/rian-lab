defmodule Rian.CheckerFixpointTest do
  @moduledoc """
  Checker fixpoint with teeth (ADR-0063 §4 — Samir's "inert checker"
  critique). The Rian-written type-checker (`check.rian`) is run, compiled to
  real `.beam`, over a golden corpus of well- and ill-typed toy `Expr` programs; its
  verdicts must match exactly. The **teeth**: ill-typed programs must be *rejected*
  (`Bad`), so a checker that regressed to "always `Ok`" fails — the verification is not
  vacuous. This is the discipline the existing lexer/parser fixpoints already carry,
  extended to one of the two untested-fragility areas.
  """
  use ExUnit.Case, async: false

  alias Rian.Beam

  # Expr sum -> tagged tuples (the BEAM lowering): Num→{:num,n}, Bln→{:bln,b},
  # Var→{:var,s}, Add/Lt→{:tag,a,b}, If→{:if,c,t,e}, Let→{:let,name,rhs,body}.
  setup do
    {:ok, chk} =
      Beam.load(File.read!("test/fixtures/rian/check.rian"), :rian_checker_fixpoint)

    {:ok, chk: chk}
  end

  # well-typed: an Expr and the type the checker must infer.
  @well_typed [
    {{:num, 1}, "Int"},
    {{:bln, true}, "Bool"},
    {{:add, {:num, 1}, {:num, 2}}, "Int"},
    {{:lt, {:num, 1}, {:num, 2}}, "Bool"},
    {{:if, {:lt, {:num, 1}, {:num, 2}}, {:num, 3}, {:num, 4}}, "Int"},
    {{:let, "x", {:num, 5}, {:add, {:var, "x"}, {:num, 1}}}, "Int"}
  ]

  # ill-typed: an Expr and the exact structured error the checker must report.
  @ill_typed [
    {{:add, {:num, 1}, {:bln, true}}, "type error in add: expected Int, got Bool"},
    {{:lt, {:bln, true}, {:num, 1}}, "type error in lt: expected Int, got Bool"},
    {{:if, {:num, 1}, {:num, 0}, {:num, 1}}, "type error in if-cond: expected Bool, got Int"},
    {{:if, {:lt, {:num, 1}, {:num, 2}}, {:num, 10}, {:bln, true}},
     "type error in if-branch: expected Int, got Bool"}
  ]

  describe "check.rian — the Rian checker agrees with the golden verdicts" do
    test "well-typed programs infer the expected type", %{chk: chk} do
      for {expr, ty} <- @well_typed,
          do: assert(chk.describe(chk.check(expr)) == ty, "for #{inspect(expr)}")
    end

    test "ill-typed programs report the exact structured mismatch", %{chk: chk} do
      for {expr, msg} <- @ill_typed,
          do: assert(chk.describe(chk.check(expr)) == msg, "for #{inspect(expr)}")
    end
  end

  describe "teeth — the checker genuinely rejects type errors (not vacuously Ok)" do
    test "every ill-typed program is a structured error, never a type", %{chk: chk} do
      for {expr, _} <- @ill_typed do
        verdict = chk.describe(chk.check(expr))

        assert verdict =~ "type error",
               "#{inspect(expr)} is ill-typed but the checker accepted it (#{verdict}) — " <>
                 "a regressed/vacuous checker would pass here"

        refute verdict in ["Int", "Bool"]
      end
    end

    test "a well-typed program and its ill-typed mutation get different verdicts", %{chk: chk} do
      good = {:add, {:num, 1}, {:num, 2}}
      bad = {:add, {:num, 1}, {:bln, true}}

      assert chk.describe(chk.check(good)) == "Int"
      assert chk.describe(chk.check(bad)) =~ "type error"
      assert chk.describe(chk.check(good)) != chk.describe(chk.check(bad))
    end

    test "the `Bad` verdict carries the structured Mismatch fields (op/expected/got)", %{chk: chk} do
      # check/1 returns the Check sum directly: Bad(Mismatch) -> {:bad, %{...}}
      assert {:bad, mismatch} = chk.check({:add, {:num, 1}, {:bln, true}})
      assert mismatch.op == "add"
      assert mismatch.expected == :t_int
      assert mismatch.got == :t_bool
    end
  end
end
