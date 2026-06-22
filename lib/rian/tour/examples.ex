defmodule Rian.Tour.Examples.Error do
  @moduledoc "Raised by `Rian.Tour.Examples.check!/0` when a by-example file drifts from its header."
  defexception [:message]
end

defmodule Rian.Tour.Examples do
  @moduledoc """
  The gate behind the numbered **"Rian by example"** files (`examples/rian/NN_*.rian`).

  Each file carries a machine-readable header in its leading comments:

    * `#@reach <targets>` — the union of target environments the file's functions
      reach (`ex`/`rs`/`js`/`jvm`). `check!/0` runs the real `Rian.Reach` analysis
      and fails the build if the computed union drifts from the declaration, so the
      portability claims in these teaching files cannot rot.
    * `#@reach-pin name=<targets>` — every function whose reach is *below* the
      file's union must be pinned with its exact reach (e.g. `show=ex` because it
      uses host FFI). This keeps mixed-portability files honest about which
      functions are not fully portable, rather than hiding behind the union.
    * `#@illustrative <reason>` — the file uses surface the `Rian.Decl` front-end
      does not yet accept (`else if`, `@partial`, `extern`, `@wire`). Such files
      are *not* compiled; `check!/0` asserts they genuinely do not parse (so the
      marker cannot outlive the gap) and carry a reason.

  `check!/0` is run by `Rian.TourReachTest` and by `mix rian.tour --check`.
  """

  use Rian.Ann

  alias Rian.{Decl, Reach}
  alias Rian.Tour.Examples.Error

  @dir "examples/rian"

  @doc "The numbered by-example files, sorted."
  @rian_sig "pub def files() Vec(String)"
  @spec files() :: [String.t()]
  def files, do: @dir |> Path.join("[0-9]*.rian") |> Path.wildcard() |> Enum.sort()

  @doc """
  Parse a source's machine-readable header from its leading comments. Returns
  `{:gated, reach, pins}`, `{:illustrative, reason}`, or `:none`.
  """
  @spec header(String.t()) ::
          {:gated, MapSet.t(atom()), %{String.t() => MapSet.t(atom())}}
          | {:illustrative, String.t()}
          | :none
  @rian_sig "pub def header(src String) Any"
  def header(src) do
    lines = src |> String.split("\n") |> Enum.map(&String.trim/1)
    illus = Enum.find(lines, &String.starts_with?(&1, "#@illustrative"))
    reach = Enum.find(lines, &String.starts_with?(&1, "#@reach "))
    pin = Enum.find(lines, &String.starts_with?(&1, "#@reach-pin"))

    cond do
      illus != nil -> {:illustrative, reason(illus)}
      reach != nil -> {:gated, targets(strip(reach, "#@reach")), pins(pin)}
      true -> :none
    end
  end

  @doc """
  Verify every numbered file against its header. Returns `:ok` or raises
  `Rian.Tour.Examples.Error` listing every drift found across the corpus.
  """
  @rian_sig "pub def check!() Symbol"
  @spec check!() :: :ok
  def check! do
    issues =
      Enum.flat_map(files(), fn file ->
        case check_file(file) do
          [] -> []
          msgs -> [{Path.basename(file), msgs}]
        end
      end)

    if issues == [], do: :ok, else: raise(Error, format(issues))
  end

  @doc """
  The list of drift issues for one source string (empty when it honours its
  header). The unit the per-file and corpus checks are built from.
  """
  @rian_sig "pub def issues(src String) Vec(String)"
  @spec issues(String.t()) :: [String.t()]
  def issues(src) do
    case header(src) do
      :none -> ["no `#@reach` or `#@illustrative` header"]
      {:illustrative, reason} -> check_illustrative(src, reason)
      {:gated, reach, pins} -> check_gated(src, reach, pins)
    end
  end

  # ── per-file checks ───────────────────────────────────────────────────────

  defp check_file(file), do: file |> File.read!() |> issues()

  defp check_illustrative(src, reason) do
    reason_issue = if reason == "", do: ["`#@illustrative` needs a reason"], else: []

    case safe_parse(src) do
      {:ok, _} ->
        [
          "marked `#@illustrative` but now parses — promote it to a `#@reach` header"
          | reason_issue
        ]

      :error ->
        reason_issue
    end
  end

  defp check_gated(src, declared, pins) do
    case safe_parse(src) do
      :error ->
        ["declared `#@reach` but no longer parses — fix it or mark it `#@illustrative`"]

      {:ok, prog} ->
        by_name =
          prog
          |> Reach.analyze()
          |> Map.new(fn {key, %{reach: reach}} -> {Reach.bare_name(key), reach} end)

        union = by_name |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)
        reach_issue(declared, union) ++ pin_issues(by_name, union, pins)
    end
  end

  defp reach_issue(declared, union) do
    if MapSet.equal?(declared, union),
      do: [],
      else: ["declares `#@reach #{fmt(declared)}` but the analysis reaches `#{fmt(union)}`"]
  end

  defp pin_issues(by_name, union, pins) do
    below =
      for {name, reach} <- by_name, not MapSet.equal?(reach, union), into: %{}, do: {name, reach}

    missing =
      for name <- Map.keys(below) -- Map.keys(pins),
          do:
            "function `#{name}` reaches `#{fmt(below[name])}`, a subset of the union, " <>
              "but has no `#@reach-pin`"

    unknown =
      for name <- Map.keys(pins),
          not Map.has_key?(by_name, name),
          do: "`#@reach-pin #{name}=…` names no function in the file"

    stale =
      for name <- Map.keys(pins),
          Map.has_key?(by_name, name),
          not Map.has_key?(below, name),
          do:
            "`#@reach-pin #{name}=…` is stale — `#{name}` now reaches the full union `#{fmt(union)}`"

    wrong =
      for name <- Map.keys(pins),
          reach = below[name],
          reach != nil,
          not MapSet.equal?(pins[name], reach),
          do: "`#@reach-pin #{name}=#{fmt(pins[name])}` but `#{name}` reaches `#{fmt(reach)}`"

    missing ++ unknown ++ stale ++ wrong
  end

  # ── header parsing ────────────────────────────────────────────────────────

  defp reason(line),
    do: line |> strip("#@illustrative") |> String.trim_leading("—") |> String.trim()

  defp strip(line, prefix), do: line |> String.replace_prefix(prefix, "") |> String.trim()

  defp pins(nil), do: %{}

  defp pins(line) do
    line
    |> strip("#@reach-pin")
    |> String.split()
    |> Map.new(fn entry ->
      case String.split(entry, "=") do
        [name, set] -> {name, targets(set)}
        _ -> raise Error, "malformed `#@reach-pin` entry #{inspect(entry)} (expected name=t1,t2)"
      end
    end)
  end

  defp targets(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&target/1)
    |> MapSet.new()
  end

  defp target(name) do
    atom = String.to_atom(name)

    if atom in Reach.targets(),
      do: atom,
      else: raise(Error, "unknown target #{inspect(name)}; known: #{inspect(Reach.targets())}")
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp safe_parse(src) do
    {:ok, Decl.parse(src)}
  rescue
    _ -> :error
  end

  defp fmt(set), do: set |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")

  defp format(issues) do
    body =
      Enum.map_join(issues, "\n", fn {file, msgs} ->
        "  #{file}:\n" <> Enum.map_join(msgs, "\n", &"    - #{&1}")
      end)

    "by-example reach gate failed:\n\n#{body}\n\n" <>
      "Run `mix rian.targets examples/rian/<file>` to inspect, then fix the\n" <>
      "`#@reach`/`#@reach-pin` header or the code."
  end
end
