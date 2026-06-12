defmodule Rian.Capability do
  @moduledoc """
  Lowers Rian reference capabilities to each target.

  Rust signature lowering (capability + type -> parameter type):
      val + Copy   -> by value (i64)        iso + str    -> String
      val + str    -> &str                  iso + Vec(T) -> Vec<T>
      val + Vec(T) -> &[T]                   iso + other  -> T   (move)
      val + other  -> &T                     ref + T      -> &mut <owned T>
                                             tag + T      -> &<owned T>

  BEAM-side typestate: there is no borrow checker, so capabilities become a
  LINEARITY check — an `iso`/`ref` binding may be used at most once along any
  path; `val` is freely shareable. `ref` is rejected on the BEAM target.
  """

  # Crystal-family primitive vocabulary (ADR-0033). The `Copy` set is the
  # width-explicit scalars (Int*/UInt*/Float*) plus Bool/Char; `String`/`Symbol`
  # are not Copy. Source names map to each target — `Int64` is Rian's name, not
  # Rust's `i64`.
  @copy for(p <- ~w(Int UInt), w <- ~w(8 16 32 64 128), do: p <> w) ++
          ~w(Int53 Float32 Float64 Bool Char)

  # ── Rust parameter-type lowering ───────────────────────────────────────
  def rust_param(:iso, t), do: owned(t)
  def rust_param(:val, t), do: if(copy?(t), do: rust_name(t), else: borrowed(t))
  def rust_param(:ref, t), do: "&mut " <> owned(t)
  def rust_param(:tag, t), do: "&" <> owned(t)

  def copy?(t), do: t in @copy

  # Source primitive -> Rust spelling (`Int64` -> `i64`, …). Nominal types and
  # `Vec(...)` pass through unchanged. Only exact `@copy` members are remapped,
  # so a nominal type that happens to start with `Int` is untouched.
  def rust_name(t), do: if(t in @copy, do: rust_scalar(t), else: t)

  # `Int53` is the ECMAScript-safe integer (a native JS `number` is exact only to
  # 2^53); on the BEAM/Rust it is a 64-bit integer (`i64`).
  defp rust_scalar("Int53"), do: "i64"
  defp rust_scalar("Int" <> w), do: "i" <> w
  defp rust_scalar("UInt" <> w), do: "u" <> w
  defp rust_scalar("Float" <> w), do: "f" <> w
  defp rust_scalar("Bool"), do: "bool"
  defp rust_scalar("Char"), do: "char"

  def owned("String"), do: "String"

  def owned("Vec(" <> rest) do
    inner = String.trim_trailing(rest, ")")
    "Vec<" <> owned(inner) <> ">"
  end

  def owned(t), do: rust_name(t)

  def borrowed("String"), do: "&str"

  def borrowed("Vec(" <> rest) do
    inner = String.trim_trailing(rest, ")")
    "&[" <> owned(inner) <> "]"
  end

  def borrowed(t), do: "&" <> rust_name(t)

  # ── BEAM-side legality ─────────────────────────────────────────────────
  def beam_legal!(:ref),
    do: raise("`ref` is not permitted on the BEAM target (no process-local proof in PoC)")

  def beam_legal!(_), do: :ok

  # ── Linearity (use-once) check ─────────────────────────────────────────
  @doc "Check a single expression: iso/ref vars in `env` must be used at most once."
  def lin_check(env, ast), do: verdict(env, count_uses(ast))

  @doc """
  Check a straight-line block. `bindings` is [{name, capability, rhs_ast}];
  each binding name enters scope (with its capability) for later bindings/final.
  """
  def lin_check_block(env, bindings, final) do
    {total, env2} =
      Enum.reduce(bindings, {%{}, env}, fn {name, cap, ast}, {acc, e} ->
        {merge(acc, count_uses(ast)), Map.put(e, name, cap)}
      end)

    verdict(env2, merge(total, count_uses(final)))
  end

  defp verdict(env, uses) do
    bad = for {v, n} <- uses, n > 1, Map.get(env, v) in [:iso, :ref], do: {v, n}
    if bad == [], do: :ok, else: {:error, bad}
  end

  @doc """
  Free-variable occurrence counts in a Pratt expression AST.

  Total over every node the parser produces. Binders shadow the linear
  environment (lambda parameters and block bindings do not count as uses of an
  outer variable), and `if` is **branch-aware**: a variable consumed in both
  arms is consumed once (`max` over arms), so a value moved once per branch is
  legal. Counting is otherwise additive along a path.
  """
  def count_uses(ast), do: count_uses(ast, MapSet.new())

  # `bound` holds names bound locally; they shadow the outer linear environment.
  defp count_uses({:id, x}, bound), do: if(MapSet.member?(bound, x), do: %{}, else: %{x => 1})
  defp count_uses({:num, _}, _bound), do: %{}
  defp count_uses({:str, _}, _bound), do: %{}
  defp count_uses({:atom, _}, _bound), do: %{}
  defp count_uses({:dot, head, _name}, bound), do: count_uses(head, bound)
  defp count_uses({:cap_arg, _}, _bound), do: %{}
  defp count_uses({:capture, body}, bound), do: count_uses(body, bound)
  defp count_uses({:capture_named, path, _}, bound), do: count_uses(path, bound)
  defp count_uses({:unary, _, x}, bound), do: count_uses(x, bound)
  defp count_uses({:bin, _, l, r}, bound), do: merge(count_uses(l, bound), count_uses(r, bound))

  defp count_uses({:call, f, args}, bound),
    do: Enum.reduce([f | args], %{}, fn n, acc -> merge(acc, count_uses(n, bound)) end)

  defp count_uses({:list_lit, elems, tail}, bound) do
    base = Enum.reduce(elems, %{}, fn e, acc -> merge(acc, count_uses(e, bound)) end)

    case tail do
      {:tail, tl} -> merge(base, count_uses(tl, bound))
      nil -> base
    end
  end

  defp count_uses({:map_lit, pairs}, bound),
    do: Enum.reduce(pairs, %{}, fn {_k, v}, acc -> merge(acc, count_uses(v, bound)) end)

  defp count_uses({:lambda, params, body}, bound) do
    inner = Enum.reduce(params, bound, fn {n, _}, acc -> MapSet.put(acc, n) end)
    count_uses(body, inner)
  end

  defp count_uses({:if, cond, then_arm, else_arm}, bound) do
    merge(
      count_uses(cond, bound),
      max_merge(count_uses(then_arm, bound), count_uses(else_arm, bound))
    )
  end

  defp count_uses({:case, scrut, arms}, bound) do
    # branch-aware (max over arms, like `if`); each arm's pattern variables
    # shadow the outer linear environment within that arm.
    branches =
      arms
      |> Enum.map(fn {pat, guard, body} ->
        inner = MapSet.union(bound, pat_vars(pat))
        guard_uses = if guard, do: count_uses(guard, inner), else: %{}
        merge(guard_uses, count_uses(body, inner))
      end)
      |> Enum.reduce(%{}, &max_merge/2)

    merge(count_uses(scrut, bound), branches)
  end

  defp count_uses({:block, stmts}, bound), do: count_block(stmts, bound, %{})

  defp count_block([], _bound, acc), do: acc

  defp count_block([{:bind, n, e} | rest], bound, acc),
    do: count_block(rest, MapSet.put(bound, n), merge(acc, count_uses(e, bound)))

  defp count_block([{:typed_bind, n, _t, e} | rest], bound, acc),
    do: count_block(rest, MapSet.put(bound, n), merge(acc, count_uses(e, bound)))

  defp count_block([{:expr, e} | rest], bound, acc),
    do: count_block(rest, bound, merge(acc, count_uses(e, bound)))

  defp merge(a, b), do: Map.merge(a, b, fn _, x, y -> x + y end)
  defp max_merge(a, b), do: Map.merge(a, b, fn _, x, y -> max(x, y) end)

  # variables a `case` pattern binds (they shadow the linear env within the arm)
  defp pat_vars({:var, x}), do: MapSet.new([x])

  defp pat_vars({:ctor, _, args}),
    do: Enum.reduce(args, MapSet.new(), &MapSet.union(pat_vars(&1), &2))

  defp pat_vars(_), do: MapSet.new()
end
