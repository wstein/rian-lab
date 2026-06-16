defmodule Rian.Format do
  @moduledoc """
  The canonical Rian source formatter — a gofmt-style, **opinionated, zero-config**
  re-printer. `format/1` takes `.rian` source and returns the formatted source.

  ## Pipeline

      tokenize_trivia → Cst.build → logical lines → per-line Doc → Doc.render

  The formatter never builds a semantic AST and never reparses. It lexes with
  trivia preserved (`Rian.Lexer.tokenize_trivia/1`), groups tokens into a
  bracket-structured lossless tree (`Rian.Format.Cst`), splits the top level into
  logical lines on significant newlines, lowers each line to a pretty-printing
  document, and renders it with the Lindig engine (`Rian.Format.Doc`) against a
  fixed column budget.

  ## What it does

    * **Indentation + intra-line spacing** are re-derived from structure (2-space
      indent, one level per `do`-block / block-form `def` body).
    * **Bracket interiors reflow** (Tier 2): a call's arguments, a list/map/tuple,
      or a parenthesized expression collapse onto one line when they fit the
      98-column budget, and otherwise break **one item per line** with a trailing
      comma. A bracket region containing a line comment is forced to break.
    * **Operator chains reflow** (depth-0 continuation): a top-level `:=` body that
      is a flat `|>`/`and`/`or`/`<>` chain collapses when it fits and otherwise
      breaks **leading-operator, one stage per line** with a one-level hanging
      indent. Confined to declaration bodies — `Rian.Decl`'s `take_line` continues
      across a newline adjacent to such an operator there (P1), but a block-internal
      bind's newline becomes a `;`, so those are left intact.
    * **Block newline placement is preserved** — the formatter does not collapse or
      expand `do…end` blocks; those statement newlines are significant.
    * Blank-line runs collapse to one; comments and heredocs are kept verbatim at
      their authored position.

  ## Why it can't change meaning

  `Rian.Decl.detokenize` is whitespace-invariant, the parser is newline-tolerant
  inside brackets and adjacent to a `@cont_ops` operator in a `:=` body, and it
  accepts a trailing comma identically — so the formatter's edits (reflow
  whitespace/newlines in those positions, plus an optional trailing comma before a
  closer) are all parse-insignificant. The oracle is **significant-token
  equivalence** (drop exactly those insignificant tokens, assert the rest is
  identical — the analog of `Rian.FormsEquiv` for the BEAM backend), backed by a
  **parse-still-valid** guard over the corpus, plus idempotence and comment
  fidelity. (Full-AST equality is *not* used: `Rian.Decl.parse` is non-deterministic
  under macro hygiene — fresh `__h<n>` gensyms — so it would need perpetual
  alpha-renaming for no extra safety.)
  """

  alias Rian.Lexer
  alias Rian.Format.{Cst, Doc}

  @width 98

  # Operators whose chains wrap one-per-line (leading-operator style) when a
  # top-level `:=` body overflows. These are exactly the `Rian.Decl` `@cont_ops`
  # subset that the parser treats as **newline-insignificant in a `:=` body**
  # (P1, [decl.ex](decl.ex)) — so breaking before one is meaning-preserving. `|`
  # (cons/sum) is deliberately excluded (see the cons-tail trailing-comma fix).
  @wrap_ops ~w(|> and or <>)

  @doc """
  Format Rian source. **Total** — never raises: source that cannot even be lexed
  (an unterminated string/char/heredoc) is returned **unchanged**, so a
  format-on-save can never corrupt a buffer mid-edit. Use `format_result/1` when
  you need to distinguish "already formatted" from "could not be formatted".
  """
  def format(src) when is_binary(src) do
    case format_result(src) do
      {:ok, out} -> out
      {:error, _reason} -> src
    end
  end

  @doc """
  Like `format/1` but returns `{:ok, formatted}` or `{:error, message}` (the latter
  when the source cannot be lexed). Lets the CLI report unformattable files instead
  of silently passing them.
  """
  def format_result(src) when is_binary(src) do
    out =
      src
      |> Lexer.tokenize_trivia()
      |> Cst.build()
      |> logical_lines()
      |> merge_chains()
      |> indent_and_render([0], 0, [])
      |> squeeze_blanks()
      |> Enum.map_join("", &(&1 <> "\n"))

    {:ok, out}
  rescue
    e in [ArgumentError, RuntimeError] -> {:error, Exception.message(e)}
  end

  # ── split the CST into logical lines on top-level newlines ────────────────
  # A bracket `{:group}` is one node, so a multi-line bracket stays within one
  # logical line (its inner newlines are the group's children, not top-level).
  defp logical_lines(nodes), do: ll(nodes, [], [])
  defp ll([], cur, acc), do: Enum.reverse([Enum.reverse(cur) | acc])
  defp ll([{:tok, {:nl}} | rest], cur, acc), do: ll(rest, [], [Enum.reverse(cur) | acc])
  defp ll([n | rest], cur, acc), do: ll(rest, [n | cur], acc)

  # ── merge operator-continuation lines into one logical unit ───────────────
  # A `:=` body split across source lines by a wrap-operator continuation (a
  # trailing `|>`/`and`/`or`/`<>`, or a leading one on the next line) is rejoined
  # into a single logical line, so the wrap pass re-decides collapse-vs-break as a
  # whole — which is what makes wrapping **idempotent** (a broken chain re-lexes to
  # separate lines and must remerge to the same unit). Only a declaration line
  # accumulates (a block-internal bind can't legally continue this way — its
  # newline would become a `;`), and a line ending in a comment never merges
  # forward (the comment would eat the next line).
  defp merge_chains([a, b | rest]) do
    if chain_link?(a, b),
      do: merge_chains([a ++ b | rest]),
      else: [a | merge_chains([b | rest])]
  end

  defp merge_chains(lines), do: lines

  defp chain_link?(a, b) do
    declaration_line?(a) and not ends_with_comment?(a) and not blank?(b) and
      not comment_only?(b) and (trailing_wrap_op?(a) or leading_wrap_op?(b))
  end

  defp ends_with_comment?(line), do: match?({:tok, {:comment, _}}, List.last(line))

  defp trailing_wrap_op?(line), do: wrap_op_tok?(tail_tok(List.last(line)))
  defp leading_wrap_op?([first | _]), do: wrap_op_tok?(head_tok(first))

  defp wrap_op_tok?({:op, o}), do: o in @wrap_ops
  defp wrap_op_tok?(_), do: false

  # ── per-line indent (stack) + Doc render ──────────────────────────────────
  # `stack` holds the indent level for each open block; `cont` is 1 when the
  # previous line ended in a trailing binary operator (this line continues it).
  defp indent_and_render([], _stack, _cont, acc), do: Enum.reverse(acc)

  defp indent_and_render([line | rest], stack, cont, acc) do
    if blank?(line) do
      indent_and_render(rest, stack, cont, ["" | acc])
    else
      line = mark(line)
      base = max(0, hd(stack) + cont + lead_adjust(line))
      rendered = render_line(line, base)
      stack = update_stack(line, rest, base, stack)
      cont = if trailing_op?(line), do: 1, else: 0
      indent_and_render(rest, stack, cont, [rendered | acc])
    end
  end

  defp blank?([]), do: true
  defp blank?(_), do: false

  # render one logical line as a Doc at indent `base` (in 2-space levels); a
  # breaking bracket group produces multiple physical lines, nested under `base`.
  defp render_line(nodes, base) do
    doc =
      Doc.concat([Doc.text(String.duplicate("  ", base)), Doc.nest(2 * base, line_doc(nodes))])

    Doc.render(doc, @width)
  end

  # ── indent stack (driven by do/end + block-form def heads) ────────────────
  defp update_stack(line, rest, base, stack) do
    stack = Enum.reduce(line, stack, fn node, st -> apply_node(node, base, st) end)
    if block_head?(line, rest), do: push(base, stack), else: stack
  end

  defp apply_node({:tok, {:kw, "do"}}, base, st), do: push(base, st)
  defp apply_node({:tok, {:kw, "end"}}, _base, st), do: pop(st)
  defp apply_node(_node, _base, st), do: st

  defp push(base, st), do: [base + 1 | st]
  defp pop([_top, next | rest]), do: [next | rest]
  defp pop(st), do: st

  # First-token nudge: closer-led line dedents; operator-led continuation indents.
  defp lead_adjust([first | _]) do
    cond do
      closer_lead?(head_tok(first)) -> -1
      cont_lead?(head_tok(first)) -> 1
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

  defp trailing_op?(line) do
    case tail_tok(List.last(line)) do
      {:op, _} -> true
      _ -> false
    end
  end

  # A `def`/`macro` head opens a block body iff it has no `:=` and no `do`, and the
  # next code line is not a declaration boundary (mirrors `Rian.Decl`).
  defp block_head?([{:tok, {:kw, "pub"}} | line_rest], next), do: block_head?(line_rest, next)

  defp block_head?([{:tok, {:kw, k}} | _] = line, next) when k in ~w(def macro) do
    not has_tok?(line, {:op, ":="}) and not has_tok?(line, {:kw, "do"}) and
      not boundary?(next_code_line(next))
  end

  defp block_head?(_line, _next), do: false

  defp has_tok?(line, t), do: Enum.any?(line, &(&1 == {:tok, t}))

  defp next_code_line([]), do: nil

  defp next_code_line([line | rest]) do
    if blank?(line) or comment_only?(line), do: next_code_line(rest), else: line
  end

  defp comment_only?(line), do: Enum.all?(line, &match?({:tok, {:comment, _}}, &1))

  defp boundary?(nil), do: true
  defp boundary?([first | _]), do: boundary_tok?(head_tok(first))

  defp boundary_tok?({:kw, "end"}), do: true
  defp boundary_tok?({:annot, _}), do: true

  defp boundary_tok?({:kw, k}),
    do:
      k in ~w(type def struct alias mod pub const macro use import protocol impl opaque abstract)

  defp boundary_tok?(_), do: false

  # ── node → Doc, with context-sensitive spacing ────────────────────────────
  # `reflow?` marks the zone where bracket groups may wrap. A **declaration head**
  # (`def f(p) ret when g`) is NOT a safe reflow zone — `Rian.Decl`'s head parser
  # is not newline-tolerant inside its parens — so for a declaration line the zone
  # opens only after the top-level `:=`. Other lines (expressions/statements in a
  # block body) reflow throughout.
  defp line_doc(nodes), do: bd(nodes, nil, not declaration_line?(nodes))

  defp declaration_line?([first | _]), do: decl_kw?(head_tok(first))
  defp declaration_line?([]), do: false

  defp decl_kw?({:kw, k}),
    do:
      k in ~w(def type struct alias mod pub const macro use import protocol impl opaque abstract range)

  defp decl_kw?(_), do: false

  defp bd([], _prev, _rf), do: Doc.empty()

  # an own-line comment (first node) prints inline; a trailing comment defers to
  # end-of-line via line_suffix so it survives an earlier group break.
  defp bd([{:tok, {:comment, c}} = node | rest], nil, rf),
    do: Doc.concat([Doc.text(c), bd(rest, node, rf)])

  defp bd([{:tok, {:comment, c}} = node | rest], _prev, rf),
    do: Doc.concat([Doc.line_suffix(Doc.text("  " <> c)), bd(rest, node, rf)])

  # the top-level `:=` opens the body (reflow) zone for the rest of the line.
  # Reaching it with `rf == false` means this is a **declaration body** (only a
  # declaration line starts in the head zone) — the one place a wrap-op chain may
  # break across lines safely (P1 take_line continues; a block-internal bind can't).
  defp bd([{:tok, {:op, ":="}} = node | rest], prev, rf) do
    sep =
      if prev != nil and space?(tail_tok(prev), {:op, ":="}), do: Doc.text(" "), else: Doc.empty()

    body = if not rf and chain?(rest), do: chain_body(rest, node), else: bd(rest, node, true)
    Doc.concat([sep, Doc.text(":="), body])
  end

  defp bd([node | rest], prev, rf) do
    sep =
      if prev != nil and space?(tail_tok(prev), head_tok(node)),
        do: Doc.text(" "),
        else: Doc.empty()

    Doc.concat([sep, node_doc(node, rf), bd(rest, node, rf)])
  end

  defp node_doc({:tok, {:comment, c}}, _rf), do: Doc.text(c)
  defp node_doc({:tok, t}, _rf), do: Doc.text(leaf(t))
  defp node_doc({:group, open, inner, close}, rf), do: group_doc(open, inner, close, rf)

  # ── depth-0 operator-chain wrapping (leading-operator style) ──────────────
  # A `:=` body that is a flat chain of `|>`/`and`/`or`/`<>` (no inline `do`-block)
  # is rendered as a group: one line if it fits, else broken before each operator
  # with a one-level hanging indent. Breaking before a leading `@cont_ops` operator
  # in a `:=` body is meaning-safe (P1). Bodies containing a `do` are left alone
  # (a wrap-op there may sit inside the block — not a top-level chain split point).
  defp chain?(nodes) do
    not Enum.any?(nodes, &match?({:tok, {:kw, "do"}}, &1)) and Enum.any?(nodes, &wrap_op_node?/1)
  end

  defp chain_body(nodes, prev) do
    sep =
      if space?(tail_tok(prev), head_tok(hd(nodes))), do: Doc.text(" "), else: Doc.empty()

    Doc.concat([sep, chain_doc(nodes)])
  end

  defp chain_doc(nodes) do
    {seg0, rest} = take_until_wrap(nodes, [])
    Doc.group(Doc.concat([bd(seg0, nil, true), Doc.nest(2, chain_tail(rest))]))
  end

  defp chain_tail([]), do: Doc.empty()

  defp chain_tail([{:tok, {:op, o}} | rest]) do
    {seg, rest2} = take_until_wrap(rest, [])
    Doc.concat([Doc.line(), Doc.text(o), Doc.text(" "), bd(seg, nil, true), chain_tail(rest2)])
  end

  defp take_until_wrap([], acc), do: {Enum.reverse(acc), []}

  defp take_until_wrap([n | rest], acc) do
    if wrap_op_node?(n),
      do: {Enum.reverse(acc), [n | rest]},
      else: take_until_wrap(rest, [n | acc])
  end

  defp wrap_op_node?({:tok, t}), do: wrap_op_tok?(t)
  defp wrap_op_node?(_), do: false

  # the reflow core: in the body zone a bracket group collapses if it fits, else
  # breaks one item per line with a trailing comma; a comment inside forces a full
  # break. In a head zone (`reflow? = false`) it always renders flat (one line).
  defp group_doc(open, inner, close, reflow?) do
    o = Doc.text(leaf(open))
    c = Doc.text(leaf(close))
    items = split_items(inner)

    cond do
      items == [] ->
        Doc.concat([o, c])

      not reflow? ->
        body = Doc.join(Doc.text(", "), Enum.map(items, &bd(&1, nil, false)))
        Doc.concat([o, body, c])

      has_comment?(inner) ->
        body =
          Doc.join(
            Doc.concat([Doc.text(","), Doc.hardline()]),
            Enum.map(items, &bd(&1, nil, true))
          )

        Doc.concat([o, Doc.nest(2, Doc.concat([Doc.hardline(), body])), Doc.hardline(), c])

      true ->
        body =
          Doc.join(Doc.concat([Doc.text(","), Doc.line()]), Enum.map(items, &bd(&1, nil, true)))

        # a trailing comma is safe before `)` / `]` / `}` (`f(a,) ≡ f(a)`), but NOT
        # after a cons tail — `[a, b | tail,]` is a syntax error — so a cons group
        # never gets one. A trailing comma is never *required*, so suppressing it is
        # always meaning-safe.
        trailing =
          if trailing_comma?(inner) and not cons_group?(inner),
            do: Doc.if_break(Doc.text(","), Doc.empty()),
            else: Doc.empty()

        Doc.group(
          Doc.concat([
            o,
            Doc.nest(2, Doc.concat([Doc.softline(), body])),
            trailing,
            Doc.softline(),
            c
          ])
        )
    end
  end

  # split a group's inner nodes on top-level commas (newlines dropped — the group
  # supplies its own breaks); a source trailing comma yields no extra empty item.
  defp split_items(nodes) do
    nodes
    |> Enum.reject(&match?({:tok, {:nl}}, &1))
    |> chunk_on_comma([], [])
  end

  defp chunk_on_comma([], cur, acc), do: finish_items(cur, acc)

  defp chunk_on_comma([{:tok, {:comma}} | rest], cur, acc),
    do: chunk_on_comma(rest, [], [Enum.reverse(cur) | acc])

  defp chunk_on_comma([n | rest], cur, acc), do: chunk_on_comma(rest, [n | cur], acc)

  defp finish_items(cur, acc) do
    items = Enum.reverse([Enum.reverse(cur) | acc])

    case List.last(items) do
      [] -> Enum.drop(items, -1)
      _ -> items
    end
  end

  defp has_comment?(nodes), do: Enum.any?(nodes, &match?({:tok, {:comment, _}}, &1))
  defp trailing_comma?(inner), do: Enum.any?(inner, &match?({:tok, {:comma}}, &1))

  # a cons list (`[a, b | tail]`) — a top-level `|` inside the group. The parser
  # closes the list immediately after the cons tail, so no trailing comma may follow.
  defp cons_group?(inner), do: Enum.any?(inner, &match?({:tok, {:op, "|"}}, &1))

  # ── leaf token text + node head/tail tokens ───────────────────────────────
  defp leaf({:uop, o}), do: o
  defp leaf({:kcolon}), do: ":"
  defp leaf({:acolon}), do: ":"
  defp leaf(t), do: Lexer.detokenize([t])

  defp head_tok({:group, open, _, _}), do: open
  defp head_tok({:tok, t}), do: t
  defp tail_tok({:group, _, _, close}), do: close
  defp tail_tok({:tok, t}), do: t

  # ── mark: resolve unary `-`/`+` and key/atom `:` up front (recurse groups) ─
  defp mark(nodes), do: mark(nodes, nil, [])
  defp mark([], _prev, acc), do: Enum.reverse(acc)

  defp mark([{:group, open, inner, close} | rest], _prev, acc) do
    g = {:group, open, mark(inner), close}
    mark(rest, g, [g | acc])
  end

  defp mark([{:tok, {:op, o}} | rest], prev, acc) when o in ["-", "+"] do
    t = if value_end?(prev), do: {:tok, {:op, o}}, else: {:tok, {:uop, o}}
    mark(rest, t, [t | acc])
  end

  defp mark([{:tok, {:op, ":"}} | rest], prev, acc) do
    t = if value_end?(prev), do: {:tok, {:kcolon}}, else: {:tok, {:acolon}}
    mark(rest, t, [t | acc])
  end

  defp mark([node | rest], _prev, acc), do: mark(rest, node, [node | acc])

  # value-end as a *node* (the next `-`/`+` is binary, the next `:` is a key)
  defp value_end?(nil), do: false
  defp value_end?(node), do: value_end_tok?(tail_tok(node))

  defp value_end_tok?({:id, _}), do: true
  defp value_end_tok?({:num, _}), do: true
  defp value_end_tok?({:str, _}), do: true
  defp value_end_tok?({:istr, _}), do: true
  defp value_end_tok?({:char, _}), do: true
  defp value_end_tok?({:heredoc, _}), do: true
  defp value_end_tok?({:rparen}), do: true
  defp value_end_tok?({:rbracket}), do: true
  defp value_end_tok?({:rbrace}), do: true
  defp value_end_tok?(_), do: false

  # ── pairwise spacing (operates on the boundary tokens of two nodes) ────────
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
  # `f(` / `xs[` bind tightly (application/index); grouping `(`/literal `[` don't.
  defp space?(prev, {:lparen}), do: not value_end_tok?(prev)
  defp space?(prev, {:lbracket}), do: not value_end_tok?(prev)
  defp space?(_prev, _cur), do: true

  # ── blank-line policy: collapse runs, trim edges ──────────────────────────
  defp squeeze_blanks(lines) do
    lines
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> collapse_runs([])
  end

  defp collapse_runs([], acc), do: Enum.reverse(acc)
  defp collapse_runs(["", "" | rest], acc), do: collapse_runs(["" | rest], acc)
  defp collapse_runs([l | rest], acc), do: collapse_runs(rest, [l | acc])
end
