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
      `if`/`case` (incl. `when` arms), binary/unary operators, ctor & struct
      patterns (`%ECall{fun: f}` → `ECall(fun: f)`), tuples, lists/cons, atoms,
      string/number literals, local calls;
    * everything else is left **in place** as a greppable `TODO_PORT("…")`
      sentinel (carrying the original Elixir) or a `# TODO[port]: …` line comment,
      so nothing untranslated can masquerade as done;
    * **types are always holes** (`_Ty`, `_Ret`) — Elixir is untyped, so the human
      supplies the sums and signatures.

  Usage: `mix rian.transpile lib/rian/range.ex [-o out.rian]`.

  The honest contract: the output **will not compile** until a human fills the
  holes and resolves the markers. The value is the diff between "blank file" and
  "annotated draft", and the TODO summary that quantifies the remaining work per
  module before you commit to porting it.
  """

  @header [
    "# ─────────────────────────────────────────────────────────────────────────",
    "# DRAFT skeleton — transpiled from Elixir by `mix rian.transpile`. NOT done.",
    "# Translated: defs/clauses (+guards), if/case, operators, ctor/struct patterns,",
    "#   tuples, lists, maps, atoms, literals, local & sibling-module calls,",
    "#   string interpolation (${e}), nil→None.",
    "# You must still: (1) fill type holes `_Ty`/`_Ret`, (2) resolve every",
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
    {"Map", :get, 2} => {"Dict", "get"},
    {"Map", :get, 3} => {"Dict", "get_or"},
    {"Map", :put, 3} => {"Dict", "put"},
    {"Map", :has_key?, 2} => {"Dict", "has"},
    {"String", :length, 1} => {"Str", "length"}
  }

  # Elixir-stdlib modules with no (or only partial) Rian image — calls to these
  # stay markers unless individually `@stdlib`-mapped. Everything else capitalized
  # is assumed a sibling Rian module, whose `Mod.fun(args)` call is valid Rian and
  # is emitted inline (flagged for verification in the header, like `@stdlib`).
  @elixir_stdlib ~w(Enum Map MapSet String Regex Process Tuple Integer Float List
                    Keyword IO Kernel File Stream Atom Base Code Macro Exception
                    Module Application Agent Task GenServer System Path Access
                    Function Range Date Time DateTime Calendar)

  @doc "Transpile Elixir source text to a draft Rian skeleton string."
  def transpile(source) when is_binary(source) do
    source
    |> Code.string_to_quoted!()
    |> toplevel()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Transpile and report `{text, %{ports: n, defs: n}}` — `ports` counts unresolved
  markers (the remaining hand-work), `defs` counts emitted function groups.
  """
  def transpile_with_stats(source) when is_binary(source) do
    text = transpile(source)
    lines = String.split(text, "\n")
    ports = Enum.count(lines, &(String.contains?(&1, "TODO_PORT") or String.contains?(&1, "TODO[port]")))
    defs = Enum.count(lines, &Regex.match?(~r/^\s+(pub )?def \w+\(.*\) _Ret/, &1))
    # auto-mapped stdlib calls (A1) — resolved inline, but flagged for a semantics
    # check; counted (occurrences, not lines) so the report can surface them.
    mapped = (Regex.scan(~r/\b(?:List|Dict|Str|Int)\.[a-z_]+\(/, text) |> length())
    {text, %{ports: ports, defs: defs, mapped: mapped}}
  end

  @doc """
  Rank transpiled modules by port difficulty for folder-mode triage. Takes
  `[{name, %{defs:, ports:}}]` and returns rows sorted easiest-first by
  markers-per-def, each tagged `"easy"` (<3), `"med"`, `"hard"` (≥6), or `"—"`
  (no defs). The ratio is the honest cost signal: a struct-reflection module
  (many markers per def) sorts last; a near-portable one sorts first.
  """
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

      %{name: name, defs: defs, ports: ports, mapped: Map.get(stats, :mapped, 0), ratio: ratio, tag: tag}
    end)
    |> Enum.sort_by(& &1.ratio)
  end

  # ── module ────────────────────────────────────────────────────────────────

  defp toplevel({:defmodule, _, [aliases, [do: body]]}) do
    name = short_name(aliases)
    inner = body |> block_stmts() |> render_items() |> Enum.map(&indent/1)
    @header ++ ["mod #{name} do" | inner] ++ ["end"]
  end

  defp toplevel(other) do
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

  defp render_items(stmts) do
    {lines, _pending_doc, open} =
      Enum.reduce(stmts, {[], nil, nil}, fn stmt, {acc, doc, open} ->
        case classify(stmt) do
          {:moduledoc, text} ->
            {acc ++ flush(open) ++ [""] ++ moduledoc_lines(text), doc, nil}

          {:doc, text} ->
            {acc ++ flush(open), text, nil}

          {:drop, what, node} ->
            # alias/import/require are intentionally dropped (Rian resolves modules
            # differently) — a plain note, NOT a porting marker.
            {acc ++ flush(open) ++ ["# (dropped Elixir `#{what}`: #{snippet(node)})"], doc, nil}

          {:clause, vis, head, kw} ->
            clause = build_clause(head, kw)

            cond do
              open && same_group?(open, vis, clause) ->
                {acc, doc, add_clause(open, clause)}

              true ->
                {acc ++ flush(open), nil, new_group(vis, clause, doc)}
            end

          {:other, node} ->
            {acc ++ flush(open) ++ ["# TODO[port]: #{snippet(node)}"], doc, nil}
        end
      end)

    lines ++ flush(open)
  end

  defp classify({:@, _, [{:moduledoc, _, [text]}]}) when is_binary(text), do: {:moduledoc, text}
  defp classify({:@, _, [{:moduledoc, _, _}]}), do: {:moduledoc, ""}
  defp classify({:@, _, [{:doc, _, [text]}]}) when is_binary(text), do: {:doc, text}
  defp classify({:alias, _, _} = n), do: {:drop, "alias", n}
  defp classify({:import, _, _} = n), do: {:drop, "import", n}
  defp classify({:require, _, _} = n), do: {:drop, "require", n}
  defp classify({:def, _, [head, kw]}), do: {:clause, :pub, head, kw}
  defp classify({:defp, _, [head, kw]}), do: {:clause, :priv, head, kw}
  defp classify(other), do: {:other, other}

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

  defp flush(nil), do: []

  defp flush(%{vis: vis, doc: doc, clauses: clauses}) do
    kw = if vis == :pub, do: "pub def", else: "def"
    doc_lines = if doc, do: [~s(@doc "#{escape(one_line(doc))}")], else: []
    name = hd(clauses).name
    arity = hd(clauses).arity

    body_lines =
      if simple?(clauses) do
        [c] = clauses
        params = c.args |> Enum.map(&"#{var_name(&1)} _Ty") |> Enum.join(", ")
        # The `_Ty`/`_Ret` holes are themselves the type-filling signal (tracked by
        # the `defs` stat); no redundant per-line marker — types are erased in BEAM
        # forms and don't affect equiv-locking.
        ["#{kw} #{name}(#{params}) _Ret := #{render_body(c.body)}"]
      else
        holes = List.duplicate("_Ty", arity) |> Enum.join(", ")
        sig = "#{kw} #{name}(#{holes}) _Ret"
        [sig | Enum.map(clauses, &render_clause(kw, &1))]
      end

    [""] ++ doc_lines ++ body_lines
  end

  # "Simple" = a single clause whose params are all plain variables and no guard;
  # render inline `def f(a _Ty) _Ret := body`. Anything else gets a sig + clauses.
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
