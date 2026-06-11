defmodule Rian.PatternLowerTest do
  use ExUnit.Case, async: true
  alias Rian.Exhaustiveness, as: E
  alias Rian.PatternLower, as: L

  defp env_opt, do: E.add_type(E.base_env(), :option, [{:some, 1}, {:none, 0}])
  defp env_point, do: L.add_struct(E.base_env(), "Point", [:x, :y])

  describe "name conversion" do
    test "PascalCase and compound names snake-case correctly" do
      assert L.to_snake("Circle") == :circle
      assert L.to_snake("JNum") == :j_num
      assert L.to_snake("JArr") == :j_arr
      assert L.to_snake(:already_snake) == :already_snake
    end
  end

  describe "coverage-irrelevant binders normalize to wildcard" do
    test "variable -> :wild" do
      assert L.lower({:var, :x}, E.base_env()) == {:wild, false}
    end

    test "as-pattern keeps the inner pattern, drops the binder" do
      assert L.lower({:as, :p, {:ctor, "Some", [{:var, :y}]}}, env_opt()) ==
               {{:ctor, :some, [:wild]}, false}
    end
  end

  describe "pin lowering" do
    test "^e becomes a wildcard AND introduces a guard" do
      assert L.lower({:pin, {:var, :expected}}, E.base_env()) == {:wild, true}
    end

    test "a clause containing a pin is marked guarded (excluded from exhaustiveness)" do
      clause =
        L.lower_clause(%{pats: [{:pin, :exp}, {:var, :actual}], guard: false}, E.base_env())

      assert clause == %{pat: [:wild, :wild], guard: true}

      # one pinned 2-arg clause => non-exhaustive (the guarded clause cannot cover)
      r = E.analyze([clause], 2, E.base_env())
      refute r.exhaustive?
    end
  end

  describe "literals, tuples, constructors" do
    test "literal" do
      assert L.lower({:lit, 0}, E.base_env()) == {{:ctor, {:lit, 0}, []}, false}
    end

    test "tuple decomposes positionally" do
      assert L.lower({:tuple, [{:lit, 1}, {:var, :y}]}, E.base_env()) ==
               {{:ctor, {:tuple, 2}, [{:ctor, {:lit, 1}, []}, :wild]}, false}
    end

    test "constructor name is snaked and args lowered" do
      assert L.lower({:ctor, "Some", [{:var, :x}]}, env_opt()) ==
               {{:ctor, :some, [:wild]}, false}
    end
  end

  describe "struct patterns" do
    test "named fields are reordered to declared order; missing fields -> wildcard" do
      # declared order is [:x, :y]; pattern only mentions y
      assert L.lower({:struct, "Point", [{:y, {:var, :a}}]}, env_point()) ==
               {{:ctor, :point, [:wild, :wild]}, false}
    end

    test "a single struct clause is exhaustive (one constructor)" do
      clause = L.lower_clause(%{pats: [{:struct, "Point", []}], guard: false}, env_point())
      assert E.analyze([clause], 1, env_point()).exhaustive?
    end
  end

  describe "list desugaring" do
    test "[] -> nil ctor" do
      assert L.lower({:list, [], :close}, E.base_env()) == {{:ctor, nil, []}, false}
    end

    test "[h | t] -> cons(_, _)" do
      assert L.lower({:list, [{:var, :h}], {:tail, {:var, :t}}}, E.base_env()) ==
               {{:ctor, :cons, [:wild, :wild]}, false}
    end

    test "[a, b | rest] -> nested cons" do
      p = {:list, [{:var, :a}, {:var, :b}], {:tail, {:var, :rest}}}

      assert L.lower(p, E.base_env()) ==
               {{:ctor, :cons, [:wild, {:ctor, :cons, [:wild, :wild]}]}, false}
    end
  end

  describe "map patterns (BEAM-only)" do
    test "empty map is irrefutable" do
      assert L.lower({:map, []}, E.base_env()) == {:wild, false}
    end

    test "non-empty map is refutable (introduces a guard)" do
      assert L.lower({:map, [{:k, {:var, :v}}]}, E.base_env()) == {:wild, true}
    end
  end

  describe "end-to-end: surface clauses -> lower -> analyze" do
    test "Option match missing None is detected after lowering" do
      clauses =
        [%{pats: [{:ctor, "Some", [{:var, :x}]}], guard: false}]
        |> Enum.map(&L.lower_clause(&1, env_opt()))

      r = E.analyze(clauses, 1, env_opt())
      refute r.exhaustive?
      assert E.render(r.missing) == "None"
    end

    test "Option match with Some + None is exhaustive after lowering" do
      clauses =
        [
          %{pats: [{:ctor, "Some", [{:var, :x}]}], guard: false},
          %{pats: [{:ctor, "None", []}], guard: false}
        ]
        |> Enum.map(&L.lower_clause(&1, env_opt()))

      assert E.analyze(clauses, 1, env_opt()).exhaustive?
    end
  end
end
