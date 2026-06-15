defmodule Rian.Interp do
  @moduledoc """
  String-interpolation resolution (ADR-0069).

  `Rian.Pratt` parses `"… ${expr} …"` into a `{:str_interp, parts}` surface node.
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
    * `Float64`           → `Show.float(value)` — the portable ECMAScript
                            `Number::toString` formatter (examples/rian/stdlib_show.rian),
                            **auto-injected** into the program when first interpolated
                            (`Rian.Decl.inject_stdlib/1`), so it needs no explicit
                            import. Reaches all four targets, byte-identical on
                            `:ex`/`:rs`/`:js` and on `:jvm` except the tiniest denormal
                            extremes (a `Double.toString` spec quirk, ADR-0069 §6).
    * a **user type `T`**  with an `impl Show for T` → `show(value)`: the program's
                            `Show` dispatcher routes it to the impl (ADR-0069 §6, user
                            `Show`). The hole's static type fixes `T`, so this is still
                            monomorphic. Reaches as far as the impl does — a sum-dispatch
                            consumer is `[:ex, :js]` (the constructor-tag atom pins off
                            `:rs`/`:jvm`), honestly via `Rian.Reach`.

  `Float32`, a user type with **no** `impl Show`, and a hole whose type cannot be
  inferred are a **compile error at the hole** — never a silent `inspect`-style
  fallback (ADR-0035). (`Float32` has no portable formatter; widen to `Float64` and
  interpolate that.) NB: a field-access hole (`${p.x}`) over a pattern/field-bound
  value still infers `:unknown` — interpolate the **whole** value (`${p}`, routed
  through its `Show`) or build the string with explicit calls.
  """
  alias Rian.Check

  @doc """
  Rewrite every `{:str_interp, …}` in `ast` to a `<>`/stringify chain.

  `show` is the set of type names with an `impl Show for T` in the program — a hole
  of such a type lowers to `show(value)` (the protocol dispatcher routes it to the
  impl; ADR-0069 §6, user `Show`). It is statically resolved, so still monomorphic.
  """
  def resolve(ast, env, ic, show \\ MapSet.new())

  def resolve({:str_interp, parts}, env, ic, show) do
    parts
    |> Enum.map(&resolve_part(&1, env, ic, show))
    |> concat_chain()
  end

  def resolve(ast, env, ic, show) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&resolve(&1, env, ic, show)) |> List.to_tuple()

  def resolve(list, env, ic, show) when is_list(list),
    do: Enum.map(list, &resolve(&1, env, ic, show))

  def resolve(other, _env, _ic, _show), do: other

  defp resolve_part({:lit, s}, _env, _ic, _show), do: {:str, s}

  defp resolve_part({:hole, expr}, env, ic, show) do
    # resolve nested interpolation first, then stringify by the hole's type
    expr = resolve(expr, env, ic, show)
    stringify(expr, Check.infer(expr, env, ic), show)
  end

  defp stringify(expr, "String", _show), do: expr

  defp stringify(expr, "Bool", _show),
    do: {:if, expr, {:block, [expr: {:str, "true"}]}, {:block, [expr: {:str, "false"}]}}

  defp stringify(expr, type, show) do
    cond do
      int_type?(type) ->
        {:call, {:id, "__prim_int_to_string"}, [expr]}

      type == "Char" ->
        # the hole's type is known statically here, so there is no runtime Char/Int
        # dispatch (ADR-0069 §6) — emit the codepoint→string prim directly. A Char's
        # single-character string is byte-identical on every target.
        {:call, {:id, "__prim_char_to_string"}, [expr]}

      type == "Float64" ->
        # the canonical portable ECMAScript formatter (`Show.float`, ADR-0069 §6).
        # The flag asks `Rian.Decl.parse` to inject the `Show` stdlib module so the
        # call resolves without the program importing it (prelude-function injection).
        Process.put(:rian_needs_show_float, true)
        {:call, {:dot, {:id, "Show"}, "float"}, [expr]}

      type == "Float32" ->
        raise ArgumentError,
              "interpolation of a `Float32` is not supported — widen to `Float64` and " <>
                "interpolate that (`Show.float` is the portable Float64 formatter, ADR-0069)"

      MapSet.member?(show, type) ->
        # a user type with an `impl Show for T` (ADR-0069 §6, user `Show`): call the
        # protocol method `show/1`. The hole's static type fixes T, so this stays
        # monomorphic — the program's `Show` dispatcher routes it to T's impl.
        {:call, {:id, "show"}, [expr]}

      true ->
        raise ArgumentError,
              "no `Show` for `#{type}` — interpolation requires a statically-known " <>
                "stringifiable type (String / Int* / Bool / Float64, or a type with an " <>
                "`impl Show`); got `#{type}`"
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
