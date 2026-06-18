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
  exactly as on every other path. `run_file/2` (and `rian run FILE`) additionally
  **bundles** a program's `@external(:ex)` file-references — compiling+loading the
  foreign `.ffi.ex` so the calls resolve before the entry runs (ADR-0080 §7).
  """

  @doc """
  Evaluate Rian source: gate it, load every module, and apply the zero-arg entry
  `main` (or `name`). Returns `{:ok, value}` or `{:error, message}`. A *compile*
  error (parse/check/exhaustiveness) becomes `{:error, …}`; a *runtime* error in the
  entry function propagates (its real stacktrace is more useful than a swallowed one).
  """
  @spec eval(String.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def eval(src, main \\ "main") when is_binary(src) do
    with {:ok, mod, fun} <- resolve(src, main, nil) do
      {:ok, apply(mod, fun, [])}
    end
  end

  @doc """
  Read `path` and run its entry. Unlike `eval/2`, a file has a base directory, so a
  program whose `@external(:ex, "./x.ffi.ex", …)` references a foreign Elixir file is
  **bundled**: the `.ffi.ex` is compiled+loaded and the external calls resolve before
  the entry runs (ADR-0080 §7 / ADR-0068).
  """
  @spec run_file(Path.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def run_file(path, main \\ "main") do
    case File.read(path) do
      {:ok, src} ->
        with {:ok, mod, fun} <- resolve(src, main, Path.dirname(path)) do
          {:ok, apply(mod, fun, [])}
        end

      {:error, reason} ->
        {:error, "cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  # gate + load, then find the single module exporting the zero-arg entry. Parse,
  # gate and codegen errors arrive as `{:error, message}` values (errors-as-values,
  # ADR-0035/0040) and short-circuit the `with`; `apply/3` runs in the caller (outside
  # this chain) so a genuine runtime crash keeps its stacktrace. `src_dir` is the base
  # for `@external` file-reference resolution (`nil` for a dir-less string `eval/2`).
  defp resolve(src, main, src_dir) do
    with {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.Check.check_program(prog),
         {:ok, mods} <- load_mods(prog, src, src_dir) do
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

  # a program with `@external(:ex)` file-references is bundled before loading (`src_dir`
  # gives the base for resolution); without a dir, a file-reference cannot resolve, so
  # that is a clear error rather than an obscure emit failure. Otherwise load from text.
  defp load_mods(prog, src, src_dir) do
    cond do
      Rian.External.has_beam_file_ref?(prog) and is_binary(src_dir) ->
        bundle_and_load(prog, src_dir)

      Rian.External.has_beam_file_ref?(prog) ->
        {:error,
         "a file-reference `@external(:ex, …)` needs a source file path — use `rian run FILE`"}

      true ->
        load_plain(prog, src)
    end
  end

  # `lower_beam/2` resolves the references, compiles+loads the foreign modules, and
  # rewrites each file-reference to a module-reference; the lowered program then loads
  # straight from IR (skipping a re-parse that would re-derive the file-references).
  defp bundle_and_load(prog, src_dir) do
    with :ok <- Rian.External.resolve(prog, src_dir),
         {:ok, lowered, _ffi_beams} <- Rian.External.lower_beam(prog, src_dir) do
      load_lowered(lowered)
    end
  end

  defp load_lowered(%{mods: [_ | _]} = prog), do: {:ok, Rian.Beam.load_program_ir(prog)}

  defp load_lowered(prog) do
    {:ok, mod} = Rian.Beam.load_ir(prog, :"Elixir.RianCompiled")
    {:ok, [mod]}
  end

  # mirror `mix rian.compile`'s BEAM path: a file of `mod`s loads each by its
  # `Elixir.<Mod>` atom; a flat file of top-level `def`s loads as one module.
  defp load_plain(%{mods: [_ | _]}, src), do: Rian.Beam.load_program_result(src)

  defp load_plain(_prog, src) do
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
