defmodule Rian.CheckerBindsFixpointTest do
  # async: false — loads compiler/checker.rian into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Decl, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the type checker's THIRD ERROR SET — the
  # TYPED-BINDING mismatch (Rian.Check.check_binds/bind_mismatch, ADR-0034/0064).
  # `compiler/checker.rian`'s `binds_bad/3` walks a clause's CBlock statements,
  # threading the growing env, and returns `true` iff a `name Ann := value` has a
  # value that provably contradicts `Ann`: a constant-of-literals must FIT the
  # declared width, an integer literal never adopts a float annotation, otherwise the
  # inferred value type must be ASSIGNABLE to it. It reuses the lit-adopt / range /
  # assignable machinery already locked for the return-type set (error set #2).
  #
  # LOCK: for each corpus function the port's `binds_bad` (over the body's FAITHFUL
  # Core stmts, the clause's param env, an empty `ic`) must AGREE with whether the
  # REAL `Rian.Check.check/1` reports the binding error. The corpus gives every
  # function a VALID return so `check_return` (which runs before `check_binds` in the
  # gate chain) passes — the binding error is the only one that fires. With an empty
  # `ic` the oracle's `range`-typed binding case never fires, the same conservative
  # slice the port covers.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/checker.rian"), :rian_checker_binds_fixpoint)
    {:ok, mod: mod}
  end

  # {label, param env, full function source}. The block body for the port is extracted
  # from `src` via `Decl` — the SAME `c.body` the reference's `check_binds` parses.
  # NEGATIVE = a provable binding mismatch → BOTH the port and Rian.Check must flag it.
  @negative [
    {"Int8 := 9999 (out of range)", %{}, "def f() Int64\n  x Int8 := 9999\n  5\nend"},
    {"Int64 := String", %{}, ~s|def f() Int64\n  s Int64 := "hi"\n  s\nend|},
    {"Float64 := 66 (int lit ⋢ float)", %{}, "def f() Int64\n  y Float64 := 66\n  5\nend"},
    {"Int8 := 200 after a valid bind", %{},
     "def f() Int64\n  a Int8 := 5\n  b Int8 := 200\n  5\nend"}
  ]

  # POSITIVE = NO mismatch → BOTH must pass. In-range literal, adoption, identity-widen,
  # an untyped bind (unchecked), and a float literal adopting a float type.
  @positive [
    {"Int8 := 5 (in range)", %{}, "def f() Int64\n  x Int8 := 5\n  5\nend"},
    {"Int64 := 5 (adopts)", %{}, "def f() Int64\n  a Int64 := 5\n  a\nend"},
    {"untyped bind (unchecked)", %{}, "def f() Int64\n  a := 5\n  a\nend"},
    {"Float64 := 6.0 (float lit adopts)", %{}, "def f() Int64\n  z Float64 := 6.0\n  5\nend"}
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

  defp port_binds(mod, src, env) do
    body =
      src
      |> Decl.parse()
      |> Map.fetch!(:funcs)
      |> hd()
      |> Map.fetch!(:clauses)
      |> hd()
      |> Map.fetch!(:body)

    {:c_block, stmts} = inj(Core.from_expr(Pratt.parse_body(body)))
    mod.binds_bad(stmts, env, %{})
  end

  # the reference's verdict isolated to the binding gate by its message (the corpus is
  # built so a binding mismatch is the only error a function carries — check_return runs
  # before check_binds and passes on every valid-return corpus body).
  defp ref_binds(src) do
    case Check.check(src) do
      :ok ->
        false

      {:error, msg} ->
        String.contains?(msg, "binding declared") or
          String.contains?(msg, "does not adopt the float type") or
          String.contains?(msg, "out of range for")
    end
  end

  describe "binds_bad agrees with Rian.Check.check_binds (the lock)" do
    test "every NEGATIVE case is flagged by BOTH the port and the reference", %{mod: mod} do
      for {label, env, src} <- @negative do
        assert ref_binds(src),
               "reference did not flag the binding mismatch in #{label}: #{inspect(src)}"

        assert port_binds(mod, src, env),
               "port binds_bad missed the mismatch in #{label}: #{inspect(src)}"
      end
    end

    test "every POSITIVE case is passed by BOTH the port and the reference", %{mod: mod} do
      for {label, env, src} <- @positive do
        refute ref_binds(src), "reference flagged a non-mismatch in #{label}: #{inspect(src)}"

        refute port_binds(mod, src, env),
               "port binds_bad false-flagged #{label}: #{inspect(src)}"
      end
    end

    test "port and reference agree on every corpus entry (the equivalence lock)", %{mod: mod} do
      for {label, env, src} <- @negative ++ @positive do
        assert port_binds(mod, src, env) == ref_binds(src),
               "binds_bad DIVERGED from Rian.Check on #{label}: #{inspect(src)}"
      end
    end
  end
end
