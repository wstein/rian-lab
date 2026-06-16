defmodule Rian.LSP.FormattingTest do
  use ExUnit.Case, async: true

  alias Rian.Format
  alias Rian.LSP.Formatting, as: F

  describe "formatting/1 (whole document)" do
    test "an already-formatted document yields no edits" do
      assert F.formatting("def f() := 1\n") == []
    end

    test "edits applied to the source reproduce Rian.Format.format/1" do
      src = "def a():=1\ndef b()  := foo(x,y)\ndef c():=3\n"
      edits = F.formatting(src)
      assert edits != []
      assert F.apply_edits(src, edits) == Format.format(src)
    end

    test "only-some-lines-changed produces hunks that leave clean lines alone" do
      src = "def a() := 1\ndef b():=2\ndef c() := 3\n"
      edits = F.formatting(src)
      # one hunk, touching only line 1 (def b)
      assert [%{range: %{start: %{line: 1}, end: %{line: 2}}}] = edits
      assert F.apply_edits(src, edits) == Format.format(src)
    end
  end

  describe "range_formatting/3 (selection)" do
    @doc_src "mod M do\n  def a():=1\n  def b()  := foo(x,y)\n  def c():=3\nend\n"

    test "formats only the selected line, re-indented to its context" do
      [edit] = F.range_formatting(@doc_src, 2, 2)
      assert edit.new_text == "  def b() := foo(x, y)\n"
      assert edit.range == %{start: %{line: 2, character: 0}, end: %{line: 3, character: 0}}
    end

    test "leaves the rest of the buffer untouched" do
      out = F.apply_edits(@doc_src, F.range_formatting(@doc_src, 2, 2))
      # def a and def c are still unformatted; only def b changed
      assert out == "mod M do\n  def a():=1\n  def b() := foo(x, y)\n  def c():=3\nend\n"
    end

    test "an already-formatted selection yields no edits" do
      formatted = Format.format(@doc_src)
      lines = String.split(formatted, "\n")
      # pick a real def line
      idx = Enum.find_index(lines, &String.contains?(&1, "def b"))
      assert F.range_formatting(formatted, idx, idx) == []
    end

    test "clamps an out-of-range selection without raising" do
      assert is_list(F.range_formatting("def f() := 1\n", 0, 9999))
    end
  end
end
