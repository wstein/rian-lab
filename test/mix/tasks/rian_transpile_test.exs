defmodule Mix.Tasks.Rian.TranspileTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  # Folder mode writes drafts + prints a triage to stderr; run it against a tmp
  # dir and assert on the files written, swallowing the stderr report.
  defp run_dir(args) do
    capture_io(:stderr, fn -> Mix.Tasks.Rian.Transpile.run(args) end)
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "rian_transpile_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "src"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "folder mode covers both .ex and .exs" do
    test "an .exs source is drafted, written with a .rian extension", %{dir: dir} do
      File.write!(Path.join(dir, "src/lib_mod.ex"), "def double(n) do\n  n * 2\nend")
      File.write!(Path.join(dir, "src/script.exs"), "def triple(n) do\n  n * 3\nend")
      out = Path.join(dir, "out")

      report = run_dir([dir, "-o", out])

      # both files appear in the triage, and both drafts land as `.rian`
      assert report =~ "src/lib_mod.ex"
      assert report =~ "src/script.exs"
      assert File.exists?(Path.join(out, "src/lib_mod.rian"))
      assert File.exists?(Path.join(out, "src/script.rian"))
      # the `.exs` draft is NOT written back under its own extension
      refute File.exists?(Path.join(out, "src/script.exs"))
      assert File.read!(Path.join(out, "src/script.rian")) =~ "pub def triple(n _Unk)"
    end

    test "an empty dir raises mentioning both extensions", %{dir: dir} do
      empty = Path.join(dir, "empty")
      File.mkdir_p!(empty)
      assert_raise Mix.Error, ~r/no \.ex\/\.exs files/, fn -> run_dir([empty]) end
    end
  end
end
