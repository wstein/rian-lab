defmodule Rian.ComposeBoundsGateFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false
  alias Rian.Beam

  # P3 Phase 2 — the protocol-bound gate (Checker.bounds_bad, ADR-0042 §2) is WIRED into
  # `build`. The driver builds the `fbounds` (bounded generic -> tvars/param-types/bounds,
  # from each `forall T: P`) and `impls` (protocol -> implementing types, from the `d_impl`
  # facts) tables, then gates each body. The self-built compiler now REFUSES a call to a
  # bounded generic whose argument type has no matching `impl` ({:type_error, name}) and
  # compiles+runs one whose type does — building on the protocol emission that lets such a
  # program compile end-to-end at all.

  setup_all do
    for {f, m} <- [
          {"lexer_v2", "LexerV2"},
          {"decl", "Decl"},
          {"beam", "Beam"},
          {"exhaust", "Exhaust"},
          {"cap", "Cap"},
          {"checker", "Checker"}
        ] do
      {:ok, _} = Beam.load(File.read!("compiler/#{f}.rian"), :"Elixir.#{m}")
    end

    {:ok, drv} = Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_bounds_gate)
    {:ok, drv: drv}
  end

  defp uniq(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  @proto """
  protocol Show do
    def show(self Self) String
  end

  impl Show for Int53 do
    def show(x) := "i"
  end

  def render(v C) String forall C: Show := show(v)
  """

  describe "the protocol-bound gate is WIRED into build" do
    test "a call to a bounded generic with a no-impl type is REFUSED", %{drv: drv} do
      src = @proto <> "\ndef bad() String := render(\"hi\")"

      assert catch_error(drv.build(src, uniq(:BoundBad))) == {:type_error, "bad"},
             "the bounds gate did not refuse render(String) with no impl Show for String"
    end

    test "a call whose argument type HAS the impl compiles + runs", %{drv: drv} do
      src = @proto <> "\ndef good() String := render(5)"
      m = drv.build(src, uniq(:BoundGood))
      assert m.good() == "i"
    end

    test "a non-bounded program is unaffected by the gate", %{drv: drv} do
      m = drv.build("def add(a Int53) Int53 := a + 1\ndef go() Int53 := add(41)", uniq(:NoBound))
      assert m.go() == 42
    end
  end
end
