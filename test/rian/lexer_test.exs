defmodule Rian.LexerTest do
  use ExUnit.Case, async: true

  alias Rian.Lexer

  describe "expression stream (Rian.Pratt consumes this)" do
    test "drops newlines and tokenizes operators/identifiers" do
      assert Lexer.expr_tokens("a + b") == [{:id, "a"}, {:op, "+"}, {:id, "b"}]
    end

    test "control keywords drive expressions" do
      assert {:kw, "if"} in Lexer.expr_tokens("if c do a else b end")
    end

    test "literals: separators, floats, normalized exponents, strings" do
      assert Lexer.expr_tokens("1_000") == [{:num, "1_000"}]
      assert Lexer.expr_tokens("3.14") == [{:num, "3.14"}]
      assert Lexer.expr_tokens("1e9") == [{:num, "1.0e9"}]
      assert Lexer.expr_tokens(~s("hi")) == [{:str, "hi"}]
    end

    test "word-operators stay operators (not keywords)" do
      assert Lexer.expr_tokens("a and not b") ==
               [{:id, "a"}, {:op, "and"}, {:op, "not"}, {:id, "b"}]
    end
  end

  describe "full stream (the token-driven declaration parser will consume this)" do
    test "newlines are significant tokens — runs collapse, edges trimmed" do
      assert Lexer.tokenize("\n\na\n\n\nb\n\n") == [{:id, "a"}, {:nl}, {:id, "b"}]
    end

    test "declaration and case keywords are classified" do
      kws =
        for {:kw, k} <- Lexer.tokenize("def case when type struct alias mod pub const macro use"),
            do: k

      assert kws == ~w(def case when type struct alias mod pub const macro use)
    end

    test "comments run to end of line" do
      assert Lexer.tokenize("a # ignored\nb") == [{:id, "a"}, {:nl}, {:id, "b"}]
    end

    test "the multi-line block/case constructs the line-based parser could not handle now tokenize" do
      src = """
      def area(s val Shape) Float64
        case s do
          Circle(r) -> pi * r * r
          Square(s) -> s * s
        end
      end
      """

      toks = Lexer.tokenize(src)

      assert {:kw, "def"} in toks
      assert {:kw, "case"} in toks
      assert {:kw, "do"} in toks
      assert {:nl} in toks
      # one `end` closes the `case`, one closes the `def`
      assert Enum.count(toks, &(&1 == {:kw, "end"})) == 2
    end
  end

  test "detokenize renders a re-lexable string; `{:nl}` becomes the chosen separator" do
    assert Lexer.detokenize(Lexer.tokenize("a + b")) == "a + b"
    assert Lexer.detokenize(Lexer.tokenize("a := 2\nb"), ";") == "a := 2 ; b"
  end

  test "unterminated string is a lex error" do
    assert_raise ArgumentError, ~r/unterminated/, fn -> Lexer.tokenize(~s("oops)) end
  end
end
