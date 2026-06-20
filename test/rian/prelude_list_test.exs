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
    assert m.reduce([1, 2, 3], 0, fn x, acc -> acc - x end) ==
             Enum.reduce([1, 2, 3], 0, fn x, acc -> acc - x end)
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

  test "member / take / drop / count_by", %{mod: m} do
    assert m.member([1, 2, 3], 2)
    refute m.member([1, 2, 3], 9)
    assert m.take([1, 2, 3, 4], 2) == [1, 2]
    assert m.drop([1, 2, 3, 4], 2) == [3, 4]
    assert m.count_by([1, 2, 3, 4], fn x -> rem(x, 2) == 0 end) == 2
  end

  test "find returns an Option (Some/None), not a bare value/nil", %{mod: m} do
    assert m.find([1, 2, 3], fn x -> x > 1 end) == {:some, 2}
    assert m.find([1, 2, 3], fn x -> x > 9 end) == :none
  end

  test "sort_by orders by the comparator; uniq keeps the first occurrence", %{mod: m} do
    le = fn a, b -> a <= b end
    assert m.sort_by([3, 1, 2, 1], le) == [1, 1, 2, 3]
    assert m.sort_by([], le) == []
    assert m.uniq([1, 1, 2, 3, 3, 1]) == [1, 2, 3]
    # sort_by is stable for equal keys (by a key projection)
    by_fst = fn {a, _}, {b, _} -> a <= b end
    assert m.sort_by([{1, :a}, {0, :b}, {1, :c}], by_fst) == [{0, :b}, {1, :a}, {1, :c}]
  end

  describe "Dict.from_list and Str.trim (portable, ADR-0047)" do
    test "Dict.from_list builds a map; first occurrence wins on a duplicate" do
      {:ok, d} =
        Rian.Beam.load(File.read!("examples/rian/prelude_dict.rian"), :"Elixir.RianPreludeDict")

      assert d.from_list([{"a", 1}, {"b", 2}]) == %{"a" => 1, "b" => 2}
      # on a duplicate key the FIRST occurrence wins (the head `put` is outermost)
      assert d.from_list([{"a", 1}, {"a", 2}]) == %{"a" => 1}
      assert d.from_list([]) == %{}
    end

    test "Str.trim strips leading/trailing ASCII whitespace (self-contained, no List dep)" do
      {:ok, s} =
        Rian.Beam.load(File.read!("examples/rian/prelude_str.rian"), :"Elixir.RianPreludeStr")

      assert s.trim("  hi  ") == "hi"
      assert s.trim("\t a \n") == "a"
      assert s.trim("none") == "none"
    end

    test "Str.replace substitutes every occurrence (the portable String.replace/3)" do
      {:ok, s} =
        Rian.Beam.load(File.read!("examples/rian/prelude_str.rian"), :"Elixir.RianPreludeStrR")

      assert s.replace("a-b-c", "-", "_") == "a_b_c"
      assert s.replace(~s|"x"|, "\"", "\\\"") == ~s|\\"x\\"|
      assert s.replace("none", "z", "Q") == "none"
      # empty pattern is a no-op (terminates)
      assert s.replace("abc", "", "X") == "abc"
    end
  end

  describe "the additions are portable (reach + run on JS via node)" do
    test "sort_by/uniq/from_list/trim compile to JS and run under node" do
      node_run = fn src, expr ->
        case System.find_executable("node") do
          nil ->
            :no_node

          node ->
            js = Rian.JS.compile(src)
            p = Path.join(System.tmp_dir!(), "pl_#{System.unique_integer([:positive])}.mjs")
            File.write!(p, js <> "\nconsole.log(String(#{expr}));\n")
            {out, 0} = System.cmd(node, [p])
            File.rm(p)
            String.trim(out)
        end
      end

      list = File.read!("examples/rian/prelude_list.rian")
      dict = File.read!("examples/rian/prelude_dict.rian")
      str = File.read!("examples/rian/prelude_str.rian")

      assert node_run.(list, "sort_by([3,1,2], (a,b)=>a<=b).join(',')") in [:no_node, "1,2,3"]
      assert node_run.(list, "uniq([1,1,2,3,3]).join(',')") in [:no_node, "1,2,3"]
      assert node_run.(dict, "from_list([['a',1],['b',2]]).a") in [:no_node, "1"]
      assert node_run.(str, "trim('  hi  ')") in [:no_node, "hi"]
    end
  end
end
