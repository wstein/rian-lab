defmodule Rian.ComposeRealLexFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 10 (ADR-0063 Step 3): the front-end's LAST driver-local
  # piece — tokenizing — is replaced by the equivalence-locked `selfhost_lexer_v2`
  # port. `selfhost_compose_real_lex.rian` now owns NO lexing or parsing: the whole
  # front-end is verified ports, called cross-module.
  #
  #   SelfhostLexerV2.tokenize → SelfhostDecl.parse_program → lower → SelfhostBeam.compile_forms
  #        → inflate (in Rian) → :compile.forms / :code.load_binary
  #
  # THREE verified ports (lexer, declaration parser, backend) composed end to end,
  # with identical token tags across the lexer→parser boundary (no projection). The
  # only driver-local code is the surface→Core lowering and the Form inflater. The
  # test loads all three ports under their :"Elixir.Selfhost*" atoms, then calls only
  # `build/2` and runs the result, identical to `Rian.Beam`.

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_lex.rian"),
        :rian_compose_real_lex
      )

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_rl_ref_#{System.unique_integer([:positive])}")
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
      [{:even, [8]}, {:odd, [7]}]
    },
    {
      "def sum([]) := 0\ndef sum([h | t]) := h + sum(t)",
      "def sum(xs Vec(Int53)) Int53\ndef sum([]) := 0\ndef sum([h | t]) := h + sum(t)",
      [{:sum, [[]]}, {:sum, [[1, 2, 3, 4]]}]
    },
    {
      "def len([]) := 0\ndef len([_ | t]) := 1 + len(t)",
      "def len(xs Vec(Int53)) Int53\ndef len([]) := 0\ndef len([_ | t]) := 1 + len(t)",
      [{:len, [[]]}, {:len, [[1, 2, 3]]}]
    }
  ]

  describe "fully-verified front-end + back-end fixpoint — runs identically to Elixir" do
    test "build/2 (LexerV2 + Decl + Beam ports) loads modules equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_rl_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver(real lex+decl+back) `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the driver owns no lexing or parsing" do
    test "tokenizing comes from the verified lexer (handles whitespace/comments)", %{drv: drv} do
      # the real lexer collapses newlines and skips `#` comments — driver code never
      # touches characters. A comment line and extra blank lines must not break it.
      src = "# fib\ndef fib(0) := 0\n\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\n"
      m = drv.build(src, :rl_comment)
      assert Enum.map(0..7, &apply(m, :fib, [&1])) == [0, 1, 1, 2, 3, 5, 8, 13]
    end

    test "list-pattern recursion compiles + runs (sum over a list)", %{drv: drv} do
      m = drv.build("def sum([]) := 0\ndef sum([h | t]) := h + sum(t)", :rl_sum_teeth)
      assert apply(m, :sum, [[5, 10, 15, 20]]) == 50
    end
  end
end
