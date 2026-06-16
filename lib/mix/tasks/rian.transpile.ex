defmodule Mix.Tasks.Rian.Transpile do
  @shortdoc "Scaffold a draft .rian skeleton from an Elixir source file"

  @moduledoc """
  **Assisted-scaffolding** transpiler for the Elixir-pass-retirement track: turn
  an Elixir module into a *draft* Rian skeleton you then finish by hand and
  equiv-lock against the oracle.

      mix rian.transpile FILE.ex [-o OUT.rian]

  Without `-o`, the draft prints to stdout. A TODO summary (count of unresolved
  `TODO_PORT`/`# TODO[port]` markers and emitted def groups) is always printed to
  stderr so it never pollutes a redirected draft.

  This is **not** a one-shot port: the output will not compile until a human fills
  the `_Ty`/`_Ret` holes, resolves every marker, makes matches exhaustive, and
  adds a fixpoint test. See `Rian.Transpile` for the translated-vs-flagged split.

      mix rian.transpile lib/rian/range.ex
      mix rian.transpile lib/rian/range.ex -o compiler/range.rian
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _invalid} =
      OptionParser.parse(args, strict: [output: :string], aliases: [o: :output])

    file =
      case argv do
        [f | _] -> f
        [] -> Mix.raise("usage: mix rian.transpile FILE.ex [-o OUT.rian]")
      end

    unless File.exists?(file), do: Mix.raise("no such file: #{file}")

    {text, stats} = file |> File.read!() |> Rian.Transpile.transpile_with_stats()

    case opts[:output] do
      nil ->
        IO.puts(text)

      out ->
        File.write!(out, text)
        IO.puts(:stderr, "wrote draft → #{out}")
    end

    IO.puts(
      :stderr,
      "TODO summary: #{stats.defs} def group(s), #{stats.ports} marker(s) to resolve by hand"
    )
  end
end
