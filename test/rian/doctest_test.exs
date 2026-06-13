defmodule Rian.DoctestFileTest do
  @moduledoc """
  ADR-0060 tier B: the doctests in a `.rian` file's `@doc`s, executed — each
  `expr #=> expected` surfaced as its own ExUnit case via `Rian.Doctest.exunit/1`.
  A drifted example fails this build.
  """
  use ExUnit.Case, async: false
  require Rian.Doctest

  Rian.Doctest.exunit("examples/rian/16_doctests.rian")
end

defmodule Rian.SpecDoctestTest do
  @moduledoc """
  ADR-0060 tier B: the ` ```rian ` fences in a `docs/spec/*.md` file, executed —
  the spec corpus made un-driftable. Each `expr #=> expected` is its own case.
  """
  use ExUnit.Case, async: false
  require Rian.Doctest

  Rian.Doctest.exunit_markdown("docs/spec/expressions.md")
end

defmodule Rian.DoctestRunnerTest do
  use ExUnit.Case, async: false

  alias Rian.Doctest

  describe "Rian.Doctest runner (ADR-0060 tier B)" do
    test "extracts `expr #=> expected` pairs from top-level @doc heredocs" do
      src = """
      @doc \"\"\"
      Adds one.

          inc(1) #=> 2
          inc(0) #=> 1
      \"\"\"
      def inc(n Int64) Int64 := n + 1
      """

      assert Doctest.extract(src) == [{"inc(1)", "2"}, {"inc(0)", "1"}]
    end

    test "a correct example passes; both sides are evaluated as real Rian" do
      src = """
      @doc \"\"\"
          add(2, 3)  #=> 5
          add(2, 3)  #=> 1 + 4
      \"\"\"
      def add(a Int64, b Int64) Int64 := a + b
      """

      assert Doctest.run(src) == [{"add(2, 3)", :pass}, {"add(2, 3)", :pass}]
    end

    test "a drifted example fails with the actual and expected values" do
      src = """
      @doc \"\"\"
          inc(1) #=> 3
      \"\"\"
      def inc(n Int64) Int64 := n + 1
      """

      assert Doctest.run(src) == [{"inc(1)", {:fail, 2, 3}}]
    end

    test "a file with no doctests yields no checks" do
      assert Doctest.run("def f(n Int64) Int64 := n\n") == []
    end

    test "doctests over a String-returning function compare by value" do
      src = """
      @doc \"\"\"
          greet()  #=> "hi"
      \"\"\"
      def greet() String := "hi"
      """

      assert Doctest.run(src) == [{"greet()", :pass}]
    end

    test "module-internal @doc doctests run (injected into the module)" do
      src = """
      mod Calc do
        @doc \"\"\"
            double(21) #=> 42
        \"\"\"
        pub def double(n Int64) Int64 := n * 2
      end
      """

      assert Doctest.extract(src) == [{"double(21)", "42"}]
      assert Doctest.run(src) == [{"double(21)", :pass}]
    end

    test "run_markdown runs the ```rian fences in a Markdown string" do
      md = """
      # Spec

      ```rian
      @doc \"\"\"
          inc(1) #=> 2
      \"\"\"
      def inc(n Int64) Int64 := n + 1
      ```

      prose

      ```rian
      @doc \"\"\"
          neg(3) #=> 0 - 3
      \"\"\"
      def neg(n Int64) Int64 := 0 - n
      ```
      """

      assert length(Doctest.fences(md)) == 2
      assert Doctest.run_markdown(md) == [{"inc(1)", :pass}, {"neg(3)", :pass}]
    end
  end
end
