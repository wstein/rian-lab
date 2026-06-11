defmodule Rian.ExhaustivenessTest do
  use ExUnit.Case, async: true
  alias Rian.Exhaustiveness, as: E

  # pattern constructors
  defp w, do: :wild
  defp c(id, args \\ []), do: {:ctor, id, args}
  defp lit(v), do: {:ctor, {:lit, v}, []}
  defp lnil, do: {:ctor, nil, []}
  defp cons(h, t), do: {:ctor, :cons, [h, t]}
  defp arm(pat, guard \\ false), do: %{pat: pat, guard: guard}

  defp env_option, do: E.add_type(E.base_env(), :option, [{:some, 1}, {:none, 0}])
  defp env_shape, do: E.add_type(E.base_env(), :shape, [{:circle, 1}, {:square, 1}])
  defp env_tree, do: E.add_type(E.base_env(), :tree, [{:leaf, 0}, {:node, 3}])

  describe "exhaustiveness — finite types" do
    test "bool: both literals are exhaustive" do
      r = E.analyze([arm([c(true)]), arm([c(false)])], 1, E.base_env())
      assert r.exhaustive?
      assert r.missing == nil
    end

    test "bool: missing `false` is reported with a witness" do
      r = E.analyze([arm([c(true)])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "false"
    end

    test "option: Some + None is exhaustive" do
      r = E.analyze([arm([c(:some, [w()])]), arm([c(:none)])], 1, env_option())
      assert r.exhaustive?
    end

    test "option: missing None -> witness `None`" do
      r = E.analyze([arm([c(:some, [w()])])], 1, env_option())
      refute r.exhaustive?
      assert E.render(r.missing) == "None"
    end

    test "shape: missing Square -> witness `Square(_)`" do
      r = E.analyze([arm([c(:circle, [w()])])], 1, env_shape())
      refute r.exhaustive?
      assert E.render(r.missing) == "Square(_)"
    end
  end

  describe "lists" do
    test "nil + cons is exhaustive" do
      r = E.analyze([arm([lnil()]), arm([cons(w(), w())])], 1, E.base_env())
      assert r.exhaustive?
    end

    test "only nil -> witness `[_ | _]`" do
      r = E.analyze([arm([lnil()])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "[_ | _]"
    end

    test "only cons -> witness `[]`" do
      r = E.analyze([arm([cons(w(), w())])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "[]"
    end
  end

  describe "nested constructors" do
    test "Tree with only Leaf and Node(Leaf,_,_) is non-exhaustive (deep witness)" do
      arms = [arm([c(:leaf)]), arm([c(:node, [c(:leaf), w(), w()])])]
      r = E.analyze(arms, 1, env_tree())
      refute r.exhaustive?
      # the uncovered case is a Node whose left child is itself a Node
      assert E.render(r.missing) =~ "Node(Node("
    end

    test "Tree with Leaf and Node(_,_,_) is exhaustive" do
      arms = [arm([c(:leaf)]), arm([c(:node, [w(), w(), w()])])]
      assert E.analyze(arms, 1, env_tree()).exhaustive?
    end
  end

  describe "primitives are infinite — require a wildcard" do
    test "two int literals are NOT exhaustive" do
      r = E.analyze([arm([lit(0)]), arm([lit(1)])], 1, E.base_env())
      refute r.exhaustive?
      assert E.render(r.missing) == "_"
    end

    test "literals plus wildcard ARE exhaustive" do
      r = E.analyze([arm([lit(0)]), arm([lit(1)]), arm([w()])], 1, E.base_env())
      assert r.exhaustive?
    end
  end

  describe "guards do not count toward exhaustiveness" do
    test "a guarded Some(_) leaves the match non-exhaustive" do
      arms = [arm([c(:some, [w()])], true), arm([c(:none)])]
      r = E.analyze(arms, 1, env_option())
      refute r.exhaustive?
      assert E.render(r.missing) == "Some(_)"
    end
  end

  describe "reachability" do
    test "a clause after a wildcard is unreachable" do
      arms = [arm([w()]), arm([c(:leaf)])]
      assert E.analyze(arms, 1, env_tree()).unreachable == [1]
    end

    test "a guarded clause does NOT shadow a later identical clause" do
      arms = [arm([c(:some, [w()])], true), arm([c(:some, [w()])], false)]
      assert E.analyze(arms, 1, env_option()).unreachable == []
    end

    test "an exact duplicate after an unguarded clause is unreachable" do
      arms = [arm([c(:none)]), arm([c(:none)])]
      assert E.analyze(arms, 1, env_option()).unreachable == [1]
    end
  end

  describe "multi-argument clauses (tuple matrix)" do
    test "wildcard fallback row makes a 2-arg match exhaustive" do
      arms = [arm([lit(0), lit(0)]), arm([w(), w()])]
      assert E.analyze(arms, 2, E.base_env()).exhaustive?
    end

    test "single (0,0) clause is non-exhaustive" do
      r = E.analyze([arm([lit(0), lit(0)])], 2, E.base_env())
      refute r.exhaustive?
    end
  end
end
