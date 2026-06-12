defmodule Mix.Tasks.Rian.CompileTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Rian.Compile

  defp run(args), do: capture_io(fn -> Compile.run(args) end)

  describe "compiling a real .rian file" do
    test "emits both targets by default" do
      out = run(["examples/area.rian"])
      assert out =~ "══ area ══"
      assert out =~ "── Elixir ──"
      assert out =~ "def area({:circle, r})"
      assert out =~ "── Rust ──"
      assert out =~ "fn area(s: &Shape)"
    end

    test "--rust shows only the Rust output" do
      out = run(["examples/area.rian", "--rust"])
      assert out =~ "── Rust ──"
      refute out =~ "── Elixir ──"
    end

    test "--beam emits Elixir only and permits Erlang FFI" do
      out = run(["examples/rian/08_lambdas_collections.rian", "--beam"])
      assert out =~ "── Elixir ──"
      refute out =~ "── Rust ──"
    end

    test "a module lowers to one unit keyed by the module name" do
      out = run(["examples/rian/05_modules.rian"])
      assert out =~ "══ Geometry ══"
      assert out =~ "defmodule Geometry do"
      assert out =~ "mod geometry {"
    end
  end

  describe "errors exit non-zero (Mix.Error)" do
    test "a missing file" do
      assert_raise Mix.Error, ~r/no such file/, fn -> run(["does_not_exist.rian"]) end
    end

    test "no file argument" do
      assert_raise Mix.Error, ~r/usage:/, fn -> run([]) end
    end

    test "a type-check error surfaces with the file name" do
      path = Path.join(System.tmp_dir!(), "rian_bad_#{System.unique_integer([:positive])}.rian")
      File.write!(path, "def f(n Int64) Bool := n + 1\n")

      try do
        assert_raise Mix.Error, ~r/declared return type is `Bool`/, fn -> run([path]) end
      after
        File.rm(path)
      end
    end
  end
end
