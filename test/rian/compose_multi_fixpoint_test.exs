defmodule Rian.ComposeMultiFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 3 (ADR-0063 Step 3): widens the composed subset from
  # a single-clause `def` (compose_decl_fixpoint_test) to a whole MULTI-CLAUSE,
  # self-recursive function. `selfhost_compose_multi.rian` splits the clause
  # sequence (`def` is its own token), reads literal/variable head patterns, parses
  # function calls, and assembles ONE multi-clause Erlang function form in Rian —
  # compile_fn(s) = emit_fn(parse_clauses(lex(s))).
  #
  # The fixpoint loads + RUNS the composed function and asserts it computes the same
  # values as `Rian.Beam` on the same source — recursion, pattern dispatch, and
  # precedence all surviving end to end. The only Elixir is the :module/:export
  # attribute boilerplate (name + arity read back from the Rian-produced form).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_compose_multi.rian"), :rian_compose_multi)

    {:ok, mod: mod}
  end

  # build, compile, and load a module from the Rian-produced multi-clause form.
  defp compose_module(mod, src, modname) do
    {:function, _l, name, arity, _clauses} = func_form = mod.compile_fn(src)

    forms = [
      {:attribute, 0, :module, modname},
      {:attribute, 0, :export, [{name, arity}]},
      func_form
    ]

    {:ok, ^modname, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^modname} = :code.load_binary(modname, ~c"nofile", bin)
    {modname, name, arity}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_multi_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped clauses), reference source (typed sig + clauses),
  #  function name, [args to run on both]}. Literal-pattern heads have no name to
  # type, so the reference carries a single leading signature line.
  @corpus [
    {
      "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
      "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
      :fib,
      [[0], [1], [2], [5], [10], [15]]
    },
    {
      "def fact(0) := 1\ndef fact(n) := n * fact(n - 1)",
      "def fact(n Int53) Int53\ndef fact(0) := 1\ndef fact(n) := n * fact(n - 1)",
      :fact,
      [[0], [1], [5], [8]]
    },
    {
      "def sumto(0) := 0\ndef sumto(n) := n + sumto(n - 1)",
      "def sumto(n Int53) Int53\ndef sumto(0) := 0\ndef sumto(n) := n + sumto(n - 1)",
      :sumto,
      [[0], [4], [10], [100]]
    },
    # single-clause still works through the wider pipeline
    {
      "def double(n) := n + n",
      "def double(n Int53) Int53 := n + n",
      :double,
      [[0], [21], [-5]]
    }
  ]

  describe "composition fixpoint — a multi-clause recursive fn (Rian) runs identically to Elixir" do
    test "the composed function computes the same values as Rian.Beam's", %{mod: mod} do
      for {rian_src, ref_src, fname, inputs} <- @corpus do
        {composed, name, _arity} =
          compose_module(mod, rian_src, :"cmp_multi_#{System.unique_integer([:positive])}")

        assert name == fname, "composed function name diverged for `#{fname}`"
        ref = ref_module(ref_src)

        for args <- inputs do
          assert apply(composed, fname, args) == apply(ref, fname, args),
                 "composed `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — multi-clause dispatch, patterns, and calls are all built in Rian" do
    test "compile_fn emits one {:function,…} with a clause per `def`", %{mod: mod} do
      assert mod.compile_fn(
               "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)"
             ) ==
               {:function, 1, :fib, 1,
                [
                  {:clause, 1, [{:integer, 1, 0}], [], [{:integer, 1, 0}]},
                  {:clause, 1, [{:integer, 1, 1}], [], [{:integer, 1, 1}]},
                  {:clause, 1, [{:var, 1, :N}], [],
                   [
                     {:op, 1, :+,
                      {:call, 1, {:atom, 1, :fib},
                       [{:op, 1, :-, {:var, 1, :N}, {:integer, 1, 1}}]},
                      {:call, 1, {:atom, 1, :fib},
                       [{:op, 1, :-, {:var, 1, :N}, {:integer, 1, 2}}]}}
                   ]}
                ]}
    end

    test "literal heads become integer patterns, variable heads become var patterns", %{mod: mod} do
      {:function, 1, :f, 1, [c0, c1]} =
        mod.compile_fn("def f(0) := 1\ndef f(x) := x")

      assert {:clause, 1, [{:integer, 1, 0}], [], _} = c0
      assert {:clause, 1, [{:var, 1, :X}], [], _} = c1
    end

    test "a runtime fib actually recurses to the right value", %{mod: mod} do
      {m, :fib, 1} =
        compose_module(
          mod,
          "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
          :cmp_fib_run
        )

      assert Enum.map(0..10, &m.fib/1) == [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
    end
  end
end
