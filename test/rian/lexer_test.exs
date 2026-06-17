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

    test "identifiers carry a trailing `?`/`!` (predicate/bang, ADR-0033)" do
      assert Lexer.expr_tokens("empty?") == [{:id, "empty?"}]
      assert Lexer.expr_tokens("gate!") == [{:id, "gate!"}]

      assert Lexer.expr_tokens("Reach.gate!(prog)") ==
               [{:id, "Reach"}, {:op, "."}, {:id, "gate!"}, {:lparen}, {:id, "prog"}, {:rparen}]
    end

    test "a trailing `!` does not swallow the `!=` operator" do
      assert Lexer.expr_tokens("a != b") == [{:id, "a"}, {:op, "!="}, {:id, "b"}]
      assert Lexer.expr_tokens("a!=b") == [{:id, "a"}, {:op, "!="}, {:id, "b"}]
    end

    test "literals: separators, floats, normalized exponents, strings" do
      assert Lexer.expr_tokens("1_000") == [{:num, "1_000"}]
      assert Lexer.expr_tokens("3.14") == [{:num, "3.14"}]
      assert Lexer.expr_tokens("1e9") == [{:num, "1.0e9"}]
      assert Lexer.expr_tokens(~s("hi")) == [{:str, "hi"}]
    end

    test "string escapes: inner quotes, backslash, and \\n/\\t decode to their value" do
      # `"a\"b"` is the value a"b — the inner quote must not terminate the string
      assert Lexer.expr_tokens(~S|"a\"b"|) == [{:str, ~s(a"b)}]
      assert Lexer.expr_tokens(~S|"a\\b"|) == [{:str, ~S(a\b)}]
      assert Lexer.expr_tokens(~S|"line\nbreak"|) == [{:str, "line\nbreak"}]
      assert Lexer.expr_tokens(~S|"tab\there"|) == [{:str, "tab\there"}]
      # a body string literal embedding a quote still lexes as one token
      assert Lexer.expr_tokens(~S|f("say \"hi\"")|) ==
               [{:id, "f"}, {:lparen}, {:str, ~s(say "hi")}, {:rparen}]
    end

    test "string escapes: the full Elixir/Gleam named set decodes to its codepoint" do
      assert Lexer.expr_tokens(~S|"\a"|) == [{:str, <<0x07>>}]
      assert Lexer.expr_tokens(~S|"\b"|) == [{:str, <<0x08>>}]
      assert Lexer.expr_tokens(~S|"\d"|) == [{:str, <<0x7F>>}]
      assert Lexer.expr_tokens(~S|"\e"|) == [{:str, <<0x1B>>}]
      assert Lexer.expr_tokens(~S|"\f"|) == [{:str, <<0x0C>>}]
      assert Lexer.expr_tokens(~S|"\r"|) == [{:str, "\r"}]
      assert Lexer.expr_tokens(~S|"\s"|) == [{:str, " "}]
      assert Lexer.expr_tokens(~S|"\v"|) == [{:str, <<0x0B>>}]
      assert Lexer.expr_tokens(~S|"\0"|) == [{:str, <<0>>}]
    end

    test "string escapes: \\xHH, \\uHHHH, and \\u{HEX} numeric forms" do
      assert Lexer.expr_tokens(~S|"\x41"|) == [{:str, "A"}]
      assert Lexer.expr_tokens(~S|"\x7"|) == [{:str, <<0x07>>}]
      assert Lexer.expr_tokens(~S|"é"|) == [{:str, "é"}]
      assert Lexer.expr_tokens(~S|"\u{e9}"|) == [{:str, "é"}]
      assert Lexer.expr_tokens(~S|"\u00e9"|) == [{:str, "é"}]
      assert Lexer.expr_tokens(~S|"\u{1F600}"|) == [{:str, "😀"}]
      # a literal (unescaped) non-ASCII codepoint passes through unchanged
      assert Lexer.expr_tokens(~S|"café"|) == [{:str, "café"}]
    end

    test "word-operators stay operators (not keywords)" do
      assert Lexer.expr_tokens("a and not b") ==
               [{:id, "a"}, {:op, "and"}, {:op, "not"}, {:id, "b"}]
    end

    test "char literals lex to codepoint integers (ADR-0036)" do
      assert Lexer.expr_tokens("'A'") == [{:char, 65}]
      assert Lexer.expr_tokens("'+'") == [{:char, 43}]
      assert Lexer.expr_tokens("' '") == [{:char, 32}]
      # in context: a guard comparison reads like a character
      assert Lexer.expr_tokens("c == '0'") == [{:id, "c"}, {:op, "=="}, {:char, 48}]
    end

    test "char-literal escapes (ADR-0036)" do
      assert Lexer.expr_tokens(~S('\n')) == [{:char, 10}]
      assert Lexer.expr_tokens(~S('\t')) == [{:char, 9}]
      assert Lexer.expr_tokens(~S('\\')) == [{:char, 92}]
      assert Lexer.expr_tokens(~S('\'')) == [{:char, 39}]
      assert Lexer.expr_tokens(~S('\0')) == [{:char, 0}]
      assert Lexer.expr_tokens("'\\u{1F600}'") == [{:char, 0x1F600}]
    end

    test "char literals honor the full Elixir/Gleam escape set" do
      assert Lexer.expr_tokens(~S('\a')) == [{:char, 0x07}]
      assert Lexer.expr_tokens(~S('\e')) == [{:char, 0x1B}]
      assert Lexer.expr_tokens(~S('\s')) == [{:char, 0x20}]
      assert Lexer.expr_tokens(~S('\v')) == [{:char, 0x0B}]
      assert Lexer.expr_tokens(~S('\x41')) == [{:char, 0x41}]
      assert Lexer.expr_tokens("'\\u00e9'") == [{:char, 0xE9}]
    end

    test "a non-ASCII codepoint is one Char" do
      assert Lexer.expr_tokens("'é'") == [{:char, ?é}]
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

  test "detokenize round-trips char literals re-lexably" do
    assert Lexer.detokenize(Lexer.tokenize("'A'")) == "'A'"
    assert Lexer.detokenize(Lexer.tokenize(~S('\n'))) == ~S('\n')
    assert Lexer.expr_tokens(Lexer.detokenize(Lexer.tokenize(~S('\\')))) == [{:char, 92}]
  end

  test "detokenize re-escapes inner quotes so a string round-trips re-lexably" do
    # value a"b → `"a\"b"` → re-lexes back to the same value
    assert Lexer.detokenize(Lexer.tokenize(~S|"a\"b"|)) == ~S|"a\"b"|
    assert Lexer.expr_tokens(Lexer.detokenize(Lexer.tokenize(~S|"a\"b"|))) == [{:str, ~s(a"b)}]
    # a body string literal embedding a quote survives the detokenize round-trip
    src = ~S|f("say \"hi\"")|
    assert Lexer.expr_tokens(Lexer.detokenize(Lexer.expr_tokens(src))) == Lexer.expr_tokens(src)
    # backslash and \n re-escape too
    assert Lexer.expr_tokens(Lexer.detokenize(Lexer.tokenize(~S|"a\\b"|))) == [{:str, ~S(a\b)}]
    assert Lexer.expr_tokens(Lexer.detokenize(Lexer.tokenize(~S|"a\nb"|))) == [{:str, "a\nb"}]
  end

  test "detokenize round-trips control codepoints in strings via the `\\u{HEX}` fallback" do
    # values: bell (7), unit-separator (31), DEL (127) — no named escape for 31
    original = [{:str, <<0x07, 0x1F, 0x7F>>}]
    assert Lexer.detokenize(original) == ~S|"\u{7}\u{1F}\u{7F}"|
    assert Lexer.expr_tokens(Lexer.detokenize(original)) == original
  end

  test "out-of-range and surrogate codepoints are lex errors" do
    assert_raise ArgumentError, ~r/out of range/, fn -> Lexer.tokenize(~S|"\u{110000}"|) end
    assert_raise ArgumentError, ~r/surrogate/, fn -> Lexer.tokenize(~S|"\u{d800}"|) end
  end

  test "malformed numeric escapes are lex errors" do
    assert_raise ArgumentError, ~r/`\\x` escape needs/, fn -> Lexer.tokenize(~S|"\xZ"|) end
    assert_raise ArgumentError, ~r/`\\u` escape needs four/, fn -> Lexer.tokenize(~S|"\uAB"|) end
    assert_raise ArgumentError, ~r/empty or unterminated/, fn -> Lexer.tokenize(~S|"\u{}"|) end
  end

  test "unterminated string is a lex error" do
    assert_raise ArgumentError, ~r/unterminated/, fn -> Lexer.tokenize(~s("oops)) end
  end

  test "an empty or multi-codepoint char literal is a lex error (no charlists)" do
    assert_raise ArgumentError, ~r/empty character/, fn -> Lexer.tokenize("''") end
    assert_raise ArgumentError, ~r/single codepoint/, fn -> Lexer.tokenize("'ab'") end
    assert_raise ArgumentError, ~r/unterminated/, fn -> Lexer.tokenize("'a") end
    assert_raise ArgumentError, ~r/unknown character escape/, fn -> Lexer.tokenize(~S('\q')) end
  end

  test "a lone `'` at end of input is an unterminated char literal" do
    assert_raise ArgumentError, ~r/unterminated character literal/, fn -> Lexer.tokenize("'") end
  end

  test "the `\\\"` escape in a char literal lexes to the double-quote codepoint" do
    assert Lexer.expr_tokens(~S('\"')) == [{:char, ?"}]
  end

  test "an unterminated `\\u{...}` escape is a lex error" do
    assert_raise ArgumentError, ~r/unterminated `\\u\{\.\.\.\}` escape/, fn ->
      Lexer.tokenize("'\\u{1F600")
    end
  end

  test "an annotation token detokenizes back to `@name`" do
    assert [{:annot, "doc"}] = Lexer.tokenize("@doc")
    assert Lexer.detokenize(Lexer.tokenize("@doc")) == "@doc"
  end

  test "detokenize round-trips the \\t, \\r and \\0 char-source escapes" do
    assert Lexer.detokenize(Lexer.tokenize(~S('\t'))) == ~S('\t')
    assert Lexer.detokenize(Lexer.tokenize(~S('\r'))) == ~S('\r')
    assert Lexer.detokenize(Lexer.tokenize(~S('\0'))) == ~S('\0')
  end

  test "a heredoc `\"\"\"…\"\"\"` is one trimmed string; an empty heredoc is the empty string" do
    assert Lexer.tokenize(~s(\"\"\"hi\"\"\")) == [{:str, "hi"}]
    assert Lexer.tokenize(~s(\"\"\"\"\"\")) == [{:str, ""}]
  end

  test "an unterminated heredoc is a lex error" do
    assert_raise ArgumentError, ~r/unterminated heredoc/, fn -> Lexer.tokenize(~s(\"\"\"oops)) end
  end

  test "an unscannable character is a lex error" do
    assert_raise ArgumentError, ~r/cannot scan/, fn -> Lexer.tokenize("\x00") end
  end

  test "a comment with no trailing newline runs cleanly to end of input" do
    assert Lexer.tokenize("a # trailing comment, no newline") == [{:id, "a"}]
    assert Lexer.tokenize("# whole-line comment, no newline") == []
  end
end
