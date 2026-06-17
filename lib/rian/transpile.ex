defmodule Rian.Transpile do
  @moduledoc """
  **Assisted-scaffolding** Elixir→Rian transpiler — the porting accelerator for
  the Elixir-pass-retirement track (the freeze plan in ADR-0063's orbit).

  This is deliberately **not** a one-shot replacement. Translating untyped,
  full-surface Elixir (macros, `Enum`/`Map`, struct reflection, comprehensions)
  into typed, capability-disciplined Rian that survives `Rian.Check` /
  `Rian.Exhaustiveness` / `Rian.Reach` is the *hard* direction — it requires type
  reconstruction a transpiler cannot do alone. So this tool produces a **draft
  skeleton** a human then finishes and equiv-locks against the oracle:

    * forms with a clear Rian image are translated — `def`/`defp` clauses (a
      multi-statement body becomes a block clause `head … end`, a single expression
      the inline `head := expr`), `defstruct` (→ a `struct Mod(…)` record skeleton),
      nested `defmodule`s (a struct-only wrapper flattens to its `struct`; a
      function-bearing one is hoisted to a sibling top-level `mod`, since Rian is
      flat), `@type` (→ a synthesized `type …` decl and/or resolved into `@spec`s),
      `if`/`case` (incl. `when` arms), binary/unary operators, ctor & struct patterns
      (`%ECall{fun: f}` → `ECall(fun: f)`), tuples, lists/cons, atoms, literals, calls;
    * everything else is left **in place** as a greppable `TODO_PORT("…")`
      sentinel (carrying the original Elixir) or a `# TODO[port]: …` line comment,
      so nothing untranslated can masquerade as done;
    * **types are holes** (`_Unk`) by default — Elixir is untyped, so the human
      supplies the sums and signatures. With `--infer` (ADR-0075) the engine fills
      every *provable* slot, **harvesting any `@spec`** as a cross-checked hint (a
      consumed `@spec` becomes a passive `# spec:` provenance line, not a TODO);
      whatever stays unproven remains an honest `_Unk` hole for the human. A **private**
      function (`defp` → `def`) omits its return hole — `Rian.InferLocal` recovers the
      return once its params are typed (infer-local, ADR-0034), one fewer hole per `defp`.

  Usage: `mix rian.transpile lib/rian/range.ex [-o out.rian]`.

  The honest contract: the output **will not compile** until a human fills the
  holes and resolves the markers. The value is the diff between "blank file" and
  "annotated draft", and the TODO summary that quantifies the remaining work per
  module before you commit to porting it.
  """

  @header [
    "# ─────────────────────────────────────────────────────────────────────────",
    "# DRAFT skeleton — transpiled from Elixir by `mix rian.transpile`. NOT done.",
    "# Translated: defs/clauses (+guards), defstruct→struct, if/case, operators,",
    "#   pipes (|>), single- & multi-clause lambdas (multi → `(p) -> case p do …`),",
    "#   ctor/struct patterns, tuples, lists, maps, atoms, literals, local/sibling calls,",
    "#   word sigils (~w → list), referenced @attrs → const, as-patterns (var @ pat),",
    "#   field access (r.f), string interpolation (${e}), nil→None.",
    "# You must still: (1) fill type holes `_Unk`, (2) resolve every",
    "#   `TODO_PORT(...)` / `# TODO[port]` marker, (3) make matches exhaustive,",
    "#   (4) equiv-lock against the Elixir oracle with a fixpoint test.",
    "# Auto-mapped stdlib calls (List./Dict./Str.) are spelled inline but NOT",
    "#   semantics-verified — check arg-order/edge-cases against the Elixir source.",
    "# Other Elixir-stdlib calls are emitted as BEAM FFI (native remote calls): they",
    "#   compile/run on BEAM but are non-portable — Reach pins them off :rs/:js.",
    "# ─────────────────────────────────────────────────────────────────────────",
    ""
  ]

  # Elixir binary operators that map to a Rian infix spelling unchanged. `++`
  # (list concat) is NOT here — Rian has no `++`; it lowers to `List.concat/2`.
  @binops ~w(+ - * / <> <= >= < > == != and or)a
  # Elixir local calls that Rian spells as infix operators.
  @infix_calls %{div: "div", rem: "rem"}

  # Stdlib auto-mapping (A1): `{ElixirMod, fun, arity} => {RianMod, rian_fun}`.
  # **Only** entries whose Rian image genuinely exists in the prelude
  # (`examples/rian/prelude_*.rian`) are listed — mapping to a non-existent
  # `List.map`/`reduce` would emit Rian that references nothing, so those stay
  # `TODO_PORT`. Mapped calls are spelled inline but still need a semantics check
  # (arg-order/edge-cases), flagged in the draft header — the prelude op is not
  # guaranteed bug-for-bug identical to the Elixir original.
  @stdlib %{
    {"Enum", :sum, 1} => {"List", "sum"},
    {"Enum", :product, 1} => {"List", "product"},
    {"Enum", :count, 1} => {"List", "length"},
    {"Enum", :any?, 1} => {"List", "any"},
    {"Enum", :all?, 1} => {"List", "all"},
    {"Enum", :map, 2} => {"List", "map"},
    {"Enum", :filter, 2} => {"List", "filter"},
    {"Enum", :reject, 2} => {"List", "reject"},
    {"Enum", :reduce, 3} => {"List", "reduce"},
    {"Enum", :flat_map, 2} => {"List", "flat_map"},
    {"Enum", :concat, 2} => {"List", "concat"},
    {"Enum", :reverse, 1} => {"List", "reverse"},
    {"Enum", :any?, 2} => {"List", "any_by"},
    {"Enum", :all?, 2} => {"List", "all_by"},
    {"Enum", :join, 2} => {"List", "join"},
    {"Enum", :map_join, 3} => {"List", "map_join"},
    {"Enum", :member?, 2} => {"List", "member"},
    {"Enum", :take, 2} => {"List", "take"},
    {"Enum", :drop, 2} => {"List", "drop"},
    {"Enum", :count, 2} => {"List", "count_by"},
    {"Enum", :find, 2} => {"List", "find"},
    {"Map", :get, 2} => {"Dict", "get"},
    {"Map", :get, 3} => {"Dict", "get_or"},
    {"Map", :put, 3} => {"Dict", "put"},
    {"Map", :has_key?, 2} => {"Dict", "has"},
    {"String", :length, 1} => {"Str", "length"},
    {"String", :to_charlist, 1} => {"Str", "chars"},
    {"List", :to_string, 1} => {"Str", "from_chars"},
    {"Integer", :to_string, 1} => {"Str", "from_int"}
  }

  # Elixir-stdlib modules. A call to one is emitted as a native BEAM FFI call
  # (`Mod.fun(args)`) when it is not individually `@stdlib`-mapped to a portable
  # prelude op — it compiles and runs on BEAM but is non-portable (Reach pins it
  # off `:rs`/`:js`). Everything else capitalized is assumed a sibling Rian module
  # and emitted inline; a lowercase receiver (`r.name`) is struct-field reflection
  # with no Rian image and stays a `TODO_PORT` marker.
  @elixir_stdlib ~w(Enum Map MapSet String Regex Process Tuple Integer Float List
                    Keyword IO Kernel File Stream Atom Base Code Macro Exception
                    Module Application Agent Task GenServer System Path Access
                    Function Range Date Time DateTime Calendar)

  @doc """
  Transpile Elixir source text to a draft Rian skeleton string.

  With `infer: true`, runs whole-program type inference (`Rian.Transpile.Infer`)
  to fill the `_Unk` holes with concrete types where provable (harvesting any
  `@spec` as a cross-checked hint), leaving an honest `_Unk` hole otherwise —
  a hole signals "a human must supply this type", never an auto-filled placeholder.

  **`@rian` annotations** (always honoured, with or without `infer`) are the
  authoritative escape hatch (`Rian.Ann`): a `@rian` module attribute carrying a native
  Rian `def`/`struct`/`type` declaration supplies the exact types inference can't
  recover. A `def` annotation overrides the function's signature; a `struct`/`type`
  annotation replaces the holes the `defstruct`/`@type` emission leaves. A heredoc gives
  multi-line struct/type decls; `use Rian.Ann` keeps the `.ex` warning-free.
  """
  @spec transpile(String.t(), keyword()) :: term()
  def transpile(source, opts \\ []) when is_binary(source) do
    ast = Code.string_to_quoted!(source)
    {sigmap, types} = if opts[:infer], do: infer_program(ast), else: {%{}, []}

    # `@rian` annotations are authoritative — merge `def` sigs OVER inference, hand the
    # `struct`/`type` decls to the renderer. Read from the AST we ALREADY parsed (no
    # second parse of the source text); `Rian.Ann.from_beam/1` is the no-source reader.
    {def_anns, struct_anns, type_anns} = classify_annotations(Rian.Ann.from_ast(ast))

    ast
    |> toplevel(Map.merge(sigmap, def_anns), types ++ type_anns, struct_anns)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Render the program. Rian modules are flat (`Rian.Decl` has no nested `mod`),
  # so a function-bearing nested Elixir module is hoisted to a sibling top-level
  # `mod` rather than nested (where it would be silently dropped); a struct-only
  # nested module stays, flattening into the parent's `struct` decls.
  defp toplevel({:defmodule, _, _} = top, sigmap, types, struct_anns) do
    [parent | hoisted] = flatten_modules(top)

    @header ++
      module_lines(parent, sigmap, types, struct_anns) ++
      Enum.flat_map(hoisted, &["" | module_lines(&1, sigmap, [], struct_anns)])
  end

  defp toplevel(other, _sigmap, _types, _struct_anns) do
    @header ++ ["# TODO[port]: top-level is not a single `defmodule`", "# #{snippet(other)}"]
  end

  # `[parent | hoisted]` — the top module with its function-bearing submodules
  # removed, followed by each of those submodules (recursively flattened) as a
  # standalone top-level module.
  defp flatten_modules({:defmodule, m, [al, [do: body]]}) do
    {hoist, keep} = Enum.split_with(block_stmts(body), &hoistable_submodule?/1)
    parent = {:defmodule, m, [al, [do: {:__block__, [], keep}]]}
    [parent | Enum.flat_map(hoist, &flatten_modules/1)]
  end

  defp hoistable_submodule?({:defmodule, _, [_, [do: b]]}),
    do: not struct_only_module?(block_stmts(b))

  defp hoistable_submodule?(_), do: false

  # the `mod Name do … end` lines for one module (no header).
  defp module_lines({:defmodule, _, [aliases, [do: body]]}, sigmap, types, struct_anns) do
    name = short_name(aliases)
    referenced = referenced_attrs(body)

    inner =
      body
      |> block_stmts()
      |> render_items(sigmap, name, struct_anns, referenced)
      |> Enum.map(&indent/1)

    # synthesized `type …` declarations (Phase B error sets, `@rian type`) after `mod … do`.
    type_lines = if types == [], do: [], else: Enum.map(types, &("  " <> &1)) ++ [""]
    ["mod #{name} do" | type_lines ++ inner] ++ ["end"]
  end

  # split `@rian` annotation strings into `{def sigmap, struct-by-name, [type decl]}`.
  # Whitespace is collapsed so a heredoc multi-line decl parses/emits as one line.
  defp classify_annotations(strings) do
    Enum.reduce(strings, {%{}, %{}, []}, fn raw, {defs, structs, types} ->
      str = raw |> String.replace(~r/\s+/, " ") |> String.trim()

      # Classify by *parsing* the annotation with the real Rian declaration parser
      # rather than sniffing it with regex: a `struct`/`type` decl parses directly;
      # a bodiless `def` head does not (it raises "no clauses"), so it falls through
      # to `parse_rian_sig`, which supplies the dummy body.
      case safe_decl(str) do
        %{structs: [s | _]} ->
          {defs, Map.put(structs, s.name, str), types}

        %{types: [_ | _]} ->
          {defs, structs, types ++ [str]}

        _ ->
          case parse_rian_sig(str) do
            {k, sig} ->
              {Map.put(defs, k, sig), structs, types}

            # Not a struct/type decl and not a parseable def head — the annotation
            # is unusable. Surface it instead of silently dropping it to `_Unk`
            # (the old regex path swallowed such mistakes without a trace).
            nil ->
              IO.warn("ignoring unparseable @rian annotation: #{inspect(str)}", [])
              {defs, structs, types}
          end
      end
    end)
  end

  # Parse a declaration annotation, returning nil instead of raising when the
  # string is not a complete declaration (e.g. a bodiless `def` head).
  defp safe_decl(str) do
    Rian.Decl.parse(str)
  rescue
    _ -> nil
  end

  # parse a Rian def signature into a sigmap entry, keyed by its own {name, arity}.
  # A dummy body makes the bodiless head a complete, parseable clause.
  defp parse_rian_sig(sig) do
    case Rian.Decl.parse(sig <> " := nil") do
      %{funcs: [f | _]} ->
        {{to_string(f.name), length(f.params)},
         %{params: Enum.map(f.params, & &1.type), ret: f.ret, tvars: f.tvars}}

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # Phase B: assemble Result returns (`Payload | Errors`) and synthesize the
  # `type Errors := Tag | …` declaration from the error tags the inferer collected.
  # Phase C+: harvest `@type` decls — synthesize `type Name := …` and resolve local
  # type refs in `@spec`s (`type_env`).
  defp infer_program({:defmodule, _, [_, [do: _]]} = ast), do: infer_program_local(ast)
  defp infer_program(_), do: {%{}, []}

  defp infer_program_local({:defmodule, _, [aliases, [do: body]]} = ast) do
    stmts = block_stmts(body)
    {type_env, type_decls} = Rian.Transpile.Infer.collect_types(stmts, short_name(aliases))
    sigmap = infer_sigs(ast, type_env)

    tags =
      sigmap
      |> Map.values()
      |> Enum.flat_map(&Map.get(&1, :error_tags, []))
      |> Enum.uniq()
      |> Enum.sort()

    sigmap =
      if tags == [] do
        sigmap
      else
        Map.new(sigmap, fn {k, v} ->
          if Map.get(v, :result, false), do: {k, %{v | ret: "#{v.ret} | Errors"}}, else: {k, v}
        end)
      end

    error_decls = if tags == [], do: [], else: ["type Errors := #{Enum.join(tags, " | ")}"]
    {sigmap, type_decls ++ error_decls}
  end

  @doc """
  Transpile and report `{text, stats}` — `ports` counts unresolved markers,
  `defs` counts emitted function groups, `mapped` counts auto-mapped stdlib
  calls, and (with `infer: true`) `holes`/`filled` count remaining vs filled
  type slots.
  """
  @spec transpile_with_stats(String.t(), keyword()) :: term()
  def transpile_with_stats(source, opts \\ []) when is_binary(source) do
    text = transpile(source, opts)
    lines = String.split(text, "\n")

    ports =
      Enum.count(
        lines,
        &(String.contains?(&1, "TODO_PORT") or String.contains?(&1, "TODO[port]"))
      )

    defs = Enum.count(lines, &Regex.match?(~r/^\s+(pub )?def \w+\(/, &1))
    # auto-mapped stdlib calls (A1) — resolved inline, but flagged for a semantics
    # check; counted (occurrences, not lines) so the report can surface them.
    mapped = Regex.scan(~r/\b(?:List|Dict|Str|Int)\.[a-z_]+\(/, text) |> length()
    # holes/open are counted over the code only — the header comment illustrates
    # `_Unk` and must not inflate the count.
    code =
      lines |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#")) |> Enum.join("\n")

    holes = Regex.scan(~r/\b_Unk\b/, code) |> length()
    {text, %{ports: ports, defs: defs, mapped: mapped, holes: holes}}
  end

  # ── type inference (ADR-0034-aligned hole filling) ─────────────────────────
  # Two passes: pass 1 infers each def group in isolation; pass 2 re-infers with
  # the fully-resolved sigs as an intra-module sibling table (so a local call can
  # adopt a callee's inferred type). Returns `{name, arity} => %{params, ret, tvars}`.
  defp infer_sigs(ast, type_env \\ %{})

  defp infer_sigs({:defmodule, _, [_, [do: body]]}, type_env) do
    stmts = block_stmts(body)
    groups = def_groups(stmts)
    key = fn g -> {to_string(hd(g.clauses).name), hd(g.clauses).arity} end

    # harvest `@spec` hints once (local `@type` refs resolved via type_env); they seed
    # both passes (cross-checked in infer_group).
    specs = Rian.Transpile.Infer.collect_specs(stmts, type_env)

    # build the context (parses the prelude) ONCE per pass, not per group.
    ctx1 = Map.put(Rian.Transpile.Infer.build_ctx(@stdlib), :specs, specs)
    pass1 = Map.new(groups, fn g -> {key.(g), Rian.Transpile.Infer.infer_group(g, ctx1)} end)

    siblings =
      for {k, v} <- pass1, not hole_sig?(v), into: %{} do
        {k, %{params: v.params, ret: v.ret, tvars: v.tvars}}
      end

    ctx2 = %{ctx1 | siblings: siblings}
    Map.new(groups, fn g -> {key.(g), Rian.Transpile.Infer.infer_group(g, ctx2)} end)
  end

  defp infer_sigs(_, _), do: %{}

  @doc "The Elixir→Rian stdlib call-mapping table (for type inference)."
  @spec stdlib_map() :: map()
  def stdlib_map, do: @stdlib

  @doc """
  Per-def inference ledger for `--infer-report`: `[{ {name, arity}, ledger }]`
  where each ledger lists the remaining holes and why (`:unresolved`, …).
  """
  @spec infer_report(String.t()) :: term()
  def infer_report(source) when is_binary(source) do
    ast = Code.string_to_quoted!(source)
    for {k, v} <- infer_sigs(ast), v.ledger != [], do: {k, v.ledger}
  end

  @doc """
  Phase A: prime the whole-program cross-module signature table from a list of
  Elixir sources, so a subsequent `transpile(_, infer: true)` resolves
  cross-module calls (`OtherMod.fun(…)`). Call once before folder-mode rendering.
  """
  @spec prime_xmod(list()) :: term()
  def prime_xmod(sources) when is_list(sources) do
    sources
    |> Enum.map(&module_groups/1)
    |> Enum.reject(&is_nil/1)
    |> Rian.Transpile.Infer.prime_xmod(@stdlib)
  end

  defp module_groups(src) do
    case Code.string_to_quoted(src) do
      {:ok, {:defmodule, _, [aliases, [do: body]]}} ->
        {short_name(aliases), body |> block_stmts() |> def_groups()}

      _ ->
        nil
    end
  end

  defp hole_sig?(%{params: ps, ret: r}), do: r == "_Unk" or Enum.any?(ps, &(&1 == "_Unk"))

  # Collect just the def groups (reusing the clause grouping), no rendering.
  defp def_groups(stmts) do
    {groups, open} =
      Enum.reduce(stmts, {[], nil}, fn stmt, {acc, open} ->
        case classify(stmt) do
          {:clause, vis, head, kw} ->
            clause = build_clause(head, kw)

            if open && same_group?(open, vis, clause),
              do: {acc, add_clause(open, clause)},
              else: {close_group(acc, open), new_group(vis, clause, nil)}

          _ ->
            {close_group(acc, open), nil}
        end
      end)

    close_group(groups, open)
  end

  defp close_group(acc, nil), do: acc
  defp close_group(acc, g), do: acc ++ [g]

  @doc """
  Rank transpiled modules by port difficulty for folder-mode triage. Takes
  `[{name, %{defs:, ports:}}]` and returns rows sorted easiest-first by
  markers-per-def, each tagged `"easy"` (<3), `"med"`, `"hard"` (≥6), or `"—"`
  (no defs). The ratio is the honest cost signal: a struct-reflection module
  (many markers per def) sorts last; a near-portable one sorts first.
  """
  @spec rank(list()) :: term()
  def rank(entries) do
    entries
    |> Enum.map(fn {name, stats} ->
      %{defs: defs, ports: ports} = stats
      ratio = if defs > 0, do: ports / defs, else: ports * 1.0

      tag =
        cond do
          defs == 0 -> "—"
          ratio < 3.0 -> "easy"
          ratio >= 6.0 -> "hard"
          true -> "med"
        end

      %{
        name: name,
        defs: defs,
        ports: ports,
        mapped: Map.get(stats, :mapped, 0),
        ratio: ratio,
        tag: tag
      }
    end)
    |> Enum.sort_by(& &1.ratio)
  end

  # ── module ────────────────────────────────────────────────────────────────

  defp short_name({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()
  defp short_name(other), do: snippet(other)

  defp block_stmts({:__block__, _, stmts}), do: stmts
  defp block_stmts(single), do: [single]

  # ── declarations ────────────────────────────────────────────────────────────
  #
  # Walk the statement list, attaching a pending `@doc` to the next def, and
  # merging consecutive same-name/arity clauses into one rendered group.

  defp render_items(stmts, sigmap, mod_name, struct_anns, referenced) do
    {lines, _pending_doc, open} =
      Enum.reduce(stmts, {[], nil, nil}, fn stmt, {acc, doc, open} ->
        case classify(stmt) do
          :skip ->
            # subsumed by Rian's type system (e.g. `@enforce_keys`) — emit nothing.
            {acc, doc, open}

          {:submodule, name, body} ->
            # Elixir nests struct/util modules; recurse. A struct-only wrapper flattens
            # to its `struct …` decl (the module is just a namespace for the struct);
            # a submodule with other content nests as `mod Name do … end`.
            {acc ++
               flush(open, sigmap) ++
               render_submodule(name, body, sigmap, struct_anns, referenced), doc, nil}

          {:defstruct, fields} ->
            # an Elixir `defstruct` IS the module's record type → a Rian `struct` decl
            # named for the module; a `@rian struct …` annotation supplies the field
            # types, else they are `_Unk` holes for a human to type.
            {acc ++ flush(open, sigmap) ++ [struct_decl(mod_name, fields, struct_anns)], doc, nil}

          {:moduledoc, text} ->
            {acc ++ flush(open, sigmap) ++ [""] ++ moduledoc_lines(text), doc, nil}

          {:doc, text} ->
            {acc ++ flush(open, sigmap), text, nil}

          {:drop, what, node} ->
            # alias/import/require are intentionally dropped (Rian resolves modules
            # differently) — a plain note, NOT a porting marker.
            {acc ++ flush(open, sigmap) ++ ["# (dropped Elixir `#{what}`: #{snippet(node)})"],
             doc, nil}

          {:clause, vis, head, kw} ->
            clause = build_clause(head, kw)

            cond do
              open && same_group?(open, vis, clause) ->
                {acc, doc, add_clause(open, clause)}

              true ->
                {acc ++ flush(open, sigmap), nil, new_group(vis, clause, doc)}
            end

          {:spec, node} ->
            # `@spec` is HARVESTED into the typed signature when inferring (seeded +
            # cross-checked in Infer.seed_spec/6) — keep it as passive provenance, not a
            # `TODO[port]` action marker (the type info now lives in the signature).
            {acc ++ flush(open, sigmap) ++ ["# spec: #{snippet(node)}"], doc, nil}

          {:type_decl, node} ->
            # `@type` is HARVESTED (synthesized to a `type …` decl and/or resolved into
            # `@spec` types when inferring) — passive provenance, not a TODO action.
            {acc ++ flush(open, sigmap) ++ ["# type: #{snippet(node)}"], doc, nil}

          {:attr_def, name, value} ->
            # An Elixir module attribute. When it is referenced as a value it is a
            # module constant → a Rian `const` (its type omitted — Rian infers it
            # from the value, Crystal-style); otherwise it is a directive (`@impl`,
            # `@typep`) with no Rian image → a port marker.
            line =
              if MapSet.member?(referenced, name),
                do: "const #{name} := #{render_body(value)}",
                else: "# TODO[port]: @#{name} #{snippet(value)}"

            {acc ++ flush(open, sigmap) ++ [line], doc, nil}

          {:other, node} ->
            {acc ++ flush(open, sigmap) ++ ["# TODO[port]: #{snippet(node)}"], doc, nil}
        end
      end)

    lines ++ flush(open, sigmap)
  end

  # Names of module attributes that are *referenced as a value* (`@prims` in an
  # expression), as opposed to merely *defined*. Only these lower to a Rian
  # `const`; a directive attribute (`@impl true`) is never read back this way.
  defp referenced_attrs(body) do
    {_, set} =
      Macro.prewalk(body, MapSet.new(), fn
        {:@, _, [{name, _, ctx}]} = node, acc when is_atom(name) and not is_list(ctx) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp classify({:@, _, [{:moduledoc, _, [text]}]}) when is_binary(text), do: {:moduledoc, text}
  defp classify({:@, _, [{:moduledoc, _, _}]}), do: {:moduledoc, ""}
  defp classify({:@, _, [{:doc, _, [text]}]}) when is_binary(text), do: {:doc, text}
  defp classify({:alias, _, _} = n), do: {:drop, "alias", n}
  defp classify({:import, _, _} = n), do: {:drop, "import", n}
  defp classify({:require, _, _} = n), do: {:drop, "require", n}
  defp classify({:@, _, [{:spec, _, _}]} = n), do: {:spec, n}
  defp classify({:@, _, [{:type, _, _}]} = n), do: {:type_decl, n}
  # `@enforce_keys` is an Elixir runtime concern subsumed by Rian's typed fields.
  defp classify({:@, _, [{:enforce_keys, _, _}]}), do: :skip
  # `@rian` annotations are HARVESTED into the signatures/struct/type decls; the
  # `use Rian.Ann` directive is annotation support — both are consumed, not ported.
  defp classify({:@, _, [{:rian, _, _}]}), do: :skip
  defp classify({:use, _, [{:__aliases__, _, [:Rian, :Ann]}]}), do: :skip

  defp classify({:defmodule, _, [{:__aliases__, _, _} = al, [do: body]]}),
    do: {:submodule, short_name(al), body}

  defp classify({:defstruct, _, [fields]} = n) when is_list(fields) do
    if Enum.all?(fields, &struct_field?/1), do: {:defstruct, fields}, else: {:other, n}
  end

  defp classify({:def, _, [head, kw]}), do: {:clause, :pub, head, kw}
  defp classify({:defp, _, [head, kw]}), do: {:clause, :priv, head, kw}

  # Any remaining `@name <value>` (after the doc/spec/type/rian clauses above) is a
  # module attribute — a constant or a directive; `render_items` decides which.
  defp classify({:@, _, [{name, _, [value]}]}) when is_atom(name), do: {:attr_def, name, value}
  defp classify(other), do: {:other, other}

  # render a nested `defmodule`: flatten a struct-only wrapper to its `struct` decl
  # (Elixir's one-struct-per-module idiom), else nest it as a `mod … do … end`.
  # Only struct-only nested modules reach here — function-bearing ones are hoisted
  # to standalone top-level `mod`s by `flatten_modules/1`. A struct-only module is
  # just a namespace for its `struct`, so it flattens to that struct's decl.
  defp render_submodule(name, body, sigmap, struct_anns, referenced) do
    render_items(block_stmts(body), sigmap, name, struct_anns, referenced)
  end

  # a wrapper whose only real declaration is a `defstruct` (the rest is docs /
  # `@enforce_keys` / `@type`) — its `mod` shell is noise in Rian.
  defp struct_only_module?(stmts) do
    match?([{:defstruct, _, _}], Enum.reject(stmts, &struct_mod_noise?/1))
  end

  defp struct_mod_noise?({:@, _, [{a, _, _}]})
       when a in [:moduledoc, :doc, :typedoc, :enforce_keys, :type, :typep],
       do: true

  defp struct_mod_noise?(_), do: false

  # a `defstruct` field: a bare atom (`:x`) or a `{atom, default}` keyword pair.
  defp struct_field?(a) when is_atom(a), do: true
  defp struct_field?({a, _default}) when is_atom(a), do: true
  defp struct_field?(_), do: false

  # `defstruct [:x, y: 0]` → `struct Mod(x _Unk, y _Unk)` (defaults dropped — the field
  # NAMES port; their types and any default are for the human to fill). A `@rian struct
  # Mod(…)` annotation (by name) supplies the field types verbatim instead.
  defp struct_decl(mod_name, fields, struct_anns) do
    case Map.get(struct_anns, mod_name) do
      nil ->
        names =
          Enum.map(fields, fn
            {k, _default} -> k
            k -> k
          end)

        "struct #{mod_name}(#{Enum.map_join(names, ", ", &"#{&1} _Unk")})"

      decl ->
        decl
    end
  end

  # A clause: name, arity, parameter/pattern nodes, optional guard, body AST.
  defp build_clause(head, kw) do
    {call, guard} =
      case head do
        {:when, _, [c, g]} -> {c, g}
        c -> {c, nil}
      end

    {name, args} =
      case call do
        {n, _, a} when is_atom(n) and is_list(a) -> {n, a}
        {n, _, a} when is_atom(n) and is_nil(a) -> {n, []}
      end

    # Distinguish a *present* `nil` body (`def f, do: nil`) from a truly bodyless
    # def (no `:do` key): both reduce to the atom `nil`, but only the former should
    # route through the `nil → Option` marker. The sentinel marks genuine absence.
    body = if kw && Keyword.has_key?(kw, :do), do: Keyword.get(kw, :do), else: :__no_body__
    %{name: name, arity: length(args), args: args, guard: guard, body: body}
  end

  defp new_group(vis, clause, doc), do: %{vis: vis, doc: doc, clauses: [clause]}
  defp add_clause(open, clause), do: %{open | clauses: open.clauses ++ [clause]}

  defp same_group?(open, vis, clause) do
    open.vis == vis and hd(open.clauses).name == clause.name and
      hd(open.clauses).arity == clause.arity
  end

  # ── rendering a def group ───────────────────────────────────────────────────

  defp flush(nil, _sigmap), do: []

  defp flush(%{vis: vis, doc: doc, clauses: clauses}, sigmap) do
    kw = if vis == :pub, do: "pub def", else: "def"
    doc_lines = if doc, do: [~s(@doc "#{escape(one_line(doc))}")], else: []
    name = hd(clauses).name
    arity = hd(clauses).arity

    # inferred sig (or all-holes when inference is off / the slot is unresolved).
    sig = Map.get(sigmap, {to_string(name), arity})
    ptypes = if sig, do: sig.params, else: List.duplicate("_Unk", arity)
    ret = if sig, do: sig.ret, else: "_Unk"
    forall = if sig && sig.tvars != [], do: " forall #{Enum.join(sig.tvars, ", ")}", else: ""

    # infer-local (ADR-0034): a PRIVATE function needn't declare its return — drop the
    # `_Unk` return hole so `Rian.InferLocal` recovers it once the params are typed
    # (one fewer hole per `defp`). `pub` keeps its declared boundary; a return inference
    # already resolved (a real type) is kept as useful signal.
    ret_part = if vis != :pub and ret == "_Unk", do: "", else: " #{ret}"

    body_lines =
      if simple?(clauses) do
        [c] = clauses

        params =
          c.args
          |> Enum.zip(ptypes)
          |> Enum.map_join(", ", fn {a, t} -> param(var_name(a), t, vis) end)

        clause_lines("#{kw} #{name}(#{params})#{ret_part}#{forall}", c.body)
      else
        sig_line = "#{kw} #{name}(#{sig_params(ptypes, vis)})#{ret_part}#{forall}"
        [sig_line | Enum.flat_map(clauses, &render_clause(kw, &1))]
      end

    [""] ++ doc_lines ++ body_lines
  end

  # A clause's body lines. A multi-statement body becomes a **block clause**
  # (`head\n  stmt\n  …\n  final\nend`); a single expression stays the inline
  # `head := expr` form. The block reads far better than the `;`-joined one-liner.
  defp clause_lines(head, {:__block__, _, [_, _ | _] = stmts}),
    do: [head] ++ Enum.map(stmts, &("  " <> stmt(&1))) ++ ["end"]

  defp clause_lines(head, body), do: ["#{head} := #{render_body(body)}"]

  # A PRIVATE parameter whose type is an unresolved hole omits the type — Rian
  # infers it (infer-local, like the dropped private return), so the draft carries
  # no `_Unk` noise. A `pub` parameter keeps its declared boundary (declare-public).
  defp param(name, "_Unk", vis) when vis != :pub, do: name
  defp param(name, type, _vis), do: "#{name} #{type}"

  # The multi-clause signature line lists param TYPES (the clauses carry the
  # patterns). For a private function with all-hole params, drop the `_Unk` types
  # to inferred placeholder names — Rian still needs a head to group the clauses.
  defp sig_params(ptypes, vis) do
    if vis != :pub and Enum.all?(ptypes, &(&1 == "_Unk")) do
      Enum.map_join(1..length(ptypes), ", ", &"p#{&1}")
    else
      Enum.join(ptypes, ", ")
    end
  end

  # "Simple" = a single clause whose params are all plain variables and no guard;
  # render inline `def f(a _Unk) _Unk := body`. Anything else gets a sig + clauses.
  defp simple?([%{args: args, guard: nil}]), do: Enum.all?(args, &var?/1)
  defp simple?(_), do: false

  defp render_clause(kw, c) do
    pats = c.args |> Enum.map(&pat/1) |> Enum.join(", ")
    # Rian supports `when` guards in clause heads (proven equiv-lockable), so
    # translate the guard rather than dropping it to a note.
    guard = if c.guard, do: " when #{expr(c.guard)}", else: ""
    clause_lines("#{kw} #{name_str(c.name)}(#{pats})#{guard}", c.body)
  end

  defp name_str(n), do: to_string(n)
  defp var_name({n, _, ctx}) when is_atom(n) and is_atom(ctx), do: to_string(n)
  defp var_name(other), do: snippet(other)

  # ── bodies ──────────────────────────────────────────────────────────────────

  defp render_body(:__no_body__), do: ~s|TODO_PORT("bodyless clause")|

  # multi-statement body → Rian `;`-separated block: `x := e; …; final` (Pratt
  # parses a function body as a block of statements with a final expression).
  defp render_body({:__block__, _, stmts}) when length(stmts) > 1 do
    Enum.map_join(stmts, "; ", &stmt/1)
  end

  defp render_body({:__block__, _, [one]}), do: expr(one)
  defp render_body(node), do: expr(node)

  # a block statement: an Elixir bind `x = e` → Rian bind `x := e`; anything else
  # (incl. the final return expression) is a bare expression.
  defp stmt({:=, _, [lhs, rhs]}), do: "#{pat(lhs)} := #{expr(rhs)}"
  defp stmt(other), do: expr(other)

  # ── expressions ─────────────────────────────────────────────────────────────

  defp expr(n) when is_integer(n) or is_float(n), do: to_string(n)
  defp expr(s) when is_binary(s), do: ~s|"#{escape(s)}"|
  defp expr(true), do: "true"
  defp expr(false), do: "false"
  # Rian has no `nil`; the canonical port of a nullable is `Option`, whose empty
  # case is `None`. (A `nil` used as a non-Option sentinel will surface at the
  # type gate — that is the right place, not a transpile-time marker.)
  defp expr(nil), do: "None"
  defp expr(a) when is_atom(a), do: ":#{a}"

  # a bare Capitalized identifier `Foo` (a nullary ctor / sum variant, e.g. an
  # error tag `{:error, DivByZero}`) → its name, not `__aliases__(:Foo)`.
  defp expr({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()

  # string interpolation `"a#{e}b"` — an Elixir `<<>>` binary of literal parts and
  # `Kernel.to_string`/`::binary` segments → Rian interpolated string `"a${e}b"`
  # (ADR-0069). Only when every segment is string-shaped; a genuine binary
  # construction (sizes/integer segments) is flagged instead.
  defp expr({:<<>>, _, segments} = n) do
    case string_parts(segments) do
      {:ok, parts} -> ~s|"#{Enum.join(parts)}"|
      :error -> ~s|TODO_PORT("binary construction #{escape(snippet(n))}")|
    end
  end

  # 2-tuples are genuine Elixir tuples in quoted form; n-tuples are {:{}, _, _}.
  defp expr({l, r}), do: "{#{expr(l)}, #{expr(r)}}"
  defp expr({:{}, _, elems}), do: "{#{Enum.map_join(elems, ", ", &expr/1)}}"

  # struct construction `%Mod{f: e, …}` → Rian ctor call `Mod(f: e, …)` (the
  # expression-side dual of the struct *pattern* clause below). Must precede the
  # generic local-call clause, else `{:%, _, [aliases, map]}` is mistaken for a
  # 2-arg call named `:%` and emits a malformed `%(__aliases__(...), …)`.
  # struct/map *update* `%Mod{base | f: v}` carries a leading `{:|, …}` element —
  # Rian sums are immutable tagged tuples, so there is no direct image; flag it
  # rather than crash trying to destructure the cons as a `{k, v}` pair.
  defp expr({:%, _, [_aliases, {:%{}, _, [{:|, _, _} | _]}]} = n),
    do: ~s|TODO_PORT("struct update #{escape(snippet(n))}")|

  defp expr({:%, _, [aliases, {:%{}, _, kvs}]}) do
    fields = Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{expr(v)}" end)
    "#{short_name(aliases)}(#{fields})"
  end

  # map *update* `%{base | k: v}` has no Rian image (immutable) — flag it.
  defp expr({:%{}, _, [{:|, _, _} | _]} = m),
    do: ~s|TODO_PORT("map update #{escape(snippet(m))}")|

  # atom-keyed map literal `%{k: v}` → Rian `%{k: v}` (Rian has map literals).
  # Non-atom keys (`%{expr => v}`) have no `key: value` spelling here — flagged.
  defp expr({:%{}, _, kvs} = m) do
    if Enum.all?(kvs, &match?({k, _} when is_atom(k), &1)) do
      "%{#{Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{expr(v)}" end)}}"
    else
      ~s|TODO_PORT("map literal #{escape(snippet(m))}")|
    end
  end

  defp expr({op, _, [l, r]}) when op in @binops,
    do: "#{expr(l)} #{op} #{expr(r)}"

  # Elixir list concat `l ++ r` → the portable prelude `List.concat/2` (Rian has no
  # `++` operator).
  defp expr({:++, _, [l, r]}), do: "List.concat(#{expr(l)}, #{expr(r)})"

  # The pipe is real Rian surface (`x |> f(y)` ≡ `f(x, y)`, ADR/01_basics) — render
  # it infix. Without this it falls through to the generic local-call clause and
  # mis-renders as the prefix `|>(l, r)`.
  defp expr({:|>, _, [l, r]}), do: "#{expr(l)} |> #{pipe_rhs(r)}"

  # A match `=` reached in expression position (a `with`/`case` arm, a nested
  # statement) is Rian's bind `:=`, same as the block-statement path (`stmt/1`).
  # Without this it falls through to the generic local-call clause and mis-renders
  # as the prefix `=(l, r)`.
  defp expr({:=, _, [l, r]}), do: "#{pat(l)} := #{expr(r)}"

  defp expr({:-, _, [x]}), do: "-#{expr(x)}"
  defp expr({:not, _, [x]}), do: "not #{expr(x)}"
  defp expr({:!, _, [x]}), do: "not #{expr(x)}"

  defp expr({:if, _, [c, kw]}) do
    t = render_body(Keyword.get(kw, :do))
    e = if Keyword.has_key?(kw, :else), do: render_body(Keyword.get(kw, :else)), else: nil
    if e, do: "if #{expr(c)} do #{t} else #{e} end", else: "if #{expr(c)} do #{t} end"
  end

  defp expr({:case, _, [subj, [do: arms]]}) do
    rendered = Enum.map_join(arms, "\n", fn arm -> indent(case_arm(arm)) end)
    "case #{expr(subj)} do\n#{rendered}\nend"
  end

  # single-clause anonymous fn `fn a, b -> body end` → Rian lambda `(a, b) -> body`
  # (ADR-0042).
  defp expr({:fn, _, [{:->, _, [args, body]}]}) do
    params = Enum.map_join(args, ", ", &pat/1)
    "(#{params}) -> #{render_body(body)}"
  end

  # multi-clause `fn` → a single-clause lambda over fresh params that `case`-matches
  # on them (Rian lambdas are single-clause, ADR-0042). Arity > 1 matches on the
  # tuple of params; guards and per-clause patterns are preserved via `case_arm`.
  defp expr({:fn, _, [_ | _] = clauses}) do
    n = fn_arity(hd(clauses))
    params = Enum.map(1..n, &"p#{&1}")
    subject = if n == 1, do: hd(params), else: "{#{Enum.join(params, ", ")}}"
    arms = Enum.map_join(clauses, "\n", &indent(case_arm(fn_clause_to_arm(&1, n))))
    "(#{Enum.join(params, ", ")}) -> case #{subject} do\n#{arms}\nend"
  end

  # function captures (ADR-0042) → eta-expanded Rian lambdas.
  # `&name/arity` → `(p1,…) -> name(p1,…)`
  defp expr({:&, _, [{:/, _, [{name, _, ctx}, arity]}]})
       when is_atom(name) and is_atom(ctx) and is_integer(arity) do
    ps = capture_params(arity)
    "(#{Enum.join(ps, ", ")}) -> #{name}(#{Enum.join(ps, ", ")})"
  end

  # `&Mod.fun/arity` → `(p1,…) -> Mod.fun(p1,…)` (reusing the remote-call lowering)
  defp expr({:&, _, [{:/, _, [{{:., _, [_, _]} = dot, _, []}, arity]}]}) when is_integer(arity) do
    ps = capture_params(arity)
    args = Enum.map(ps, &{String.to_atom(&1), [], nil})
    "(#{Enum.join(ps, ", ")}) -> #{expr({dot, [], args})}"
  end

  # `&(… &1 … &2 …)` → eta-expand: bind `p1..pN`, substitute the placeholders.
  defp expr({:&, _, [body]}) do
    ps = capture_params(max_placeholder(body))
    "(#{Enum.join(ps, ", ")}) -> #{expr(subst_ph(body, ps))}"
  end

  # cons `[h | t]` and proper list literals.
  defp expr({:|, _, [h, t]}), do: "#{expr(h)} | #{expr(t)}"

  defp expr(list) when is_list(list),
    do: "[#{Enum.map_join(list, ", ", &expr/1)}]"

  # local call mapped to a Rian infix operator (`div`, `rem`).
  defp expr({op, _, [l, r]}) when is_map_key(@infix_calls, op),
    do: "#{expr(l)} #{@infix_calls[op]} #{expr(r)}"

  # `Mod.fun(args)` / `Mod.fun()` — a call on an alias module: (1) auto-map to a
  # Rian prelude call when the image exists (`@stdlib`); (2) inline if `Mod` is a
  # sibling Rian module; (3) Elixir-stdlib → BEAM FFI; (4) else flag.
  defp expr({{:., _, [{:__aliases__, _, _} = mod, fun]}, _, args}) when is_list(args),
    do: remote_call(mod, fun, args, 0)

  # `value.field` (a dot on a non-module value, no args) is struct/map field access
  # — Rian reads it natively (`value.field`, lowering to a map get on every target),
  # so it needs no FFI. Alias receivers are handled above; an atom receiver
  # (`:erl.f()`) is a remote call, excluded by `not is_atom(recv)`.
  defp expr({{:., _, [recv, field]}, _, []}) when is_atom(field) and not is_atom(recv),
    do: "#{expr(recv)}.#{field}"

  # any other dot call (`:erlang.f()`, a method on a variable) — remote call.
  defp expr({{:., _, [mod, fun]}, _, args}) when is_list(args),
    do: remote_call(mod, fun, args, 0)

  # local call / nullary var reference.
  # A module-attribute *reference* used as a value (`@prims`) is a read of a module
  # constant — render the bare name (the definition lowers to a `const`). Without
  # this it falls through to the generic call clause and mis-renders as `@(prims)`.
  defp expr({:@, _, [{name, _, ctx}]}) when is_atom(name) and not is_list(ctx),
    do: to_string(name)

  # `~w(a b c)` word sigil → a Rian list literal (the common spelling of the string/
  # atom-list module constants this transpiler turns into `const`s). The `a`
  # modifier yields atoms; the default yields strings.
  defp expr({:sigil_w, _, [{:<<>>, _, [str]}, mods]}) when is_binary(str) do
    fmt = if ?a in mods, do: &":#{&1}", else: &~s|"#{&1}"|
    "[#{str |> String.split() |> Enum.map_join(", ", fmt)}]"
  end

  defp expr({name, _, args}) when is_atom(name) and is_list(args),
    do: "#{name}(#{Enum.map_join(args, ", ", &expr/1)})"

  defp expr({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: to_string(name)

  # anonymous-function application `f.(args)` → Rian variable application `f(args)`
  # (Rian distinguishes calling a fn-valued variable from a local call by scope).
  defp expr({{:., _, [f]}, _, args}) when is_list(args),
    do: "#{expr(f)}(#{Enum.map_join(args, ", ", &expr/1)})"

  defp expr(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

  # RHS of a pipe `l |> r`: the pipe injects `l` as the first arg, so a stdlib
  # call written with N args is really arity N+1 for the `@stdlib` lookup —
  # without the bump, `xs |> Enum.reverse()` (written arity 0) misses the mapped
  # `{"Enum", :reverse, 1}` and wrongly stays a marker.
  defp pipe_rhs({{:., _, [mod, fun]}, _, args}) when is_list(args),
    do: remote_call(mod, fun, args, 1)

  defp pipe_rhs(other), do: expr(other)

  # remote call `Mod.fun(args)`: (1) auto-map to a Rian prelude call when the
  # image exists (`@stdlib`); (2) emit inline if `Mod` is a sibling Rian module;
  # (3) else flag — Elixir stdlib / atom module / variable field-access (`r.name`)
  # has no clean Rian image. `pipe_arity` is 1 when this is a piped call head.
  defp remote_call(mod, fun, args, pipe_arity) do
    arg_strs = Enum.map_join(args, ", ", &expr/1)
    m = mod_str(mod)

    cond do
      Map.has_key?(@stdlib, {m, fun, length(args) + pipe_arity}) ->
        {rmod, rfun} = @stdlib[{m, fun, length(args) + pipe_arity}]
        "#{rmod}.#{rfun}(#{arg_strs})"

      sibling_module?(mod, m) ->
        "#{m}.#{fun}(#{arg_strs})"

      elixir_stdlib?(mod, m) ->
        # A known Elixir-stdlib call with no portable prelude image — emit it as a
        # native remote call (BEAM FFI). It compiles and runs on BEAM, so the draft
        # is far less marker-ridden; it is *not* portable, so `Rian.Reach` pins the
        # function off `:rs`/`:js` (honestly reported, not hidden).
        "#{m}.#{fun}(#{arg_strs})"

      is_atom(mod) ->
        # An Erlang/atom-module call `:erlang.fun(…)` — valid Rian FFI (BEAM-only),
        # so emit it natively rather than flag it. `m` already carries the `:` prefix.
        "#{m}.#{fun}(#{arg_strs})"

      true ->
        ~s|TODO_PORT("remote/stdlib call: #{escape("#{m}.#{fun}(#{arg_strs})")}")|
    end
  end

  defp elixir_stdlib?({:__aliases__, _, _}, m), do: m in @elixir_stdlib
  defp elixir_stdlib?(_, _), do: false

  defp mod_str({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()
  defp mod_str(a) when is_atom(a), do: ":#{a}"
  defp mod_str(other), do: snippet(other)

  # An `{:__aliases__, …}` capitalized module that isn't Elixir stdlib — treated
  # as a sibling Rian module (its call has a direct Rian image).
  defp sibling_module?({:__aliases__, _, _}, m), do: m not in @elixir_stdlib
  defp sibling_module?(_, _), do: false

  # ── capture (`&…`) eta-expansion ──────────────────────────────────────────
  defp capture_params(n), do: Enum.map(1..n//1, &"p#{&1}")

  # highest `&N` placeholder index in a capture body (0 if none).
  defp max_placeholder({:&, _, [k]}) when is_integer(k), do: k
  defp max_placeholder(t) when is_tuple(t), do: t |> Tuple.to_list() |> max_placeholder()
  defp max_placeholder(l) when is_list(l), do: Enum.reduce(l, 0, &max(max_placeholder(&1), &2))
  defp max_placeholder(_), do: 0

  # substitute each `&N` placeholder with the var `pN`.
  defp subst_ph({:&, _, [k]}, ps) when is_integer(k),
    do: {String.to_atom(Enum.at(ps, k - 1)), [], nil}

  defp subst_ph(t, ps) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.map(&subst_ph(&1, ps)) |> List.to_tuple()

  defp subst_ph(l, ps) when is_list(l), do: Enum.map(l, &subst_ph(&1, ps))
  defp subst_ph(x, _), do: x

  # ── string interpolation segments ─────────────────────────────────────────
  # `{:ok, parts}` when every `<<>>` segment is a string literal or an interpolated
  # `::binary` segment; `:error` for a real binary construction.
  defp string_parts(segments) do
    Enum.reduce_while(segments, {:ok, []}, fn seg, {:ok, acc} ->
      case string_part(seg) do
        {:ok, s} -> {:cont, {:ok, acc ++ [s]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp string_part(s) when is_binary(s), do: {:ok, escape_lit(s)}
  defp string_part({:"::", _, [interp, {:binary, _, _}]}), do: {:ok, "${#{interp_inner(interp)}}"}
  defp string_part(_), do: :error

  # an interpolated hole is usually wrapped in `Kernel.to_string`/`to_string`; unwrap.
  defp interp_inner({{:., _, [_mod, :to_string]}, _, [e]}), do: expr(e)
  defp interp_inner({:to_string, _, [e]}), do: expr(e)
  defp interp_inner(e), do: expr(e)

  defp escape_lit(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  # case arm: `pat -> body` or `pat when guard -> body`.
  defp case_arm({:->, _, [[{:when, _, [p, g]}], body]}),
    do: "#{pat(p)} when #{expr(g)} -> #{render_body(body)}"

  defp case_arm({:->, _, [[p], body]}),
    do: "#{pat(p)} -> #{render_body(body)}"

  defp case_arm(other), do: "# TODO[port]: case arm #{snippet(other)}"

  # arity of one `fn` clause — a multi-arg guard is `[{:when, _, [p…, g]}]`, so the
  # arg count is one less than the `when` group; otherwise it is the arg-list length.
  defp fn_arity({:->, _, [[{:when, _, wargs}], _]}), do: length(wargs) - 1
  defp fn_arity({:->, _, [args, _]}), do: length(args)

  # rewrite a `fn` clause into an equivalent single-subject `case` arm: wrap the
  # clause's patterns into a tuple (when arity > 1) so they match the tupled params.
  defp fn_clause_to_arm({:->, m, [[{:when, wm, wargs}], body]}, n) do
    {pats, [guard]} = Enum.split(wargs, n)
    {:->, m, [[{:when, wm, [wrap_tuple(pats), guard]}], body]}
  end

  defp fn_clause_to_arm({:->, m, [pats, body]}, _n), do: {:->, m, [[wrap_tuple(pats)], body]}

  defp wrap_tuple([p]), do: p
  defp wrap_tuple(pats), do: {:{}, [], pats}

  # ── patterns ────────────────────────────────────────────────────────────────

  defp pat(n) when is_integer(n) or is_float(n), do: to_string(n)
  defp pat(s) when is_binary(s), do: ~s|"#{escape(s)}"|
  defp pat(true), do: "true"
  defp pat(false), do: "false"
  defp pat(a) when is_atom(a), do: ":#{a}"
  defp pat({l, r}), do: "{#{pat(l)}, #{pat(r)}}"
  defp pat({:{}, _, elems}), do: "{#{Enum.map_join(elems, ", ", &pat/1)}}"
  defp pat({:|, _, [h, t]}), do: "#{pat(h)} | #{pat(t)}"
  defp pat(list) when is_list(list), do: "[#{Enum.map_join(list, ", ", &pat/1)}]"

  # struct pattern `%Mod{f: p, …}` → Rian ctor pattern `Mod(f: p, …)`.
  defp pat({:%, _, [aliases, {:%{}, _, kvs}]}) do
    fields = Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{pat(v)}" end)
    "#{short_name(aliases)}(#{fields})"
  end

  # bare map pattern `%{k: p}` → Rian map pattern. Atom keys render bare (`k: p`),
  # mirroring the struct-pattern and `expr` map paths — `pat(:k)` would otherwise
  # prefix a stray colon (`:k: p`). Non-atom keys have no `key: value` spelling.
  defp pat({:%{}, _, kvs} = m) do
    if Enum.all?(kvs, &match?({k, _} when is_atom(k), &1)) do
      "%{#{Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{pat(v)}" end)}}"
    else
      ~s|TODO_PORT("map pattern #{escape(snippet(m))}")|
    end
  end

  # binding `_` and vars.
  defp pat({:_, _, ctx}) when is_atom(ctx), do: "_"
  defp pat({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: underscore_var(name)

  # as-pattern: Elixir `pat = var` (or `var = pat`) → Rian `var @ pat` (Core `PAs`),
  # binding the whole value while matching the pattern. Only a variable can be the
  # binder; two complex sides have no Rian image and stay a marker.
  defp pat({:=, _, [l, r]}) do
    cond do
      var?(r) -> "#{var_name(r)} @ #{pat(l)}"
      var?(l) -> "#{var_name(l)} @ #{pat(r)}"
      true -> ~s|TODO_PORT("as-pattern #{escape(snippet({:=, [], [l, r]}))}")|
    end
  end

  defp pat(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

  defp var?({n, _, ctx}) when is_atom(n) and is_atom(ctx), do: true
  defp var?(_), do: false

  defp underscore_var(name) do
    s = to_string(name)
    if String.starts_with?(s, "_"), do: "_", else: s
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp indent(line), do: if(line == "", do: "", else: "  " <> line)

  defp moduledoc_lines(text) do
    text
    |> one_line()
    |> then(&["# #{&1}"])
  end

  defp snippet(node), do: node |> Macro.to_string() |> one_line()
  defp one_line(s), do: s |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()
  defp escape(s), do: s |> to_string() |> String.replace("\"", "\\\"")
end
