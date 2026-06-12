defmodule Rian.Macro do
  @moduledoc """
  Declarative, hygienic macros — `macro name(params) => template`, where the
  template is ordinary Rian code (NO quote/unquote). This is the
  macro_rules!/syntax-rules model: macro calls are substituted at the AST level
  (so precedence is always correct — no C-preprocessor bugs), and template-local
  binders are gensym-renamed so they cannot capture the caller's variables.

  Runs as a pure AST -> AST pass before typecheck.
  """
  alias Rian.Pratt

  @max_depth 200

  @doc "Build a macro env from defs: [%{name, params: [String], template: String}]."
  def build_env(defs) do
    Map.new(defs, fn %{name: n, params: ps, template: t} ->
      {n, %{params: ps, template: Pratt.parse(t)}}
    end)
  end

  def expand(env, ast), do: expand(env, ast, 0)

  def expand(_env, _ast, d) when d > @max_depth, do: raise("macro expansion too deep")

  def expand(env, {:call, {:id, name}, args} = node, d) do
    case Map.get(env, name) do
      %{params: ps, template: tmpl} when length(ps) == length(args) ->
        eargs = Enum.map(args, &expand(env, &1, d))
        tmpl = freshen(tmpl, ps)
        subst = Map.new(Enum.zip(ps, eargs))
        expand(env, substitute(tmpl, subst), d + 1)

      _ ->
        map_node(node, &expand(env, &1, d))
    end
  end

  def expand(env, node, d), do: map_node(node, &expand(env, &1, d))

  # ── generic child mapping (also reused by Rian.Comptime) ───────────────
  def map_node({:bin, op, l, r}, f), do: {:bin, op, f.(l), f.(r)}
  def map_node({:unary, op, x}, f), do: {:unary, op, f.(x)}
  def map_node({:call, fun, args}, f), do: {:call, f.(fun), Enum.map(args, f)}
  def map_node({:dot, o, n}, f), do: {:dot, f.(o), n}
  def map_node({:capture, b}, f), do: {:capture, f.(b)}
  def map_node({:capture_named, p, a}, f), do: {:capture_named, f.(p), a}
  def map_node({:lambda, ps, b}, f), do: {:lambda, ps, f.(b)}
  def map_node({:if, c, t, e}, f), do: {:if, f.(c), f.(t), f.(e)}

  def map_node({:case, s, arms}, f),
    do: {:case, f.(s), Enum.map(arms, fn {p, g, b} -> {p, g && f.(g), f.(b)} end)}

  def map_node({:block, stmts}, f) do
    {:block,
     Enum.map(stmts, fn
       {:bind, n, e} -> {:bind, n, f.(e)}
       {:expr, e} -> {:expr, f.(e)}
     end)}
  end

  def map_node({:list_lit, es, tail}, f) do
    {:list_lit, Enum.map(es, f),
     case tail do
       nil -> nil
       {:tail, p} -> {:tail, f.(p)}
     end}
  end

  def map_node({:map_lit, ps}, f), do: {:map_lit, Enum.map(ps, fn {k, v} -> {k, f.(v)} end)}
  def map_node({:tuple, es}, f), do: {:tuple, Enum.map(es, f)}

  def map_node({:struct_lit, n, ps}, f),
    do: {:struct_lit, n, Enum.map(ps, fn {k, v} -> {k, f.(v)} end)}

  def map_node({:variant_lit, enum, ctor, named, ps}, f),
    do: {:variant_lit, enum, ctor, named, Enum.map(ps, fn {k, v} -> {k, f.(v)} end)}

  def map_node({:label, n, e}, f), do: {:label, n, f.(e)}

  def map_node(leaf, _f), do: leaf

  # ── substitution: replace {:id, param} with the argument AST ───────────
  defp substitute({:id, x} = node, subst), do: Map.get(subst, x, node)
  defp substitute(node, subst), do: map_node(node, &substitute(&1, subst))

  # ── hygiene: gensym-rename template-local binders (not the params) ─────
  defp freshen(tmpl, params) do
    binders = collect_binders(tmpl) |> Enum.uniq() |> Enum.reject(&(&1 in params))

    ren =
      Map.new(binders, fn b ->
        {b, b <> "__h" <> Integer.to_string(:erlang.unique_integer([:positive]))}
      end)

    rename(tmpl, ren)
  end

  defp collect_binders({:block, stmts}) do
    Enum.flat_map(stmts, fn
      {:bind, n, e} -> [n | collect_binders(e)]
      {:expr, e} -> collect_binders(e)
    end)
  end

  defp collect_binders({:lambda, ps, b}),
    do: Enum.map(ps, fn {n, _} -> n end) ++ collect_binders(b)

  defp collect_binders({:bin, _, l, r}), do: collect_binders(l) ++ collect_binders(r)
  defp collect_binders({:unary, _, x}), do: collect_binders(x)

  defp collect_binders({:call, f, a}),
    do: collect_binders(f) ++ Enum.flat_map(a, &collect_binders/1)

  defp collect_binders({:dot, o, _}), do: collect_binders(o)
  defp collect_binders({:capture, b}), do: collect_binders(b)
  defp collect_binders({:capture_named, p, _}), do: collect_binders(p)

  defp collect_binders({:if, c, t, e}),
    do: collect_binders(c) ++ collect_binders(t) ++ collect_binders(e)

  defp collect_binders({:case, s, arms}) do
    collect_binders(s) ++
      Enum.flat_map(arms, fn {_p, g, b} ->
        ((g && collect_binders(g)) || []) ++ collect_binders(b)
      end)
  end

  defp collect_binders({:list_lit, es, tail}) do
    Enum.flat_map(es, &collect_binders/1) ++
      case tail do
        {:tail, p} -> collect_binders(p)
        _ -> []
      end
  end

  defp collect_binders({:map_lit, ps}), do: Enum.flat_map(ps, fn {_, v} -> collect_binders(v) end)
  defp collect_binders(_), do: []

  defp rename({:id, x}, ren), do: {:id, Map.get(ren, x, x)}
  defp rename({:bin, op, l, r}, ren), do: {:bin, op, rename(l, ren), rename(r, ren)}
  defp rename({:unary, op, x}, ren), do: {:unary, op, rename(x, ren)}
  defp rename({:call, f, a}, ren), do: {:call, rename(f, ren), Enum.map(a, &rename(&1, ren))}
  defp rename({:dot, o, n}, ren), do: {:dot, rename(o, ren), n}
  defp rename({:capture, b}, ren), do: {:capture, rename(b, ren)}
  defp rename({:capture_named, p, a}, ren), do: {:capture_named, rename(p, ren), a}

  defp rename({:lambda, ps, b}, ren),
    do: {:lambda, Enum.map(ps, fn {n, t} -> {Map.get(ren, n, n), t} end), rename(b, ren)}

  defp rename({:if, c, t, e}, ren), do: {:if, rename(c, ren), rename(t, ren), rename(e, ren)}

  defp rename({:case, s, arms}, ren),
    do:
      {:case, rename(s, ren),
       Enum.map(arms, fn {p, g, b} -> {p, g && rename(g, ren), rename(b, ren)} end)}

  defp rename({:block, stmts}, ren) do
    {:block,
     Enum.map(stmts, fn
       {:bind, n, e} -> {:bind, Map.get(ren, n, n), rename(e, ren)}
       {:expr, e} -> {:expr, rename(e, ren)}
     end)}
  end

  defp rename({:list_lit, es, tail}, ren) do
    {:list_lit, Enum.map(es, &rename(&1, ren)),
     case tail do
       {:tail, p} -> {:tail, rename(p, ren)}
       _ -> nil
     end}
  end

  defp rename({:map_lit, ps}, ren),
    do: {:map_lit, Enum.map(ps, fn {k, v} -> {k, rename(v, ren)} end)}

  defp rename(leaf, _ren), do: leaf
end
