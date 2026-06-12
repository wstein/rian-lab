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
  `:unknown`. Error sets (pillar 2) and protocol bounds (pillar 3) await their
  surface (`Result`/error tags, protocols); their runtime substrate already
  exists as sum types checked by the exhaustiveness gate.

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
  Check one function: each clause body's inferred type must not *contradict* the
  declared return type. `tdefs` enables flow narrowing. Returns `:ok` or
  `{:error, message}`.
  """
  def check_func(func, tdefs \\ %{})

  def check_func(%Func{name: name, params: ps, ret: ret, clauses: clauses}, tdefs) do
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
    tdefs = type_table(prog)
    mod_funcs = for m <- Map.get(prog, :mods, []), f <- m.funcs, do: f

    Enum.find_value(funcs ++ mod_funcs, :ok, fn f ->
      with :ok <- check_func(f, tdefs), do: nil
    end)
  end

  # Constructor table for flow narrowing: every sum-type variant (top-level and
  # inside modules) mapped to its ordered field types.
  defp type_table(prog) do
    types = Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)

    for t <- types, v <- t.variants, into: %{} do
      {v.ctor, Enum.map(v.fields, & &1.type)}
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
