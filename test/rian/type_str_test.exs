defmodule Rian.TypeStrTest do
  use ExUnit.Case, async: true
  doctest Rian.TypeStr

  alias Rian.TypeStr

  describe "split_top_commas/1 — top-level (paren-depth-0) comma split" do
    test "nested generics stay intact" do
      assert TypeStr.split_top_commas("Map(K, V), Bool") == ["Map(K, V)", "Bool"]

      assert TypeStr.split_top_commas("Dict(String, Vec(Int64)), T") == [
               "Dict(String, Vec(Int64))",
               "T"
             ]
    end

    test "components are trimmed and empties dropped (trailing comma, blanks)" do
      assert TypeStr.split_top_commas("A, B,") == ["A", "B"]
      assert TypeStr.split_top_commas("") == []
      assert TypeStr.split_top_commas("   ") == []
    end

    test "exact source spelling is preserved — no spacing normalization" do
      # a lexer that reconstructed from tokens would canonicalize `K,V` → `K, V`;
      # slicing the original keeps it verbatim.
      assert TypeStr.split_top_commas("Map(K,V)") == ["Map(K,V)"]
      assert TypeStr.split_top_commas("a,b ,c") == ["a", "b", "c"]
    end
  end

  describe "lexer-driven split is equivalent to the reference char-scanner" do
    # The historical hand-rolled implementation, kept here as the differential
    # oracle: the lexer-based `split_top_commas` must agree with it byte-for-byte.
    defp ref(""), do: []

    defp ref(s) do
      {parts, cur, _d} =
        s
        |> String.graphemes()
        |> Enum.reduce({[], "", 0}, fn
          ",", {p, c, 0} -> {[c | p], "", 0}
          "(", {p, c, d} -> {p, c <> "(", d + 1}
          ")", {p, c, d} -> {p, c <> ")", d - 1}
          ch, {p, c, d} -> {p, c <> ch, d}
        end)

      [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

    test "agrees with the reference over a corpus of real and edge-case type strings" do
      from_sources =
        (Path.wildcard("examples/rian/*.rian") ++ Path.wildcard("compiler/*.rian"))
        |> Enum.flat_map(&Regex.scan(~r/\(([A-Za-z_][A-Za-z0-9_, ()|]*)\)/, File.read!(&1)))
        |> Enum.map(fn [_, inner] -> inner end)

      edge = [
        "Map(K,V)",
        "A,B",
        "A, B,",
        "",
        "  ",
        "T | E",
        "Dict(String, Vec(Int64))",
        "Fn(A, B)",
        "Option(T)",
        "a,b ,c",
        "Map( K , V )"
      ]

      for s <- Enum.uniq(from_sources ++ edge) do
        assert TypeStr.split_top_commas(s) == ref(s), "diverged on #{inspect(s)}"
      end
    end
  end
end
