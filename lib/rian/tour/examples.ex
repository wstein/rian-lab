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
      portability claims in these teaching files cannot rot. Because reach is an
      over-approximation (it does not run the full `Check`), `check!/0` *also* runs
      the real emitter for every target in the file's **floor** (the targets every
      function reaches) and fails if it raises — so a claimed target the compiler
      cannot actually produce is caught (ADR-0091).
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

  alias Rian.{Decl, Doctest, JS, JVM, Lower, Reach}
  alias Rian.Tour.Examples.Error

  @dir "examples/rian"
  @pane_dir "examples/rian/panes"
  @pane_max_lines 15

  @doc "The numbered by-example files, sorted."
  @rian_sig "pub def files() Vec(String)"
  @spec files() :: [String.t()]
  def files, do: @dir |> Path.join("[0-9]*.rian") |> Path.wildcard() |> Enum.sort()

  @doc "The `#@pane` source files (the minimal site-pane snippets), sorted."
  @rian_sig "pub def pane_files() Vec(String)"
  @spec pane_files() :: [String.t()]
  def pane_files, do: @pane_dir |> Path.join("*.rian") |> Path.wildcard() |> Enum.sort()

  @doc "The Rian source of pane `id`, with the `#@pane` tag line stripped."
  @rian_sig "pub def pane_source(id String) String"
  @spec pane_source(String.t()) :: String.t()
  def pane_source(id) do
    @pane_dir
    |> Path.join("#{id}.rian")
    |> File.read!()
    |> strip_pane_tag()
  end

  @doc """
  Verify the `#@pane` files stay minimal teaching panes: tagged, at most
  #{@pane_max_lines} lines, and emittable to **all four** targets (a pane is shown
  in every language, so it must reach every one). Raises on any violation.
  """
  @rian_sig "pub def check_panes!() Symbol"
  @spec check_panes!() :: :ok
  def check_panes! do
    issues =
      Enum.flat_map(pane_files(), fn file ->
        case check_pane(file) do
          [] -> []
          msgs -> [{Path.basename(file), msgs}]
        end
      end)

    if issues == [], do: :ok, else: raise(Error, format(issues))
  end

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
  The whole corpus as JSON-shaped data (string keys) for `tour.json`: each file's
  title, kind, and — for gated files — its declared `reach`, `pins`, the honest
  per-function `reachByFn` matrix, and its extracted `doctests`. This is what
  makes the `examples/rian` files inputs to the generated, site-consumed dataset
  (ADR-0091): a drift between a file and the published data fails the freshness
  gate (`Rian.TourTest` / `mix rian.tour --check`).
  """
  @rian_sig "pub def dataset() Any"
  @spec dataset() :: [map()]
  def dataset, do: Enum.map(files(), &describe/1)

  @doc """
  Execute the `expr #=> expected` doctests in every gated file and raise if any
  fail. Files with no doctests (or marked `#@illustrative`) are skipped without
  compiling, so a BEAM-illegal-but-doctest-free file is never touched. Returns
  the number of doctests run.
  """
  @rian_sig "pub def check_doctests!() Int53"
  @spec check_doctests!() :: non_neg_integer()
  def check_doctests! do
    {failures, count} =
      Enum.reduce(files(), {[], 0}, fn file, {fails, n} ->
        src = File.read!(file)

        case header(src) do
          {:gated, _reach, _pins} ->
            {results, ran} = run_doctests(file, src)
            {fails ++ results, n + ran}

          _ ->
            {fails, n}
        end
      end)

    if failures == [], do: count, else: raise(Error, format_doctests(failures))
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

  # ── pane checks ───────────────────────────────────────────────────────────

  defp check_pane(file) do
    raw = File.read!(file)
    lines = raw |> String.trim_trailing() |> String.split("\n")

    tag_issue =
      if Enum.any?(lines, &String.starts_with?(String.trim(&1), "#@pane")),
        do: [],
        else: ["lacks a `#@pane` tag"]

    size_issue =
      if length(lines) > @pane_max_lines,
        do: [
          "#{length(lines)} lines exceeds the #{@pane_max_lines}-line pane limit — keep it minimal"
        ],
        else: []

    tag_issue ++ size_issue ++ pane_emit_issues(file)
  end

  @rian_host "tour gate: a `Decl.parse`/emitter raise becomes a 'does not parse/emit' issue list"
  defp pane_emit_issues(file) do
    body = file |> Path.basename(".rian") |> pane_source()
    prog = Decl.parse(body)

    for target <- Reach.targets(), {:raise, msg} <- [safe_emit(target, body, prog)] do
      "does not emit to #{target}: #{msg}"
    end
  rescue
    e ->
      [
        "does not parse: #{Exception.message(e) |> String.replace("\n", " ") |> String.slice(0, 80)}"
      ]
  end

  defp strip_pane_tag(src) do
    src
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim(&1), "#@pane"))
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  # ── dataset (tour.json input) ─────────────────────────────────────────────

  defp describe(file) do
    src = File.read!(file)
    base = %{"file" => Path.basename(file), "title" => title(src)}

    case header(src) do
      {:gated, reach, pins} ->
        Map.merge(base, %{
          "kind" => "gated",
          "reach" => sorted(reach),
          "pins" => Map.new(pins, fn {name, set} -> {name, sorted(set)} end),
          "reachByFn" => Map.new(reach_by_name(src), fn {name, set} -> {name, sorted(set)} end),
          "doctests" =>
            Enum.map(Doctest.extract(src), &%{"expr" => elem(&1, 0), "expected" => elem(&1, 1)})
        })

      {:illustrative, reason} ->
        Map.merge(base, %{"kind" => "illustrative", "reason" => reason})

      :none ->
        raise Error, "#{Path.basename(file)} has no `#@reach` or `#@illustrative` header"
    end
  end

  defp reach_by_name(src) do
    src
    |> Decl.parse()
    |> Reach.analyze()
    |> Map.new(fn {key, %{reach: reach}} -> {Reach.bare_name(key), reach} end)
  end

  defp title(src) do
    src
    |> String.split("\n")
    |> Enum.find_value("", fn line ->
      case Regex.run(~r/^#\s*\d+\s*(?:—|-)\s*(.+?)\s*$/u, line) do
        [_, t] -> t
        _ -> nil
      end
    end)
  end

  defp sorted(set), do: set |> MapSet.to_list() |> Enum.map(&to_string/1) |> Enum.sort()

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

        reach_issue(declared, union) ++
          pin_issues(by_name, union, pins) ++
          emit_issues(src, prog, by_name)
    end
  end

  # Reachability is an over-approximation (`Rian.Reach` does not run the full
  # `Check`), so a file can "reach" a target the emitter then refuses. We verify
  # the **floor** — the targets EVERY function reaches — by running that target's
  # real emitter and requiring it not to raise. (Union-but-not-floor targets on a
  # mixed file can't be whole-file-emitted, since the emitters compile the whole
  # module and a pinned-off function would raise; those rest on reach + doctests.)
  defp emit_issues(src, prog, by_name) do
    floor =
      by_name
      |> Map.values()
      |> Enum.reduce(MapSet.new(Reach.targets()), &MapSet.intersection/2)

    for target <- Enum.sort(floor), {:raise, msg} <- [safe_emit(target, src, prog)] do
      "claims `#{target}` (floor) but the #{target} emitter raises: #{msg}"
    end
  end

  @rian_host "tour gate: an emitter's unsupported-construct raise becomes `{:raise, msg}`"
  defp safe_emit(target, src, prog) do
    case target do
      :ex -> Rian.Beam.compile_program(src)
      :rs -> Lower.rust_program(prog)
      :js -> JS.compile(src)
      :jvm -> JVM.compile(src)
    end

    :ok
  rescue
    e -> {:raise, Exception.message(e) |> String.replace("\n", " ") |> String.slice(0, 80)}
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

  @rian_host "tour gate: `Decl.parse/1`'s malformed-source raise becomes `:error`"
  defp safe_parse(src) do
    {:ok, Decl.parse(src)}
  rescue
    _ -> :error
  end

  @rian_host "tour gate: `Doctest.run/1`'s compile raise becomes a failure record"
  defp run_doctests(file, src) do
    results = Doctest.run(src)
    fails = for {expr, {:fail, got, want}} <- results, do: {Path.basename(file), expr, got, want}
    {fails, length(results)}
  rescue
    e -> {[{Path.basename(file), "<compile>", Exception.message(e), "a loadable module"}], 0}
  end

  defp format_doctests(failures) do
    body =
      Enum.map_join(failures, "\n", fn {file, expr, got, want} ->
        "  #{file}: `#{expr}` => #{inspect(got)} (expected #{inspect(want)})"
      end)

    "by-example doctests failed:\n\n#{body}"
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
