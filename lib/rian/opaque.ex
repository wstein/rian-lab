defmodule Rian.Opaque do
  @moduledoc """
  Erases `opaque T := Base` abstract types (ADR-0067 / ADR-0043) from a parsed
  program, after the gates and before any emitter.

  An opaque is **nominal** to `Rian.Check` — distinct from its base, so a raw
  `Base` where a `T` is expected (or the reverse) is a type error — but it is
  **zero-cost** at runtime: the value *is* the base value, no wrapper, no box.
  This pass makes that real. Run after `Check.gate!`/`Reach.gate!` (which need the
  nominal view) and before lowering, it:

    1. substitutes every opaque name to its `base` in all type positions
       (params, returns, struct/variant fields, consts),
    2. rewrites the total constructor `T.of(x)` to the bare `x` in every clause
       body (an opaque adds no failure mode, so the constructor is the identity), and
    3. rewrites a declared `abstract` cast `v.base()` to the bare `v` (ADR-0067 §2 —
       the cast exposes the underlying representation, which *is* the value at runtime).

  After erasure no emitter ever sees an opaque type name or an opaque `.of` call —
  `opaque Token := String` reaches every target exactly as `String` would. A
  program with no opaques is returned unchanged (the common, zero-overhead case).
  """
  alias Rian.{IR, Pratt}
  alias Rian.IR.{Clause, Const, Func, Struct, Type, Variant}

  @doc "Erase all opaque types from a parsed program. A no-op when it has none."
  def erase(%{} = prog) do
    all = opaques(prog)
    if all == [], do: prog, else: do_erase(prog, erase_ctx(all))
  end

  # every `%IR.Opaque{}` in the program (top level + every module).
  defp opaques(prog) do
    Map.get(prog, :opaques, []) ++
      for(m <- Map.get(prog, :mods, []), o <- Map.get(m, :opaques, []), do: o)
  end

  # The erasure context: `names` is name->base for type substitution; `casts` is the
  # set of declared cast names, so `v.castname()` erases to `v` (ADR-0067 §2).
  defp erase_ctx(all) do
    names = Map.new(all, fn o -> {o.name, o.base} end)
    casts = for(o <- all, c <- Map.get(o, :casts, []), into: MapSet.new(), do: c.name)
    {names, casts}
  end

  defp do_erase(prog, ctx) do
    prog
    |> Map.update(:types, [], fn ts -> Enum.map(ts, &erase_type(&1, ctx)) end)
    |> Map.update(:structs, [], fn ss -> Enum.map(ss, &erase_struct(&1, ctx)) end)
    |> Map.update(:funcs, [], fn fs -> Enum.map(fs, &erase_func(&1, ctx)) end)
    |> Map.update(:mods, [], fn ms -> Enum.map(ms, &erase_mod(&1, ctx)) end)
  end

  defp erase_mod(%IR.Mod{} = m, ctx) do
    %IR.Mod{
      m
      | types: Enum.map(m.types, &erase_type(&1, ctx)),
        structs: Enum.map(m.structs, &erase_struct(&1, ctx)),
        consts: Enum.map(m.consts, &erase_const(&1, ctx)),
        funcs: Enum.map(m.funcs, &erase_func(&1, ctx))
    }
  end

  defp erase_func(%Func{} = f, {names, _casts} = ctx) do
    params = Enum.map(f.params, fn p -> %{p | type: subst(p.type, names)} end)

    %Func{
      f
      | params: params,
        ret: subst(f.ret, names),
        clauses: Enum.map(f.clauses, &erase_clause(&1, ctx))
    }
  end

  defp erase_type(%Type{} = t, {names, _} = _ctx) do
    %Type{t | variants: Enum.map(t.variants, fn v -> erase_variant(v, names) end)}
  end

  defp erase_variant(%Variant{} = v, names) do
    %Variant{v | fields: Enum.map(v.fields, fn f -> %{f | type: subst(f.type, names)} end)}
  end

  defp erase_struct(%Struct{} = s, {names, _} = _ctx) do
    %Struct{s | fields: Enum.map(s.fields, fn f -> %{f | type: subst(f.type, names)} end)}
  end

  defp erase_const(%Const{} = c, {names, _} = _ctx), do: %Const{c | type: subst(c.type, names)}

  defp erase_clause(%Clause{body: nil} = c, _ctx), do: c

  defp erase_clause(%Clause{body: body} = c, ctx),
    do: %Clause{c | body: strip(Pratt.parse_body(body), ctx)}

  # Substitute opaque names -> base in a type string. `\b…\b` keeps `Token` from
  # matching inside `TokenList`; the substitution covers compound types
  # (`Vec(Token)`, `Token | E`, tuples) since it is a plain word replacement.
  defp subst(nil, _names), do: nil

  defp subst(type, names) when is_binary(type) do
    Enum.reduce(names, type, fn {name, base}, acc ->
      Regex.replace(~r/\b#{Regex.escape(name)}\b/, acc, base)
    end)
  end

  # Rewrite the two opaque constructs that are runtime identities, recursively over
  # the expr AST: the constructor `T.of(x)` -> `x` (opaque `T`), and a declared cast
  # `v.castname()` -> `v` (ADR-0067 §2). A non-opaque `.of` (a `range` constructor)
  # and any other dot-call fall through to the generic tuple/list recursion.
  defp strip({:call, {:dot, {:id, n}, "of"}, [arg]}, {names, _} = ctx) when is_map_key(names, n),
    do: strip(arg, ctx)

  defp strip({:call, {:dot, head, cn}, []}, {_, casts} = ctx) do
    if MapSet.member?(casts, cn),
      do: strip(head, ctx),
      else: strip_into({:call, {:dot, head, cn}, []}, ctx)
  end

  defp strip(ast, ctx) when is_tuple(ast), do: strip_into(ast, ctx)
  defp strip(list, ctx) when is_list(list), do: Enum.map(list, &strip(&1, ctx))
  defp strip(other, _ctx), do: other

  defp strip_into(ast, ctx),
    do: ast |> Tuple.to_list() |> Enum.map(&strip(&1, ctx)) |> List.to_tuple()
end
