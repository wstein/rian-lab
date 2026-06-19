defmodule Rian.ComposeErrorSetGateFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false
  alias Rian.Beam

  # P3 Phase 2 — the `T | E` error-set gate (Checker.error_set_bad, ADR-0040 §4) is WIRED
  # into `build`. The driver builds `tsets` (each sum type -> its variant tags, from the
  # d_type decls), projects each body with the atom/tuple-PRESERVING `to_chk_es`, and
  # `first_error_set_bad` rejects a `T | E` function that returns an `{:error, Tag}` whose
  # tag is not in `E`'s set. This is the fifth and last of Rian.Check's error sets — the
  # self-built compiler's type-error coverage now mirrors the reference's.

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

    {:ok, drv} = Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_errorset_gate)
    {:ok, drv: drv}
  end

  defp uniq(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  @types "type DivErr := DivByZero | Overflow\n"

  describe "the `T | E` error-set gate is WIRED into build" do
    test "a function returning an OUT-OF-SET error tag is REFUSED", %{drv: drv} do
      src = @types <> "def bad() Result(Int53, DivErr) := {:error, NotFound}"

      assert catch_error(drv.build(src, uniq(:ESBad))) == {:type_error, "bad"},
             "the error-set gate did not refuse an out-of-set tag"
    end

    test "an in-set error tag compiles + runs", %{drv: drv} do
      src = @types <> "def good() Result(Int53, DivErr) := {:error, DivByZero}"
      m = drv.build(src, uniq(:ESGood))
      assert m.good() == {:error, :div_by_zero}
    end

    test "a non-`T | E` program is unaffected by the gate", %{drv: drv} do
      m = drv.build("def add(a Int53) Int53 := a + 1\ndef go() Int53 := add(41)", uniq(:ESNone))
      assert m.go() == 42
    end
  end
end
