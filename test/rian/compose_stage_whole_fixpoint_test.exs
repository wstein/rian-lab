defmodule Rian.ComposeStageWholeFixpointTest do
  # async: false — loads the verified ports + the driver, then `build/2` compiles
  # each whole stage source at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # WHOLE-STAGE self-compile locks (ADR-0063 Step 4) for the two compiler stages
  # newly brought within the composed `build`'s surface:
  #
  #   * selfhost_core.rian — the surface→Core lowering oracle (`emit`/`emit_pat`,
  #     the Rian-written counterpart of `Rian.Core.from_expr`, locked vs it in
  #     core_fixpoint_test). Reached the build once `Prim.int_to_string` lowered.
  #   * selfhost_exhaust.rian — the Maranget usefulness checker (`useful/3`). Reached
  #     the build once struct field access (`cd.name`/`td.ctors`) lowered (Step 1).
  #
  # For each, the composed build (verified lexer + decl parser + beam backend) compiles
  # the WHOLE file into a real loadable module that runs identically to `Rian.Beam`.
  # Together with compose_lexer / compose_decl_whole / compose_beam_whole /
  # compose_selfcompile (cap) / compose_driver_whole, the build now self-compiles every
  # critical-path stage AND the driver. Self-COMPILING, not self-CHECKING.

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_cap.rian"), :"Elixir.SelfhostCap")

    {:ok, drv} =
      Beam.load(File.read!("examples/rian/selfhost_compose_real_sum.rian"), :rian_compose_stage)

    core_src = File.read!("examples/rian/selfhost_core.rian")
    exh_src = File.read!("examples/rian/selfhost_exhaust.rian")

    {:ok, core_b} = {:ok, drv.build(core_src, :"RianBuiltCore_#{System.unique_integer([:positive])}")}
    {:ok, core_r} = Beam.load(core_src, :"core_ref_#{System.unique_integer([:positive])}")
    {:ok, exh_b} = {:ok, drv.build(exh_src, :"RianBuiltExh_#{System.unique_integer([:positive])}")}
    {:ok, exh_r} = Beam.load(exh_src, :"exh_ref_#{System.unique_integer([:positive])}")

    {:ok, core_src: core_src, exh_src: exh_src, core_b: core_b, core_r: core_r, exh_b: exh_b, exh_r: exh_r}
  end

  # Surface AST nodes (the port's `Surface` sum; nullary→atom, applied→tagged tuple),
  # spanning num/str/atom/id, unary/binary, call, field access, `if`, tuple, list.
  @surfaces [
    {:s_num, "5"},
    {:s_str, "hi"},
    {:s_atom, "ok"},
    {:s_id, "x"},
    {:s_unary, "-", {:s_num, "3"}},
    {:s_bin, "+", {:s_num, "1"}, {:s_num, "2"}},
    {:s_call, {:s_id, "f"}, [{:s_num, "1"}, {:s_id, "y"}]},
    {:s_dot, {:s_id, "c"}, "name"},
    {:s_if, {:s_id, "c"}, {:s_num, "1"}, {:s_num, "0"}},
    {:s_tuple, [{:s_atom, "ok"}, {:s_num, "7"}]},
    {:s_list, [{:s_num, "1"}, {:s_num, "2"}], :t_close}
  ]

  describe "selfhost_core self-compiles whole — `emit` runs identically to Rian.Beam" do
    test "the built lowering oracle renders every surface node like the reference",
         %{core_b: b, core_r: r} do
      for s <- @surfaces do
        assert b.emit(s) == r.emit(s), "selfhost_core emit diverged on #{inspect(s)}"
      end
    end

    test "it is the WHOLE real file", %{core_src: src, core_b: b} do
      assert src =~ "mod SelfhostCore do"
      assert src =~ "pub def emit(Surface) String"
      assert function_exported?(b, :emit, 1)
    end
  end

  # a small typing env (Bool = {true,false}) + pattern matrices for the usefulness
  # checker (PWild→atom, PCtor→tagged tuple; structs are field-keyed maps).
  @env %{
    cdefs: [%{name: "true", ar: 0, ty: "Bool"}, %{name: "false", ar: 0, ty: "Bool"}],
    tdefs: [%{ty: "Bool", ctors: ["true", "false"]}]
  }
  @exhaust_cases [
    {@env, [], [:p_wild]},
    {@env, [[{:p_ctor, "true", []}]], [{:p_ctor, "false", []}]},
    {@env, [[{:p_ctor, "true", []}], [{:p_ctor, "false", []}]], [:p_wild]},
    {@env, [[:p_wild]], [{:p_ctor, "true", []}]}
  ]

  describe "selfhost_exhaust self-compiles whole — `useful` runs identically to Rian.Beam" do
    test "the built usefulness checker agrees with the reference over pattern matrices",
         %{exh_b: b, exh_r: r} do
      for {env, rows, q} <- @exhaust_cases do
        assert b.useful(env, rows, q) == r.useful(env, rows, q),
               "selfhost_exhaust useful diverged on #{inspect({rows, q})}"
      end

      # the algorithm's teeth: a not-yet-covered ctor is useful; a full cover is not.
      assert b.useful(@env, [[{:p_ctor, "true", []}]], [{:p_ctor, "false", []}]) == true
      assert b.useful(@env, [[{:p_ctor, "true", []}], [{:p_ctor, "false", []}]], [:p_wild]) == false
    end

    test "it is the WHOLE real file", %{exh_src: src, exh_b: b} do
      assert src =~ "mod SelfhostExhaust do"
      assert src =~ "pub def useful("
      assert function_exported?(b, :useful, 3)
    end
  end
end
