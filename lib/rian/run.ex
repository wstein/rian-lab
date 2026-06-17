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

  # gate + load, then find the single module exporting the zero-arg entry. Compile
  # errors are rescued to `{:error, message}`; `apply/3` runs in `eval/2` (outside
  # this rescue) so a runtime crash keeps its stacktrace.
  defp resolve(src, main) do
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)
    fun = String.to_atom(main)

    # mirror `mix rian.compile`'s BEAM path: a file of `mod`s loads each by its
    # `Elixir.<Mod>` atom; a flat file of top-level `def`s loads as one module.
    mods =
      case prog do
        %{mods: [_ | _]} ->
          Rian.Beam.load_program(src)

        _ ->
          {:ok, mod} = Rian.Beam.load(src, :"Elixir.RianCompiled")
          [mod]
      end

    case Enum.filter(mods, &function_exported?(&1, fun, 0)) do
      [mod] ->
        {:ok, mod, fun}

      [] ->
        {:error,
         "no zero-arg entry `#{main}` (loaded: #{mods_str(mods)}) — define `def #{main}() …`"}

      many ->
        {:error, "entry `#{main}` is defined in more than one module (#{mods_str(many)})"}
    end
  rescue
    e -> {:error, Exception.message(e)}
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
