defmodule Rian.Format.CLI do
  @moduledoc """
  Mix-free command core for the formatter, shared by the `rian fmt` escript
  (`Rian.CLI`) and the `mix rian.format` task. `run/1` takes the argv *after* the
  subcommand, does its own `IO`, and **returns an integer exit code** (it never
  halts) so it is callable from both runtimes and directly testable.

  Exit codes: `0` ok / nothing to do · `1` files differ or are unlexable
  (`--check`/`--diff`) · `2` usage error.
  """

  alias Rian.Format

  @doc "Run the fmt CLI over `argv` (already stripped of any `fmt` subcommand)."
  def run(argv) do
    case OptionParser.parse(argv, strict: [check: :boolean, diff: :boolean, stdout: :boolean]) do
      {_opts, _files, [_ | _] = invalid} ->
        IO.puts(
          :stderr,
          "rian fmt: unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}"
        )

        2

      {opts, files, []} ->
        cond do
          files == ["-"] -> format_stdin()
          files == [] -> usage()
          opts[:check] -> check(files)
          opts[:diff] -> diff(files)
          opts[:stdout] -> each(files, &to_stdout/1)
          true -> each(files, &in_place/1)
        end
    end
  end

  defp usage do
    IO.puts(:stderr, "usage: rian fmt FILE… [--check | --diff | --stdout]   (or `-` for stdin)")
    2
  end

  # run `fun` over every file, returning the worst (max) exit code
  defp each(files, fun), do: files |> Enum.map(fun) |> Enum.max(fn -> 0 end)

  defp format_stdin do
    src = IO.read(:stdio, :eof) || ""

    case Format.format_result(src) do
      {:ok, out} ->
        IO.write(out)
        0

      {:error, msg} ->
        IO.write(src)
        IO.puts(:stderr, "rian fmt: #{msg}")
        1
    end
  end

  defp to_stdout(file) do
    with {:ok, src} <- read(file),
         {:ok, out} <- Format.format_result(src) do
      IO.write(out)
      0
    else
      {:error, msg} ->
        IO.puts(:stderr, "#{file}: #{msg}")
        1
    end
  end

  defp in_place(file) do
    with {:ok, src} <- read(file),
         {:ok, out} <- Format.format_result(src) do
      cond do
        out == src ->
          IO.puts("  unchanged  #{file}")
          0

        true ->
          File.write!(file, out)
          IO.puts("  formatted  #{file}")
          0
      end
    else
      {:error, msg} ->
        IO.puts(:stderr, "  ERROR      #{file}: #{msg}")
        1
    end
  end

  defp check(files) do
    bad =
      Enum.filter(files, fn f ->
        case read(f) do
          {:ok, src} -> Format.format_result(src) != {:ok, src}
          {:error, _} -> true
        end
      end)

    if bad == [] do
      IO.puts("all #{length(files)} file(s) already formatted")
      0
    else
      IO.puts(:stderr, "not formatted (run `rian fmt`):")
      Enum.each(bad, &IO.puts(:stderr, "  #{&1}"))
      1
    end
  end

  defp diff(files) do
    codes =
      Enum.map(files, fn f ->
        with {:ok, src} <- read(f), {:ok, out} <- Format.format_result(src) do
          if out == src, do: 0, else: print_diff(f, src, out)
        else
          {:error, msg} ->
            IO.puts(:stderr, "#{f}: #{msg}")
            1
        end
      end)

    Enum.max(codes, fn -> 0 end)
  end

  defp print_diff(file, src, out) do
    IO.puts(unified_diff(file, src, out))
    1
  end

  # a minimal unified diff via Elixir's built-in Myers diff over lines
  defp unified_diff(file, old, new) do
    body =
      String.split(old, "\n")
      |> List.myers_difference(String.split(new, "\n"))
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &("  " <> &1))
        {:del, lines} -> Enum.map(lines, &("- " <> &1))
        {:ins, lines} -> Enum.map(lines, &("+ " <> &1))
      end)
      |> Enum.join("\n")

    "--- #{file}\n+++ #{file} (formatted)\n" <> body
  end

  defp read(file) do
    case File.read(file) do
      {:ok, src} -> {:ok, src}
      {:error, reason} -> {:error, "cannot read: #{:file.format_error(reason)}"}
    end
  end
end
