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
  alias Rian.{Check, IR, Pratt}
  alias Rian.IR.{Clause, Const, Func, Struct, Type, Variant}

  @doc "Erase all opaque types from a parsed program. A no-op when it has none."
  @spec erase(map()) :: map()
  def erase(%{} = prog) do
    all = opaques(prog)
    if all == [], do: prog, else: do_erase(prog, erase_ctx(all))
  end

  # every `%IR.Opaque{}` in the program (top level + every module).
  defp opaques(prog) do
    Map.get(prog, :opaques, []) ++
      for(m <- Map.get(prog, :mods, []), o <- Map.get(m, :opaques, []), do: o)
  end

  # The erasure context: `names` is name->base for type substitution; `casts` maps
  # a declared cast name to the **set of abstracts that declare it**, so a cast
  # `v.castname()` erases to `v` (ADR-0067 §2) **only when `v`'s type is one of
  # those abstracts** — not merely because the name matches (an unrelated
  # `other.base()` on a different type must not be stripped).
  defp erase_ctx(all) do
    names = Map.new(all, fn o -> {o.name, o.base} end)

    casts =
      for o <- all, c <- Map.get(o, :casts, []), reduce: %{} do
        acc -> Map.update(acc, c.name, MapSet.new([o.name]), &MapSet.put(&1, o.name))
      end

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
    # name->type from the *original* (pre-substitution) params, so a cast's head
    # variable infers its abstract type for the type-scoped cast erasure in `strip`
    env = Map.new(f.params, &{&1.name, &1.type})

    %Func{
      f
      | params: params,
        ret: subst(f.ret, names),
        clauses: Enum.map(f.clauses, &erase_clause(&1, ctx, env))
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

  defp erase_clause(%Clause{body: nil} = c, _ctx, _env), do: c

  defp erase_clause(%Clause{body: body} = c, ctx, env),
    do: %Clause{c | body: strip(Pratt.parse_body(body), ctx, env)}

  # Substitute opaque names -> base in a type string. `\b…\b` keeps `Token` from
  # matching inside `TokenList`; the substitution covers compound types
  # (`Vec(Token)`, `Token | E`, tuples) since it is a plain word replacement.
  #
  # Each pass replaces **all** opaque names *simultaneously* (one alternation regex
  # whose replacement reads the matched name), so the result is order-independent —
  # unlike a sequential per-name `reduce`, where `opaque A := B`, `opaque B := Int64`
  # could collapse `A` straight to `Int64` or stall at `B` depending on Map order.
  # The pass repeats to a fixpoint so opaque-over-opaque (and `Vec(B)`) resolve
  # transitively to the concrete base; a `fuel` cap (chain length) stops a cyclic
  # definition from looping forever.
  defp subst(nil, _names), do: nil

  defp subst(type, names) when is_binary(type) do
    case names |> Map.keys() |> Enum.map(&Regex.escape/1) |> Enum.join("|") do
      "" -> type
      alts -> subst_fix(type, names, ~r/\b(#{alts})\b/, map_size(names) + 1)
    end
  end

  defp subst_fix(type, _names, _re, 0), do: type

  defp subst_fix(type, names, re, fuel) do
    next = Regex.replace(re, type, fn _whole, name -> Map.fetch!(names, name) end)
    if next == type, do: type, else: subst_fix(next, names, re, fuel - 1)
  end

  # Rewrite the two opaque constructs that are runtime identities, recursively over
  # the expr AST: the constructor `T.of(x)` -> `x` (opaque `T`), and a declared cast
  # `v.castname()` -> `v` (ADR-0067 §2) **when `v`'s type is the abstract that
  # declares the cast**. A non-opaque `.of` (a `range` constructor) and any other
  # dot-call fall through to the generic recursion.
  defp strip({:call, {:dot, {:id, n}, "of"}, [arg]}, {names, _} = ctx, env)
       when is_map_key(names, n),
       do: strip(arg, ctx, env)

  defp strip({:call, {:dot, head, cn}, []} = node, {_, casts} = ctx, env) do
    decls = Map.get(casts, cn)

    if decls && MapSet.member?(decls, Check.infer(head, env, %{})),
      do: strip(head, ctx, env),
      else: strip_into(node, ctx, env)
  end

  defp strip(ast, ctx, env) when is_tuple(ast), do: strip_into(ast, ctx, env)
  defp strip(list, ctx, env) when is_list(list), do: Enum.map(list, &strip(&1, ctx, env))
  defp strip(other, _ctx, _env), do: other

  defp strip_into(ast, ctx, env),
    do: ast |> Tuple.to_list() |> Enum.map(&strip(&1, ctx, env)) |> List.to_tuple()
end
