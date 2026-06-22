defmodule Mix.Tasks.Rian.Format do
  @shortdoc "Format .rian source files (the canonical, gofmt-style formatter)"

  @moduledoc """
  Format Rian source with `Rian.Format` — one canonical style, **no options**.

      mix rian.format FILE…              # rewrite each file in place
      mix rian.format --check FILE…      # CI gate: exit non-zero if any file differs
      mix rian.format --diff FILE…       # print a unified diff of what would change (no write)
      mix rian.format -                  # read stdin, write formatted source to stdout
      mix rian.format --stdout FILE…     # format files, write to stdout (don't rewrite)

  The formatter is meaning-preserving (same parse), idempotent, comment-preserving,
  and wraps long lines to a fixed column budget (see `Rian.Format`). A file that
  cannot be lexed is reported and left untouched; with `--check`/`--diff` that is a
  non-zero exit.

  This task is a thin wrapper over `Rian.Format.CLI` — the same code backs the
  self-contained `rian fmt` escript (`mix escript.build`).

  Examples:

      mix rian.format examples/rian/08_lambdas_collections.rian
      mix rian.format --check examples/rian/*.rian
      mix rian.format --diff lib/foo.rian
      cat foo.rian | mix rian.format -
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    case Rian.Format.CLI.run(args) do
      0 -> :ok
      code -> exit({:shutdown, code})
    end
  end
end
