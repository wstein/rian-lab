defmodule Rian.RunTest do
  # async: false — `Rian.Run` loads compiled modules into the VM (global state).
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  alias Rian.Run

  defp tmp(src) do
    path = Path.join(System.tmp_dir!(), "rian_run_#{System.unique_integer([:positive])}.rian")
    File.write!(path, src)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "eval/2" do
    test "runs a `mod`'s main/0" do
      assert Run.eval("mod M do\n  pub def main() Int53 := 21 * 2\nend\n") == {:ok, 42}
    end

    test "runs a flat (top-level `def`) program's main/0" do
      assert Run.eval("pub def main() Int53 := 6 * 7\n") == {:ok, 42}
    end

    test "`--main` selects a different zero-arg entry" do
      src = ~s|mod M do\n  pub def demo() String := "hi" <> "!"\nend\n|
      assert Run.eval(src, "demo") == {:ok, "hi!"}
    end

    test "a cross-`mod` call resolves at runtime" do
      src = """
      mod Lib do
        pub def double(n Int53) Int53 := n * 2
      end

      mod Main do
        pub def main() Int53 := Lib.double(21)
      end
      """

      assert Run.eval(src) == {:ok, 42}
    end

    test "no entry → {:error, …} (not a raise)" do
      assert {:error, msg} = Run.eval("mod M do\n  pub def f() Int53 := 1\nend\n")
      assert msg =~ "no zero-arg entry `main`"
    end

    test "a compile error (type mismatch) is reported as {:error, …}, not a raise" do
      assert {:error, msg} = Run.eval("pub def main() Bool := 1 + 1\n")
      assert msg =~ "declared return type is `Bool`"
    end

    test "a *runtime* error in the entry propagates (its stacktrace is not swallowed)" do
      assert_raise ArithmeticError, fn -> Run.eval("pub def main() Int53 := 1 div 0\n") end
    end

    test "an entry defined in more than one module → {:error, …}" do
      src = """
      mod A do
        pub def main() Int53 := 1
      end

      mod B do
        pub def main() Int53 := 2
      end
      """

      assert {:error, msg} = Run.eval(src)
      assert msg =~ "defined in more than one module"
    end
  end

  describe "run_file/2" do
    test "reads + runs a file" do
      assert Run.run_file(tmp("pub def main() Int53 := 42\n")) == {:ok, 42}
    end

    test "a missing file → {:error, …}" do
      assert {:error, msg} = Run.run_file("/no/such/file.rian")
      assert msg =~ "cannot read"
    end

    test "bundles a `@external(:ex)` file-reference and runs the call end-to-end" do
      # the full build pipeline through `run`: the foreign `.ffi.ex` is resolved,
      # compiled+loaded, the external rewritten to a module-reference, and the entry
      # (which calls the external) actually executes (ADR-0080 §7 / ADR-0068).
      dir = Path.join(System.tmp_dir!(), "rian_run_ffi_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      File.write!(
        Path.join(dir, "RunFfiCodec.ffi.ex"),
        "defmodule RunFfiCodec do\n  def twice(x), do: x * 2\nend\n"
      )

      path = Path.join(dir, "prog.rian")

      File.write!(
        path,
        ~S|@external(:ex, "./RunFfiCodec.ffi.ex", "twice") pub def twice(x Int53) Int53| <>
          "\npub def main() Int53 := twice(21)\n"
      )

      on_exit(fn ->
        for atom <- [:"Elixir.RianCompiled", :"Elixir.RunFfiCodec"] do
          :code.purge(atom) && :code.delete(atom)
        end
      end)

      assert Run.run_file(path) == {:ok, 42}
    end

    test "a multi-dir project resolves file-references against the project root (rian.toml)" do
      # layout: root/rian.toml, root/ffi/Codec.ffi.ex, root/src/app.rian. The entry
      # sits in src/ but references the FFI project-root-relative (`ffi/…`), which
      # resolves because the base is the manifest's dir, not the entry's (ADR-0080 §7).
      root = Path.join(System.tmp_dir!(), "rian_run_proj_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "ffi"))
      File.mkdir_p!(Path.join(root, "src"))
      on_exit(fn -> File.rm_rf(root) end)

      File.write!(Path.join(root, "rian.toml"), ~s|[project]\nname = "x"\nversion = "1"\n|)

      File.write!(
        Path.join([root, "ffi", "RunMfCodec.ffi.ex"]),
        "defmodule RunMfCodec do\n  def twice(x), do: x * 2\nend\n"
      )

      entry = Path.join([root, "src", "app.rian"])

      File.write!(
        entry,
        ~S|@external(:ex, "ffi/RunMfCodec.ffi.ex", "twice") pub def twice(x Int53) Int53| <>
          "\npub def main() Int53 := twice(21)\n"
      )

      on_exit(fn ->
        for atom <- [:"Elixir.RianCompiled", :"Elixir.RunMfCodec"] do
          :code.purge(atom) && :code.delete(atom)
        end
      end)

      assert Run.run_file(entry) == {:ok, 42}
    end

    test "a file-reference with no usable base dir (string eval) is a clear error" do
      src =
        ~S|@external(:ex, "./x.ffi.ex", "go") pub def go(x Int53) Int53| <>
          "\npub def main() Int53 := go(1)\n"

      assert {:error, msg} = Run.eval(src)
      assert msg =~ "needs a source file path"
    end
  end

  describe "cli/1 (the `rian run` escript adapter) — exit codes" do
    test "ok → prints the value to stdout, exit 0" do
      file = tmp("pub def main() Int53 := 42\n")
      out = capture_io(fn -> assert Run.cli([file]) == 0 end)
      assert out == "42\n"
    end

    test "no entry → error on stderr, exit 1" do
      file = tmp("mod M do\n  pub def f() Int53 := 1\nend\n")
      err = capture_io(:stderr, fn -> assert Run.cli([file]) == 1 end)
      assert err =~ "no zero-arg entry"
    end

    test "no file → usage on stderr, exit 2" do
      err = capture_io(:stderr, fn -> assert Run.cli([]) == 2 end)
      assert err =~ "usage: rian run"
    end

    test "unknown option → exit 2" do
      file = tmp("pub def main() Int53 := 1\n")
      err = capture_io(:stderr, fn -> assert Run.cli([file, "--nope"]) == 2 end)
      assert err =~ "unknown option"
    end

    test "`--main` selects the entry and prints its value, exit 0" do
      file = tmp(~s|mod M do\n  pub def demo() String := "hi!"\nend\n|)
      out = capture_io(fn -> assert Run.cli([file, "--main", "demo"]) == 0 end)
      assert out == ~s("hi!"\n)
    end

    test "more than one file → error on stderr, exit 2" do
      a = tmp("pub def main() Int53 := 1\n")
      b = tmp("pub def main() Int53 := 2\n")
      err = capture_io(:stderr, fn -> assert Run.cli([a, b]) == 2 end)
      assert err =~ "run one file at a time"
    end
  end
end
