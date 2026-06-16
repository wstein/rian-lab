defmodule Rian.PreludeListTest do
  # async: false — loads a real BEAM module into the VM.
  use ExUnit.Case, async: false

  @moduledoc """
  The `List` prelude (`examples/rian/prelude_list.rian`) is portable Rian — these
  tests compile it to a real `.beam` via `Rian.Beam` and exercise the higher-order
  combinators that the transpiler's `@stdlib` table maps `Enum.*` onto, so the
  mapping targets are proven to exist and behave like their Elixir originals.
  """

  setup_all do
    src = File.read!("examples/rian/prelude_list.rian")
    {:ok, mod} = Rian.Beam.load(src, :"Elixir.RianPreludeList")
    {:ok, mod: mod}
  end

  test "map / filter / reject", %{mod: m} do
    assert m.map([1, 2, 3], fn x -> x * 10 end) == [10, 20, 30]
    assert m.filter([1, 2, 3, 4], fn x -> rem(x, 2) == 0 end) == [2, 4]
    assert m.reject([1, 2, 3, 4], fn x -> rem(x, 2) == 0 end) == [1, 3]
  end

  test "reduce matches Enum.reduce order f(elem, acc)", %{mod: m} do
    assert m.reduce([1, 2, 3, 4], 0, fn x, acc -> x + acc end) == 10
    # subtraction exposes argument order: ((((0)-1)... ) reduces left-to-right
    assert m.reduce([1, 2, 3], 0, fn x, acc -> acc - x end) == Enum.reduce([1, 2, 3], 0, fn x, acc -> acc - x end)
  end

  test "concat / flat_map / reverse", %{mod: m} do
    assert m.concat([1, 2], [3, 4]) == [1, 2, 3, 4]
    assert m.flat_map([1, 2], fn x -> [x, x] end) == [1, 1, 2, 2]
    assert m.reverse([1, 2, 3]) == [3, 2, 1]
  end

  test "any_by / all_by", %{mod: m} do
    assert m.any_by([1, 2, 3], fn x -> x > 2 end)
    refute m.any_by([1, 2, 3], fn x -> x > 9 end)
    assert m.all_by([1, 2, 3], fn x -> x > 0 end)
    refute m.all_by([1, 2, 3], fn x -> x > 1 end)
  end

  test "join / map_join match Enum", %{mod: m} do
    assert m.join(["a", "b", "c"], ", ") == "a, b, c"
    assert m.join([], ", ") == ""
    assert m.map_join([1, 2, 3], "-", fn x -> "v#{x}" end) == "v1-v2-v3"
  end
end
