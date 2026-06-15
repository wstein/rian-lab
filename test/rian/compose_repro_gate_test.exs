defmodule Rian.ComposeReproGateTest do
  # async: false — loads the verified ports (by their natural atoms) + the driver;
  # `build/2` loads compiled modules into the VM at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # REPRODUCIBILITY GATE (ADR-0063 §4, the P3 prototype — "prove the loop before
  # debating the artifact"). The composed `build` (verified lexer + decl parser +
  # beam backend, cross-module — selfhost_compose_real_sum.rian) is a DETERMINISTIC
  # function of its source: the same real-source slice must regenerate identical
  # output, whose hash is pinned here. We commit the **hash, never the `.beam`
  # bytes** — so reproducible builds are *gated in CI*, and the question of vendoring
  # the bootstrap artifact is moot unless/until this hash drifts.
  #
  # The anchor is the Rian-produced **forms** (`compile_module/2` — the whole
  # pipeline's output that feeds `:compile.forms`), NOT raw `.beam` bytes: forms are
  # OTP-independent (no Erlang-assembler metadata, no source paths, no timestamps),
  # so the stored hash is stable across toolchains. A second check confirms the
  # `.beam` *itself* is byte-reproducible under deterministic compilation.
  #
  # Scope honesty (mirrors Rian.SelfHost @composition self_compiling/self_checking):
  # this gate proves codegen is **reproducible**, not that the loop self-CHECKS —
  # `Rian.Check`/`Exhaustiveness`/`Capability` are not in `build`.

  @modname :rian_repro_gate

  # a VERBATIM real-source slice (the `Ty` sum + `copyt` from selfhost_cap.rian, the
  # capability checker) — the same slice compose_selfcompile_fixpoint_test.exs pins
  # and asserts is verbatim in the real file, so the gate is anchored to real
  # compiler source, never a toy.
  @slice """
  type Ty := TScalar(String) | TString | TNom(String) | TVec(Ty) | TGen(String, Vec(Ty), String)
  def copyt(Ty) Bool
  def copyt(TScalar(_)) := true
  def copyt(TString) := false
  def copyt(TNom(_)) := false
  def copyt(TVec(_)) := false
  def copyt(TGen(_, _, _)) := false
  """

  # sha256 of `:erlang.term_to_binary(compile_module(@slice, @modname))`. If the
  # Rian pipeline's output legitimately changes, regenerate this *deliberately* and
  # review the diff; an accidental change fails the gate loudly.
  @expected_forms_sha256 "dca1e3ea27450865845dd17437e1b07a779c53ca88fb0dfcad7954533f2d499a"

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_sum.rian"),
        :rian_repro_gate_drv
      )

    {:ok, drv: drv}
  end

  defp forms_hash(forms),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(forms)) |> Base.encode16(case: :lower)

  test "build is deterministic — the same source regenerates identical forms", %{drv: drv} do
    f1 = drv.compile_module(@slice, @modname)
    f2 = drv.compile_module(@slice, @modname)

    assert f1 == f2
    assert forms_hash(f1) == forms_hash(f2)
  end

  test "regeneration reproduces the stored hash (the gate; `.beam` bytes never committed)", %{
    drv: drv
  } do
    forms = drv.compile_module(@slice, @modname)

    assert forms_hash(forms) == @expected_forms_sha256,
           "the composed build's output drifted from the pinned hash.\n" <>
             "If intentional, regenerate @expected_forms_sha256 (review the diff first):\n" <>
             "  got: #{forms_hash(forms)}"
  end

  test "the `.beam` compiled from those forms is byte-reproducible (deterministic compile)", %{
    drv: drv
  } do
    forms = drv.compile_module(@slice, @modname)

    {:ok, _m, bin1} = :compile.forms(forms, [:deterministic, :return_errors])
    {:ok, _m, bin2} = :compile.forms(forms, [:deterministic, :return_errors])
    assert bin1 == bin2, "`:compile.forms` output is not byte-reproducible under :deterministic"

    # and the driver's loaded module actually runs the real stage logic (only a
    # scalar is Copy) — reproducibility of *correct* codegen, not just stable bytes.
    mod = drv.build(@slice, @modname)
    assert mod.copyt({:t_scalar, "Int53"}) == true
    assert mod.copyt(:t_string) == false
  end
end
