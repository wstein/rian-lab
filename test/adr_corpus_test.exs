defmodule AdrCorpusTest do
  @moduledoc """
  Corpus-consistency gate for the ADRs (ADR-0000 §5, corpus-review consensus #1).

  The ADRs are the design source of truth, so they must at least be internally
  honest: every ADR carries a Status from the taxonomy and an `Implemented:`
  line, and every `ADR-NNNN` cross-reference resolves to a real file. This is
  the check that would have caught the dangling `ADR-0025` reference.

  Beyond structure, a **claims-vs-reality** gate (corpus-review consensus #3) links
  a curated set of concrete safety *claims* to the tests that enforce them: each
  claim's anchor phrase must still be present in its ADR, and each linked test file
  must still exist. It fails the build if a claim is edited away or its enforcing
  test deleted — turning a silent doc/code drift into a red test.
  """
  use ExUnit.Case, async: true

  @adr_dir Path.join([File.cwd!(), "docs", "adr"])
  @files Path.wildcard(Path.join(@adr_dir, "*.md"))

  # Curated claim -> enforcing-test links (consensus #3). Each entry: an ADR, a short
  # verbatim *anchor* phrase that must remain in that ADR, and the test file(s) that
  # enforce the claim. Anchors are deliberately short and structural so an innocuous
  # reword is unlikely to break them, but deleting the claim outright does.
  @claims [
    %{adr: "0064", claim: "fixed-width literal range-check", tests: ["test/rian/check_test.exs"]},
    %{adr: "0067", claim: "erased to base", tests: ["test/rian/opaque_test.exs"]},
    %{adr: "0043", claim: "nominally distinct", tests: ["test/rian/opaque_test.exs"]},
    %{adr: "0041", claim: "Reach is honest about atoms", tests: ["test/rian/reach_test.exs"]},
    %{adr: "0065", claim: "clean compile error", tests: ["test/rian/check_test.exs"]},
    %{adr: "0036", claim: "RangeError", tests: ["test/rian/range_test.exs"]}
  ]

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

  test "every curated safety claim is present in its ADR and backed by an existing test (consensus #3)" do
    problems =
      Enum.flat_map(@claims, fn %{adr: adr, claim: claim, tests: tests} ->
        adr_path = Path.wildcard(Path.join(@adr_dir, "#{adr}-*.md")) |> List.first()

        adr_problem =
          cond do
            adr_path == nil ->
              ["ADR-#{adr}: no such ADR file"]

            not String.contains?(File.read!(adr_path), claim) ->
              ["ADR-#{adr}: claim phrase gone: #{inspect(claim)}"]

            true ->
              []
          end

        test_problems =
          for t <- tests,
              not File.exists?(Path.join(File.cwd!(), t)),
              do: "ADR-#{adr}: enforcing test missing: #{t}"

        adr_problem ++ test_problems
      end)

    assert problems == [],
           "ADR claim<->test linkage broken (consensus #3):\n  " <> Enum.join(problems, "\n  ")
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
