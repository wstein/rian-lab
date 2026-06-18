defmodule Mix.Tasks.Rian.CompileTest do
  # async: false — the manifest cases set the global `:rian_manifest` app env (via
  # `Rian.Manifest.with_project`) that `Rian.Reach.gate!/1` reads on every compile.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Rian.Compile

  defp run(args), do: capture_io(fn -> Compile.run(args) end)

  # a tiny project dir holding a `rian.toml` with the given targets + one source file.
  defp project(targets, src) do
    dir = Path.join(System.tmp_dir!(), "rian_proj_#{System.unique_integer([:positive])}")
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

  describe "compiling a real .rian file" do
    test "emits both real targets by default: BEAM bytecode + Rust source" do
      out = run(["examples/area.rian"])
      # BEAM is the canonical path — real bytecode via Rian.Beam, reported by
      # module/exports/size, not printed as text
      assert out =~ "BEAM bytecode"
      assert out =~ "exports area/1"
      assert out =~ "bytes"
      # Rust is the real text target
      assert out =~ "area/1 — Rust"
      assert out =~ "fn area(s: &Shape)"
      # the Elixir text emitter is demoted: not shown unless asked
      refute out =~ "DEBUG text view"
    end

    test "--rust shows only the Rust output" do
      out = run(["examples/area.rian", "--rust"])
      assert out =~ "— Rust"
      refute out =~ "BEAM bytecode"
      refute out =~ "DEBUG text view"
    end

    test "--beam emits BEAM bytecode only and permits Erlang FFI" do
      out = run(["examples/rian/08_lambdas_collections.rian", "--beam"])
      assert out =~ "BEAM bytecode"
      refute out =~ "— Rust"
      refute out =~ "DEBUG text view"
    end

    test "--show-elixir appends the demoted Elixir-text debug view" do
      out = run(["examples/area.rian", "--beam", "--show-elixir"])
      assert out =~ "BEAM bytecode"
      assert out =~ "Elixir (DEBUG text view"
      assert out =~ "def area({:circle, r})"
    end

    test "a module compiles to its own BEAM module keyed by the module name" do
      out = run(["examples/rian/05_modules.rian", "--beam"])
      assert out =~ "Elixir.Geometry"
      assert out =~ "exports"
    end

    test "a module's Rust still lowers under --rust" do
      out = run(["examples/rian/05_modules.rian", "--rust"])
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

  describe "honors the project rian.toml targets (ADR-0080 §2)" do
    # a host-FFI function reaches only :ex (Reach pins it off :rs/:js/:jvm).
    @host_mod "mod M do\n  pub def go() Int53 := :erlang.unique_integer()\nend\n"

    test "a manifest demanding an unreachable target fails the compile" do
      file = project(~s|targets = ["ex", "rs"]|, @host_mod)
      assert_raise Mix.Error, ~r/contract not met/, fn -> run([file, "--beam"]) end
    end

    test "the same function compiles when the manifest declares only the reachable target" do
      file = project(~s|targets = ["ex"]|, @host_mod)
      out = run([file, "--beam"])
      assert out =~ "BEAM bytecode"
    end
  end
end
