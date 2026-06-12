defmodule Mix.Tasks.Rian.Compile do
  @shortdoc "Compile a .rian source file to Elixir and/or Rust"

  @moduledoc """
  Compile a Rian source file (Stage 0.1 declaration surface) and print the
  lowered output for each top-level function and module.

      mix rian.compile FILE [--beam | --elixir | --rust]

  By default **both** targets are emitted. Options:

    * `--beam`    compile to the BEAM target only; permits Erlang FFI
                  (`:lists.sum(...)`, `String.upcase(...)`) that has no Rust form
    * `--elixir`  show only the Elixir output (both-target compile)
    * `--rust`    show only the Rust output (both-target compile)

  Exits non-zero on a parse, exhaustiveness, or type-check error.

      mix rian.compile examples/area.rian
      mix rian.compile examples/rian/05_modules.rian --rust
      mix rian.compile examples/rian/08_lambdas_collections.rian --beam
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args, strict: [beam: :boolean, elixir: :boolean, rust: :boolean])

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    file =
      case argv do
        [f] -> f
        [] -> Mix.raise("usage: mix rian.compile FILE [--beam | --elixir | --rust]")
        _ -> Mix.raise("compile one file at a time")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    # ensure the project (and Rian.*) is compiled before we call into it
    Mix.Task.run("compile")
    compile_and_print(file, opts)
  end

  defp compile_and_print(file, opts) do
    src = File.read!(file)
    targets = targets(opts)

    units =
      if opts[:beam], do: Rian.Decl.compile_beam(src), else: Rian.Decl.compile(src)

    Mix.shell().info("# #{file} — #{length(units)} unit(s)\n")
    Enum.each(units, &print_unit(&1, targets))
  rescue
    e in [Rian.Decl.Error, Rian.Check.Error, ArgumentError, RuntimeError] ->
      Mix.raise("#{file}: #{Exception.message(e)}")
  end

  defp print_unit({name, out}, targets) do
    Mix.shell().info("══ #{name} ══")
    if :elixir in targets && out[:elixir], do: section("Elixir", out.elixir)
    if :rust in targets && out[:rust], do: section("Rust", out.rust)
  end

  defp section(label, code), do: Mix.shell().info("── #{label} ──\n#{code}\n")

  # `--beam` forces Elixir-only; otherwise an explicit `--elixir`/`--rust`
  # narrows the display, and with neither both targets are shown.
  defp targets(opts) do
    cond do
      opts[:beam] -> [:elixir]
      opts[:elixir] && opts[:rust] -> [:elixir, :rust]
      opts[:elixir] -> [:elixir]
      opts[:rust] -> [:rust]
      true -> [:elixir, :rust]
    end
  end
end
