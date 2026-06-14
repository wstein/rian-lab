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
       (params, returns, struct/variant fields, consts), and
    2. rewrites the total constructor `T.of(x)` to the bare `x` in every clause
       body (an opaque adds no failure mode, so the constructor is the identity).

  After erasure no emitter ever sees an opaque type name or an opaque `.of` call —
  `opaque Token := String` reaches every target exactly as `String` would. A
  program with no opaques is returned unchanged (the common, zero-overhead case).
  """
  alias Rian.{IR, Pratt}
  alias Rian.IR.{Clause, Const, Func, Struct, Type, Variant}

  @doc "Erase all opaque types from a parsed program. A no-op when it has none."
  def erase(%{} = prog) do
    names = opaque_names(prog)
    if names == %{}, do: prog, else: do_erase(prog, names)
  end

  # name -> base over the whole program (top level + every module).
  defp opaque_names(prog) do
    locals = Map.get(prog, :opaques, [])
    nested = for m <- Map.get(prog, :mods, []), o <- Map.get(m, :opaques, []), do: o
    Map.new(locals ++ nested, fn o -> {o.name, o.base} end)
  end

  defp do_erase(prog, names) do
    prog
    |> Map.update(:types, [], fn ts -> Enum.map(ts, &erase_type(&1, names)) end)
    |> Map.update(:structs, [], fn ss -> Enum.map(ss, &erase_struct(&1, names)) end)
    |> Map.update(:funcs, [], fn fs -> Enum.map(fs, &erase_func(&1, names)) end)
    |> Map.update(:mods, [], fn ms -> Enum.map(ms, &erase_mod(&1, names)) end)
  end

  defp erase_mod(%IR.Mod{} = m, names) do
    %IR.Mod{
      m
      | types: Enum.map(m.types, &erase_type(&1, names)),
        structs: Enum.map(m.structs, &erase_struct(&1, names)),
        consts: Enum.map(m.consts, &erase_const(&1, names)),
        funcs: Enum.map(m.funcs, &erase_func(&1, names))
    }
  end

  defp erase_func(%Func{} = f, names) do
    params = Enum.map(f.params, fn p -> %{p | type: subst(p.type, names)} end)

    %Func{
      f
      | params: params,
        ret: subst(f.ret, names),
        clauses: Enum.map(f.clauses, &erase_clause(&1, names))
    }
  end

  defp erase_type(%Type{} = t, names) do
    %Type{t | variants: Enum.map(t.variants, &erase_variant(&1, names))}
  end

  defp erase_variant(%Variant{} = v, names) do
    %Variant{v | fields: Enum.map(v.fields, fn f -> %{f | type: subst(f.type, names)} end)}
  end

  defp erase_struct(%Struct{} = s, names) do
    %Struct{s | fields: Enum.map(s.fields, fn f -> %{f | type: subst(f.type, names)} end)}
  end

  defp erase_const(%Const{} = c, names), do: %Const{c | type: subst(c.type, names)}

  defp erase_clause(%Clause{body: nil} = c, _names), do: c

  defp erase_clause(%Clause{body: body} = c, names),
    do: %Clause{c | body: strip_of(Pratt.parse_body(body), names)}

  # Substitute opaque names -> base in a type string. `\b…\b` keeps `Token` from
  # matching inside `TokenList`; the substitution covers compound types
  # (`Vec(Token)`, `Token | E`, tuples) since it is a plain word replacement.
  defp subst(nil, _names), do: nil

  defp subst(type, names) when is_binary(type) do
    Enum.reduce(names, type, fn {name, base}, acc ->
      Regex.replace(~r/\b#{Regex.escape(name)}\b/, acc, base)
    end)
  end

  # Rewrite `T.of(x)` -> `x` for any opaque `T`, recursively over the expr AST.
  # Non-opaque `.of` calls (a `range` constructor) fall through to the generic
  # tuple/list recursion and are preserved.
  defp strip_of({:call, {:dot, {:id, n}, "of"}, [arg]}, names) when is_map_key(names, n),
    do: strip_of(arg, names)

  defp strip_of(ast, names) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&strip_of(&1, names)) |> List.to_tuple()

  defp strip_of(list, names) when is_list(list), do: Enum.map(list, &strip_of(&1, names))

  defp strip_of(other, _names), do: other
end
