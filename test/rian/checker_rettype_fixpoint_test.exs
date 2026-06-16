defmodule Rian.CheckerRetTypeFixpointTest do
  # async: false — loads compiler/checker.rian into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the type checker's SECOND ERROR SET — the
  # canonical type error, RETURN-TYPE mismatch (Rian.Check.check_return, ADR-0064/0034).
  # `compiler/checker.rian`'s `ret_bad/4` returns `true` iff a clause body's inferred type
  # provably contradicts the declared return: a generic return is skipped; a
  # constant-of-literals body that ADOPTS the declared width must FIT its range; otherwise
  # the inferred body type must be ASSIGNABLE (directional widening) to the return.
  #
  # LOCK: for each corpus function the port's `ret_bad` (over the body's FAITHFUL Core, the
  # clause's param env, an empty `ic`) must AGREE with whether the REAL `Rian.Check.check/1`
  # reports the return-type error. `check_return` runs before binds/bounds/numeric-mix in
  # the gate chain, so a return mismatch is the message that fires. The corpus uses
  # param/literal operands so the empty `ic` is irrelevant. Because the inference is itself
  # already equivalence-locked (checker_infer_fixpoint_test), agreeing body types compose
  # into an agreeing return decision.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/checker.rian"), :rian_checker_rettype_fixpoint)
    {:ok, mod: mod}
  end

  # {label, body expression, param env, declared return, full function (for the reference)}.
  # NEGATIVE = a provable return mismatch → BOTH the port and Rian.Check must flag it.
  @negative [
    {"Int64 ⋢ Float64", "a", %{"a" => "Int64"}, "Float64", "def f(a Int64) Float64 := a"},
    {"String ⋢ Int64", ~S|"hi"|, %{}, "Int64", ~S|def f() Int64 := "hi"|},
    {"narrowing Int16→Int8", "a", %{"a" => "Int16"}, "Int8", "def f(a Int16) Int8 := a"},
    {"Bool ⋢ Int64", "b", %{"b" => "Bool"}, "Int64", "def f(b Bool) Int64 := b"},
    {"literal out of range", "9999", %{}, "Int8", "def f() Int8 := 9999"},
    {"neg literal out of range", "-200", %{}, "Int8", "def f() Int8 := -200"},
    {"Vec elem out of range", "[1, 2, 9999]", %{}, "Vec(Int8)",
     "def f() Vec(Int8) := [1, 2, 9999]"}
  ]

  # POSITIVE = NO mismatch → BOTH must pass. Widening, literal adoption in range, identity,
  # int-literal→float, conservative unknown, and a generic return.
  @positive [
    {"Int32 ⊑ Float64", "a", %{"a" => "Int32"}, "Float64", "def f(a Int32) Float64 := a"},
    {"Int8 := 5 (adopts, in range)", "5", %{}, "Int8", "def f() Int8 := 5"},
    {"Int64 identity", "a", %{"a" => "Int64"}, "Int64", "def f(a Int64) Int64 := a"},
    {"int-lit ⊑ Float64", "66", %{}, "Float64", "def f() Float64 := 66"},
    {"Vec elems in range", "[1, 2, 3]", %{}, "Vec(Int8)", "def f() Vec(Int8) := [1, 2, 3]"},
    {"untyped param → unknown", "a", %{}, "Int64", "def f(a, b) Int64 := a"},
    {"generic return (skipped)", "x", %{"x" => "T"}, "T", "def id(x T) T forall T := x"}
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
  defp inj_arm({pat, _guard, body}), do: {:c_arm, inj_pat(pat), inj(body)}
  defp inj_pat(%Core.PVar{name: n}), do: {:p_var, n}
  defp inj_pat(%Core.PCtor{ctor: c, args: args}), do: {:p_ctor, c, Enum.map(args, &inj_pat/1)}
  defp inj_pat(_), do: :p_other

  defp port_ret(mod, body, env, ret),
    do: mod.ret_bad(inj(Core.from_expr(Pratt.parse(body))), ret, env, %{})

  # the reference's verdict isolated to the return-type gate by its message (the corpus is
  # built so a return mismatch is the only error a function carries, and check_return runs
  # before the binds/bounds/numeric-mix gates).
  defp ref_ret(src) do
    case Check.check(src) do
      :ok ->
        false

      {:error, msg} ->
        String.contains?(msg, "declared return type is") or
          String.contains?(msg, "out of range for")
    end
  end

  describe "ret_bad agrees with Rian.Check.check_return (the lock)" do
    test "every NEGATIVE case is flagged by BOTH the port and the reference", %{mod: mod} do
      for {label, body, env, ret, src} <- @negative do
        assert ref_ret(src),
               "reference did not flag the return mismatch in #{label}: #{inspect(src)}"

        assert port_ret(mod, body, env, ret),
               "port ret_bad missed the mismatch in #{label}: #{inspect(body)} ⋢ #{ret}"
      end
    end

    test "every POSITIVE case is passed by BOTH the port and the reference", %{mod: mod} do
      for {label, body, env, ret, src} <- @positive do
        refute ref_ret(src), "reference flagged a non-mismatch in #{label}: #{inspect(src)}"

        refute port_ret(mod, body, env, ret),
               "port ret_bad false-flagged #{label}: #{inspect(body)} : #{ret}"
      end
    end

    test "port and reference agree on every corpus entry (the equivalence lock)", %{mod: mod} do
      for {label, body, env, ret, src} <- @negative ++ @positive do
        assert port_ret(mod, body, env, ret) == ref_ret(src),
               "ret_bad DIVERGED from Rian.Check on #{label}: #{inspect(src)}"
      end
    end
  end
end
