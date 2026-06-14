defmodule AdrCorpusTest do
  @moduledoc """
  Corpus-consistency gate for the ADRs (ADR-0000 §5, corpus-review consensus #1).

  The ADRs are the design source of truth, so they must at least be internally
  honest: every ADR carries a Status from the taxonomy and an `Implemented:`
  line, and every `ADR-NNNN` cross-reference resolves to a real file. This is
  the check that would have caught the dangling `ADR-0025` reference.
  """
  use ExUnit.Case, async: true

  @adr_dir Path.join([File.cwd!(), "docs", "adr"])
  @files Path.wildcard(Path.join(@adr_dir, "*.md"))

  # the taxonomy ADR-0000 §5 defines; a Status line (markdown emphasis stripped)
  # must begin with one of these
  @statuses ["Proposed", "Accepted", "Implemented", "Superseded"]

  # This corpus is the 0026+ slice; ADRs 0001–0025 are pre-corpus foundational
  # decisions intentionally not maintained as files here (ADR-0000 §5). A
  # reference into that range is legacy-by-design, not a dangling typo — only
  # references to the maintained corpus (>= 0026) must resolve.
  @corpus_floor 26

  defp number(path), do: path |> Path.basename() |> String.slice(0, 4)
  defp exists?(num), do: Path.wildcard(Path.join(@adr_dir, "#{num}-*.md")) != []

  test "the corpus is non-empty (sanity)" do
    assert length(@files) > 30, "expected the ADR corpus, found #{length(@files)} files"
  end

  test "every ADR has a Status from the ADR-0000 taxonomy" do
    bad =
      for path <- @files,
          line = first_status_line(path),
          not (line && String.starts_with?(strip_emphasis(line), @statuses)),
          do: {number(path), line}

    assert bad == [], "ADRs with a missing/unknown Status (see ADR-0000 §5): #{inspect(bad)}"
  end

  test "every `ADR-NNNN` cross-reference resolves to a real ADR file" do
    dangling =
      for path <- @files,
          ref <- Regex.scan(~r/ADR-(\d{4})/, File.read!(path), capture: :all_but_first),
          num = hd(ref),
          String.to_integer(num) >= @corpus_floor,
          not exists?(num),
          do: {number(path), "ADR-#{num}"}

    assert Enum.uniq(dangling) == [],
           "dangling ADR references in the maintained corpus (>= #{@corpus_floor}): #{inspect(Enum.uniq(dangling))}"
  end

  test "every ADR carries an `Implemented:` indicator (ADR-0000 §5 shipped-ness)" do
    missing =
      for path <- @files,
          not String.contains?(File.read!(path), "Implemented:"),
          do: number(path)

    assert missing == [],
           "ADRs missing an `Implemented:` line (add one per ADR-0000 §5): #{inspect(missing)}"
  end

  # drop leading markdown emphasis/strikethrough so a `**Proposed (draft)**` or a
  # `~~Accepted~~ Superseded` status still matches the taxonomy
  defp strip_emphasis(s), do: String.replace(s, ~r/^[*~\s]+/, "")

  defp first_status_line(path) do
    File.read!(path)
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, "**Status:**"))
    |> case do
      nil -> nil
      line -> line |> String.replace("**Status:**", "") |> String.trim()
    end
  end
end
