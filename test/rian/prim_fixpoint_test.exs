defmodule Rian.PrimFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # Self-hosting fixpoint (ADR-0047 §2 / ADR-0063 #2) for the `Prim.* -> __prim_*`
  # normalization pass: a Rian-written `compiler/prim.rian` (PrimNorm.normalize),
  # compiled to real `.beam`, diffed against the reference `Rian.Prim.normalize`.
  #
  # The corpus is HAND-BUILT raw `Rian.Pratt` surface tuples — NOT `Pratt.parse`,
  # which already runs `Rian.Prim.normalize` at the parse boundary (so parsing would
  # leave no `Prim.*` to test). Both the port and the oracle operate on the raw tuple;
  # we `inj` each result into the port's `Surface` sum (same tags) and compare. Only
  # VALID prims appear — the oracle RAISES on an unknown `Prim.x` (the port leaves it,
  # a documented tail), so an unknown would not be a fixpoint.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/prim.rian"), :rian_prim_fixpoint)
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

  # a Prim call helper for the corpus
  defp prim(name, args), do: {:call, {:dot, {:id, "Prim"}, name}, args}

  # HAND-BUILT raw surface trees exercising the rewrite in every expression position.
  # (a function, not a @attr — it calls the `prim/2` helper.)
  defp corpus,
    do: [
      # the bare rewrite
      prim("str_concat", [{:id, "a"}, {:id, "b"}]),
      prim("map_new", []),
      # nested Prim inside Prim args
      prim("str_concat", [prim("char_to_string", [{:id, "c"}]), {:str, "x"}]),
      # inside unary / binary
      {:unary, "-", prim("char_code", [{:id, "c"}])},
      {:bin, "+", prim("char_code", [{:id, "c"}]), {:num, "1"}},
      # a NON-Prim dot-call passes through (head not "Prim")
      {:call, {:dot, {:id, "Foo"}, "bar"}, [prim("char_code", [{:id, "a"}])]},
      # inside if / tuple / list / label
      {:if, {:id, "c"}, prim("int_to_string", [{:num, "1"}]), {:str, "z"}},
      {:tuple, [prim("char_code", [{:id, "a"}]), {:num, "2"}]},
      {:list_lit, [prim("char_code", [{:id, "a"}]), {:id, "b"}], nil},
      {:call, {:id, "f"}, [{:label, "k", prim("str_concat", [{:str, "a"}, {:str, "b"}])}]},
      # inside a block (bind + expr) and a case arm (guard + body)
      {:block,
       [{:bind, "x", prim("map_new", [])}, {:expr, prim("map_get", [{:id, "x"}, {:str, "k"}])}]},
      {:case, {:id, "x"}, [{{:var, "n"}, nil, prim("int_to_string", [{:id, "n"}])}]},
      # a tree with NO Prim calls is unchanged
      {:bin, "*", {:num, "3"}, {:bin, "+", {:num, "1"}, {:num, "2"}}}
    ]

  defp ported(mod, raw), do: mod.normalize(inj(raw))
  defp reference(raw), do: inj(Rian.Prim.normalize(raw))

  describe "self-hosting Prim-normalization fixpoint (vs Rian.Prim.normalize)" do
    test "the port rewrites Prim.* exactly like Rian.Prim.normalize", %{mod: mod} do
      for raw <- corpus() do
        assert ported(mod, raw) == reference(raw),
               "prim normalization diverged on #{inspect(raw)}\n" <>
                 "  ported:    #{inspect(ported(mod, raw))}\n" <>
                 "  reference: #{inspect(reference(raw))}"
      end
    end

    test "sanity — a known Prim.<name> becomes __prim_<name>, args recurse", %{mod: mod} do
      assert mod.normalize(inj(prim("str_concat", [{:id, "a"}, {:id, "b"}]))) ==
               {:s_call, {:s_id, "__prim_str_concat"}, [{:s_id, "a"}, {:s_id, "b"}]}
    end

    test "teeth — a non-Prim dot-call is left untouched", %{mod: mod} do
      raw = {:call, {:dot, {:id, "Foo"}, "bar"}, [{:id, "x"}]}
      assert mod.normalize(inj(raw)) == {:s_call, {:s_dot, {:s_id, "Foo"}, "bar"}, [{:s_id, "x"}]}
    end
  end
end
