defmodule Rian.Run do
  @moduledoc """
  Run a `.rian` program on the BEAM — the non-interactive sibling of `Rian.Repl`
  (ADR-0031). Parse → `Rian.Check.gate!` → `Rian.Beam.load_program/1` → invoke a
  zero-arg entry function (default `main`) and return its value.

  Shared by `mix rian.run` and the `rian run` escript subcommand (`Rian.CLI`), the
  same split as `Rian.Format.CLI` backing `mix rian.format` + `rian fmt`. **BEAM-only
  by nature** — the run *target* is the BEAM; other targets emit via `mix rian.compile`.
  This is a run *convenience*, not an `.exs`-style script file type (which would cut
  against ADR-0057's "one source, many targets"); the program is statically gated
  exactly as on every other path.
  """

  @doc """
  Evaluate Rian source: gate it, load every module, and apply the zero-arg entry
  `main` (or `name`). Returns `{:ok, value}` or `{:error, message}`. A *compile*
  error (parse/check/exhaustiveness) becomes `{:error, …}`; a *runtime* error in the
  entry function propagates (its real stacktrace is more useful than a swallowed one).
  """
  @spec eval(String.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def eval(src, main \\ "main") when is_binary(src) do
    with {:ok, mod, fun} <- resolve(src, main) do
      {:ok, apply(mod, fun, [])}
    end
  end

  @doc "Read `path` and `eval/2` its contents."
  @spec run_file(Path.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def run_file(path, main \\ "main") do
    case File.read(path) do
      {:ok, src} -> eval(src, main)
      {:error, reason} -> {:error, "cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  # gate + load, then find the single module exporting the zero-arg entry. Parse,
  # gate and codegen errors arrive as `{:error, message}` values (errors-as-values,
  # ADR-0035/0040) and short-circuit the `with`; `apply/3` runs in `eval/2` (outside
  # this chain) so a genuine runtime crash keeps its stacktrace.
  defp resolve(src, main) do
    with {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.Check.check_program(prog),
         {:ok, mods} <- load_mods(prog, src) do
      fun = String.to_atom(main)

      case Enum.filter(mods, &function_exported?(&1, fun, 0)) do
        [mod] ->
          {:ok, mod, fun}

        [] ->
          {:error,
           "no zero-arg entry `#{main}` (loaded: #{mods_str(mods)}) — define `def #{main}() …`"}

        many ->
          {:error, "entry `#{main}` is defined in more than one module (#{mods_str(many)})"}
      end
    end
  end

  # mirror `mix rian.compile`'s BEAM path: a file of `mod`s loads each by its
  # `Elixir.<Mod>` atom; a flat file of top-level `def`s loads as one module.
  defp load_mods(%{mods: [_ | _]}, src), do: Rian.Beam.load_program_result(src)

  defp load_mods(_prog, src) do
    case Rian.Beam.load_result(src, :"Elixir.RianCompiled") do
      {:ok, mod} -> {:ok, [mod]}
      {:error, _} = err -> err
    end
  end

  defp mods_str([]), do: "no modules"
  defp mods_str(mods), do: Enum.map_join(mods, ", ", &inspect/1)

  @doc """
  Escript `rian run` adapter: `argv → exit code`, printing the entry's value to
  stdout (0) or an error to stderr (1; usage error 2).
  """
  @spec cli([String.t()]) :: non_neg_integer()
  def cli(argv) do
    case OptionParser.parse(argv, strict: [main: :string]) do
      {_opts, _files, [_ | _] = invalid} ->
        IO.puts(:stderr, "rian run: unknown option #{inspect(Enum.map(invalid, &elem(&1, 0)))}")
        2

      {_opts, [], _} ->
        IO.puts(:stderr, "usage: rian run FILE [--main FUNC]")
        2

      {opts, [file], _} ->
        case run_file(file, Keyword.get(opts, :main, "main")) do
          {:ok, value} ->
            IO.puts(inspect(value))
            0

          {:error, msg} ->
            IO.puts(:stderr, "rian run: #{msg}")
            1
        end

      {_opts, _files, _} ->
        IO.puts(:stderr, "rian run: run one file at a time")
        2
    end
  end
end
