defmodule Rian.CLI do
  @moduledoc """
  The `rian` command-line entry point for the self-contained escript
  (`mix escript.build` → a `rian` binary; ADR-0031/0045 Tier 3). Runs with no Mix
  or Elixir toolchain on the host.

  Currently one subcommand:

      rian fmt FILE…            # rewrite each file in place
      rian fmt --check FILE…    # exit non-zero if any file is unformatted / unlexable
      rian fmt --diff FILE…     # print a unified diff of what would change (no write)
      rian fmt --stdout FILE…   # write formatted source to stdout (don't rewrite)
      rian fmt -                # read stdin, write formatted source to stdout

  The actual formatting/diff/check logic lives in `Rian.Format.CLI` so the same
  code backs both this escript and `mix rian.format`; this module only adapts
  argv → exit code via `System.halt/1`.
  """

  @doc "escript entry point."
  def main(argv) do
    argv
    |> dispatch()
    |> System.halt()
  end

  # returns an integer exit code
  defp dispatch(["fmt" | rest]), do: Rian.Format.CLI.run(rest)

  defp dispatch(["-h" | _]), do: usage(0)
  defp dispatch(["--help" | _]), do: usage(0)
  defp dispatch([]), do: usage(0)

  defp dispatch([other | _]) do
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
    """)

    code
  end
end
