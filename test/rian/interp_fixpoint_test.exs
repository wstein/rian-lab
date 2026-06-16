defmodule Rian.InterpFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Check}

  # Self-hosting fixpoint (ADR-0069 / ADR-0063 #2) for the string-interpolation DESUGAR:
  # a Rian-written `compiler/interp.rian` (Interp.desugar), compiled to real `.beam`,
  # diffed against the desugar half of `Rian.Interp.resolve`.
  #
  # Factoring: `Rian.Interp.resolve` both INFERS each hole's type (Check.infer) and
  # DESUGARS by it. Inference is a separately self-hosted pass (compiler/checker.rian);
  # this port owns the desugar — stringify-by-type + single-shot concat — taking each
  # hole's inferred type as input. The test feeds it the very types `Check.infer`
  # produces, so `Interp.desugar(parts, types, show)` is locked against
  # `inj(Rian.Interp.resolve(node, env, ic, show))`. Only stringifiable hole types
  # appear — the oracle RAISES on an un-`Show`-able type (a documented tail).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/interp.rian"), :rian_interp_fixpoint)
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

  # ── interp-specific helpers ──
  defp inj_parts({:str_interp, parts}) do
    Enum.map(parts, fn
      {:lit, s} -> {:i_lit, s}
      {:hole, e} -> {:i_hole, inj(e)}
    end)
  end

  defp hole_types({:str_interp, parts}, env, ic) do
    for {:hole, e} <- parts, do: norm(Check.infer(e, env, ic))
  end

  defp norm(:unknown), do: "unknown"
  defp norm(t), do: t

  defp ported(mod, node, env, ic, show), do: mod.desugar(inj_parts(node), hole_types(node, env, ic), show)
  defp reference(node, env, ic, show), do: inj(Rian.Interp.resolve(node, env, ic, MapSet.new(show)))

  # {str_interp node, env (param -> type), show type-name list}
  defp corpus do
    [
      # an int hole between two literals -> single-shot concat
      {{:str_interp, [{:lit, "a"}, {:hole, {:id, "x"}}, {:lit, "b"}]}, %{"x" => "Int53"}, []},
      # a String hole alone is the value itself (identity, single part)
      {{:str_interp, [{:hole, {:id, "s"}}]}, %{"s" => "String"}, []},
      # Bool -> if/true/false
      {{:str_interp, [{:hole, {:id, "bb"}}]}, %{"bb" => "Bool"}, []},
      # Char -> __prim_char_to_string
      {{:str_interp, [{:hole, {:id, "c"}}]}, %{"c" => "Char"}, []},
      # Float64 -> Show.float
      {{:str_interp, [{:hole, {:id, "f"}}]}, %{"f" => "Float64"}, []},
      # UInt8 -> __prim_int_to_string (the U?Int\d* path)
      {{:str_interp, [{:hole, {:id, "u"}}]}, %{"u" => "UInt8"}, []},
      # a user type with impl Show -> show(value)
      {{:str_interp, [{:hole, {:id, "p"}}]}, %{"p" => "Point"}, ["Point"]},
      # a trailing empty literal is dropped (concat collapses to the single hole)
      {{:str_interp, [{:hole, {:id, "n"}}, {:lit, ""}]}, %{"n" => "Int53"}, []},
      # multiple holes of mixed type + literals
      {{:str_interp, [{:hole, {:id, "x"}}, {:lit, " and "}, {:hole, {:id, "s"}}]},
       %{"x" => "Int53", "s" => "String"}, []}
    ]
  end

  describe "self-hosting interpolation-desugar fixpoint (vs Rian.Interp.resolve)" do
    test "the port desugars ${…} exactly like Rian.Interp.resolve", %{mod: mod} do
      for {node, env, show} <- corpus() do
        assert ported(mod, node, env, %{}, show) == reference(node, env, %{}, show),
               "interp desugar diverged on #{inspect(node)} (env #{inspect(env)})\n" <>
                 "  ported:    #{inspect(ported(mod, node, env, %{}, show))}\n" <>
                 "  reference: #{inspect(reference(node, env, %{}, show))}"
      end
    end

    test "sanity — an int hole between literals is one __prim_str_concat_all", %{mod: mod} do
      node = {:str_interp, [{:lit, "a"}, {:hole, {:id, "x"}}, {:lit, "b"}]}

      assert ported(mod, node, %{"x" => "Int53"}, %{}, []) ==
               {:s_call, {:s_id, "__prim_str_concat_all"},
                [{:s_str, "a"}, {:s_call, {:s_id, "__prim_int_to_string"}, [{:s_id, "x"}]}, {:s_str, "b"}]}
    end
  end
end
