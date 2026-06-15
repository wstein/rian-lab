defmodule Mix.Tasks.Rian.Targets do
  @shortdoc "Report (and optionally gate) per-function target reachability for a .rian file"

  @moduledoc """
  Report which **target environments** each function in a Rian source file can
  lower to — `:ex` (Elixir/BEAM), `:rs` (Rust), `:js` (ECMAScript) — and *why* a
  function is pinned to a subset (host FFI, including concurrency/process/state
  FFI, which is native-per-target by design — ADR-0057).

      mix rian.targets FILE [--require ex,rs,js]

  With no `--require`, prints the reachability report (pure analysis, never
  fails). With `--require`, the listed targets become a **required set**: any
  function that cannot reach all of them is reported and the task exits non-zero
  — the portability gate, with the constraint *selected by need*.

      mix rian.targets examples/rian/prelude_int.rian
      mix rian.targets examples/rian/prelude_int.rian --require ex,rs,js
      mix rian.targets test/fixtures/rian/lexer.rian --require rs,js
  """
  use Mix.Task

  alias Rian.Reach

  @mark %{yes: "✓", no: "·"}

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: [require: :string])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    file =
      case argv do
        [f] -> f
        _ -> Mix.raise("usage: mix rian.targets FILE [--require ex,rs,js]")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    required = parse_required(opts[:require])
    Mix.Task.run("compile")
    report(file, required)
  end

  defp report(file, required) do
    prog = file |> File.read!() |> Rian.Decl.parse()
    rows = prog |> Reach.analyze() |> Enum.sort_by(&elem(&1, 0))

    Mix.shell().info("# #{file} — target reachability (ADR-0057)\n")

    Mix.shell().info(
      "  #{pad("fn", 22)}#{Enum.map_join(Reach.targets(), "  ", &pad(to_string(&1), 4))}  note"
    )

    failures =
      Enum.reduce(rows, [], fn {name, %{reach: reach, blockers: blockers}}, failed ->
        marks = Enum.map_join(Reach.targets(), "  ", &pad(mark(&1 in reach), 4))
        Mix.shell().info("  #{pad(name, 22)}#{marks}  #{note(blockers)}")

        missing = required -- MapSet.to_list(reach)
        if missing == [], do: failed, else: [{name, missing} | failed]
      end)

    report_contracts(prog)
    finish(required, Enum.reverse(failures))
  rescue
    e in [Rian.Decl.Error, Rian.Check.Error, ArgumentError, RuntimeError] ->
      Mix.raise("#{file}: #{Exception.message(e)}")
  end

  # In-source `@targets(…)` module contracts (ADR-0058 §2) are gated regardless
  # of `--require`: a declared promise must hold.
  defp report_contracts(prog) do
    contracted = Enum.filter(Map.get(prog, :mods, []), &(&1.targets != nil))

    Enum.each(contracted, fn m ->
      Mix.shell().info(
        "\n  module `#{m.name}` declares `@targets(#{Enum.join(m.targets, ", ")})`"
      )
    end)

    case Rian.Reach.check_contracts(prog) do
      :ok ->
        if contracted != [], do: Mix.shell().info("  all `@targets` contracts hold ✓")

      {:error, msg} ->
        Mix.shell().error("\n#{msg}")
        Mix.raise("`@targets` contract gate failed")
    end
  end

  defp finish([], _failures), do: :ok

  defp finish(required, []) do
    Mix.shell().info("\n  all functions reach the required set #{inspect(required)} ✓")
  end

  defp finish(required, failures) do
    Mix.shell().error(
      "\n  #{length(failures)} function(s) cannot reach the required set #{inspect(required)}:"
    )

    Enum.each(failures, fn {name, missing} ->
      Mix.shell().error("    #{name} — missing #{inspect(missing)}")
    end)

    Mix.raise("portability gate failed for #{inspect(required)}")
  end

  defp note([]), do: ""

  defp note(blockers) do
    {conc, ffi} = Enum.split_with(blockers, &(&1.kind == :concurrency))
    constructs = Enum.map_join(blockers, ", ", & &1.construct)
    kills = blockers |> Enum.flat_map(& &1.kills) |> Enum.uniq() |> Enum.sort()

    tag =
      cond do
        conc != [] and ffi == [] -> "concurrency/state FFI (native-per-target, ADR-0057)"
        conc != [] -> "host + concurrency FFI"
        true -> "host FFI"
      end

    "#{constructs} is ex-only — #{tag}; blocks #{inspect(kills)}"
  end

  defp parse_required(nil), do: []

  defp parse_required(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.to_atom()))
    |> Enum.map(fn t ->
      if t in Reach.targets(),
        do: t,
        else: Mix.raise("unknown target #{inspect(t)}; known: #{inspect(Reach.targets())}")
    end)
  end

  defp mark(true), do: @mark.yes
  defp mark(false), do: @mark.no
  defp pad(s, n), do: String.pad_trailing(to_string(s), n)
end
