defmodule Rian.Build do
  use Rian.Ann

  @moduledoc """
  Toolchain-free build/inspect verbs for the `rian` escript (ADR-0026/0031): the
  same operations as `mix rian.compile`/`rian.targets` surfaced with no Elixir/mix
  on the host. Each `*/1` takes argv and returns an exit code (`Rian.CLI` halts on it).

    * `build/1`   — compile a `.rian` to BEAM `.beam` files (the backend a rebar3
      plugin shells out to), or print Rust/JS/JVM source.
    * `check/1`   — run the parse/type/exhaustiveness gates; exit 0 / non-zero.
    * `targets/1` — per-function target reachability (`Rian.Reach`); `--require` gates.
  """

  @doc """
  `rian build FILE [-o DIR] [--rust|--js|--jvm]` — default emits BEAM bytecode,
  one `Elixir.<Mod>.beam` per module into DIR (default `.`); a target flag prints
  that target's source to stdout instead. Returns an exit code.
  """
  @spec build([String.t()]) :: non_neg_integer()
  def build(argv) do
    case OptionParser.parse(argv,
           strict: [out: :string, rust: :boolean, js: :boolean, jvm: :boolean],
           aliases: [o: :out]
         ) do
      {_opts, _, [_ | _] = bad} ->
        err("build: unknown option #{inspect(Enum.map(bad, &elem(&1, 0)))}")

      {opts, [file], _} ->
        case File.read(file) do
          {:ok, src} -> resolve_then_emit(opts, src, Path.dirname(file))
          {:error, reason} -> err(error_text(reason))
        end

      {_opts, _, _} ->
        err("usage: rian build FILE [-o DIR] [--rust|--js|--jvm]")
    end
  end

  # Resolve every file-reference `@external` against the source's directory before
  # emitting (ADR-0080 §7 a/c): a missing foreign file / absent export fails the build
  # closed, never a silent stub. A program with no file-references resolves trivially.
  # Parse errors-as-values here, mirroring `check`/`targets`.
  defp resolve_then_emit(opts, src, src_dir) do
    with {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.External.resolve(prog, src_dir) do
      emit(opts, src)
    else
      {:error, reason} -> err(error_text(reason))
    end
  end

  # The emit step is the one remaining boundary: a `--rust`/`--js`/`--jvm` lowering
  # (or BEAM codegen) can still raise on an unsupported construct or a gate failure
  # — converted to an exit code here rather than escaping the escript. Parse/IO
  # errors above are already values; this isolates the genuine emitter boundary.
  @rian_host "emit boundary: a lowering / BEAM codegen raise becomes an exit code"
  defp emit(opts, src) do
    cond do
      opts[:rust] -> print(Rian.Lower.rust_program(Rian.Decl.parse(src)))
      opts[:js] -> print(Rian.JS.compile(src))
      opts[:jvm] -> print(Rian.JVM.compile(src))
      true -> build_beam(src, Keyword.get(opts, :out, "."))
    end
  rescue
    e -> err(Exception.message(e))
  end

  # compile to BEAM and write one `<module>.beam` per module into `dir`.
  defp build_beam(src, dir) do
    File.mkdir_p!(dir)
    mods = compile_modules(src)

    Enum.each(mods, fn {atom, bin} ->
      path = Path.join(dir, "#{atom}.beam")
      File.write!(path, bin)
      IO.puts(path)
    end)

    0
  end

  # mods-xor-flat, mirroring `mix rian.compile`'s BEAM path: a file of `mod`s gives
  # one `Elixir.<Mod>.beam` each; a flat top-level file gives one `Elixir.RianCompiled`.
  defp compile_modules(src) do
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)

    case prog do
      %{mods: [_ | _]} ->
        Rian.Beam.compile_program(src)

      _ ->
        {:ok, atom, bin} = Rian.Beam.compile(src, :"Elixir.RianCompiled")
        [{atom, bin}]
    end
  end

  @doc "`rian check FILE` — run the gates; print `ok` (exit 0) or the error (exit 1)."
  @spec check([String.t()]) :: non_neg_integer()
  def check([file]) do
    with {:ok, src} <- File.read(file),
         {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.Check.check_program(prog) do
      IO.puts("#{file}: ok")
      0
    else
      {:error, reason} ->
        IO.puts(:stderr, "rian check: #{error_text(reason)}")
        1
    end
  end

  def check(_), do: err("usage: rian check FILE")

  @doc """
  `rian targets FILE [--require ex,rs,js]` — print per-function reachability. With
  `--require`, the listed targets are required: a function missing any is reported
  and the exit code is non-zero (the CI portability gate, toolchain-free).
  """
  @spec targets([String.t()]) :: non_neg_integer()
  def targets(argv) do
    case OptionParser.parse(argv, strict: [require: :string]) do
      {opts, [file], _} ->
        case File.read(file) do
          {:ok, src} -> targets_report(src, parse_required(opts[:require]))
          {:error, reason} -> err("targets: #{error_text(reason)}")
        end

      _ ->
        err("usage: rian targets FILE [--require ex,rs,js]")
    end
  end

  defp targets_report(src, required) do
    case Rian.Decl.parse_result(src) do
      {:error, msg} -> err("targets: #{msg}")
      {:ok, prog} -> targets_report(prog, required, Rian.Reach.analyze(prog))
    end
  end

  defp targets_report(_prog, required, report) do
    rows = Enum.sort_by(report, &elem(&1, 0))

    for {name, %{reach: reach}} <- rows do
      ts = Rian.Reach.targets() |> Enum.filter(&(&1 in reach)) |> Enum.map_join(",", &to_string/1)
      IO.puts("  #{name}: #{ts}")
    end

    missing =
      for {name, %{reach: reach}} <- rows,
          gap = required -- MapSet.to_list(reach),
          gap != [],
          do: {name, gap}

    case {required, missing} do
      {[], _} ->
        0

      {_, []} ->
        IO.puts("\nall functions reach #{inspect(required)} ✓")
        0

      {_, gaps} ->
        report_missing(gaps, required)
    end
  end

  defp report_missing(gaps, required) do
    IO.puts(:stderr, "\n#{length(gaps)} function(s) cannot reach #{inspect(required)}:")
    for {name, gap} <- gaps, do: IO.puts(:stderr, "  #{name} — missing #{inspect(gap)}")
    1
  end

  defp parse_required(nil), do: []

  defp parse_required(s),
    do: s |> String.split(",", trim: true) |> Enum.map(&String.to_atom(String.trim(&1)))

  defp print(text) do
    IO.puts(text)
    0
  end

  defp err(msg) when is_binary(msg) do
    IO.puts(:stderr, "rian: #{msg}")
    2
  end

  # render an error value for display: a gate/parse message is already a string; a
  # `File.read/1` failure is a posix atom, formatted via `:file.format_error/1`.
  defp error_text(msg) when is_binary(msg), do: msg
  defp error_text(posix), do: posix |> :file.format_error() |> List.to_string()
end
