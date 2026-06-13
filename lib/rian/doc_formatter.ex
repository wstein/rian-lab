defmodule Rian.DocFormatter do
  @moduledoc """
  Starlight-flavored **MDX** formatter — the production path that replaces the
  `rian-docs-spike` post-processing script.

  Forked in spirit from `ExDoc.Formatter.MARKDOWN`, but emits the API-reference
  detail the stock markdown formatter drops (which the spike proved is gone for
  good from the markdown output, recoverable only here, with the nodes in hand):

    * per-member **signatures** (`node.signature`, e.g. `compile(src)`) instead
      of the bare `node.name` the stock `detail_template.eex` emits, with an
      **arity-stable anchor** (`<a id="compile-1" />` from `node.id`), so
      overloads no longer collapse to the same heading;
    * `@spec` / typespec blocks from `node.source_specs`;
    * per-member **source links** (`node.source_url`);
    * a **section header** per `DocGroupNode` (Functions / Types / Callbacks) —
      the stock template iterates `docs_groups` but throws the titles away;
    * a **group-aware sidebar** built from `ModuleNode.group` (`groups_for_modules`)
      — the module taxonomy that survives in no markdown output.

  Prose comes from `Rian.DocFormatter.MDX`, which renders the parsed `DocAST`
  (not the raw `source_doc` string) so JSX metacharacters are escaped
  structure-aware — the principled alternative to the spike's flat-text regex.

  Wire it up in `mix.exs` (a module atom resolves directly; a CLI string would be
  upcased and mis-resolved, so configure it here rather than via `-f`):

      docs: [formatters: ["html", Rian.DocFormatter], ...]

  Output is consumed by `rian_lab/site` (Starlight). Still TODO: internal-link
  rewriting to Astro routes (ExDoc `autolink_options`), and routing extras into
  their `groups_for_extras` folders (currently flat at the docs root).
  """

  @api_dir "api"
  @task_dir "tasks"

  def run(config, project_nodes, extras) do
    File.mkdir_p!(config.output)

    {modules, tasks} =
      project_nodes
      |> Enum.filter(&(&1.source_format == "text/markdown"))
      |> Enum.split_with(&(&1.type != :task))

    extra_nodes = Enum.filter(extras, &match?(%ExDoc.ExtraNode{}, &1))

    files =
      Enum.map(modules, &write_node_page(config, &1, @api_dir)) ++
        Enum.map(tasks, &write_node_page(config, &1, @task_dir)) ++
        Enum.map(extra_nodes, &write_extra(config, &1)) ++
        [write_sidebar(config, modules, tasks, extra_nodes)]

    %{
      entrypoint: config.output |> Path.join("sidebar.mjs") |> Path.relative_to_cwd(),
      build: files
    }
  end

  # --- module / task pages --------------------------------------------------

  defp write_node_page(config, mod, dir) do
    body =
      [frontmatter(mod.title), source_link(mod.source_url), node_doc(mod), members(mod)]
      |> compact()
      |> Enum.join("\n\n")

    rel = Path.join(dir, "#{slug(mod.id)}.mdx")
    write!(config, rel, body <> "\n")
    rel
  end

  defp members(mod) do
    mod.docs_groups
    |> Enum.map(fn group ->
      "## #{group.title}\n\n" <> Enum.map_join(group.docs, "\n\n", &member(&1, mod))
    end)
    |> Enum.join("\n\n")
  end

  defp member(node, mod) do
    [
      # explicit arity-stable anchor (valid JSX); signature in backticks so any
      # `%{}` / `<` in it stays verbatim instead of being parsed as MDX
      ~s(<a id="#{slug(node.id)}" />),
      "### `#{node.signature}`",
      annotations(node.annotations),
      spec_block(node, mod),
      source_link(node.source_url),
      node_doc(node)
    ]
    |> compact()
    |> Enum.join("\n\n")
  end

  defp spec_block(%{source_specs: []}, _mod), do: nil

  defp spec_block(node, mod) do
    lang = mod.language.highlight_info().language_name

    specs =
      Enum.map_join(node.source_specs, "\n", fn spec ->
        "#{mod.language.format_spec_attribute(node)} #{mod.language.format_spec(spec)}"
      end)

    "```#{lang}\n#{specs}\n```"
  end

  defp annotations([]), do: nil
  defp annotations(list), do: Enum.map_join(list, " ", &"*#{&1}*")

  # --- extras (render DocAST -> MDX; strip the leading h1, kept in frontmatter) --

  defp write_extra(config, %ExDoc.ExtraNode{} = extra) do
    ast =
      case ExDoc.DocAST.extract_title(extra.doc || []) do
        {:ok, _title, rest} -> rest
        :error -> extra.doc
      end

    rel = "#{slug(extra.id)}.mdx"
    write!(config, rel, "#{frontmatter(extra.title)}\n\n#{Rian.DocFormatter.MDX.render(ast)}\n")
    rel
  end

  # --- sidebar manifest (Astro/Starlight `sidebar` shape) -------------------

  defp write_sidebar(config, modules, tasks, extras) do
    pages = grouped(extras, "Pages", fn e -> %{slug: slug(e.id)} end)

    api =
      grouped(modules, "Modules", fn m -> %{slug: Path.join(@api_dir, slug(m.id))} end) ++
        maybe_group("Mix Tasks", Enum.map(tasks, fn t -> %{slug: Path.join(@task_dir, slug(t.id))} end))

    sidebar = [%{label: "Pages", items: pages}, %{label: "API", items: api}]
    write!(config, "sidebar.mjs", "export default #{to_json(sidebar)};\n")
    "sidebar.mjs"
  end

  # chunk nodes into [%{label, items}] by their `.group`, preserving ExDoc's
  # order; nil groups collapse under `default`
  defp grouped(nodes, default, item_fn) do
    nodes
    |> Enum.chunk_by(&(&1.group || default))
    |> Enum.map(fn chunk ->
      %{label: to_string(hd(chunk).group || default), items: Enum.map(chunk, item_fn)}
    end)
  end

  defp maybe_group(_label, []), do: []
  defp maybe_group(label, items), do: [%{label: label, items: items}]

  # --- helpers --------------------------------------------------------------

  defp node_doc(%{doc: ast}) when not is_nil(ast), do: Rian.DocFormatter.MDX.render(ast)
  defp node_doc(_), do: nil

  defp source_link(nil), do: nil
  defp source_link(url), do: "[🔗 Source](#{url})"

  defp frontmatter(title), do: "---\ntitle: #{quote_yaml(title)}\n---"

  defp compact(list), do: Enum.reject(list, &(&1 in [nil, ""]))

  defp write!(config, rel, content) do
    path = Path.join(config.output, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp slug(id) do
    id
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp quote_yaml(s), do: ~s(") <> escape(to_string(s)) <> ~s(")

  defp escape(s), do: s |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

  defp to_json(v) when is_list(v), do: "[" <> Enum.map_join(v, ",", &to_json/1) <> "]"

  defp to_json(v) when is_map(v),
    do: "{" <> Enum.map_join(v, ",", fn {k, val} -> ~s("#{k}":) <> to_json(val) end) <> "}"

  defp to_json(v) when is_atom(v), do: to_json(to_string(v))
  defp to_json(v) when is_binary(v), do: ~s(") <> escape(v) <> ~s(")
end
