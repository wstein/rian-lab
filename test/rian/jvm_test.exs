defmodule Rian.JVMTest do
  use ExUnit.Case, async: true

  alias Rian.JVM

  # Compile emitted Kotlin with `kotlinc` and run the resulting jar with `java`;
  # returns the trimmed stdout, or `:no_jvm` when the toolchain is absent (CI may
  # lack it — JVM is ADR-0049 Tier 2, non-blocking — so the *shape* assertions
  # still run unconditionally and only the run is skipped). kotlinc is slow, so a
  # test compiles one jar and may probe several `println`s through it.
  defp kotlin_run(kt, main) do
    kotlinc = System.find_executable("kotlinc")
    java = System.find_executable("java")

    if kotlinc && java do
      base = Path.join(System.tmp_dir!(), "rian_jvm_#{System.unique_integer([:positive])}")
      src = base <> ".kt"
      jar = base <> ".jar"
      File.write!(src, kt <> "\n\nfun main() {\n" <> main <> "\n}\n")

      {_, 0} = System.cmd(kotlinc, [src, "-include-runtime", "-d", jar], stderr_to_stdout: true)
      {out, 0} = System.cmd(java, ["-jar", jar])
      File.rm(src)
      File.rm(jar)
      String.trim(out)
    else
      :no_jvm
    end
  end

  describe "Kotlin/JVM emitter on the typed core IR (ADR-0049 Tier 2 / ADR-0050)" do
    test "a one-liner: Int64 -> Long, single-clause function" do
      kt = JVM.compile("def double(n Int64) Int64 := n * 2")
      assert kt =~ "fun double(a0: Long): Long"
      assert kt =~ "(n * 2L)"
    end

    test "a multi-clause function lowers to an if-dispatcher with Long literals" do
      kt =
        JVM.compile("""
        def fib(n Int64) Int64
        def fib(0) := 0
        def fib(1) := 1
        def fib(n) := fib(n - 1) + fib(n - 2)
        """)

      assert kt =~ "if (a0 == 0L)"
      assert kt =~ "if (a0 == 1L)"

      case kotlin_run(kt, ~s|println(fib(10L))|) do
        :no_jvm -> :ok
        out -> assert out == "55"
      end
    end

    test "a sum type lowers to a sealed interface + data classes" do
      kt = JVM.compile("type Color := Red | Green | RGB(Int64, Int64, Int64)")
      assert kt =~ "sealed interface Color"
      assert kt =~ "object Red : Color"
      assert kt =~ "data class RGB(val f0: Long, val f1: Long, val f2: Long) : Color"
    end

    test "the self-hosting optimizer lowers to Kotlin and folds under java (multi-target)" do
      kt = JVM.compile(File.read!("examples/rian/selfhost_opt.rian"))
      # the Kotlin showcase: sealed hierarchy + smart-cast `is` patterns
      assert kt =~ "sealed interface Expr"
      assert kt =~ "if (a0 is Add)"
      assert kt =~ "if (a0 is Num && a0.f0 == 0L)"

      main = """
        println(fold(Mul(Add(Num(2L), Num(3L)), Num(4L))))
        println(fold(Mul(Var("x"), Num(1L))))
      """

      case kotlin_run(kt, main) do
        :no_jvm -> :ok
        # (2+3)*4 constant-folds to Num(20); x*1 simplifies to Var("x")
        out -> assert out == "Num(f0=20)\nVar(f0=x)"
      end
    end

    test "an unsupported construct raises rather than miscompiling" do
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("def f(s String) Vec(Int64) := String.to_charlist(s)")
      end
    end
  end
end
