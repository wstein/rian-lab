defmodule Rian.CoreFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **typed Core IR** stage (full): a
  # Rian-written surface→Core lowering (compiler/core.rian),
  # compiled to real `.beam`, diffed against the reference
  # `Rian.Core.from_expr`/`from_pat` over the FULL surface front-door.
  #
  # Each node is rendered to a canonical s-expression. The port emits it directly;
  # this test renders the reference `Rian.Core` struct to the SAME s-expression
  # (`canon`/`canon_pat`) and asserts equality over a corpus that exercises every
  # surface-reachable construct. The Lower-internal resolved nodes
  # (variant_lit/struct_lit/const_ref), decl-resolved str_interp, Rust-baked rpat,
  # and the never-parsed `as`/pin patterns are not surface, so they are out of scope.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/core.rian"), :rian_core_fixpoint)
    {:ok, mod: mod}
  end

  # ── inject: Rian.Pratt surface tuple -> the port's Surface sum ──
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

  # ── canon: reference Rian.Core struct -> the same canonical s-expression ──
  defp canon(%Core.ENum{text: t}), do: "(num #{t})"
  defp canon(%Core.EStr{value: s}), do: "(str #{s})"
  defp canon(%Core.EChar{value: c}), do: "(char #{c})"
  defp canon(%Core.EId{name: n}), do: "(id #{n})"
  defp canon(%Core.EAtom{name: a}), do: "(atom #{a})"
  defp canon(%Core.EUnary{op: op, arg: x}), do: "(unary #{op} #{canon(x)})"
  defp canon(%Core.EBin{op: op, left: l, right: r}), do: "(bin #{op} #{canon(l)} #{canon(r)})"
  defp canon(%Core.ECall{fun: f, args: as}), do: "(call #{canon(f)} [#{join(as)}])"
  defp canon(%Core.ELabel{name: n, expr: e}), do: "(label #{n} #{canon(e)})"
  defp canon(%Core.EDot{head: h, name: n}), do: "(dot #{canon(h)} #{n})"
  defp canon(%Core.EIf{cond: c, then: t, else: e}), do: "(if #{canon(c)} #{canon(t)} #{canon(e)})"
  defp canon(%Core.ETuple{elems: es}), do: "(tuple [#{join(es)}])"

  defp canon(%Core.EList{elems: es, tail: tl}),
    do: "(list [#{join(es)}] #{canon_tail(tl)})"

  defp canon(%Core.EMap{pairs: ps}),
    do: "(map [#{Enum.map_join(ps, " ", fn {k, v} -> "(#{k} #{canon(v)})" end)}])"

  defp canon(%Core.EBlock{stmts: ss}), do: "(block [#{Enum.map_join(ss, " ", &canon_stmt/1)}])"

  defp canon(%Core.ECase{scrut: s, arms: arms}),
    do: "(case #{canon(s)} [#{Enum.map_join(arms, " ", &canon_arm/1)}])"

  defp canon(%Core.ELambda{params: ps, body: b}),
    do: "(lambda [#{Enum.map_join(ps, " ", &canon_param/1)}] #{canon(b)})"

  defp canon(%Core.ECapArg{n: n}), do: "(cap_arg #{n})"
  defp canon(%Core.ECapture{body: b}), do: "(capture #{canon(b)})"
  defp canon(%Core.ECaptureNamed{path: p, arity: a}), do: "(capture_named #{canon(p)} #{a})"

  defp canon(%Core.EWith{clauses: cls, body: b, els: els}) do
    c = Enum.map_join(cls, " ", fn {p, e} -> "(clause #{canon_pat(p)} #{canon(e)})" end)
    "(with [#{c}] #{canon(b)} [#{Enum.map_join(els, " ", &canon_arm/1)}])"
  end

  defp join(es), do: Enum.map_join(es, " ", &canon/1)
  defp canon_tail(:close), do: "close"
  defp canon_tail(e), do: "(tail #{canon(e)})"

  defp canon_stmt({:bind, n, e}), do: "(bind #{n} #{canon(e)})"
  defp canon_stmt({:typed_bind, n, t, e}), do: "(typed_bind #{n} #{t} #{canon(e)})"
  defp canon_stmt({:expr, e}), do: "(expr #{canon(e)})"

  defp canon_arm({p, g, b}), do: "(arm #{canon_pat(p)} #{canon_guard(g)} #{canon(b)})"
  defp canon_guard(nil), do: "nil"
  defp canon_guard(e), do: canon(e)

  defp canon_param({name, nil}), do: "(#{name})"
  defp canon_param({name, ty}), do: "(#{name} #{ty})"

  defp canon_pat(%Core.PWild{}), do: "(pwild)"
  defp canon_pat(%Core.PVar{name: n}), do: "(pvar #{n})"
  defp canon_pat(%Core.PLit{value: v}) when is_integer(v), do: "(plit_int #{v})"
  defp canon_pat(%Core.PLit{value: v}) when is_binary(v), do: "(plit_str #{v})"
  defp canon_pat(%Core.PChar{value: c}), do: "(pchar #{c})"
  defp canon_pat(%Core.PAtom{name: a}), do: "(patom #{a})"
  defp canon_pat(%Core.PTuple{elems: ps}), do: "(ptuple [#{join_pat(ps)}])"
  defp canon_pat(%Core.PCtor{ctor: c, args: args}), do: "(pctor #{c} [#{join_pat(args)}])"

  defp canon_pat(%Core.PList{elems: ps, tail: tl}),
    do: "(plist [#{join_pat(ps)}] #{canon_ptail(tl)})"

  defp canon_pat(%Core.PStruct{name: n, fields: fs}),
    do: "(pstruct #{n} [#{Enum.map_join(fs, " ", fn {f, p} -> "(#{f} #{canon_pat(p)})" end)}])"

  defp canon_pat(%Core.PMap{pairs: ps}),
    do: "(pmap [#{Enum.map_join(ps, " ", fn {k, p} -> "(#{k} #{canon_pat(p)})" end)}])"

  defp join_pat(ps), do: Enum.map_join(ps, " ", &canon_pat/1)
  defp canon_ptail(:close), do: "close"
  defp canon_ptail(p), do: "(tail #{canon_pat(p)})"

  defp ported(mod, src), do: mod.emit(inj(Pratt.parse(src)))
  defp reference(src), do: canon(Core.from_expr(Pratt.parse(src)))

  # one pattern, extracted from a case arm head (the shared pattern parser).
  defp pat_of(src) do
    {:case, _, [{p, _, _} | _]} = Pratt.parse("case _scrut do\n  #{src} -> 0\nend")
    p
  end

  defp ported_pat(mod, src), do: mod.emit_pat(inj_pat(pat_of(src)))
  defp reference_pat(src), do: canon_pat(Core.from_pat(pat_of(src)))

  @expr_corpus [
    "1",
    "x",
    "'A'",
    ":ok",
    ~S|"hi"|,
    "-x",
    "not a",
    "1 + 2 * 3",
    "(1 + 2) * 3",
    "f(x, 1)",
    "g()",
    "Point(x: 1, y: 2)",
    "obj.field",
    "obj.f(1, 2)",
    "if c do 1 else 2 end",
    "if c do 1 end",
    "{1, 2}",
    "{:ok, x}",
    "[1, 2, 3]",
    "[1, 2 | rest]",
    "[]",
    "%{a: 1, b: x}",
    "%{}",
    "(p) -> p + 1",
    "(a, b) -> a * b",
    "() -> 0",
    "&(_1 + _2)",
    "&foo/2",
    "with y <- f(x) do y else z -> 0 end",
    "with a <- p(), b <- q(a) do a + b end",
    "case n do\n  0 -> \"z\"\n  m -> \"nz\"\nend",
    "f(a + b, c) * -d"
  ]

  @pat_corpus [
    "_",
    "x",
    "42",
    ~S|"hi"|,
    "true",
    "'A'",
    ":ok",
    "Some(v)",
    "None",
    "Wrap(Some(v))",
    "[a, b]",
    "[h | t]",
    "[]",
    "{a, b}",
    "{:ok, v}",
    "Point(x: a, y: b)",
    "%{k: w}"
  ]

  describe "self-hosting Core fixpoint — Rian lowering vs Rian.Core.from_expr (full surface)" do
    test "every surface expression lowers exactly like Rian.Core.from_expr", %{mod: mod} do
      for src <- @expr_corpus do
        assert ported(mod, src) == reference(src),
               "expr lowering diverged on #{inspect(src)}"
      end
    end

    test "every surface pattern lowers exactly like Rian.Core.from_pat", %{mod: mod} do
      for src <- @pat_corpus do
        assert ported_pat(mod, src) == reference_pat(src),
               "pattern lowering diverged on #{inspect(src)}"
      end
    end
  end

  describe "teeth — structure, nesting, and node kind are all preserved" do
    test "nested calls/labels/dots keep their shape", %{mod: mod} do
      assert ported(mod, "obj.f(1, 2)") == reference("obj.f(1, 2)")
      refute ported(mod, "f(a, b)") == ported(mod, "f(b, a)")
    end

    test "constructor and list patterns recurse, not flatten", %{mod: mod} do
      assert ported_pat(mod, "Wrap(Some(v))") == "(pctor Wrap [(pctor Some [(pvar v)])])"
      assert ported_pat(mod, "[h | t]") == "(plist [(pvar h)] (tail (pvar t)))"
    end

    test "different node kinds produce different Core", %{mod: mod} do
      refute ported(mod, "{1, 2}") == ported(mod, "[1, 2]")
      refute ported_pat(mod, "42") == ported_pat(mod, ~S|"42"|)
    end
  end

  # === reference-completeness ledger (selfhost_core vs Rian.Core) ===============
  # Every surface-reachable Core node kind, with a representative snippet and a
  # `ported?` flag. The Core port is complete over the surface front-door, so this
  # is a confirmation lock with teeth — if a future node stops lowering like
  # `Rian.Core.from_expr`/`from_pat`, the matching row flips and the build fails.
  # (Non-surface nodes — EVariant/EStruct/EConstRef, str_interp, PAs/PPin, rpat —
  # are produced only by Lower's resolution passes, so they're out of scope.)
  defp core_covers?(mod, src) do
    ported(mod, src) == reference(src)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp core_pat_covers?(mod, src) do
    ported_pat(mod, src) == reference_pat(src)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @core_exprs [
    {"ENum", "1", true},
    {"EId", "x", true},
    {"EChar", "'A'", true},
    {"EAtom", ":ok", true},
    {"EStr", ~S|"hi"|, true},
    {"EUnary", "-x", true},
    {"EBin", "1 + 2 * 3", true},
    {"ECall", "f(x, 1)", true},
    {"ELabel", "Point(x: 1, y: 2)", true},
    {"EDot", "obj.field", true},
    {"EIf (+ EBlock branches)", "if c do 1 else 2 end", true},
    {"ETuple", "{1, 2}", true},
    {"EList", "[1, 2, 3]", true},
    {"EMap", "%{a: 1}", true},
    {"ECase", "case n do\n  0 -> 1\n  m -> m\nend", true},
    {"ELambda", "(x) -> x + 1", true},
    {"ECapture", "&(_1 + _2)", true},
    {"ECaptureNamed", "&foo/2", true},
    {"EWith", "with y <- f(x) do y else z -> 0 end", true}
  ]

  @core_pats [
    {"PWild", "_", true},
    {"PVar", "x", true},
    {"PLit (int)", "42", true},
    {"PLit (str)", ~S|"hi"|, true},
    {"PChar", "'A'", true},
    {"PAtom", ":ok", true},
    {"PCtor", "Some(v)", true},
    {"PList", "[a, b]", true},
    {"PTuple", "{a, b}", true},
    {"PStruct", "Point(x: a, y: b)", true},
    {"PMap", "%{k: w}", true}
  ]

  describe "Core lowering completeness ledger (selfhost_core vs Rian.Core)" do
    test "every node's ported? flag matches reality", %{mod: mod} do
      expr_drift =
        for {name, src, ported?} <- @core_exprs, core_covers?(mod, src) != ported? do
          "expr #{name}: ported?=#{ported?} but port " <>
            "#{if core_covers?(mod, src), do: "REPRODUCES", else: "does NOT reproduce"} Rian.Core"
        end

      pat_drift =
        for {name, src, ported?} <- @core_pats, core_pat_covers?(mod, src) != ported? do
          "pat #{name}: ported?=#{ported?} but port " <>
            "#{if core_pat_covers?(mod, src), do: "REPRODUCES", else: "does NOT reproduce"} Rian.Core"
        end

      drift = expr_drift ++ pat_drift
      assert drift == [], "Core completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "Core node coverage is measured and must not regress" do
      total = length(@core_exprs) + length(@core_pats)
      ported = Enum.count(@core_exprs ++ @core_pats, fn {_, _, p} -> p end)
      IO.puts("\n  selfhost_core completeness: #{ported}/#{total} surface Core node kinds")
      assert ported == total
    end
  end
end
