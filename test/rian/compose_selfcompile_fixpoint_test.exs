defmodule Rian.ComposeSelfcompileFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE LOOP CLOSES ON A WHOLE REAL STAGE (ADR-0063 Step 3/4). This was once a
  # verbatim SLICE of selfhost_cap.rian (the `Ty` sum + `copyt`); it now feeds the
  # composed `build` the ENTIRE capability checker — the `Cap`/`Ty` sums, the
  # `rust_param` Rust-signature matrix, `beam_legal`, and `copyt` — and the composed
  # build (verified lexer + decl parser + beam backend, cross-module) compiles it
  # into a real loadable module that runs identically to `Rian.Beam`.
  #
  # Caveat (honesty): the loop is self-COMPILING and now PARTIALLY self-CHECKING — the
  # Exhaustiveness AND Capability gates run in `build` (see
  # compose_exhaust_gate_fixpoint_test), but Rian.Check (type inference) is still not
  # in the loop (see Rian.SelfHost @composition). `self_checking` stays false until
  # type inference is wired too.

  @cap_file "examples/rian/selfhost_cap.rian"
  @cap_src File.read!(@cap_file)

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_cap.rian"), :"Elixir.SelfhostCap")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_sum.rian"),
        :rian_compose_selfcompile
      )

    built = drv.build(@cap_src, :"RianBuiltCap_#{System.unique_integer([:positive])}")
    {:ok, ref} = Beam.load(@cap_src, :"selfcompile_ref_#{System.unique_integer([:positive])}")
    {:ok, built: built, ref: ref}
  end

  # the capability core (ADR-0055): `Cap` nullary variants → atoms, `Ty` → atom /
  # tagged tuple. `copyt` (only a scalar is Copy), `beam_legal` (`ref` is the sole
  # BEAM-illegal cap), and `rust_param` (the val/iso/ref/tag → Rust-signature matrix).
  @caps [:iso, :val, :ref, :tag]
  @tys [
    {:t_scalar, "Int53"},
    :t_string,
    {:t_nom, "Color"},
    {:t_vec, :t_string},
    {:t_vec, {:t_scalar, "Int8"}},
    {:t_gen, "Vec", [], "raw"}
  ]

  describe "the loop closes on the whole capability checker — `build` self-compiles the file" do
    test "copyt / beam_legal / rust_param run identically to Rian.Beam over the matrix",
         %{built: built, ref: ref} do
      for ty <- @tys do
        assert built.copyt(ty) == ref.copyt(ty), "copyt diverged on #{inspect(ty)}"
      end

      for cap <- @caps do
        assert built.beam_legal(cap) == ref.beam_legal(cap), "beam_legal diverged on #{cap}"

        for ty <- @tys do
          assert built.rust_param(cap, ty) == ref.rust_param(cap, ty),
                 "rust_param diverged on #{cap}/#{inspect(ty)}"
        end
      end

      # the capability semantics survive: only a scalar is Copy; only `ref` is
      # BEAM-illegal (it lowers to `&mut`).
      assert built.copyt({:t_scalar, "Int53"}) == true
      assert built.copyt(:t_string) == false
      assert built.beam_legal(:ref) == false
      assert built.beam_legal(:iso) == true
    end

    test "it is the WHOLE real file (verbatim), not a slice", %{built: built} do
      assert @cap_src =~ "mod SelfhostCap do"
      assert @cap_src =~ "pub def rust_param(Cap, Ty) String"
      assert function_exported?(built, :rust_param, 2)
      assert function_exported?(built, :copyt, 1)
    end

    test "teeth — `build` self-COMPILES but does NOT self-CHECK (honest scope)" do
      comp = Rian.SelfHost.composition()
      assert comp.self_compiling == true
      assert comp.self_checking == false
      assert comp.closed_on_real_source =~ "selfhost_cap.rian"
    end
  end
end
