defmodule Rian.ComposeDeclFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 2 (ADR-0063 Step 3): widens the composed subset from
  # an *expression* (compose_fixpoint_test) to a full single-clause `def`
  # DECLARATION. `selfhost_compose_decl.rian` now parses the def head + parameter
  # list + `:=` body AND assembles the complete Erlang function form in Rian —
  # `compile_def(s) = emit_def(parse_def(lex(s)))` — so name, arity, params, and
  # body all come from the SOURCE, not from Elixir glue.
  #
  # The only Elixir residual is the two module-level attribute forms
  # (`:module` / `:export`): the export list needs a *tagless* `{name, arity}`
  # tuple, which Rian's variant lowering (every ctor injects a tag atom) can't
  # spell. Both the name and arity in that boilerplate are READ BACK from the
  # Rian-produced function form — nothing source-dependent is authored here.
  #
  # As before, this compiles + loads + RUNS the result and asserts it behaves
  # identically to the full Elixir toolchain (`Rian.Beam` on the same `def`).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_compose_decl.rian"), :rian_compose_decl)

    {:ok, mod: mod}
  end

  # build, compile, and load a module from the Rian-produced function form. Only
  # the :module/:export attribute boilerplate is Elixir — name + arity are read
  # back out of the Rian form, not re-derived from the source.
  defp compose_module(mod, src, modname) do
    {:function, _l, name, arity, _clauses} = func_form = mod.compile_def(src)

    forms = [
      {:attribute, 0, :module, modname},
      {:attribute, 0, :export, [{name, arity}]},
      func_form
    ]

    {:ok, ^modname, bin} = :compile.forms(forms, [:return_errors])
    {:module, ^modname} = :code.load_binary(modname, ~c"nofile", bin)
    {modname, name, arity}
  end

  # the Elixir toolchain compiling the reference declaration.
  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_decl_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped — the arithmetic subset has no type syntax),
  #  reference source (typed Rian for Rian.Beam), function name, [arg lists]}.
  # The two strings are the SAME function; the fixpoint compares runtime behavior.
  @corpus [
    {"def f(a, b) := a + b", "def f(a Int53, b Int53) Int53 := a + b", :f, [[2, 3], [10, -4]]},
    {"def f(a, b, c) := a + b * c", "def f(a Int53, b Int53, c Int53) Int53 := a + b * c", :f,
     [[1, 2, 3], [5, 6, 7]]},
    {"def f(a, b, c) := (a + b) * c", "def f(a Int53, b Int53, c Int53) Int53 := (a + b) * c", :f,
     [[1, 2, 3], [4, 5, 6]]},
    {"def f(a, b, c) := a - b - c", "def f(a Int53, b Int53, c Int53) Int53 := a - b - c", :f,
     [[10, 3, 2]]},
    {"def g(x) := x * 2 + 1", "def g(x Int53) Int53 := x * 2 + 1", :g, [[20]]},
    {"def h() := 2 + 3 * 4", "def h() Int53 := 2 + 3 * 4", :h, [[]]},
    {"def f(foo, bar) := foo * bar + 1", "def f(foo Int53, bar Int53) Int53 := foo * bar + 1", :f,
     [[6, 7]]}
  ]

  describe "composition fixpoint — a full `def` (Rian) runs identically to Elixir" do
    test "the composed declaration compiles + runs a function equal to Rian.Beam's", %{mod: mod} do
      for {rian_src, ref_src, fname, inputs} <- @corpus do
        {composed, name, _arity} =
          compose_module(mod, rian_src, :"cmp_decl_#{System.unique_integer([:positive])}")

        assert name == fname, "composed function name diverged for `#{rian_src}`"
        ref = ref_module(ref_src)

        for args <- inputs do
          assert apply(composed, fname, args) == apply(ref, fname, args),
                 "composed `def` diverged from Elixir toolchain on `#{rian_src}` with #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the whole function form is built in Rian (name, arity, params, body)" do
    test "compile_def emits a complete {:function, …} abstract form", %{mod: mod} do
      assert mod.compile_def("def f(a, b) := a + b * 2") ==
               {:function, 1, :f, 2,
                [
                  {:clause, 1, [{:var, 1, :A}, {:var, 1, :B}], [],
                   [{:op, 1, :+, {:var, 1, :A}, {:op, 1, :*, {:var, 1, :B}, {:integer, 1, 2}}}]}
                ]}
    end

    test "arity and param vars come from the source's parameter list", %{mod: mod} do
      {:function, 1, :sum3, 3, [{:clause, 1, params, [], _body}]} =
        mod.compile_def("def sum3(x, y, z) := x + y + z")

      assert params == [{:var, 1, :X}, {:var, 1, :Y}, {:var, 1, :Z}]
    end

    test "a zero-arg def yields arity 0 and an empty parameter list", %{mod: mod} do
      assert mod.compile_def("def answer() := 6 * 7") ==
               {:function, 1, :answer, 0,
                [{:clause, 1, [], [], [{:op, 1, :*, {:integer, 1, 6}, {:integer, 1, 7}}]}]}
    end
  end
end
