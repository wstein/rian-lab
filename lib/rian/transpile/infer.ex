defmodule Rian.Transpile.Infer do
  use Rian.Ann

  @moduledoc """
  Type inference that fills the transpiler's `_Unk` holes — per def group, with a
  cross-module signature cache (`prime_xmod/2`) so calls into sibling modules
  resolve (ADR-0034-aligned: it *produces* explicit signatures rather than relaxing
  the declare-public boundary).

  It runs at the transpiler's rendering seam over the **Elixir quoted AST** of a
  def group (the same shapes `Rian.Transpile.expr/1` handles), generating
  constraints into a small union-find over type *terms*, then resolving each
  parameter / return slot to a concrete Rian type string — or leaving the hole
  when nothing pins it (honest partiality, matching the transpiler's contract).

  Term language: `{:var, id}` (a unification variable), `{:con, name}` (a nullary
  type like `Int53`/`Bool`/`String`), `{:app, head, args}` (`Vec(_)`, `Option(_)`,
  `Fn(_,…,_)`). The numeric kernel reuses `Rian.Check.unify/2` + `join/2`.

  **Cross-target defaulting (ADR-0064):** an unresolved numeric var defaults to
  `Int53` — the portable all-target integer (`:ex/:rs/:js/:jvm`) — never `Int64`
  (off `:js`) or `Int` (off `:rs/:jvm`), so inferred functions stay maximally
  portable. MVP solves each def group in isolation (no cross-def fixpoint).

  **`@spec` harvesting (ADR-0075 Phase C):** Elixir's own `@spec` annotations *are*
  the human-written types inference tries to reconstruct, so `collect_specs/1` +
  `translate_spec/1` map them into terms and `seed_spec/6` unifies each sig var with
  its spec term *after* the body pass — a body-hole var ADOPTS the spec, a conflicting
  body-concrete var keeps its proven type. Hints, cross-checked: a stale/wrong `@spec`
  never forces an accidental fill. Untranslatable spec types (`any()`/`term()`, tuples,
  maps) yield no hint — the slot stays an honest `_Unk` hole for a human to fill.
  """

  alias Rian.Decl

  @arith ~w(+ - *)a
  @cmp ~w(< <= > >= == !=)a
  @bool ~w(and or)a

  # ── context (prelude signatures, loaded once) ─────────────────────────────

  @doc """
  Build the inference context once per transpile invocation: the prelude
  signature table keyed by `{module, fun, arity}` (parsed from
  `examples/rian/prelude_*.rian`), plus the transpiler's stdlib mapping and an
  optional sibling-signature table for intra-module calls.
  """
  @spec build_ctx(map(), map()) :: term()
  def build_ctx(stdlib_map, siblings \\ %{}) do
    %{prelude: prelude_sigs(), stdlib: stdlib_map, siblings: siblings, xmod: xmod_cache()}
  end

  @doc """
  Phase A — whole-program cross-module signatures. Infer every module's def groups
  in isolation and cache the non-hole sigs keyed `{short_module, fun, arity}`, so a
  cross-module call `Core.from_expr(x)` can be resolved. Accident-free: a hole sig
  is simply not recorded, and recorded sigs are anchor-derived. `modules` is a list
  of `{short_module_name, [group]}`.
  """
  @spec prime_xmod(list(), map()) :: term()
  def prime_xmod(modules, stdlib_map) do
    base = %{prelude: prelude_sigs(), stdlib: stdlib_map, siblings: %{}, xmod: %{}}

    table =
      for {short, groups} <- modules, g <- groups, reduce: %{} do
        acc ->
          sig = infer_group(g, base)
          k = {short, to_string(hd(g.clauses).name), hd(g.clauses).arity}
          if hole_sig?(sig), do: acc, else: Map.put(acc, k, sig)
      end

    :persistent_term.put({__MODULE__, :xmod}, table)
    table
  end

  @rian "pub def clear_xmod() Bool"
  @spec clear_xmod() :: boolean()
  def clear_xmod, do: :persistent_term.erase({__MODULE__, :xmod})

  defp xmod_cache, do: :persistent_term.get({__MODULE__, :xmod}, %{})

  defp hole_sig?(%{params: ps, ret: r}), do: r == "_Unk" or Enum.any?(ps, &(&1 == "_Unk"))

  # parse the prelude `fsigs` once and cache (the perf-sensitive path when
  # transpiling all of `lib/rian`; re-run the OS process to pick up prelude edits).
  defp prelude_sigs do
    case :persistent_term.get({__MODULE__, :prelude}, nil) do
      nil ->
        sigs = load_prelude_sigs()
        :persistent_term.put({__MODULE__, :prelude}, sigs)
        sigs

      sigs ->
        sigs
    end
  end

  defp load_prelude_sigs do
    "examples/rian/prelude_*.rian"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      # a prelude that fails to parse must not crash transpilation — degrade to "no
      # prelude knowledge" for that file (everything stays a hole rather than mis-typed).
      case path |> File.read!() |> Decl.parse_result() do
        {:ok, prog} ->
          for m <- Map.get(prog, :mods, []), f <- m.funcs do
            {{m.name, to_string(f.name), length(f.params)}, sig_of(f)}
          end

        {:error, _} ->
          []
      end
    end)
    |> Map.new()
  end

  defp sig_of(f), do: %{params: Enum.map(f.params, & &1.type), ret: f.ret, tvars: f.tvars}

  # ── public entry: infer one def group ─────────────────────────────────────

  @doc """
  Infer a def group (all clauses of one name/arity). Returns
  `%{params: [type_string], ret: type_string, tvars: [name], ledger: [{slot, reason}]}`
  where an unresolved slot is the literal hole `"_Unk"` and `ledger`
  records why each hole was left (for `--infer-report`).
  """
  @spec infer_group(map(), term()) :: term()
  def infer_group(%{clauses: clauses}, ctx) do
    arity = hd(clauses).arity
    s0 = store_new()
    {pvars, s1} = fresh_n(s0, arity)
    {rvar, s2} = fresh(s1)

    # build the store; keep each clause's body + bound env for Result analysis.
    {store, clause_envs} =
      Enum.reduce(clauses, {s2, []}, fn clause, {s, envs} ->
        {env, s} = bind_params(clause.args, pvars, ctx, s)
        # a `when` guard is type evidence too (`is_integer(n)`, `n > 0`): run it for
        # its unification side-effects (the `Bool` result is discarded), so a param
        # constrained only by its guard still infers — Phase B (ADR-0075).
        s = if clause.guard, do: elem(gen(clause.guard, env, ctx, s), 1), else: s
        {bt, s} = gen(clause.body, env, ctx, s)
        {s, _} = unify(s, rvar, bt)
        {s, envs ++ [{clause.body, env}]}
      end)

    # Phase B Result analysis runs BEFORE rendering — it adds payload constraints
    # (e.g. a `{:ok, div(a,b)}` pins `a`/`b`) that the param types must reflect.
    {res, store} = result_analysis(clause_envs, ctx, store)

    # `@spec` harvest (cross-checked): unify each sig var with its declared spec
    # type. A body-hole var ADOPTS the spec (the hint fills it); a body-concrete
    # var that conflicts with the spec keeps the proven body type — the spec yields
    # to body inference, so a stale/wrong `@spec` never causes an accidental fill.
    store = seed_spec(ctx, to_string(hd(clauses).name), arity, pvars, rvar, store)

    gmap = generalize_map(pvars, rvar, store)
    params = pvars |> Enum.map(&(render(store, gmap, &1) |> hole_or("_Unk")))
    tvars = gmap |> Map.values() |> Enum.uniq() |> Enum.sort()

    # a Result (all tails `{:ok, _}`/`{:error, Tag}`) types as `Payload | <error set>`;
    # the caller synthesizes the `type … := Tag | …` declaration (ADR-0040).
    {ret, tags, result} =
      case res do
        {:result, payload_term, tg} ->
          case render(store, gmap, payload_term) do
            :hole -> {render(store, gmap, rvar) |> hole_or("_Unk"), [], false}
            p -> {p, tg, true}
          end

        :no ->
          {render(store, gmap, rvar) |> hole_or("_Unk"), [], false}
      end

    %{
      params: params,
      ret: ret,
      tvars: tvars,
      ledger: build_ledger(params, ret),
      error_tags: tags,
      result: result
    }
  end

  @doc """
  Harvest Elixir `@spec` annotations from a module's statements into a hint map
  `%{{name, arity} => %{params: [term | nil], ret: term | nil}}`. A `nil` slot is a
  spec type with no clean Rian image (tuples, maps, pids) — no hint. `type_env` (from
  `collect_types/2`) resolves local `@type` refs (`t()`, `expr()`) to their Rian type.
  `@spec`s are *documentary* in Elixir (unenforced, possibly stale), so these are
  hints, cross-checked against the body in `seed_spec/6`, never ground truth.
  """
  def collect_specs(stmts, type_env \\ %{})

  def collect_specs(stmts, type_env) when is_list(stmts) do
    for stmt <- stmts, pair = spec_pair(stmt, type_env), pair != nil, into: %{}, do: pair
  end

  def collect_specs(_, _), do: %{}

  @doc """
  Harvest Elixir `@type` declarations into `{type_env, decls}`: `type_env` maps each
  local type NAME to its Rian term (so `@spec`s referencing `t()`/`expr()` resolve),
  and `decls` are synthesized Rian `type Name := …` declaration strings for the
  union-shaped `@type`s (a single-type alias resolves *inline*, no decl). `%__MODULE__{}`
  resolves to the module's own struct; a remote `Mod.t()` to `Mod`. Untranslatable
  `@type`s (tuples/maps) are dropped — no hint, no decl.
  """
  def collect_types(stmts, mod_name) when is_list(stmts) do
    raw =
      for {:@, _, [{:type, _, [body]}]} <- stmts,
          {name, term} <- [type_pair(body, mod_name)],
          term != nil,
          into: %{},
          do: {name, term}

    decls =
      for {name, {:con, str}} <- raw, String.contains?(str, " | ") do
        "type #{pascal(name)} := #{str}"
      end

    # a union @type resolves to its synthesized name; everything else inlines.
    env =
      Map.new(raw, fn
        {name, {:con, str} = t} ->
          if String.contains?(str, " | "), do: {name, con(pascal(name))}, else: {name, t}

        {name, t} ->
          {name, t}
      end)

    {env, Enum.sort(decls)}
  end

  def collect_types(_, _), do: {%{}, []}

  defp type_pair({:"::", _, [{name, _, _}, rhs]}, mod_name) when is_atom(name),
    do: {name, translate_type(rhs, mod_name)}

  defp type_pair(_, _), do: nil

  # `@type` RHS → a Rian term; like `translate_spec` but also resolves `%__MODULE__{}`
  # (the module's own struct) and a remote `Mod.t()` (→ `Mod`).
  defp translate_type({:%, _, [{:__MODULE__, _, _}, _]}, mod_name), do: con(mod_name)

  defp translate_type({{:., _, [{:__aliases__, _, parts}, :t]}, _, _}, _mod)
       when parts != [:String],
       do: con(to_string(List.last(parts)))

  defp translate_type(ast, _mod), do: translate_spec(ast)

  defp pascal(name) do
    name |> to_string() |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end

  defp spec_pair({:@, _, [{:spec, _, [body]}]}, type_env) do
    body =
      case body do
        # drop `when x: t` bounded quantifiers; translate the bare head/return
        {:when, _, [s, _]} -> s
        s -> s
      end

    case body do
      {:"::", _, [{name, _, args}, ret]} when is_atom(name) ->
        args =
          case args do
            nil -> []
            v -> v
          end

        {{to_string(name), length(args)},
         %{
           params: Enum.map(args, &translate_spec(&1, type_env)),
           ret: translate_spec(ret, type_env)
         }}

      _ ->
        nil
    end
  end

  defp spec_pair(_, _), do: nil

  # Elixir/Erlang spec-type AST -> internal Infer term (`con`/`app`), or `nil` for
  # types with no clean Rian image. The inverse of ADR-0026's `-spec` *emission*.
  # `type_env` resolves local `@type` refs (`t()`/`expr()`) to their Rian term.
  defp translate_spec(ast, type_env \\ %{})
  defp translate_spec({:integer, _, _}, _e), do: con("Int53")

  defp translate_spec({t, _, _}, _e)
       when t in [:non_neg_integer, :pos_integer, :neg_integer, :byte, :char, :arity],
       do: con("Int53")

  defp translate_spec({:float, _, _}, _e), do: con("Float64")
  defp translate_spec({:boolean, _, _}, _e), do: con("Bool")

  defp translate_spec({t, _, _}, _e) when t in [:binary, :bitstring, :iodata, :iolist],
    do: con("String")

  defp translate_spec({t, _, _}, _e) when t in [:atom, :module, :node], do: con("Symbol")
  # `any()`/`term()` carries no concrete type -> leave the slot a `_Unk` hole
  # (an honest "human must type this" marker, not an auto-filled placeholder).
  defp translate_spec({t, _, _}, _e) when t in [:any, :term], do: nil
  defp translate_spec({{:., _, [{:__aliases__, _, [:String]}, :t]}, _, _}, _e), do: con("String")
  defp translate_spec([elem], e), do: vec_spec(elem, e)
  defp translate_spec({:list, _, [elem]}, e), do: vec_spec(elem, e)
  defp translate_spec({:|, _, [a, b]}, e), do: union_spec(a, b, e)

  defp translate_spec({:%, _, [{:__aliases__, _, parts}, _]}, _e),
    do: con(to_string(List.last(parts)))

  # a local `@type` ref (`t()`, `expr()`) resolves through `type_env` (ADR-0075 Phase C+).
  defp translate_spec({name, _, args}, type_env)
       when is_atom(name) and (is_list(args) or is_nil(args)),
       do: Map.get(type_env, name)

  defp translate_spec(a, _e) when is_atom(a) and a not in [nil, true, false], do: con("Symbol")
  # tuples, maps, pids — no clean Rian hint.
  defp translate_spec(_, _e), do: nil

  defp vec_spec(elem, e) do
    case translate_spec(elem, e) do
      nil -> nil
      t -> app("Vec", [t])
    end
  end

  defp union_spec(a, b, e) do
    with ta when ta != nil <- translate_spec(a, e),
         tb when tb != nil <- translate_spec(b, e) do
      con("#{spec_str(ta)} | #{spec_str(tb)}")
    else
      _ -> nil
    end
  end

  defp spec_str({:con, n}), do: n
  defp spec_str({:app, h, parts}), do: "#{h}(#{Enum.map_join(parts, ", ", &spec_str/1)})"

  @doc """
  Render an Elixir `@spec` type AST as a **Rian type string** — the converse of the
  harvest (ADR-0026 inverse). `_Unk` when the Elixir type has no clean Rian image
  (a tuple/map/atom-literal — a porting decision a human must make). `type_env` resolves
  local `@type` refs. Used to convert `@spec` into a native `@rian` annotation.
  """
  @spec spec_type_to_rian(Macro.t(), map()) :: String.t()
  def spec_type_to_rian(ast, type_env \\ %{}) do
    case translate_spec(ast, type_env) do
      nil -> "_Unk"
      term -> spec_str(term)
    end
  end

  # Cross-checked `@spec` seeding: unify each sig var with its declared spec term
  # AFTER the body pass. A free (body-hole) var ADOPTS the spec; a body-concrete var
  # that conflicts keeps its proven type (unify reports `:conflict` and leaves it),
  # so a stale/wrong `@spec` never forces an accidental fill.
  defp seed_spec(ctx, name, arity, pvars, rvar, store) do
    apply_spec_terms(Map.get(Map.get(ctx, :specs, %{}), {name, arity}), pvars, rvar, store)
  end

  # unify each sig var with its spec term (used by both the per-group and the
  # whole-program paths). A free var ADOPTS the spec; a conflict leaves the var.
  defp apply_spec_terms(nil, _pvars, _rvar, store), do: store

  defp apply_spec_terms(%{params: ps, ret: r}, pvars, rvar, store) do
    store =
      Enum.zip(pvars, ps)
      |> Enum.reduce(store, fn {pv, t}, s -> if t, do: elem(unify(s, pv, t), 0), else: s end)

    if r, do: elem(unify(store, rvar, r), 0), else: store
  end

  # bind each clause's parameter pattern against the shared param var
  defp bind_params(args, pvars, ctx, store) do
    Enum.zip(args, pvars)
    |> Enum.reduce({%{}, store}, fn {pat, pv}, {env, s} ->
      gen_pat(pat, pv, env, ctx, s)
    end)
  end

  # ── constraint generation: Elixir AST → term ──────────────────────────────

  # literals
  defp gen(n, _env, _ctx, s) when is_integer(n), do: fresh_num(s)
  defp gen(x, _env, _ctx, s) when is_float(x), do: {con("Float64"), s}
  defp gen(b, _env, _ctx, s) when is_binary(b), do: {con("String"), s}
  defp gen(true, _env, _ctx, s), do: {con("Bool"), s}
  defp gen(false, _env, _ctx, s), do: {con("Bool"), s}
  defp gen(nil, _env, _ctx, s), do: app1("Option", s)

  # string interpolation `<<…>>`
  defp gen({:<<>>, _, _}, _env, _ctx, s), do: {con("String"), s}

  # arithmetic: operands unify (numeric), result is that shared numeric type
  defp gen({op, _, [l, r]}, env, ctx, s) when op in @arith do
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, rt)
    {s, _} = mark_num(s, lt)
    {lt, s}
  end

  # division is Float64; div/rem are integer
  defp gen({:/, _, [l, r]}, env, ctx, s) do
    {_, s} = gen(l, env, ctx, s)
    {_, s} = gen(r, env, ctx, s)
    {con("Float64"), s}
  end

  defp gen({op, _, [l, r]}, env, ctx, s) when op in [:div, :rem] do
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, rt)
    {s, _} = mark_num(s, lt)
    {lt, s}
  end

  # string concat
  defp gen({:<>, _, [l, r]}, env, ctx, s) do
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, con("String"))
    {s, _} = unify(s, rt, con("String"))
    {con("String"), s}
  end

  # list concat
  defp gen({:++, _, [l, r]}, env, ctx, s) do
    {ev, s} = fresh(s)
    vec = app("Vec", [ev])
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, vec)
    {s, _} = unify(s, rt, vec)
    {vec, s}
  end

  # comparisons / boolean / not
  defp gen({op, _, [l, r]}, env, ctx, s) when op in @cmp do
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, rt)
    {con("Bool"), s}
  end

  defp gen({op, _, [l, r]}, env, ctx, s) when op in @bool do
    {lt, s} = gen(l, env, ctx, s)
    {rt, s} = gen(r, env, ctx, s)
    {s, _} = unify(s, lt, con("Bool"))
    {s, _} = unify(s, rt, con("Bool"))
    {con("Bool"), s}
  end

  defp gen({op, _, [x]}, env, ctx, s) when op in [:not, :!] do
    {xt, s} = gen(x, env, ctx, s)
    {s, _} = unify(s, xt, con("Bool"))
    {con("Bool"), s}
  end

  # unary minus → numeric, same as operand
  defp gen({:-, _, [x]}, env, ctx, s) do
    {xt, s} = gen(x, env, ctx, s)
    {s, _} = mark_num(s, xt)
    {xt, s}
  end

  # if/else: cond is Bool, result joins both branches; no else ⇒ unconstrained hole
  defp gen({:if, _, [c, kw]}, env, ctx, s) do
    {ct, s} = gen(c, env, ctx, s)
    {s, _} = unify(s, ct, con("Bool"))
    {tt, s} = gen(body_of(Keyword.get(kw, :do)), env, ctx, s)

    if Keyword.has_key?(kw, :else) do
      {et, s} = gen(body_of(Keyword.get(kw, :else)), env, ctx, s)
      {r, s} = fresh(s)
      {s, _} = unify(s, r, tt)
      {s, _} = unify(s, r, et)
      {r, s}
    else
      fresh(s)
    end
  end

  # case: result joins arm bodies; arms narrow their pattern against the subject
  defp gen({:case, _, [subj, [do: arms]]}, env, ctx, s) do
    {st, s} = gen(subj, env, ctx, s)
    {r, s} = fresh(s)

    s =
      Enum.reduce(arms, s, fn arm, s ->
        {pat, body} = case_arm(arm)
        {env2, s} = gen_pat(pat, st, env, ctx, s)
        {bt, s} = gen(body, env2, ctx, s)
        {s, _} = unify(s, r, bt)
        s
      end)

    {r, s}
  end

  # cons `[h | t]` — note Elixir parses this as a 1-element list holding a `{:|, …}`
  # cons cell, so this clause must precede the proper-list clause below.
  defp gen([{:|, _, [h, t]}], env, ctx, s), do: gen_cons(h, t, env, ctx, s)
  defp gen({:|, _, [h, t]}, env, ctx, s), do: gen_cons(h, t, env, ctx, s)

  defp gen(list, env, ctx, s) when is_list(list) do
    {ev, s} = fresh(s)

    s =
      Enum.reduce(list, s, fn el, s ->
        {et, s} = gen(el, env, ctx, s)
        {s, _} = unify(s, et, ev)
        s
      end)

    {app("Vec", [ev]), s}
  end

  # lambda — closed over `env`; its own params get fresh vars
  defp gen({:fn, _, [{:->, _, [args, body]}]}, env, ctx, s) do
    {avars, s} = fresh_n(s, length(args))

    {env2, s} =
      Enum.zip(args, avars)
      |> Enum.reduce({env, s}, fn {a, av}, {e, s} -> gen_pat(a, av, e, ctx, s) end)

    {bt, s} = gen(body, env2, ctx, s)
    {app("Fn", avars ++ [bt]), s}
  end

  # block: thread binds through env, return the last statement's type. (Must precede
  # the local-call clause — `{:__block__, _, stmts}` otherwise looks like a call.)
  defp gen({:__block__, _, stmts}, env, ctx, s) when is_list(stmts),
    do: gen_block(stmts, env, ctx, s)

  # capture placeholder `&N` — references the eta-expanded param `pN`
  defp gen({:&, _, [k]}, env, _ctx, s) when is_integer(k) do
    case Map.get(env, "&#{k}") do
      nil -> fresh(s)
      t -> {t, s}
    end
  end

  # `&name/arity` / `&Mod.fun/arity` — a function reference of known arity
  defp gen({:&, _, [{:/, _, [_target, arity]}]}, _env, _ctx, s) when is_integer(arity) do
    {avars, s} = fresh_n(s, arity)
    {rv, s} = fresh(s)
    {app("Fn", avars ++ [rv]), s}
  end

  # `&(… &1 … &2 …)` → eta-expand to a lambda `Fn(p1,…,pN, body)` (must precede the
  # local-call clause — `{:&, _, [body]}` otherwise looks like a call to `:&`).
  defp gen({:&, _, [body]}, env, ctx, s) do
    n = max_ph(body)
    {pvars, s} = fresh_n(s, n)

    env2 =
      pvars |> Enum.with_index(1) |> Enum.reduce(env, fn {v, i}, e -> Map.put(e, "&#{i}", v) end)

    {bt, s} = gen(body, env2, ctx, s)
    {app("Fn", pvars ++ [bt]), s}
  end

  # struct construction `%Mod{…}` — the value IS that struct's type (Lever B): the
  # struct's own declared name, sound now that the transpiler emits a `struct Mod(…)`
  # decl for every `defstruct`/nested struct module. Must precede the local-call clause
  # (`{:%, _, [a, b]}` otherwise looks like a call to `:%`).
  defp gen({:%, _, [{:__aliases__, _, parts}, {:%{}, _, _}]}, _env, _ctx, s) do
    {con(parts |> List.last() |> to_string()), s}
  end

  # remote call `Mod.fun(args)` — stdlib map first, then the Phase A cross-module
  # table, else free.
  defp gen({{:., _, [mod, fun]}, _, args}, env, ctx, s) when is_list(args) do
    m = mod_name(mod)

    case Map.get(ctx.stdlib, {m, fun, length(args)}) do
      {rmod, rfun} ->
        call_sig(ctx, {rmod, rfun, length(args)}, args, env, ctx, s)

      nil ->
        case Map.get(ctx.xmod, {m, to_string(fun), length(args)}) do
          nil -> gen_args_then_fresh(args, env, ctx, s)
          sig -> instantiate(sig, args, env, ctx, s)
        end
    end
  end

  # Type-test predicate evidence (Phase B): a `when is_integer(x)` guard — or the
  # same predicate in a body (`if is_binary(x), …`) — determines its argument's type.
  # Each returns `Bool` and constrains the arg; a conflict with other evidence
  # collapses the var to a hole (existing occurs/conflict detection), never a wrong
  # fill. These MUST precede the generic local-call clause below (`is_integer(x)` is
  # `{:is_integer, _, [x]}`, which also matches `{name, _, args}`).
  defp gen({:is_integer, _, [a]}, env, ctx, s), do: pred_num(a, env, ctx, s)
  defp gen({:is_float, _, [a]}, env, ctx, s), do: pred_con(a, "Float64", env, ctx, s)
  defp gen({:is_binary, _, [a]}, env, ctx, s), do: pred_con(a, "String", env, ctx, s)
  defp gen({:is_boolean, _, [a]}, env, ctx, s), do: pred_con(a, "Bool", env, ctx, s)
  defp gen({:is_atom, _, [a]}, env, ctx, s), do: pred_con(a, "Symbol", env, ctx, s)

  defp gen({:is_list, _, [a]}, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {ev, s} = fresh(s)
    {s, _} = unify(s, at, app("Vec", [ev]))
    {con("Bool"), s}
  end

  # Kernel accessor evidence (Phase B): a bare Kernel BIF whose argument type is
  # determined. `byte_size`/`length` return a number; `hd`/`tl` decompose a `Vec`.
  # (Skip `tuple_size`/`map_size` — tuple/map have no clean Rian signature type.)
  # Same ordering requirement as the predicates above. A user fn shadowing these
  # Kernel names is not expected in transpiled Elixir.
  defp gen({:byte_size, _, [a]}, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {s, _} = unify(s, at, con("String"))
    fresh_num(s)
  end

  defp gen({:length, _, [a]}, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {ev, s} = fresh(s)
    {s, _} = unify(s, at, app("Vec", [ev]))
    fresh_num(s)
  end

  defp gen({:hd, _, [a]}, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {ev, s} = fresh(s)
    {s, _} = unify(s, at, app("Vec", [ev]))
    {ev, s}
  end

  defp gen({:tl, _, [a]}, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {ev, s} = fresh(s)
    vec = app("Vec", [ev])
    {s, _} = unify(s, at, vec)
    {vec, s}
  end

  # local call `f(args)` — a same-file sibling sig, else free.
  defp gen({name, _, args}, env, ctx, s) when is_atom(name) and is_list(args) do
    case Map.get(ctx.siblings, {to_string(name), length(args)}) do
      nil -> gen_args_then_fresh(args, env, ctx, s)
      sig -> instantiate(sig, args, env, ctx, s)
    end
  end

  # variable reference
  defp gen({name, _, ctxm}, env, _ctx, s) when is_atom(name) and is_atom(ctxm) do
    case Map.get(env, to_string(name)) do
      nil -> fresh(s)
      t -> {t, s}
    end
  end

  # anything else (tuples, maps, with, captures, …) — unconstrained hole.
  # `Tuple(…)` isn't a Rian signature type, so a `{node, rest}` decomposition stays
  # an opaque free var rather than a structured term.
  defp gen(_other, _env, _ctx, s), do: fresh(s)

  defp gen_block([], _env, _ctx, s), do: fresh(s)
  defp gen_block([last], env, ctx, s), do: gen(last, env, ctx, s)

  defp gen_block([{:=, _, [lhs, rhs]} | rest], env, ctx, s) do
    {rt, s} = gen(rhs, env, ctx, s)
    {env2, s} = gen_pat(lhs, rt, env, ctx, s)
    gen_block(rest, env2, ctx, s)
  end

  defp gen_block([stmt | rest], env, ctx, s) do
    {_, s} = gen(stmt, env, ctx, s)
    gen_block(rest, env, ctx, s)
  end

  defp gen_cons(h, t, env, ctx, s) do
    {ev, s} = fresh(s)
    {ht, s} = gen(h, env, ctx, s)
    {tt, s} = gen(t, env, ctx, s)
    {s, _} = unify(s, ht, ev)
    {s, _} = unify(s, tt, app("Vec", [ev]))
    {app("Vec", [ev]), s}
  end

  defp gen_args_then_fresh(args, env, ctx, s) do
    s =
      Enum.reduce(args, s, fn a, s ->
        {_, s} = gen(a, env, ctx, s)
        s
      end)

    fresh(s)
  end

  # a type-test predicate `is_T(arg)`: constrain `arg` to `type`, result is `Bool`.
  defp pred_con(a, type, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {s, _} = unify(s, at, con(type))
    {con("Bool"), s}
  end

  # `is_integer(arg)`: mark `arg` numeric (defaults to the portable `Int53`), result `Bool`.
  defp pred_num(a, env, ctx, s) do
    {at, s} = gen(a, env, ctx, s)
    {s, _} = mark_num(s, at)
    {con("Bool"), s}
  end

  defp call_sig(ctx, key, args, env, _outer, s) do
    case Map.get(ctx.prelude, key) do
      nil -> gen_args_then_fresh(args, env, ctx, s)
      sig -> instantiate(sig, args, env, ctx, s)
    end
  end

  # instantiate a callee sig: freshen tvars, unify each param with the arg type,
  # return the (freshened) return term.
  defp instantiate(%{params: ps, ret: ret, tvars: tvars}, args, env, ctx, s) do
    {fmap, s} = freshen_tvars(tvars, s)
    pterms = Enum.map(ps, &parse_type(&1, fmap))
    rterm = parse_type(ret, fmap)

    s =
      Enum.zip(args, pterms)
      |> Enum.reduce(s, fn {a, pt}, s ->
        {at, s} = gen(a, env, ctx, s)
        {s, _} = unify(s, at, pt)
        s
      end)

    {rterm, s}
  end

  defp freshen_tvars(tvars, s) do
    Enum.reduce(tvars, {%{}, s}, fn tv, {m, s} ->
      {v, s} = fresh(s)
      {Map.put(m, tv, v), s}
    end)
  end

  # ── patterns → constraints + bindings ─────────────────────────────────────

  # struct pattern `%Mod{…}` — the matched value IS that struct's type, so constrain
  # the param/scrutinee to the struct's declared name (Lever B). Field sub-patterns
  # recurse. Must precede the var clause (`%Mod{}` is `{:%, _, […]}`, not `{name, _, ctx}`).
  defp gen_pat({:%, _, [{:__aliases__, _, parts}, {:%{}, _, fields}]}, pv, env, ctx, s) do
    name = parts |> List.last() |> to_string()
    s = elem(unify(s, pv, con(name)), 0)

    # bind field sub-patterns (`%ENum{text: t}` binds `t`) — fresh vars (field types
    # aren't modelled), so nested names are at least in scope.
    Enum.reduce(fields, {env, s}, fn
      {_k, sub}, {env, s} ->
        {fv, s} = fresh(s)
        gen_pat(sub, fv, env, ctx, s)

      _, acc ->
        acc
    end)
  end

  defp gen_pat({name, _, c}, pv, env, _ctx, s) when is_atom(name) and is_atom(c) do
    sname = to_string(name)

    if sname == "_" or String.starts_with?(sname, "_"),
      do: {env, s},
      else: {Map.put(env, sname, pv), s}
  end

  defp gen_pat(n, pv, env, _ctx, s) when is_integer(n) do
    {s, _} = mark_num(s, pv)
    {env, s}
  end

  defp gen_pat(x, pv, env, _ctx, s) when is_float(x),
    do: {env, elem(unify(s, pv, con("Float64")), 0)}

  defp gen_pat(b, pv, env, _ctx, s) when is_binary(b),
    do: {env, elem(unify(s, pv, con("String")), 0)}

  defp gen_pat(bool, pv, env, _ctx, s) when is_boolean(bool),
    do: {env, elem(unify(s, pv, con("Bool")), 0)}

  # `[]` and `[h | t]` constrain the param to a Vec
  defp gen_pat([], pv, env, _ctx, s) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    {env, s}
  end

  # `[h | t]` parses as a 1-element list holding a `{:|, …}` cons cell — must
  # precede the proper-list clause so the cons isn't treated as an element.
  defp gen_pat([{:|, _, [h, t]}], pv, env, ctx, s), do: gen_pat_cons(h, t, pv, env, ctx, s)
  defp gen_pat({:|, _, [h, t]}, pv, env, ctx, s), do: gen_pat_cons(h, t, pv, env, ctx, s)

  defp gen_pat(list, pv, env, ctx, s) when is_list(list) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    Enum.reduce(list, {env, s}, fn el, {env, s} -> gen_pat(el, ev, env, ctx, s) end)
  end

  # anything else (tuples, ctor patterns) — no constraint in the MVP
  defp gen_pat(_other, _pv, env, _ctx, s), do: {env, s}

  defp gen_pat_cons(h, t, pv, env, ctx, s) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    {env, s} = gen_pat(h, ev, env, ctx, s)
    gen_pat(t, pv, env, ctx, s)
  end

  # ── union-find store over terms ───────────────────────────────────────────
  # store: %{binds: %{id => term}, num: MapSet of unbound numeric var ids, n: int}

  defp store_new, do: %{binds: %{}, num: MapSet.new(), n: 0}

  defp fresh(s), do: {{:var, s.n}, %{s | n: s.n + 1}}

  defp fresh_n(s, k) do
    Enum.reduce(1..k//1, {[], s}, fn _, {acc, s} ->
      {v, s} = fresh(s)
      {acc ++ [v], s}
    end)
  end

  # an integer literal: a fresh numeric var (defaults Int53, can widen)
  defp fresh_num(s) do
    {v, s} = fresh(s)
    {s, _} = mark_num(s, v)
    {v, s}
  end

  defp con(name), do: {:con, name}
  defp app(head, args), do: {:app, head, args}

  defp app1(head, s) do
    {v, s} = fresh(s)
    {app(head, [v]), s}
  end

  # follow var bindings to a head term
  defp resolve(s, {:var, id} = v) do
    case Map.get(s.binds, id) do
      nil -> v
      t -> resolve(s, t)
    end
  end

  defp resolve(_s, t), do: t

  defp mark_num(s, t) do
    case resolve(s, t) do
      {:var, id} -> {%{s | num: MapSet.put(s.num, id)}, :ok}
      _ -> {s, :ok}
    end
  end

  # unify two terms; returns {store, :ok | :conflict}
  defp unify(s, a, b) do
    a = resolve(s, a)
    b = resolve(s, b)
    do_unify(s, a, b)
  end

  defp do_unify(s, t, t), do: {s, :ok}

  defp do_unify(s, {:var, i}, {:var, j}) when i != j do
    # bind i -> j; carry numeric tag onto j
    num = if MapSet.member?(s.num, i), do: MapSet.put(s.num, j), else: s.num
    {%{s | binds: Map.put(s.binds, i, {:var, j}), num: num}, :ok}
  end

  defp do_unify(s, {:var, i}, t), do: bind_checked(s, i, t)
  defp do_unify(s, t, {:var, i}), do: bind_checked(s, i, t)

  defp do_unify(s, {:app, h, as}, {:app, h, bs}) when length(as) == length(bs) do
    Enum.zip(as, bs)
    |> Enum.reduce({s, :ok}, fn {x, y}, {s, acc} ->
      {s, r} = unify(s, x, y)
      {s, if(r == :conflict, do: :conflict, else: acc)}
    end)
  end

  defp do_unify(s, {:con, x}, {:con, y}) do
    case Rian.Check.join(x, y) do
      :unknown -> {s, :conflict}
      :mismatch -> {s, :conflict}
      _joined -> {s, :ok}
    end
  end

  defp do_unify(s, _a, _b), do: {s, :conflict}

  # Bind `id := t`, guarded by the two checks the literature requires before
  # binding a variable (Damas–Milner unification): the OCCURS-CHECK (binding a var
  # into a term that contains it would build an infinite/cyclic type and loop
  # `resolve`/`render` forever) and a numeric-soundness check (a var already used
  # numerically must not become a non-numeric concrete). On either, report a
  # conflict and leave the var free — honest partiality, not an exception.
  defp bind_checked(s, i, t) do
    cond do
      occurs?(s, i, t) -> {s, :conflict}
      num_conflict?(s, i, t) -> {s, :conflict}
      true -> {bind(s, i, t), :ok}
    end
  end

  defp occurs?(s, i, t) do
    case resolve(s, t) do
      {:var, ^i} -> true
      {:var, _} -> false
      {:con, _} -> false
      {:app, _, args} -> Enum.any?(args, &occurs?(s, i, &1))
    end
  end

  defp num_conflict?(s, i, t) do
    MapSet.member?(s.num, i) and match?({:con, _}, t) and not numeric_con?(t)
  end

  defp numeric_con?({:con, name}), do: String.starts_with?(name, ["Int", "UInt", "Float"])

  defp bind(s, id, t) do
    # if the var was numeric, propagate the constraint onto a var target
    s =
      case t do
        {:var, j} -> if MapSet.member?(s.num, id), do: %{s | num: MapSet.put(s.num, j)}, else: s
        _ -> s
      end

    %{s | binds: Map.put(s.binds, id, t)}
  end

  # ── Result analysis (Phase B): {:ok,_}/{:error,Tag} → `Payload | <error set>` ─
  # A group is a Result iff every tail expression is `{:ok, v}` or `{:error, Tag}`,
  # with at least one of each, and every error tag is a Capitalized ctor (a bare
  # atom / variable tag can't be a synthesized sum variant → bail, leave a hole).
  defp result_analysis(clause_envs, ctx, store) do
    tail_pairs =
      Enum.flat_map(clause_envs, fn {body, env} ->
        tails(body) |> Enum.map(&{&1, env})
      end)

    shapes = Enum.map(tail_pairs, fn {t, _} -> result_tag(t) end)

    cond do
      shapes == [] ->
        {:no, store}

      Enum.any?(shapes, &(&1 == :other)) ->
        {:no, store}

      Enum.any?(shapes, &(&1 == :bad_tag)) ->
        {:no, store}

      not Enum.any?(shapes, &match?({:ok, _}, &1)) ->
        {:no, store}

      not Enum.any?(shapes, &match?({:error, _}, &1)) ->
        {:no, store}

      true ->
        {payload_term, store, bad} = ok_payload(tail_pairs, ctx, store)
        tags = for {:error, tag} <- shapes, uniq: true, do: tag

        if payload_term != nil and not bad,
          do: {{:result, payload_term, tags}, store},
          else: {:no, store}
    end
  end

  # unify the types of every `{:ok, v}` payload; return `{term | nil, store, bad?}`.
  # `bad?` is set when two ok-payloads conflict (e.g. `{:ok, 1}` and `{:ok, "s"}`) —
  # the caller then leaves a hole rather than pick one (no accidental fill).
  defp ok_payload(tail_pairs, ctx, store) do
    Enum.reduce(tail_pairs, {nil, store, false}, fn {t, env}, {acc, s, bad} ->
      case result_tag(t) do
        {:ok, v} ->
          {vt, s} = gen(v, env, ctx, s)
          {s, r} = if acc, do: unify(s, acc, vt), else: {s, :ok}

          {case acc do
             nil -> vt
             v -> v
           end, s, bad or r == :conflict}

        _ ->
          {acc, s, bad}
      end
    end)
  end

  defp result_tag({:ok, v}), do: {:ok, v}

  defp result_tag({:error, {:__aliases__, _, parts}}),
    do: {:error, parts |> List.last() |> to_string()}

  defp result_tag({:error, _}), do: :bad_tag
  defp result_tag(_), do: :other

  # tail expressions of a body (the values it can evaluate to), recursing into
  # `if`/`case`/blocks. Anything else is its own single tail.
  defp tails({:__block__, _, stmts}) when is_list(stmts) and stmts != [],
    do: tails(List.last(stmts))

  defp tails({:if, _, [_, kw]}) do
    tails(body_of(Keyword.get(kw, :do))) ++
      if Keyword.has_key?(kw, :else), do: tails(body_of(Keyword.get(kw, :else))), else: []
  end

  defp tails({:case, _, [_, [do: arms]]}) do
    Enum.flat_map(arms, fn arm ->
      {_, body} = case_arm(arm)
      tails(body)
    end)
  end

  defp tails(node), do: [node]

  # Generalization (the Damas–Milner [Gen] rule, adapted for an INCOMPLETE inferer).
  # In a complete HM checker a free signature variable is, by definition,
  # polymorphic, so all free vars generalize. Here a var can also be free because
  # analysis hit something it doesn't model (an unknown call, a tuple) — so blindly
  # generalizing would over-claim. We therefore quantify only the vars that
  # genuinely flow input→output: a non-numeric free var appearing in BOTH some
  # parameter term and the return term (`id`, `head`, `map`-shaped). Each distinct
  # connector gets its own tvar (`T`, `U`, …); other free vars stay holes.
  defp generalize_map(pvars, rvar, store) do
    param_vars = pvars |> Enum.flat_map(&free_vars(store, &1)) |> MapSet.new()
    ret_vars = free_vars(store, rvar)

    ret_vars
    |> Enum.uniq()
    |> Enum.filter(&(MapSet.member?(param_vars, &1) and not MapSet.member?(store.num, &1)))
    |> Enum.with_index()
    |> Map.new(fn {id, i} -> {id, tvar_name(i)} end)
  end

  # the free unification variables reachable from a resolved term
  defp free_vars(store, t) do
    case resolve(store, t) do
      {:var, id} -> [id]
      {:con, _} -> []
      {:app, _, args} -> Enum.flat_map(args, &free_vars(store, &1))
    end
  end

  defp tvar_name(i), do: Enum.at(~w(T U V W X Y Z), i, "T#{i}")

  defp render(store, gmap, t) do
    case resolve(store, t) do
      {:con, name} ->
        name

      {:app, head, parts} ->
        # a parametric type is concrete only if EVERY argument is — an unresolved
        # element (`Vec(<unknown>)`) makes the whole slot a hole, never `Vec(hole)`
        # (which would be invalid Rian — an accidental fill).
        rendered = Enum.map(parts, &render(store, gmap, &1))

        if Enum.any?(rendered, &(&1 == :hole)),
          do: :hole,
          else: "#{head}(#{Enum.join(rendered, ", ")})"

      {:var, id} ->
        cond do
          Map.has_key?(gmap, id) -> gmap[id]
          MapSet.member?(store.num, id) -> "Int53"
          true -> :hole
        end
    end
  end

  defp hole_or(:hole, h), do: h
  defp hole_or(t, _h), do: t

  # operates on the FINAL rendered slot strings (`"_Unk"` are the holes).
  defp build_ledger(params, ret) do
    param_entries =
      params
      |> Enum.with_index()
      |> Enum.filter(fn {t, _} -> t == "_Unk" end)
      |> Enum.map(fn {_, i} -> {"param##{i}", :unresolved} end)

    ret_entry = if ret == "_Unk", do: [{"ret", :unresolved}], else: []
    param_entries ++ ret_entry
  end

  # ── small Elixir-AST helpers (mirror Rian.Transpile) ──────────────────────

  defp body_of({:__block__, _, [one]}), do: one
  defp body_of(node), do: node

  defp case_arm({:->, _, [[{:when, _, [p, _g]}], body]}), do: {p, body}
  defp case_arm({:->, _, [[p], body]}), do: {p, body}
  defp case_arm(_), do: {{:_, [], nil}, nil}

  defp mod_name({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()
  defp mod_name(a) when is_atom(a), do: to_string(a)
  defp mod_name(_), do: "?"

  # highest `&N` placeholder index in a capture body (0 if none).
  defp max_ph({:&, _, [k]}) when is_integer(k), do: k
  defp max_ph(t) when is_tuple(t), do: t |> Tuple.to_list() |> max_ph()
  defp max_ph(l) when is_list(l), do: Enum.reduce(l, 0, &max(max_ph(&1), &2))
  defp max_ph(_), do: 0

  # ── type-string → term (for prelude sig instantiation) ────────────────────

  @doc false
  @spec parse_type(String.t(), map()) :: term()
  def parse_type(str, fmap) when is_binary(str) do
    str = String.trim(str)

    case parametric_split(str) do
      {head, inner} ->
        args = Rian.TypeStr.split_top_commas(inner) |> Enum.map(&parse_type(&1, fmap))
        {:app, head, args}

      nil ->
        Map.get(fmap, str, {:con, str})
    end
  end

  # Recognize a parametric type `Head(inner)` by *tokenizing with the Rian lexer*
  # rather than sniffing it with a regex: the shape is a leading identifier, an
  # opening paren, and a closing paren at the end. The inner substring is then
  # sliced off literally and handed to the shared top-level-comma splitter.
  defp parametric_split(str) do
    case Rian.Lexer.expr_tokens(str) do
      [{:id, head}, {:lparen} | _] = toks ->
        if List.last(toks) == {:rparen} do
          inner =
            str
            |> String.replace_prefix(head, "")
            |> String.trim_leading()
            |> String.replace_prefix("(", "")
            |> String.replace_suffix(")", "")

          {head, inner}
        end

      _ ->
        nil
    end
  end
end
