defmodule Rian.Format.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Rian.Format.CLI

  setup do
    dir = System.tmp_dir!() |> Path.join("rian_cli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  describe "--stdout" do
    test "formats to stdout and returns 0", %{dir: dir} do
      f = write(dir, "a.rian", "def f(x):=x+1\n")
      code = 0

      out =
        capture_io(fn ->
          send(self(), {:code, CLI.run(["--stdout", f])})
        end)

      assert out == "def f(x) := x + 1\n"
      assert_received {:code, ^code}
    end
  end

  describe "--check" do
    test "returns 0 when already formatted", %{dir: dir} do
      f = write(dir, "ok.rian", "def f(x) := x + 1\n")

      assert capture_io(fn -> send(self(), {:code, CLI.run(["--check", f])}) end) =~
               "already formatted"

      assert_received {:code, 0}
    end

    test "returns 1 when a file differs", %{dir: dir} do
      f = write(dir, "bad.rian", "def f(x):=x+1\n")

      capture_io(:stderr, fn ->
        send(self(), {:code, CLI.run(["--check", f])})
      end)

      assert_received {:code, 1}
    end

    test "returns 1 when a file cannot be lexed", %{dir: dir} do
      f = write(dir, "broken.rian", "def f() := \"unterminated\n")
      capture_io(:stderr, fn -> send(self(), {:code, CLI.run(["--check", f])}) end)
      assert_received {:code, 1}
    end
  end

  describe "--diff" do
    test "prints a unified diff and returns 1", %{dir: dir} do
      f = write(dir, "d.rian", "def f(x):=x+1\n")
      out = capture_io(fn -> send(self(), {:code, CLI.run(["--diff", f])}) end)
      assert out =~ "- def f(x):=x+1"
      assert out =~ "+ def f(x) := x + 1"
      assert_received {:code, 1}
    end
  end

  describe "in place" do
    test "rewrites the file and is idempotent", %{dir: dir} do
      f = write(dir, "p.rian", "def f(x):=x+1\n")
      capture_io(fn -> CLI.run([f]) end)
      assert File.read!(f) == "def f(x) := x + 1\n"
      # second run: unchanged, exit 0
      capture_io(fn -> send(self(), {:code, CLI.run(["--check", f])}) end)
      assert_received {:code, 0}
    end
  end

  describe "robustness" do
    test "unknown option returns 2", %{dir: dir} do
      f = write(dir, "x.rian", "def f() := 1\n")
      capture_io(:stderr, fn -> send(self(), {:code, CLI.run(["--nope", f])}) end)
      assert_received {:code, 2}
    end

    test "no files returns a usage error (2)" do
      capture_io(:stderr, fn -> send(self(), {:code, CLI.run([])}) end)
      assert_received {:code, 2}
    end
  end
end
