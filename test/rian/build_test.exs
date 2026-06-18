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

  describe "build/1 — BEAM OTP package (ADR-0082 step 2)" do
    test "-o ROOT packages an OTP app under _build/ex/ — loadable beams + valid rebar.config/.app.src" do
      # a unique module name so loading the built artifact can't collide with a
      # module another test already loaded into the shared VM.
      file = tmp_file("mod RbBeamProbe do\n  pub def main() Int53 := 21 * 2\nend\n")
      dir = tmp_dir()

      out = capture_io(fn -> assert Build.build([file, "-o", dir]) == 0 end)
      ex = Path.join([dir, "_build", "ex"])
      ebin = Path.join(ex, "ebin")
      beam = Path.join(ebin, "Elixir.RbBeamProbe.beam")

      assert out =~ "Elixir.RbBeamProbe.beam"
      assert File.exists?(beam)

      # the generated manifests are well-formed Erlang terms
      assert {:ok, [_ | _]} = :file.consult(String.to_charlist(Path.join(ex, "rebar.config")))
      [app_src] = Path.wildcard(Path.join([ex, "src", "*.app.src"]))
      assert {:ok, [{:application, _name, kw}]} = :file.consult(String.to_charlist(app_src))
      assert :"Elixir.RbBeamProbe" in Keyword.fetch!(kw, :modules)

      # the packaged bytecode is real: load it from ebin/ and run the entry
      :code.purge(:"Elixir.RbBeamProbe")
      true = :code.add_path(String.to_charlist(ebin))
      {:module, mod} = :code.load_file(:"Elixir.RbBeamProbe")
      assert mod.main() == 42
      on_exit(fn -> :code.purge(:"Elixir.RbBeamProbe") && :code.delete(:"Elixir.RbBeamProbe") end)
    end

    test "a flat (top-level) file packages `Elixir.RianCompiled.beam` into _build/ex/ebin/" do
      file = tmp_file("pub def main() Int53 := 7\n")
      dir = tmp_dir()
      capture_io(fn -> assert Build.build([file, "-o", dir]) == 0 end)
      assert File.exists?(Path.join([dir, "_build", "ex", "ebin", "Elixir.RianCompiled.beam"]))
    end

    test "a type error → exit 2, nothing written" do
      file = tmp_file("pub def main() Bool := 1 + 1\n")
      dir = tmp_dir()
      capture_io(:stderr, fn -> assert Build.build([file, "-o", dir]) == 2 end)
      refute File.exists?(Path.join(dir, "_build"))
    end

    @tag :rebar
    test "the generated OTP project builds through rebar3 (invariant 4)" do
      case System.find_executable("rebar3") do
        nil ->
          :ok

        rebar3 ->
          file = tmp_file("mod RbRebarProbe do\n  pub def answer() Int53 := 42\nend\n")
          dir = tmp_dir()
          capture_io(fn -> assert Build.build([file, "-o", dir]) == 0 end)

          ex = Path.join([dir, "_build", "ex"])
          {res, code} = System.cmd(rebar3, ["compile"], cd: ex, stderr_to_stdout: true)
          assert code == 0, "rebar3 compile failed:\n#{res}"
      end
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
      ebin = Path.join([dir, "_build", "ex", "ebin"])

      # both the Rian module and the bundled foreign module are packaged into ebin/
      assert out =~ "Elixir.RianCompiled.beam"
      assert File.exists?(Path.join(ebin, "Elixir.RianCompiled.beam"))
      assert File.exists?(Path.join(ebin, "Elixir.RbFfiCodec.beam"))

      # the bundled artifact is real: load both and run the entry through the FFI
      for atom <- [:"Elixir.RbFfiCodec", :"Elixir.RianCompiled"], do: :code.purge(atom)
      true = :code.add_path(String.to_charlist(ebin))
      {:module, _} = :code.load_file(:"Elixir.RbFfiCodec")
      {:module, mod} = :code.load_file(:"Elixir.RianCompiled")
      assert mod.main(21) == 42

      on_exit(fn ->
        for atom <- [:"Elixir.RianCompiled", :"Elixir.RbFfiCodec"] do
          :code.purge(atom) && :code.delete(atom)
        end
      end)
    end

    @tag :js
    test "bundles a :js file-reference: writes the .mjs, copies the .ffi.mjs, runs under node" do
      src_dir = Path.join(System.tmp_dir!(), "rian_ffi_js_#{System.unique_integer([:positive])}")
      File.mkdir_p!(src_dir)
      on_exit(fn -> File.rm_rf(src_dir) end)

      File.write!(
        Path.join(src_dir, "codec.ffi.mjs"),
        "export function encode(x) { return x + 1; }\n"
      )

      rian = Path.join(src_dir, "prog.rian")

      File.write!(
        rian,
        ~S|@external(:js, "./codec.ffi.mjs", "encode") pub def enc(x val Int53) Int53| <> "\n"
      )

      out_dir = tmp_dir()
      out = capture_io(fn -> assert Build.build([rian, "--js", "-o", out_dir]) == 0 end)

      assert out =~ "prog.mjs"
      mjs = Path.join(out_dir, "prog.mjs")
      assert File.read!(mjs) =~ ~s|import { encode } from "./codec.ffi.mjs";|
      # the foreign file is copied beside the output so the relative import resolves
      assert File.exists?(Path.join(out_dir, "codec.ffi.mjs"))

      case System.find_executable("node") do
        nil ->
          :ok

        node ->
          runner = Path.join(out_dir, "run.mjs")

          File.write!(
            runner,
            ~s|import { enc } from "./prog.mjs";\nconsole.log(String(enc(41)));\n|
          )

          {res, 0} = System.cmd(node, [runner])
          assert String.trim(res) == "42"
      end
    end

    @tag :rust
    test "packages a Rust crate under _build/rs/ — Cargo.toml + wired FFI, builds via cargo (ADR-0082)" do
      src_dir = Path.join(System.tmp_dir!(), "rian_pkg_rs_#{System.unique_integer([:positive])}")
      File.mkdir_p!(src_dir)
      on_exit(fn -> File.rm_rf(src_dir) end)

      # the project manifest is the single source of the generated Cargo.toml (invariant 1)
      File.write!(
        Path.join(src_dir, "rian.toml"),
        ~s([project]\nname = "demo_pkg"\nversion = "0.2.0"\nlicense = "Apache-2.0"\n)
      )

      File.write!(Path.join(src_dir, "codec.ffi.rs"), "pub fn encode(x: i64) -> i64 { x + 1 }\n")
      rian = Path.join(src_dir, "prog.rian")

      File.write!(
        rian,
        ~S|@external(:rs, "./codec.ffi.rs", "encode") pub def enc(x val Int64) Int64| <> "\n"
      )

      out = tmp_dir()
      _ = capture_io(fn -> assert Build.build([rian, "--rust", "-o", out]) == 0 end)

      crate = Path.join([out, "_build", "rs"])
      cargo_toml = File.read!(Path.join(crate, "Cargo.toml"))
      assert cargo_toml =~ ~s(name = "demo_pkg")
      assert cargo_toml =~ ~s(version = "0.2.0")
      assert cargo_toml =~ "[lib]"

      lib = File.read!(Path.join(crate, "src/lib.rs"))
      assert lib =~ ~s|#[path = "codec.ffi.rs"] mod codec;|
      # the FFI file is wired into the crate's src/ where the `#[path] mod` resolves it
      assert File.exists?(Path.join(crate, "src/codec.ffi.rs"))

      case System.find_executable("cargo") do
        nil ->
          :ok

        cargo ->
          {res, code} =
            System.cmd(cargo, ["build", "--manifest-path", Path.join(crate, "Cargo.toml")],
              stderr_to_stdout: true,
              env: [{"CARGO_TERM_COLOR", "never"}]
            )

          assert code == 0, "cargo build failed:\n#{res}"
      end
    end

    @tag :jvm
    test "bundles a :jvm file-reference: copies the .ffi.kt, compiles + runs under kotlinc/java" do
      kotlinc = System.find_executable("kotlinc")
      java = System.find_executable("java")

      src_dir = Path.join(System.tmp_dir!(), "rian_ffi_kt_#{System.unique_integer([:positive])}")
      File.mkdir_p!(src_dir)
      on_exit(fn -> File.rm_rf(src_dir) end)

      File.write!(
        Path.join(src_dir, "codec.ffi.kt"),
        "fun encode(x: Long): Long { return x + 1 }\n"
      )

      rian = Path.join(src_dir, "prog.rian")

      File.write!(
        rian,
        ~S|@external(:jvm, "./codec.ffi.kt", "encode") pub def enc(x val Int64) Int64| <> "\n"
      )

      out_dir = tmp_dir()
      out = capture_io(fn -> assert Build.build([rian, "--jvm", "-o", out_dir]) == 0 end)

      assert out =~ "prog.kt"
      assert File.read!(Path.join(out_dir, "prog.kt")) =~ "return encode(x)"
      # the foreign file is copied beside the output so it compiles in the same package
      assert File.exists?(Path.join(out_dir, "codec.ffi.kt"))

      if kotlinc && java do
        File.write!(Path.join(out_dir, "runner.kt"), "fun main() { println(enc(41L)) }\n")
        jar = Path.join(out_dir, "bundle.jar")
        files = Path.wildcard(Path.join(out_dir, "*.kt"))

        {_, 0} =
          System.cmd(kotlinc, files ++ ["-include-runtime", "-d", jar], stderr_to_stdout: true)

        {res, 0} = System.cmd(java, ["-jar", jar])
        assert String.trim(res) == "42"
      end
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
