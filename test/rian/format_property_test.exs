defmodule Rian.FormatPropertyTest do
  @moduledoc """
  Property + fuzz tests for the formatter. Dependency-free: a seeded `:rand`
  generator (so any failure reproduces) drives hundreds of random programs through
  the formatter and checks the invariants that *must* hold for every input —
  idempotence and significant-token equivalence — and that `format/1` never raises
  on arbitrary bytes.
  """
  use ExUnit.Case, async: false

  alias Rian.Format
  alias Rian.Lexer

  @seed {0x1234, 0x5678, 0x9ABC}

  # ── the significant-token oracle (same as FormatTest) ─────────────────────
  @open [{:lparen}, {:lbracket}, {:lbrace}, {:mapopen}]
  @close [{:rparen}, {:rbracket}, {:rbrace}]

  defp sig(src) do
    src
    |> Lexer.tokenize_trivia()
    |> Enum.reject(&match?({:comment, _}, &1))
    |> Enum.map(fn
      {:heredoc, c} -> {:str, String.trim(c)}
      t -> t
    end)
    |> drop_bracket_nl(0, [])
    |> collapse_nl([])
    |> strip_tc()
  end

  defp drop_bracket_nl([], _d, acc), do: Enum.reverse(acc)
  defp drop_bracket_nl([t | r], d, acc) when t in @open, do: drop_bracket_nl(r, d + 1, [t | acc])

  defp drop_bracket_nl([t | r], d, acc) when t in @close,
    do: drop_bracket_nl(r, max(0, d - 1), [t | acc])

  defp drop_bracket_nl([{:nl} | r], d, acc) when d > 0, do: drop_bracket_nl(r, d, acc)
  defp drop_bracket_nl([t | r], d, acc), do: drop_bracket_nl(r, d, [t | acc])

  defp collapse_nl([], acc), do: Enum.reverse(acc)
  defp collapse_nl([{:nl}, {:nl} | r], acc), do: collapse_nl([{:nl} | r], acc)
  defp collapse_nl([t | r], acc), do: collapse_nl(r, [t | acc])

  defp strip_tc([{:comma}, c | r]) when c in @close, do: [c | strip_tc(r)]
  defp strip_tc([t | r]), do: [t | strip_tc(r)]
  defp strip_tc([]), do: []

  # ── a random Rian program generator (seeded) ──────────────────────────────
  defp ident do
    len = 1 + :rand.uniform(14)
    first = <<Enum.random(?a..?z)>>

    first <>
      for _ <- 1..len, into: "", do: <<Enum.random(~c"abcdefghijklmnopqrstuvwxyz_0123456789")>>
  end

  defp leaf do
    case :rand.uniform(4) do
      1 -> ident()
      2 -> Integer.to_string(:rand.uniform(99_999))
      3 -> ":" <> ident()
      4 -> "\"" <> ident() <> "\""
    end
  end

  defp args(depth) do
    1..(1 + :rand.uniform(5))
    |> Enum.map_join(", ", fn _ -> expr(depth - 1) end)
  end

  defp expr(depth) when depth <= 0, do: leaf()

  defp expr(depth) do
    case :rand.uniform(6) do
      1 -> leaf()
      2 -> leaf()
      3 -> ident() <> "(" <> args(depth) <> ")"
      4 -> "[" <> args(depth) <> "]"
      5 -> "%{" <> kvs(depth) <> "}"
      6 -> expr(depth - 1) <> " + " <> expr(depth - 1)
    end
  end

  defp kvs(depth) do
    1..(1 + :rand.uniform(3))
    |> Enum.map_join(", ", fn _ -> ident() <> ": " <> expr(depth - 1) end)
  end

  defp program do
    n = 1 + :rand.uniform(5)

    1..n
    |> Enum.map_join("\n", fn _ -> "def #{ident()}() := #{expr(3)}" end)
    |> Kernel.<>("\n")
  end

  describe "properties over random programs" do
    test "format is idempotent and meaning-preserving for 400 random programs" do
      :rand.seed(:exsss, @seed)

      for _ <- 1..400 do
        src = program()
        once = Format.format(src)
        # idempotence
        assert Format.format(once) == once, "not idempotent for:\n#{src}\n→\n#{once}"
        # meaning preserved (significant tokens unchanged)
        assert sig(once) == sig(src), "meaning changed for:\n#{src}\n→\n#{once}"
      end
    end

    test "no formatted line exceeds 98 columns for wrappable random programs" do
      :rand.seed(:exsss, @seed)

      for _ <- 1..200 do
        out = Format.format(program())

        long =
          out
          |> String.split("\n")
          # ignore unbreakable atoms: lines that are a single token with no comma/space to break on
          |> Enum.filter(&(String.length(&1) > 98 and String.contains?(&1, ", ")))

        assert long == [], "over-budget breakable line(s):\n#{Enum.join(long, "\n")}"
      end
    end
  end

  describe "fuzz: format/1 is total" do
    test "never raises on random byte strings" do
      :rand.seed(:exsss, @seed)

      for _ <- 1..1000 do
        bytes = for _ <- 1..:rand.uniform(60), into: "", do: <<:rand.uniform(126)>>

        assert is_binary(Format.format(bytes)), "raised on: #{inspect(bytes)}"
      end
    end

    test "never raises on random Rian-token soup" do
      :rand.seed(:exsss, @seed)

      pieces =
        ["def", "(", ")", "[", "]", "{", "}", "%{", ",", ";", ":=", "->", "|", "end"] ++
          ["do", "case", "if", "else", "x", "1", "\"s\"", "# c", "\n"]

      for _ <- 1..1000 do
        src = for _ <- 1..:rand.uniform(40), into: "", do: Enum.random(pieces) <> " "
        assert is_binary(Format.format(src))
      end
    end
  end
end
