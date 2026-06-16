defmodule Rian.CheckerBoundsFixpointTest do
  # async: false — loads compiler/checker.rian into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Decl, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the type checker's FOURTH ERROR SET — the
  # PROTOCOL-BOUND violation (Rian.Check.check_bounds, ADR-0042 §2). At a call to a
  # bounded generic (`def g(x T) … forall T: P`), `compiler/checker.rian`'s
  # `bounds_bad/5` instantiates the callee's tvars from the argument types (`bind_all`,
  # reused from generic-return inference) and returns `true` iff a bound `T: P`
  # instantiates `T` to a CONCRETE type with no `impl P for that-type`.
  #
  # The port needs two tables the reference builds in `program_ic`: `fbounds` (a bounded
  # function's tvars/param-types/bounds) and `impls` (protocol → implementing types). The
  # test derives BOTH from the real `Check.program_ic`, projects them to the port's tuple
  # shape, and feeds the caller's body Core to `bounds_bad`.
  #
  # LOCK: for each corpus program the port's `bounds_bad` over the caller's body must
  # AGREE with whether the real `Check.check/1` reports the bound violation.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/checker.rian"), :rian_checker_bounds_fixpoint)
    {:ok, mod: mod}
  end

  @proto """
  protocol Show do
    def show(self Self) String
  end

  impl Show for Int53 do
    def show(x) := "ok"
  end

  def render(v C) String forall C: Show := show(v)
  """

  # {label, caller name, full program source}.
  # NEGATIVE = a provable bound violation → BOTH the port and Rian.Check must flag it.
  @negative [
    {"render(String) — no `impl Show for String`", "bad",
     @proto <> "\ndef bad() String := render(\"hi\")"},
    {"render(Float64) — no `impl Show for Float64`", "badf",
     @proto <> "\ndef badf() String := render(3.0)"}
  ]

  # POSITIVE = NO violation → BOTH must pass: the arg's inferred type HAS the impl, or
  # the instantiation stays generic (a forwarded type variable — conservatively unchecked).
  @positive [
    {"render(Int53) — `impl Show for Int53` exists", "good",
     @proto <> "\ndef good() String := render(5)"},
    {"render(C) — the tvar stays generic, never rejected", "relay",
     @proto <> "\ndef relay(z C) String forall C: Show := render(z)"}
  ]

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EChar{value: c}), do: {:c_char, c}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}
  defp inj(%Core.ECall{fun: %Core.EId{name: f}, args: as}), do: {:c_call, f, Enum.map(as, &inj/1)}
  defp inj(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, inj(c), inj(t), inj(e)}
  defp inj(%Core.EBlock{stmts: stmts}), do: {:c_block, Enum.map(stmts, &inj_stmt/1)}
  defp inj(%Core.ECase{scrut: s, arms: arms}), do: {:c_case, inj(s), Enum.map(arms, &inj_arm/1)}

  defp inj(%Core.EList{elems: elems, tail: tail}),
    do: {:c_list, Enum.map(elems, &inj/1), inj_tail(tail)}

  defp inj(%Core.ELambda{params: ps, body: body}),
    do: {:c_lambda, Enum.map(ps, &inj_param/1), inj(body)}

  defp inj_tail(nil), do: :t_close
  defp inj_tail(:close), do: :t_close
  defp inj_tail(tail), do: {:t_cons, inj(tail)}
  defp inj_param({n, nil}), do: {:lp, n, :pt_none}
  defp inj_param({n, t}), do: {:lp, n, {:pt_some, t}}
  defp inj_stmt({:expr, e}), do: {:s_expr, inj(e)}
  defp inj_stmt({:bind, n, e}), do: {:s_bind, n, inj(e)}
  defp inj_stmt({:typed_bind, n, ann, e}), do: {:s_typed_bind, n, ann, inj(e)}
  defp inj_arm({pat, _guard, body}), do: {:c_arm, inj_pat(pat), inj(body)}
  defp inj_pat(%Core.PVar{name: n}), do: {:p_var, n}
  defp inj_pat(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &inj_pat/1)}
  defp inj_pat(_), do: :p_other

  # project the reference's `ic.fbounds` (`%{g => %{params, tvars, bounds}}`) and
  # `ic.impls` (`%{proto => MapSet}`) into the port's tuple shape: `{:fb, tvars, params,
  # [{:p_bound, tvar, protos}]}` and `%{proto => [types]}`.
  defp port_fbounds(fbounds) do
    Map.new(fbounds, fn {g, %{params: params, tvars: tvars, bounds: bounds}} ->
      pbounds = Enum.map(bounds, fn {tv, protos} -> {:p_bound, tv, protos} end)
      {g, {:fb, tvars, params, pbounds}}
    end)
  end

  defp port_impls(impls), do: Map.new(impls, fn {p, tys} -> {p, MapSet.to_list(tys)} end)

  defp caller(src, name) do
    prog = Decl.parse(src)
    Enum.find(prog.funcs, &(&1.name == name))
  end

  defp port_bounds(mod, src, name) do
    ic = Check.program_ic(Decl.parse(src))
    f = caller(src, name)
    env = Map.new(f.params, fn p -> {p.name, p.type} end)
    body = inj(Core.from_expr(Pratt.parse_body(hd(f.clauses).body)))
    mod.bounds_bad(body, env, %{}, port_fbounds(ic.fbounds), port_impls(ic.impls))
  end

  defp ref_bounds(src) do
    case Check.check(src) do
      :ok -> false
      {:error, msg} -> String.contains?(msg, "requires") and String.contains?(msg, "has no `impl")
    end
  end

  describe "bounds_bad agrees with Rian.Check.check_bounds (the lock)" do
    test "every NEGATIVE case is flagged by BOTH the port and the reference", %{mod: mod} do
      for {label, name, src} <- @negative do
        assert ref_bounds(src), "reference did not flag the bound violation in #{label}"
        assert port_bounds(mod, src, name), "port bounds_bad missed the violation in #{label}"
      end
    end

    test "every POSITIVE case is passed by BOTH the port and the reference", %{mod: mod} do
      for {label, name, src} <- @positive do
        refute ref_bounds(src), "reference flagged a non-violation in #{label}"
        refute port_bounds(mod, src, name), "port bounds_bad false-flagged #{label}"
      end
    end

    test "port and reference agree on every corpus entry (the equivalence lock)", %{mod: mod} do
      for {label, name, src} <- @negative ++ @positive do
        assert port_bounds(mod, src, name) == ref_bounds(src),
               "bounds_bad DIVERGED from Rian.Check on #{label}"
      end
    end
  end
end
