defmodule Rian.Lexer do
  @moduledoc """
  The single tokenizer for Rian source — the "lexer" half of Stage 0.1
  (ADR-0031). It is the foundation a token-driven declaration parser needs to
  handle the constructs the line-based `Rian.Decl` MVP cannot: `do … end` block
  bodies, `case … end`, and contiguous multi-clause groups — because `do`/`end`/
  `;` and **significant newlines** become real tokens here.

  `Rian.Pratt` consumes `expr_tokens/1` (the newline-free stream), so the
  expression grammar is unchanged; a future declaration parser consumes the full
  `tokenize/1` stream (with `{:nl}` separators and the declaration keywords).

  ## Tokens

      {:nl}                       significant newline (collapsed runs; full stream only)
      {:lparen} {:rparen}         ( )
      {:lbracket} {:rbracket}     [ ]
      {:lbrace} {:rbrace}         { }
      {:mapopen}                  %{
      {:comma} {:semi}            , ;
      {:str, content}             "…"
      {:num, lexeme}              42 · 3.14 · 1_000 · 1.0e9 (exponent normalized)
      {:op, op}                   operators + word-operators (and/or/not/in/rem/div)
      {:kw, kw}                   keywords (see @keywords)
      {:id, name}                 identifier
  """

  # Word-operators (kept as ops so the precedence parser sees them uniformly).
  @op_words ~w(and or not in rem div)

  # Keywords. `if`/`do`/`else`/`end` drive expressions (Pratt); the rest are
  # declaration/`case` keywords for the token-driven declaration parser.
  @keywords ~w(if do else end def type case when struct alias mod pub const macro use)

  @multi ["->", ":=", "|>", "<>", "<~", "<-", "<=", ">=", "==", "!="]
  @single ["+", "-", "*", "/", "<", ">", ".", "|", ":", "&"]

  @num_re ~r/^\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?/
  @id_re ~r/^[A-Za-z_]\w*/

  @doc "Full token stream, with collapsed `{:nl}` separators."
  def tokenize(src), do: src |> lex([]) |> collapse_nl()

  @doc "Newline-free token stream for the expression grammar (`Rian.Pratt`)."
  def expr_tokens(src), do: src |> lex([]) |> Enum.reject(&(&1 == {:nl}))

  @doc """
  Render a token list back to a source string (space-joined; re-lexable).

  `nl_as` is the string a `{:nl}` becomes — `";"` turns a block's newline
  statement-separators into the `;` the block grammar expects, `" "` joins a
  continued declaration onto one line.
  """
  def detokenize(tokens, nl_as \\ " ") do
    tokens |> Enum.map_join(" ", &tok_str(&1, nl_as))
  end

  defp tok_str({:nl}, nl_as), do: nl_as
  defp tok_str({:id, x}, _), do: x
  defp tok_str({:num, n}, _), do: n
  defp tok_str({:str, s}, _), do: ~s("#{s}")
  defp tok_str({:op, o}, _), do: o
  defp tok_str({:kw, k}, _), do: k
  defp tok_str({:lparen}, _), do: "("
  defp tok_str({:rparen}, _), do: ")"
  defp tok_str({:lbracket}, _), do: "["
  defp tok_str({:rbracket}, _), do: "]"
  defp tok_str({:lbrace}, _), do: "{"
  defp tok_str({:rbrace}, _), do: "}"
  defp tok_str({:mapopen}, _), do: "%{"
  defp tok_str({:comma}, _), do: ","
  defp tok_str({:semi}, _), do: ";"

  defp advance(s, n), do: elem(String.split_at(s, n), 1)

  defp lex(str, acc) do
    cond do
      str == "" ->
        Enum.reverse(acc)

      String.starts_with?(str, [" ", "\t", "\r"]) ->
        lex(advance(str, 1), acc)

      String.starts_with?(str, "\n") ->
        lex(advance(str, 1), [{:nl} | acc])

      String.starts_with?(str, "#") ->
        lex(skip_line(str), acc)

      String.starts_with?(str, "%{") ->
        lex(advance(str, 2), [{:mapopen} | acc])

      (punct = punct(str)) != nil ->
        lex(advance(str, 1), [punct | acc])

      String.starts_with?(str, "\"") ->
        case String.split(advance(str, 1), "\"", parts: 2) do
          [content, rest] -> lex(rest, [{:str, content} | acc])
          [_] -> raise ArgumentError, "unterminated string literal"
        end

      op = Enum.find(@multi, &String.starts_with?(str, &1)) ->
        lex(advance(str, String.length(op)), [{:op, op} | acc])

      op = Enum.find(@single, &String.starts_with?(str, &1)) ->
        lex(advance(str, 1), [{:op, op} | acc])

      m = Regex.run(@num_re, str) ->
        lexeme = hd(m)
        lex(advance(str, String.length(lexeme)), [{:num, norm_num(lexeme)} | acc])

      m = Regex.run(@id_re, str) ->
        w = hd(m)
        lex(advance(str, String.length(w)), [word(w) | acc])

      true ->
        raise ArgumentError, "cannot scan: #{inspect(str)}"
    end
  end

  defp punct(str) do
    case str do
      "(" <> _ -> {:lparen}
      ")" <> _ -> {:rparen}
      "[" <> _ -> {:lbracket}
      "]" <> _ -> {:rbracket}
      "{" <> _ -> {:lbrace}
      "}" <> _ -> {:rbrace}
      "," <> _ -> {:comma}
      ";" <> _ -> {:semi}
      _ -> nil
    end
  end

  defp word(w) do
    cond do
      w in @op_words -> {:op, w}
      w in @keywords -> {:kw, w}
      true -> {:id, w}
    end
  end

  defp skip_line(str) do
    case String.split(str, "\n", parts: 2) do
      [_comment, rest] -> "\n" <> rest
      [_only] -> ""
    end
  end

  # Normalize an exponent-without-point lexeme (`1e9`) to `1.0e9` — valid on both
  # targets (invalid as `1e9` in Elixir).
  defp norm_num(lexeme) do
    if String.match?(lexeme, ~r/[eE]/) and not String.contains?(lexeme, ".") do
      String.replace(lexeme, ~r/[eE]/, ".0e", global: false)
    else
      lexeme
    end
  end

  # Collapse runs of newlines to one separator and drop leading/trailing ones.
  defp collapse_nl(tokens) do
    tokens
    |> Enum.chunk_by(&(&1 == {:nl}))
    |> Enum.map(fn
      [{:nl} | _] -> {:nl}
      chunk -> chunk
    end)
    |> List.flatten()
    |> Enum.drop_while(&(&1 == {:nl}))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == {:nl}))
    |> Enum.reverse()
  end
end
