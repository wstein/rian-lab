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

    test "a type error is caught by the gate, not emitted as malformed Kotlin (parity)" do
      # JVM.compile now runs `Check.gate!` before emitting (parity with the BEAM path).
      assert_raise Rian.Check.Error, fn -> JVM.compile("def f() Int64 := true") end
    end

    test "float `/` lowers to Kotlin Double division (integer `div` stays `/` on Long)" do
      kt = JVM.compile("def half(x Float64) Float64 := x / 2.0")
      assert kt =~ "fun half(a0: Double): Double"
      assert kt =~ "(x / 2.0)"

      case kotlin_run(kt, ~s|println(half(7.0))|) do
        :no_jvm -> :ok
        out -> assert out == "3.5"
      end
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

    test "a `ref` param is lowered to value semantics (sound: return-based surface)" do
      # `ref` (&mut) has no Kotlin analog; it only ever changed the Rust signature,
      # so JVM emits an ordinary `val` binding. Reach reports `ref` as reaching :jvm,
      # so this MUST compile (not raise), and the cap must not leak into the emitted
      # parameter. Locks the documented value-lowering decision against a future
      # in-place-mutation primitive silently miscompiling here.
      kt = JVM.compile("def bump(x ref Int64) Int64 := x + 1")
      assert kt =~ "fun bump(a0: Long): Long"
      assert kt =~ "val x = a0"

      case kotlin_run(kt, ~s|println(bump(41L))|) do
        :no_jvm -> :ok
        out -> assert out == "42"
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

  describe "JVM jar assembly (rung B, ADR-0062)" do
    test "to_jar produces a runnable jar that runs under java" do
      case {System.find_executable("kotlinc"), System.find_executable("java")} do
        {nil, _} ->
          :ok

        {_, nil} ->
          :ok

        {_, java} ->
          jar =
            Path.join(System.tmp_dir!(), "rian_jartest_#{System.unique_integer([:positive])}.jar")

          {:ok, ^jar} = JVM.to_jar("def answer() Int64 := 6 * 7", jar, main: "answer")
          assert File.exists?(jar)
          {out, 0} = System.cmd(java, ["-jar", jar])
          assert String.trim(out) == "42"
          File.rm(jar)
      end
    end
  end

  describe "clause heads: guards, char patterns, and unsupported patterns" do
    test "a `when` guard lowers to a guarded `if (cond) { return .. }`" do
      kt =
        JVM.compile("""
        def classify(n Int64) Int64
        def classify(n) when n > 0 := 1
        def classify(n) := 0
        """)

      # the guard becomes an inner `if (..) { return .. }` (jvm.ex:149); the
      # binding for the guarded clause is emitted alongside it (jvm.ex:155/174)
      assert kt =~ "if ((n > 0L)) { return 1L }"
      assert kt =~ "val n = a0;"
    end

    test "a char-literal pattern in a clause head matches on the codepoint" do
      kt =
        JVM.compile("""
        def kind(c Char) Int64
        def kind('a') := 1
        def kind(c) := 0
        """)

      # 'a' is codepoint 97, matched as a `Long` (jvm.ex:157)
      assert kt =~ "if (a0 == 97L) { return 1L }"

      case kotlin_run(kt, ~s|println(kind(97L)); println(kind(98L))|) do
        :no_jvm -> :ok
        out -> assert out == "1\n0"
      end
    end

    test "an unsupported clause pattern (a list pattern) raises" do
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("""
        def head(xs Vec(Int64)) Int64
        def head([x]) := x
        def head(xs) := 0
        """)
      end
    end
  end

  describe "literal and unary expressions" do
    test "a char-literal expression emits a `Long` codepoint" do
      kt = JVM.compile("def z(n Char) Char := 'z'")
      # 'z' is codepoint 122 (jvm.ex:199)
      assert kt =~ "return 122L"
    end

    test "a string-literal expression emits a quoted Kotlin string" do
      kt = JVM.compile(~s|def greet(n Int64) String := "hi"|)
      # (jvm.ex:200)
      assert kt =~ ~s|return "hi"|
    end

    test "boolean literals pass through as `true`/`false`" do
      kt = JVM.compile("def yes(n Int64) Bool := true")
      # (jvm.ex:201)
      assert kt =~ "return true"
    end

    test "unary negation emits `-x`" do
      kt = JVM.compile("def neg(x Int64) Int64 := -x")
      # (jvm.ex:204)
      assert kt =~ "return -x"
    end

    test "logical `not` emits `!x`" do
      kt = JVM.compile("def flip(x Bool) Bool := not x")
      # (jvm.ex:205)
      assert kt =~ "return !x"
    end
  end

  describe "if-expressions and blocks" do
    test "an if-expression with a block then-branch emits `run { .. }`" do
      kt = JVM.compile("def step(n Int64) Int64 := if n > 0 do a := n * 2; a + 1 else 0 end")

      # the if-expression itself (jvm.ex:216), a multi-statement block branch
      # (jvm.ex:221 -> block_value -> stmt_kt :bind jvm.ex:190 + stmt_value jvm.ex:193),
      # and a bare-expression else-branch (jvm.ex:222)
      assert kt =~ "if ((n > 0L)) run { val a = (n * 2L); (a + 1L) } else 0L"

      case kotlin_run(kt, ~s|println(step(3L)); println(step(-1L))|) do
        :no_jvm -> :ok
        out -> assert out == "7\n0"
      end
    end

    test "a single-expression if-branch needs no `run` wrapper" do
      kt = JVM.compile("def sign(n Int64) Int64 := if n >= 0 do 1 else -1 end")
      # both branches are single-expr blocks (jvm.ex:220)
      assert kt =~ "if ((n >= 0L)) 1L else -1L"
    end

    test "a typed bind inside a block emits a `val`" do
      kt = JVM.compile("def st(n Int64) Int64 := if n > 0 do a Int64 := 100; n + a else 0 end")
      # the typed_bind statement (jvm.ex:191)
      assert kt =~ "run { val a = 100L; (n + a) }"
    end

    test "a statement-expression inside a block is emitted then discarded" do
      kt = JVM.compile("def se(n Int64) Int64 := if n > 0 do n + 1; n * 2 else 0 end")
      # a bare-expr statement (jvm.ex:192), with the final expr as the value (jvm.ex:193)
      assert kt =~ "run { (n + 1L); (n * 2L) }"
    end
  end

  describe "operators" do
    test "comparison, equality, logical, concat and rem map to Kotlin operators" do
      kt =
        JVM.compile("""
        def both(a Int64, b Int64) Bool := (a == b) and (a != b) or (a < b)
        """)

      # ==, !=, and->&&, or->|| (jvm.ex:233-236)
      assert kt =~ "(((a == b) && (a != b)) || (a < b))"
    end

    test "string `<>` lowers to Kotlin `+`" do
      kt = JVM.compile(~s|def cat(a String, b String) String := a <> b|)
      # (jvm.ex:237)
      assert kt =~ "return (a + b)"
    end

    test "`rem` lowers to Kotlin `%`" do
      kt = JVM.compile("def md(a Int64, b Int64) Int64 := a rem b")
      # (jvm.ex:240)
      assert kt =~ "return (a % b)"
    end

    test "an operator outside the Tier-2 subset raises" do
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("def pipe(a Int64) Int64 := a |> id")
      end
    end
  end

  describe "type lowering" do
    test "an unknown (lowercase) type annotation raises" do
      # a lowercase, non-builtin type reaches the `kt_type` fall-through. The body is
      # `n` (typed `widget` from the param) so the type gate — now run by
      # `JVM.compile` — passes conservatively, leaving `kt_type` to reject the type.
      assert_raise JVM.Unsupported, fn ->
        JVM.compile("def lc(n widget) widget := n")
      end
    end
  end

  describe "blocks whose last statement is a bind (stmt_value)" do
    test "a block ending in a plain bind yields that bind's value" do
      kt = JVM.compile("def g(n Int64) Int64 := if n > 0 do a := 5 else 0 end")
      # the block's last statement is `a := 5` -> stmt_value({:bind, _, e}) (jvm.ex:238)
      assert kt =~ "run {  5L }"

      case kotlin_run(kt, ~s|println(g(1L)); println(g(-1L))|) do
        :no_jvm -> :ok
        out -> assert out == "5\n0"
      end
    end

    test "a block ending in a typed bind yields that bind's value" do
      kt = JVM.compile("def g(n Int64) Int64 := if n > 0 do a Int64 := 7 else 0 end")
      # last statement is `a Int64 := 7` -> stmt_value({:typed_bind, _, _, e}) (jvm.ex:239)
      assert kt =~ "run {  7L }"

      case kotlin_run(kt, ~s|println(g(1L))|) do
        :no_jvm -> :ok
        out -> assert out == "7"
      end
    end
  end

  describe "string-literal clause-head patterns (lit_kt binary)" do
    test "a string-literal pattern matches by equality on the Kotlin String" do
      kt =
        JVM.compile("""
        def tag(s String) Int64
        def tag("x") := 1
        def tag(s) := 0
        """)

      # a binary literal in a pattern reaches lit_kt/1 binary clause (jvm.ex:273)
      assert kt =~ ~s|if (a0 == "x")|

      case kotlin_run(kt, ~s|println(tag("x")); println(tag("y"))|) do
        :no_jvm -> :ok
        out -> assert out == "1\n0"
      end
    end
  end

  describe "JVM library jar (to_jar with no :main)" do
    test "to_jar without a :main opt assembles a plain library jar" do
      # kotlin_module(src, nil) = plain compile() — no generated `fun main`
      # (jvm.ex:87/113). Skip the actual kotlinc run when the toolchain is absent,
      # like the runnable-jar test above.
      case System.find_executable("kotlinc") do
        nil ->
          :ok

        _ ->
          jar =
            Path.join(System.tmp_dir!(), "rian_libjar_#{System.unique_integer([:positive])}.jar")

          {:ok, ^jar} = JVM.to_jar("def answer() Int64 := 6 * 7", jar)
          assert File.exists?(jar)
          File.rm(jar)
      end
    end
  end
end
