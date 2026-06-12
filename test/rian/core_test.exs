defmodule Rian.CoreTest do
  use ExUnit.Case, async: true

  alias Rian.Core
  alias Rian.Core.{PAtom, PCtor, PList, PLit, PTuple, PVar, PWild}

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
end
