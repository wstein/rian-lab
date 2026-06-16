defmodule Rian.LSP.Formatting do
  @moduledoc """
  The formatting half of the (future) language server (ADR-0038), as a **data-only**
  API — no transport, no GenLSP. It turns `Rian.Format` into the `TextEdit[]` an LSP
  client expects, for both `textDocument/formatting` (whole document) and
  `textDocument/rangeFormatting` (a selection).

  A `TextEdit` is a plain map matching the LSP shape (0-based lines/characters):

      %{range: %{start: %{line: l, character: c}, end: %{line: l, character: c}},
        new_text: "…"}

  Edits are **line-granular**: each is a replacement of a run of whole lines. We
  produce the minimal set of such hunks via Elixir's Myers line diff between the
  source and `Rian.Format.format/1`'s output, so applying them yields exactly the
  formatted document. (`apply_edits/2` does that and is the test oracle.)

  ## Range formatting

  `range_formatting/3` formats **only the selected lines**, as a fragment: the slice
  is run through `Rian.Format` on its own (the formatter ignores leading whitespace
  and re-derives indentation from level 0), then every output line is re-prefixed
  with the selection's base indentation, and a single replacement edit is returned.
  The rest of the buffer is untouched. Character offsets are ignored — selection is
  rounded out to whole lines (the natural granularity). It works best on selections
  that are complete declarations or statements; a selection cut across a `do…end`
  boundary still produces valid output but may indent oddly.
  """

  alias Rian.Format

  @doc "Edits to format the whole document (empty list if already formatted)."
  def formatting(text) when is_binary(text) do
    hunks(text, Format.format(text))
  end

  @doc """
  Edits to format the lines in `[start_line, end_line]` (0-based, inclusive), as a
  fragment. Returns a single line-replacement edit, or `[]` if already formatted.
  """
  def range_formatting(text, start_line, end_line)
      when is_integer(start_line) and is_integer(end_line) do
    lines = String.split(text, "\n")
    last = max(length(lines) - 1, 0)
    s = clamp(start_line, 0, last)
    e = clamp(end_line, s, last)

    selected = Enum.slice(lines, s..e//1)
    base = base_indent(selected)
    formatted = Format.format(Enum.join(selected, "\n") <> "\n")

    new_lines =
      formatted
      |> String.trim_trailing("\n")
      |> String.split("\n")
      |> Enum.map(fn
        "" -> ""
        line -> base <> line
      end)

    if new_lines == selected do
      []
    else
      [
        %{
          range: %{start: %{line: s, character: 0}, end: %{line: e + 1, character: 0}},
          new_text: Enum.map_join(new_lines, "", &(&1 <> "\n"))
        }
      ]
    end
  end

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)

  # the leading-whitespace string of the first non-blank selected line
  defp base_indent(lines) do
    lines
    |> Enum.find("", &(String.trim(&1) != ""))
    |> then(fn line -> String.slice(line, 0, leading_spaces(line)) end)
  end

  defp leading_spaces(line), do: String.length(line) - String.length(String.trim_leading(line))

  @doc "Apply line-granular `edits` to `text` (right-to-left). The test oracle."
  def apply_edits(text, edits) do
    lines = String.split(text, "\n")

    edits
    |> Enum.sort_by(& &1.range.start.line, :desc)
    |> Enum.reduce(lines, fn e, acc ->
      a = e.range.start.line
      b = e.range.end.line

      ins =
        if e.new_text == "",
          do: [],
          else: e.new_text |> String.trim_trailing("\n") |> String.split("\n")

      Enum.slice(acc, 0, a) ++ ins ++ Enum.slice(acc, b..-1//1)
    end)
    |> Enum.join("\n")
  end

  # ── diff → line-replacement hunks ─────────────────────────────────────────
  defp hunks(old, new) when old == new, do: []

  defp hunks(old, new) do
    String.split(old, "\n")
    |> List.myers_difference(String.split(new, "\n"))
    |> to_hunks()
    |> Enum.map(&edit/1)
  end

  # group the Myers diff into change hunks: a maximal run of del/ins between `eq`s,
  # each replacing `del` old lines starting at `old_start` with the `ins` lines.
  defp to_hunks(diff) do
    {_old, acc, cur} =
      Enum.reduce(diff, {0, [], nil}, fn
        {:eq, ls}, {old, acc, cur} -> {old + length(ls), flush(cur, acc), nil}
        {:del, ls}, {old, acc, cur} -> {old + length(ls), acc, bump_del(cur, old, length(ls))}
        {:ins, ls}, {old, acc, cur} -> {old, acc, bump_ins(cur, old, ls)}
      end)

    Enum.reverse(flush(cur, acc))
  end

  defp start_hunk(old), do: %{old_start: old, del: 0, ins: []}

  defp bump_del(cur, old, n),
    do: %{(cur || start_hunk(old)) | del: (cur || start_hunk(old)).del + n}

  defp bump_ins(cur, old, ls),
    do: %{(cur || start_hunk(old)) | ins: (cur || start_hunk(old)).ins ++ ls}

  defp flush(nil, acc), do: acc
  defp flush(cur, acc), do: [cur | acc]

  defp edit(%{old_start: a, del: del, ins: ins}) do
    %{
      range: %{
        start: %{line: a, character: 0},
        end: %{line: a + del, character: 0}
      },
      new_text: Enum.map_join(ins, "", &(&1 <> "\n"))
    }
  end
end
