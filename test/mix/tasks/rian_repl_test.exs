defmodule Mix.Tasks.Rian.ReplTest do
  # async: false — the REPL compiles + loads modules into the global VM.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Rian.Repl, as: Task
  alias Rian.Repl

  describe "--eval (one-shot)" do
    test "evaluates an expression with its type" do
      assert capture_io(fn -> Task.run(["--eval", "1 + 1"]) end) =~ "2 : Int64"
    end

    test "reports a definition" do
      out =
        capture_io(fn -> Task.run(["--eval", "def sq(n Int64) Int64\ndef sq(n) := n * n"]) end)

      assert out =~ "defined sq"
    end

    test "rejects unknown options and stray arguments" do
      assert_raise Mix.Error, fn -> Task.run(["--nope"]) end
      assert_raise Mix.Error, fn -> Task.run(["extra.rian"]) end
    end
  end

  describe "interactive loop" do
    # Drive `loop/1` over a captured IO device: `capture_io(input, fun)` feeds
    # `input` as stdin and returns what the loop printed.
    defp session_output(input), do: capture_io(input, fn -> Task.loop(Repl.new()) end)

    test "an expression evaluates on Enter" do
      assert session_output("1 + 2\n") =~ "3 : Int64"
    end

    test "a binding is visible to a later expression" do
      out = session_output("x := 5\nx + 1\n")
      assert out =~ "x := 5 : Int64"
      assert out =~ "6 : Int64"
    end

    test "a multi-clause definition is entered until a blank line, then called" do
      # A local call's return type is not inferred by the conservative checker,
      # so the value prints without a type annotation — value, not `: Int64`.
      out = session_output("def sq(n Int64) Int64\ndef sq(n) := n * n\n\nsq(6)\n")
      assert out =~ "defined sq"
      assert out =~ "36"
    end

    test "a multi-line case block accumulates until balanced" do
      out = session_output("case 1 do\n  0 -> :zero\n  _ -> :other\nend\n")
      assert out =~ ":other"
    end

    test "an error is reported and the loop continues" do
      out = session_output("1 +\n2 + 2\n")
      assert out =~ "error:"
      assert out =~ "4 : Int64"
    end
  end
end
