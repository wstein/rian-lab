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

  **Folder mode** — when the argument is a directory, every `**/*.ex` under it is
  drafted; with `-o OUTDIR` the parallel `.rian` files are written there (relative
  paths preserved). A **triage report** is printed to stderr: each module's defs,
  markers, and markers-per-def, ranked easiest-first, so you can see which modules
  are cheap to port and which are struct-reflection-heavy before committing.

  This is **not** a one-shot port: the output will not compile until a human fills
  the `_Ty`/`_Ret` holes, resolves every marker, makes matches exhaustive, and
  adds a fixpoint test. See `Rian.Transpile` for the translated-vs-flagged split.

      mix rian.transpile lib/rian/range.ex
      mix rian.transpile lib/rian/range.ex -o compiler/range.rian
      mix rian.transpile lib/rian/ -o compiler/drafts
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _invalid} =
      OptionParser.parse(args, strict: [output: :string], aliases: [o: :output])

    path =
      case argv do
        [p | _] -> p
        [] -> Mix.raise("usage: mix rian.transpile FILE.ex|DIR/ [-o OUT]")
      end

    cond do
      File.dir?(path) -> run_dir(path, opts[:output])
      File.regular?(path) -> run_file(path, opts[:output])
      true -> Mix.raise("no such file or directory: #{path}")
    end
  end

  # ── single file ─────────────────────────────────────────────────────────────

  defp run_file(file, out) do
    {text, stats} = file |> File.read!() |> Rian.Transpile.transpile_with_stats()

    case out do
      nil ->
        IO.puts(text)

      dest ->
        File.write!(dest, text)
        IO.puts(:stderr, "wrote draft → #{dest}")
    end

    IO.puts(
      :stderr,
      "TODO summary: #{stats.defs} def group(s), #{stats.ports} marker(s) to resolve by hand, " <>
        "#{stats.mapped} stdlib call(s) auto-mapped (verify semantics)"
    )
  end

  # ── folder ──────────────────────────────────────────────────────────────────

  defp run_dir(dir, out) do
    files = Path.wildcard(Path.join(dir, "**/*.ex"))
    if files == [], do: Mix.raise("no .ex files under #{dir}")

    entries =
      Enum.map(files, fn file ->
        {text, stats} = file |> File.read!() |> Rian.Transpile.transpile_with_stats()
        if out, do: write_draft(text, dir, file, out)
        {Path.relative_to(file, dir), stats}
      end)

    print_report(Rian.Transpile.rank(entries), out)
  end

  defp write_draft(text, dir, file, out) do
    dest = Path.join(out, String.replace_suffix(Path.relative_to(file, dir), ".ex", ".rian"))
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
