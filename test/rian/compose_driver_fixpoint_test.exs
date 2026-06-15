defmodule Rian.ComposeDriverFixpointTest do
  # async: false — loads real modules into the VM via the Rian driver itself.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 5 / capstone (ADR-0063 Step 3 / §4): the BEAM-bootstrap
  # terminus shape. `compose_driver.rian` owns the WHOLE loop in Rian —
  # source string -> a loaded, runnable module:
  #
  #     build(src, modname) = load(compile_forms(compile_module(src, modname)), modname)
  #
  # The only host dependency is the two irreducible BEAM toolchain calls, declared as
  # `@external(:ex, …)` FFI and counted in @selfhost_ffi: `:compile.forms` and
  # `:code.load_binary`. Everything between — destructuring `{:ok, _, _}`, threading
  # the binary, returning the module atom — is ordinary Rian.
  #
  # Unlike rungs 1-4, this test calls NOTHING but `build`: no Elixir `:compile.forms`,
  # no `:code.load_binary`. The Rian driver compiles AND loads; the test merely runs
  # the returned module and asserts it behaves identically to `Rian.Beam`.

  setup_all do
    {:ok, drv} =
      Beam.load(File.read!("compiler/compose_driver.rian"), :rian_compose_driver)

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_drv_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped), reference source (typed sigs), [{fn, args}] to run}.
  @corpus [
    {
      "def square(n) := n * n\ndef sumsq(a, b) := square(a) + square(b)",
      "def square(n Int53) Int53 := n * n\ndef sumsq(a Int53, b Int53) Int53 := square(a) + square(b)",
      [{:square, [9]}, {:sumsq, [3, 4]}]
    },
    {
      "def fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\ndef fib2(n) := fib(n) + fib(n)",
      "def fib(n Int53) Int53\ndef fib(0) := 0\ndef fib(1) := 1\ndef fib(n) := fib(n - 1) + fib(n - 2)\ndef fib2(n Int53) Int53 := fib(n) + fib(n)",
      [{:fib, [12]}, {:fib2, [10]}]
    },
    {
      "def even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      "def even(n Int53) Int53\ndef even(0) := 1\ndef even(n) := odd(n - 1)\ndef odd(n Int53) Int53\ndef odd(0) := 0\ndef odd(n) := even(n - 1)",
      [{:even, [9]}, {:odd, [9]}]
    }
  ]

  describe "driver fixpoint — Rian compiles AND loads; runs identically to Elixir" do
    test "build/2 loads a module behaviourally equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_drv_#{System.unique_integer([:positive])}"
        # the Rian driver itself calls :compile.forms + :code.load_binary
        loaded = drv.build(rian_src, modname)
        assert loaded == modname, "driver returned an unexpected module atom"

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver-loaded `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — the driver, not the test, owns the toolchain calls" do
    test "build/2 returns a loaded module whose functions are callable", %{drv: drv} do
      loaded = drv.build("def triple(n) := n + n + n", :drv_triple)
      assert loaded == :drv_triple
      # dynamic apply — the module is defined at runtime by the driver, not at compile time
      assert apply(loaded, :triple, [7]) == 21
    end

    test "compile_module produces forms but does NOT load (load is build's job)", %{drv: drv} do
      # compile_module is pure data — calling it must not define the module.
      forms = drv.compile_module("def noload(n) := n", :drv_should_not_exist)
      assert is_list(forms)
      refute :code.is_loaded(:drv_should_not_exist)

      # build, by contrast, loads it.
      drv.build("def yesload(n) := n", :drv_should_not_exist)
      assert :code.is_loaded(:drv_should_not_exist) != false
    end
  end
end
