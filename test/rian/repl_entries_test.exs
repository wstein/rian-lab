defmodule Rian.ReplEntriesTest do
  use ExUnit.Case, async: true

  alias Rian.Repl

  describe "split_entries/1 — the batch-surface entry splitter (ADR-0053)" do
    test "each single-line expression / bind is its own entry" do
      assert Repl.split_entries("x := 1\ny := 2\nx + y") == ["x := 1\n", "y := 2\n", "x + y\n"]
    end

    test "a multi-clause declaration accumulates until a blank line" do
      src = "def f(n Int64) Int64\ndef f(n) := n + 1\n\nf(10)"
      assert Repl.split_entries(src) == ["def f(n Int64) Int64\ndef f(n) := n + 1\n", "f(10)\n"]
    end

    test "an unbalanced `do …` block accumulates until it balances" do
      src = "case A do\n  A -> 1\n  B -> 2\nend"
      assert Repl.split_entries(src) == ["case A do\n  A -> 1\n  B -> 2\nend\n"]
    end

    test "blank lines separate entries and never become entries themselves" do
      assert Repl.split_entries("1 + 2\n\n\n3 * 4") == ["1 + 2\n", "3 * 4\n"]
    end

    test "a trailing declaration with no blank line is flushed at end of input" do
      assert Repl.split_entries("type T := A | B") == ["type T := A | B\n"]
    end

    test "empty / whitespace-only input yields no entries" do
      assert Repl.split_entries("") == []
      assert Repl.split_entries("\n   \n\t\n") == []
    end

    test "entries round-trip through the engine, threading one session" do
      session =
        "x := 6\ny := 7\nx * y"
        |> Repl.split_entries()
        |> Enum.reduce(Repl.new(), fn entry, s ->
          {_result, s} = Repl.eval(s, entry)
          s
        end)

      {result, _} = Repl.eval(session, "x * y")
      assert Repl.render(result) == "42 : Int53"
    end
  end
end
