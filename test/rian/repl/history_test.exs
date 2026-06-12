defmodule Rian.Repl.HistoryTest do
  use ExUnit.Case, async: false

  alias Rian.Repl.History

  setup do
    path = Path.join(System.tmp_dir!(), "rian_history_#{System.unique_integer([:positive])}")
    Application.put_env(:rian_lab, :history_file, path)

    on_exit(fn ->
      Application.delete_env(:rian_lab, :history_file)
      File.rm(path)
    end)

    {:ok, path: path}
  end

  test "a missing file loads as empty" do
    assert History.load() == []
  end

  test "add/1 then load/0 round-trips a line as a charlist" do
    assert History.add("x := 1\n") == :ok
    assert History.load() == [~c"x := 1"]
  end

  test "entries persist newest-last across adds" do
    History.add("first")
    History.add("second")
    assert History.load() == [~c"first", ~c"second"]
  end

  test "blank lines are dropped" do
    History.add("kept")
    History.add("   \n")
    History.add("\n")
    assert History.load() == [~c"kept"]
  end

  test "an immediate repeat of the previous line is dropped" do
    History.add("dup")
    History.add("dup")
    History.add("other")
    History.add("dup")
    assert History.load() == [~c"dup", ~c"other", ~c"dup"]
  end

  test "load tolerates an unreadable path" do
    Application.put_env(:rian_lab, :history_file, "/nonexistent-dir/nope/rian_history")
    assert History.load() == []
  end

  test "path/0 honors the RIAN_HISTORY env var when no app env is set" do
    Application.delete_env(:rian_lab, :history_file)
    System.put_env("RIAN_HISTORY", "/tmp/from-env-rian-history")
    assert History.path() == "/tmp/from-env-rian-history"
  after
    System.delete_env("RIAN_HISTORY")
  end
end
