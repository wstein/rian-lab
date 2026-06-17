defmodule Rian.Macro do
  @moduledoc """
  Declarative, hygienic macros — `macro name(params) := template`, where the
  template is ordinary Rian code (NO quote/unquote). This is the
  macro_rules!/syntax-rules model: macro calls are substituted at the AST level
  (so precedence is always correct — no C-preprocessor bugs), and template-local
  binders are gensym-renamed so they cannot capture the caller's variables.

  Runs as a pure AST -> AST pass before typecheck.

  ## Portable-core discipline (ADR-0035 · ADR-0058)

  `expand/3` with `portable: true` enforces the rule the design review reached
  for shared (`@targets`)-declared code: a macro may not **introduce
  caller-invisible control flow**. Concretely, a template that expands a one-line
  call site into a failable bind (`with … <- …`, ADR-0039) hides where control
  diverges — the "debugging a ghost" failure where a type/ownership error points
  at expanded nodes the caller never wrote. In portable expansion such a template
  is rejected at the call site, by name. (We gate on the *kind* of node
  introduced, not a raw depth counter — a benign macro calling a benign helper is
  not "macro soup"; an invisible `<-` is. `@max_depth` remains a separate runaway
  backstop.)
  """
  alias Rian.Pratt

  @max_depth 200

  @doc "Build a macro env from defs: [%{name, params: [String], template: String}]."
  @spec build_env([map()]) :: map()
  def build_env(defs) do
    Map.new(defs, fn %{name: n, params: ps, template: t} ->
      {n, %{params: ps, template: Pratt.parse(t)}}
    end)
  end

  @doc """
  Expand all macro calls in `ast`. `opts[:portable]` (default `false`) enforces
  the portable-core discipline above — a template that introduces a failable bind
  is rejected. Driven by `Rian.Decl.assemble/3`, which passes `portable: true` for
  `@targets`-declared modules.
  """
  @spec expand(map(), term(), keyword()) :: term()
  def expand(env, ast, opts \\ []),
    do: do_expand(env, ast, 0, Keyword.get(opts, :portable, false))

  defp do_expand(_env, _ast, d, _p) when d > @max_depth, do: raise("macro expansion too deep")

  defp do_expand(env, {:call, {:id, name}, args} = node, d, portable?) do
    case Map.get(env, name) do
      %{params: ps, template: tmpl} when length(ps) == length(args) ->
        if portable?, do: check_portable!(name, tmpl)
        eargs = Enum.map(args, &do_expand(env, &1, d, portable?))
        tmpl = freshen(tmpl, ps)
        subst = Map.new(Enum.zip(ps, eargs))
        do_expand(env, substitute(tmpl, subst), d + 1, portable?)

      _ ->
        map_node(node, &do_expand(env, &1, d, portable?))
    end
  end

  defp do_expand(env, node, d, portable?), do: map_node(node, &do_expand(env, &1, d, portable?))

  # Portable-core guard: reject a template that introduces a failable bind
  # (`with … <- …`), which would hide control flow behind a one-line call site.
  defp check_portable!(name, tmpl) do
    if introduces_failable_bind?(tmpl) do
      raise "macro `#{name}` introduces a failable bind (`with … <- …`) — not " <>
              "allowed in portable/@targets code: it hides control flow the call " <>
              "site does not show (ADR-0035 no-hidden-control-flow, ADR-0039)"
    end
  end

  # a failable bind (`<-`) parses to a `with` node; detect one anywhere in the
  # template by a structural search — no throw/catch (ADR-0035: control is explicit,
  # errors are values).
  defp introduces_failable_bind?({:with, _clauses, _body, _els}), do: true

  defp introduces_failable_bind?(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.any?(&introduces_failable_bind?/1)

  defp introduces_failable_bind?(node) when is_list(node),
    do: Enum.any?(node, &introduces_failable_bind?/1)

  defp introduces_failable_bind?(_), do: false

  # ── generic child mapping (also reused by Rian.Comptime) ───────────────
  @spec map_node(term(), (term() -> term())) :: term()
  def map_node({:bin, op, l, r}, f), do: {:bin, op, f.(l), f.(r)}
  def map_node({:unary, op, x}, f), do: {:unary, op, f.(x)}
  def map_node({:call, fun, args}, f), do: {:call, f.(fun), Enum.map(args, f)}
  def map_node({:dot, o, n}, f), do: {:dot, f.(o), n}
  def map_node({:capture, b}, f), do: {:capture, f.(b)}
  def map_node({:capture_named, p, a}, f), do: {:capture_named, f.(p), a}
  def map_node({:lambda, ps, b}, f), do: {:lambda, ps, f.(b)}
  def map_node({:if, c, t, e}, f), do: {:if, f.(c), f.(t), f.(e)}

  def map_node({:case, s, arms}, f),
    do:
      {:case, f.(s),
       Enum.map(arms, fn {p, g, b} ->
         {p,
          case g do
            nil -> nil
            g -> f.(g)
          end, f.(b)}
       end)}

  def map_node({:with, clauses, body, els}, f) do
    {:with, Enum.map(clauses, fn {p, e} -> {p, f.(e)} end), f.(body),
     Enum.map(els, fn {p, g, b} ->
       {p,
        case g do
          nil -> nil
          g -> f.(g)
        end, f.(b)}
     end)}
  end

  def map_node({:block, stmts}, f) do
    {:block,
     Enum.map(stmts, fn
       {:bind, n, e} -> {:bind, n, f.(e)}
       {:typed_bind, n, t, e} -> {:typed_bind, n, t, f.(e)}
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

  def map_node({:map_lit, ps}, f), do: {:map_lit, Enum.map(ps, &map_pair_node(&1, f))}

  def map_node({:map_update, base, ps}, f),
    do: {:map_update, f.(base), Enum.map(ps, &map_pair_node(&1, f))}

  def map_node({:tuple, es}, f), do: {:tuple, Enum.map(es, f)}

  def map_node({:struct_lit, n, ps}, f),
    do: {:struct_lit, n, Enum.map(ps, fn {k, v} -> {k, f.(v)} end)}

  def map_node({:variant_lit, enum, ctor, named, ps}, f),
    do: {:variant_lit, enum, ctor, named, Enum.map(ps, fn {k, v} -> {k, f.(v)} end)}

  def map_node({:label, n, e}, f), do: {:label, n, f.(e)}

  # comprehension (ADR-0079): recurse into each generator source / filter condition
  # and the body (the generator's bound var is a leaf name, left as-is).
  def map_node({:comprehension, clauses, body}, f) do
    clauses =
      Enum.map(clauses, fn
        {:gen, v, src} -> {:gen, v, f.(src)}
        {:filter, c} -> {:filter, f.(c)}
      end)

    {:comprehension, clauses, f.(body)}
  end

  # bitstring (ADR-0078): recurse into each segment's *value* (the spec is metadata).
  def map_node({:bitstr, segs}, f),
    do: {:bitstr, Enum.map(segs, fn {:bitseg, v, specs} -> {:bitseg, f.(v), specs} end)}

  # string interpolation (ADR-0069): recurse into each `${expr}` hole, so a macro
  # template's interpolation gets its parameters substituted (and template-local
  # binders renamed for hygiene). Literal parts carry no expression to map.
  def map_node({:str_interp, parts}, f) do
    {:str_interp,
     Enum.map(parts, fn
       {:hole, e} -> {:hole, f.(e)}
       lit -> lit
     end)}
  end

  def map_node(leaf, _f), do: leaf

  # a map pair: recurse into the value, and — for a computed key `{:key, expr}` —
  # into the key expression too (an atom-key `k` is a bare leaf, left as-is).
  defp map_pair_node({{:key, k}, v}, f), do: {{:key, f.(k)}, f.(v)}
  defp map_pair_node({k, v}, f), do: {k, f.(v)}

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

  # Template-local binder NAMES — block `:=` binds and lambda params — found
  # anywhere by a GENERIC walk over the AST. Previously this hand-rolled one clause
  # per node type and drifted out of sync with `map_node`, so a binder nested under
  # `:tuple`/`:struct_lit`/`:variant_lit`/`:with`/`:label` escaped renaming (the
  # hygiene bug). The generic tuple/list recursion enumerates *no* node types, so it
  # can never drift again; `binders_here/1` is the only node-specific knowledge.
  defp collect_binders(node) when is_tuple(node),
    do: binders_here(node) ++ Enum.flat_map(Tuple.to_list(node), &collect_binders/1)

  defp collect_binders(node) when is_list(node), do: Enum.flat_map(node, &collect_binders/1)
  defp collect_binders(_), do: []

  defp binders_here({:block, stmts}) do
    Enum.flat_map(stmts, fn
      {:bind, n, _} -> [n]
      {:typed_bind, n, _, _} -> [n]
      _ -> []
    end)
  end

  defp binders_here({:lambda, ps, _}), do: Enum.map(ps, fn {n, _} -> n end)
  defp binders_here(_), do: []

  # The actual rename happens at `{:id, x}`; the two binder-introducing nodes
  # (`:block` binds, `:lambda` params) also rename their bound NAMES. EVERYTHING
  # else just recurses into children — which is exactly `map_node`, so the generic
  # fallback covers every node `map_node` knows (including the tuple/struct_lit/
  # variant_lit/with/label that the old hand-rolled clauses missed). No drift.
  defp rename({:id, x}, ren), do: {:id, Map.get(ren, x, x)}

  defp rename({:lambda, ps, b}, ren),
    do: {:lambda, Enum.map(ps, fn {n, t} -> {Map.get(ren, n, n), t} end), rename(b, ren)}

  defp rename({:block, stmts}, ren) do
    {:block,
     Enum.map(stmts, fn
       {:bind, n, e} -> {:bind, Map.get(ren, n, n), rename(e, ren)}
       {:typed_bind, n, t, e} -> {:typed_bind, Map.get(ren, n, n), t, rename(e, ren)}
       {:expr, e} -> {:expr, rename(e, ren)}
     end)}
  end

  defp rename(node, ren), do: map_node(node, &rename(&1, ren))
end
