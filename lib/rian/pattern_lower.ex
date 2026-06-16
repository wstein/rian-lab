defmodule Rian.PatternLower do
  @moduledoc """
  Lowers patterns into the CHECKER patterns (the Maranget `{:ctor, tag, args}`
  form) consumed by `Rian.Exhaustiveness.analyze/3`, before exhaustiveness
  analysis. Consumes the typed core IR (`Rian.Core` pattern nodes); a surface
  tuple is translated via `Core.from_pat` (ADR-0050).

  Surface pattern AST (translated to `Rian.Core` by `from_pat`):
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
  alias Rian.Core

  # Register a product type (struct) so struct patterns can be ordered + decomposed.
  @spec add_struct(map(), term(), list()) :: map()
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
  @spec lower_clause(map(), map()) :: map()
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

  @doc """
  Lower one pattern -> {checker_pattern, introduced_guard?}. Consumes the typed
  core IR (`Rian.Core`); a surface pattern is translated via `Core.from_pat`, so
  callers and the direct tests can still pass surface tuples (ADR-0050).
  """
  @spec lower(term(), map()) :: {term(), boolean()}
  def lower(pat, env) when not is_struct(pat), do: lower(Core.from_pat(pat), env)
  def lower(%Core.PWild{}, _env), do: {:wild, false}
  def lower(%Core.PVar{}, _env), do: {:wild, false}
  def lower(%Core.PAs{pat: p}, env), do: lower(p, env)
  def lower(%Core.PPin{}, _env), do: {:wild, true}
  def lower(%Core.PLit{value: v}, _env), do: {{:ctor, {:lit, v}, []}, false}
  # a `Char` literal pattern is its codepoint literal for exhaustiveness (ADR-0036)
  def lower(%Core.PChar{value: cp}, _env), do: {{:ctor, {:lit, cp}, []}, false}
  # an atom (`:ok`) is a nullary literal constructor over the open atom universe
  def lower(%Core.PAtom{name: a}, _env), do: {{:ctor, {:lit, String.to_atom(a)}, []}, false}

  def lower(%Core.PTuple{elems: ps}, env) do
    {cps, intro} = lower_many(ps, env)
    {{:ctor, {:tuple, length(ps)}, cps}, intro}
  end

  def lower(%Core.PCtor{ctor: name, args: ps}, env) do
    {cps, intro} = lower_many(ps, env)
    {{:ctor, to_snake(name), cps}, intro}
  end

  def lower(%Core.PStruct{name: name, fields: field_pats}, env) do
    s = to_snake(name)
    order = Map.fetch!(Map.get(env, :structs, %{}), s)

    in_order =
      Enum.map(order, fn f ->
        case List.keyfind(field_pats, f, 0) do
          {^f, p} -> p
          nil -> %Core.PWild{}
        end
      end)

    {cps, intro} = lower_many(in_order, env)
    {{:ctor, s, cps}, intro}
  end

  def lower(%Core.PList{elems: elems, tail: tail}, env), do: lower_list(elems, tail, env)

  # Open maps are refutable (unless empty): treat like a guarded clause for coverage.
  def lower(%Core.PMap{pairs: []}, _env), do: {:wild, false}
  def lower(%Core.PMap{}, _env), do: {:wild, true}

  defp lower_list([], :close, _env), do: {{:ctor, nil, []}, false}
  defp lower_list([], tail, env), do: lower(tail, env)

  defp lower_list([h | rest], tail, env) do
    {hc, hi} = lower(h, env)
    {tc, ti} = lower_list(rest, tail, env)
    {{:ctor, :cons, [hc, tc]}, hi or ti}
  end

  # PascalCase / "JNum" -> snake atom ; pre-snaked atoms pass through.
  @spec to_snake(atom() | String.t()) :: atom()
  def to_snake(name) when is_atom(name), do: name

  def to_snake(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.to_atom()
  end
end
