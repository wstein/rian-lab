defmodule Rian.CLITest do
  @moduledoc """
  Covers `Rian.CLI.run/1`, the non-halting half of the escript entry point: every
  subcommand dispatch clause plus the usage/unknown-command branches. `main/1`
  itself is just `run/1 |> System.halt/1` and is not exercised here (it would halt
  the test VM).
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Rian.CLI

  # Run the CLI, posting its exit code to the mailbox (assert with `assert_received
  # {:code, n}`) and returning the captured stdout for content assertions.
  defp out_of(argv), do: capture_io(fn -> send(self(), {:code, CLI.run(argv)}) end)

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  setup do
    dir = System.tmp_dir!() |> Path.join("rian_cli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, prog: write(dir, "main.rian", "def main() Int53 := 42\n")}
  end

  describe "usage / help" do
    test "no args prints usage and returns 0" do
      out = capture_io(fn -> send(self(), {:code, CLI.run([])}) end)
      assert_received {:code, 0}
      assert out =~ "rian — the Rian toolchain"
      assert out =~ "rian fmt"
    end

    test "-h and --help both return 0 with usage" do
      for flag <- ["-h", "--help"] do
        out = capture_io(fn -> send(self(), {:code, CLI.run([flag])}) end)
        assert_received {:code, 0}
        assert out =~ "usage:"
      end
    end
  end

  describe "unknown command" do
    test "returns 2 and names the command on stderr" do
      # usage(2) prints its banner to stdout too — the inner capture swallows it
      # while the outer one keeps the stderr message we assert on.
      err =
        capture_io(:stderr, fn ->
          capture_io(fn -> send(self(), {:code, CLI.run(["frobnicate", "x.rian"])}) end)
        end)

      assert_received {:code, 2}
      assert err =~ ~s(unknown command "frobnicate")
    end
  end

  describe "subcommand dispatch" do
    test "fmt delegates to Rian.Format.CLI (already-formatted file → 0)", %{prog: prog} do
      assert out_of(["fmt", "--check", prog]) =~ "already formatted"
      assert_received {:code, 0}
    end

    test "run delegates to Rian.Run and prints the entry value", %{prog: prog} do
      assert out_of(["run", prog]) == "42\n"
    end

    test "check delegates to Rian.Build (valid program → 0)", %{prog: prog} do
      assert out_of(["check", prog]) =~ "ok"
    end

    test "build delegates to Rian.Build (--rust prints source)", %{prog: prog} do
      out = capture_io(fn -> send(self(), {:code, CLI.run(["build", "--rust", prog])}) end)
      assert_received {:code, 0}
      assert out != ""
    end

    test "targets delegates to Rian.Build (reachability report → 0)", %{prog: prog} do
      capture_io(fn -> send(self(), {:code, CLI.run(["targets", prog])}) end)
      assert_received {:code, 0}
    end
  end
end
