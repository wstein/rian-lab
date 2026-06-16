defmodule Rian.CheckerNumMixFixpointTest do
  # async: false — loads compiler/checker.rian into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the type checker's FIRST ERROR SET — numeric
  # mix (ADR-0035). `compiler/checker.rian`'s inference (`infer_ic`) never rejects; it
  # infers `unknown` and moves on. `num_mix/3` is the first port of a Rian.Check
  # BOUNDARY check — the thing that turns the self-built compiler from self-COMPILING
  # into (partially) self-CHECKING: it returns `true` iff a clause body contains a
  # `+`/`-`/`*` whose two operands are concretely a different numeric KIND (one
  # int/uint, the other float) — a value never silently becomes a float.
  #
  # LOCK: for each corpus function, the port's `num_mix` (over the body's Core, the
  # clause's param env, an empty `ic`) must AGREE with whether the REAL
  # `Rian.Check.check/1` reports the numeric-mix error. The corpus uses param/literal
  # operands only, so the empty `ic` is irrelevant (an `ic`-dependent operand — a call
  # to a float-returning function — is the documented tail, where the port is merely
  # MORE conservative, never wrong). The reference's inference is itself already
  # equivalence-locked (checker_infer_fixpoint_test), so agreeing operand types compose
  # into an agreeing mix decision.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/checker.rian"), :rian_checker_nummix_fixpoint)
    {:ok, mod: mod}
  end

  # {label, body expression, param env, the full function (for the reference)}.
  # NEGATIVE = a provable int↔float mix → BOTH the port and Rian.Check must flag it.
  @negative [
    {"Int + float-lit", "a + 1.5", %{"a" => "Int64"}, "def f(a Int64) Float64 := a + 1.5"},
    {"Int - float-lit", "a - 2.5", %{"a" => "Int64"}, "def f(a Int64) Float64 := a - 2.5"},
    {"Int * Float param", "a * b", %{"a" => "Int64", "b" => "Float64"},
     "def f(a Int64, b Float64) Float64 := a * b"},
    {"float-lit + Int", "1 + x", %{"x" => "Float64"}, "def f(x Float64) Float64 := 1 + x"},
    {"UInt * float-lit", "u * 2.0", %{"u" => "UInt32"}, "def f(u UInt32) Float64 := u * 2.0"},
    {"Char + float-lit", "c + 1.5", %{"c" => "Char"}, "def f(c Char) Float64 := c + 1.5"},
    # the mix sits inside a comparison so the body is well-typed `Bool` (no return-type
    # error to fire first) — isolating the gate while proving the walk recurses.
    {"mix nested in comparison", "(a + 1.5) > a", %{"a" => "Int64"},
     "def f(a Int64) Bool := (a + 1.5) > a"}
  ]

  # POSITIVE = NO provable mix → BOTH must pass. Covers same-kind arithmetic, non-arith
  # operators, conservative `unknown` operands, and the div/rem exclusion.
  @positive [
    {"Int + Int", "a + b", %{"a" => "Int64", "b" => "Int64"},
     "def f(a Int64, b Int64) Int64 := a + b"},
    {"Float - Float", "a - b", %{"a" => "Float64", "b" => "Float64"},
     "def f(a Float64, b Float64) Float64 := a - b"},
    {"Int * int-lit", "a * 2", %{"a" => "Int64"}, "def f(a Int64) Int64 := a * 2"},
    {"Float + float-lit", "a + 1.0", %{"a" => "Float64"}, "def f(a Float64) Float64 := a + 1.0"},
    {"untyped operands (unknown)", "a + b", %{}, "def f(a, b) Int64 := a + b"},
    {"bare var, no arith", "a", %{"a" => "Int64"}, "def f(a Int64) Int64 := a"},
    # div/rem are NOT @arith — an Int÷Float is never a num-mix error (ADR-0035 is about
    # the implicit-widening operators); the port's `mix_op` excludes them to match.
    {"Int div int-lit", "a div 2", %{"a" => "Int64"}, "def f(a Int64) Int64 := a div 2"}
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

  defp port_mix(mod, body, env), do: mod.num_mix(inj(Core.from_expr(Pratt.parse(body))), env, %{})

  # the reference's verdict, isolated to the numeric-mix gate by its message. The corpus
  # is built so num-mix is the ONLY error a function can carry (well-typed otherwise), so
  # `:ok` ⇒ no mix and the mix message ⇒ mix.
  defp ref_mix(src) do
    case Check.check(src) do
      :ok -> false
      {:error, msg} -> String.contains?(msg, "no implicit Int↔Float")
    end
  end

  describe "num_mix agrees with Rian.Check.check_numeric_mix (the lock)" do
    test "every NEGATIVE case is flagged by BOTH the port and the reference", %{mod: mod} do
      for {label, body, env, src} <- @negative do
        assert ref_mix(src), "reference did not flag the mix in #{label}: #{inspect(src)}"

        assert port_mix(mod, body, env),
               "port num_mix missed the mix in #{label}: #{inspect(body)}"
      end
    end

    test "every POSITIVE case is passed by BOTH the port and the reference", %{mod: mod} do
      for {label, body, env, src} <- @positive do
        refute ref_mix(src), "reference flagged a non-mix in #{label}: #{inspect(src)}"
        refute port_mix(mod, body, env), "port num_mix false-flagged #{label}: #{inspect(body)}"
      end
    end

    test "port and reference agree on every corpus entry (the equivalence lock)", %{mod: mod} do
      for {label, body, env, src} <- @negative ++ @positive do
        assert port_mix(mod, body, env) == ref_mix(src),
               "num_mix DIVERGED from Rian.Check on #{label}: #{inspect(src)}"
      end
    end
  end
end
