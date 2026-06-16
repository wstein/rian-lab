defmodule Rian.PortAnalysis do
  @moduledoc """
  **Read-only** Elixir→Rian port-analysis (ADR-0075, the agreed first increment).
  Generates a reviewable `PORT.analysis.md` for one or more Elixir sources, covering
  what the transpiler/inference already knows plus the *human-judgment* decisions a
  port needs but inference cannot make safely:

    1. inferred signatures (auto, high-confidence) with target reach;
    2. type holes with the reason each was left (the inference ledger);
    3. **proposed sum-type groupings** — structs clustered by co-occurrence in
       dispatch (multi-clause heads + `case` arms), the non-local decision a human
       can't see while editing one draft at a time;
    4. **error-idiom inventory** — every distinct `{:error, X}` shape with a
       proposed-but-blank Rian variant for the human to decide.

  It produces NO fills and feeds nothing back yet — it is the artifact a human
  reviews. Generated, so it stays diffable against the source (anti-drift).
  """

  alias Rian.Transpile

  @doc "Analyze `[{filename, source}]` into report data."
  def analyze(sources) when is_list(sources) do
    asts =
      for {file, src} <- sources, ast = parse(src), ast != nil, do: {file, ast}

    sums = cluster_sums(Enum.flat_map(asts, fn {_, ast} -> dispatch_sets(ast) end))

    # whole-program inference: shared sig variables linked across the call graph,
    # structs resolved to their proposed sum, residual unknowns named `Unk####`.
    mods_groups = Enum.map(asts, fn {_, ast} -> {module_name(ast), collect_groups(ast)} end)

    %{
      modules:
        Enum.map(asts, fn {file, ast} -> module_report(file, ast, src_of(sources, file)) end),
      sums: sums,
      structs: Enum.reduce(asts, %{}, fn {_, ast}, acc -> collect_structs(ast, acc) end),
      errors: Enum.reduce(asts, %{}, fn {_, ast}, acc -> collect_errors(ast, acc) end),
      wp: Rian.Transpile.Infer.whole_program(mods_groups, Rian.Transpile.stdlib_map(), sums),
      names: param_name_index(mods_groups)
    }
  end

  # def groups per module (for whole-program inference). Non-`defmodule` or
  # unusual top-levels (defprotocol/defimpl/multi-module) contribute no groups.
  defp collect_groups({:defmodule, _, [_, [do: body]]}) do
    stmts =
      case body do
        {:__block__, _, s} -> s
        s -> [s]
      end

    stmts
    |> Enum.flat_map(fn
      {d, _, [head, kw]} when d in [:def, :defp] ->
        call =
          case head do
            {:when, _, [c, _]} -> c
            c -> c
          end

        {name, args} =
          case call do
            {n, _, a} when is_atom(n) and is_list(a) -> {n, a}
            {n, _, _} when is_atom(n) -> {n, []}
          end

        [
          %{
            name: name,
            arity: length(args),
            args: args,
            guard: nil,
            body: kw && Keyword.get(kw, :do)
          }
        ]

      _ ->
        []
    end)
    |> Enum.group_by(&{&1.name, &1.arity})
    |> Enum.map(fn {_, clauses} -> %{clauses: clauses} end)
  end

  defp collect_groups(_), do: []

  # `{module, fn, arity} => [param name]` (first clause's heads, for the decl).
  defp param_name_index(mods_groups) do
    for {mod, groups} <- mods_groups, g <- groups, into: %{} do
      c = hd(g.clauses)

      names =
        c.args
        |> Enum.with_index()
        |> Enum.map(fn
          {{n, _, ctx}, _} when is_atom(n) and is_atom(ctx) -> to_string(n)
          {_, i} -> "p#{i}"
        end)

      {{mod, to_string(c.name), c.arity}, names}
    end
  end

  defp src_of(sources, file), do: Enum.find_value(sources, fn {f, s} -> if f == file, do: s end)

  defp parse(src) do
    case Code.string_to_quoted(src) do
      {:ok, ast} -> ast
      _ -> nil
    end
  end

  # ── per-module inference summary (reuses the transpiler's inference) ────────

  defp module_report(file, ast, src) do
    {sigmap, _types} = Transpile.inferred(src)
    name = module_name(ast)

    {filled, holes} =
      Enum.reduce(sigmap, {[], []}, fn {{n, ar}, sig}, {f, h} ->
        if sig.ledger == [] do
          {[{n, ar, sig} | f], h}
        else
          {f, [{n, ar, sig.ledger} | h]}
        end
      end)

    total_slots = Enum.sum(for {{_, ar}, _} <- sigmap, do: ar + 1)
    hole_slots = Enum.sum(for {_, _, ledger} <- holes, do: length(ledger))

    %{
      file: file,
      module: name,
      filled: Enum.sort(filled),
      holes: Enum.sort(holes),
      total_slots: total_slots,
      filled_slots: total_slots - hole_slots
    }
  end

  # ── sum-type clustering: structs that co-occur in dispatch ──────────────────

  # connected components over the co-occurrence sets (union-find by merging).
  defp cluster_sums(sets) do
    sets
    |> Enum.reduce([], fn set, comps ->
      {touching, rest} = Enum.split_with(comps, &(not MapSet.disjoint?(&1, set)))
      merged = Enum.reduce(touching, set, &MapSet.union/2)
      [merged | rest]
    end)
    |> Enum.map(&MapSet.to_list/1)
    |> Enum.map(&Enum.sort/1)
    |> Enum.sort_by(&(-length(&1)))
  end

  # every dispatch site → the set of struct names it discriminates (size >= 2).
  defp dispatch_sets(ast) do
    func_sets = clause_head_sets(ast)
    case_sets = case_arm_sets(ast)
    (func_sets ++ case_sets) |> Enum.filter(&(MapSet.size(&1) >= 2))
  end

  # structs matched across a multi-clause function's heads (same name) co-occur.
  defp clause_head_sets(ast) do
    {_, by_name} =
      Macro.prewalk(ast, %{}, fn
        {d, _, [head, _]} = node, acc when d in [:def, :defp] ->
          {name, pats} = head_name_pats(head)
          structs = pats |> Enum.flat_map(&pattern_structs/1) |> MapSet.new()
          {node, Map.update(acc, name, structs, &MapSet.union(&1, structs))}

        node, acc ->
          {node, acc}
      end)

    Map.values(by_name)
  end

  defp case_arm_sets(ast) do
    {_, sets} =
      Macro.prewalk(ast, [], fn
        {:case, _, [_, [do: arms]]} = node, acc ->
          structs =
            arms
            |> Enum.flat_map(fn
              {:->, _, [[p | _], _]} -> pattern_structs(p)
              _ -> []
            end)
            |> MapSet.new()

          {node, [structs | acc]}

        node, acc ->
          {node, acc}
      end)

    sets
  end

  defp head_name_pats({:when, _, [call, _]}), do: head_name_pats(call)
  defp head_name_pats({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp head_name_pats({name, _, _}) when is_atom(name), do: {name, []}

  # struct names mentioned in a pattern (`%Mod{…}`)
  defp pattern_structs({:%, _, [{:__aliases__, _, parts}, _]}),
    do: [List.last(parts) |> to_string()]

  defp pattern_structs({:=, _, [l, r]}), do: pattern_structs(l) ++ pattern_structs(r)
  defp pattern_structs(_), do: []

  # ── struct field inventory ──────────────────────────────────────────────────

  defp collect_structs(ast, acc) do
    {_, acc} =
      Macro.prewalk(ast, acc, fn
        {:%, _, [{:__aliases__, _, parts}, {:%{}, _, kvs}]} = node, acc ->
          name = List.last(parts) |> to_string()
          fields = for {k, _} <- kvs, is_atom(k), do: to_string(k)
          {node, Map.update(acc, name, MapSet.new(fields), &MapSet.union(&1, MapSet.new(fields)))}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # ── error-idiom inventory ───────────────────────────────────────────────────

  defp collect_errors(ast, acc) do
    {_, acc} =
      Macro.prewalk(ast, acc, fn
        {:error, x} = node, acc ->
          {node, Map.update(acc, error_shape(x), 1, &(&1 + 1))}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp error_shape({:__aliases__, _, parts}), do: {:ctor, List.last(parts) |> to_string()}
  defp error_shape(a) when is_atom(a) and a not in [nil, true, false], do: {:atom, to_string(a)}
  defp error_shape(s) when is_binary(s), do: {:string, nil}

  defp error_shape({:%, _, [{:__aliases__, _, parts}, _]}),
    do: {:struct, List.last(parts) |> to_string()}

  defp error_shape({n, _, c}) when is_atom(n) and is_atom(c), do: {:var, to_string(n)}
  defp error_shape(other), do: {:expr, Macro.to_string(other) |> String.slice(0, 30)}

  # ── reach annotation (which targets a type can reach) ───────────────────────

  @doc false
  def reach_note(type) when is_binary(type) do
    cond do
      Regex.match?(~r/\bFn\(/, type) -> "off :rs (closure)"
      Regex.match?(~r/\b(Int64|Int128|UInt64|UInt128)\b/, type) -> "off :js (>2^53)"
      Regex.match?(~r/\bInt\b(?![0-9])/, type) -> "off :rs/:jvm (bignum)"
      type in ["_Ty", "_Ret"] -> "—"
      true -> "✓ all 4"
    end
  end

  defp module_name({:defmodule, _, [aliases, _]}), do: short(aliases)
  defp module_name(_), do: "?"
  defp short({:__aliases__, _, parts}), do: List.last(parts) |> to_string()
  defp short(other), do: Macro.to_string(other)

  # ── markdown rendering ──────────────────────────────────────────────────────

  @doc "Render report data as the reviewable `PORT.analysis.md` string."
  def to_markdown(data) do
    [
      "# Port Analysis — Elixir → Rian",
      "",
      "**READ-ONLY, GENERATED** by `mix rian.port-analysis` (ADR-0075). Review the",
      "`REVIEW` sections and record decisions in a `port.spec` (feedback loop not yet",
      "wired). Regenerate to diff against source — do not hand-edit this file.",
      "",
      summary_section(data),
      sigs_section(data),
      holes_section(data),
      sums_section(data),
      errors_section(data)
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp summary_section(data) do
    ts = Enum.sum(for m <- data.modules, do: m.total_slots)
    fs = Enum.sum(for m <- data.modules, do: m.filled_slots)
    pct = if ts > 0, do: round(fs * 100 / ts), else: 0

    """
    ## Summary

    - modules: #{length(data.modules)} · type slots: #{ts} · auto-filled: #{fs} (#{pct}%) · holes: #{ts - fs}
    - structs seen: #{map_size(data.structs)} · proposed sums: #{length(data.sums)} · distinct error idioms: #{map_size(data.errors)}
    """
  end

  defp sigs_section(data) do
    rows =
      for m <- data.modules, {n, ar, sig} <- m.filled do
        params = Enum.join(sig.params, ", ")
        fa = if sig.tvars != [], do: " forall " <> Enum.join(sig.tvars, ", "), else: ""
        "| `#{n}/#{ar}` | `(#{params}) #{sig.ret}#{fa}` | #{reach_note(sig.ret)} |"
      end

    """
    ## 1. Inferred signatures — AUTO (high confidence, type-check-validated)

    | function | signature | return reach |
    |---|---|---|
    #{Enum.join(rows, "\n")}
    """
  end

  # whole-program declarations: each function with a residual unknown rendered as
  # an editable Rian signature — concrete types resolved by inference, structs as
  # their proposed `SumN`, and genuine unknowns as SHARED `Unk####` (the same
  # logical type carries one name everywhere). Replace each `Unk####` once.
  defp holes_section(data) do
    decls =
      data.wp.sigs
      |> Enum.filter(fn {_k, sig} -> needs_review?(sig) end)
      |> Enum.sort()
      |> Enum.map(fn {{mod, fn_, ar}, sig} ->
        names = Map.get(data.names, {mod, fn_, ar}, Enum.map(0..max(ar - 1, 0), &"p#{&1}"))
        params = Enum.zip(names, sig.params) |> Enum.map_join(", ", fn {n, t} -> "#{n} #{t}" end)
        "  # #{mod}.#{fn_}/#{ar}\n  pub def #{fn_}(#{params}) #{sig.ret} := …"
      end)

    index =
      data.wp.unks
      |> Enum.sort()
      |> Enum.map(fn {name, sites} ->
        refs = Enum.map_join(sites, ", ", fn {{m, f, a}, slot} -> "`#{m}.#{f}/#{a}:#{slot}`" end)
        "| `#{name}` | #{length(sites)} | #{refs} |"
      end)

    """
    ## 2. Declarations to complete — REVIEW (whole-program inferred)

    Each function with a residual unknown, as an **editable Rian signature**:
    concrete types are inferred, structs resolve to their proposed `SumN` (§3), and
    a genuine unknown is a **shared `Unk####`** — the *same* logical type carries one
    name across the whole program (linked through the call graph), so you replace
    each `Unk####` **once** and it propagates to every site in the index below.

    ```rian
    #{Enum.join(decls, "\n\n")}
    ```

    ### Placeholder index (replace once → applies to all sites)

    | placeholder | sites | references |
    |---|---|---|
    #{Enum.join(index, "\n")}
    """
  end

  defp needs_review?(%{params: ps, ret: r}) do
    Enum.any?([r | ps], fn t ->
      is_binary(t) and (String.contains?(t, "Unk") or String.contains?(t, "Sum"))
    end)
  end

  defp sums_section(data) do
    clustered = data.sums
    grouped = clustered |> List.flatten() |> MapSet.new()

    standalone =
      data.structs |> Map.keys() |> Enum.reject(&MapSet.member?(grouped, &1)) |> Enum.sort()

    groups =
      clustered
      |> Enum.with_index(1)
      |> Enum.map(fn {members, i} ->
        variants =
          Enum.map_join(members, "\n", fn s ->
            fields = data.structs |> Map.get(s, MapSet.new()) |> Enum.sort() |> Enum.join(", ")
            "  - `#{s}` { #{fields} }"
          end)

        "**Cluster #{i}** (co-occur in dispatch) — propose `type <NAME?> := #{Enum.join(members, " | ")}`\n#{variants}\n  - [ ] human: name the sum, confirm membership, set field types/reach"
      end)

    """
    ## 3. Proposed sum-type groupings — REVIEW (heuristic from dispatch co-occurrence)

    Structs clustered by co-occurrence in multi-clause heads + `case` arms. This is
    the non-local decision a human cannot make from a single draft file. Confirm or
    split each cluster; ambiguous structs (bridging two clusters) are merged here and
    may need splitting.

    #{Enum.join(groups, "\n\n")}

    **Standalone structs** (never dispatched): #{if standalone == [], do: "—", else: Enum.map_join(standalone, ", ", &"`#{&1}`")}
    """
  end

  defp errors_section(data) do
    rows =
      data.errors
      |> Enum.sort_by(fn {_, n} -> -n end)
      |> Enum.map(fn {shape, n} ->
        {form, proposal, reach} = error_proposal(shape)
        "| #{form} | #{n} | #{proposal} | #{reach} |"
      end)

    """
    ## 4. Error idioms — REVIEW (Elixir `{:error, _}` → Rian sum variant)

    A Rian `Result` (`T | E`) needs a Capitalized sum variant; Elixir uses atoms/
    strings/structs. Each distinct shape needs a human decision (atoms have a
    proposed PascalCase variant; strings/structs/vars need a named variant).

    | `{:error, X}` shape | count | proposed Rian variant | reach |
    |---|---|---|---|
    #{Enum.join(rows, "\n")}
    """
  end

  defp error_proposal({:ctor, name}),
    do: {"`#{name}` (ctor)", "`#{name}` ✓ already a variant", "✓ all 4"}

  defp error_proposal({:atom, a}), do: {"`:#{a}` (atom)", "`#{pascal(a)}` ? (confirm)", "✓ all 4"}

  defp error_proposal({:string, _}),
    do: {"`\"…\"` (string)", "**NEEDS DECISION** — name a variant", "—"}

  defp error_proposal({:struct, name}),
    do: {"`%#{name}{}` (struct)", "**NEEDS DECISION** — variant or payload", "—"}

  defp error_proposal({:var, v}),
    do: {"`#{v}` (var/propagation)", "propagated `E` (no fixed tag)", "—"}

  defp error_proposal({:expr, e}), do: {"`#{e}` (expr)", "**NEEDS DECISION**", "—"}

  defp pascal(atom_str) do
    atom_str |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end
end
