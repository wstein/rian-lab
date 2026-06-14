defmodule Rian.Interp do
  @moduledoc """
  String-interpolation resolution (ADR-0069).

  `Rian.Pratt` parses `"… \\(expr) …"` into a `{:str_interp, parts}` surface node.
  This pass — run in the `Rian.Decl` metaprogramming stage, *with the enclosing
  clause's parameter types in scope* — rewrites each node into a plain `<>`/
  stringify chain *before* the checker and every emitter see it. So there is **no
  new Core node and no per-emitter `{:str_interp}` handling**: the result is an
  ordinary `{:bin, "<>", …}` tree the existing machinery already lowers.

  Each hole is stringified by its **statically inferred type** (interpolation is
  monomorphic per call site, ADR-0069 §4 — so no runtime `Show` dispatch and none
  of the BEAM/JS dispatch-guard collision the ADR flags):

    * `String`            → the value itself (identity)
    * `Int`/`Int*`/`UInt*`→ `__prim_int_to_string(value)` (lowered natively per target)
    * `Bool`              → `if value do "true" else "false" end`

  `Char`/`Float64` (ADR-0069 open items: dispatch collision / round-trip
  divergence) and a hole whose type cannot be inferred are a **compile error at the
  hole** — never a silent `inspect`-style fallback (ADR-0035).
  """
  alias Rian.Check

  @doc "Rewrite every `{:str_interp, …}` in `ast` to a `<>`/stringify chain."
  def resolve(ast, env, ic)

  def resolve({:str_interp, parts}, env, ic) do
    parts
    |> Enum.map(&resolve_part(&1, env, ic))
    |> concat_chain()
  end

  def resolve(ast, env, ic) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&resolve(&1, env, ic)) |> List.to_tuple()

  def resolve(list, env, ic) when is_list(list), do: Enum.map(list, &resolve(&1, env, ic))
  def resolve(other, _env, _ic), do: other

  defp resolve_part({:lit, s}, _env, _ic), do: {:str, s}

  defp resolve_part({:hole, expr}, env, ic) do
    # resolve nested interpolation first, then stringify by the hole's type
    expr = resolve(expr, env, ic)
    stringify(expr, Check.infer(expr, env, ic))
  end

  defp stringify(expr, "String"), do: expr

  defp stringify(expr, "Bool"),
    do: {:if, expr, {:block, [expr: {:str, "true"}]}, {:block, [expr: {:str, "false"}]}}

  defp stringify(expr, type) do
    cond do
      int_type?(type) ->
        {:call, {:id, "__prim_int_to_string"}, [expr]}

      type == "Char" ->
        raise ArgumentError,
              "interpolation of a `Char` is not supported yet (ADR-0069 open item: " <>
                "the Char/Int dispatch-guard collision) — convert explicitly"

      type == "Float64" or type == "Float32" ->
        raise ArgumentError,
              "interpolation of a `Float` is not supported yet (ADR-0069 open item: " <>
                "cross-target round-trip divergence is unspecified)"

      true ->
        raise ArgumentError,
              "no `Show` for `#{type}` — interpolation requires a statically-known, " <>
                "stringifiable type (String / Int* / Bool); got `#{type}`"
    end
  end

  # left-associative `<>` chain over the resolved parts (always ≥ 1 part: a string
  # with holes lexes to interleaved lits + holes, so the list is never empty)
  defp concat_chain([only]), do: only
  defp concat_chain([h | t]), do: Enum.reduce(t, h, fn p, acc -> {:bin, "<>", acc, p} end)

  defp int_type?(t), do: is_binary(t) and Regex.match?(~r/^U?Int\d*$/, t)
end
