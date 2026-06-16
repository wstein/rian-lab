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
      #{98}-column budget, and otherwise break **one item per line** with a
      trailing comma. A bracket region containing a line comment is forced to break.
    * **Statement / block newline placement is preserved** — the formatter does not
      collapse or expand `do…end` blocks, nor reflow pipe/operator chains. Those
      newlines are significant, so re-deriving them is deferred (see ADR-0045).
    * Blank-line runs collapse to one; comments and heredocs are kept verbatim at
      their authored position.

  ## Why it can't change meaning

  `Rian.Decl.detokenize` is whitespace-invariant and the parser is newline-tolerant
  inside brackets (and accepts a trailing comma identically), so **reflow that only
  changes whitespace/newlines inside brackets — plus an optional trailing comma —
  leaves `Rian.Decl.parse/1`'s AST unchanged**. That full-AST equality is the
  semantic-preservation oracle, asserted over the whole corpus and in property tests
  (the analog of `Rian.FormsEquiv` for the BEAM backend), alongside idempotence and
  comment fidelity.
  """

  alias Rian.Lexer
  alias Rian.Format.{Cst, Doc}

  @width 98

  @doc "Format Rian source. Total on valid `.rian`; returns a string."
  def format(src) when is_binary(src) do
    src
    |> Lexer.tokenize_trivia()
    |> Cst.build()
    |> logical_lines()
    |> indent_and_render([0], 0, [])
    |> squeeze_blanks()
    |> Enum.map_join("", &(&1 <> "\n"))
  end

  # ── split the CST into logical lines on top-level newlines ────────────────
  # A bracket `{:group}` is one node, so a multi-line bracket stays within one
  # logical line (its inner newlines are the group's children, not top-level).
  defp logical_lines(nodes), do: ll(nodes, [], [])
  defp ll([], cur, acc), do: Enum.reverse([Enum.reverse(cur) | acc])
  defp ll([{:tok, {:nl}} | rest], cur, acc), do: ll(rest, [], [Enum.reverse(cur) | acc])
  defp ll([n | rest], cur, acc), do: ll(rest, [n | cur], acc)

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

  # the top-level `:=` opens the body (reflow) zone for the rest of the line
  defp bd([{:tok, {:op, ":="}} = node | rest], prev, _rf) do
    sep =
      if prev != nil and space?(tail_tok(prev), {:op, ":="}), do: Doc.text(" "), else: Doc.empty()

    Doc.concat([sep, Doc.text(":="), bd(rest, node, true)])
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

        trailing =
          if trailing_comma?(inner),
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
