defmodule Mix.Tasks.Rian.PortAnalysis do
  @shortdoc "Generate a reviewable Elixir→Rian port-analysis report (read-only)"

  @moduledoc """
  Read-only port-analysis (ADR-0075): emit a `PORT.analysis.md` summarizing what the
  transpiler/inference knows plus the human-judgment decisions a port needs — sum-type
  groupings and error-idiom→variant mappings.

      mix rian.port-analysis FILE.ex|DIR/ [-o OUT.md] [--spec port.spec] [--emit-spec FILE]

  The **`port.spec` feedback loop** (ADR-0075): `--spec port.spec` reads your decisions
  (`Sum1 = Expr`, `Unk0042 = String`) and applies them program-wide — one decision per
  *shared* placeholder re-resolves every site, so naming a few sums collapses hundreds of
  `Unk####`/`Sum#`. `--emit-spec FILE` writes a stub `port.spec` listing every decision to
  make (sums with their members, unknowns with site counts) so you have a checklist to
  fill, then re-run with `--spec`.

  Produces NO fills — it is the artifact a human reviews. Cross-module clustering uses
  every file given, so pass a DIR for the real sum groupings (the evidence is non-local).
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args,
        strict: [output: :string, spec: :string, emit_spec: :string],
        aliases: [o: :output]
      )

    path =
      case argv do
        [p | _] ->
          p

        [] ->
          Mix.raise("usage: mix rian.port-analysis FILE.ex|DIR/ [-o OUT.md] [--spec port.spec]")
      end

    files =
      cond do
        File.dir?(path) -> Path.wildcard(Path.join(path, "**/*.ex"))
        File.regular?(path) -> [path]
        true -> Mix.raise("no such file or directory: #{path}")
      end

    subs = Rian.PortSpec.load(opts[:spec])
    data = files |> Enum.map(&{&1, File.read!(&1)}) |> Rian.PortAnalysis.analyze()

    if dest = opts[:emit_spec] do
      File.write!(dest, Rian.PortSpec.template(data, subs))
      IO.puts(:stderr, "wrote spec template → #{dest}")
    end

    md = Rian.PortAnalysis.to_markdown(data, subs)

    case opts[:output] do
      nil ->
        IO.puts(md)

      out ->
        File.write!(out, md)

        applied =
          if subs == %{}, do: "", else: " (#{map_size(subs)} port.spec decision(s) applied)"

        IO.puts(:stderr, "wrote #{out}#{applied}")
    end
  end
end
