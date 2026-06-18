defmodule Mix.Tasks.Rian.RunTest do
  # async: false — the manifest cases set the global `:rian_manifest` app env (via
  # `Rian.Manifest.with_project`) that `Rian.Reach.gate!/1` reads on every compile.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Rian.Run

  defp run(args), do: capture_io(fn -> Run.run(args) end)

  # a tiny project dir holding a `rian.toml` with the given targets + one source file.
  defp project(targets, src) do
    dir = Path.join(System.tmp_dir!(), "rian_runproj_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    File.write!(
      Path.join(dir, "rian.toml"),
      ~s|[project]\nname = "x"\nversion = "1"\n#{targets}\n|
    )

    file = Path.join(dir, "p.rian")
    File.write!(file, src)
    file
  end

  # a host-FFI `main/0` reaching only :ex, with a deterministic value (42).
  @host_main "mod M do\n  pub def main() Int53 := :erlang.abs(-42)\nend\n"

  describe "running a .rian file" do
    test "prints the entry's value" do
      file = project(~s|targets = ["ex"]|, "pub def main() Int53 := 21 * 2\n")
      assert run([file]) =~ "42"
    end

    test "a missing file is a Mix error" do
      assert_raise Mix.Error, ~r/no such file/, fn -> run(["nope.rian"]) end
    end
  end

  describe "honors the project rian.toml targets (ADR-0080 §2)" do
    test "a manifest demanding an unreachable target fails the run" do
      file = project(~s|targets = ["ex", "rs"]|, @host_main)
      assert_raise Mix.Error, ~r/contract not met/, fn -> run([file]) end
    end

    test "the same entry runs when the manifest declares only the reachable target" do
      file = project(~s|targets = ["ex"]|, @host_main)
      assert run([file]) =~ "42"
    end
  end
end
