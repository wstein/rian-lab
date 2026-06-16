defmodule Rian.Format.Doc do
  @moduledoc """
  A Wadler-style pretty-printing document algebra with Lindig's strict,
  linear-time renderer (*Strictly Pretty*, 2000) plus the production extensions
  from Prettier (`softline`/`hardline`/`line_suffix`/`if_break` and break
  propagation). This is the wrapping engine behind `Rian.Format` Tier 2.

  ## Algebra

  A `Doc` is built from:

    * `empty()` — the unit.
    * `text(s)` — a literal string (must not contain newlines).
    * `concat(docs)` — sequence.
    * `nest(n, doc)` — add `n` columns of indentation to line breaks inside `doc`.
    * `line()` — a break that is a single space when its group is **flat**, else a
      newline + indent.
    * `softline()` — like `line()` but `""` when flat.
    * `hardline()` — always a newline; **forces every enclosing `group` to break**.
    * `group(doc)` — try `doc` flat (one line); if it doesn't fit the width (or it
      contains a `hardline`), render it broken.
    * `line_suffix(doc)` — content deferred to just before the next newline (used to
      keep a trailing `# comment` at end-of-line when its group breaks).
    * `if_break(broken, flat)` — `broken` when the enclosing group breaks, else `flat`
      (used for trailing commas).

  ## Renderer

  `render(doc, width)` runs Lindig's worklist of `{indent, mode, doc}` triples with
  a bounded `fits?` lookahead, so it is O(document size). A `group` is rendered flat
  iff it has no propagated hard break *and* `fits?` the columns remaining on the line.
  """

  # ── constructors ──────────────────────────────────────────────────────────
  def empty, do: :empty
  def text(s) when is_binary(s), do: {:text, s}
  def nest(n, doc) when is_integer(n), do: {:nest, n, doc}
  def line, do: {:line, " "}
  def softline, do: {:line, ""}
  def hardline, do: :hardline
  def line_suffix(doc), do: {:line_suffix, doc}
  def if_break(broken, flat), do: {:if_break, broken, flat}

  @doc "Concatenate a list of docs (flattening `empty`)."
  def concat(docs) when is_list(docs) do
    case Enum.reject(docs, &(&1 == :empty)) do
      [] -> :empty
      [one] -> one
      many -> {:concat, many}
    end
  end

  def concat(a, b), do: concat([a, b])

  @doc "Join `docs` with `sep` between each."
  def join(_sep, []), do: :empty
  def join(sep, docs), do: concat(Enum.intersperse(docs, sep))

  @doc """
  A group: render flat if it fits, else broken. Computes break propagation up
  front — a group containing a `hardline` (at any depth) is permanently broken.
  """
  def group(doc), do: {:group, must_break?(doc), doc}

  # ── break propagation (Prettier's propagateBreaks) ────────────────────────
  # True if `doc` transitively contains a hard break, so every enclosing group
  # must render broken.
  defp must_break?(:hardline), do: true
  defp must_break?({:concat, ds}), do: Enum.any?(ds, &must_break?/1)
  defp must_break?({:nest, _, d}), do: must_break?(d)
  defp must_break?({:group, mb, _}), do: mb
  defp must_break?({:line_suffix, d}), do: must_break?(d)
  defp must_break?({:if_break, b, f}), do: must_break?(b) or must_break?(f)
  defp must_break?(_), do: false

  # ── fits?: can the worklist render flat within `w` remaining columns? ──────
  # Lindig's bounded lookahead. A break in :break mode (or a hardline) ends the
  # line, so what follows no longer counts — it "fits".
  defp fits?(w, _work) when w < 0, do: false
  defp fits?(_w, []), do: true

  defp fits?(w, [{_i, _m, :empty} | rest]), do: fits?(w, rest)
  defp fits?(w, [{_i, _m, {:text, s}} | rest]), do: fits?(w - String.length(s), rest)

  defp fits?(w, [{i, m, {:concat, ds}} | rest]),
    do: fits?(w, Enum.map(ds, &{i, m, &1}) ++ rest)

  defp fits?(w, [{i, m, {:nest, n, d}} | rest]), do: fits?(w, [{i + n, m, d} | rest])
  defp fits?(_w, [{_i, :break, {:line, _}} | _rest]), do: true
  defp fits?(w, [{_i, :flat, {:line, s}} | rest]), do: fits?(w - String.length(s), rest)
  defp fits?(_w, [{_i, _m, :hardline} | _rest]), do: true
  # a group inside a fits-check is measured flat unless it must break
  defp fits?(w, [{i, _m, {:group, true, d}} | rest]), do: fits?(w, [{i, :break, d} | rest])
  defp fits?(w, [{i, _m, {:group, false, d}} | rest]), do: fits?(w, [{i, :flat, d} | rest])
  defp fits?(w, [{_i, _m, {:line_suffix, _}} | rest]), do: fits?(w, rest)
  defp fits?(w, [{i, :flat, {:if_break, _b, f}} | rest]), do: fits?(w, [{i, :flat, f} | rest])
  defp fits?(w, [{i, :break, {:if_break, b, _f}} | rest]), do: fits?(w, [{i, :break, b} | rest])

  # ── render ────────────────────────────────────────────────────────────────
  @doc "Render `doc` to a string within a soft `width` column budget."
  def render(doc, width) when is_integer(width) do
    # state: worklist, current column `k`, buffered line-suffix docs (reversed)
    do_render(width, 0, [{0, :break, doc}], [], [])
    |> IO.iodata_to_binary()
  end

  # done — flush any trailing suffixes (e.g. a file ending in a comment)
  defp do_render(_w, _k, [], [], out), do: Enum.reverse(out)
  defp do_render(_w, _k, [], suffix, out), do: Enum.reverse(flush_suffix(suffix, out))

  defp do_render(w, k, [{_i, _m, :empty} | rest], suffix, out),
    do: do_render(w, k, rest, suffix, out)

  defp do_render(w, k, [{_i, _m, {:text, s}} | rest], suffix, out),
    do: do_render(w, k + String.length(s), rest, suffix, [s | out])

  defp do_render(w, k, [{i, m, {:concat, ds}} | rest], suffix, out),
    do: do_render(w, k, Enum.map(ds, &{i, m, &1}) ++ rest, suffix, out)

  defp do_render(w, k, [{i, m, {:nest, n, d}} | rest], suffix, out),
    do: do_render(w, k, [{i + n, m, d} | rest], suffix, out)

  # a line break in flat mode is just its flat string
  defp do_render(w, k, [{_i, :flat, {:line, s}} | rest], suffix, out),
    do: do_render(w, k + String.length(s), rest, suffix, [s | out])

  # a line break in break mode: flush deferred suffixes, then newline + indent
  defp do_render(w, _k, [{i, :break, {:line, _}} | rest], suffix, out),
    do: do_render(w, i, rest, [], [String.duplicate(" ", i), "\n" | flush_suffix(suffix, out)])

  defp do_render(w, _k, [{i, _m, :hardline} | rest], suffix, out),
    do: do_render(w, i, rest, [], [String.duplicate(" ", i), "\n" | flush_suffix(suffix, out)])

  # defer line-suffix content (e.g. a trailing comment) to the next newline
  defp do_render(w, k, [{_i, _m, {:line_suffix, d}} | rest], suffix, out),
    do: do_render(w, k, rest, [d | suffix], out)

  defp do_render(w, k, [{i, :flat, {:if_break, _b, f}} | rest], suffix, out),
    do: do_render(w, k, [{i, :flat, f} | rest], suffix, out)

  defp do_render(w, k, [{i, :break, {:if_break, b, _f}} | rest], suffix, out),
    do: do_render(w, k, [{i, :break, b} | rest], suffix, out)

  # the crux: choose flat or broken for a group
  defp do_render(w, k, [{i, _m, {:group, must_break, d}} | rest], suffix, out) do
    mode = if not must_break and fits?(w - k, [{i, :flat, d} | rest]), do: :flat, else: :break
    do_render(w, k, [{i, mode, d} | rest], suffix, out)
  end

  # emit buffered line-suffix docs (in insertion order) right before a newline.
  # `suffix` is held reversed; suffix content is always flat (trailing comments).
  defp flush_suffix([], out), do: out

  defp flush_suffix(suffix, out),
    do: Enum.reduce(Enum.reverse(suffix), out, fn d, acc -> [flat_string(d) | acc] end)

  defp flat_string(:empty), do: ""
  defp flat_string({:text, s}), do: s
  defp flat_string({:concat, ds}), do: Enum.map_join(ds, "", &flat_string/1)
  defp flat_string({:nest, _, d}), do: flat_string(d)
  defp flat_string({:group, _, d}), do: flat_string(d)
  defp flat_string({:line, s}), do: s
  defp flat_string(:hardline), do: ""
  defp flat_string({:line_suffix, d}), do: flat_string(d)
  defp flat_string({:if_break, _b, f}), do: flat_string(f)
end
