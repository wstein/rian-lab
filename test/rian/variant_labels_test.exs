defmodule Rian.VariantLabelsTest do
  use ExUnit.Case, async: true

  alias Rian.Core
  alias Rian.Core.{PCtor, PVar}
  alias Rian.VariantLabels

  defp meta(src), do: src |> Rian.Decl.parse() |> VariantLabels.meta()

  describe "meta/1" do
    test "maps each ctor to its enum, per-field labels, and `named` flag" do
      m = meta("type Shape := Circle(radius Float64) | Square(side Float64)")

      assert m["Circle"] == %{enum: "Shape", ctor: "Circle", named: true, labels: ["radius"]}
      assert m["Square"] == %{enum: "Shape", ctor: "Square", named: true, labels: ["side"]}
    end

    test "an anonymous field is a `nil` label and makes the variant un-`named`" do
      m = meta("type Box := Wrap(Int53) | Empty")

      assert m["Wrap"] == %{enum: "Box", ctor: "Wrap", named: false, labels: [nil]}
      # a nullary variant is not `named` (no fields) and has an empty label list
      assert m["Empty"] == %{enum: "Box", ctor: "Empty", named: false, labels: []}
    end

    test "a partially-labeled variant is un-`named` but keeps the per-field labels" do
      m = meta("type Tag := Named(id Int53, Int53)")
      assert m["Named"] == %{enum: "Tag", ctor: "Named", named: false, labels: ["id", nil]}
    end

    test "collects variants declared inside a `mod`" do
      m = meta("mod M do\n  type Color := Red | Green\nend")
      assert Map.keys(m) |> Enum.sort() == ["Green", "Red"]
      assert m["Red"].enum == "Color"
    end

    test "is empty for a program with no sum types" do
      assert meta("pub def id(x Int53) Int53 := x") == %{}
    end
  end

  describe "bake_pats/2" do
    setup do
      %{meta: meta("type Shape := Circle(radius Float64) | Square(side Float64)")}
    end

    test "fills a ctor pattern's labels from the meta", %{meta: m} do
      baked = VariantLabels.bake_pats(Core.from_pat({:ctor, "Circle", [{:var, "r"}]}), m)
      assert %PCtor{ctor: "Circle", labels: ["radius"], args: [%PVar{name: "r"}]} = baked
    end

    test "recurses into nested ctor patterns", %{meta: m} do
      # `Square(Circle(r))` is not type-correct, but exercises the structural recursion
      inner = {:ctor, "Circle", [{:var, "r"}]}
      baked = VariantLabels.bake_pats(Core.from_pat({:ctor, "Square", [inner]}), m)

      assert %PCtor{
               ctor: "Square",
               labels: ["side"],
               args: [%PCtor{ctor: "Circle", labels: ["radius"]}]
             } = baked
    end

    test "leaves a ctor not in the meta untouched (labels stay nil)", %{meta: m} do
      baked = VariantLabels.bake_pats(Core.from_pat({:ctor, "Unknown", [{:var, "x"}]}), m)
      assert %PCtor{ctor: "Unknown", labels: nil} = baked
    end

    test "walks lists and tuples of nodes", %{meta: m} do
      pat = Core.from_pat({:ctor, "Circle", [{:var, "r"}]})
      assert [%PCtor{labels: ["radius"]}] = VariantLabels.bake_pats([pat], m)
      assert {%PCtor{labels: ["radius"]}, :other} = VariantLabels.bake_pats({pat, :other}, m)
    end

    test "passes plain leaves through unchanged", %{meta: m} do
      assert VariantLabels.bake_pats(:atom, m) == :atom
      assert VariantLabels.bake_pats(42, m) == 42
    end
  end
end
