defmodule Rian.SelfhostV1V2FixpointTest do
  # async: false — compiles + loads the whole Rian-written compiler into the VM in
  # two generations and compares their output.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE BOOTSTRAP FIXED POINT — v1 == v2 (ADR-0063 §4, Step 5). The Rian-written
  # compiler is the composed `build`: the verified lexer (selfhost_lexer_v2) + decl
  # parser (selfhost_decl) + BEAM backend (selfhost_beam) wired by the driver
  # (selfhost_compose_real_sum). All four are themselves Rian source.
  #
  #   gen0  = the compiler as compiled by the Elixir host (`Rian.Beam`).
  #   gen1  = gen0 compiles the compiler's OWN four sources  → the Rian compiler,
  #           now built by itself.
  #   gen2  = gen1 (the self-built compiler) compiles the SAME four sources again.
  #
  # We assert gen1 == gen2 for every compiler module — identical canonical forms, and
  # hence (compiling under `:deterministic`) bit-identical `.beam`. That is the fixed
  # point: the Rian compiler reproduces itself exactly under self-application.
  #
  # Scope/honesty: this is v1==v2 FOR THE RIAN COMPILER (the composed `build`), which
  # is self-COMPILING, not self-CHECKING — `Rian.Check`/`Exhaustiveness`/`Capability`
  # are not in the loop. It is NOT a claim that `build` reproduces `Rian.Beam`'s
  # bytecode: `Rian.Beam` additionally emits `-spec`/type attributes and runs Reach,
  # so the Elixir host's `.beam` is a richer artifact by design. The comparison is on
  # FORMS, the canonical artifact (`compose_repro_gate_test` shows `.beam` is
  # byte-reproducible from forms under `:deterministic`).

  @lexer File.read!("examples/rian/selfhost_lexer_v2.rian")
  @decl File.read!("examples/rian/selfhost_decl.rian")
  @beam File.read!("examples/rian/selfhost_beam.rian")
  @driver File.read!("examples/rian/selfhost_compose_real_sum.rian")

  # {label, source, the BEAM module atom it must load under}. The driver references
  # its sibling stages by their `Elixir.`-prefixed atoms, so those three MUST load
  # under exactly these names for the self-built compiler to find them.
  defp modules do
    [
      {"lexer", @lexer, :"Elixir.SelfhostLexerV2"},
      {"decl", @decl, :"Elixir.SelfhostDecl"},
      {"beam", @beam, :"Elixir.SelfhostBeam"},
      {"driver", @driver, :SelfhostDriverFixedPoint}
    ]
  end

  defp load_forms(name, forms) do
    {:ok, m, bin} = :compile.forms(forms, [:deterministic, :return_errors])
    {:module, ^m} = :code.load_binary(name, ~c"nofile", bin)
    {m, bin}
  end

  setup_all do
    # gen0 — the compiler compiled by the Elixir host.
    {:ok, _} = Beam.load(@lexer, :"Elixir.SelfhostLexerV2")
    {:ok, _} = Beam.load(@decl, :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(@beam, :"Elixir.SelfhostBeam")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_cap.rian"), :"Elixir.SelfhostCap")
    {:ok, gen0_driver} = Beam.load(@driver, :rian_gen0_driver)

    # gen1 — gen0 compiles each compiler source (canonical forms).
    gen1 = for {n, src, name} <- modules(), into: %{}, do: {n, gen0_driver.compile_module(src, name)}

    # load gen1 as the live compiler: the three stages under their Elixir atoms
    # (replacing gen0), and the gen1 driver under its own.
    load_forms(:"Elixir.SelfhostLexerV2", gen1["lexer"])
    load_forms(:"Elixir.SelfhostDecl", gen1["decl"])
    load_forms(:"Elixir.SelfhostBeam", gen1["beam"])
    {gen1_driver, _} = load_forms(:SelfhostDriverFixedPoint, gen1["driver"])

    # gen2 — the self-built compiler recompiles the SAME sources.
    gen2 = for {n, src, name} <- modules(), into: %{}, do: {n, gen1_driver.compile_module(src, name)}

    {:ok, gen1: gen1, gen2: gen2}
  end

  describe "v1 == v2 — the Rian compiler reproduces itself under self-application" do
    test "gen1 and gen2 produce identical canonical forms for every compiler module",
         %{gen1: gen1, gen2: gen2} do
      for {n, _, _} <- modules() do
        assert gen1[n] == gen2[n],
               "FIXED-POINT BREAK: gen1 != gen2 for the #{n} module — the Rian compiler does not reproduce its own #{n}"
      end
    end

    test "and the compiled `.beam` is bit-identical (deterministic compile) for every module",
         %{gen1: gen1, gen2: gen2} do
      for {n, _, _} <- modules() do
        {:ok, _, b1} = :compile.forms(gen1[n], [:deterministic, :return_errors])
        {:ok, _, b2} = :compile.forms(gen2[n], [:deterministic, :return_errors])

        assert b1 == b2, ".beam for the #{n} module is not bit-identical between gen1 and gen2"
      end
    end

    test "the fixed point covers the WHOLE compiler — all four stages, real sources" do
      # each module is the verbatim real file, and the set is the entire composed build.
      assert @lexer =~ "pub def tokenize("
      assert @decl =~ "pub def parse_program("
      assert @beam =~ "pub def compile_forms("
      assert @driver =~ "pub def build(src String, modname Symbol) Symbol"
      assert length(modules()) == 4
    end
  end
end
