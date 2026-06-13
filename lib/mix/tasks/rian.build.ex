defmodule Mix.Tasks.Rian.Build do
  @shortdoc "Assemble a .rian file into one whole-program module per target"

  @moduledoc """
  Build a Rian source file as a **single** target module — unlike
  `mix rian.compile`, which emits one unit per function for inspection, this
  composes the whole program (types, `protocol` traits + `impl`s, and every
  function) into one artifact that a target toolchain can build directly.

      mix rian.build FILE --rust    # one Rust module (ADR-0061 whole-program assembly)

  Types/traits/impls are emitted once (deduped), so the stdlib + protocols +
  generics compose. Currently `--rust` is supported; `--beam`/`--js` whole-program
  assembly can follow the same shape.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} = OptionParser.parse(args, strict: [rust: :boolean])

    file =
      case argv do
        [f] -> f
        _ -> Mix.raise("usage: mix rian.build FILE --rust")
      end

    unless opts[:rust], do: Mix.raise("specify a target, e.g. `--rust`")
    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    Mix.Task.run("compile")
    prog = Rian.Decl.parse(File.read!(file))
    :ok = Rian.Check.gate!(prog)
    :ok = Rian.Reach.gate!(prog)
    Mix.shell().info(Rian.Lower.rust_program(prog))
  rescue
    e in [Rian.Decl.Error, Rian.Check.Error, Rian.Reach.Error] ->
      Mix.raise(Exception.message(e))
  end
end
