defmodule Rian.Format do
  @moduledoc """
  The canonical Rian source formatter — a gofmt-style, **opinionated, zero-config**
  re-printer. `format/1` takes `.rian` source and returns the formatted source.

  ## How it works (and why it can't change meaning)

  The formatter is a **token-stream pretty-printer** built on
  `Rian.Lexer.tokenize_trivia/1`. It deliberately does **not** parse: it never
  builds an AST, so it cannot mis-lower a construct the parser doesn't model, and
  it cannot reorder or drop program structure.

  Two facts about Rian make this safe and total:

    * **Indentation is never tokenized.** Leading whitespace is consumed silently
      by the lexer, so the formatter may re-indent freely without touching the
      token stream the compiler sees.
    * **Newlines are significant** (`{:nl}` tokens drive declaration boundaries and
      block bodies, ADR-0031). So the formatter **preserves newline placement
      exactly** — it never inserts or removes a newline between code tokens. It
      only (a) collapses runs of ≥2 blank lines to one, (b) normalizes indentation,
      (c) normalizes intra-line spacing, and (d) trims trailing whitespace.

  Together these give the correctness contract, enforced by the test suite:

    * **Re-lex equivalence** — `tokenize(format(src)) == tokenize(src)`. Same
      program. (The analog of `Rian.FormsEquiv` for the BEAM backend.)
    * **Idempotence** — `format(format(src)) == format(src)`.
    * **Comment fidelity** — every `{:comment}` survives at its authored position
      (trailing comments stay on their line, own-line comments keep their place);
      heredocs (`\"""…\"""`) are reproduced verbatim.

  ## Style

    * 2-space indent, one level per `do`-block / block-form `def` body / open
      bracket; lines that open with a closer (`end`/`)`/`]`/`}`/`else`/`when`)
      dedent one step; lines that open with a continuation operator (a leading
      `|`, `|>`, …) indent one step.
    * One space around binary operators and after `,`/`;`; none after an opener,
      before a closer, around `.`, after a unary `-`/`+`, or inside `f(x)`/`xs[0]`.
    * At most one blank line anywhere; no leading/trailing blank lines; the file
      ends in a single newline.
  """

  alias Rian.Lexer

  @doc "Format Rian source. Total: never raises on valid `.rian`, returns a string."
  def format(src) when is_binary(src) do
    src
    |> Lexer.tokenize_trivia()
    |> rows()
    |> indent_rows([0], 0, [])
    |> squeeze_blanks()
    |> Enum.map_join("", &(&1 <> "\n"))
  end

  # ── split the token stream into rows (one per source line) ────────────────
  # Each `{:nl}` ends a row; an empty row is a blank line. Comment/heredoc tokens
  # ride along inside their row, so their position is preserved verbatim.
  defp rows(tokens), do: rows(tokens, [], [])
  defp rows([], cur, acc), do: Enum.reverse([Enum.reverse(cur) | acc])
  defp rows([{:nl} | rest], cur, acc), do: rows(rest, [], [Enum.reverse(cur) | acc])
  defp rows([t | rest], cur, acc), do: rows(rest, [t | cur], acc)

  # ── assign each row an indent and render it ───────────────────────────────
  # `stack` holds the indent level for content at each open nesting (top = the
  # current body indent); `cont` is 1 when the previous code row ended in a
  # trailing binary operator, so this row is its continuation and indents once.
  # Each opener (`do` / block-form `def` / open bracket) pushes `line + 1`, so a
  # block opened on a continued line nests under the *continued* position — which
  # is why a multi-line `case` arm body lands correctly.
  defp indent_rows([], _stack, _cont, acc), do: Enum.reverse(acc)

  defp indent_rows([row | rest], stack, cont, acc) do
    if blank?(row) do
      indent_rows(rest, stack, cont, ["" | acc])
    else
      level = max(0, hd(stack) + cont + lead_adjust(row))
      line = String.duplicate("  ", level) <> render(mark(row))
      stack = update_stack(row, rest, level, stack)
      cont = if trailing_op?(row), do: 1, else: 0
      indent_rows(rest, stack, cont, [line | acc])
    end
  end

  # Apply this row's openers/closers to the indent stack. An opener pushes the
  # body indent (`level + 1`); a closer pops back. A block-form `def`/`macro`
  # head (no `do` token) pushes once for its implicit body.
  defp update_stack(row, rest, level, stack) do
    stack = Enum.reduce(row, stack, fn t, st -> apply_tok(t, level, st) end)
    if block_head?(row, rest), do: push(level, stack), else: stack
  end

  defp apply_tok({:kw, "do"}, level, st), do: push(level, st)
  defp apply_tok({:lparen}, level, st), do: push(level, st)
  defp apply_tok({:lbracket}, level, st), do: push(level, st)
  defp apply_tok({:lbrace}, level, st), do: push(level, st)
  defp apply_tok({:mapopen}, level, st), do: push(level, st)
  defp apply_tok({:kw, "end"}, _level, st), do: pop(st)
  defp apply_tok({:rparen}, _level, st), do: pop(st)
  defp apply_tok({:rbracket}, _level, st), do: pop(st)
  defp apply_tok({:rbrace}, _level, st), do: pop(st)
  defp apply_tok(_t, _level, st), do: st

  defp push(level, st), do: [level + 1 | st]
  defp pop([_top, next | rest]), do: [next | rest]
  defp pop(st), do: st

  defp trailing_op?(row) do
    case List.last(row) do
      {:op, _} -> true
      _ -> false
    end
  end

  # a row is blank iff it has no tokens at all (a comment-only row is NOT blank)
  defp blank?([]), do: true
  defp blank?(_), do: false

  # First-token indent nudge: a row opening with a closer dedents one level; a row
  # opening with a continuation operator (leading `|`, `|>`, `<>`, …) indents one.
  defp lead_adjust([first | _]) do
    cond do
      closer_lead?(first) -> -1
      cont_lead?(first) -> 1
      true -> 0
    end
  end

  defp closer_lead?({:kw, k}) when k in ~w(end else when), do: true
  defp closer_lead?({:rparen}), do: true
  defp closer_lead?({:rbracket}), do: true
  defp closer_lead?({:rbrace}), do: true
  defp closer_lead?(_), do: false

  defp cont_lead?({:op, _}), do: true
  defp cont_lead?(_), do: false

  # A `def`/`macro` head opens a block body iff it carries no `:=` one-liner and
  # the next code line is not a declaration boundary (mirrors `Rian.Decl`'s
  # `take_head`/`decl_boundary?`). `do`-bearing heads are caught by `tok_delta`.
  defp block_head?([{:kw, "pub"} | rest], next), do: block_head?(rest, next)

  defp block_head?([{:kw, k} | _] = row, rest) when k in ~w(def macro) do
    not has_assign?(row) and not has_do?(row) and not boundary?(next_code_row(rest))
  end

  defp block_head?(_, _), do: false

  defp has_assign?(row), do: Enum.any?(row, &(&1 == {:op, ":="}))
  defp has_do?(row), do: Enum.any?(row, &(&1 == {:kw, "do"}))

  # the next row carrying real code, skipping blank and comment-only rows
  defp next_code_row([]), do: nil
  defp next_code_row([row | rest]) do
    if blank?(row) or comment_only?(row), do: next_code_row(rest), else: row
  end

  # only reached for non-empty rows (callers guard with `blank?/1` first)
  defp comment_only?(row), do: Enum.all?(row, &match?({:comment, _}, &1))

  defp boundary?(nil), do: true
  defp boundary?([{:kw, "end"} | _]), do: true
  defp boundary?([{:annot, _} | _]), do: true

  defp boundary?([{:kw, k} | _]),
    do: k in ~w(type def struct alias mod pub const macro use import protocol impl opaque abstract)

  defp boundary?(_), do: false

  # ── intra-line rendering with context-sensitive spacing ───────────────────
  defp render([]), do: ""
  defp render([t | rest]), do: leaf(t) <> render_rest(rest, t)

  defp render_rest([], _prev), do: ""

  defp render_rest([t | rest], prev) do
    sep = if space?(prev, t), do: " ", else: ""
    sep <> leaf(t) <> render_rest(rest, t)
  end

  defp leaf({:uop, o}), do: o
  defp leaf({:kcolon}), do: ":"
  defp leaf({:acolon}), do: ":"
  defp leaf(t), do: Lexer.detokenize([t])

  # `mark/1` resolves the two context-dependent tokens up front, so `space?/2`
  # is a pure pairwise function: `-`/`+` → `{:uop}` when unary, `:` → `{:kcolon}`
  # (map/keyword key) or `{:acolon}` (atom prefix like `:lists`).
  defp mark(row), do: mark(row, nil, [])
  defp mark([], _prev, acc), do: Enum.reverse(acc)

  defp mark([{:op, o} | rest], prev, acc) when o in ["-", "+"] do
    t = if value_end?(prev), do: {:op, o}, else: {:uop, o}
    mark(rest, t, [t | acc])
  end

  defp mark([{:op, ":"} | rest], prev, acc) do
    t = if value_end?(prev), do: {:kcolon}, else: {:acolon}
    mark(rest, t, [t | acc])
  end

  defp mark([t | rest], _prev, acc), do: mark(rest, t, [t | acc])

  # a token that ends a value (so a following `-`/`+` is binary, a `:` is a key)
  defp value_end?({:id, _}), do: true
  defp value_end?({:num, _}), do: true
  defp value_end?({:str, _}), do: true
  defp value_end?({:istr, _}), do: true
  defp value_end?({:char, _}), do: true
  defp value_end?({:rparen}), do: true
  defp value_end?({:rbracket}), do: true
  defp value_end?({:rbrace}), do: true
  defp value_end?(_), do: false

  # `space?(prev, cur)` — is a single space wanted between these two tokens?
  # Clause order matters; the no-space cases come before the call/group cases.
  defp space?(_prev, {:rparen}), do: false
  defp space?(_prev, {:rbracket}), do: false
  defp space?(_prev, {:rbrace}), do: false
  defp space?(_prev, {:comma}), do: false
  defp space?(_prev, {:semi}), do: false
  defp space?({:lparen}, _cur), do: false
  defp space?({:lbracket}, _cur), do: false
  defp space?({:lbrace}, _cur), do: false
  defp space?({:mapopen}, _cur), do: false
  defp space?({:op, "."}, _cur), do: false
  defp space?(_prev, {:op, "."}), do: false
  defp space?({:uop, _}, _cur), do: false
  defp space?({:acolon}, _cur), do: false
  defp space?(_prev, {:kcolon}), do: false
  # `f(`, `xs[` — application/index binds tightly; grouping `(`/literal `[` does not.
  defp space?(prev, {:lparen}), do: not value_end?(prev)
  defp space?(prev, {:lbracket}), do: not value_end?(prev)
  defp space?(_prev, _cur), do: true

  # ── blank-line policy: collapse runs, trim edges ──────────────────────────
  defp squeeze_blanks(lines) do
    lines
    |> drop_edge_blanks()
    |> collapse_runs([])
  end

  defp drop_edge_blanks(lines) do
    lines
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp collapse_runs([], acc), do: Enum.reverse(acc)
  defp collapse_runs(["", "" | rest], acc), do: collapse_runs(["" | rest], acc)
  defp collapse_runs([l | rest], acc), do: collapse_runs(rest, [l | acc])
end
