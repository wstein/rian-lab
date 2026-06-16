defmodule Rian.Shadow do
  @moduledoc """
  Capture-avoiding `:=` shadow rename over the Core IR (ADR-0034).

  A Rian block may rebind a name (`x := …; x := …`). On targets whose binding
  forms forbid same-scope re-declaration — JS `let`/`const`, Kotlin `val`/`var` —
  the second binding is a compile error unless it is given a fresh name. This pass
  rewrites a Core `EBlock` statement list so every *same-scope* binding is unique
  and every reference resolves to the binding in force at its position, **before**
  the emitter turns binds into target syntax.

  The fresh-name *scheme* is target-specific (JS appends a JS-valid `$` suffix;
  Kotlin cannot use `$`/`@` in a plain identifier, so it backtick-quotes the
  fresh name) — the caller supplies `fresh` as `fn base, count -> name end`. The
  renaming *logic* is shared. Erlang uses a different scheme entirely
  (`@`-versioned scope vars in `Rian.Beam`); there is no fresh-var marker valid on
  every target, which is why this lives on the Core IR rather than in one emitter.

  `dedup/3` seeds the version map with the clause params so a `:=` rebinding a
  parameter (already bound in the clause scope) is renamed rather than
  re-declared. Each nested Rian block is its own target scope, so only rebinds
  within one block are renamed; references thread out through the rename map `r`.
  """
  alias Rian.Core.{EBlock, ECase, EId, PCtor, PList, PStruct, PTuple, PVar}

  @doc """
  Rewrite `stmts` (a Core `EBlock` stmt list) so shadowing binds get fresh names.

  `params` are the clause parameter names (seeded so a param rebind renames);
  `fresh` is `fn base, count -> fresh_name end`, the target's fresh-name scheme.
  """
  @spec dedup(list(), list(), fun()) :: term()
  def dedup(stmts, params, fresh), do: ded_block(stmts, %{}, Map.new(params, &{&1, 1}), fresh)

  defp ded_block(stmts, r, ver, fresh) do
    {rev, _r, _ver} =
      Enum.reduce(stmts, {[], r, ver}, fn
        {:bind, n, e}, acc -> ded_bind(n, nil, e, acc, fresh)
        {:typed_bind, n, t, e}, acc -> ded_bind(n, t, e, acc, fresh)
        {:expr, e}, {acc, r, ver} -> {[{:expr, ded_expr(e, r, fresh)} | acc], r, ver}
      end)

    Enum.reverse(rev)
  end

  defp ded_bind(n, t, e, {acc, r, ver}, fresh) do
    e2 = ded_expr(e, r, fresh)
    count = Map.get(ver, n, 0)

    {name, r2} =
      if count == 0 do
        # first binding in this block shadows any outer rename of the same name
        {n, Map.delete(r, n)}
      else
        new = fresh.(n, count)
        {new, Map.put(r, n, new)}
      end

    stmt = if t, do: {:typed_bind, name, t, e2}, else: {:bind, name, e2}
    {[stmt | acc], r2, Map.put(ver, n, count + 1)}
  end

  # rename free references through `r`, descending into nested binders with the
  # shadowed names removed (nested blocks open a fresh scope; `case` arm patterns
  # bind their own vars)
  defp ded_expr(%EId{name: x} = node, r, _fresh), do: %{node | name: Map.get(r, x, x)}

  defp ded_expr(%EBlock{stmts: stmts} = node, r, fresh),
    do: %{node | stmts: ded_block(stmts, r, %{}, fresh)}

  defp ded_expr(%ECase{scrut: s, arms: arms} = node, r, fresh) do
    arms2 =
      Enum.map(arms, fn {pat, g, b} ->
        inner = Map.drop(r, pat_var_names(pat))
        {pat, g && ded_expr(g, inner, fresh), ded_expr(b, inner, fresh)}
      end)

    %{node | scrut: ded_expr(s, r, fresh), arms: arms2}
  end

  defp ded_expr(node, r, fresh) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.reduce(node, fn {k, v}, acc -> %{acc | k => ded_expr(v, r, fresh)} end)
  end

  defp ded_expr(list, r, fresh) when is_list(list), do: Enum.map(list, &ded_expr(&1, r, fresh))

  defp ded_expr(tuple, r, fresh) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&ded_expr(&1, r, fresh)) |> List.to_tuple()

  defp ded_expr(other, _r, _fresh), do: other

  defp pat_var_names(%PVar{name: n}), do: [n]
  defp pat_var_names(%PCtor{args: ps}), do: Enum.flat_map(ps, &pat_var_names/1)
  defp pat_var_names(%PList{elems: ps, tail: t}), do: Enum.flat_map([t | ps], &pat_var_names/1)
  defp pat_var_names(%PTuple{elems: ps}), do: Enum.flat_map(ps, &pat_var_names/1)

  defp pat_var_names(%PStruct{fields: fs}),
    do: Enum.flat_map(fs, fn {_l, p} -> pat_var_names(p) end)

  defp pat_var_names(_), do: []
end
