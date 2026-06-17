defmodule Mix.Tasks.Rian.Run do
  @shortdoc "Compile a .rian file to BEAM and run its `main/0`"

  @moduledoc """
  Compile a Rian source file to BEAM bytecode and invoke its entry function — the
  non-interactive sibling of `mix rian.repl` (ADR-0031). Parses, runs the
  type/exhaustiveness gates, loads every module, and applies the zero-arg entry
  (default `main`), printing its value.

      mix rian.run FILE [--main FUNC]

  Options:

    * `--main FUNC`  the zero-arg entry function to call (default `main`)

  Runs on the **BEAM** (the run target); emit other targets with `mix rian.compile`.
  Exits non-zero on a parse / type / exhaustiveness error, or if no entry is found.

      mix rian.run examples/area.rian
      mix rian.run prog.rian --main demo
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: [main: :string])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    file =
      case argv do
        [f] -> f
        [] -> Mix.raise("usage: mix rian.run FILE [--main FUNC]")
        _ -> Mix.raise("run one file at a time")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    # ensure the project (and Rian.*) is compiled before we call into it
    Mix.Task.run("compile")

    case Rian.Run.run_file(file, opts[:main] || "main") do
      {:ok, value} -> Mix.shell().info(inspect(value))
      {:error, msg} -> Mix.raise(msg)
    end
  end
end
