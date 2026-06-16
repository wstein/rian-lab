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

  describe "whole-program section 2 — declarations with shared Unk + struct sums" do
    test "fully-resolved fn → section 1; an unknown-return fn → an editable decl" do
      src = "defmodule M do\n  def f(x), do: x + 1\n  def g(x), do: {:a, x}\nend"
      out = md([{"m.ex", src}])
      # f/1 resolves to Int53 (section 1); g/1 returns a tuple → a decl with an Unk
      assert out =~ "`f/1`"
      assert out =~ "Int53"
      assert out =~ "pub def g(x "
      assert out =~ "Unk"
    end

    test "a struct-returning fn resolves its return to the proposed sum; Unk is shared" do
      core = "defmodule Core do\n  def lit(n), do: %ENum{v: n}\nend"
      check = "defmodule Check do\n  def i(%ENum{}), do: 1\n  def i(%EIf{}), do: 2\nend"
      out = md([{"core.ex", core}, {"check.ex", check}])
      # ENum dispatched in Check → a sum; lit returns %ENum{} → that sum
      assert out =~ ~r/pub def lit\(n Unk\d+\) Sum1/
      assert out =~ ~r/pub def i\(p0 Sum1\)/
      assert out =~ "Placeholder index"
    end

    test "a cross-function unknown shares one Unk name across both sites" do
      a = "defmodule A do\n  def f(x), do: g(x)\n  def g(y), do: h(y)\nend"
      b = "defmodule B do\n  def h(z), do: z\nend"
      out = md([{"a.ex", a}, {"b.ex", b}])
      # x → g's param → h's param → h's return → g/f returns: one shared Unk, many sites
      assert out =~ ~r/`Unk0001` \| [2-9] \|/
    end
  end
end
