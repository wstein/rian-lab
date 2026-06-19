defmodule Rian.Format.Cst do
  @moduledoc """
  A **bracket-structured, lossless** token tree for the formatter — the concrete
  syntax tree the wrapping pass (`Rian.Format` Tier 2) walks.

  Inspired by lossless/concrete syntax trees (Rowan, Roslyn red-green, Swift
  libsyntax): **every** token from `Rian.Lexer.tokenize_trivia/1` — including
  `{:comment}`, `{:heredoc}` and `{:nl}` — is preserved. The only structure
  imposed is **bracket nesting**: a matched `( ) · [ ] · { } · %{ }` pair becomes a
  `{:group, open, children, close}` node whose children are the (recursively
  parsed) tokens between the delimiters. Everything else — `do`/`end`, operators,
  identifiers, newlines — stays a flat `{:tok, token}` node.

  Why bracket-only: reflow is meaning-safe **only inside brackets** (where Rian's
  parser is newline-tolerant), so those are the regions that become reflowable
  groups. Block (`do…end`) and statement structure is handled by `Rian.Format`'s
  line/indent skeleton, not here — so a `do`/`end` without a matching `{:group}`
  (e.g. a block-form `def` body) is no problem: they are just flat tokens.

  ## Node shapes

      {:tok, token}                       a single token (incl. comment / nl / heredoc)
      {:group, open_tok, [node], close}   a bracket-delimited, reflowable region

  Building is **total**: an unbalanced opener degrades to a plain `{:tok}` rather
  than raising, so a malformed file still produces a (best-effort) tree.
  """

  use Rian.Ann

  @typedoc "A CST node: a single token, or a bracket-delimited group of nodes."
  @type node_t ::
          {:tok, Rian.Lexer.token()}
          | {:group, Rian.Lexer.token(), [node_t()], Rian.Lexer.token()}

  @rian_sig "pub def build(tokens Vec(_Unk)) Vec(_Unk)"
  @doc "Build the bracket-structured node list for a trivia token stream."
  @spec build([Rian.Lexer.token()]) :: [node_t()]
  def build(tokens), do: elem(seq(tokens, []), 0)

  # seq/2 → {nodes, rest}: consume tokens into nodes until a closer/`end`-less
  # EOF; `rest` begins at the first unconsumed closing bracket (left for `open/4`).
  defp seq([], acc), do: {Enum.reverse(acc), []}

  defp seq([{:lparen} = o | rest], acc), do: open(o, {:rparen}, rest, acc)
  defp seq([{:lbracket} = o | rest], acc), do: open(o, {:rbracket}, rest, acc)
  defp seq([{:lbrace} = o | rest], acc), do: open(o, {:rbrace}, rest, acc)
  defp seq([{:mapopen} = o | rest], acc), do: open(o, {:rbrace}, rest, acc)

  defp seq([{:rparen} | _] = toks, acc), do: {Enum.reverse(acc), toks}
  defp seq([{:rbracket} | _] = toks, acc), do: {Enum.reverse(acc), toks}
  defp seq([{:rbrace} | _] = toks, acc), do: {Enum.reverse(acc), toks}

  defp seq([t | rest], acc), do: seq(rest, [{:tok, t} | acc])

  # consume an opener; recurse for the body; require the matching closer, else
  # degrade the opener to a plain token (keeps `build/1` total on malformed input)
  defp open(open_tok, close, rest, acc) do
    {inner, rest2} = seq(rest, [])

    case rest2 do
      [^close | rest3] -> seq(rest3, [{:group, open_tok, inner, close} | acc])
      _ -> seq(rest, [{:tok, open_tok} | acc])
    end
  end
end
