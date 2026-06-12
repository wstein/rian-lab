defmodule Rian.Check do
  @moduledoc """
  Type checking — first increment of ADR-0034 (unification-based inference).

  This is a deliberately **conservative** slice: it infers the type of an
  expression where it can (literals, arithmetic, comparisons, concat, `if`/block
  value) and **only reports an error when it can *prove* a mismatch** — a body
  whose inferred concrete type differs from the function's declared return type.
  Anything it cannot pin down infers to `:unknown` and never rejects, so it can
  be grown toward the full ADR-0034 design (error sets, protocol bounds) without
  ever rejecting a valid program in the meantime.

  **Flow narrowing (ADR-0034 pillar 4)** is implemented: a `case` arm — and a
  clause head, which is a one-arm `case` on the parameters — refines a matched
  constructor's bound variables to that variant's field types, so the checker
  infers through `case` bodies and pattern clauses rather than giving up at
  `:unknown`.

  **Error sets (ADR-0034 pillar 2 / ADR-0040 §4)** are checked at the declared
  boundary: a `T | E` return type declares the error set `E`; the body's
  constructed error tags (`{:error, Tag}`) must be a *subset* of `E`
  (over-declaration is allowed). A named `E` expands to its variant tags.
  *Not yet:* inferring a private function's set from its propagated callees (the
  `with`-composition half of §4).

  **Concrete generics (ADR-0042, BEAM-first)** are inferred: a list literal is
  `Vec(T)`, a variant value/constructor-call carries its sum type, and a call
  carries the callee's declared return type — so the checker actually verifies
  list/recursive/constructor-shaped code (the self-hosting spike's evidence) by
  string-equal unification of concrete parametric types. `forall T` binders are
  parsed; a generic return type (mentioning a type variable) is checked
  *conservatively* (no structural type-variable unification yet) and protocol
  bounds are not yet enforced.

  Types here are the Crystal-family primitive names (`Int64`/`Float64`/`String`/
  `Bool`, ADR-0033) plus `:unknown`. `unify/2` is the kernel: equal types unify
  to themselves, `:unknown` unifies with anything, two differing concrete types
  are a `:mismatch`.
  """
  alias Rian.IR.Func
  alias Rian.Pratt

  defmodule Error do
    @moduledoc "Raised by the compile-time type gate on a proven type mismatch."
    defexception [:message]
  end

  @bool_ops ~w(< <= > >= == != and or in)
  @int_ops ~w(div rem)
  @arith ~w(+ - *)

  # ── unification kernel ─────────────────────────────────────────────────
  @doc "Unify two types: equal -> itself; `:unknown` -> the other; differ -> `:mismatch`."
  def unify(t, t), do: t
  def unify(:unknown, t), do: t
  def unify(t, :unknown), do: t
  def unify(_, _), do: :mismatch

  # ── inference ──────────────────────────────────────────────────────────
  # `ic` is the static inference context (a map): `:tdefs` (ctor -> field types,
  # for flow narrowing), `:funs` (function name -> declared return type), and
  # `:ctors` (ctor -> its sum-type name, so a variant value infers its type).
  # `%{}` disables all three. `env` is the per-scope variable map.
  @doc "Infer the type of an expression AST under `env` (name -> type); `:unknown` when unsure."
  def infer(ast, env \\ %{}, ic \\ %{})

  def infer({:num, n}, _env, _ic),
    do: if(String.contains?(n, ".") or String.match?(n, ~r/[eE]/), do: "Float64", else: "Int64")

  def infer({:str, _}, _env, _ic), do: "String"
  def infer({:id, b}, _env, _ic) when b in ~w(true false), do: "Bool"
  # a name resolves to a bound var, else a nullary variant constructor, else unknown
  def infer({:id, x}, env, ic), do: Map.get(env, x) || ctor_type(ic, x) || :unknown
  def infer({:unary, "-", x}, env, ic), do: infer(x, env, ic)
  def infer({:unary, "not", _}, _env, _ic), do: "Bool"

  def infer({:bin, op, l, r}, env, ic) do
    cond do
      op in @bool_ops -> "Bool"
      op == "<>" -> "String"
      op == "/" -> "Float64"
      op in @int_ops -> "Int64"
      op in @arith -> conservative(unify(infer(l, env, ic), infer(r, env, ic)))
      true -> :unknown
    end
  end

  # a call to a constructor infers its sum type; a call to a known function infers
  # that function's declared return type; otherwise unknown
  def infer({:call, {:id, f}, _args}, _env, ic),
    do: ctor_type(ic, f) || Map.get(Map.get(ic, :funs, %{}), f) || :unknown

  def infer({:if, _c, then_arm, else_arm}, env, ic),
    do: conservative(unify(infer(then_arm, env, ic), infer(else_arm, env, ic)))

  # `case` — flow narrowing: each arm body is inferred under an env where the
  # arm pattern's bindings are refined against the scrutinee's type. The case's
  # type is the unification of all arm bodies (conservative on mismatch).
  def infer({:case, scrut, arms}, env, ic) do
    st = infer(scrut, env, ic)

    arms
    |> Enum.map(fn {pat, _guard, body} -> infer(body, narrow(pat, st, ic, env), ic) end)
    |> Enum.reduce(:unknown, fn t, acc -> conservative(unify(acc, t)) end)
  end

  # a list literal infers `Vec(T)` (the family list type) when its elements — and
  # any cons tail — agree on a concrete element type `T`; else `:unknown`
  def infer({:list_lit, elems, tail}, env, ic) do
    elem_t =
      elems
      |> Enum.map(&infer(&1, env, ic))
      |> Enum.reduce(:unknown, &conservative(unify(&1, &2)))

    case {elem_t, list_elem(infer_tail(tail, env, ic))} do
      {t, te} when te == :unknown or te == t -> list_of(conservative(t))
      _ -> :unknown
    end
  end

  def infer({:block, stmts}, env, ic), do: infer_block(stmts, env, ic, :unknown)
  # a `with` yields its do-block value on the happy path (clause-bound vars are
  # not tracked yet -> they infer `:unknown`, keeping the checker conservative)
  def infer({:with, _clauses, body, _els}, env, ic), do: infer(body, env, ic)
  def infer(_other, _env, _ic), do: :unknown

  defp ctor_type(ic, name), do: Map.get(Map.get(ic, :ctors, %{}), name)

  defp infer_tail(nil, _env, _ic), do: :unknown
  defp infer_tail({:tail, e}, env, ic), do: infer(e, env, ic)

  # `Vec(T)` string helpers (types are strings; concrete generics unify by ==).
  defp list_of(:unknown), do: :unknown
  defp list_of(t), do: "Vec(#{t})"

  defp list_elem("Vec(" <> rest), do: String.trim_trailing(rest, ")")
  defp list_elem(_), do: :unknown

  defp infer_block([], _env, _ic, value), do: value

  defp infer_block([{:bind, n, e} | rest], env, ic, _value) do
    t = infer(e, env, ic)
    infer_block(rest, Map.put(env, n, t), ic, t)
  end

  defp infer_block([{:expr, e} | rest], env, ic, _value),
    do: infer_block(rest, env, ic, infer(e, env, ic))

  # Narrow one pattern against the type it matches, binding its variables.
  # A `{:var}` takes the matched type directly; a constructor pattern looks up
  # its field types and narrows each argument pattern in turn (recursively).
  # Unknown constructor or no `tdefs` -> field variables stay `:unknown`.
  defp narrow({:var, name}, type, _ic, env), do: Map.put(env, name, type)

  defp narrow({:ctor, ctor, args}, _type, ic, env) do
    field_types = Map.get(Map.get(ic, :tdefs, %{}), ctor, [])

    args
    |> Enum.with_index()
    |> Enum.reduce(env, fn {p, i}, env ->
      narrow(p, Enum.at(field_types, i, :unknown), ic, env)
    end)
  end

  defp narrow(_pat, _type, _ic, env), do: env

  # a mismatch deep in arithmetic stays conservative (we do not model coercion
  # fully yet) rather than rejecting; only the body-vs-return check rejects
  defp conservative(:mismatch), do: :unknown
  defp conservative(t), do: t

  # ── function checking ──────────────────────────────────────────────────
  @doc """
  Check one function. `ic` is the inference context (`:tdefs`/`:funs`/`:ctors`);
  `tsets` maps an error-set type name to its tags (ADR-0040 §4). Returns `:ok` or
  `{:error, message}`. Two checks run:

    * **return type** — no clause body's inferred concrete type may *contradict*
      the declared return type (now including parametric `Vec(T)` and a body's
      sum-variant / function-call result, ADR-0042 — concrete generics);
    * **error set** — when the return type is `T | E` (a `Result`), every error
      tag the body constructs (`{:error, Tag}`) must be in the declared set `E`
      (over-declaration is allowed; ADR-0040 §4).
  """
  def check_func(func, ic \\ %{}, tsets \\ %{})

  def check_func(%Func{} = f, ic, tsets) do
    with :ok <- check_return(f, ic), do: check_error_set(f, tsets)
  end

  defp check_return(%Func{name: name, params: ps, ret: ret, tvars: tvars, clauses: clauses}, ic) do
    # A return type mentioning a `forall` type variable is generic; we don't yet
    # unify type variables structurally, so such a function is checked
    # conservatively (its body is not contradicted). Concrete returns are checked.
    if generic_ret?(ret, tvars) do
      :ok
    else
      Enum.find_value(clauses, :ok, fn c ->
        body_t = infer(Pratt.parse_body(c.body), clause_env(c.pats, ps, ic), ic)

        case unify(body_t, ret) do
          :mismatch ->
            {:error,
             "`#{name}`: body has type `#{body_t}` but the declared return type is `#{ret}`"}

          _ ->
            nil
        end
      end)
    end
  end

  defp generic_ret?(_ret, []), do: false
  defp generic_ret?(ret, tvars), do: Enum.any?(tvars, &Regex.match?(~r/\b#{&1}\b/, ret))

  # ADR-0040 §4: a `T | E` return type declares the error set `E`; every error
  # the body actually constructs must be in it (the body's set ⊆ the declared
  # set — over-declaration is fine). Non-`Result` returns are unconstrained here.
  defp check_error_set(%Func{ret: ret} = f, tsets) do
    case String.split(ret, "|") |> Enum.map(&String.trim/1) do
      [ok_t, err_t] when ok_t != "" ->
        declared = MapSet.new(Map.get(tsets, err_t, [err_t]))

        produced =
          f.clauses
          |> Enum.flat_map(fn c -> c.body |> Pratt.parse_body() |> error_tags() end)
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        case MapSet.difference(produced, declared) |> MapSet.to_list() do
          [] ->
            :ok

          extra ->
            {:error,
             "`#{f.name}`: returns error(s) #{inspect(extra)} not in its declared set `#{err_t}`"}
        end

      _ ->
        :ok
    end
  end

  # Collect the tag names of every `{:error, Tag}` constructed in an expression.
  defp error_tags({:tuple, [{:atom, "error"}, e]}), do: [tag_name(e) | error_tags(e)]
  defp error_tags(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.flat_map(&error_tags/1)
  defp error_tags(l) when is_list(l), do: Enum.flat_map(l, &error_tags/1)
  defp error_tags(_), do: []

  # An error tag is a PascalCase constructor (`NotFound`, `DivByZero(…)`). A
  # lowercase identifier in error position is a *bound variable* re-propagating an
  # existing error (`{:error, e} -> {:error, e}`), not a newly-constructed tag.
  defp tag_name({:id, n}), do: if(pascal?(n), do: n)
  defp tag_name({:call, {:id, n}, _}), do: if(pascal?(n), do: n)
  defp tag_name(_), do: nil

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  # Bind names introduced by the clause head, narrowing constructor patterns
  # against their parameter type (flow narrowing applies to clause heads too —
  # a clause head is a one-arm `case` on the parameters).
  defp clause_env(pats, params, ic) do
    pats
    |> Enum.zip(params)
    |> Enum.reduce(%{}, fn {pat, param}, env -> narrow(pat, param.type, ic, env) end)
  end

  @doc "Parse source and check every function; returns `:ok` or the first `{:error, message}`."
  def check(src), do: src |> Rian.Decl.parse() |> check_program()

  @doc """
  Check every function in a parsed program — top-level and inside every module.
  Returns `:ok` or the first `{:error, message}`.
  """
  def check_program(%{funcs: funcs} = prog) do
    types = all_types(prog)
    all_funcs = funcs ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    ic = %{
      tdefs: type_table(types),
      funs: Map.new(all_funcs, fn f -> {f.name, f.ret} end),
      ctors: ctor_types(types, prog)
    }

    tsets = error_sets(types)
    Enum.find_value(all_funcs, :ok, fn f -> with :ok <- check_func(f, ic, tsets), do: nil end)
  end

  # ctor name -> the sum type it builds (so a variant value/call infers its type);
  # struct names map to themselves (a struct constructor builds its own type).
  defp ctor_types(types, prog) do
    structs =
      Map.get(prog, :structs, []) ++ for(m <- Map.get(prog, :mods, []), s <- m.structs, do: s)

    from_variants = for t <- types, v <- t.variants, into: %{}, do: {v.ctor, t.name}
    Enum.reduce(structs, from_variants, fn s, acc -> Map.put(acc, s.name, s.name) end)
  end

  defp all_types(prog),
    do: Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)

  # Constructor table for flow narrowing: every sum-type variant mapped to its
  # ordered field types.
  defp type_table(types) do
    for t <- types, v <- t.variants, into: %{} do
      {v.ctor, Enum.map(v.fields, & &1.type)}
    end
  end

  # Error-set table (ADR-0040 §4): a sum type's name -> its tag (variant) names,
  # so a declared `T | E` can be expanded when `E` is a named set.
  defp error_sets(types) do
    for t <- types, into: %{} do
      {t.name, Enum.map(t.variants, & &1.ctor)}
    end
  end

  @doc "The compile-time type gate: raise `Rian.Check.Error` on a proven mismatch, else `:ok`."
  def gate!(prog) do
    case check_program(prog) do
      :ok -> :ok
      {:error, msg} -> raise Error, msg
    end
  end
end
