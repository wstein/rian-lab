defmodule Rian.ComptimeFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # Self-hosting fixpoint (ADR-0056 fold / ADR-0063 #2) for `comptime(expr)` folding:
  # a Rian-written `compiler/comptime.rian` (Comptime.fold), compiled to real `.beam`,
  # diffed against the reference `Rian.Comptime.fold`.
  #
  # The corpus is HAND-BUILT raw `Rian.Pratt` surface tuples (no Pratt.parse). Both the
  # port and the oracle fold the raw tuple; we `inj` each result into the port's
  # `Surface` sum (same tags) and compare. Only the INTEGER/BOOLEAN subset appears:
  # float results are unported (no float→string prim), and a non-foldable body makes the
  # oracle RAISE (the port leaves the call) — neither is a fixpoint, both documented tails.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/comptime.rian"), :rian_comptime_fixpoint)
    {:ok, mod: mod}
  end

  # ── inject: Rian.Pratt surface tuple -> the port's Surface sum (mirrors core.rian) ──
  defp inj({:num, t}), do: {:s_num, t}
  defp inj({:str, s}), do: {:s_str, s}
  defp inj({:char, c}), do: {:s_char, c}
  defp inj({:id, n}), do: {:s_id, n}
  defp inj({:atom, a}), do: {:s_atom, a}
  defp inj({:unary, op, x}), do: {:s_unary, op, inj(x)}
  defp inj({:bin, op, l, r}), do: {:s_bin, op, inj(l), inj(r)}
  defp inj({:call, f, args}), do: {:s_call, inj(f), Enum.map(args, &inj/1)}
  defp inj({:label, n, e}), do: {:s_label, n, inj(e)}
  defp inj({:dot, h, n}), do: {:s_dot, inj(h), n}
  defp inj({:if, c, t, e}), do: {:s_if, inj(c), inj(t), inj(e)}
  defp inj({:tuple, es}), do: {:s_tuple, Enum.map(es, &inj/1)}
  defp inj({:list_lit, es, tail}), do: {:s_list, Enum.map(es, &inj/1), inj_tail(tail)}
  defp inj({:map_lit, ps}), do: {:s_map, Enum.map(ps, fn {k, v} -> {:sp, k, inj(v)} end)}
  defp inj({:block, ss}), do: {:s_block, Enum.map(ss, &inj_stmt/1)}
  defp inj({:case, s, arms}), do: {:s_case, inj(s), Enum.map(arms, &inj_arm/1)}
  defp inj({:lambda, ps, b}), do: {:s_lambda, Enum.map(ps, &inj_param/1), inj(b)}
  defp inj({:cap_arg, n}), do: {:s_cap_arg, n}
  defp inj({:capture, b}), do: {:s_capture, inj(b)}
  defp inj({:capture_named, p, a}), do: {:s_capture_named, inj(p), a}

  defp inj({:with, cls, body, els}) do
    {:s_with, Enum.map(cls, fn {p, e} -> {:s_clause, inj_pat(p), inj(e)} end), inj(body),
     Enum.map(els, &inj_arm/1)}
  end

  defp inj_tail(nil), do: :t_close
  defp inj_tail(:close), do: :t_close
  defp inj_tail({:tail, e}), do: {:t_tail, inj(e)}

  defp inj_stmt({:bind, n, e}), do: {:s_bind, n, inj(e)}
  defp inj_stmt({:typed_bind, n, t, e}), do: {:s_typed_bind, n, t, inj(e)}
  defp inj_stmt({:expr, e}), do: {:s_expr, inj(e)}

  defp inj_arm({p, g, b}), do: {:s_arm, inj_pat(p), inj_guard(g), inj(b)}
  defp inj_guard(nil), do: :g_none
  defp inj_guard(e), do: {:g_some, inj(e)}

  defp inj_param({name, nil}), do: {:s_param, name, :pt_none}
  defp inj_param({name, ty}), do: {:s_param, name, {:pt_some, ty}}

  defp inj_pat(:wild), do: :p_wild
  defp inj_pat({:var, n}), do: {:p_var, n}
  defp inj_pat({:lit, v}) when is_integer(v), do: {:p_lit_int, v}
  defp inj_pat({:lit, v}) when is_binary(v), do: {:p_lit_str, v}
  defp inj_pat({:char_lit, c}), do: {:pp_char, c}
  defp inj_pat({:atom, a}), do: {:pp_atom, a}
  defp inj_pat({:tuple, ps}), do: {:pp_tuple, Enum.map(ps, &inj_pat/1)}
  defp inj_pat({:ctor, c, args}), do: {:p_ctor, c, Enum.map(args, &inj_pat/1)}
  defp inj_pat({:list, ps, :close}), do: {:pp_list, Enum.map(ps, &inj_pat/1), :ptl_close}

  defp inj_pat({:list, ps, {:tail, t}}),
    do: {:pp_list, Enum.map(ps, &inj_pat/1), {:ptl_tail, inj_pat(t)}}

  defp inj_pat({:struct, n, fs}),
    do: {:pp_struct, n, Enum.map(fs, fn {f, p} -> {:p_pr, f, inj_pat(p)} end)}

  defp inj_pat({:map, kvs}),
    do: {:pp_map, Enum.map(kvs, fn {k, p} -> {:p_pr, k, inj_pat(p)} end)}

  defp ct(e), do: {:call, {:id, "comptime"}, [e]}

  # HAND-BUILT raw surface trees (integer/boolean comptime + passthrough).
  defp corpus,
    do: [
      ct({:bin, "+", {:num, "2"}, {:num, "3"}}),
      ct({:bin, "-", {:num, "10"}, {:bin, "*", {:num, "4"}, {:num, "2"}}}),
      ct({:bin, "div", {:num, "20"}, {:num, "6"}}),
      ct({:bin, "rem", {:num, "20"}, {:num, "6"}}),
      # `_` separators
      ct({:bin, "+", {:num, "1_000"}, {:num, "1"}}),
      # unary negate
      ct({:unary, "-", {:bin, "+", {:num, "2"}, {:num, "3"}}}),
      # comparisons + boolean negate -> true/false
      ct({:bin, "<", {:num, "1"}, {:num, "2"}}),
      ct({:bin, ">=", {:num, "5"}, {:num, "9"}}),
      ct({:unary, "not", {:bin, "==", {:num, "1"}, {:num, "1"}}}),
      # nested inside a larger expression (recursion past the fold site)
      {:call, {:id, "f"}, [ct({:bin, "+", {:num, "2"}, {:num, "3"}}), {:id, "x"}]},
      {:if, {:id, "c"}, ct({:bin, "*", {:num, "6"}, {:num, "7"}}), {:num, "0"}},
      {:block, [{:bind, "x", ct({:bin, "+", {:num, "1"}, {:num, "1"}})}, {:expr, {:id, "x"}}]},
      # a tree with NO comptime is unchanged
      {:bin, "+", {:num, "1"}, {:num, "2"}}
    ]

  defp ported(mod, raw), do: mod.fold(inj(raw))
  defp reference(raw), do: inj(Rian.Comptime.fold(raw))

  describe "self-hosting comptime-fold fixpoint (vs Rian.Comptime.fold)" do
    test "the port folds comptime(...) exactly like Rian.Comptime.fold", %{mod: mod} do
      for raw <- corpus() do
        assert ported(mod, raw) == reference(raw),
               "comptime fold diverged on #{inspect(raw)}\n" <>
                 "  ported:    #{inspect(ported(mod, raw))}\n" <>
                 "  reference: #{inspect(reference(raw))}"
      end
    end

    test "sanity — integer fold yields a num literal, comparison yields true/false", %{mod: mod} do
      assert mod.fold(inj(ct({:bin, "+", {:num, "2"}, {:num, "3"}}))) == {:s_num, "5"}
      assert mod.fold(inj(ct({:bin, "<", {:num, "1"}, {:num, "2"}}))) == {:s_id, "true"}
    end
  end
end
