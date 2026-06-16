defmodule Rian.ComposeBindsGateFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false
  alias Rian.Beam

  # P3 Phase 2 — the THIRD type gate (typed-binding mismatch) is WIRED into `build`.
  # The composed compiler already refused non-exhaustive, BEAM-illegal, numeric-mix,
  # and return-type-mismatched programs; this adds the binding gate via the
  # equivalence-locked `Checker.binds_bad` (checker.rian, ADR-0034/0064). The
  # self-built compiler now REFUSES a program whose `name Ann := value` provably
  # contradicts `Ann` ({:type_error, name}) — instead of silently emitting it.
  #
  # This exercises the WHOLE self-hosted path the gate needs: the self-hosted parser
  # (decl.rian) now parses `name Ty := expr` typed binds, the driver lowers + projects
  # them (to_chk_stmts), `Checker.binds_bad` decides, and `Rian.Beam` emits a valid
  # typed bind as an ordinary match (annotation erased) so a well-typed one still runs.

  setup_all do
    {:ok, _} = Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.LexerV2")
    {:ok, _} = Beam.load(File.read!("compiler/decl.rian"), :"Elixir.Decl")
    {:ok, _} = Beam.load(File.read!("compiler/beam.rian"), :"Elixir.Beam")
    {:ok, _} = Beam.load(File.read!("compiler/exhaust.rian"), :"Elixir.Exhaust")
    {:ok, _} = Beam.load(File.read!("compiler/cap.rian"), :"Elixir.Cap")
    {:ok, _} = Beam.load(File.read!("compiler/checker.rian"), :"Elixir.Checker")
    {:ok, drv} = Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_binds_gate)
    {:ok, drv: drv}
  end

  defp uniq(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  describe "the binding gate is WIRED into build — a bad typed bind is REFUSED" do
    @bad [
      # out-of-range literal for the declared fixed width
      "def f() Int64\n  x Int8 := 9999\n  5\nend",
      # value type contradicts the declared annotation
      ~s|def f() Int64\n  s Int64 := "hi"\n  5\nend|,
      # an integer literal does not adopt a float annotation (ADR-0035)
      "def f() Int64\n  y Float64 := 66\n  5\nend"
    ]

    test "build and compile_module REFUSE every binding-mismatch program ({:type_error, f})",
         %{drv: drv} do
      for src <- @bad do
        assert catch_error(drv.compile_module(src, uniq(:BindBad))) == {:type_error, "f"},
               "the binding gate did not refuse: #{inspect(src)}"

        assert catch_error(drv.build(src, uniq(:BindBad))) == {:type_error, "f"},
               "build did not refuse: #{inspect(src)}"
      end
    end
  end

  describe "a well-typed bind still compiles + runs (no false reject)" do
    test "an in-range typed bind builds and runs", %{drv: drv} do
      m = drv.build("def f() Int64\n  x Int8 := 5\n  x\nend", uniq(:BindOk))
      assert m.f() == 5
    end

    test "a typed bind whose value adopts the annotation builds and runs", %{drv: drv} do
      m = drv.build("def g() Int64\n  a Int64 := 41\n  a + 1\nend", uniq(:BindOk))
      assert m.g() == 42
    end
  end
end
