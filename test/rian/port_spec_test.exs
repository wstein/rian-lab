defmodule Rian.PortSpecTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The `port.spec` feedback loop (ADR-0075, Levers C+D): a few human decisions —
  naming proposed sums, pinning residual unknowns — applied program-wide because each
  `Sum#`/`Unk####` placeholder is *shared* (one identity per logical type).
  """

  alias Rian.PortSpec

  describe "parse/1" do
    test "reads `Placeholder = Type` lines, ignoring comments and blanks" do
      spec = """
      # a comment
      Sum1 = Expr

      Sum2 = Pat
      Unk0042 = String
      """

      assert PortSpec.parse(spec) == %{"Sum1" => "Expr", "Sum2" => "Pat", "Unk0042" => "String"}
    end

    test "skips lines with no `=` and blank right-hand sides" do
      assert PortSpec.parse("Sum1\nSum2 =\nSum3 = Pat") == %{"Sum3" => "Pat"}
    end

    test "strips an INLINE comment from the value (not part of the type)" do
      assert PortSpec.parse("Sum1 = Expr   # the E* nodes\nUnk0607 = Vec(Tok) # tokens") ==
               %{"Sum1" => "Expr", "Unk0607" => "Vec(Tok)"}
    end
  end

  describe "apply_subs/2" do
    test "substitutes a placeholder with its decision" do
      subs = %{"Sum1" => "Expr"}
      assert PortSpec.apply_subs("Sum1", subs) == "Expr"
    end

    test "substitutes placeholders nested in a compound type, program-wide" do
      subs = %{"Sum1" => "Expr", "Unk0042" => "String"}
      assert PortSpec.apply_subs("Map(Unk0042, Vec(Sum1))", subs) == "Map(String, Vec(Expr))"
    end

    test "leaves undecided placeholders and ordinary types untouched" do
      subs = %{"Sum1" => "Expr"}
      assert PortSpec.apply_subs("Vec(Unk0099)", subs) == "Vec(Unk0099)"
      assert PortSpec.apply_subs("Int53", subs) == "Int53"
    end

    test "an empty spec is the identity" do
      assert PortSpec.apply_subs("Sum1", %{}) == "Sum1"
    end
  end

  describe "template/2" do
    test "lists each proposed sum (with members) and each unknown (with sites)" do
      data = %{
        sums: [["ENum", "ECall"]],
        wp: %{unks: %{"Unk0042" => [{{"M", "f", 1}, "p0"}, {{"M", "g", 1}, "ret"}]}}
      }

      out = PortSpec.template(data)
      assert out =~ "co-occur in dispatch: ENum | ECall"
      assert out =~ "Sum1 = "
      assert out =~ "# 2 site(s)"
      assert out =~ "Unk0042 = "
    end

    test "keeps already-decided values (idempotent against an edited spec)" do
      data = %{sums: [["ENum", "ECall"]], wp: %{unks: %{}}}
      assert PortSpec.template(data, %{"Sum1" => "Expr"}) =~ "Sum1 = Expr"
    end
  end
end
