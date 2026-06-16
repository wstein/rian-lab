defmodule Rian.ComposeBeamWholeFixpointTest do
  # async: false — loads the verified ports (by their natural atoms) + the driver,
  # and `build/2` loads the freshly-compiled beam backend at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE LOOP CLOSES ON THE WHOLE BEAM BACKEND (ADR-0063 Step 3 / §4). Like the
  # lexer (`compose_lexer_fixpoint_test`) and decl parser
  # (`compose_decl_whole_fixpoint_test`), this feeds the composed `build` the ENTIRE
  # `compiler/beam.rian` — the Rian-written counterpart of
  # `Rian.Beam`'s form generation: Core→Form lowering, native-dispatch clause
  # patterns, `Prim.*` (str_concat/str_chars/…), `<>`, `if`/`case`, list/tuple
  # construction — and the composed build (verified lexer + decl parser + beam
  # backend, cross-module) compiles it into a real loadable module.
  #
  # That Rian-built backend then lowers Core IR to abstract forms IDENTICALLY to the
  # reference backend (`Beam`, which `beam_module_fixpoint_test` already
  # locks against `Rian.Beam`). This is the third whole stage to compile its **own
  # whole source** — the v1==v2 shape, now on the backend itself.
  #
  # Honesty (mirrors Rian.SelfHost @composition): the loop is self-COMPILING, not
  # self-CHECKING — Rian.Check/Exhaustiveness/Capability are not in `build`.

  @beam_file "compiler/beam.rian"
  @beam_src File.read!(@beam_file)

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.LexerV2")

    {:ok, _} = Beam.load(File.read!("compiler/decl.rian"), :"Elixir.Decl")
    {:ok, ref} = Beam.load(@beam_src, :"Elixir.Beam")

    {:ok, _} =
      Beam.load(File.read!("compiler/exhaust.rian"), :"Elixir.Exhaust")

    {:ok, _} = Beam.load(File.read!("compiler/cap.rian"), :"Elixir.Cap")

    {:ok, _} = Beam.load(File.read!("compiler/checker.rian"), :"Elixir.Checker")

    {:ok, drv} =
      Beam.load(
        File.read!("compiler/compose_real_sum.rian"),
        :rian_compose_beam_whole
      )

    built = drv.build(@beam_src, :"RianBuiltBeam_#{System.unique_integer([:positive])}")
    {:ok, built: built, ref: ref}
  end

  # Core IR (sum ctors lower to tagged tuples on the BEAM): each Func exercises a
  # facet of the backend — arithmetic, `if`, the `<>`/Prim.str_concat → FConcat
  # path, `case` with guarded arms, and list/tuple construction. If the self-hosted
  # build mis-compiled any clause, one diverges from the reference's forms.
  @funcs [
    {:func, "f", 2,
     [
       {:clause, [{:p_var, "a"}, {:p_var, "b"}], :g_none,
        {:block, [{:s_expr, {:c_bin, "+", {:c_id, "a"}, {:c_id, "b"}}}]}}
     ]},
    {:func, "g", 1,
     [
       {:clause, [{:p_var, "n"}], :g_none,
        {:block,
         [
           {:s_expr,
            {:c_if, {:c_bin, "==", {:c_id, "n"}, {:c_num, "0"}},
             {:block, [{:s_expr, {:c_num, "1"}}]}, {:block, [{:s_expr, {:c_id, "n"}}]}}}
         ]}}
     ]},
    {:func, "cc", 1,
     [
       {:clause, [{:p_var, "s"}], :g_none,
        {:block, [{:s_expr, {:c_call, "__prim_str_concat", [{:c_str, "_"}, {:c_id, "s"}]}}]}}
     ]},
    {:func, "cat", 2,
     [
       {:clause, [{:p_var, "a"}, {:p_var, "b"}], :g_none,
        {:block, [{:s_expr, {:c_bin, "<>", {:c_id, "a"}, {:c_id, "b"}}}]}}
     ]},
    {:func, "cls", 1,
     [
       {:clause, [{:p_var, "c"}], :g_none,
        {:block,
         [
           {:s_expr,
            {:c_case, {:c_id, "c"},
             [
               {:arm, {:p_var, "n"}, {:g_some, {:c_bin, ">=", {:c_id, "n"}, {:c_num, "48"}}},
                {:block, [{:s_expr, {:c_id, "n"}}]}},
               {:arm, :p_wild, :g_none, {:block, [{:s_expr, {:c_num, "0"}}]}}
             ]}}
         ]}}
     ]},
    {:func, "pair", 2,
     [
       {:clause, [{:p_var, "x"}, {:p_var, "y"}], :g_none,
        {:block, [{:s_expr, {:c_tuple, [{:c_id, "x"}, {:c_id, "y"}]}}]}}
     ]},
    # a cross-module remote call (CRemote) — the composition driver reaches sibling
    # self-host modules this way.
    {:func, "rem", 1,
     [
       {:clause, [{:p_var, "x"}], :g_none,
        {:block, [{:s_expr, {:c_remote, "Elixir.Decl", "parse_program", [{:c_id, "x"}]}}]}}
     ]},
    # the str_to_atom prim (CCall → String.to_atom) — the driver interns names.
    {:func, "atm", 1,
     [
       {:clause, [{:p_var, "s"}], :g_none,
        {:block, [{:s_expr, {:c_call, "__prim_str_to_atom", [{:c_id, "s"}]}}]}}
     ]},
    {:func, "lst", 1,
     [
       {:clause, [{:p_var, "t"}], :g_none,
        {:block, [{:s_expr, {:c_list, [{:c_num, "1"}, {:c_num, "2"}], {:t_tail, {:c_id, "t"}}}}]}}
     ]}
  ]

  describe "the loop closes on the beam backend — `build` self-compiles the whole file" do
    test "the Rian-built backend lowers Core to forms identically to the reference",
         %{built: built, ref: ref} do
      for f <- @funcs do
        assert built.compile_forms([f]) == ref.compile_forms([f]),
               "the self-hosted-build beam backend diverged from the reference on #{inspect(f)}"
      end
    end

    test "it is the WHOLE real file (verbatim), not a slice", %{built: built} do
      # the source compiled is compiler/beam.rian unmodified, and the
      # built module exports the real entry point.
      assert @beam_src =~ "mod Beam do"
      assert @beam_src =~ "pub def compile_forms("
      assert function_exported?(built, :compile_forms, 1)
    end
  end
end
