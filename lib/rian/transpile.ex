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
      flat), a **module-less** source — a bare sequence of top-level `def`s with no
      `defmodule` wrapper (the shape of the codegen fixtures and hand-written `.rian`
      files) — which renders flat, with no `mod … do` box, `@type`/`@typep` (→ a
      synthesized `type …` decl and/or resolved into `@spec`s), `if`/`case` (incl.
      `when` arms), binary/unary operators, ctor & struct patterns
      (`%ECall{fun: f}` → `ECall(fun: f)`), tuples, lists/cons, maps (atom **and**
      non-atom `=>` keys, ADR-0033), pins (`^x`), bitstrings, atoms, literals, calls,
      and **ExUnit test modules** — a `defmodule … use ExUnit.Case … test "…" do … end`
      flattens to module-less `@test def`s (ADR-0060: tests are top-level), with
      `assert`/`refute` rewritten to the assertion macros (`assert_eq`/`assert_neq` for
      `==`/`!=`) and a multi-assertion body `and`-combined; `Rian.Test` runs the result;
    * documentation / compile-metadata / conformance attributes with **no runtime
      semantics** are *dropped* (not flagged): `@typedoc`, `@doc false`, `@impl`,
      `@external_resource`, `@enforce_keys`, `@rian`/`use Rian.Ann` — emitting a
      `# TODO[port]` for these would falsely imply lost behaviour;
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
    "#   field access (r.f), string interpolation (${e}), nil→None,",
    "#   ExUnit `test` blocks → `@test def`, assert/refute → assertion macros.",
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
  defp toplevel({:defmodule, _, [_, [do: body]]} = top, sigmap, types, struct_anns) do
    # A **test module** (`use ExUnit.Case`, or `test`/`describe` blocks) carries no
    # Rian-meaningful name — `@test def`s are top-level (ADR-0060), where `Rian.Test`
    # discovers them and the injected assertion macros are in scope (both fail inside
    # a `mod`). So flatten it to module-less top-level rather than wrapping in `mod`.
    if test_module?(body) do
      @header ++ flat_items(body, sigmap, types, struct_anns)
    else
      [parent | hoisted] = flatten_modules(top)

      @header ++
        module_lines(parent, sigmap, types, struct_anns) ++
        Enum.flat_map(hoisted, &["" | module_lines(&1, sigmap, [], struct_anns)])
    end
  end

  # A **module-less** top level — Rian source needs no `defmodule` wrapper (the
  # codegen fixtures and hand-written `.rian` files are bare `def`s). Render the
  # declarations FLAT: no `mod … do` box, no indentation, just the decls a finished
  # `.rian` would carry. Each statement without a Rian image still drops to its own
  # greppable `TODO[port]` marker via `render_items`, so a non-declaration script
  # degrades per-statement rather than collapsing into one opaque blob.
  defp toplevel(other, sigmap, types, struct_anns) do
    @header ++ flat_items(other, sigmap, types, struct_anns)
  end

  # Render a statement-carrying node's declarations flat (no `mod` wrapper).
  defp flat_items(node, sigmap, types, struct_anns) do
    type_lines = if types == [], do: [], else: types ++ [""]

    type_lines ++
      render_items(block_stmts(node), sigmap, nil, struct_anns, referenced_attrs(node))
  end

  # An ExUnit test module: `use ExUnit.Case`, or any `test`/`describe` block.
  defp test_module?(body) do
    Enum.any?(block_stmts(body), fn
      {:use, _, [{:__aliases__, _, [:ExUnit, :Case]} | _]} -> true
      {:test, _, _} -> true
      {:describe, _, _} -> true
      _ -> false
    end)
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
      |> Enum.flat_map(&expand_defaults/1)
      |> render_items(sigmap, name, struct_anns, referenced)
      |> Enum.map(&indent/1)

    # synthesized `type …` declarations (Phase B error sets, `@rian type`) after `mod … do`.
    type_lines = if types == [], do: [], else: Enum.map(types, &("  " <> &1)) ++ [""]
    ["mod #{name} do" | type_lines ++ inner] ++ ["end"]
  end

  # Rian has no default arguments, so a `def f(a, opts \\ [])` expands into a real
  # clause `def f(a, opts) := body` plus one delegating clause per trailing default
  # (`def f(a) := f(a, [])`) — the same desugaring Elixir performs. Only expanded
  # when every parameter is a plain variable (so forwarding by name is sound);
  # otherwise the defaults are stripped to a single clause.
  defp expand_defaults({df, m, [{name, hm, params}, kw]})
       when df in [:def, :defp] and is_atom(name) and is_list(params) and
              kw != [] do
    defaulted = Enum.count(params, &match?({:\\, _, _}, &1))
    plain = Enum.map(params, &strip_default/1)

    cond do
      defaulted == 0 ->
        [{df, m, [{name, hm, params}, kw]}]

      Enum.all?(plain, &var?/1) ->
        n = length(params)

        delegators =
          for keep <- (n - defaulted)..(n - 1) do
            taken = Enum.take(plain, keep)
            call_args = taken ++ Enum.map(Enum.drop(params, keep), fn {:\\, _, [_, d]} -> d end)
            {df, m, [{name, hm, taken}, [do: {name, [], call_args}]]}
          end

        delegators ++ [{df, m, [{name, hm, plain}, kw]}]

      true ->
        [{df, m, [{name, hm, plain}, kw]}]
    end
  end

  # a *bodyless* default-declaring head `def f(a, b \\ d)` (Elixir requires the
  # defaults to live on a bodyless head when the function has multiple clauses). It
  # declares defaults for the real clauses that follow, so desugar to the delegating
  # clauses only and DROP the head — the following clauses carry the top-arity body.
  defp expand_defaults({df, m, [{name, hm, params}]})
       when df in [:def, :defp] and is_atom(name) and is_list(params) do
    defaulted = Enum.count(params, &match?({:\\, _, _}, &1))
    plain = Enum.map(params, &strip_default/1)

    if defaulted > 0 and Enum.all?(plain, &var?/1) do
      n = length(params)

      for keep <- (n - defaulted)..(n - 1) do
        taken = Enum.take(plain, keep)
        call_args = taken ++ Enum.map(Enum.drop(params, keep), fn {:\\, _, [_, d]} -> d end)
        {df, m, [{name, hm, taken}, [do: {name, [], call_args}]]}
      end
    else
      [{df, m, [{name, hm, params}]}]
    end
  end

  defp expand_defaults(stmt), do: [stmt]

  defp strip_default({:\\, _, [p, _]}), do: p
  defp strip_default(p), do: p

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
  defp infer_program({:defmodule, _, [aliases, [do: body]]}),
    do: infer_program_stmts(block_stmts(body), short_name(aliases))

  # Module-less source: infer over the bare top-level statement list. There is no
  # enclosing module to qualify `t()`/`%__MODULE__{}` self-refs against, so the
  # module name is `nil` (such self-refs cannot occur outside a `defmodule`).
  defp infer_program(other), do: infer_program_stmts(block_stmts(other), nil)

  defp infer_program_stmts(stmts, mod_name) do
    {type_env, type_decls} = Rian.Transpile.Infer.collect_types(stmts, mod_name)
    sigmap = infer_sigs(stmts, type_env)

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
    # Count over the BODY, never the fixed DRAFT header: that header documents
    # `TODO_PORT`/`# TODO[port]`/`_Unk` by name, so counting the whole text would
    # inflate every module's marker and hole tally by the header's self-reference.
    body = text |> String.split("\n") |> Enum.drop(length(@header))

    ports =
      Enum.count(
        body,
        &(String.contains?(&1, "TODO_PORT") or String.contains?(&1, "TODO[port]"))
      )

    # def heads — indented (inside a `mod`) or at column 0 (module-less source).
    defs = Enum.count(body, &Regex.match?(~r/^\s*(pub )?def \w+\(/, &1))
    # auto-mapped stdlib calls (A1) — resolved inline, but flagged for a semantics
    # check; counted (occurrences, not lines) so the report can surface them.
    mapped = Regex.scan(~r/\b(?:List|Dict|Str|Int)\.[a-z_]+\(/, Enum.join(body, "\n")) |> length()
    # holes are counted over the code only — comment provenance lines are dropped.
    code =
      body |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#")) |> Enum.join("\n")

    holes = Regex.scan(~r/\b_Unk\b/, code) |> length()
    {text, %{ports: ports, defs: defs, mapped: mapped, holes: holes}}
  end

  # ── type inference (ADR-0034-aligned hole filling) ─────────────────────────
  # Two passes: pass 1 infers each def group in isolation; pass 2 re-infers with
  # the fully-resolved sigs as an intra-module sibling table (so a local call can
  # adopt a callee's inferred type). Returns `{name, arity} => %{params, ret, tvars}`.
  defp infer_sigs(stmts, type_env \\ %{})

  defp infer_sigs(stmts, type_env) when is_list(stmts) do
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
    stmts = source |> Code.string_to_quoted!() |> toplevel_stmts()
    for {k, v} <- infer_sigs(stmts), v.ledger != [], do: {k, v.ledger}
  end

  # The top-level statement list, whether the source is a `defmodule` (its body) or
  # a module-less bare-`def` sequence (the forms themselves).
  defp toplevel_stmts({:defmodule, _, [_, [do: body]]}), do: block_stmts(body)
  defp toplevel_stmts(other), do: block_stmts(other)

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

          {:test, name, body} ->
            {acc ++ flush(open, sigmap) ++ test_def(name, body, ""), doc, nil}

          {:describe, name, body} ->
            {acc ++ flush(open, sigmap) ++ render_describe(name, body), doc, nil}

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
  # `@typep` is a *private* `@type` — harvest it the same way (provenance + a type
  # the inference can resolve in a local `@spec`), never a port marker.
  defp classify({:@, _, [{:typep, _, _}]} = n), do: {:type_decl, n}
  # Documentation / compile-metadata / behaviour-conformance attributes carry **no
  # runtime semantics**, so they are dropped, not flagged: `@typedoc`/`@doc false`
  # (doc strings; a *non-`false`* `@doc "…"` is attached to the next def above),
  # `@impl` (a compile-time callback assertion), `@external_resource` (a recompile
  # trigger). Flagging these as `# TODO[port]` would falsely imply lost behaviour.
  defp classify({:@, _, [{:typedoc, _, _}]}), do: :skip
  defp classify({:@, _, [{:doc, _, _}]}), do: :skip
  defp classify({:@, _, [{:impl, _, _}]}), do: :skip
  defp classify({:@, _, [{:external_resource, _, _}]}), do: :skip
  # `@enforce_keys` is an Elixir runtime concern subsumed by Rian's typed fields.
  defp classify({:@, _, [{:enforce_keys, _, _}]}), do: :skip
  # `@rian` annotations are HARVESTED into the signatures/struct/type decls; the
  # `use Rian.Ann` directive is annotation support — both are consumed, not ported.
  defp classify({:@, _, [{:rian, _, _}]}), do: :skip
  defp classify({:use, _, [{:__aliases__, _, [:Rian, :Ann]}]}), do: :skip
  # `use ExUnit.Case` (with or without options) is test-framework scaffolding with
  # no Rian analog — `@test def` is the whole surface (ADR-0060). Drop it silently.
  defp classify({:use, _, [{:__aliases__, _, [:ExUnit, :Case]} | _]}), do: :skip

  defp classify({:defmodule, _, [{:__aliases__, _, _} = al, [do: body]]}),
    do: {:submodule, short_name(al), body}

  defp classify({:defstruct, _, [fields]} = n) when is_list(fields) do
    if Enum.all?(fields, &struct_field?/1), do: {:defstruct, fields}, else: {:other, n}
  end

  defp classify({:def, _, [head, kw]}), do: {:clause, :pub, head, kw}
  defp classify({:defp, _, [head, kw]}), do: {:clause, :priv, head, kw}

  # ExUnit `test "name" do … end` (or `test "name", ctx do … end`) → a Rian
  # `@test def` (ADR-0060). Only a literal-string name ports to a function name; a
  # dynamic/interpolated name falls through to a marker. The setup `ctx` argument is
  # dropped (Rian has no per-test fixture context). `describe` is handled separately.
  defp classify({:test, _, [name, [do: body]]}) when is_binary(name), do: {:test, name, body}

  defp classify({:test, _, [name, _ctx, [do: body]]}) when is_binary(name),
    do: {:test, name, body}

  # ExUnit `describe "group" do … end` — Rian tests are flat (no nesting), so the
  # group flattens to its inner `@test def`s with a `group_`-prefixed name (avoiding
  # collisions across groups). `setup` blocks inside have no Rian image (markers).
  defp classify({:describe, _, [name, [do: body]]}) when is_binary(name),
    do: {:describe, name, body}

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

  # ── ExUnit test blocks (ADR-0060) ─────────────────────────────────────────
  #
  # `test "name" do … end` → `@test def slug() Bool := …`. The assertion macros
  # (`assert`/`refute`/`assert_eq`/`assert_neq`) are injected by `Rian.Test`, so the
  # body needs only the call sites. ExUnit runs every assertion; a Rian `@test def`
  # returns ONE `Bool`, so the assertions are `and`-combined as the return value and
  # any non-assertion statements (binds, setup calls) become the block preamble —
  # sound because assertions are side-effect-free values that don't feed the binds.
  defp test_def(name, body, prefix) do
    slug = prefix <> test_slug(name)

    case render_test_body(body) do
      {:inline, expr} ->
        ["", "@test def #{slug}() Bool := #{expr}"]

      {:block, lines} ->
        ["", "@test def #{slug}() Bool do"] ++ Enum.map(lines, &("  " <> &1)) ++ ["end"]
    end
  end

  # `describe "group" do … end` → its inner `@test def`s, each slug prefixed with
  # the group (Rian has no test nesting, ADR-0060). A `setup`/`setup_all` block (or
  # any other non-test statement) has no Rian image and stays a greppable marker.
  defp render_describe(name, body) do
    prefix = test_slug(name) <> "_"

    body
    |> block_stmts()
    |> Enum.flat_map(fn stmt ->
      case classify(stmt) do
        {:test, tname, tbody} -> test_def(tname, tbody, prefix)
        :skip -> []
        _ -> ["", "# TODO[port]: #{snippet(stmt)}"]
      end
    end)
  end

  defp render_test_body(body) do
    stmts =
      case body do
        {:__block__, _, ss} -> ss
        one -> [one]
      end

    {asserts, preamble} = Enum.split_with(stmts, &assertion?/1)

    cond do
      # No ExUnit assertion to anchor the `Bool` — best-effort render the body; the
      # human supplies the missing check (the draft won't type-check until then).
      asserts == [] -> {:inline, render_body(body)}
      preamble == [] -> {:inline, Enum.map_join(asserts, " and ", &expr/1)}
      true -> {:block, Enum.map(preamble, &stmt/1) ++ [Enum.map_join(asserts, " and ", &expr/1)]}
    end
  end

  defp assertion?({:assert, _, _}), do: true
  defp assertion?({:refute, _, _}), do: true
  defp assertion?(_), do: false

  # A match assertion `assert pat = rhs` → `case rhs do pat -> <on_match>; _ ->
  # <on_miss> end`, the Bool of "did `rhs` match `pat`?" (refute flips the arms).
  defp match_check(lhs, rhs, on_match, on_miss) do
    "case #{expr(rhs)} do\n" <>
      indent("#{pat(lhs)} -> #{on_match}") <>
      "\n" <> indent("_ -> #{on_miss}") <> "\nend"
  end

  # A test name → a valid Rian identifier: lowercase, non-alphanumerics collapsed to
  # `_`, and a leading non-letter prefixed (Rian identifiers start with a letter).
  defp test_slug(name) do
    slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")

    cond do
      slug == "" -> "test"
      String.match?(slug, ~r/^[a-z]/) -> slug
      true -> "t_" <> slug
    end
  end

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
      {:ok, parts} ->
        ~s|"#{Enum.join(parts)}"|

      :error ->
        # a genuine bitstring (sizes/`::utf8`/`::binary`, ADR-0078) → Rian `<<…>>`;
        # an unsupported segment/specifier falls back to a marker (no broken output).
        bitstr_text(segments, &expr/1) ||
          ~s|TODO_PORT("binary construction #{escape(snippet(n))}")|
    end
  end

  # 2-tuples are genuine Elixir tuples in quoted form; n-tuples are {:{}, _, _}.
  defp expr({l, r}), do: "{#{expr(l)}, #{expr(r)}}"
  defp expr({:{}, _, elems}), do: "{#{Enum.map_join(elems, ", ", &expr/1)}}"

  # struct construction `%Mod{f: e, …}` → Rian ctor call `Mod(f: e, …)` (the
  # expression-side dual of the struct *pattern* clause below). Must precede the
  # generic local-call clause, else `{:%, _, [aliases, map]}` is mistaken for a
  # 2-arg call named `:%` and emits a malformed `%(__aliases__(...), …)`.
  # struct update `%Mod{base | f: v}` → Rian map update `%{base | f: v}` (ADR-0033):
  # a Rian struct value IS a tagged map (ADR-0043), so updating its fields is the
  # BEAM exact-assoc — which preserves the value's `__struct__` tag. The nominal
  # `%Mod{}` re-assertion is dropped (Rian has no struct-update surface; the tagged
  # map carries the type). Atom keys only; otherwise flag it.
  defp expr({:%, _, [_aliases, {:%{}, _, [{:|, _, [base, kvs]}]}]} = n) when is_list(kvs) do
    if Enum.all?(kvs, &match?({k, _} when is_atom(k), &1)) do
      fields = Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{expr(v)}" end)
      "%{#{expr(base)} | #{fields}}"
    else
      ~s|TODO_PORT("struct update #{escape(snippet(n))}")|
    end
  end

  defp expr({:%, _, [aliases, {:%{}, _, kvs}]}) do
    fields = Enum.map_join(kvs, ", ", fn {k, v} -> "#{k}: #{expr(v)}" end)
    "#{short_name(aliases)}(#{fields})"
  end

  # map *update* `%{base | k: v}` → Rian `%{base | k: v}` (ADR-0033): same surface,
  # the BEAM exact-assoc replacement of present keys. Atom keys render `k: v`; a
  # non-atom key renders `keyExpr => v` (ADR-0033 non-atom keys).
  defp expr({:%{}, _, [{:|, _, [base, kvs]}]}) when is_list(kvs) do
    "%{#{expr(base)} | #{Enum.map_join(kvs, ", ", &map_pair_rian/1)}}"
  end

  # map literal `%{k: v}` / `%{key => v}` → Rian map literal (ADR-0033): atom keys
  # render `k: v`, non-atom keys render `keyExpr => v`.
  defp expr({:%{}, _, kvs}) do
    "%{#{Enum.map_join(kvs, ", ", &map_pair_rian/1)}}"
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

  # a comprehension `for clauses…, <tail>` (ADR-0079). Generators bind a full pattern
  # (a non-match skips the element). The trailing keyword selects the shape:
  #   `do:`            → a list comprehension (the surface `for … do … end`);
  #   `into:` + `do:`  → fold the list into a collection (`List.reduce` + insert);
  #   `reduce:` + `do:`→ fold the loop into an accumulator (nested `List.reduce`).
  # `into:`/`:reduce` desugar to **portable prelude folds** — no Rian surface, and
  # Reach inherits any blocker from the insert op (`Dict.put` pins a map off `:rs`/`:jvm`).
  # A binary generator (`<<b <- bin>>`), an unrecognized `into:` target, or any extra
  # option (`uniq:`, …) stays an honest marker.
  defp expr({:for, _, args} = n) when is_list(args) and args != [] do
    # options (`do:`/`into:`/`reduce:`/…) are keyword-list args — separate them from the
    # generator/filter clauses (`do … end` vs `, do:` splits `reduce:` into its own arg).
    {opt_args, clauses} = Enum.split_with(args, &(is_list(&1) and Keyword.keyword?(&1)))
    opts = Enum.concat(opt_args)

    cond do
      clauses == [] or has_binary_generator?(clauses) ->
        for_marker(n)

      Enum.sort(Keyword.keys(opts)) == [:do] ->
        "for #{for_clauses_text(clauses)} do #{render_body(opts[:do])} end"

      Enum.sort(Keyword.keys(opts)) == [:do, :into] ->
        into_fold(clauses, opts[:into], opts[:do], n)

      Enum.sort(Keyword.keys(opts)) == [:do, :reduce] ->
        reduce_for(clauses, expr(opts[:reduce]), opts[:do], 0)

      true ->
        for_marker(n)
    end
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

  # ExUnit assertions → the Rian assertion-macro vocabulary (ADR-0060): `assert a
  # == b` / `refute a == b` specialize to `assert_eq` / `assert_neq`; the bare forms
  # map to `assert` / `refute`. A custom failure message (2nd arg) is dropped — the
  # Bool test model can't carry it until `Test.Outcome` lands (ADR-0060 §2); the
  # assertion itself ports. `assert_raise` and kin are exception-based (ADR-0035 has
  # no exceptions), so they have no Rian image and stay a greppable marker.
  #
  # A MATCH assertion `assert pat = expr` (and `refute pat = expr`) ports to a
  # `case` on the truth of the match — the Bool the test model wants. Variables the
  # pattern binds are scoped to the arm, so they are NOT threaded to sibling
  # assertions (Rian has no refutable block bind); a test that reuses a matched
  # binding is a draft the human finishes. This is far better than the old
  # `assert(pat := expr)` (a bind, not a `Bool`).
  defp expr({:assert, _, [{:=, _, [lhs, rhs]} | _]}), do: match_check(lhs, rhs, "true", "false")
  defp expr({:refute, _, [{:=, _, [lhs, rhs]} | _]}), do: match_check(lhs, rhs, "false", "true")
  defp expr({:assert, _, [{:==, _, [l, r]} | _]}), do: "assert_eq(#{expr(l)}, #{expr(r)})"
  defp expr({:assert, _, [{:!=, _, [l, r]} | _]}), do: "assert_neq(#{expr(l)}, #{expr(r)})"
  defp expr({:assert, _, [e | _]}), do: "assert(#{expr(e)})"
  defp expr({:refute, _, [{:==, _, [l, r]} | _]}), do: "assert_neq(#{expr(l)}, #{expr(r)})"
  defp expr({:refute, _, [{:!=, _, [l, r]} | _]}), do: "assert_eq(#{expr(l)}, #{expr(r)})"
  defp expr({:refute, _, [e | _]}), do: "refute(#{expr(e)})"

  defp expr({raise_assert, _, _} = n)
       when raise_assert in [:assert_raise, :assert_receive, :assert_received, :catch_throw],
       do: ~s|TODO_PORT(#{inspect(snippet(n))})|

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

  # bare map pattern `%{k: p}` / `%{key => p}` → Rian map pattern (ADR-0033). Atom
  # keys render bare (`k: p`); a non-atom key renders `keyExpr => p` (the key is a
  # *value* looked up in the map, so it lowers via `expr`, the value via `pat`).
  defp pat({:%{}, _, kvs}) do
    "%{#{Enum.map_join(kvs, ", ", &map_pat_pair_rian/1)}}"
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

  defp pat({:<<>>, _, segments} = n),
    do: bitstr_text(segments, &pat/1) || ~s|TODO_PORT(#{inspect(snippet(n))})|

  # a string-prefix match `"pre" <> rest` is sugar for the bitstring pattern
  # `<<"pre", rest::binary>>` (ADR-0078); flatten a `<>`-chain of literal prefixes
  # ending in a binder. A non-literal/non-binder shape falls back to a marker.
  defp pat({:<>, _, _} = n) do
    case concat_pat_segs(n) do
      nil -> ~s|TODO_PORT(#{inspect(snippet(n))})|
      segs -> "<<#{Enum.join(segs, ", ")}>>"
    end
  end

  # a pin `^x` (Elixir `{:^, _, [expr]}`) → Rian `^expr` (ADR-0050): match the value
  # of an already-bound expression rather than binding a fresh var.
  defp pat({:^, _, [e]}), do: "^#{expr(e)}"

  defp pat(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

  # one Rian map pair (expression position): an atom Elixir key → the `k: v`
  # shorthand; any other key (string/module/tuple/var) → `keyExpr => v` (ADR-0033).
  defp map_pair_rian({k, v}) when is_atom(k), do: "#{k}: #{expr(v)}"
  defp map_pair_rian({k, v}), do: "#{expr(k)} => #{expr(v)}"

  # one Rian map *pattern* pair: the key is a value (lowered via `expr`), the value a
  # sub-pattern (via `pat`). Atom key → `k: p`; non-atom key → `keyExpr => p`.
  defp map_pat_pair_rian({k, p}) when is_atom(k), do: "#{k}: #{pat(p)}"
  defp map_pat_pair_rian({k, p}), do: "#{expr(k)} => #{pat(p)}"

  # a comprehension clause (ADR-0079): a generator `pat <- src` (any pattern — a
  # non-match skips the element) or a boolean filter.
  defp for_clause_rian({:<-, _, [lhs, src]}), do: "#{pat(lhs)} <- #{expr(src)}"
  defp for_clause_rian(filter), do: expr(filter)

  defp for_clauses_text(clauses), do: Enum.map_join(clauses, ", ", &for_clause_rian/1)

  defp for_marker(n), do: ~s|TODO_PORT("for comprehension #{escape(snippet(n))}")|

  # a binary generator `<<b <- bin>>` (Elixir `{:<<>>, _, …}`) has no list-comprehension
  # image yet (ADR-0079) — it stays a marker rather than mis-rendering as a filter.
  defp has_binary_generator?(clauses), do: Enum.any?(clauses, &match?({:<<>>, _, _}, &1))

  # `for …, into: c, do: body` → build the list comprehension, then fold it into the
  # target with a *named prelude op* so Reach inherits the blocker (ADR-0079/ADR-0000):
  #   into: ""  → left-fold with `<>`        (String — portable, all targets)
  #   into: %{} → fold with `Dict.put`       (Map — pins off `:rs`/`:jvm`)
  #   into: []  → identity (the list itself)
  # Any other collectable (a struct, `Map.new`, a variable) stays a marker.
  defp into_fold(clauses, into_ast, body, n) do
    listcomp = "for #{for_clauses_text(clauses)} do #{render_body(body)} end"

    case into_ast do
      "" ->
        # NOTE: a left-fold `<>` is O(n²) on immutable strings — acceptable for a
        # reviewed migration draft; a future builder/iolist prelude is the fast path.
        "List.reduce(#{listcomp}, \"\", (__e, __acc) -> __acc <> __e)"

      {:%{}, _, []} ->
        "List.reduce(#{listcomp}, %{}, (__e, __acc) -> case __e do {__k, __v} -> Dict.put(__acc, __k, __v) end)"

      [] ->
        listcomp

      _ ->
        for_marker(n)
    end
  end

  # `for …, reduce: acc do acc_pat -> e … end` → a *nested* `List.reduce` that threads
  # the accumulator through each generator (filters pass it through unchanged), with the
  # reduce-arms applied at the leaf. `__accᵢ` is depth-fresh to avoid shadowing.
  defp reduce_for([], acc_text, arms, _depth) when is_list(arms) do
    rendered = Enum.map_join(arms, "\n", &indent(case_arm(&1)))
    "case #{acc_text} do\n#{rendered}\nend"
  end

  defp reduce_for([{:<-, _, [pat, src]} | rest], acc_text, arms, depth) do
    a = "__acc#{depth}"

    "List.reduce(#{expr(src)}, #{acc_text}, (#{pat(pat)}, #{a}) -> #{reduce_for(rest, a, arms, depth + 1)})"
  end

  defp reduce_for([filter | rest], acc_text, arms, depth) do
    "if #{expr(filter)} do #{reduce_for(rest, acc_text, arms, depth)} else #{acc_text} end"
  end

  # `"a" <> "b" <> rest` → `["a"`, `"b"`, `rest::binary"]` segment texts; nil if the
  # tail isn't a literal or a bare binder.
  defp concat_pat_segs({:<>, _, [prefix, rest]}) when is_binary(prefix) do
    case concat_pat_segs(rest) do
      nil -> nil
      segs -> [inspect(prefix) | segs]
    end
  end

  defp concat_pat_segs(bin) when is_binary(bin), do: [inspect(bin)]

  defp concat_pat_segs({name, _, ctx}) when is_atom(name) and is_atom(ctx),
    do: ["#{pat({name, [], ctx})}::binary"]

  defp concat_pat_segs(_), do: nil

  # ── bitstrings (ADR-0078) ──────────────────────────────────────────────
  # Render an Elixir `<<>>` segment list to Rian `<<seg::spec, …>>` text, reused for
  # construction (`value_fun = expr/1`) and patterns (`pat/1`). Returns `nil` if any
  # segment/specifier is outside the supported subset, so the caller emits a marker
  # rather than broken Rian. The accepted specifiers mirror `Rian.Beam`.
  @bit_specs ~w(integer float binary bytes bitstring bits utf8 utf16 utf32 signed unsigned big little native)a

  defp bitstr_text(segments, value_fun) do
    rendered = Enum.map(segments, &bitseg_text(&1, value_fun))
    if Enum.all?(rendered, &(&1 != nil)), do: "<<#{Enum.join(rendered, ", ")}>>"
  end

  defp bitseg_text({:"::", _, [value, spec]}, value_fun) do
    case bitspec_text(spec) do
      nil -> nil
      s -> "#{value_fun.(value)}::#{s}"
    end
  end

  defp bitseg_text(value, value_fun) when is_integer(value) or is_binary(value),
    do: value_fun.(value)

  defp bitseg_text({_, _, ctx} = value, value_fun) when is_atom(ctx), do: value_fun.(value)
  defp bitseg_text(_, _), do: nil

  defp bitspec_text({:-, _, [a, b]}) do
    sa = bitspec_text(a)
    sb = bitspec_text(b)
    if sa && sb, do: "#{sa}-#{sb}"
  end

  defp bitspec_text(n) when is_integer(n), do: "#{n}"
  defp bitspec_text({:size, _, [n]}) when is_integer(n), do: "size(#{n})"
  defp bitspec_text({:unit, _, [n]}) when is_integer(n), do: "unit(#{n})"

  defp bitspec_text({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name in @bit_specs,
    do: "#{name}"

  defp bitspec_text(_), do: nil

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
