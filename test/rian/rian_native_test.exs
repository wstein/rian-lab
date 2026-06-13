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
end
