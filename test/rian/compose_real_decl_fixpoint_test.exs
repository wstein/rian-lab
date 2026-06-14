defmodule Rian.ComposeRealDeclFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 9 (ADR-0063 Step 3): the front-end's LAST toy piece —
  # declaration splitting — is replaced by the equivalence-locked `selfhost_decl`
  # port. `selfhost_compose_real_decl.rian` parses the whole program with
  # `SelfhostDecl.parse_program` (cross-module), lowers its Decl IR to `selfhost_beam`
  # Core/Pat (the surface→Core lowering), and compiles via the verified `selfhost_beam`
  # backend (cross-module). BOTH front-end (lex→SelfhostDecl) and back-end
  # (SelfhostBeam) are now verified ports.
  #
  #   lex → SelfhostDecl.parse_program → normalize/group → lower → SelfhostBeam.compile_forms
  #        → inflate (in Rian) → :compile.forms / :code.load_binary
  #
  # selfhost_decl's surface has no `if` (that was rung 8's selfhost_parse) but DOES
  # have cons-list patterns — so this rung compiles list-pattern recursion
  # (`sum`/`len`), beyond rung 8. The test loads both ports under their
  # :"Elixir.Selfhost*" atoms, then calls only `build/2` and runs the result,
  # identical to `Rian.Beam`.

  setup_all do
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_decl.rian"),
        :rian_compose_real_decl
      )

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_rd_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped), reference source (typed sigs), [{fn, args}] to run}.
  @corpus [
    {
      "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
      "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
      [{:fib, [0]}, {:fib, [1]}, {:fib, [10]}, {:fib, [15]}]
    },
    {
      "def fact(0) := 1\ndef fact(n) := n * fact(n - 1)",
      "def fact(n Int53) Int53\ndef fact(0) := 1\ndef fact(n) := n * fact(n - 1)",
      [{:fact, [0]}, {:fact, [6]}]
    },
    {
      "def even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      "def even(n Int53) Int53\ndef even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(n Int53) Int53\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      [{:even, [8]}, {:even, [7]}, {:odd, [8]}, {:odd, [5]}]
    },
    # list-pattern recursion — beyond rung 8's (if-based) surface
    {
      "def sum([]) := 0\ndef sum([h | t]) := h + sum(t)",
      "def sum(xs Vec(Int53)) Int53\ndef sum([]) := 0\ndef sum([h | t]) := h + sum(t)",
      [{:sum, [[]]}, {:sum, [[1, 2, 3, 4]]}, {:sum, [[10, -3, 5]]}]
    },
    {
      "def len([]) := 0\ndef len([_ | t]) := 1 + len(t)",
      "def len(xs Vec(Int53)) Int53\ndef len([]) := 0\ndef len([_ | t]) := 1 + len(t)",
      [{:len, [[]]}, {:len, [[1, 2, 3]]}, {:len, [[9]]}]
    }
  ]

  describe "verified front-end + back-end fixpoint — runs identically to Elixir" do
    test "build/2 (SelfhostDecl + SelfhostBeam) loads modules equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_rd_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver(real decl+back) `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the declaration parser AND backend are the verified ports" do
    test "list-pattern clauses lower to cons forms and run (sum over a list)", %{drv: drv} do
      m = drv.build("def sum([]) := 0\ndef sum([h | t]) := h + sum(t)", :rd_sum_teeth)
      assert apply(m, :sum, [[1, 2, 3, 4, 5]]) == 15
    end

    test "compile_module groups multi-clause defs via the real decl parser", %{drv: drv} do
      [_m, {:attribute, 0, :export, exports} | funcs] =
        drv.compile_module(
          "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)",
          :rd_fibs
        )

      assert exports == [{:fib, 1}]
      assert [{:function, 0, :fib, 1, clauses}] = funcs
      assert length(clauses) == 3
    end

    test "an empty-list pattern lowers to the nil form `{nil, 0}`", %{drv: drv} do
      [_m, _e, {:function, 0, :f, 1, [c0 | _]}] =
        drv.compile_module("def f([]) := 0\ndef f([_ | t]) := t", :rd_nil)

      assert {:clause, 0, [{nil, 0}], [], [{:integer, 0, 0}]} = c0
    end
  end
end
