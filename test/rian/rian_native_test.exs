defmodule Rian.RianNativeTest do
  @moduledoc """
  Dogfooding ADR-0057: a `.rian` test file run *as Rian*, each `@test def`
  surfaced as its own ExUnit case via `Rian.Test.exunit/1`. This is the first
  Rian-native test corpus — the wedge for migrating `test/rian/*_test.exs` to
  `test/rian/*_test.rian` over time.
  """
  # async: false — loads a compiled module into the VM.
  use ExUnit.Case, async: false
  require Rian.Test

  # one ExUnit `test` per `@test def` in the file
  Rian.Test.exunit("examples/rian/14_test_framework.rian")
end

defmodule Rian.TestRunnerTest do
  use ExUnit.Case, async: false

  alias Rian.Test, as: RT

  describe "Rian.Test runner (ADR-0057)" do
    test "discovers `@test def`s and runs them, reporting pass/fail" do
      src = """
      def inc(n Int64) Int64 := n + 1

      @test def inc_works() Bool := inc(1) == 2
      @test def also_passes() Bool := 1 == 1
      @test def fails() Bool := 1 == 2
      """

      assert RT.tests(src) == ["inc_works", "also_passes", "fails"]

      assert RT.run(src) == [
               {"inc_works", :pass},
               {"also_passes", :pass},
               {"fails", {:fail, false}}
             ]
    end

    test "`@test` may only precede a `def`" do
      assert_raise Rian.Decl.Error, ~r/`@test` may only precede a `def`/, fn ->
        Rian.Decl.parse("@test\ntype T := A | B\n")
      end
    end

    test "a non-test function is not collected as a test" do
      src = "def helper(n Int64) Int64 := n\n@test def t() Bool := true\n"
      assert RT.tests(src) == ["t"]
    end
  end

  describe "assertion macros (ADR-0060 · ADR-0030) — injected, no redeclaration" do
    @asserts """
    def double(n Int53) Int53 := n * 2

    @test def with_assert() Bool := assert(double(21) == 42)
    @test def with_refute() Bool := refute(double(2) == 5)
    @test def with_assert_eq() Bool := assert_eq(double(3), 6)
    @test def with_assert_neq() Bool := assert_neq(double(3), 7)
    @test def combined() Bool := assert_eq(double(3), 6) and assert_eq(double(4), 8)
    @test def honest_failure() Bool := assert(double(2) == 5)
    """

    test "expand to plain Bool and report pass/fail without the source defining them" do
      # the macros are NOT declared in @asserts — `Rian.Test` prepends the lib.
      assert RT.run(@asserts) == [
               {"with_assert", :pass},
               {"with_refute", :pass},
               {"with_assert_eq", :pass},
               {"with_assert_neq", :pass},
               {"combined", :pass},
               {"honest_failure", {:fail, false}}
             ]
    end

    test "the prepended lib adds no tests of its own" do
      assert RT.tests(@asserts) == [
               "with_assert",
               "with_refute",
               "with_assert_eq",
               "with_assert_neq",
               "combined",
               "honest_failure"
             ]
    end

    test "assert_prelude/0 exposes the lib that gets injected" do
      assert RT.assert_prelude() =~ "macro assert(cond)"
      assert RT.assert_prelude() =~ "macro refute(cond)"
    end

    test "the loop closes: an ExUnit module transpiles to a draft that runs as Rian" do
      ex = """
      defmodule DoubleTest do
        use ExUnit.Case, async: true

        def double(n), do: n * 2

        test "doubling works" do
          assert double(21) == 42
        end

        test "is additive" do
          assert double(3) == 6
          assert double(4) == 8
        end

        test "honest failure" do
          assert double(2) == 5
        end
      end
      """

      code =
        ex
        |> Rian.Transpile.transpile(infer: true)
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.join("\n")

      assert RT.run(code) == [
               {"doubling_works", :pass},
               {"is_additive", :pass},
               {"honest_failure", {:fail, false}}
             ]
    end
  end

  describe "per-target test harness (ADR-0060 §3)" do
    @src File.read!("examples/rian/14_test_framework.rian")

    test "Rust harness emits a #[test] wrapper per @test asserting it returns true" do
      rust = RT.rust(@src)
      assert rust =~ "fn double_zero() -> i64" or rust =~ "fn double(n: i64)"
      assert rust =~ "#[test]\nfn rian_test_double_zero() { assert!(double_zero()); }"
      assert rust =~ "#[test]\nfn rian_test_fib_recurses() { assert!(fib_recurses()); }"
    end

    test "JS harness emits a node:test case per @test" do
      js = RT.js(@src)
      assert js =~ ~s|import { test } from "node:test"|
      assert js =~ ~s|test("double_zero", () => assert.strictEqual(double_zero(), true))|
    end

    @tag :rust
    test "the Rust test module compiles and passes under `rustc --test`" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_th_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, RT.rust(@src))

          {_, 0} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin])

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert out =~ "5 passed"
      end
    end

    @tag :js
    test "the JS test module passes under `node --test`" do
      case System.find_executable("node") do
        nil ->
          :ok

        node ->
          dir = System.tmp_dir!()
          path = Path.join(dir, "rian_th_#{System.unique_integer([:positive])}.mjs")
          File.write!(path, RT.js(@src))
          {out, code} = System.cmd(node, ["--test", path])
          File.rm(path)
          assert code == 0
          assert out =~ "pass 5"
      end
    end
  end

  describe "assertion macros lower per target (ADR-0060 §3 · ADR-0030)" do
    # the source declares NO macros — the harness injects the lib before lowering.
    @asserts_src """
    def double(n Int53) Int53 := n * 2

    @test def eq_passes() Bool := assert_eq(double(3), 6)
    @test def refute_passes() Bool := refute(double(2) == 5)
    """

    test "Rust lowering expands the macros to plain Bool — no `macro` leaks" do
      rust = RT.rust(@asserts_src)
      assert rust =~ "double(3) == 6"
      assert rust =~ "!(double(2) == 5)"
      refute rust =~ "macro"
      assert rust =~ "#[test]\nfn rian_test_eq_passes() { assert!(eq_passes()); }"
    end

    test "JS lowering expands the macros to plain Bool — no `macro` leaks" do
      js = RT.js(@asserts_src)
      assert js =~ "double(3) === 6"
      assert js =~ "!(double(2) === 5)"
      refute js =~ "macro"
      assert js =~ ~s|test("eq_passes", () => assert.strictEqual(eq_passes(), true))|
    end

    @tag :rust
    test "the expanded Rust test module compiles and passes under `rustc --test`" do
      case System.find_executable("rustc") do
        nil ->
          :ok

        rustc ->
          dir = System.tmp_dir!()
          src = Path.join(dir, "rian_at_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, RT.rust(@asserts_src))

          {_, 0} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin])

          {out, 0} = System.cmd(bin, [])
          File.rm(src)
          File.rm(bin)
          assert out =~ "2 passed"
      end
    end

    @tag :js
    test "the expanded JS test module passes under `node --test`" do
      case System.find_executable("node") do
        nil ->
          :ok

        node ->
          dir = System.tmp_dir!()
          path = Path.join(dir, "rian_at_#{System.unique_integer([:positive])}.mjs")
          File.write!(path, RT.js(@asserts_src))
          {out, code} = System.cmd(node, ["--test", path])
          File.rm(path)
          assert code == 0
          assert out =~ "pass 2"
      end
    end
  end
end
