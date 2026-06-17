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
      {:char, codepoint}          'A' · '+' · '\n' · '\u{1F600}' (ADR-0036, codepoint integer)
      {:num, lexeme}              42 · 3.14 · 1_000 · 1.0e9 (exponent normalized)
      {:op, op}                   operators + word-operators (and/or/not/in/rem/div)
      {:kw, kw}                   keywords (see @keywords)
      {:id, name}                 identifier (optional trailing `?`/`!`: `empty?`, `gate!`)
  """

  # Word-operators (kept as ops so the precedence parser sees them uniformly).
  @op_words ~w(and or not in rem div)

  # Keywords. `if`/`do`/`else`/`end` drive expressions (Pratt); the rest are
  # declaration/`case` keywords for the token-driven declaration parser.
  @keywords ~w(if do else end def type range case when struct alias mod pub const macro use with protocol impl opaque abstract)

  # multi-char operators, matched greedily before the single-char ops. `::` (the
  # bitstring segment-spec separator, ADR-0078) was previously unused in Rian source —
  # an atom is `:name` (single `:`), and type ascription is space-separated, not `::`.
  @multi ["->", "..", ":=", "|>", "<>", "<~", "<-", "<=", ">=", "==", "!=", "::", "=>"]
  # `@` is the as-pattern operator (`name @ pat`); the annotation lane (`@name`,
  # checked first) still wins when `@` is immediately followed by an identifier.
  @single ["+", "-", "*", "/", "<", ">", ".", "|", ":", "&", "@", "^"]

  @num_re ~r/^\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?/
  # Identifiers may carry a single trailing `?` or `!` — the Elixir/Ruby/Crystal
  # predicate/bang convention (ADR-0033): `empty?`, `gate!`. A `!` is part of the
  # name only when it is *not* the start of the `!=` operator, so `a!=b` still
  # lexes as `a`, `!=`, `b`.
  @id_re ~r/^[A-Za-z_]\w*(?:\?|!(?!=))?/

  @typedoc "A lexer token (see the `## Tokens` section above)."
  @type token ::
          {:nl}
          | {:lparen}
          | {:rparen}
          | {:lbracket}
          | {:rbracket}
          | {:lbrace}
          | {:rbrace}
          | {:mapopen}
          | {:comma}
          | {:semi}
          | {:str, String.t()}
          | {:char, non_neg_integer()}
          | {:num, String.t()}
          | {:op, String.t()}
          | {:kw, String.t()}
          | {:id, String.t()}
          | {:annot, String.t()}
          | {:comment, String.t()}
          | {:heredoc, String.t()}
          | {:istr, [{:lit, String.t()} | {:hole, String.t()}]}

  @doc "Full token stream, with collapsed `{:nl}` separators (comments stripped)."
  @spec tokenize(String.t()) :: [token()]
  def tokenize(src), do: src |> lex([]) |> strip_trivia() |> collapse_nl()

  @doc "Newline-free token stream for the expression grammar (`Rian.Pratt`)."
  @spec expr_tokens(String.t()) :: [token()]
  def expr_tokens(src),
    do: src |> lex([]) |> strip_trivia() |> Enum.reject(&(&1 == {:nl}))

  # The compiler pipeline never sees formatter-only trivia: comment tokens are
  # dropped and a raw `{:heredoc, c}` collapses to the trimmed `{:str, …}` the
  # grammar expects (the heredoc is kept verbatim only for `Rian.Format`).
  defp strip_trivia(tokens) do
    tokens
    |> Enum.reject(&match?({:comment, _}, &1))
    |> Enum.map(fn
      {:heredoc, content} -> {:str, String.trim(content)}
      t -> t
    end)
  end

  @doc """
  Trivia-preserving token stream for the source **formatter** (`Rian.Format`).

  Unlike `tokenize/1`, this keeps everything the compiler pipeline throws away:
  `{:comment, text}` tokens (the comment text incl. the leading `#`, trailing
  whitespace trimmed) sit exactly between the tokens they followed in source, and
  `{:nl}` separators are **not** collapsed — so a run of ≥2 `{:nl}` is a blank
  line, recoverable by the formatter. Nothing downstream consumes this; it exists
  solely so `Rian.Format` can re-print without losing comments or paragraphing.
  """
  @spec tokenize_trivia(String.t()) :: [token()]
  def tokenize_trivia(src), do: lex(src, [])

  @doc """
  Render a token list back to a source string (space-joined; re-lexable).

  `nl_as` is the string a `{:nl}` becomes — `";"` turns a block's newline
  statement-separators into the `;` the block grammar expects, `" "` joins a
  continued declaration onto one line.
  """
  @spec detokenize([token()], String.t()) :: String.t()
  def detokenize(tokens, nl_as \\ " ") do
    tokens |> Enum.map_join(" ", &tok_str(&1, nl_as))
  end

  defp tok_str({:nl}, nl_as), do: nl_as
  defp tok_str({:id, x}, _), do: x
  defp tok_str({:num, n}, _), do: n
  defp tok_str({:char, cp}, _), do: "'" <> char_source(cp) <> "'"
  defp tok_str({:str, s}, _), do: ~s(") <> escape_str(s) <> ~s(")

  # round-trip an interpolated string: literal segments re-escape, holes re-emit
  # as `${source}` (ADR-0069 — the detokenizer must not flatten interpolation)
  defp tok_str({:istr, parts}, _) do
    body =
      Enum.map_join(parts, "", fn
        {:lit, s} -> escape_str(s)
        {:hole, src} -> "${" <> src <> "}"
      end)

    ~s(") <> body <> ~s(")
  end

  defp tok_str({:op, o}, _), do: o
  defp tok_str({:kw, k}, _), do: k
  defp tok_str({:annot, a}, _), do: "@" <> a
  defp tok_str({:lparen}, _), do: "("
  defp tok_str({:rparen}, _), do: ")"
  defp tok_str({:lbracket}, _), do: "["
  defp tok_str({:rbracket}, _), do: "]"
  defp tok_str({:lbrace}, _), do: "{"
  defp tok_str({:rbrace}, _), do: "}"
  defp tok_str({:mapopen}, _), do: "%{"
  defp tok_str({:bitopen}, _), do: "<<"
  defp tok_str({:bitclose}, _), do: ">>"
  defp tok_str({:comma}, _), do: ","
  defp tok_str({:semi}, _), do: ";"
  defp tok_str({:comment, text}, _), do: text
  defp tok_str({:heredoc, content}, _), do: ~s(""") <> content <> ~s(""")

  defp advance(s, n), do: elem(String.split_at(s, n), 1)

  # `Char` literal body (ADR-0036): the text after the opening `'`. Returns
  # `{codepoint, rest}` where `rest` is the source past the closing `'`. Exactly
  # one codepoint is allowed — `''` and multi-codepoint `'AB'` are lex errors
  # (Rian has no charlists; use a `"…"` string). Escapes are the full
  # Elixir/Gleam set, see `char_escape/1`.
  defp lex_char("\\" <> rest) do
    {cp, after_escape} = char_escape(rest)
    {cp, close_char(after_escape)}
  end

  defp lex_char("'" <> _), do: raise(ArgumentError, "empty character literal '' — use a string")
  defp lex_char(""), do: raise(ArgumentError, "unterminated character literal")

  defp lex_char(str) do
    {<<cp::utf8>>, rest} = String.next_codepoint(str)
    {cp, close_char(rest)}
  end

  # consume the required closing quote; anything else means a multi-codepoint
  # literal, which is rejected (no charlists).
  defp close_char("'" <> rest), do: rest
  defp close_char(""), do: raise(ArgumentError, "unterminated character literal")

  defp close_char(other),
    do:
      raise(ArgumentError, "character literal must be a single codepoint near: #{inspect(other)}")

  # The escape vocabulary, shared by `Char` and `String` literals — the full
  # Elixir set (a strict superset of Gleam's). Named single-character escapes:
  defp char_escape("a" <> rest), do: {0x07, rest}
  defp char_escape("b" <> rest), do: {0x08, rest}
  defp char_escape("d" <> rest), do: {0x7F, rest}
  defp char_escape("e" <> rest), do: {0x1B, rest}
  defp char_escape("f" <> rest), do: {0x0C, rest}
  defp char_escape("n" <> rest), do: {?\n, rest}
  defp char_escape("r" <> rest), do: {?\r, rest}
  defp char_escape("s" <> rest), do: {0x20, rest}
  defp char_escape("t" <> rest), do: {?\t, rest}
  defp char_escape("v" <> rest), do: {0x0B, rest}
  defp char_escape("0" <> rest), do: {0, rest}
  defp char_escape("\\" <> rest), do: {?\\, rest}
  defp char_escape("'" <> rest), do: {?', rest}
  defp char_escape("\"" <> rest), do: {?", rest}

  # `\xH`/`\xHH` — one or two hex digits (Elixir byte escape), read as a codepoint.
  defp char_escape("x" <> rest) do
    case take_hex(rest, 2) do
      {"", _} -> raise ArgumentError, "`\\x` escape needs at least one hex digit"
      {hex, after_hex} -> {cp!(String.to_integer(hex, 16)), after_hex}
    end
  end

  # `\u{HEX}` — braced Unicode codepoint (Elixir + Gleam), 1–6 hex digits.
  defp char_escape("u{" <> rest) do
    case String.split(rest, "}", parts: 2) do
      [hex, after_brace] when hex != "" -> {cp!(parse_hex!(hex)), after_brace}
      _ -> raise ArgumentError, "empty or unterminated `\\u{...}` escape"
    end
  end

  # `\uHHHH` — exactly four hex digits (Elixir Unicode escape).
  defp char_escape("u" <> rest) do
    case take_hex(rest, 4) do
      {hex, after_hex} when byte_size(hex) == 4 ->
        {cp!(String.to_integer(hex, 16)), after_hex}

      _ ->
        raise ArgumentError, "`\\u` escape needs four hex digits — or use `\\u{...}`"
    end
  end

  defp char_escape(other),
    do: raise(ArgumentError, "unknown character escape near: #{inspect(other)}")

  # take up to `max` leading hex digits; returns `{taken, rest}`.
  defp take_hex(str, max), do: take_hex(str, max, "")

  defp take_hex(<<c, rest::binary>>, max, acc)
       when max > 0 and
              ((c >= ?0 and c <= ?9) or (c >= ?a and c <= ?f) or (c >= ?A and c <= ?F)),
       do: take_hex(rest, max - 1, <<acc::binary, c>>)

  defp take_hex(str, _max, acc), do: {acc, str}

  defp parse_hex!(hex) do
    if hex =~ ~r/\A[0-9a-fA-F]+\z/,
      do: String.to_integer(hex, 16),
      else: raise(ArgumentError, "invalid hex digits in escape: #{inspect(hex)}")
  end

  # a valid scalar Unicode codepoint (no surrogates, ≤ U+10FFFF).
  defp cp!(n) when n in 0..0xD7FF or n in 0xE000..0x10FFFF, do: n

  defp cp!(n),
    do: raise(ArgumentError, "codepoint out of range or a surrogate: #{inspect(n)}")

  # String literal body scanner (the text after the opening `"`). Returns
  # `{decoded, rest}` where `decoded` is the string value with escapes resolved
  # and `rest` is the source past the closing `"`. Honors the same escapes as
  # `char_escape/1`, so `"a\"b"` lexes to the value `a"b` rather than terminating
  # early on the inner quote.
  # A regular `"…"` string with optional `${expr}` interpolation holes (ADR-0069).
  # Returns `{:str, binary}` when there are no holes, else `{:istr, parts}` where
  # `parts` interleaves `{:lit, binary}` (escape-decoded) and `{:hole, source}`
  # (raw expression text, parsed later by `Rian.Pratt`).
  defp lex_string_token(str) do
    {parts, rest} = lex_parts(str, [], [])
    {string_token(parts), rest}
  end

  defp lex_parts("", _lit, _parts), do: raise(ArgumentError, "unterminated string literal")

  defp lex_parts("\"" <> rest, lit, parts),
    do: {Enum.reverse([{:lit, binify(lit)} | parts]), rest}

  # interpolation hole `${expr}` (ADR-0069) — a `$` is special only when followed by
  # `{`; a bare `$` (e.g. `"$5.00"`) is an ordinary character via the default clause.
  defp lex_parts("${" <> rest, lit, parts) do
    {src, rest2} = capture_hole(rest, 0, [])
    lex_parts(rest2, [], [{:hole, src}, {:lit, binify(lit)} | parts])
  end

  # `\$` is a literal `$` — the only escape `$` needs, so a literal `${` is `\${`.
  # MUST precede the general `\\` escape clause.
  defp lex_parts("\\$" <> rest, lit, parts), do: lex_parts(rest, ["$" | lit], parts)

  defp lex_parts("\\" <> rest, lit, parts) do
    {cp, after_escape} = char_escape(rest)
    lex_parts(after_escape, [<<cp::utf8>> | lit], parts)
  end

  defp lex_parts(str, lit, parts) do
    {ch, rest} = String.next_codepoint(str)
    lex_parts(rest, [ch | lit], parts)
  end

  # capture a hole's raw source up to its matching `}` (brace-depth aware, so a map
  # or struct literal inside a hole nests correctly). The source is parsed later by
  # `Rian.Pratt` (it re-enters the expression grammar); a string literal containing
  # `}` inside a hole is out of scope (ADR-0069 discourages nesting strings in holes).
  defp capture_hole("", _d, _acc),
    do: raise(ArgumentError, "unterminated interpolation hole `${` in string")

  defp capture_hole("}" <> rest, 0, acc), do: {binify(acc), rest}
  defp capture_hole("}" <> rest, d, acc), do: capture_hole(rest, d - 1, ["}" | acc])
  defp capture_hole("{" <> rest, d, acc), do: capture_hole(rest, d + 1, ["{" | acc])

  defp capture_hole(str, d, acc) do
    {ch, rest} = String.next_codepoint(str)
    capture_hole(rest, d, [ch | acc])
  end

  defp binify(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # no holes -> a plain `{:str, s}`; otherwise the structured `{:istr, parts}`
  defp string_token(parts) do
    if Enum.any?(parts, &match?({:hole, _}, &1)) do
      {:istr, parts}
    else
      {:str, parts |> Enum.map_join("", fn {:lit, s} -> s end)}
    end
  end

  # re-lexable rendering of a codepoint inside `'…'` (the inverse of `lex_char/1`).
  # Backslash and the single quote must be escaped; other control codepoints fall
  # back to `\u{HEX}` so any value round-trips.
  defp char_source(?\n), do: "\\n"
  defp char_source(?\t), do: "\\t"
  defp char_source(?\r), do: "\\r"
  defp char_source(0), do: "\\0"
  defp char_source(?\\), do: "\\\\"
  defp char_source(?'), do: "\\'"

  defp char_source(cp) when cp < 0x20 or cp == 0x7F,
    do: "\\u{" <> Integer.to_string(cp, 16) <> "}"

  defp char_source(cp), do: <<cp::utf8>>

  # re-escape a decoded string value for rendering inside `"…"` (the inverse of
  # `lex_string/2`), one codepoint at a time.
  defp escape_str(s), do: for(<<cp::utf8 <- s>>, into: "", do: str_cp_source(cp))

  # rendering of a single codepoint inside a `"…"` body. Backslash and the double
  # quote must be escaped; control codepoints fall back to `\u{HEX}`.
  defp str_cp_source(?\\), do: "\\\\"
  defp str_cp_source(?"), do: "\\\""
  defp str_cp_source(?\n), do: "\\n"
  defp str_cp_source(?\t), do: "\\t"
  defp str_cp_source(?\r), do: "\\r"

  defp str_cp_source(cp) when cp < 0x20 or cp == 0x7F,
    do: "\\u{" <> Integer.to_string(cp, 16) <> "}"

  defp str_cp_source(cp), do: <<cp::utf8>>

  defp lex(str, acc) do
    cond do
      str == "" ->
        Enum.reverse(acc)

      String.starts_with?(str, [" ", "\t", "\r"]) ->
        lex(advance(str, 1), acc)

      String.starts_with?(str, "\n") ->
        lex(advance(str, 1), [{:nl} | acc])

      String.starts_with?(str, "#") ->
        {comment, rest} = take_comment(str)
        lex(rest, [{:comment, comment} | acc])

      String.starts_with?(str, "%{") ->
        lex(advance(str, 2), [{:mapopen} | acc])

      # bitstring delimiters (ADR-0078) — must precede the `<`/`>` single ops.
      String.starts_with?(str, "<<") ->
        lex(advance(str, 2), [{:bitopen} | acc])

      String.starts_with?(str, ">>") ->
        lex(advance(str, 2), [{:bitclose} | acc])

      # `@name` — the annotation lane (`@doc`/`@moduledoc`/`@typedoc`, `@wire`, …)
      m = Regex.run(~r/^@([A-Za-z_]\w*)/, str) ->
        [full, name] = m
        lex(advance(str, String.length(full)), [{:annot, name} | acc])

      (punct = punct(str)) != nil ->
        lex(advance(str, 1), [punct | acc])

      # heredoc `"""…"""` — multi-line string (doc content, ADR-0051); must precede `"`.
      # The raw (untrimmed) content is kept in a `{:heredoc, c}` token so the formatter
      # can reproduce the block verbatim; `strip_trivia/1` trims it to `{:str, …}` for
      # the compiler.
      String.starts_with?(str, ~s(""")) ->
        case String.split(advance(str, 3), ~s("""), parts: 2) do
          [content, rest] -> lex(rest, [{:heredoc, content} | acc])
          [_] -> raise ArgumentError, "unterminated heredoc string"
        end

      String.starts_with?(str, "\"") ->
        {token, rest} = lex_string_token(advance(str, 1))
        lex(rest, [token | acc])

      # `Char` literal `'A'` (ADR-0036) — exactly one codepoint between single
      # quotes (Crystal-style); the parser desugars it to its codepoint integer.
      String.starts_with?(str, "'") ->
        {cp, rest} = lex_char(advance(str, 1))
        lex(rest, [{:char, cp} | acc])

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

  # A `#` line comment, kept as a `{:comment, text}` token for the formatter.
  # Returns the trimmed comment text (incl. the leading `#`) and the rest of the
  # source with the terminating `\n` preserved, so the next `{:nl}` still fires.
  defp take_comment(str) do
    case String.split(str, "\n", parts: 2) do
      [comment, rest] -> {String.trim_trailing(comment), "\n" <> rest}
      [only] -> {String.trim_trailing(only), ""}
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
