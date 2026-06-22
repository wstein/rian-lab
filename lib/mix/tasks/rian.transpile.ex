defmodule Mix.Tasks.Rian.Transpile do
  @shortdoc "Scaffold a draft .rian skeleton from an Elixir source file"

  @moduledoc """
  **Assisted-scaffolding** transpiler for the Elixir-pass-retirement track: turn
  an Elixir module into a *draft* Rian skeleton you then finish by hand and
  equiv-lock against the oracle.

      mix rian.transpile FILE.ex  [-o OUT.rian]
      mix rian.transpile DIR/     [-o OUTDIR]

  **File mode** — without `-o`, the draft prints to stdout; a TODO summary (count
  of unresolved `TODO_PORT`/`# TODO[port]` markers and emitted def groups) goes to
  stderr so it never pollutes a redirected draft.

  **Folder mode** — when the argument is a directory, every `**/*.{ex,exs}` under it
  is drafted (so `.exs` scripts and test modules are triaged too, not just `.ex`
  sources); with `-o OUTDIR` the parallel `.rian` files are written there (relative
  paths preserved). A **triage report** is printed to stderr: each module's defs,
  markers, and markers-per-def, ranked easiest-first, so you can see which modules
  are cheap to port and which are struct-reflection-heavy before committing.

  **`--infer`** (ADR-0075) — runs per-def-group type inference (with a cross-module
  signature cache primed over the dir, so cross-module calls resolve) and fills the
  draft signatures with the inferred types; an unpinned slot stays a `_Unk` hole.
  **`--infer-report`** additionally prints the per-function residual-hole ledger.

  **`--check [DIR]`** — a CI/build **portability gate**: report every
  Rian-model-*incompatible* construct (truthy `&&`/`||` and exception flow
  `def … rescue`/`catch`/`after`, ADR-0035/0040 — see `Rian.Transpile.incompatible/1`)
  and **fail** (non-zero exit) if any file exceeds its recorded count in the
  baseline manifest (`priv/transpile_check_baseline.txt`, override with `--baseline`).
  This keeps the source in the portable subset — a newly-introduced truthy operator
  or `rescue` breaks the build. Host FFI and `_Unk` type holes are **not** flagged:
  those are honestly non-portable / fillable, not concept clashes. Re-baseline after
  intentionally resolving (or, rarely, adding) constructs with **`--update-baseline`**;
  the baseline only ever ratchets down toward zero.

  This is **not** a one-shot port: the output will not compile until a human fills
  the `_Unk` holes, resolves every marker, makes matches exhaustive, and
  adds a fixpoint test. See `Rian.Transpile` for the translated-vs-flagged split.

      mix rian.transpile lib/rian/range.ex
      mix rian.transpile lib/rian/range.ex -o tmp/range.rian
      mix rian.transpile lib/rian/ -o tmp/drafts
      mix rian.transpile lib/rian/ -o tmp/drafts --infer
      mix rian.transpile lib/rian --check                  # CI gate (exit non-zero on regression)
      mix rian.transpile lib/rian --check --update-baseline # re-record after resolving constructs
  """

  use Mix.Task

  # Default baseline manifest for `--check` (per-file incompatible-construct counts).
  @baseline_default "priv/transpile_check_baseline.txt"

  @impl Mix.Task
  def run(args) do
    {opts, argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          infer: :boolean,
          infer_report: :boolean,
          check: :boolean,
          update_baseline: :boolean,
          baseline: :string
        ],
        aliases: [o: :output, i: :infer]
      )

    path =
      case argv do
        [p | _] ->
          p

        [] ->
          Mix.raise(
            "usage: mix rian.transpile FILE.ex|DIR/ [-o OUT] [--infer] [--infer-report] | --check [DIR]"
          )
      end

    cond do
      opts[:check] || opts[:update_baseline] ->
        run_check(path, opts[:baseline] || @baseline_default, !!opts[:update_baseline])

      true ->
        # --infer-report implies --infer
        infer? = !!opts[:infer] or !!opts[:infer_report]
        o = %{out: opts[:output], infer: infer?, report: !!opts[:infer_report]}

        cond do
          File.dir?(path) -> run_dir(path, o)
          File.regular?(path) -> run_file(path, o)
          true -> Mix.raise("no such file or directory: #{path}")
        end
    end
  end

  # ── --check: gate a tree against Rian-incompatible constructs ─────────────────

  defp run_check(path, baseline_path, update?) do
    files =
      cond do
        File.dir?(path) -> Path.wildcard(Path.join(path, "**/*.{ex,exs}"))
        File.regular?(path) -> [path]
        true -> Mix.raise("no such file or directory: #{path}")
      end

    if files == [], do: Mix.raise("no .ex/.exs files under #{path}")

    # relpath => [incompatible construct lines], dropping the clean files.
    found =
      files
      |> Enum.map(fn f -> {f, Rian.Transpile.incompatible(File.read!(f))} end)
      |> Enum.reject(fn {_f, ms} -> ms == [] end)
      |> Map.new()

    if update? do
      write_baseline(baseline_path, found)
      IO.puts(:stderr, "wrote baseline → #{baseline_path} (#{map_size(found)} file(s))")
    else
      check_against_baseline(found, baseline_path)
    end
  end

  defp check_against_baseline(found, baseline_path) do
    baseline = read_baseline(baseline_path)

    regressions =
      for {file, markers} <- found,
          allowed = Map.get(baseline, file, 0),
          length(markers) > allowed,
          do: {file, markers, allowed}

    total = found |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    case Enum.sort(regressions) do
      [] ->
        IO.puts(
          :stderr,
          "rian.transpile --check: ok — #{total} Rian-incompatible construct(s) across " <>
            "#{map_size(found)} file(s), all within baseline (#{baseline_path})"
        )

      regs ->
        for {file, markers, allowed} <- regs do
          IO.puts(
            :stderr,
            "✗ #{file}: #{length(markers)} incompatible construct(s) (baseline #{allowed})"
          )

          for m <- markers, do: IO.puts(:stderr, "    #{m}")
        end

        Mix.raise(
          "rian.transpile --check: #{length(regs)} file(s) introduced Rian-incompatible " <>
            "constructs (truthy &&/|| or exception flow). Restructure to case/Option/Result " <>
            "(ADR-0035/0040), or re-baseline with `--update-baseline` if intentional."
        )
    end
  end

  # baseline format: one `count\trelpath` per line; `#` comment lines ignored.
  defp read_baseline(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Map.new(fn line ->
          [count, file] = String.split(line, "\t", parts: 2)
          {file, String.to_integer(count)}
        end)

      {:error, _} ->
        %{}
    end
  end

  defp write_baseline(path, found) do
    rows =
      found
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {file, markers} -> "#{length(markers)}\t#{file}" end)

    header = [
      "# Rian-incompatible-construct baseline for `mix rian.transpile --check` (ADR-0035/0040).",
      "# `count<TAB>path` — the per-file ceiling of truthy &&/|| + exception-flow markers.",
      "# CI fails if a file EXCEEDS its count; ratchet DOWN by resolving constructs then",
      "# re-running `--update-baseline`. Regenerated, do not hand-edit."
    ]

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.join(header ++ rows, "\n") <> "\n")
  end

  # ── single file ─────────────────────────────────────────────────────────────

  defp run_file(file, o) do
    src = File.read!(file)
    {text, stats} = Rian.Transpile.transpile_with_stats(src, infer: o.infer)

    case o.out do
      nil ->
        IO.puts(text)

      dest ->
        File.write!(dest, text)
        IO.puts(:stderr, "wrote draft → #{dest}")
    end

    IO.puts(
      :stderr,
      "TODO summary: #{stats.defs} def group(s), #{stats.ports} marker(s) to resolve by hand, " <>
        "#{stats.mapped} stdlib call(s) auto-mapped (verify semantics)" <>
        infer_suffix(src, stats, o)
    )

    if o.report, do: print_infer_report(src)
  end

  # remaining/filled type-hole counts when inference ran.
  defp infer_suffix(_src, _stats, %{infer: false}), do: ""

  defp infer_suffix(src, stats, %{infer: true}) do
    {_, base} = Rian.Transpile.transpile_with_stats(src, infer: false)
    filled = base.holes - stats.holes
    ", inferred #{filled}/#{base.holes} type hole(s) (#{stats.holes} remain)"
  end

  defp print_infer_report(src) do
    IO.puts(:stderr, "\ninference report (remaining holes):")

    case Rian.Transpile.infer_report(src) do
      [] ->
        IO.puts(:stderr, "  (all type holes filled)")

      reports ->
        for {{name, arity}, ledger} <- reports do
          slots = Enum.map_join(ledger, ", ", fn {slot, reason} -> "#{slot} #{reason}" end)
          IO.puts(:stderr, "  #{name}/#{arity}: #{slots}")
        end
    end
  end

  # ── folder ──────────────────────────────────────────────────────────────────

  defp run_dir(dir, o) do
    # Both `.ex` and `.exs`: a `.exs` script/test module is valid Elixir the
    # transpiler parses (not evaluates), so test modules can be triaged too — its
    # unsupported macros (`test`/`assert`) just surface as honest `TODO[port]`s.
    files = Path.wildcard(Path.join(dir, "**/*.{ex,exs}"))
    if files == [], do: Mix.raise("no .ex/.exs files under #{dir}")

    # Phase A: prime the cross-module signature table so cross-module calls resolve
    # during per-file inference.
    if o.infer, do: Rian.Transpile.prime_xmod(Enum.map(files, &File.read!/1))

    entries =
      Enum.map(files, fn file ->
        {text, stats} =
          Rian.Transpile.transpile_with_stats(File.read!(file), infer: o.infer)

        if o.out, do: write_draft(text, dir, file, o.out)
        {Path.relative_to(file, dir), stats}
      end)

    print_report(Rian.Transpile.rank(entries), o.out)
    if o.infer, do: print_hole_total(entries)
  end

  defp print_hole_total(entries) do
    total = entries |> Enum.map(fn {_, s} -> Map.get(s, :holes, 0) end) |> Enum.sum()
    IO.puts(:stderr, "  #{pad("TYPE HOLES REMAINING", 40)} #{total}")
  end

  defp write_draft(text, dir, file, out) do
    # Strip either `.ex` or `.exs` — a plain `replace_suffix(".ex", …)` would miss
    # `.exs` (its suffix is `.exs`) and write the draft as `foo.exs`, not `foo.rian`.
    rel = Regex.replace(~r/\.exs?$/, Path.relative_to(file, dir), ".rian")
    dest = Path.join(out, rel)
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, text)
  end

  defp print_report(rows, out) do
    if out, do: IO.puts(:stderr, "wrote #{length(rows)} draft(s) → #{out}/")

    IO.puts(:stderr, "\nport-difficulty triage (easiest first):")
    IO.puts(:stderr, "  #{pad("module", 40)} defs  markers  mapped  mk/def  tag")

    for r <- rows do
      ratio = :erlang.float_to_binary(r.ratio, decimals: 1)

      IO.puts(
        :stderr,
        "  #{pad(r.name, 40)} #{pad(r.defs, 4)}  #{pad(r.ports, 7)}  #{pad(r.mapped, 6)}  #{pad(ratio, 6)}  #{r.tag}"
      )
    end

    tot_defs = Enum.sum(Enum.map(rows, & &1.defs))
    tot_mk = Enum.sum(Enum.map(rows, & &1.ports))
    tot_mapped = Enum.sum(Enum.map(rows, & &1.mapped))

    IO.puts(
      :stderr,
      "  #{pad("TOTAL", 40)} #{pad(tot_defs, 4)}  #{pad(tot_mk, 7)}  #{pad(tot_mapped, 6)}"
    )
  end

  defp pad(v, n), do: v |> to_string() |> String.pad_trailing(n)
end
