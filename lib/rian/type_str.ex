defmodule Rian.TypeStr do
  @moduledoc """
  Shared helpers for the **type-string surface** — the textual form of types
  (`Fn(A, B)`, `Map(K, V)`, `Vec(T)`, `Name(A, B)`) that several stages parse.

  Historically each stage carried its own copy of the "split a parenthesised
  argument list on its *top-level* commas" loop — `Rian.Check` (`Fn` unification),
  `Rian.Capability` (Rust generic lowering), `Rian.Protocol` (method params),
  `Rian.JS` and `Rian.Lower` (emitter signatures). Five copies drifted (some
  rejected empty components, some did not), which is exactly how a latent bug
  hides. This module is the single source of truth.
  """

  @doc """
  Split `s` on its **top-level commas only**, so nested generics stay intact:

      iex> Rian.TypeStr.split_top_commas("String, Vec(Int64)")
      ["String", "Vec(Int64)"]
      iex> Rian.TypeStr.split_top_commas("Map(K, V), Bool")
      ["Map(K, V)", "Bool"]

  Each component is trimmed; empty components (and `""`) are dropped, so a
  trailing comma or an empty argument list yields no spurious `""` entries.
  """
  @spec split_top_commas(String.t()) :: [String.t()]
  def split_top_commas(""), do: []

  def split_top_commas(s) do
    {parts, cur, _depth} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ",", {parts, cur, 0} -> {[cur | parts], "", 0}
        "(", {parts, cur, d} -> {parts, cur <> "(", d + 1}
        ")", {parts, cur, d} -> {parts, cur <> ")", d - 1}
        ch, {parts, cur, d} -> {parts, cur <> ch, d}
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end
