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
    * `Char`              → `__prim_char_to_string(value)` (the codepoint's single
                            character; byte-identical per target — the static type
                            means no runtime Char/Int dispatch, ADR-0069 §6)

  `Float64` (ADR-0069 open item: cross-target round-trip divergence, §6) and a hole
  whose type cannot be inferred are a **compile error at the hole** — never a silent
  `inspect`-style fallback (ADR-0035).
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
        # the hole's type is known statically here, so there is no runtime Char/Int
        # dispatch (ADR-0069 §6) — emit the codepoint→string prim directly. A Char's
        # single-character string is byte-identical on every target.
        {:call, {:id, "__prim_char_to_string"}, [expr]}

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

  # join the resolved parts into one string. Empty string *literals* (the lexer
  # emits a trailing `{:lit, ""}`, and adjacent holes leave `""` between them) are
  # dropped — they are identity for concatenation and only clutter the output.
  # ≥2 parts lower to a single-shot `__prim_str_concat_all` (one allocation: a
  # single BEAM binary / `format!` on Rust) rather than a left-nested `<>` cascade
  # that builds N−1 intermediates (ADR-0069 §6). One part is the value itself.
  defp concat_chain(parts) do
    case Enum.reject(parts, &match?({:str, ""}, &1)) do
      [] -> {:str, ""}
      [only] -> only
      many -> {:call, {:id, "__prim_str_concat_all"}, many}
    end
  end

  defp int_type?(t), do: is_binary(t) and Regex.match?(~r/^U?Int\d*$/, t)
end
