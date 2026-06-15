defmodule Rian.LivebookTest do
  # async: false — drives the notebook-global shared-session Agent and loads real
  # modules into the VM through the compiling engine.
  use ExUnit.Case, async: false

  alias Rian.{Livebook, Repl}

  setup do
    Livebook.reset()
    :ok
  end

  describe "run/2 — the pure engine seam (no shared state, no IO)" do
    test "threads one session across a cell's entries and renders each" do
      {lines, _session} = Livebook.run(Repl.new(), "x := 6\ny := 7\nx * y")
      assert lines == ["x := 6 : Int53", "y := 7 : Int53", "42 : Int53"]
    end

    test "an empty entry contributes no rendered line" do
      {lines, _session} = Livebook.run(Repl.new(), "\n\n1 + 1\n\n")
      assert lines == ["2 : Int53"]
    end

    test "a later entry sees an earlier declaration in the same cell" do
      {lines, _session} =
        Livebook.run(Repl.new(), "def double(n Int64) Int64 := n * 2\n\ndouble(21)")

      assert lines == ["defined double", "42 : Int64"]
    end
  end

  describe "eval/1 — the shared notebook session (what the smart cell calls)" do
    test "returns a Kino.Markdown output of the rendered results" do
      out = Livebook.eval("1 + 2 * 3")
      assert %Kino.Markdown{} = out
      assert out.text =~ "7 : Int53"
    end

    test "a blank cell yields an empty output (never crashes the notebook)" do
      out = Livebook.eval("\n   \n")
      assert %Kino.Markdown{text: ""} = out
    end

    test "declarations and binds persist across separate eval calls (cross-cell state)" do
      Livebook.eval("type Color := Red | Green")

      Livebook.eval("""
      def name(c Color) String := case c do
        Red -> "red"
        Green -> "green"
      end
      """)

      out = Livebook.eval("name(Red)")
      assert out.text =~ ~s|"red" : String|
    end

    test "reset/0 starts a fresh session — prior declarations are gone" do
      Livebook.eval("z := 99")
      assert Livebook.eval("z").text =~ "99"

      Livebook.reset()
      assert Livebook.eval("z").text =~ "error:"
    end
  end

  describe "the Kino.SmartCell (Elixir side; the editor UI is Livebook-managed)" do
    test "to_source/1 generates a readable `Rian.Livebook.eval(...)` call" do
      source = Rian.Livebook.SmartCell.to_source(%{"source" => "x := 1\nx + 2"})
      assert source == ~s|Rian.Livebook.eval("x := 1\\nx + 2")|
    end

    test "an empty cell generates a no-op eval (never crashes the notebook)" do
      assert Rian.Livebook.SmartCell.to_source(%{"source" => ""}) == ~s|Rian.Livebook.eval("")|
    end

    test "it is registered under the name \"Rian\"" do
      assert Rian.Livebook.SmartCell.__smart_definition__().name == "Rian"
    end
  end
end
