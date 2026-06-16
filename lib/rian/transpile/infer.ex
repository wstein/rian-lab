defmodule Rian.Transpile.Infer do
  @moduledoc """
  Whole-program type inference that fills the transpiler's `_Ty`/`_Ret` holes
  (ADR-0034-aligned: it *produces* explicit signatures rather than relaxing the
  declare-public boundary).

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

  def clear_xmod, do: :persistent_term.erase({__MODULE__, :xmod})

  defp xmod_cache, do: :persistent_term.get({__MODULE__, :xmod}, %{})

  defp hole_sig?(%{params: ps, ret: r}), do: r == "_Ret" or Enum.any?(ps, &(&1 == "_Ty"))

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
      prog = path |> File.read!() |> Decl.parse()

      for m <- Map.get(prog, :mods, []), f <- m.funcs do
        {{m.name, to_string(f.name), length(f.params)}, sig_of(f)}
      end
    end)
    |> Map.new()
  rescue
    # a prelude that fails to parse must not crash transpilation — degrade to "no
    # prelude knowledge" (everything stays a hole rather than mis-typed).
    _ -> %{}
  end

  defp sig_of(f), do: %{params: Enum.map(f.params, & &1.type), ret: f.ret, tvars: f.tvars}

  # ── public entry: infer one def group ─────────────────────────────────────

  @doc """
  Infer a def group (all clauses of one name/arity). Returns
  `%{params: [type_string], ret: type_string, tvars: [name], ledger: [{slot, reason}]}`
  where an unresolved slot is the literal hole `"_Ty"`/`"_Ret"` and `ledger`
  records why each hole was left (for `--infer-report`).
  """
  def infer_group(%{clauses: clauses}, ctx) do
    arity = hd(clauses).arity
    s0 = store_new()
    {pvars, s1} = fresh_n(s0, arity)
    {rvar, s2} = fresh(s1)

    # build the store; keep each clause's body + bound env for Result analysis.
    {store, clause_envs} =
      Enum.reduce(clauses, {s2, []}, fn clause, {s, envs} ->
        {env, s} = bind_params(clause.args, pvars, s)
        {bt, s} = gen(clause.body, env, ctx, s)
        {s, _} = unify(s, rvar, bt)
        {s, envs ++ [{clause.body, env}]}
      end)

    # Phase B Result analysis runs BEFORE rendering — it adds payload constraints
    # (e.g. a `{:ok, div(a,b)}` pins `a`/`b`) that the param types must reflect.
    {res, store} = result_analysis(clause_envs, ctx, store)

    gmap = generalize_map(pvars, rvar, store)
    params = pvars |> Enum.map(&(render(store, gmap, &1) |> hole_or("_Ty")))
    tvars = gmap |> Map.values() |> Enum.uniq() |> Enum.sort()

    # a Result (all tails `{:ok, _}`/`{:error, Tag}`) types as `Payload | <error set>`;
    # the caller synthesizes the `type … := Tag | …` declaration (ADR-0040).
    {ret, tags, result} =
      case res do
        {:result, payload_term, tg} ->
          case render(store, gmap, payload_term) do
            :hole -> {render(store, gmap, rvar) |> hole_or("_Ret"), [], false}
            p -> {p, tg, true}
          end

        :no ->
          {render(store, gmap, rvar) |> hole_or("_Ret"), [], false}
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

  # bind each clause's parameter pattern against the shared param var
  defp bind_params(args, pvars, store) do
    Enum.zip(args, pvars)
    |> Enum.reduce({%{}, store}, fn {pat, pv}, {env, s} ->
      gen_pat(pat, pv, env, s)
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
        {env2, s} = gen_pat(pat, st, env, s)
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
      |> Enum.reduce({env, s}, fn {a, av}, {e, s} -> gen_pat(a, av, e, s) end)

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

  # remote call `Mod.fun(args)` — map via stdlib table to a prelude sig, or leave free
  defp gen({{:., _, [mod, fun]}, _, args}, env, ctx, s) when is_list(args) do
    m = mod_name(mod)

    case Map.get(ctx.stdlib, {m, fun, length(args)}) do
      {rmod, rfun} ->
        call_sig(ctx, {rmod, rfun, length(args)}, args, env, ctx, s)

      nil ->
        # a cross-module call to a sibling Rian module (Phase A whole-program table)
        case Map.get(ctx.xmod, {m, to_string(fun), length(args)}) do
          nil -> gen_args_then_fresh(args, env, ctx, s)
          sig -> instantiate(sig, args, env, ctx, s)
        end
    end
  end

  # local call `f(args)` — use a sibling signature if known, else leave free
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

  # anything else (tuples, maps, with, captures, …) — unconstrained hole
  defp gen(_other, _env, _ctx, s), do: fresh(s)

  defp gen_block([], _env, _ctx, s), do: fresh(s)
  defp gen_block([last], env, ctx, s), do: gen(last, env, ctx, s)

  defp gen_block([{:=, _, [lhs, rhs]} | rest], env, ctx, s) do
    {rt, s} = gen(rhs, env, ctx, s)
    {env2, s} = gen_pat(lhs, rt, env, s)
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
    s = Enum.reduce(args, s, fn a, s -> {_, s} = gen(a, env, ctx, s); s end)
    fresh(s)
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

  defp gen_pat({name, _, c}, pv, env, s) when is_atom(name) and is_atom(c) do
    sname = to_string(name)
    if sname == "_" or String.starts_with?(sname, "_"), do: {env, s}, else: {Map.put(env, sname, pv), s}
  end

  defp gen_pat(n, pv, env, s) when is_integer(n) do
    {s, _} = mark_num(s, pv)
    {env, s}
  end

  defp gen_pat(x, pv, env, s) when is_float(x), do: {env, elem(unify(s, pv, con("Float64")), 0)}
  defp gen_pat(b, pv, env, s) when is_binary(b), do: {env, elem(unify(s, pv, con("String")), 0)}
  defp gen_pat(bool, pv, env, s) when is_boolean(bool), do: {env, elem(unify(s, pv, con("Bool")), 0)}

  # `[]` and `[h | t]` constrain the param to a Vec
  defp gen_pat([], pv, env, s) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    {env, s}
  end

  # `[h | t]` parses as a 1-element list holding a `{:|, …}` cons cell — must
  # precede the proper-list clause so the cons isn't treated as an element.
  defp gen_pat([{:|, _, [h, t]}], pv, env, s), do: gen_pat_cons(h, t, pv, env, s)
  defp gen_pat({:|, _, [h, t]}, pv, env, s), do: gen_pat_cons(h, t, pv, env, s)

  defp gen_pat(list, pv, env, s) when is_list(list) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    Enum.reduce(list, {env, s}, fn el, {env, s} -> gen_pat(el, ev, env, s) end)
  end

  # anything else (tuples, ctor/struct patterns) — no constraint in the MVP
  defp gen_pat(_other, _pv, env, s), do: {env, s}

  defp gen_pat_cons(h, t, pv, env, s) do
    {ev, s} = fresh(s)
    {s, _} = unify(s, pv, app("Vec", [ev]))
    {env, s} = gen_pat(h, ev, env, s)
    gen_pat(t, pv, env, s)
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

  defp numeric_con?({:con, name}), do: Regex.match?(~r/^(Int|UInt|Float)/, name)

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
      shapes == [] -> {:no, store}
      Enum.any?(shapes, &(&1 == :other)) -> {:no, store}
      Enum.any?(shapes, &(&1 == :bad_tag)) -> {:no, store}
      not Enum.any?(shapes, &match?({:ok, _}, &1)) -> {:no, store}
      not Enum.any?(shapes, &match?({:error, _}, &1)) -> {:no, store}
      true ->
        {payload_term, store} = ok_payload(tail_pairs, ctx, store)
        tags = for {:error, tag} <- shapes, uniq: true, do: tag
        if payload_term, do: {{:result, payload_term, tags}, store}, else: {:no, store}
    end
  end

  # unify the types of every `{:ok, v}` payload; return the shared term (or nil).
  defp ok_payload(tail_pairs, ctx, store) do
    Enum.reduce(tail_pairs, {nil, store}, fn {t, env}, {acc, s} ->
      case result_tag(t) do
        {:ok, v} ->
          {vt, s} = gen(v, env, ctx, s)
          s = if acc, do: elem(unify(s, acc, vt), 0), else: s
          {acc || vt, s}

        _ ->
          {acc, s}
      end
    end)
  end

  defp result_tag({:ok, v}), do: {:ok, v}
  defp result_tag({:error, {:__aliases__, _, parts}}), do: {:error, parts |> List.last() |> to_string()}
  defp result_tag({:error, _}), do: :bad_tag
  defp result_tag(_), do: :other

  # tail expressions of a body (the values it can evaluate to), recursing into
  # `if`/`case`/blocks. Anything else is its own single tail.
  defp tails({:__block__, _, stmts}) when is_list(stmts) and stmts != [], do: tails(List.last(stmts))

  defp tails({:if, _, [_, kw]}) do
    tails(body_of(Keyword.get(kw, :do))) ++
      if Keyword.has_key?(kw, :else), do: tails(body_of(Keyword.get(kw, :else))), else: []
  end

  defp tails({:case, _, [_, [do: arms]]}) do
    Enum.flat_map(arms, fn arm -> {_, body} = case_arm(arm); tails(body) end)
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

      {:app, "Vec", [e]} ->
        "Vec(#{render(store, gmap, e)})"

      {:app, "Option", [e]} ->
        "Option(#{render(store, gmap, e)})"

      {:app, "Fn", parts} ->
        "Fn(#{Enum.map_join(parts, ", ", &render(store, gmap, &1))})"

      {:app, head, parts} ->
        "#{head}(#{Enum.map_join(parts, ", ", &render(store, gmap, &1))})"

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

  # operates on the FINAL rendered slot strings (`"_Ty"`/`"_Ret"` are the holes).
  defp build_ledger(params, ret) do
    param_entries =
      params
      |> Enum.with_index()
      |> Enum.filter(fn {t, _} -> t == "_Ty" end)
      |> Enum.map(fn {_, i} -> {"param##{i}", :unresolved} end)

    ret_entry = if ret == "_Ret", do: [{"ret", :unresolved}], else: []
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
  def parse_type(str, fmap) when is_binary(str) do
    str = String.trim(str)

    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$/s, str) do
      [_, head, inner] ->
        args = Rian.TypeStr.split_top_commas(inner) |> Enum.map(&parse_type(&1, fmap))
        {:app, head, args}

      nil ->
        cond do
          Map.has_key?(fmap, str) -> fmap[str]
          tvar?(str) -> {:con, str}
          true -> {:con, str}
        end
    end
  end

  defp tvar?(s), do: Regex.match?(~r/^[A-Z][0-9]?$/, s)
end
