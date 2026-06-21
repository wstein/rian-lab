# Generates purs/test/fixtures/lexer.fixtures — the parity oracle for the PureScript
# lexer port (ADR-0084). Runs the Elixir reference `Rian.Lexer` over a corpus and writes,
# per record: `<stream>\t<hex(source)>\t<canonical-tokens>`. The Erlang harness
# (scripts/lexer-parity.sh) re-lexes each source with the purerl-compiled lexer and asserts
# the same canonical string. Run from the repo root: `mix run purs/test/gen_fixtures.exs`.
defmodule Canon do
  # Canonical, language-agnostic serialization of a token list. String payloads are
  # lowercase hex of their UTF-8 bytes so the line is delimiter-safe and byte-identical
  # to the Erlang harness's serializer.
  def tokens(toks), do: Enum.map_join(toks, "|", &tok/1)

  defp tok({:nl}), do: "nl"
  defp tok({:lparen}), do: "lparen"
  defp tok({:rparen}), do: "rparen"
  defp tok({:lbracket}), do: "lbracket"
  defp tok({:rbracket}), do: "rbracket"
  defp tok({:lbrace}), do: "lbrace"
  defp tok({:rbrace}), do: "rbrace"
  defp tok({:mapopen}), do: "mapopen"
  defp tok({:bitopen}), do: "bitopen"
  defp tok({:bitclose}), do: "bitclose"
  defp tok({:comma}), do: "comma"
  defp tok({:semi}), do: "semi"
  defp tok({:str, s}), do: "str:" <> hex(s)
  defp tok({:char, n}), do: "char:" <> Integer.to_string(n)
  defp tok({:num, s}), do: "num:" <> hex(s)
  defp tok({:op, s}), do: "op:" <> hex(s)
  defp tok({:kw, s}), do: "kw:" <> hex(s)
  defp tok({:id, s}), do: "id:" <> hex(s)
  defp tok({:annot, s}), do: "annot:" <> hex(s)
  defp tok({:comment, s}), do: "comment:" <> hex(s)
  defp tok({:heredoc, s}), do: "heredoc:" <> hex(s)
  defp tok({:istr, parts}), do: "istr:" <> Enum.map_join(parts, ",", &part/1)

  defp part({:lit, s}), do: "lit=" <> hex(s)
  defp part({:hole, s}), do: "hole=" <> hex(s)

  def hex(s), do: Base.encode16(s, case: :lower)
end

alias Rian.Lexer

# Sources that lex successfully (error cases are covered by the Elixir suite).
corpus = [
  "a + b",
  "if c do a else b end",
  "empty?",
  "gate!",
  "Reach.gate!(prog)",
  "a != b",
  "a!=b",
  "n @ p",
  "@doc",
  "1_000",
  "3.14",
  "1e9",
  "1E9",
  "1.5e-3",
  "6.022e23",
  "0xff",
  ~s("hi"),
  ~S|"a\"b"|,
  ~S|"a\\b"|,
  ~S|"line\nbreak"|,
  ~S|"tab\there"|,
  ~S|f("say \"hi\"")|,
  ~S|"\a\b\d\e\f\r\s\v\0"|,
  ~S|"\x41"|,
  ~S|"\x7"|,
  ~S|"\u{e9}"|,
  ~S|"é"|,
  ~S|"\u{1F600}"|,
  ~S|"café"|,
  "a and not b",
  "'A'",
  "'+'",
  "' '",
  "c == '0'",
  ~S('\n'),
  ~S('\t'),
  ~S('\\'),
  ~S('\''),
  ~S('\0'),
  "'\\u{1F600}'",
  "'é'",
  "\n\na\n\n\nb\n\n",
  "def case when type struct alias mod pub const macro use",
  "a # ignored\nb",
  "a # trailing comment, no newline",
  "# whole-line comment, no newline",
  "def area(s val Shape) Float64\n  case s do\n    Circle(r) -> pi * r * r\n  end\nend\n",
  "%{a: 1, end: 2}",
  "<<1, 2>>",
  ":==",
  ":<>",
  ":and",
  "a :: b",
  "x := 2",
  ~S|"a${b}c"|,
  ~S|"${x + 1}"|,
  ~S|"$5.00"|,
  ~S|"pre${ %{k: v} }post"|,
  "\"\"\"hi\"\"\"",
  "\"\"\"\"\"\""
]

# Sources for detokenize round-trips (rendered back to a re-lexable string).
detok_corpus = [
  "a + b",
  "'A'",
  ~S('\n'),
  ~S('\t'),
  ~S('\r'),
  ~S('\0'),
  ~S|"a\"b"|,
  ~S|"a\\b"|,
  ~S|"a\nb"|,
  "@doc",
  ":and",
  "x := 2"
]

lines =
  Enum.flat_map(corpus, fn src ->
    [
      "tok\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.tokenize(src))}",
      "expr\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.expr_tokens(src))}",
      "triv\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.tokenize_trivia(src))}"
    ]
  end) ++
    Enum.flat_map(detok_corpus, fn src ->
      [
        "detok\t#{Canon.hex(src)}\t#{Canon.hex(Lexer.detokenize(Lexer.tokenize(src)))}",
        "detok;\t#{Canon.hex(src)}\t#{Canon.hex(Lexer.detokenize(Lexer.tokenize(src), ";"))}"
      ]
    end)

path = Path.join([__DIR__, "fixtures", "lexer.fixtures"])
File.mkdir_p!(Path.dirname(path))
File.write!(path, Enum.join(lines, "\n") <> "\n")
IO.puts("wrote #{length(lines)} fixture records to #{path}")
