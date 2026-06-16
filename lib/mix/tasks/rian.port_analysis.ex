defmodule Mix.Tasks.Rian.PortAnalysis do
  @shortdoc "Generate a reviewable Elixir→Rian port-analysis report (read-only)"

  @moduledoc """
  Read-only port-analysis (ADR-0075): emit a `PORT.analysis.md` summarizing what the
  transpiler/inference knows plus the human-judgment decisions a port needs — sum-type
  groupings and error-idiom→variant mappings.

      mix rian.port-analysis FILE.ex|DIR/ [-o OUT.md]

  Produces NO fills and feeds nothing back — it is the artifact a human reviews.
  Cross-module clustering uses every file given, so pass a DIR for the real sum
  groupings (the evidence is non-local).
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} = OptionParser.parse(args, strict: [output: :string], aliases: [o: :output])

    path =
      case argv do
        [p | _] -> p
        [] -> Mix.raise("usage: mix rian.port-analysis FILE.ex|DIR/ [-o OUT.md]")
      end

    files =
      cond do
        File.dir?(path) -> Path.wildcard(Path.join(path, "**/*.ex"))
        File.regular?(path) -> [path]
        true -> Mix.raise("no such file or directory: #{path}")
      end

    md =
      files
      |> Enum.map(&{&1, File.read!(&1)})
      |> Rian.PortAnalysis.analyze()
      |> Rian.PortAnalysis.to_markdown()

    case opts[:output] do
      nil ->
        IO.puts(md)

      out ->
        File.write!(out, md)
        IO.puts(:stderr, "wrote #{out}")
    end
  end
end
