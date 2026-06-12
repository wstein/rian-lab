defmodule Rian.PatternLower do
  @moduledoc """
  Lowers SURFACE patterns (parser output) into the CHECKER patterns consumed by
  `Rian.Exhaustiveness.analyze/3`, running before exhaustiveness analysis.

  Surface pattern AST:
      :wild
      {:var, name}
      {:as, name, surface}            # name @ pat   (binder ignored for coverage)
      {:pin, expr}                    # ^expr        -> :wild + introduces a guard
      {:lit, value}
      {:ctor, name, [surface]}        # variant, positional ; name is "Circle"/"JNum"/...
      {:tuple, [surface]}
      {:list, [surface], :close | {:tail, surface}}
      {:struct, name, [{field_atom, surface}]}
      {:map, [{key, surface}]}        # BEAM-only ; refutable when non-empty

  Each clause lowers to %{pat: [checker_pattern], guard: boolean}; `guard` is the
  explicit guard flag OR'd with any guard introduced by a pin / refutable map.
  """

  # Register a product type (struct) so struct patterns can be ordered + decomposed.
  def add_struct(env, name, fields) when is_list(fields) do
    s = to_snake(name)
    env = Map.put_new(env, :structs, %{})

    %{
      env
      | arity: Map.put(env.arity, s, length(fields)),
        type_of: Map.put(env.type_of, s, s),
        ctors: Map.put(env.ctors, s, {:finite, [s]}),
        structs: Map.put(env.structs, s, fields)
    }
  end

  @doc "Lower one clause: %{pats: [surface], guard: boolean} -> %{pat: [checker], guard: boolean}."
  def lower_clause(%{pats: surface, guard: explicit?}, env) do
    {pats, introduced?} = lower_many(surface, env)
    %{pat: pats, guard: explicit? or introduced?}
  end

  defp lower_many(ps, env) do
    Enum.map_reduce(ps, false, fn p, acc ->
      {c, i} = lower(p, env)
      {c, acc or i}
    end)
  end

  @doc "Lower one surface pattern -> {checker_pattern, introduced_guard?}."
  def lower(:wild, _env), do: {:wild, false}
  def lower({:var, _}, _env), do: {:wild, false}
  def lower({:as, _name, p}, env), do: lower(p, env)
  def lower({:pin, _expr}, _env), do: {:wild, true}
  def lower({:lit, v}, _env), do: {{:ctor, {:lit, v}, []}, false}
  # an atom (`:ok`) is a nullary literal constructor over the open atom universe
  def lower({:atom, a}, _env), do: {{:ctor, {:lit, String.to_atom(a)}, []}, false}

  def lower({:tuple, ps}, env) do
    {cps, intro} = lower_many(ps, env)
    {{:ctor, {:tuple, length(ps)}, cps}, intro}
  end

  def lower({:ctor, name, ps}, env) do
    {cps, intro} = lower_many(ps, env)
    {{:ctor, to_snake(name), cps}, intro}
  end

  def lower({:struct, name, field_pats}, env) do
    s = to_snake(name)
    order = Map.fetch!(Map.get(env, :structs, %{}), s)

    in_order =
      Enum.map(order, fn f ->
        case List.keyfind(field_pats, f, 0) do
          {^f, p} -> p
          nil -> :wild
        end
      end)

    {cps, intro} = lower_many(in_order, env)
    {{:ctor, s, cps}, intro}
  end

  def lower({:list, elems, tail}, env), do: lower_list(elems, tail, env)

  # Open maps are refutable (unless empty): treat like a guarded clause for coverage.
  def lower({:map, []}, _env), do: {:wild, false}
  def lower({:map, _kvs}, _env), do: {:wild, true}

  defp lower_list([], :close, _env), do: {{:ctor, nil, []}, false}
  defp lower_list([], {:tail, p}, env), do: lower(p, env)

  defp lower_list([h | rest], tail, env) do
    {hc, hi} = lower(h, env)
    {tc, ti} = lower_list(rest, tail, env)
    {{:ctor, :cons, [hc, tc]}, hi or ti}
  end

  # PascalCase / "JNum" -> snake atom ; pre-snaked atoms pass through.
  def to_snake(name) when is_atom(name), do: name

  def to_snake(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.to_atom()
  end
end
