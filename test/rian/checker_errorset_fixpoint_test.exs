defmodule Rian.CheckerErrorSetFixpointTest do
  # async: false — loads compiler/checker.rian into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Decl, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the type checker's FIFTH (and last) ERROR SET —
  # the `T | E` ERROR-SET check (Rian.Check.check_error_set, ADR-0040 §4). A function
  # declared `T | E` must not RETURN an `{:error, Tag}` whose `Tag` (a PascalCase
  # constructor) is not in `E`'s set. `compiler/checker.rian`'s `error_set_bad/3` returns
  # `true` iff such an extra tag is DIRECTLY built in the body. `tsets` maps a named error
  # type to its variant tags (built here exactly like the reference's `error_sets`).
  #
  # CONSERVATIVE Phase-1 slice (locked here): only DIRECTLY-built `{:error, Tag}` are
  # checked. The reference also unions callee-propagated error sets through a `with`-
  # without-`else` (a whole-program call-graph fixpoint); the corpus avoids that, so the
  # port's direct-only verdict agrees with the reference.
  #
  # LOCK: for each corpus program the port's `error_set_bad` (over the body's faithful
  # Core, the declared return, the program's `tsets`) must AGREE with whether the real
  # `Check.check/1` reports the error-set violation.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("compiler/checker.rian"), :rian_checker_errorset_fixpoint)
    {:ok, mod: mod}
  end

  @types "type DivErr := DivByZero | Overflow\n"

  # {label, body src (for the port), declared return, full program source (for the reference)}.
  # NEGATIVE = a tag not in the declared set → BOTH the port and Rian.Check must flag it.
  @negative [
    {"NotFound ∉ DivErr", "{:error, NotFound}", "Int53 | DivErr",
     @types <> "def bad() Int53 | DivErr := {:error, NotFound}"},
    {"applied-ctor tag ∉ DivErr", "{:error, NotFound(5)}", "Int53 | DivErr",
     @types <> "def bad() Int53 | DivErr := {:error, NotFound(5)}"}
  ]

  # POSITIVE = NO extra tag → BOTH must pass: a tag in the set, or a non-`T | E` return.
  @positive [
    {"DivByZero ∈ DivErr", "{:error, DivByZero}", "Int53 | DivErr",
     @types <> "def good() Int53 | DivErr := {:error, DivByZero}"},
    {"Overflow ∈ DivErr", "{:error, Overflow}", "Int53 | DivErr",
     @types <> "def good() Int53 | DivErr := {:error, Overflow}"},
    {"non-Result return (no declared set)", "5", "Int53", @types <> "def plain() Int53 := 5"}
  ]

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EChar{value: c}), do: {:c_char, c}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp inj(%Core.ETuple{elems: es}), do: {:c_tuple, Enum.map(es, &inj/1)}
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

  # `tsets`: a named sum type -> its variant tags — exactly the reference's `error_sets`.
  defp tsets(src) do
    prog = Decl.parse(src)
    types = Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)
    Map.new(types, fn t -> {t.name, Enum.map(t.variants, & &1.ctor)} end)
  end

  defp port_es(mod, body, ret, src),
    do: mod.error_set_bad(inj(Core.from_expr(Pratt.parse_body(body))), ret, tsets(src))

  defp ref_es(src) do
    case Check.check(src) do
      :ok -> false
      {:error, msg} -> String.contains?(msg, "not in its declared set")
    end
  end

  describe "error_set_bad agrees with Rian.Check.check_error_set (the lock)" do
    test "every NEGATIVE case is flagged by BOTH the port and the reference", %{mod: mod} do
      for {label, body, ret, src} <- @negative do
        assert ref_es(src), "reference did not flag the extra error tag in #{label}"
        assert port_es(mod, body, ret, src), "port error_set_bad missed the extra tag in #{label}"
      end
    end

    test "every POSITIVE case is passed by BOTH the port and the reference", %{mod: mod} do
      for {label, body, ret, src} <- @positive do
        refute ref_es(src), "reference flagged a non-violation in #{label}"
        refute port_es(mod, body, ret, src), "port error_set_bad false-flagged #{label}"
      end
    end

    test "port and reference agree on every corpus entry (the equivalence lock)", %{mod: mod} do
      for {label, body, ret, src} <- @negative ++ @positive do
        assert port_es(mod, body, ret, src) == ref_es(src),
               "error_set_bad DIVERGED from Rian.Check on #{label}"
      end
    end
  end
end
