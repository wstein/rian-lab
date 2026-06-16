defmodule Rian.CoreTest do
  use ExUnit.Case, async: true

  alias Rian.Core
  alias Rian.Core.{PAtom, PCtor, PList, PLit, PTuple, PVar, PWild}
  alias Rian.Core.{EBin, EBlock, ECall, EId, EIf, ENum, ETuple}

  describe "from_pat/1 — surface tuple → typed core pattern (ADR-0050)" do
    test "every leaf pattern kind translates" do
      assert Core.from_pat(:wild) == %PWild{}
      assert Core.from_pat({:var, "x"}) == %PVar{name: "x"}
      assert Core.from_pat({:lit, 7}) == %PLit{value: 7}
      assert Core.from_pat({:lit, "hi"}) == %PLit{value: "hi"}
      assert Core.from_pat({:atom, "ok"}) == %PAtom{name: "ok"}
    end

    test "nested tuple / ctor / list patterns translate recursively" do
      assert Core.from_pat({:tuple, [{:atom, "ok"}, {:var, "v"}]}) ==
               %PTuple{elems: [%PAtom{name: "ok"}, %PVar{name: "v"}]}

      assert Core.from_pat({:ctor, "Circle", [{:var, "r"}]}) ==
               %PCtor{ctor: "Circle", args: [%PVar{name: "r"}]}

      assert Core.from_pat({:list, [{:var, "h"}], {:tail, {:var, "t"}}}) ==
               %PList{elems: [%PVar{name: "h"}], tail: %PVar{name: "t"}}

      assert Core.from_pat({:list, [], :close}) == %PList{elems: [], tail: :close}
    end

    test "core nodes carry a nil `type` until the checker fills it (ADR-0050 §3)" do
      assert %PVar{type: nil} = Core.from_pat({:var, "x"})
      assert %PCtor{type: nil} = Core.from_pat({:ctor, "None", []})
    end
  end

  describe "from_expr/1 — surface tuple → typed core expression (ADR-0050)" do
    test "leaf and operator expressions translate recursively" do
      assert Core.from_expr({:num, "42"}) == %ENum{text: "42"}

      assert Core.from_expr({:bin, "+", {:id, "a"}, {:num, "1"}}) ==
               %EBin{op: "+", left: %EId{name: "a"}, right: %ENum{text: "1"}}

      assert Core.from_expr({:call, {:id, "f"}, [{:id, "x"}]}) ==
               %ECall{fun: %EId{name: "f"}, args: [%EId{name: "x"}]}

      assert Core.from_expr({:tuple, [{:atom, "ok"}, {:id, "v"}]}) ==
               %ETuple{elems: [%Core.EAtom{name: "ok"}, %EId{name: "v"}]}
    end

    test "block / if translate, with statement and branch nodes" do
      assert Core.from_expr({:block, [{:bind, "a", {:num, "1"}}, {:expr, {:id, "a"}}]}) ==
               %EBlock{stmts: [{:bind, "a", %ENum{text: "1"}}, {:expr, %EId{name: "a"}}]}

      assert %EIf{cond: %EId{name: "c"}, then: %EBlock{}, else: %EBlock{}} =
               Core.from_expr({:if, {:id, "c"}, {:block, []}, {:block, []}})
    end

    test "an expression node carries a nil `type` until the checker fills it" do
      assert %ENum{type: nil} = Core.from_expr({:num, "1"})
    end
  end

  describe "first_unsupported/2 — generic core walk for the partial emitters" do
    @unsup %{ETuple => "a tuple", Core.EMap => "a map"}

    test "returns the label of the first node whose struct is in the map" do
      tree = Core.from_expr({:tuple, [{:atom, "ok"}, {:id, "v"}]})
      assert Core.first_unsupported(tree, @unsup) == "a tuple"
    end

    test "descends into nested struct / list / tuple children to find a match" do
      # the unsupported `ETuple` is buried in a call argument list
      tree = Core.from_expr({:call, {:id, "f"}, [{:tuple, [{:id, "a"}]}]})
      assert Core.first_unsupported(tree, @unsup) == "a tuple"
    end

    test "returns nil when no node is unsupported" do
      tree = Core.from_expr({:bin, "+", {:id, "a"}, {:num, "1"}})
      assert Core.first_unsupported(tree, @unsup) == nil
    end
  end
end
