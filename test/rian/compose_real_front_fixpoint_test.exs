defmodule Rian.ComposeRealFrontFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 8 (ADR-0063 Step 3): extends rung 7 (verified BACKEND)
  # to the FRONT-END. `selfhost_compose_real_front.rian` parses each clause body with
  # the equivalence-locked `selfhost_parse` port (the full Rian.Pratt grammar), called
  # cross-module, then lowers its raw surface tuple to `selfhost_beam` Core and runs it
  # through the equivalence-locked `selfhost_beam` backend (also cross-module):
  #
  #   lex → decl-parse → SelfhostParse.parse(body) → lower → SelfhostBeam.compile_forms
  #        → inflate (in Rian) → :compile.forms / :code.load_binary
  #
  # TWO verified stages composed end to end. This test loads both ports under their
  # :"Elixir.Selfhost*" atoms (so the Pascal-qualified calls resolve), then calls only
  # `build/2` and runs the result — identical to `Rian.Beam`, now with the REAL parser
  # (real precedence, real surface) AND the real backend.

  setup_all do
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_parse.rian"), :"Elixir.SelfhostParse")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_front.rian"),
        :rian_compose_real_front
      )

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_rf_ref_#{System.unique_integer([:positive])}")
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
      "def max(a, b) := if a > b do a else b end\ndef min(a, b) := if a < b do a else b end",
      "def max(a Int53, b Int53) Int53 := if a > b do a else b end\ndef min(a Int53, b Int53) Int53 := if a < b do a else b end",
      [{:max, [3, 7]}, {:max, [9, 2]}, {:min, [3, 7]}]
    },
    {
      "def gcd(a, 0) := a\ndef gcd(a, b) := step(a, b)\ndef step(a, b) := if a > b do gcd(a - b, b) else gcd(a, b - a) end",
      "def gcd(a Int53, b Int53) Int53\ndef gcd(a, 0) := a\ndef gcd(a, b) := step(a, b)\ndef step(a Int53, b Int53) Int53 := if a > b do gcd(a - b, b) else gcd(a, b - a) end",
      [{:gcd, [48, 18]}, {:gcd, [17, 5]}, {:gcd, [100, 100]}]
    },
    {
      "def inrange(x, lo, hi) := if x >= lo and x <= hi do 1 else 0 end",
      "def inrange(x Int53, lo Int53, hi Int53) Int53 := if x >= lo and x <= hi do 1 else 0 end",
      [{:inrange, [5, 1, 10]}, {:inrange, [15, 1, 10]}]
    },
    {
      "def poly(a, b, c) := a + b * c - 1",
      "def poly(a Int53, b Int53, c Int53) Int53 := a + b * c - 1",
      [{:poly, [2, 3, 4]}, {:poly, [10, 0, 5]}]
    }
  ]

  describe "real front-end + back-end fixpoint — runs identically to Elixir" do
    test "build/2 (verified parser + backend) loads modules equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_rf_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver(real front+back) `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the REAL parser's precedence and surface flow through" do
    test "real Pratt precedence: comparison binds looser than arithmetic", %{drv: drv} do
      # a + b * c - 1 must nest as (a + (b*c)) - 1, per selfhost_parse's level table.
      m = drv.build("def f(a, b, c) := a + b * c - 1", :rf_prec_teeth)
      # 2 + 3*4 - 1 = 13, not e.g. (2+3)*4-1=19
      assert apply(m, :f, [2, 3, 4]) == 13
    end

    test "compile_module routes bodies through SelfhostParse then SelfhostBeam", %{drv: drv} do
      [_m, _exp, func] =
        drv.compile_module("def pick(a, b) := if a > b do a else b end", :pick_rf)

      assert {:function, 0, :pick, 2,
              [
                {:clause, 0, [{:var, 0, :A}, {:var, 0, :B}], [],
                 [
                   {:case, 0, {:op, 0, :>, {:var, 0, :A}, {:var, 0, :B}},
                    [
                      {:clause, 0, [{:atom, 0, true}], [], [{:var, 0, :A}]},
                      {:clause, 0, [{:atom, 0, false}], [], [{:var, 0, :B}]}
                    ]}
                 ]}
              ]} = func
    end
  end
end
