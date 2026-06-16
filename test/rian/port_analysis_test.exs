defmodule Rian.PortAnalysisTest do
  use ExUnit.Case, async: true

  alias Rian.PortAnalysis

  defp md(sources), do: sources |> PortAnalysis.analyze() |> PortAnalysis.to_markdown()

  describe "sum-type clustering (the non-local decision)" do
    test "structs that co-occur in a case dispatch are proposed as one sum" do
      src = """
      defmodule M do
        def f(x) do
          case x do
            %ENum{} -> 1
            %EIf{} -> 2
          end
        end
      end
      """

      out = md([{"m.ex", src}])
      assert out =~ ~r/Cluster 1.*EIf \| ENum/
    end

    test "structs dispatched across MULTIPLE files cluster together (non-local)" do
      # construction in one file, dispatch split across two others — the evidence
      # is non-local, which is the whole point.
      core = "defmodule Core do\n  def mk, do: %A{}\nend"
      check = "defmodule Check do\n  def c(%A{}), do: 1\n  def c(%B{}), do: 2\nend"
      lower = "defmodule Lower do\n  def l(%B{}), do: 3\n  def l(%C{}), do: 4\nend"

      out = md([{"core.ex", core}, {"check.ex", check}, {"lower.ex", lower}])
      # A–B (from check) and B–C (from lower) transitively merge into one sum.
      assert out =~ ~r/Cluster 1.*A \| B \| C/
    end

    test "a struct never dispatched is listed standalone" do
      src = "defmodule M do\n  def mk, do: %Solo{x: 1}\nend"
      out = md([{"m.ex", src}])
      assert out =~ "**Standalone structs**"
      assert out =~ "`Solo`"
    end
  end

  describe "error-idiom inventory (the Elixir↔Rian gap, made reviewable)" do
    test "classifies atom / string / ctor error tags with proposals" do
      src = """
      defmodule M do
        def a, do: {:error, :not_found}
        def b, do: {:error, "boom"}
        def c, do: {:error, DivByZero}
      end
      """

      out = md([{"m.ex", src}])
      assert out =~ "`:not_found` (atom)"
      assert out =~ "NotFound"
      assert out =~ "**NEEDS DECISION**"
      assert out =~ "`DivByZero` ✓ already a variant"
    end
  end

  describe "reach annotation" do
    test "flags types that pin off a target" do
      assert PortAnalysis.reach_note("Int53") == "✓ all 4"
      assert PortAnalysis.reach_note("Int64") =~ "off :js"
      assert PortAnalysis.reach_note("Int") =~ "off :rs"
      assert PortAnalysis.reach_note("Fn(Int53, Int53)") =~ "off :rs"
    end
  end

  describe "inference summary surfaces auto-fills + holes" do
    test "an inferred numeric function appears under section 1, a tuple under holes" do
      src = "defmodule M do\n  def f(x), do: x + 1\n  def g(x), do: {:a, x}\nend"
      out = md([{"m.ex", src}])
      assert out =~ "`f/1`"
      assert out =~ "Int53"
      assert out =~ "`g/1`"
    end
  end
end
