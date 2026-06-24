defmodule Rian.TourReachTest do
  use ExUnit.Case, async: true

  alias Rian.Tour.Examples
  alias Rian.Tour.Examples.Error

  describe "the committed by-example corpus" do
    test "every numbered file carries a `#@reach` or `#@illustrative` header" do
      for file <- Examples.files() do
        assert Examples.header(File.read!(file)) != :none,
               "#{Path.basename(file)} has no machine-readable header"
      end
    end

    test "every file honours its header (the reach gate)" do
      assert Examples.check!() == :ok
    end
  end

  describe "#@pane files (the minimal site-pane sources)" do
    test "all pane files are tagged, minimal, and emit to four targets" do
      assert Examples.check_panes!() == :ok
      assert length(Examples.pane_files()) == 8
    end

    test "pane_source/1 returns the source with the `#@pane` tag stripped" do
      src = Examples.pane_source("basics")
      refute src =~ "#@pane"
      assert src =~ "def twice(n Int53) Int53 := n * 2"
    end
  end

  describe "header/1" do
    test "parses a `#@reach` line into a target set" do
      assert {:gated, reach, pins} = Examples.header("#@reach ex, rs, js, jvm\n# title\n")
      assert reach == MapSet.new([:ex, :rs, :js, :jvm])
      assert pins == %{}
    end

    test "parses `#@reach-pin` entries (single and multi)" do
      src = "#@reach ex, rs, js, jvm\n#@reach-pin show=ex depth=ex,js,jvm\n"
      assert {:gated, _reach, pins} = Examples.header(src)
      assert pins == %{"show" => MapSet.new([:ex]), "depth" => MapSet.new([:ex, :js, :jvm])}
    end

    test "parses an `#@illustrative` line into its reason" do
      assert {:illustrative, reason} =
               Examples.header("#@illustrative — `extern` is unsupported\n")

      assert reason == "`extern` is unsupported"
    end

    test "is `:none` when no header is present" do
      assert Examples.header("# just a comment\ndef f(n Int53) Int53 := n\n") == :none
    end

    test "rejects an unknown target" do
      assert_raise Error, ~r/unknown target "wasm"/, fn ->
        Examples.header("#@reach ex, wasm\n")
      end
    end
  end

  describe "issues/1 catches drift" do
    test "no header is an issue" do
      assert Examples.issues("def f(n Int53) Int53 := n\n") == [
               "no `#@reach` or `#@illustrative` header"
             ]
    end

    test "an over-claimed `#@reach` is reported" do
      # `square` reaches every target, so claiming only `ex` under-claims the union.
      src = "#@reach ex\ndef square(n Int53) Int53 := n * n\n"
      assert [msg] = Examples.issues(src)
      assert msg =~ "declares `#@reach ex`"
      assert msg =~ "the analysis reaches"
    end

    test "a function below the union with no pin is reported" do
      # `shout` uses host FFI (ex-only); `square` reaches all — so the union is the
      # full set and `shout` must be pinned.
      src = """
      #@reach ex, rs, js, jvm
      def square(n Int53) Int53 := n * n
      def shout(s String) String := String.upcase(s)
      """

      assert Enum.any?(Examples.issues(src), &(&1 =~ "`shout`" and &1 =~ "no `#@reach-pin`"))
    end

    test "a wrong pin target set is reported" do
      src = """
      #@reach ex, rs, js, jvm
      #@reach-pin shout=ex,rs
      def square(n Int53) Int53 := n * n
      def shout(s String) String := String.upcase(s)
      """

      assert Enum.any?(Examples.issues(src), &(&1 =~ "`#@reach-pin shout="))
    end

    test "a pin naming no function is reported" do
      src = "#@reach ex, rs, js, jvm\n#@reach-pin ghost=ex\ndef square(n Int53) Int53 := n * n\n"
      assert Enum.any?(Examples.issues(src), &(&1 =~ "names no function"))
    end

    test "an `#@illustrative` file that actually parses must be promoted" do
      src = "#@illustrative — claims to be unsupported\ndef square(n Int53) Int53 := n * n\n"
      assert Enum.any?(Examples.issues(src), &(&1 =~ "now parses"))
    end

    test "a claimed target the emitter cannot actually produce is reported" do
      # `Shape` is undeclared: the BEAM tolerates the dynamic tag but Rust needs
      # the `enum`, so the rs emitter raises even though reach claims rs.
      src = """
      #@reach ex, rs, js, jvm
      def area(s val Shape) Float64
      def area(Circle(r)) := r
      def area(Square(s)) := s
      """

      assert Enum.any?(Examples.issues(src), &(&1 =~ "rs emitter raises"))
    end

    test "an `#@illustrative` file that does not parse is accepted" do
      # `extern` is not accepted by the front-end, so this genuinely cannot compile.
      assert Examples.issues("#@illustrative — extern\nextern foo()\n") == []
    end
  end
end
