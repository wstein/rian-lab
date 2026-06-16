defmodule Mix.Tasks.Rian.Format do
  @shortdoc "Format .rian source files (the canonical, gofmt-style formatter)"

  @moduledoc """
  Format Rian source with `Rian.Format` — one canonical style, **no options**.

      mix rian.format FILE…              # rewrite each file in place
      mix rian.format --check FILE…      # CI gate: exit non-zero if any file differs
      mix rian.format -                  # read stdin, write formatted source to stdout
      mix rian.format --stdout FILE…     # format files, write to stdout (don't rewrite)

  The formatter never parses and never changes program meaning: it re-lexes to
  the same token stream, is idempotent, and preserves every comment and heredoc
  at its authored position (see `Rian.Format`).

  Examples:

      mix rian.format examples/rian/08_lambdas_collections.rian
      mix rian.format --check compiler/*.rian
      cat foo.rian | mix rian.format -
  """
  use Mix.Task

  alias Rian.Format

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [check: :boolean, stdout: :boolean])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    Mix.Task.run("compile")

    cond do
      argv == ["-"] -> format_stdin()
      argv == [] -> Mix.raise("usage: mix rian.format FILE… [--check] [--stdout]")
      opts[:check] -> check(argv)
      opts[:stdout] -> Enum.each(argv, &to_stdout/1)
      true -> Enum.each(argv, &format_in_place/1)
    end
  end

  defp format_stdin do
    IO.write(Format.format(IO.read(:stdio, :eof) || ""))
  end

  defp to_stdout(file), do: IO.write(Format.format(read!(file)))

  defp format_in_place(file) do
    src = read!(file)
    out = Format.format(src)

    if out == src do
      Mix.shell().info("  unchanged  #{file}")
    else
      File.write!(file, out)
      Mix.shell().info("  formatted  #{file}")
    end
  end

  # `--check`: change nothing, list files that are not already formatted, and exit
  # non-zero if any are found (the CI gate).
  defp check(files) do
    unformatted =
      Enum.filter(files, fn f ->
        src = read!(f)
        Format.format(src) != src
      end)

    if unformatted == [] do
      Mix.shell().info("all #{length(files)} file(s) already formatted")
    else
      Mix.shell().error("not formatted (run `mix rian.format`):")
      Enum.each(unformatted, &Mix.shell().error("  #{&1}"))
      exit({:shutdown, 1})
    end
  end

  defp read!(file) do
    if not File.exists?(file), do: Mix.raise("no such file: #{file}")
    File.read!(file)
  end
end
