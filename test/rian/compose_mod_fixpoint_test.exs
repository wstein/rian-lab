defmodule Rian.ComposeModFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 4 (ADR-0063 Step 3): the composed pipeline now emits
  # an ENTIRE module. `compose_mod.rian` groups the flat clause stream into
  # per-function groups and assembles the complete `:compile.forms` input — the
  # `:module`/`:export` attributes AND every `{:function,…}` form — as native Rian
  # tuple literals. compile_module(src, modname) returns that form list directly.
  #
  # The decisive difference from rungs 1-3: this test authors NO Erlang form by
  # hand. It passes the Rian-produced list straight to `:compile.forms`, loads it,
  # and RUNS it — asserting behaviour identical to `Rian.Beam` on the same source,
  # across multi-function, multi-clause, and mutually-recursive modules.

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("compiler/compose_mod.rian"), :rian_compose_mod)

    {:ok, mod: mod}
  end

  # the whole module form list comes from Rian — no hand-authored Elixir forms.
  defp compose_module(mod, src, modname) do
    forms = mod.compile_module(src, modname)
    {:ok, ^modname, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^modname} = :code.load_binary(modname, ~c"nofile", bin)
    modname
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_mod_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped), reference source (typed sigs), [{fn, args}] to run}.
  @corpus [
    {
      "def square(n) := n * n\ndef sumsq(a, b) := square(a) + square(b)",
      "def square(n Int53) Int53 := n * n\ndef sumsq(a Int53, b Int53) Int53 := square(a) + square(b)",
      [{:square, [5]}, {:sumsq, [3, 4]}, {:sumsq, [10, 20]}]
    },
    {
      "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\ndef fib2(n) := fib(n) + fib(n)",
      "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\ndef fib2(n Int53) Int53 := fib(n) + fib(n)",
      [{:fib, [10]}, {:fib2, [10]}, {:fib2, [7]}]
    },
    {
      "def even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      "def even(n Int53) Int53\ndef even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(n Int53) Int53\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      [{:even, [8]}, {:even, [7]}, {:odd, [8]}, {:odd, [5]}]
    }
  ]

  describe "composition fixpoint — a whole module (Rian) runs identically to Elixir" do
    test "every function in the composed module matches Rian.Beam's", %{mod: mod} do
      for {rian_src, ref_src, calls} <- @corpus do
        composed = compose_module(mod, rian_src, :"cmp_mod_#{System.unique_integer([:positive])}")
        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(composed, fname, args) == apply(ref, fname, args),
                 "composed `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the entire :compile.forms input is built in Rian (no hand forms)" do
    test "compile_module yields module + export attributes and a function per group", %{mod: mod} do
      [mod_attr, export_attr | funcs] =
        mod.compile_module(
          "def square(n) := n * n\ndef sumsq(a, b) := square(a) + square(b)",
          :geo
        )

      assert mod_attr == {:attribute, 0, :module, :geo}
      assert export_attr == {:attribute, 0, :export, [{:square, 1}, {:sumsq, 2}]}
      assert [{:function, 0, :square, 1, _}, {:function, 0, :sumsq, 2, _}] = funcs
    end

    test "grouping folds a run of same-name clauses into one multi-clause function", %{mod: mod} do
      [_m, {:attribute, 0, :export, exports} | funcs] =
        mod.compile_module(
          "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\ndef fib2(n) := fib(n) + fib(n)",
          :fibs
        )

      # two functions, fib (3 clauses) and fib2 (1 clause)
      assert exports == [{:fib, 1}, {:fib2, 1}]

      assert [{:function, 0, :fib, 1, fib_clauses}, {:function, 0, :fib2, 1, fib2_clauses}] =
               funcs

      assert length(fib_clauses) == 3
      assert length(fib2_clauses) == 1
    end

    test "a mutually-recursive module actually runs", %{mod: mod} do
      m =
        compose_module(
          mod,
          "def even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
          :parity
        )

      assert {m.even(8), m.even(7), m.odd(8), m.odd(7)} == {1, 0, 0, 1}
    end
  end
end
