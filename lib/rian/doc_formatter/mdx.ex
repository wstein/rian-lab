defmodule Rian.DocFormatter.MDX do
  @moduledoc """
  Renders an ExDoc `DocAST` to Starlight-flavored **MDX**.

  This is the production answer to the spike's flat-text regex scan. Escaping is
  **structure-aware**: a `DocAST` is a tree of `{tag, attrs, children, meta}`
  tuples whose leaves are binary text. We MDX-escape the JSX metacharacters
  (`{` and `<`) only in those text leaves; `code`/`pre` nodes pass through
  verbatim because MDX never parses inside code. So `{:nl}` is escaped in prose
  and untouched in a code block — no guessing, unlike scanning a flat string.

  Extras (admonitions) map to Starlight asides (`:::caution`).
  """

  @asides %{
    "warning" => "caution",
    "error" => "danger",
    "info" => "note",
    "neutral" => "note",
    "tip" => "tip"
  }

  @doc "Render a DocAST (node or list) to an MDX string."
  def render(nil), do: ""

  def render(ast) do
    ast
    |> mdx()
    |> IO.iodata_to_binary()
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # --- block + inline nodes -------------------------------------------------

  defp mdx(list) when is_list(list), do: Enum.map(list, &mdx/1)
  defp mdx(text) when is_binary(text), do: escape(text)
  defp mdx({:comment, _, _, _}), do: ""

  # no `{#id}` — that is an MDX expression and fails to parse; Starlight auto-slugs
  # heading text, and members get an explicit <a id> in Rian.DocFormatter
  defp mdx({h, _attrs, inner, _}) when h in [:h1, :h2, :h3, :h4, :h5, :h6] do
    level = h |> Atom.to_string() |> String.trim_leading("h") |> String.to_integer()
    ["\n\n", String.duplicate("#", level), " ", inline(inner), "\n\n"]
  end

  defp mdx({:p, _, inner, _}), do: ["\n\n", inline(inner), "\n\n"]
  defp mdx({:br, _, _, _}), do: "  \n"
  defp mdx({:hr, _, _, _}), do: "\n\n---\n\n"

  defp mdx({:strong, _, inner, _}), do: ["**", inline(inner), "**"]
  defp mdx({:b, _, inner, _}), do: ["**", inline(inner), "**"]
  defp mdx({:em, _, inner, _}), do: ["*", inline(inner), "*"]
  defp mdx({:i, _, inner, _}), do: ["*", inline(inner), "*"]
  defp mdx({:del, _, inner, _}), do: ["~~", inline(inner), "~~"]

  # inline + fenced code: VERBATIM (no escape — MDX ignores `{`/`<` in code).
  # The fence must be longer than any backtick run inside the code, else it breaks.
  defp mdx({:code, _, [code], _}) when is_binary(code) do
    fence = backtick_fence(code, 1)
    pad = if String.match?(code, ~r/^`|`$/), do: " ", else: ""
    [fence, pad, code, pad, fence]
  end

  defp mdx({:pre, _, [{:code, code_attrs, [code], _}], _}) when is_binary(code) do
    fence = backtick_fence(code, 3)
    ["\n\n", fence, lang(code_attrs), "\n", String.trim_trailing(code, "\n"), "\n", fence, "\n\n"]
  end

  defp mdx({:a, attrs, inner, _}), do: ["[", inline(inner), "](", attrs[:href] || "#", ")"]
  defp mdx({:img, attrs, _, _}), do: ["![", attrs[:alt] || "", "](", attrs[:src] || "", ")"]

  defp mdx({:ul, _, items, _}), do: ["\n\n", list(items, fn _ -> "-" end), "\n\n"]

  defp mdx({:ol, _, items, _}),
    do: ["\n\n", list(items, fn i -> "#{i}." end), "\n\n"]

  defp mdx({:blockquote, _, inner, _}), do: blockquote(inner)
  defp mdx({:table, _, rows, _}), do: table(rows)

  # ExDoc rewrites admonition blockquotes into a <section class="admonition …">;
  # turn those into Starlight asides, render any other section's children inline
  defp mdx({:section, attrs, [{h, _, title, _} | rest], _}) when h in [:h3, :h4, :h5] do
    classes = attrs[:class] |> to_string() |> String.split()

    if "admonition" in classes do
      kind = Enum.find_value(@asides, "note", fn {c, k} -> if c in classes, do: k end)
      ["\n\n:::", kind, "[", inline(title), "]\n\n", render(rest), "\n\n:::\n\n"]
    else
      ["\n\n", inline(title), "\n\n", render(rest), "\n\n"]
    end
  end

  # unknown wrapper: keep the children, drop the tag (stays valid MDX)
  defp mdx({_tag, _attrs, inner, _}), do: inline(inner)

  defp inline(inner), do: inner |> mdx() |> IO.iodata_to_binary() |> String.trim()

  # --- lists ----------------------------------------------------------------

  defp list(items, marker_fun) do
    items
    |> Enum.filter(&match?({:li, _, _, _}, &1))
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{:li, _, inner, _}, i} -> li(inner, marker_fun.(i)) end)
  end

  defp li(inner, marker) do
    [first | rest] = inner |> render() |> String.split("\n")
    pad = String.duplicate(" ", String.length(marker) + 1)

    cont =
      Enum.map_join(rest, "\n", fn
        "" -> ""
        l -> pad <> l
      end)

    marker <> " " <> first <> if(rest == [], do: "", else: "\n" <> cont)
  end

  # --- blockquote / Starlight aside ----------------------------------------

  defp blockquote([{h, attrs, title, _} | rest] = inner)
       when h in [:h3, :h4, :h5] do
    case @asides[to_string(attrs[:class] || "")] do
      nil -> plain_quote(inner)
      kind -> ["\n\n:::", kind, "[", inline(title), "]\n", render(rest), "\n:::\n\n"]
    end
  end

  defp blockquote(inner), do: plain_quote(inner)

  defp plain_quote(inner) do
    body = inner |> render() |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))
    ["\n\n", body, "\n\n"]
  end

  # --- tables ---------------------------------------------------------------

  defp table(rows) do
    case rows |> Enum.flat_map(&rows_of/1) |> Enum.map(&cells_of/1) do
      [head | body] ->
        sep = Enum.map(head, fn _ -> "---" end)
        lines = Enum.map_join([head, sep | body], "\n", &("| " <> Enum.join(&1, " | ") <> " |"))
        ["\n\n", lines, "\n\n"]

      [] ->
        ""
    end
  end

  defp rows_of({:tr, _, _, _} = tr), do: [tr]
  defp rows_of({tag, _, inner, _}) when tag in [:thead, :tbody, :tfoot], do: Enum.flat_map(inner, &rows_of/1)
  defp rows_of(_), do: []

  defp cells_of({:tr, _, cells, _}) do
    # a raw `|` (even inside inline code) ends the cell in GFM — escape it, and
    # flatten newlines since a cell must be a single line
    for {tag, _, inner, _} <- cells, tag in [:td, :th] do
      inner |> inline() |> String.replace("|", "\\|") |> String.replace("\n", " ")
    end
  end

  # --- helpers --------------------------------------------------------------

  # escape ONLY the MDX/JSX openers; code leaves never reach here
  defp escape(text), do: text |> String.replace("{", "\\{") |> String.replace("<", "\\<")

  defp backtick_fence(code, min) do
    longest = ~r/`+/ |> Regex.scan(code) |> Enum.map(fn [m] -> String.length(m) end) |> Enum.max(fn -> 0 end)
    String.duplicate("`", max(min, longest + 1))
  end

  defp lang(attrs) do
    case attrs[:class] do
      nil -> ""
      class -> class |> to_string() |> String.split() |> List.first("") |> String.replace_prefix("language-", "")
    end
  end
end
