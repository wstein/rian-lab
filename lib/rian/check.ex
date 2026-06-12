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
  `with`-composition half of §4). Protocol bounds (pillar 3, ADR-0042) await
  implementation of the `forall`/`protocol` surface.

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
  # `tdefs` is the constructor table `ctor_name => [field_type]`, used for flow
  # narrowing (ADR-0034 pillar 4): a `case`/clause pattern refines its bound
  # variables to the matched variant's field types. `%{}` disables narrowing.
  @doc "Infer the type of an expression AST under `env` (name -> type); `:unknown` when unsure."
  def infer(ast, env \\ %{}, tdefs \\ %{})

  def infer({:num, n}, _env, _td),
    do: if(String.contains?(n, ".") or String.match?(n, ~r/[eE]/), do: "Float64", else: "Int64")

  def infer({:str, _}, _env, _td), do: "String"
  def infer({:id, b}, _env, _td) when b in ~w(true false), do: "Bool"
  def infer({:id, x}, env, _td), do: Map.get(env, x, :unknown)
  def infer({:unary, "-", x}, env, td), do: infer(x, env, td)
  def infer({:unary, "not", _}, _env, _td), do: "Bool"

  def infer({:bin, op, l, r}, env, td) do
    cond do
      op in @bool_ops -> "Bool"
      op == "<>" -> "String"
      op == "/" -> "Float64"
      op in @int_ops -> "Int64"
      op in @arith -> conservative(unify(infer(l, env, td), infer(r, env, td)))
      true -> :unknown
    end
  end

  def infer({:if, _c, then_arm, else_arm}, env, td),
    do: conservative(unify(infer(then_arm, env, td), infer(else_arm, env, td)))

  # `case` — flow narrowing: each arm body is inferred under an env where the
  # arm pattern's bindings are refined against the scrutinee's type. The case's
  # type is the unification of all arm bodies (conservative on mismatch).
  def infer({:case, scrut, arms}, env, td) do
    st = infer(scrut, env, td)

    arms
    |> Enum.map(fn {pat, _guard, body} -> infer(body, narrow(pat, st, td, env), td) end)
    |> Enum.reduce(:unknown, fn t, acc -> conservative(unify(acc, t)) end)
  end

  def infer({:block, stmts}, env, td), do: infer_block(stmts, env, td, :unknown)
  # a `with` yields its do-block value on the happy path (clause-bound vars are
  # not tracked yet -> they infer `:unknown`, keeping the checker conservative)
  def infer({:with, _clauses, body, _els}, env, td), do: infer(body, env, td)
  def infer(_other, _env, _td), do: :unknown

  defp infer_block([], _env, _td, value), do: value

  defp infer_block([{:bind, n, e} | rest], env, td, _value) do
    t = infer(e, env, td)
    infer_block(rest, Map.put(env, n, t), td, t)
  end

  defp infer_block([{:expr, e} | rest], env, td, _value),
    do: infer_block(rest, env, td, infer(e, env, td))

  # Narrow one pattern against the type it matches, binding its variables.
  # A `{:var}` takes the matched type directly; a constructor pattern looks up
  # its field types and narrows each argument pattern in turn (recursively).
  # Unknown constructor or no `tdefs` -> field variables stay `:unknown`.
  defp narrow({:var, name}, type, _td, env), do: Map.put(env, name, type)

  defp narrow({:ctor, ctor, args}, _type, td, env) do
    field_types = Map.get(td, ctor, [])

    args
    |> Enum.with_index()
    |> Enum.reduce(env, fn {p, i}, env ->
      narrow(p, Enum.at(field_types, i, :unknown), td, env)
    end)
  end

  defp narrow(_pat, _type, _td, env), do: env

  # a mismatch deep in arithmetic stays conservative (we do not model coercion
  # fully yet) rather than rejecting; only the body-vs-return check rejects
  defp conservative(:mismatch), do: :unknown
  defp conservative(t), do: t

  # ── function checking ──────────────────────────────────────────────────
  @doc """
  Check one function. `tdefs` enables flow narrowing; `tsets` maps an error-set
  type name to its tags (for the ADR-0040 §4 declared-⊆ check). Returns `:ok` or
  `{:error, message}`. Two checks run:

    * **return type** — no clause body's inferred concrete type may *contradict*
      the declared return type;
    * **error set** — when the return type is `T | E` (a `Result`), every error
      tag the body constructs (`{:error, Tag}`) must be in the declared set `E`
      (over-declaration is allowed; ADR-0040 §4).
  """
  def check_func(func, tdefs \\ %{}, tsets \\ %{})

  def check_func(%Func{} = f, tdefs, tsets) do
    with :ok <- check_return(f, tdefs), do: check_error_set(f, tsets)
  end

  defp check_return(%Func{name: name, params: ps, ret: ret, clauses: clauses}, tdefs) do
    Enum.find_value(clauses, :ok, fn c ->
      body_t = infer(Pratt.parse_body(c.body), clause_env(c.pats, ps, tdefs), tdefs)

      case unify(body_t, ret) do
        :mismatch ->
          {:error,
           "`#{name}`: body has type `#{body_t}` but the declared return type is `#{ret}`"}

        _ ->
          nil
      end
    end)
  end

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
  defp clause_env(pats, params, tdefs) do
    pats
    |> Enum.zip(params)
    |> Enum.reduce(%{}, fn {pat, param}, env -> narrow(pat, param.type, tdefs, env) end)
  end

  @doc "Parse source and check every function; returns `:ok` or the first `{:error, message}`."
  def check(src), do: src |> Rian.Decl.parse() |> check_program()

  @doc """
  Check every function in a parsed program — top-level and inside every module.
  Returns `:ok` or the first `{:error, message}`.
  """
  def check_program(%{funcs: funcs} = prog) do
    types = all_types(prog)
    tdefs = type_table(types)
    tsets = error_sets(types)
    mod_funcs = for m <- Map.get(prog, :mods, []), f <- m.funcs, do: f

    Enum.find_value(funcs ++ mod_funcs, :ok, fn f ->
      with :ok <- check_func(f, tdefs, tsets), do: nil
    end)
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
