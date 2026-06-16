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

    * forms with a clear Rian image are translated — `def`/`defp` clauses,
      `defstruct` (→ a `struct Mod(…)` record skeleton), nested `defmodule`s (a
      struct-only wrapper flattens to its `struct`, else nests as `mod`), `@type` (→
      a synthesized `type …` decl and/or resolved into `@spec`s), `if`/`case` (incl.
      `when` arms), binary/unary operators, ctor & struct patterns (`%ECall{fun: f}` →
      `ECall(fun: f)`), tuples, lists/cons, atoms, string/number literals, local calls;
    * everything else is left **in place** as a greppable `TODO_PORT("…")`
      sentinel (carrying the original Elixir) or a `# TODO[port]: …` line comment,
      so nothing untranslated can masquerade as done;
    * **types are holes** (`_Unk`) by default — Elixir is untyped, so the human
      supplies the sums and signatures. With `--infer` (ADR-0075) the engine fills
      every *provable* slot, **harvesting any `@spec`** as a cross-checked hint (a
      consumed `@spec` becomes a passive `# spec:` provenance line, not a TODO);
      whatever stays unproven remains an honest `_Unk` hole for the human.

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
    "#   ctor/struct patterns, tuples, lists, maps, atoms, literals, local/sibling calls,",
    "#   string interpolation (${e}), nil→None.",
    "# You must still: (1) fill type holes `_Unk`, (2) resolve every",
    "#   `TODO_PORT(...)` / `# TODO[port]` marker, (3) make matches exhaustive,",
    "#   (4) equiv-lock against the Elixir oracle with a fixpoint test.",
    "# Auto-mapped stdlib calls (List./Dict./Str.) are spelled inline but NOT",
    "#   semantics-verified — check arg-order/edge-cases against the Elixir source.",
    "# ─────────────────────────────────────────────────────────────────────────",
    ""
  ]

  # Elixir binary operators that map to a Rian infix spelling unchanged.
  @binops ~w(+ - * / <> ++ <= >= < > == != and or)a
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
    {"Integer", :to_string, 1} => {"Str", "from_int"}
  }

  # Elixir-stdlib modules with no (or only partial) Rian image — calls to these
  # stay markers unless individually `@stdlib`-mapped. Everything else capitalized
  # is assumed a sibling Rian module, whose `Mod.fun(args)` call is valid Rian and
  # is emitted inline (flagged for verification in the header, like `@stdlib`).
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
  """
  @spec transpile(String.t(), keyword()) :: term()
  def transpile(source, opts \\ []) when is_binary(source) do
    ast = Code.string_to_quoted!(source)
    {sigmap, types} = if opts[:infer], do: infer_program(ast), else: {%{}, []}

    ast
    |> toplevel(sigmap, types)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Phase B: assemble Result returns (`Payload | Errors`) and synthesize the
  # `type Errors := Tag | …` declaration from the error tags the inferer collected.
  # Phase C+: harvest `@type` decls — synthesize `type Name := …` and resolve local
  # type refs in `@spec`s (`type_env`).
  defp infer_program({:defmodule, _, [aliases, [do: body]]} = ast) do
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

  defp infer_program(_), do: {%{}, []}

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

  # ── whole-program type inference (ADR-0034-aligned hole filling) ────────────
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

  @doc """
  The inferred signature map `{name, arity} => sig` plus synthesized type decls
  for a source — the raw inference result the port-analysis report consumes.
  """
  @spec inferred(String.t()) :: term()
  def inferred(source) when is_binary(source) do
    infer_program(Code.string_to_quoted!(source))
  end

  @doc "The Elixir→Rian stdlib call-mapping table (for whole-program inference)."
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

  defp toplevel({:defmodule, _, [aliases, [do: body]]}, sigmap, types) do
    name = short_name(aliases)
    inner = body |> block_stmts() |> render_items(sigmap, name) |> Enum.map(&indent/1)
    # synthesized `type …` declarations (Phase B error sets) go after `mod … do`.
    type_lines = if types == [], do: [], else: Enum.map(types, &("  " <> &1)) ++ [""]
    @header ++ ["mod #{name} do" | type_lines ++ inner] ++ ["end"]
  end

  defp toplevel(other, _sigmap, _types) do
    @header ++ ["# TODO[port]: top-level is not a single `defmodule`", "# #{snippet(other)}"]
  end

  defp short_name({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()
  defp short_name(other), do: snippet(other)

  defp block_stmts({:__block__, _, stmts}), do: stmts
  defp block_stmts(single), do: [single]

  # ── declarations ────────────────────────────────────────────────────────────
  #
  # Walk the statement list, attaching a pending `@doc` to the next def, and
  # merging consecutive same-name/arity clauses into one rendered group.

  defp render_items(stmts, sigmap, mod_name) do
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
            {acc ++ flush(open, sigmap) ++ render_submodule(name, body, sigmap), doc, nil}

          {:defstruct, fields} ->
            # an Elixir `defstruct` IS the module's record type → a Rian `struct`
            # decl named for the module, fields as `_Unk` holes for a human to type.
            {acc ++ flush(open, sigmap) ++ [struct_decl(mod_name, fields)], doc, nil}

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

          {:other, node} ->
            {acc ++ flush(open, sigmap) ++ ["# TODO[port]: #{snippet(node)}"], doc, nil}
        end
      end)

    lines ++ flush(open, sigmap)
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

  defp classify({:defmodule, _, [{:__aliases__, _, _} = al, [do: body]]}),
    do: {:submodule, short_name(al), body}

  defp classify({:defstruct, _, [fields]} = n) when is_list(fields) do
    if Enum.all?(fields, &struct_field?/1), do: {:defstruct, fields}, else: {:other, n}
  end

  defp classify({:def, _, [head, kw]}), do: {:clause, :pub, head, kw}
  defp classify({:defp, _, [head, kw]}), do: {:clause, :priv, head, kw}
  defp classify(other), do: {:other, other}

  # render a nested `defmodule`: flatten a struct-only wrapper to its `struct` decl
  # (Elixir's one-struct-per-module idiom), else nest it as a `mod … do … end`.
  defp render_submodule(name, body, sigmap) do
    stmts = block_stmts(body)
    inner = render_items(stmts, sigmap, name)

    if struct_only_module?(stmts) do
      inner
    else
      ["mod #{name} do"] ++ Enum.map(inner, &indent/1) ++ ["end"]
    end
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

  # `defstruct [:x, y: 0]` → `struct Mod(x _Unk, y _Unk)` (defaults dropped — the
  # field NAMES port; their types and any default are for the human to fill).
  defp struct_decl(mod_name, fields) do
    names =
      Enum.map(fields, fn
        {k, _default} -> k
        k -> k
      end)

    "struct #{mod_name}(#{Enum.map_join(names, ", ", &"#{&1} _Unk")})"
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

    body_lines =
      if simple?(clauses) do
        [c] = clauses

        params =
          c.args
          |> Enum.zip(ptypes)
          |> Enum.map_join(", ", fn {a, t} -> "#{var_name(a)} #{t}" end)

        ["#{kw} #{name}(#{params}) #{ret}#{forall} := #{render_body(c.body)}"]
      else
        sig_line = "#{kw} #{name}(#{Enum.join(ptypes, ", ")}) #{ret}#{forall}"
        [sig_line | Enum.map(clauses, &render_clause(kw, &1))]
      end

    [""] ++ doc_lines ++ body_lines
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
    "#{kw} #{name_str(c.name)}(#{pats})#{guard} := #{render_body(c.body)}"
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
  # (ADR-0042). Multi-clause `fn` has no single-expression Rian image — flagged.
  defp expr({:fn, _, [{:->, _, [args, body]}]}) do
    params = Enum.map_join(args, ", ", &pat/1)
    "(#{params}) -> #{render_body(body)}"
  end

  defp expr({:fn, _, _} = n), do: ~s|TODO_PORT("multi-clause fn #{escape(snippet(n))}")|

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

  # remote call `Mod.fun(args)`: (1) auto-map to a Rian prelude call when the
  # image exists (`@stdlib`); (2) emit inline if `Mod` is a sibling Rian module
  # (a valid Rian cross-module call); (3) else flag — Elixir stdlib / atom module
  # / variable field-access (`r.name`) has no clean Rian image.
  defp expr({{:., _, [mod, fun]}, _, args}) when is_list(args) do
    arg_strs = Enum.map_join(args, ", ", &expr/1)
    m = mod_str(mod)

    cond do
      Map.has_key?(@stdlib, {m, fun, length(args)}) ->
        {rmod, rfun} = @stdlib[{m, fun, length(args)}]
        "#{rmod}.#{rfun}(#{arg_strs})"

      sibling_module?(mod, m) ->
        "#{m}.#{fun}(#{arg_strs})"

      true ->
        ~s|TODO_PORT("remote/stdlib call: #{escape("#{m}.#{fun}(#{arg_strs})")}")|
    end
  end

  # local call / nullary var reference.
  defp expr({name, _, args}) when is_atom(name) and is_list(args),
    do: "#{name}(#{Enum.map_join(args, ", ", &expr/1)})"

  defp expr({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: to_string(name)

  defp expr(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

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

  # bare map pattern `%{k: p}` → Rian map pattern.
  defp pat({:%{}, _, kvs}) do
    fields = Enum.map_join(kvs, ", ", fn {k, v} -> "#{pat(k)}: #{pat(v)}" end)
    "%{#{fields}}"
  end

  # binding `_` and vars.
  defp pat({:_, _, ctx}) when is_atom(ctx), do: "_"
  defp pat({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: underscore_var(name)

  # as-pattern `x = p` has no direct Rian image here.
  defp pat({:=, _, _} = node), do: ~s|TODO_PORT("as-pattern #{escape(snippet(node))}")|
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
