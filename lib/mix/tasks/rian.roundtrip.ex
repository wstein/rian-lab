defmodule Mix.Tasks.Rian.Roundtrip do
  @shortdoc "Elixir→Rian→Elixir roundtrip: per-module status on both BEAM backends"

  @moduledoc """
  Drive Elixir modules through the full roundtrip and report, per stage, how far
  each survives (`Rian.Roundtrip`):

      mix rian.roundtrip FILE.ex            # one module
      mix rian.roundtrip DIR/    [-o tmp]   # every .ex under DIR

  Each module is transpiled to `tmp/rian/<name>.rian`, compiled two ways — through
  `Rian.Beam` (the canonical abstract-forms backend) and through `Rian.Lower`'s
  Elixir-text emitter re-fed to the Elixir compiler (`tmp/ex/<name>.ex`) — and the
  two BEAM results are forms-checked against each other and against the *original*
  module's bytecode (the `lib/rian == tmp/ex` check).

  Columns: `beam` (Rian.Beam) · `ex` (Lower→Elixir) · `beam2` (that Elixir →
  BEAM) · `2-path` (the backends agree) · `vs-orig` (matches the original Elixir).
  A draft only reaches the BEAM stages once its `TODO_PORT` markers are resolved;
  `_Unk` type holes compile (they are open types).
  """

  use Mix.Task

  alias Rian.Roundtrip

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} = OptionParser.parse(args, strict: [out: :string], aliases: [o: :out])
    out = opts[:out] || "tmp"

    path =
      case argv do
        [p | _] -> p
        [] -> Mix.raise("usage: mix rian.roundtrip FILE.ex|DIR/ [-o tmp]")
      end

    Mix.Task.run("compile")

    {files, root} =
      cond do
        File.dir?(path) -> {Path.wildcard(Path.join(path, "**/*.ex")), path}
        File.regular?(path) -> {[path], Path.dirname(path)}
        true -> Mix.raise("no such file or directory: #{path}")
      end

    rows =
      Enum.map(files, fn f ->
        stem = f |> Path.relative_to(root) |> String.replace_suffix(".ex", "")
        {stem, Roundtrip.run_file(f, out, stem)}
      end)

    print_table(rows, out)
  end

  defp print_table(rows, out) do
    Mix.shell().info("roundtrip — wrote drafts to #{out}/rian, Elixir to #{out}/ex\n")

    Mix.shell().info("  #{pad("module", 26)} beam   ex     beam2  2-path    vs-orig")

    for {name, r} <- rows do
      Mix.shell().info(
        "  #{pad(name, 26)} #{cell(r.beam_direct)}  #{cell(elixir_stage(r))}  " <>
          "#{cell(r.beam_via_elixir)}  #{eq(r.equiv_two_paths)}  #{eq(r.equiv_vs_origin)}"
      )
    end

    green = Enum.count(rows, fn {_, r} -> r.equiv_vs_origin == :equiv end)

    Mix.shell().info(
      "\n  #{green}/#{length(rows)} module(s) roundtrip equivalent to the original"
    )
  end

  defp elixir_stage(%{elixir: nil}), do: {:error, "—"}
  defp elixir_stage(%{elixir: _}), do: :ok

  defp cell(:ok), do: pad("ok", 5)
  defp cell({:error, _}), do: pad("FAIL", 5)

  defp eq(:equiv), do: pad("equiv", 8)
  defp eq(:diverges), do: pad("diverge", 8)
  defp eq(:skipped), do: pad("—", 8)

  defp pad(v, n), do: v |> to_string() |> String.pad_trailing(n)
end
