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

    # resolve `Module.fun/arity` cross-refs (ExDoc autolink) then rewrite the
    # resulting hrefs to Astro routes
    routes = build_routes(modules, tasks, extra_nodes)
    base = autolink_base(config, extra_nodes)
    modules = Enum.map(modules, &autolink_node(&1, base, routes))
    tasks = Enum.map(tasks, &autolink_node(&1, base, routes))
    extra_nodes = Enum.map(extra_nodes, &autolink_extra(&1, base, routes))

    files =
      Enum.map(modules, &write_node_page(config, &1, @api_dir)) ++
        Enum.map(tasks, &write_node_page(config, &1, @task_dir)) ++
        Enum.map(extra_nodes, &write_extra(config, &1)) ++
        [
          write_sidebar(config, modules, tasks, extra_nodes),
          write_redirects(config, routes),
          write_meta(config)
        ]

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
      # explicit arity-stable anchors (valid JSX) — canonical id plus every
      # default arity, so `fun/2` refs to a `fun/4`-with-defaults still resolve.
      # signature in backticks so any `%{}` / `<` in it stays verbatim in MDX
      member_anchors(node),
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

  defp member_anchors(node) do
    [node.id | Enum.map(node.defaults, fn {name, arity} -> "#{name}/#{arity}" end)]
    |> Enum.uniq()
    |> Enum.map_join("\n", &~s(<a id="#{slug(&1)}" />))
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

    body =
      [frontmatter(extra.title), Rian.DocFormatter.MDX.render(ast)]
      |> compact()
      |> Enum.join("\n\n")

    rel = "#{extra_content_slug(extra)}.mdx"
    write!(config, rel, body <> "\n")
    rel
  end

  # route extras into their `groups_for_extras` folder (slugified group name);
  # ungrouped extras stay at the docs root
  defp extra_dir(nil), do: ""
  defp extra_dir(group), do: slug(group)

  defp extra_content_slug(extra) do
    case extra_dir(extra.group) do
      "" -> slug(extra.id)
      dir -> "#{dir}/#{slug(extra.id)}"
    end
  end

  defp extra_route(extra), do: "/#{extra_content_slug(extra)}/"

  # --- cross-page links: ExDoc autolink + rewrite hrefs to Astro routes ------

  defp build_routes(modules, tasks, extras) do
    Map.new(
      Enum.map(modules, &{&1.id, "/#{@api_dir}/#{slug(&1.id)}/"}) ++
        Enum.map(tasks, &{&1.id, "/#{@task_dir}/#{slug(&1.id)}/"}) ++
        Enum.map(extras, &{&1.id, extra_route(&1)})
    )
  end

  defp autolink_base(config, extras) do
    %ExDoc.Autolink{
      apps: config.apps,
      deps: config.deps,
      ext: ".html",
      extras: extra_basenames(extras),
      skip_undefined_reference_warnings_on: config.skip_undefined_reference_warnings_on,
      skip_code_autolink_to: config.skip_code_autolink_to,
      # HTML formatter already emits ref warnings; route ours to the mailbox
      warnings: :send
    }
  end

  defp extra_basenames(extras) do
    for %{source_path: p, id: id} when is_binary(p) <- extras,
        into: %{},
        do: {Path.basename(p), id}
  end

  defp autolink_node(node, base, routes) do
    lang = node.language

    modc = %{
      base
      | current_module: node.module,
        module_id: node.id,
        language: lang,
        id: node.id,
        file: node.moduledoc_file,
        line: node.moduledoc_line
    }

    groups =
      for g <- node.docs_groups do
        docs =
          for c <- g.docs do
            cc = %{
              modc
              | id: c.id,
                line: c.doc_line,
                file: c.doc_file,
                current_kfa: {c.type, c.name, c.arity}
            }

            %{c | doc: link_doc(c.doc, lang, cc, routes)}
          end

        %{g | doc: link_doc(g.doc, lang, modc, routes), docs: docs}
      end

    %{node | doc: link_doc(node.doc, lang, modc, routes), docs_groups: groups}
  end

  defp autolink_extra(extra, base, routes) do
    cfg = %{base | file: extra.source_path, id: extra.id, language: ExDoc.Language.Elixir}
    %{extra | doc: link_doc(extra.doc, ExDoc.Language.Elixir, cfg, routes)}
  end

  defp link_doc(nil, _lang, _cfg, _routes), do: nil

  defp link_doc(doc, lang, cfg, routes) do
    doc
    |> lang.autolink_doc(cfg)
    |> ExDoc.DocAST.map_tags(fn
      {:a, attrs, inner, meta} -> {:a, rewrite_href(attrs, routes), inner, meta}
      other -> other
    end)
  end

  defp rewrite_href(attrs, routes) do
    case attrs[:href] do
      nil -> attrs
      href -> Keyword.put(attrs, :href, to_route(href, routes))
    end
  end

  defp to_route(href, routes) do
    cond do
      href =~ ~r/^(https?|mailto|ftp):/ ->
        href

      String.starts_with?(href, "#") ->
        # same-page anchor -> slugified to match the member's <a id>
        "#" <> slug(href)

      true ->
        {base, anchor} =
          case String.split(href, "#", parts: 2) do
            [b] -> {b, nil}
            [b, a] -> {b, a}
          end

        case Map.fetch(routes, String.replace_suffix(base, ".html", "")) do
          {:ok, route} -> route <> if(anchor, do: "#" <> slug(anchor), else: "")
          :error -> href
        end
    end
  end

  # --- sidebar manifest (Astro/Starlight `sidebar` shape) -------------------

  defp write_sidebar(config, modules, tasks, extras) do
    pages = grouped(extras, "Pages", fn e -> %{slug: extra_content_slug(e)} end)

    api =
      grouped(modules, "Modules", fn m -> %{slug: Path.join(@api_dir, slug(m.id))} end) ++
        maybe_group(
          "Mix Tasks",
          Enum.map(tasks, fn t -> %{slug: Path.join(@task_dir, slug(t.id))} end)
        )

    sidebar = [%{label: "Pages", items: pages}, %{label: "API", items: api}]
    write!(config, "sidebar.mjs", "export default #{to_json(sidebar)};\n")
    "sidebar.mjs"
  end

  # `/` -> the route of ExDoc's `main:` page (e.g. readme), now that foldering
  # may move it under a group dir; emitted for the Astro app to import
  defp write_redirects(config, routes) do
    target = Map.get(routes, config.main, "/")
    write!(config, "redirects.mjs", "export default #{to_json(%{"/" => target})};\n")
    "redirects.mjs"
  end

  # ExDoc attribution data for the Starlight Footer override (rendered below the
  # prev/next pager). Empty when `footer: false`.
  defp write_meta(config) do
    meta =
      if config.footer,
        do: %{exdocVersion: ExDoc.version(), proglang: to_string(config.proglang)},
        else: %{}

    write!(config, "meta.mjs", "export default #{to_json(meta)};\n")
    "meta.mjs"
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

  @doc false
  # shared so Rian.DocFormatter.MDX emits heading <a id>s with the SAME slugging
  # the link rewriter uses — otherwise Starlight's auto-slug (which differs on
  # e.g. em-dashes) would not match our cross-page anchors
  def slug(id) do
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
