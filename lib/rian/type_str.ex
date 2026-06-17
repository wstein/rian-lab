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
    s
    |> top_comma_cuts()
    |> slice(s)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Byte positions of the depth-0 commas. The Rian lexer (not a hand-rolled
  # char loop) decides nesting: each `{:comma}` token at paren depth 0 is mapped
  # back to its comma *character* — the Nth comma token is the Nth `,` byte,
  # since a type string carries no string/char literal that could hide a comma —
  # so the components are sliced verbatim from the source and keep their exact
  # spelling (a token-reconstruction would normalize `Map(K,V)` → `Map(K, V)`).
  defp top_comma_cuts(s) do
    top = top_comma_ordinals(Rian.Lexer.expr_tokens(s))
    commas = :binary.matches(s, ",") |> Enum.map(&elem(&1, 0))
    Enum.map(top, &Enum.at(commas, &1))
  end

  # 0-based ordinal (among all commas) of each comma token sitting at paren
  # depth 0. Only `(`/`)` nest — brackets/braces are content, as before.
  defp top_comma_ordinals(tokens) do
    {ords, _i, _d} =
      Enum.reduce(tokens, {[], 0, 0}, fn
        {:comma}, {ords, i, 0} -> {[i | ords], i + 1, 0}
        {:comma}, {ords, i, d} -> {ords, i + 1, d}
        {:lparen}, {ords, i, d} -> {ords, i, d + 1}
        {:rparen}, {ords, i, d} -> {ords, i, d - 1}
        _tok, {ords, i, d} -> {ords, i, d}
      end)

    Enum.reverse(ords)
  end

  # cut `s` into pieces at the given comma byte positions (the commas themselves
  # are dropped).
  defp slice(cuts, s) do
    {pieces, last} =
      Enum.reduce(cuts, {[], 0}, fn pos, {acc, start} ->
        {[binary_part(s, start, pos - start) | acc], pos + 1}
      end)

    Enum.reverse([binary_part(s, last, byte_size(s) - last) | pieces])
  end
end
