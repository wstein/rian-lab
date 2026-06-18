defmodule Rian.CLI do
  @moduledoc """
  The `rian` command-line entry point for the self-contained escript
  (`mix escript.build` → a `rian` binary; ADR-0031/0045 Tier 3). Runs with no Mix
  or Elixir toolchain on the host.

  Subcommands:

      rian fmt FILE…            # rewrite each file in place
      rian fmt --check FILE…    # exit non-zero if any file is unformatted / unlexable
      rian fmt --diff FILE…     # print a unified diff of what would change (no write)
      rian fmt --stdout FILE…   # write formatted source to stdout (don't rewrite)
      rian fmt -                # read stdin, write formatted source to stdout
      rian run FILE             # compile to BEAM and run `main/0`, printing its value
      rian run FILE --main FUNC # run a different zero-arg entry
      rian build FILE [-o DIR]  # compile to BEAM `.beam` files (the rebar3 backend)
      rian build FILE --rust    # print Rust/JS/JVM source (--rust|--js|--jvm)
      rian check FILE           # run the type/exhaustiveness gates (exit 0/1)
      rian targets FILE [--require ex,rs,js]   # per-function reachability / gate

  The actual logic lives in `Rian.Format.CLI` / `Rian.Run` / `Rian.Build`, so the same
  code backs both this escript and the `mix rian.*` tasks. This module only maps a
  subcommand to its handler: `run/1` does the dispatch and returns the exit code
  (the testable half), and `main/1` is just `run/1` piped into `System.halt/1`.
  """

  @doc "escript entry point."
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    argv
    |> run()
    |> System.halt()
  end

  @doc """
  Dispatch `argv` to the matching subcommand and return its integer exit code,
  **without halting** — the testable half of `main/1` (same split as
  `Rian.Format.CLI.run/1`). `main/1` is just `run/1` piped into `System.halt/1`.
  """
  @spec run([String.t()]) :: non_neg_integer()
  def run(["fmt" | rest]), do: Rian.Format.CLI.run(rest)
  def run(["run" | rest]), do: Rian.Run.cli(rest)
  def run(["build" | rest]), do: Rian.Build.build(rest)
  def run(["check" | rest]), do: Rian.Build.check(rest)
  def run(["targets" | rest]), do: Rian.Build.targets(rest)

  def run(["-h" | _]), do: usage(0)
  def run(["--help" | _]), do: usage(0)
  def run([]), do: usage(0)

  def run([other | _]) do
    IO.puts(:stderr, "rian: unknown command #{inspect(other)}")
    usage(2)
  end

  defp usage(code) do
    IO.puts("""
    rian — the Rian toolchain

    usage:
      rian fmt FILE…            format files in place
      rian fmt --check FILE…    exit non-zero if any file is not formatted
      rian fmt --diff FILE…     print a unified diff of what would change
      rian fmt --stdout FILE…   write formatted source to stdout
      rian fmt -                format stdin → stdout
      rian run FILE             compile to BEAM and run `main/0`
      rian run FILE --main FUNC run a different zero-arg entry
      rian build FILE [-o DIR]  compile to BEAM `.beam` files in DIR (default .)
      rian build FILE --rust    print Rust/JS/JVM source (--rust|--js|--jvm)
      rian check FILE           run the type/exhaustiveness gates (exit 0/1)
      rian targets FILE [--require ex,rs,js]   per-function reachability / gate
    """)

    code
  end
end
