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

  Examples:

      mix rian.format examples/rian/08_lambdas_collections.rian
      mix rian.format --check compiler/*.rian
      mix rian.format --diff lib/foo.rian
      cat foo.rian | mix rian.format -
  """
  use Mix.Task

  alias Rian.Format

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [check: :boolean, diff: :boolean, stdout: :boolean])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    Mix.Task.run("compile")

    cond do
      argv == ["-"] -> format_stdin()
      argv == [] -> Mix.raise("usage: mix rian.format FILE… [--check | --diff | --stdout]")
      opts[:check] -> check(argv)
      opts[:diff] -> diff(argv)
      opts[:stdout] -> Enum.each(argv, &to_stdout/1)
      true -> Enum.each(argv, &format_in_place/1)
    end
  end

  defp format_stdin do
    src = IO.read(:stdio, :eof) || ""

    case Format.format_result(src) do
      {:ok, out} ->
        IO.write(out)

      {:error, msg} ->
        IO.write(src)
        Mix.shell().error("rian.format: #{msg}")
    end
  end

  defp to_stdout(file) do
    case Format.format_result(read!(file)) do
      {:ok, out} -> IO.write(out)
      {:error, msg} -> Mix.raise("#{file}: #{msg}")
    end
  end

  defp format_in_place(file) do
    src = read!(file)

    case Format.format_result(src) do
      {:ok, ^src} ->
        Mix.shell().info("  unchanged  #{file}")

      {:ok, out} ->
        File.write!(file, out)
        Mix.shell().info("  formatted  #{file}")

      {:error, msg} ->
        Mix.shell().error("  ERROR      #{file}: #{msg}")
    end
  end

  # `--check`: change nothing, list files that differ or cannot be lexed, exit
  # non-zero if any are found (the CI gate).
  defp check(files) do
    bad =
      Enum.filter(files, fn f ->
        case Format.format_result(read!(f)) do
          {:ok, out} -> out != read!(f)
          {:error, _} -> true
        end
      end)

    if bad == [] do
      Mix.shell().info("all #{length(files)} file(s) already formatted")
    else
      Mix.shell().error("not formatted (run `mix rian.format`):")
      Enum.each(bad, &Mix.shell().error("  #{&1}"))
      exit({:shutdown, 1})
    end
  end

  # `--diff`: print a unified diff per file; exit non-zero if anything would change.
  defp diff(files) do
    changed =
      Enum.reduce(files, [], fn f, acc ->
        src = read!(f)

        case Format.format_result(src) do
          {:ok, ^src} ->
            acc

          {:ok, out} ->
            Mix.shell().info(unified_diff(f, src, out))
            [f | acc]

          {:error, msg} ->
            Mix.shell().error("#{f}: #{msg}")
            [f | acc]
        end
      end)

    if changed != [], do: exit({:shutdown, 1})
  end

  # a minimal unified diff via Elixir's built-in Myers diff over lines
  defp unified_diff(file, old, new) do
    header = "--- #{file}\n+++ #{file} (formatted)"

    body =
      String.split(old, "\n")
      |> List.myers_difference(String.split(new, "\n"))
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &("  " <> &1))
        {:del, lines} -> Enum.map(lines, &("- " <> &1))
        {:ins, lines} -> Enum.map(lines, &("+ " <> &1))
      end)
      |> Enum.join("\n")

    header <> "\n" <> body
  end

  defp read!(file) do
    if not File.exists?(file), do: Mix.raise("no such file: #{file}")
    File.read!(file)
  end
end
