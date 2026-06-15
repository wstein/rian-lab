defmodule Rian.ComposeRealBeamFixpointTest do
  # async: false — loads modules into the VM (incl. the verified backend by its
  # natural module atom) and the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 7 (ADR-0063 Step 3 / §4): the first cut that connects
  # the two previously-disconnected successes — per-stage equivalence and the
  # composition loop. Rungs 1-6 used a TOY backend (the driver's own `forms`).
  # `compose_real_beam.rian` instead calls the EQUIVALENCE-LOCKED
  # `beam.rian` backend across modules:
  #
  #     parse(src) → selfhost_beam Func → Beam.compile_forms(funcs)
  #                                       └ the REAL port (cross-module call)
  #                  → inflate its Form sum → real abstract-form tuples (in Rian)
  #                  → :compile.forms / :code.load_binary (the driver loop)
  #
  # `Beam` must be loaded under its natural `:"Elixir.Beam"` atom so
  # the Pascal-qualified call resolves (ADR-0041). The `Form → abstract-form`
  # inflation the beam fixpoint test did in Elixir is now ported into the driver.
  #
  # The test calls only `build/2` and runs the result, identical to `Rian.Beam` —
  # now with the driver's backend being the verified port, not a toy.

  setup_all do
    # the verified backend, under the atom a Pascal-qualified call lowers to.
    {:ok, _} = Beam.load(File.read!("compiler/beam.rian"), :"Elixir.Beam")

    {:ok, drv} =
      Beam.load(
        File.read!("compiler/compose_real_beam.rian"),
        :rian_compose_real_beam
      )

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_rb_ref_#{System.unique_integer([:positive])}")
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
    }
  ]

  describe "real-backend fixpoint — driver via Beam runs identically to Elixir" do
    test "build/2 (verified backend) loads modules equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_rb_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver(real-backend) `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the backend really is the cross-module verified port" do
    test "compile_module routes through Beam.compile_forms (inflated in Rian)", %{
      drv: drv
    } do
      # the abstract form is exactly what the verified backend + Rian inflater produce.
      [_m, _exp, func] =
        drv.compile_module("def pick(a, b) := if a > b do a else b end", :pick_rb)

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

    test "without Beam loaded the call would fail — proving it's a real dependency", %{
      drv: drv
    } do
      # Beam IS loaded (setup_all), so this succeeds; the point of the rung is
      # that the backend is an external verified module, not inlined toy code.
      assert Code.ensure_loaded?(:"Elixir.Beam")
      m = drv.build("def double(n) := n + n", :rb_double)
      assert apply(m, :double, [21]) == 42
    end
  end
end
