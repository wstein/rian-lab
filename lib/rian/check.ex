defmodule Rian.Check do
  @moduledoc """
  Type checking — first increment of ADR-0034 (unification-based inference).

  This is a deliberately **conservative** slice: it infers the type of an
  expression where it can (literals, arithmetic, comparisons, concat, `if`/block
  value) and **only reports an error when it can *prove* a mismatch** — a body
  whose inferred concrete type differs from the function's declared return type.
  Anything it cannot pin down infers to `:unknown` and never rejects, so it can
  be grown toward the full ADR-0034 design (error sets, protocol bounds, flow
  narrowing) without ever rejecting a valid program in the meantime.

  Types here are the Crystal-family primitive names (`Int64`/`Float64`/`String`/
  `Bool`, ADR-0033) plus `:unknown`. `unify/2` is the kernel: equal types unify
  to themselves, `:unknown` unifies with anything, two differing concrete types
  are a `:mismatch`.
  """
  alias Rian.IR.Func
  alias Rian.Pratt

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
  @doc "Infer the type of an expression AST under `env` (name -> type); `:unknown` when unsure."
  def infer(ast, env \\ %{})

  def infer({:num, n}, _env),
    do: if(String.contains?(n, ".") or String.match?(n, ~r/[eE]/), do: "Float64", else: "Int64")

  def infer({:str, _}, _env), do: "String"
  def infer({:id, b}, _env) when b in ~w(true false), do: "Bool"
  def infer({:id, x}, env), do: Map.get(env, x, :unknown)
  def infer({:unary, "-", x}, env), do: infer(x, env)
  def infer({:unary, "not", _}, _env), do: "Bool"

  def infer({:bin, op, l, r}, env) do
    cond do
      op in @bool_ops -> "Bool"
      op == "<>" -> "String"
      op == "/" -> "Float64"
      op in @int_ops -> "Int64"
      op in @arith -> conservative(unify(infer(l, env), infer(r, env)))
      true -> :unknown
    end
  end

  def infer({:if, _c, then_arm, else_arm}, env),
    do: conservative(unify(infer(then_arm, env), infer(else_arm, env)))

  def infer({:block, stmts}, env), do: infer_block(stmts, env, :unknown)
  def infer(_other, _env), do: :unknown

  defp infer_block([], _env, value), do: value

  defp infer_block([{:bind, n, e} | rest], env, _value) do
    t = infer(e, env)
    infer_block(rest, Map.put(env, n, t), t)
  end

  defp infer_block([{:expr, e} | rest], env, _value), do: infer_block(rest, env, infer(e, env))

  # a mismatch deep in arithmetic stays conservative (we do not model coercion
  # fully yet) rather than rejecting; only the body-vs-return check rejects
  defp conservative(:mismatch), do: :unknown
  defp conservative(t), do: t

  # ── function checking ──────────────────────────────────────────────────
  @doc """
  Check one function: each clause body's inferred type must not *contradict* the
  declared return type. Returns `:ok` or `{:error, message}`.
  """
  def check_func(%Func{name: name, params: ps, ret: ret, clauses: clauses}) do
    Enum.find_value(clauses, :ok, fn c ->
      body_t = infer(Pratt.parse_body(c.body), clause_env(c.pats, ps))

      case unify(body_t, ret) do
        :mismatch ->
          {:error,
           "`#{name}`: body has type `#{body_t}` but the declared return type is `#{ret}`"}

        _ ->
          nil
      end
    end)
  end

  # Bind names introduced by the clause head. Only a bare `{:var, name}` pattern
  # carries its parameter's type; a constructor pattern binds field variables
  # whose types we do not yet model -> they stay `:unknown` (conservative).
  defp clause_env(pats, params) do
    pats
    |> Enum.zip(params)
    |> Enum.reduce(%{}, fn
      {{:var, name}, param}, env -> Map.put(env, name, param.type)
      {_pat, _param}, env -> env
    end)
  end

  @doc "Parse source and check every function; returns `:ok` or the first `{:error, message}`."
  def check(src) do
    %{funcs: funcs} = Rian.Decl.parse(src)
    Enum.find_value(funcs, :ok, fn f -> with :ok <- check_func(f), do: nil end)
  end
end
