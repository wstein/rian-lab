defmodule Rian.Capability do
  use Rian.Ann

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
  @rian_sig "pub def rust_param(a Symbol, t String) String"
  @spec rust_param(atom(), String.t()) :: String.t()
  # A `Fn(args.., ret)` callback parameter lowers to argument-position `&impl Fn(args) -> ret`
  # (zero-cost, monomorphized) regardless of capability — a closure is passed BY REFERENCE
  # (ADR-0061, closure-as-value). The `&` matters: a recursive higher-order fn (`map`/`filter`/
  # `reduce`) calls `f(x)` AND re-passes `f` to itself; a by-value `impl Fn` would be moved on
  # the recursive call (use-after-move), whereas `&impl Fn` is `Copy`, so both uses are fine.
  def rust_param(_cap, "Fn(" <> _ = t), do: "&impl " <> fn_trait(t)
  def rust_param(:iso, t), do: owned(t)
  def rust_param(:val, t), do: if(copy?(t), do: rust_name(t), else: borrowed(t))
  def rust_param(:ref, t), do: "&mut " <> owned(t)
  def rust_param(:tag, t), do: "&" <> owned(t)

  # `Fn(A.., R)` (last component is the return, ADR-0042) -> the Rust `Fn(A..) -> R` trait
  # spelling, every inner type lowered via `owned/1`. The caller prefixes `impl ` (a parameter)
  # or wraps `Box<dyn …>` (an owned/return position — see `owned/1`).
  defp fn_trait("Fn(" <> rest) do
    inner = String.replace_suffix(rest, ")", "")

    case Rian.TypeStr.split_top_commas(inner) do
      [] ->
        "Fn()"

      parts ->
        {args, [ret]} = Enum.split(parts, length(parts) - 1)
        "Fn(" <> Enum.map_join(args, ", ", &owned/1) <> ") -> " <> owned(ret)
    end
  end

  @rian_sig "pub def copy?(t String) Bool"
  @spec copy?(String.t()) :: boolean()
  def copy?(t), do: t in @copy

  # Source primitive -> Rust spelling (`Int64` -> `i64`, …). Nominal types and
  # `Vec(...)` pass through unchanged. Only exact `@copy` members are remapped,
  # so a nominal type that happens to start with `Int` is untouched.
  @rian_sig "pub def rust_name(t String) String"
  @spec rust_name(String.t()) :: String.t()
  def rust_name(t), do: if(t in @copy, do: rust_scalar(t), else: t)

  # `Int53` is the ECMAScript-safe integer (a native JS `number` is exact only to
  # 2^53); on the BEAM/Rust it is a 64-bit integer (`i64`).
  defp rust_scalar("Int53"), do: "i64"
  defp rust_scalar("Int" <> w), do: "i" <> w
  defp rust_scalar("UInt" <> w), do: "u" <> w
  defp rust_scalar("Float" <> w), do: "f" <> w
  defp rust_scalar("Bool"), do: "bool"
  defp rust_scalar("Char"), do: "char"

  @rian_sig "pub def owned(a String) String"
  @spec owned(String.t()) :: String.t()
  def owned("String"), do: "String"

  # `Int` is arbitrary precision (ADR-0064) — it needs a bignum on Rust (`i128` is
  # still bounded), which is not implemented. Fail loudly instead of emitting an
  # undefined `Int` type. (`Rian.Reach` already pins `Int` off `:rs`, so this is a
  # backstop for a direct `--rust` on un-gated code.)
  def owned("Int"),
    do:
      raise(
        ArgumentError,
        "`Int` (arbitrary precision, ADR-0064) has no Rust lowering yet — it needs a bignum; " <>
          "use a fixed width (`Int64`) on Rust, or target the BEAM/JS"
      )

  # an owned/return-position closure (ADR-0061): `Box<dyn Fn(args) -> ret>` (the boxed,
  # heap-allocated trait object that a returned closure needs — a `move` `Box::new(|…| …)`
  # at the construction site). Covers a bare `Fn(...)` return and a nested `Option(Fn(...))`.
  def owned("Fn(" <> _ = t), do: "Box<dyn " <> fn_trait(t) <> ">"

  def owned("Vec(" <> rest) do
    # strip exactly the one `)` that closes this `Vec(`, not every trailing paren —
    # `trim_trailing/2` would eat both in `Vec(Option(T))`, leaving `Option(T` and
    # emitting the malformed `Vec<Option(T>`. The inner type is then lowered in turn,
    # so nested generics (`Vec(Option(T))` -> `Vec<Option<T>>`) round-trip.
    inner = String.replace_suffix(rest, ")", "")
    "Vec<" <> owned(inner) <> ">"
  end

  def owned(t) do
    case parametric(t) do
      # any other generic nominal `Name(A, B)` -> Rust `Name<A, B>` (e.g.
      # `Option(Int64)` -> `Option<i64>`), each argument lowered in turn
      {name, args} -> name <> "<" <> Enum.map_join(args, ", ", &owned/1) <> ">"
      nil -> rust_name(t)
    end
  end

  # `Name(A, B, …)` -> `{name, [A, B, …]}` splitting on top-level commas only
  # (so nested generics like `Map(String, Vec(Int64))` parse); `nil` otherwise
  defp parametric(t) do
    case Regex.run(~r/^([A-Za-z_]\w*)\((.*)\)$/, t) do
      [_, name, inner] -> {name, split_top_level(inner)}
      _ -> nil
    end
  end

  defp split_top_level(s), do: Rian.TypeStr.split_top_commas(s)

  @rian_sig "pub def borrowed(a String) String"
  @spec borrowed(String.t()) :: String.t()
  def borrowed("String"), do: "&str"

  def borrowed("Vec(" <> rest) do
    # strip only the closing `)` of this `Vec(` (see `owned/1`), so a nested element
    # type (`Vec(Option(T))` -> `&[Option<T>]`) lowers correctly.
    inner = String.replace_suffix(rest, ")", "")
    "&[" <> owned(inner) <> "]"
  end

  def borrowed(t), do: "&" <> rust_name(t)

  # ── BEAM-side legality ─────────────────────────────────────────────────
  @rian_sig "pub def beam_legal!(a Symbol) Symbol"
  @spec beam_legal!(atom()) :: :ok
  def beam_legal!(:ref),
    do: raise("`ref` is not permitted on the BEAM target (no process-local proof in PoC)")

  def beam_legal!(_), do: :ok

  # ── Linearity (use-once) check ─────────────────────────────────────────
  @doc "Check a single expression: iso/ref vars in `env` must be used at most once."
  @spec lin_check(map(), term()) :: :ok | {:error, list()}
  def lin_check(env, ast), do: verdict(env, count_uses(ast))

  @doc """
  Check a straight-line block. `bindings` is [{name, capability, rhs_ast}];
  each binding name enters scope (with its capability) for later bindings/final.
  """
  @spec lin_check_block(map(), list(), term()) :: :ok | {:error, list()}
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
  @spec count_uses(term()) :: map()
  def count_uses(ast), do: count_uses(ast, MapSet.new())

  # `bound` holds names bound locally; they shadow the outer linear environment.
  defp count_uses({:id, x}, bound), do: if(MapSet.member?(bound, x), do: %{}, else: %{x => 1})
  defp count_uses({:num, _}, _bound), do: %{}
  defp count_uses({:str, _}, _bound), do: %{}
  defp count_uses({:char, _}, _bound), do: %{}
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
