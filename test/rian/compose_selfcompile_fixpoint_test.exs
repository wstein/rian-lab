defmodule Rian.ComposeSelfcompileFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE LOOP CLOSES ON REAL SOURCE (ADR-0063 Step 3). Every other composition fixpoint
  # feeds `build` a hand-written corpus. This one feeds it a VERBATIM slice of a real
  # compiler stage — `examples/rian/selfhost_cap.rian` (the capability checker): its
  # `Ty` sum type and `copyt` function. The composed build (verified lexer + decl
  # parser + backend, cross-module) compiles that real source and runs it identically
  # to `Rian.Beam`. This is the first time a stage compiles its OWN source, not a toy.
  #
  # Caveat (honesty): the loop is self-COMPILING, not self-CHECKING — Rian.Check /
  # Exhaustiveness / Capability are not in the `build` loop (see Rian.SelfHost
  # @composition). And this is a SLICE: the whole file needs `if`/strings/Prim, which
  # the build's surface does not yet cover. The slice is chosen to be within surface
  # AND is asserted to be a verbatim substring of the real file, so it cannot drift
  # into a toy.

  @cap_file "examples/rian/selfhost_cap.rian"

  # the `Ty` declaration + `copyt` clauses, verbatim from selfhost_cap.rian. The
  # "real source" assertion below checks each line actually appears in that file.
  @slice """
  type Ty := TScalar(String) | TString | TNom(String) | TVec(Ty) | TGen(String, Vec(Ty), String)
  def copyt(Ty) Bool
  def copyt(TScalar(_)) := true
  def copyt(TString) := false
  def copyt(TNom(_)) := false
  def copyt(TVec(_)) := false
  def copyt(TGen(_, _, _)) := false
  """

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_sum.rian"),
        :rian_compose_selfcompile
      )

    {:ok, drv: drv}
  end

  # representative Ty values (the BEAM rep of each variant: nullary → atom,
  # applied → tagged tuple) — the shapes copyt dispatches on.
  @values [
    {:t_scalar, "Int53"},
    :t_string,
    {:t_nom, "Color"},
    {:t_vec, :t_string},
    {:t_vec, {:t_scalar, "Int8"}},
    {:t_gen, "Vec", [], "raw"}
  ]

  test "the slice is REAL source — copyt clauses verbatim, Ty variants real, in selfhost_cap.rian" do
    real = File.read!(@cap_file)

    # the stage logic — every `copyt` clause — is verbatim in the real file.
    copyt_lines =
      @slice
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, "def copyt"))

    assert length(copyt_lines) == 6

    for line <- copyt_lines do
      assert String.contains?(real, line),
             "copyt clause is not verbatim in #{@cap_file} (would be a toy, not real source): #{line}"
    end

    # the `Ty` type is the same declaration (reflowed to one line); its variants are real.
    for variant <- [
          "TScalar(String)",
          "TString",
          "TNom(String)",
          "TVec(Ty)",
          "TGen(String, Vec(Ty), String)"
        ] do
      assert String.contains?(real, variant), "Ty variant not found in #{@cap_file}: #{variant}"
    end
  end

  test "build compiles the real selfhost_cap slice; copyt runs identically to Rian.Beam", %{
    drv: drv
  } do
    composed = drv.build(@slice, :"selfcompile_#{System.unique_integer([:positive])}")
    {:ok, ref} = Beam.load(@slice, :"selfcompile_ref_#{System.unique_integer([:positive])}")

    for v <- @values do
      assert apply(composed, :copyt, [v]) == apply(ref, :copyt, [v]),
             "composed copyt diverged from Rian.Beam on #{inspect(v)}"
    end

    # and the actual capability semantics survive: only a scalar is Copy.
    assert apply(composed, :copyt, [{:t_scalar, "Int53"}]) == true
    assert apply(composed, :copyt, [:t_string]) == false
  end

  test "teeth — `build` self-COMPILES but does NOT self-CHECK (honest scope)" do
    comp = Rian.SelfHost.composition()
    assert comp.self_compiling == true
    assert comp.self_checking == false
    assert comp.closed_on_real_source =~ "selfhost_cap.rian"
  end
end
