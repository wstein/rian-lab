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

  @copy ~w(i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char)

  # ── Rust parameter-type lowering ───────────────────────────────────────
  def rust_param(:iso, t), do: owned(t)
  def rust_param(:val, t), do: if(copy?(t), do: t, else: borrowed(t))
  def rust_param(:ref, t), do: "&mut " <> owned(t)
  def rust_param(:tag, t), do: "&" <> owned(t)

  def copy?(t), do: t in @copy

  def owned("str"), do: "String"

  def owned("Vec(" <> rest) do
    inner = String.trim_trailing(rest, ")")
    "Vec<" <> owned(inner) <> ">"
  end

  def owned(t), do: t

  def borrowed("str"), do: "&str"

  def borrowed("Vec(" <> rest) do
    inner = String.trim_trailing(rest, ")")
    "&[" <> owned(inner) <> "]"
  end

  def borrowed(t), do: "&" <> t

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

  # variable occurrence counts in a Pratt AST
  def count_uses({:id, x}), do: %{x => 1}
  def count_uses({:num, _}), do: %{}
  def count_uses({:bin, _, l, r}), do: merge(count_uses(l), count_uses(r))
  def count_uses({:unary, _, x}), do: count_uses(x)
  def count_uses({:field, o, _}), do: count_uses(o)
  def count_uses({:path, o, _}), do: count_uses(o)

  def count_uses({:call, f, args}),
    do: Enum.reduce([f | args], %{}, fn n, acc -> merge(acc, count_uses(n)) end)

  defp merge(a, b), do: Map.merge(a, b, fn _, x, y -> x + y end)
end
