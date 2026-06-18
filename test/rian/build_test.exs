defmodule Rian.BuildTest do
  # async: false — a couple of cases load the emitted `.beam` to prove it's valid.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  alias Rian.Build

  defp tmp_file(src) do
    path = Path.join(System.tmp_dir!(), "rian_build_#{System.unique_integer([:positive])}.rian")
    File.write!(path, src)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "rian_build_ebin_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  describe "build/1 — BEAM" do
    test "writes one loadable `.beam` per module into -o DIR" do
      # a unique module name so loading the built artifact can't collide with a
      # module another test already loaded into the shared VM.
      file = tmp_file("mod RbBeamProbe do\n  pub def main() Int53 := 21 * 2\nend\n")
      dir = tmp_dir()

      out = capture_io(fn -> assert Build.build([file, "-o", dir]) == 0 end)
      beam = Path.join(dir, "Elixir.RbBeamProbe.beam")

      assert out =~ "Elixir.RbBeamProbe.beam"
      assert File.exists?(beam)

      # the emitted bytecode is real: load it and run the entry
      :code.purge(:"Elixir.RbBeamProbe")
      true = :code.add_path(String.to_charlist(dir))
      {:module, mod} = :code.load_file(:"Elixir.RbBeamProbe")
      assert mod.main() == 42
      on_exit(fn -> :code.purge(:"Elixir.RbBeamProbe") && :code.delete(:"Elixir.RbBeamProbe") end)
    end

    test "a flat (top-level) file builds `Elixir.RianCompiled.beam`" do
      file = tmp_file("pub def main() Int53 := 7\n")
      dir = tmp_dir()
      capture_io(fn -> assert Build.build([file, "-o", dir]) == 0 end)
      assert File.exists?(Path.join(dir, "Elixir.RianCompiled.beam"))
    end

    test "a type error → exit 2, nothing written" do
      file = tmp_file("pub def main() Bool := 1 + 1\n")
      dir = tmp_dir()
      capture_io(:stderr, fn -> assert Build.build([file, "-o", dir]) == 2 end)
      refute File.dir?(dir) and File.ls!(dir) != []
    end
  end

  describe "build/1 — foreign-file resolution (ADR-0080 §7)" do
    test "fails closed (exit 2) on a missing @external file-reference" do
      file =
        tmp_file(
          ~S|@external(:js, "./absent.ffi.mjs", "fun") pub def main(x Int53) Int53| <> "\n"
        )

      err = capture_io(:stderr, fn -> assert Build.build([file, "--js"]) == 2 end)
      assert err =~ "absent.ffi.mjs"
      assert err =~ "does not exist"
    end

    test "bundles a :ex file-reference: the .ffi.ex compiles beside the app and the call runs" do
      src_dir = Path.join(System.tmp_dir!(), "rian_ffi_src_#{System.unique_integer([:positive])}")
      File.mkdir_p!(src_dir)
      on_exit(fn -> File.rm_rf(src_dir) end)

      File.write!(
        Path.join(src_dir, "RbFfiCodec.ffi.ex"),
        "defmodule RbFfiCodec do\n  def twice(x), do: x * 2\nend\n"
      )

      rian = Path.join(src_dir, "prog.rian")

      File.write!(
        rian,
        ~S|@external(:ex, "./RbFfiCodec.ffi.ex", "twice") pub def main(x Int53) Int53| <> "\n"
      )

      dir = tmp_dir()
      out = capture_io(fn -> assert Build.build([rian, "-o", dir]) == 0 end)

      # both the Rian module and the bundled foreign module are written
      assert out =~ "Elixir.RianCompiled.beam"
      assert File.exists?(Path.join(dir, "Elixir.RianCompiled.beam"))
      assert File.exists?(Path.join(dir, "Elixir.RbFfiCodec.beam"))

      # the bundled artifact is real: load both and run the entry through the FFI
      for atom <- [:"Elixir.RbFfiCodec", :"Elixir.RianCompiled"], do: :code.purge(atom)
      true = :code.add_path(String.to_charlist(dir))
      {:module, _} = :code.load_file(:"Elixir.RbFfiCodec")
      {:module, mod} = :code.load_file(:"Elixir.RianCompiled")
      assert mod.main(21) == 42

      on_exit(fn ->
        for atom <- [:"Elixir.RianCompiled", :"Elixir.RbFfiCodec"] do
          :code.purge(atom) && :code.delete(atom)
        end
      end)
    end
  end

  describe "build/1 — source targets" do
    test "--rust prints Rust source" do
      file = tmp_file("def add(a Int53, b Int53) Int53 := a + b\n")
      out = capture_io(fn -> assert Build.build([file, "--rust"]) == 0 end)
      assert out =~ "fn add"
    end

    test "--js prints ECMAScript source" do
      file = tmp_file("def add(a Int53, b Int53) Int53 := a + b\n")
      out = capture_io(fn -> assert Build.build([file, "--js"]) == 0 end)
      assert out =~ "function add"
    end
  end

  describe "check/1" do
    test "a well-typed file → `ok`, exit 0" do
      file = tmp_file("def f(n Int53) Int53 := n + 1\n")
      out = capture_io(fn -> assert Build.check([file]) == 0 end)
      assert out =~ "ok"
    end

    test "a type error → stderr, exit 1" do
      file = tmp_file("def f(n Int64) Bool := n + 1\n")
      err = capture_io(:stderr, fn -> assert Build.check([file]) == 1 end)
      assert err =~ "declared return type is `Bool`"
    end
  end

  describe "targets/1" do
    test "report only (no --require) → exit 0" do
      file = tmp_file("def f(a Int53, b Int53) Int53 := a + b\n")
      out = capture_io(fn -> assert Build.targets([file]) == 0 end)
      assert out =~ "f/2:"
      assert out =~ "rs"
    end

    test "--require with a gap → reported, exit 1" do
      # a bitstring is BEAM-only (ADR-0078) → cannot reach :rs
      file = tmp_file("def hdr(x Int53) Binary := <<x::8>>\n")
      err = capture_io(:stderr, fn -> assert Build.targets([file, "--require", "ex,rs"]) == 1 end)
      assert err =~ "missing"
    end

    test "--require fully satisfied → exit 0" do
      file = tmp_file("def f(a Int53, b Int53) Int53 := a + b\n")
      out = capture_io(fn -> assert Build.targets([file, "--require", "ex,rs,js"]) == 0 end)
      assert out =~ "reach"
    end
  end

  describe "usage / errors" do
    test "build with no file → exit 2" do
      capture_io(:stderr, fn -> assert Build.build([]) == 2 end)
    end

    test "build with an unknown option → exit 2" do
      file = tmp_file("def f() Int53 := 1\n")
      capture_io(:stderr, fn -> assert Build.build([file, "--nope"]) == 2 end)
    end

    test "build on a missing file → exit 2 with a posix error message" do
      err = capture_io(:stderr, fn -> assert Build.build(["/no/such/file.rian"]) == 2 end)
      assert err =~ "no such file"
    end

    test "check with the wrong number of args → usage, exit 2" do
      capture_io(:stderr, fn -> assert Build.check([]) == 2 end)
      capture_io(:stderr, fn -> assert Build.check(["a.rian", "b.rian"]) == 2 end)
    end

    test "targets with no file → usage, exit 2" do
      capture_io(:stderr, fn -> assert Build.targets([]) == 2 end)
    end

    test "targets on a missing file → exit 2 with a posix error message" do
      err = capture_io(:stderr, fn -> assert Build.targets(["/no/such/file.rian"]) == 2 end)
      assert err =~ "no such file"
    end

    test "targets on an unparseable file → exit 2 with the parse error" do
      file = tmp_file("def f( := \n")
      err = capture_io(:stderr, fn -> assert Build.targets([file]) == 2 end)
      assert err =~ "targets:"
    end
  end
end
