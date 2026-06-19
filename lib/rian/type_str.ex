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
  use Rian.Ann

  @doc """
  Split `s` on its **top-level commas only**, so nested generics stay intact:

      iex> Rian.TypeStr.split_top_commas("String, Vec(Int64)")
      ["String", "Vec(Int64)"]
      iex> Rian.TypeStr.split_top_commas("Map(K, V), Bool")
      ["Map(K, V)", "Bool"]

  Each component is trimmed; empty components (and `""`) are dropped, so a
  trailing comma or an empty argument list yields no spurious `""` entries.
  """
  @rian_sig "pub def split_top_commas(s String) Vec(String)"
  @spec split_top_commas(String.t()) :: [String.t()]
  def split_top_commas(""), do: []

  def split_top_commas(s) do
    s
    |> top_comma_cuts()
    |> slice(s)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Canonicalize a type-reference string. If it carries a **top-level `|`**, rewrite
  it to the canonical **value-union** form `Union(m1, m2, …)` (ADR-0083) — members
  **flattened** (a nested `Union(…)`/`|` is spliced in), **de-duplicated**, and
  **sorted**, so `B | A` and `A | B | A` both canonicalize to `Union(A, B)`. A type
  with no top-level `|` is returned trimmed and otherwise unchanged.

      iex> Rian.TypeStr.normalize("Int53 | String")
      "Union(Int53, String)"
      iex> Rian.TypeStr.normalize("B | A | B")
      "Union(A, B)"
      iex> Rian.TypeStr.normalize("Vec(Int53)")
      "Vec(Int53)"
  """
  @rian_sig "pub def normalize(t String) String"
  @spec normalize(String.t()) :: String.t()
  def normalize(t) do
    case split_top_pipes(t) do
      [single] ->
        String.trim(single)

      members ->
        inner =
          members
          |> Enum.flat_map(&union_members/1)
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.join(", ")

        "Union(" <> inner <> ")"
    end
  end

  @doc """
  Split `s` on its **top-level `|` only** (paren-aware), so a union member that is
  itself parametric (`Vec(Int) | Str`) stays intact. Each component is trimmed;
  empty components are dropped. Type strings carry no string/char literal that
  could hide a `|`, so a paren-depth counter is exact.
  """
  @rian_sig "pub def split_top_pipes(s String) Vec(String)"
  @spec split_top_pipes(String.t()) :: [String.t()]
  def split_top_pipes(s) do
    {parts, cur, _depth} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        "(", {parts, cur, d} -> {parts, cur <> "(", d + 1}
        ")", {parts, cur, d} -> {parts, cur <> ")", d - 1}
        "|", {parts, cur, 0} -> {[cur | parts], "", 0}
        ch, {parts, cur, d} -> {parts, cur <> ch, d}
      end)

    [cur | parts]
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # the members of a single union component, flattening a nested `Union(…)` or a
  # parenthesised group `(A | B)`. Drops exactly the ONE wrapping `)` (not every
  # trailing one — `Union(Vec(Int))` must keep `Vec(Int)`'s close paren).
  @spec union_members(String.t()) :: [String.t()]
  defp union_members("Union(" <> rest) do
    rest |> drop_close() |> split_top_commas() |> Enum.flat_map(&union_members/1)
  end

  defp union_members("(" <> rest = m) do
    if String.ends_with?(m, ")"),
      do: rest |> drop_close() |> split_top_pipes() |> Enum.flat_map(&union_members/1),
      else: [m]
  end

  defp union_members(m), do: [String.trim(m)]

  @spec drop_close(String.t()) :: String.t()
  defp drop_close(rest), do: binary_part(rest, 0, byte_size(rest) - 1)

  # Byte positions of the depth-0 commas. The Rian lexer (not a hand-rolled
  # char loop) decides nesting: each `{:comma}` token at paren depth 0 is mapped
  # back to its comma *character* — the Nth comma token is the Nth `,` byte,
  # since a type string carries no string/char literal that could hide a comma —
  # so the components are sliced verbatim from the source and keep their exact
  # spelling (a token-reconstruction would normalize `Map(K,V)` → `Map(K, V)`).
  @spec top_comma_cuts(String.t()) :: [non_neg_integer()]
  defp top_comma_cuts(s) do
    top = top_comma_ordinals(Rian.Lexer.expr_tokens(s))
    commas = :binary.matches(s, ",") |> Enum.map(&elem(&1, 0))
    Enum.map(top, &Enum.at(commas, &1))
  end

  # 0-based ordinal (among all commas) of each comma token sitting at paren
  # depth 0. Only `(`/`)` nest — brackets/braces are content, as before.
  @spec top_comma_ordinals([tuple()]) :: [non_neg_integer()]
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
  @spec slice([non_neg_integer()], String.t()) :: [String.t()]
  defp slice(cuts, s) do
    {pieces, last} =
      Enum.reduce(cuts, {[], 0}, fn pos, {acc, start} ->
        {[binary_part(s, start, pos - start) | acc], pos + 1}
      end)

    Enum.reverse([binary_part(s, last, byte_size(s) - last) | pieces])
  end
end
