defmodule Rian.ComposeCondFixpointTest do
  # async: false — the Rian driver loads modules into the VM.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 6 (ADR-0063 Step 3): widens the driver's surface past
  # arithmetic toward real compiler code — `if … do … else … end` (lowered to an
  # Erlang `case` on the boolean), comparison operators (`== < > <= >=`, with Rian
  # `<=` → Erlang `=<`), and boolean `and`/`or` (→ `andalso`/`orelse`). The driver is
  # unchanged from rung 5: `build(src, modname)` still owns the whole compile→load
  # loop, with `:compile.forms`/`:code.load_binary` the only counted @external FFI.
  #
  # As before, this test calls only `build/2` and runs the returned module, asserting
  # it behaves identically to `Rian.Beam` — now over conditionals and comparisons.

  setup_all do
    {:ok, drv} =
      Beam.load(File.read!("compiler/compose_cond.rian"), :rian_compose_cond)

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_cond_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped), reference source (typed sigs), [{fn, args}] to run}.
  @corpus [
    {
      "def max(a, b) := if a > b do a else b end\ndef min(a, b) := if a < b do a else b end",
      "def max(a Int53, b Int53) Int53 := if a > b do a else b end\ndef min(a Int53, b Int53) Int53 := if a < b do a else b end",
      [{:max, [3, 7]}, {:max, [9, 2]}, {:min, [3, 7]}, {:min, [9, 2]}]
    },
    {
      "def abs(n) := if n < 0 do 0 - n else n end",
      "def abs(n Int53) Int53 := if n < 0 do 0 - n else n end",
      [{:abs, [-5]}, {:abs, [4]}, {:abs, [0]}]
    },
    {
      "def countdown(n) := if n == 0 do 0 else countdown(n - 1) end",
      "def countdown(n Int53) Int53 := if n == 0 do 0 else countdown(n - 1) end",
      [{:countdown, [0]}, {:countdown, [5]}]
    },
    {
      "def gcd(a, 0) := a\ndef gcd(a, b) := step(a, b)\ndef step(a, b) := if a > b do gcd(a - b, b) else gcd(a, b - a) end",
      "def gcd(a Int53, b Int53) Int53\ndef gcd(a, 0) := a\ndef gcd(a, b) := step(a, b)\ndef step(a Int53, b Int53) Int53 := if a > b do gcd(a - b, b) else gcd(a, b - a) end",
      [{:gcd, [48, 18]}, {:gcd, [17, 5]}, {:gcd, [100, 100]}]
    },
    {
      "def inrange(x, lo, hi) := if x >= lo and x <= hi do 1 else 0 end\ndef outside(x, lo, hi) := if x < lo or x > hi do 1 else 0 end",
      "def inrange(x Int53, lo Int53, hi Int53) Int53 := if x >= lo and x <= hi do 1 else 0 end\ndef outside(x Int53, lo Int53, hi Int53) Int53 := if x < lo or x > hi do 1 else 0 end",
      [
        {:inrange, [5, 1, 10]},
        {:inrange, [15, 1, 10]},
        {:outside, [5, 1, 10]},
        {:outside, [15, 1, 10]}
      ]
    }
  ]

  describe "driver fixpoint — conditionals + comparisons run identically to Elixir" do
    test "build/2 loads if/comparison/boolean functions equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_cond_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver-loaded `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — `if` lowers to a case on the boolean; precedence is right" do
    test "compile_module lowers `if` to a {:case, …} with true/false clauses", %{drv: drv} do
      [_m, _exp, func] = drv.compile_module("def pick(a, b) := if a > b do a else b end", :pick)

      assert {:function, 0, :pick, 2, [{:clause, 0, _params, [], [body]}]} = func

      assert {:case, 0, {:op, 0, :>, {:var, 0, :A}, {:var, 0, :B}},
              [
                {:clause, 0, [{:atom, 0, true}], [], [{:var, 0, :A}]},
                {:clause, 0, [{:atom, 0, false}], [], [{:var, 0, :B}]}
              ]} = body
    end

    test "comparison binds looser than arithmetic (a + 1 > b parses as (a+1) > b)", %{drv: drv} do
      m = drv.build("def f(a, b) := if a + 1 > b do 1 else 0 end", :cond_prec)
      # a=3 -> a+1=4; 4 > 3 -> 1.  a=3,b=5 -> 4 > 5 -> 0.
      assert apply(m, :f, [3, 3]) == 1
      assert apply(m, :f, [3, 5]) == 0
    end

    test "Rian `<=` lowers to Erlang `=<` (and actually compiles)", %{drv: drv} do
      [_m, _e, {:function, 0, :le, 2, [{:clause, 0, _, [], [{:op, 0, op, _, _}]}]}] =
        drv.compile_module("def le(a, b) := a <= b", :le_check)

      assert op == :"=<"
    end
  end
end
