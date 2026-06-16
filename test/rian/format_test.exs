defmodule Rian.FormatTest do
  use ExUnit.Case, async: true

  alias Rian.Format
  alias Rian.Lexer

  # The token sequence the compiler actually sees — comments stripped, blank-line
  # runs collapsed. Equal streams ⇒ same program (the formatter's correctness bar).
  defp prog_tokens(src), do: Lexer.tokenize(src)
  defp comments(src), do: Enum.filter(Lexer.tokenize_trivia(src), &match?({:comment, _}, &1))

  describe "intra-line spacing" do
    test "function application and indexing bind tightly" do
      assert Format.format("def f() := g(x)\n") == "def f() := g(x)\n"
      assert Format.format("def f(xs) := xs[0]\n") == "def f(xs) := xs[0]\n"
    end

    test "normalizes ragged operator spacing to a single space" do
      assert Format.format("def f(x) := x+1\n") == "def f(x) := x + 1\n"
      assert Format.format("def f(x) := x   +   1\n") == "def f(x) := x + 1\n"
    end

    test "member access dot has no surrounding space" do
      assert Format.format("def f() := Enum.map(xs, g)\n") == "def f() := Enum.map(xs, g)\n"
      assert Format.format("def f() := :lists.foldl(g, 0, xs)\n") ==
               "def f() := :lists.foldl(g, 0, xs)\n"
    end

    test "unary minus binds to its operand; binary minus is spaced" do
      assert Format.format("def f() := -1\n") == "def f() := -1\n"
      assert Format.format("def f(a, b) := a - b\n") == "def f(a, b) := a - b\n"
    end

    test "map/keyword colons hug the key, atom colons hug the atom" do
      assert Format.format("def f() := %{x: 0, y: 0}\n") == "def f() := %{x: 0, y: 0}\n"
      assert Format.format("def f() := g(:ok)\n") == "def f() := g(:ok)\n"
    end

    test "comma and semicolon: no space before, one after" do
      assert Format.format("def f() := g(a,b)\n") == "def f() := g(a, b)\n"
    end
  end

  describe "indentation" do
    test "do/end blocks indent two spaces per level" do
      src = "def sign(n)\nif n >= 0 do\n1\nelse\n-1\nend\nend\n"
      assert Format.format(src) == """
             def sign(n)
               if n >= 0 do
                 1
               else
                 -1
               end
             end
             """
    end

    test "a multi-line case arm body nests under the arm" do
      src = "def f(x)\ncase x do\nP(a) ->\ng(a)\nend\nend\n"

      assert Format.format(src) == """
             def f(x)
               case x do
                 P(a) ->
                   g(a)
               end
             end
             """
    end

    test "module body indents one level" do
      src = "mod M do\ndef f() := 1\nend\n"
      assert Format.format(src) == "mod M do\n  def f() := 1\nend\n"
    end
  end

  describe "comments and blank lines" do
    test "trailing comments stay on their line" do
      assert Format.format("def f() := 1  # one\n") == "def f() := 1  # one\n"
    end

    test "own-line comments keep their place and context indent" do
      src = "mod M do\n# note\ndef f() := 1\nend\n"
      assert Format.format(src) == "mod M do\n  # note\n  def f() := 1\nend\n"
    end

    test "collapses blank-line runs to one and trims edges" do
      assert Format.format("\n\ndef f() := 1\n\n\n\ndef g() := 2\n\n") ==
               "def f() := 1\n\ndef g() := 2\n"
    end

    test "heredocs are reproduced verbatim, not flattened" do
      triple = "\"\"\""
      src = "@doc #{triple}\nline one\nline two\n#{triple}\ndef f() := 1\n"
      out = Format.format(src)
      assert out =~ triple
      assert out =~ "line one\nline two"
    end
  end

  describe "correctness bars over the real corpus" do
    @corpus Path.wildcard("examples/rian/*.rian") ++ Path.wildcard("compiler/*.rian")

    test "the corpus is non-empty (guards against a bad glob)" do
      assert length(@corpus) > 20
    end

    for file <- @corpus do
      @path file

      test "re-lex equivalence: #{file}" do
        src = File.read!(@path)
        assert prog_tokens(Format.format(src)) == prog_tokens(src)
      end

      test "idempotence: #{file}" do
        once = Format.format(File.read!(@path))
        assert Format.format(once) == once
      end

      test "comment fidelity: #{file}" do
        src = File.read!(@path)
        assert comments(Format.format(src)) == comments(src)
      end
    end
  end
end
