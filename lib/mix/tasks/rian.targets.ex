defmodule Mix.Tasks.Rian.Targets do
  @shortdoc "Report (and optionally gate) per-function target reachability for a .rian file"

  @moduledoc """
  Report which **target environments** each function in a Rian source file can
  lower to — `:ex` (Elixir/BEAM), `:rs` (Rust), `:js` (ECMAScript) — and *why* a
  function is pinned to a subset (host FFI, including concurrency/process/state
  FFI, which is native-per-target by design — ADR-0057).

      mix rian.targets FILE [--require ex,rs,js] [--explain]

  With no `--require`, prints the reachability report (pure analysis, never
  fails). With `--require`, the listed targets become a **required set**: any
  function that cannot reach all of them is reported and the task exits non-zero
  — the portability gate, with the constraint *selected by need*.

  With `--explain`, every pinned function gets a per-blocker diagnostic
  (ADR-0086 §6): the offending **construct**, *why* it kills the target(s) it
  does, and the governing **ADR** — so reach reads like a teachable error, not a
  mystery. (Source line numbers await IR position tracking; the construct + cause
  are exact today.)

      mix rian.targets examples/rian/prelude_int.rian
      mix rian.targets examples/rian/prelude_int.rian --require ex,rs,js
      mix rian.targets test/fixtures/rian/lexer.rian --require rs,js
      mix rian.targets examples/rian/prelude_int.rian --explain
  """
  use Mix.Task

  alias Rian.Reach

  @mark %{yes: "✓", no: "·"}

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [require: :string, explain: :boolean])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    file =
      case argv do
        [f] -> f
        _ -> Mix.raise("usage: mix rian.targets FILE [--require ex,rs,js] [--explain]")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    required = parse_required(opts[:require])
    Mix.Task.run("compile")
    report(file, required, opts[:explain] == true)
  end

  defp report(file, required, explain?) do
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

    if explain?, do: explain_section(rows)
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
    constructs = Enum.map_join(blockers, ", ", & &1.construct)
    kills = blockers |> Enum.flat_map(& &1.kills) |> Enum.uniq() |> Enum.sort()
    "#{constructs} — blocks #{inspect(kills)} (--explain for why)"
  end

  # ── `--explain`: the per-pin diagnostic (ADR-0086 §6) ────────────────────────
  # For every function that does not reach all targets, name each blocking construct, *why* it
  # kills the target(s) it does, and the governing ADR — turning the terse table note into a
  # teachable reason. (Line numbers await IR position tracking; the construct + cause are exact.)
  defp explain_section(rows) do
    pinned = Enum.filter(rows, fn {_, %{blockers: bs}} -> bs != [] end)

    if pinned != [] do
      Mix.shell().info("\n— why (ADR-0086 §6) ———————————————————————————————————————")

      Enum.each(pinned, fn {name, %{reach: reach, blockers: blockers}} ->
        off = Reach.targets() -- MapSet.to_list(reach)
        Mix.shell().info("\n  #{name} — off #{inspect(off)}")

        blockers
        |> Enum.uniq_by(&{&1.kind, &1.construct})
        |> Enum.each(fn b ->
          {why, adr} = kind_help(b.kind)
          Mix.shell().info("    • #{b.construct}")
          Mix.shell().info("        → kills #{inspect(Enum.sort(b.kills))} — #{why} (#{adr})")
        end)
      end)
    end
  end

  # a blocker `kind` → {plain-English reason, governing ADR}. The blocker's `construct` already
  # names *what*; this says *why* it cannot lower and *where the decision lives*.
  defp kind_help(:ffi), do: {"host FFI is native-per-target, not a portable surface", "ADR-0057"}

  defp kind_help(:concurrency),
    do: {"concurrency/process/state is native-per-target by design", "ADR-0057"}

  defp kind_help(:capability),
    do: {"the `ref` (&mut) capability is BEAM-rejected, so it pins off `:ex`", "ADR-0055"}

  defp kind_help(:numeric),
    do:
      {"no portable representation on the killed target(s) (no bignum / >2^53 / 64-bit wrap)",
       "ADR-0064"}

  defp kind_help(:typed),
    do:
      {"the killed target's type system can't express it (e.g. Kotlin `Any` has no operators)",
       "ADR-0083/0049"}

  defp kind_help(:prim), do: {"a primitive with no native form on the killed target", "ADR-0069"}
  defp kind_help(:atom), do: {"atoms/symbols-as-data are BEAM-only", "ADR-0036"}

  defp kind_help(:generic),
    do: {"beyond the Rust emitter's monomorphic parametric subset", "ADR-0061"}

  defp kind_help(:map), do: {"a map literal/update has no portable non-BEAM lowering", "ADR-0047"}
  defp kind_help(:bitstring), do: {"bitstrings are BEAM-only", "ADR-0040"}
  defp kind_help(:pin), do: {"a pin (`^x`) has no Rust lowering", "ADR-0050"}

  defp kind_help(:dispatch),
    do: {"associated-type protocol dispatch has no JVM shape yet", "ADR-0074"}

  defp kind_help(:result), do: {"a `Result` value has no Kotlin shape yet", "ADR-0049"}
  defp kind_help(other), do: {"#{other} construct", "—"}

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
