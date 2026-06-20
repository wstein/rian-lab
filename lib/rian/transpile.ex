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
    * constructs with **no runtime semantics** or **no Rian image** are *dropped*
      with an honest note (not flagged as work): documentation / compile-metadata /
      conformance attributes (`@typedoc`, `@doc false`, `@impl`, `@external_resource`,
      `@enforce_keys`, `@rian_sig`/`use Rian.Ann`); an **exception-only `defmodule`**
      (`defexception` — errors are values in Rian, ADR-0035); `defmacro`/`defmacrop`
      (host metaprogramming — Rian has no syntax macros); `use Application` (OTP is
      native-per-target, ADR-0057); and a `Code.ensure_loaded?` integration guard
      (an optional host module, e.g. the Livebook/Kino smart cell). Emitting a
      `# TODO[port]` for these would falsely imply lost behaviour;
    * a **`@rian_host`-tagged** def is a sanctioned host boundary (ADR-0035/0048: the
      errors-as-values twin of a raising function), whose `rescue`/`catch`/`after`
      catches a host fault into a value — so it renders as real Rian surface
      (ADR-0048 §2 / ADR-0068 / ADR-0081 §5): `@effects(host)` + an `@external(:ex,
      Mod.fun)` **reference** to the original Elixir function (a bodiless def, no
      portable body; delegates to the tested original, no escaped host blob), not a
      marker and not a comment. The annotation binds the **next** `def`, so an
      intervening `@spec`/`@doc` (the conventional order) does not break the tag.
      **Dynamic dispatch** on a runtime
      module value (`mod.fun(args)`) lowers to its faithful BEAM-FFI form
      `apply(mod, :fun, [args])` (reflection / runtime module selection — non-portable,
      Reach pins it off `:rs`/`:js`), and a **module attribute in pattern position**
      (`{:ok, @c, x} = …`) becomes a pin `^c` of the const (ADR A2);
    * everything else is left **in place** as a greppable `TODO_PORT("…")`
      sentinel (carrying the original Elixir) or a `# TODO[port]: …` line comment,
      so nothing untranslated can masquerade as done — notably the constructs with
      **no Rian image**: an *un-sanctioned* (un-`@rian_host`) exception flow
      (`def … rescue`/`catch`/`after`, ADR-0035/0040 — restructure to a
      `Result`/`Option`) and the truthy, value-returning `&&`/`||` (Rian's `and`/`or`
      are boolean-only — restructure to `case`/`Option`);
    * **unmodelled types render `Any`** (the dynamic top) by default — Elixir is untyped,
      so the human refines the sums and signatures. With `--infer` (ADR-0075) the engine
      fills every *provable* slot, **harvesting any `@spec`** as a cross-checked hint (a
      consumed `@spec` becomes a passive `# spec:` provenance line, not a TODO); whatever
      stays unproven renders `Any` — a valid dynamic type (reaches every target but `:rs`),
      NOT the `_Unk` fill-me marker the gate rejects (`Rian.Check.check_unk`, ADR-0034), so
      a draft compiles as-is. A **private** function (`defp` → `def`) instead omits its
      return/param holes — `Rian.InferLocal` recovers them once enough is typed (infer-local,
      ADR-0034), so a `defp` carries neither `_Unk` nor a premature `Any`.

  Usage: `mix rian.transpile lib/rian/range.ex [-o out.rian]`.

  The honest contract: the output **will not compile** until a human fills the
  holes and resolves the markers. The value is the diff between "blank file" and
  "annotated draft", and the TODO summary that quantifies the remaining work per
  module before you commit to porting it.
  """
  use Rian.Ann

  # `@test def` slug length budget (ExUnit `test`/`describe` → `@test def`, ADR-0060):
  # the whole identifier stays ≤ `@max_slug`, but a `describe` group prefix is capped
  # *separately* at `@max_prefix` so a long group name can't eat the whole budget and
  # erase the test-specific part — each component keeps its meaning; the test name then
  # gets whatever remains. `uniquify_test_defs/1` resolves any collision a cap introduces.
  @max_slug 64
  @max_prefix 28

  # Elixir binary operators → their Rian infix spelling, mapped unchanged. The truthy
  # pair `&&`/`||` is deliberately ABSENT: Rian's `and`/`or` are boolean (they lower
  # to native `&&`/`||` and the checker requires Bool operands), so they are not a
  # faithful image of Elixir's value-returning, nil-coalescing `&&`/`||` — those are
  # emitted as a `TODO_PORT` marker for restructuring to `case`/Option (see
  # `expr/1`'s `&&`/`||` clause). `div`/`rem` are Elixir local calls Rian spells
  # infix. `++` is absent too — Rian has no `++`; it lowers to `List.concat/2`.
  @binops %{
    :+ => "+",
    :- => "-",
    :* => "*",
    :/ => "/",
    :<> => "<>",
    :<= => "<=",
    :>= => ">=",
    :< => "<",
    :> => ">",
    :== => "==",
    :!= => "!=",
    :and => "and",
    :or => "or",
    :in => "in",
    :div => "div",
    :rem => "rem"
  }

  # Rian operator precedence levels (lower binds tighter) and associativity, kept in
  # lockstep with `Rian.Pratt.opinfo/1` so the emitted parenthesization re-parses to
  # the intended tree. Used by `paren_operand/3` to wrap an operand only when needed.
  @op_level %{
    "*" => 3,
    "/" => 3,
    "div" => 3,
    "rem" => 3,
    "+" => 4,
    "-" => 4,
    "<>" => 5,
    "in" => 6,
    ".." => 6,
    "|>" => 7,
    "<" => 8,
    "<=" => 8,
    ">" => 8,
    ">=" => 8,
    "==" => 9,
    "!=" => 9,
    "and" => 10,
    "or" => 11,
    "<~" => 12
  }
  @op_assoc %{
    "<>" => :right,
    "<~" => :right,
    "in" => :none,
    "<" => :none,
    "<=" => :none,
    ">" => :none,
    ">=" => :none,
    "==" => :none,
    "!=" => :none
  }

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

  **`@rian_sig` annotations** (always honoured, with or without `infer`) are the
  authoritative escape hatch (`Rian.Ann`): a `@rian_sig` module attribute carrying a native
  Rian `def`/`struct`/`type` declaration supplies the exact types inference can't
  recover. A `def` annotation overrides the function's signature; a `struct`/`type`
  annotation replaces the holes the `defstruct`/`@type` emission leaves. A heredoc gives
  multi-line struct/type decls; `use Rian.Ann` keeps the `.ex` warning-free.
  """
  @rian_sig "pub def transpile(source String) _Unk"
  @rian_sig "pub def transpile(source String, opts _Unk) _Unk"
  @spec transpile(String.t(), keyword()) :: term()
  def transpile(source, opts \\ []) when is_binary(source) do
    body = body_lines(source, opts)
    ((report_header(body, opts) ++ body) |> Enum.join("\n")) <> "\n"
  end

  # Render the program body (no report header). Shared by `transpile/2`,
  # `transpile_with_stats/2`, and `incompatible/2`, so the header's length never has
  # to be guessed/stripped — each consumer works on the body directly.
  defp body_lines(source, opts) do
    ast = Code.string_to_quoted!(source)
    {sigmap, types} = if opts[:infer], do: infer_program(ast), else: {%{}, []}

    # `@rian_sig` annotations are authoritative — merge `def` sigs OVER inference, hand the
    # `struct`/`type` decls to the renderer. Read from the AST we ALREADY parsed (no
    # second parse of the source text); `Rian.Ann.from_beam/1` is the no-source reader.
    {def_anns, struct_anns, type_anns} = classify_annotations(Rian.Ann.from_ast(ast))

    # `@rian_sig` is authoritative, but a **bare-name param** (`nil` type, "infer this") falls
    # back per-position to the inferred sig rather than overriding it with a hole — so a
    # return-only `@rian_sig "pub def f(s) Ret"` pins the return and lets inference type `s`.
    merged =
      Map.merge(sigmap, def_anns, fn _k, inferred, declared ->
        %{declared | params: merge_infer_params(Map.get(inferred, :params, []), declared.params)}
      end)

    toplevel(ast, merged, types ++ type_anns, struct_anns)
  end

  # Per-position: a declared `nil` (an `_Infer` "infer this") takes the inferred type at that
  # slot; an explicit declared type wins. Trailing declared params with no inferred counterpart
  # stay `nil` and render `_Unk` downstream.
  defp merge_infer_params(inferred, declared) do
    declared
    |> Enum.with_index()
    |> Enum.map(fn
      {nil, i} -> Enum.at(inferred, i)
      {t, _i} -> t
    end)
  end

  # an unresolved `_Infer`/bare slot (`nil`) renders an honest `_Unk` hole.
  defp unk_if_nil(nil), do: "_Unk"
  defp unk_if_nil(type), do: type

  # The DRAFT banner — a **per-file report** computed from the rendered body, not a
  # static capability legend: what this transpilation produced (def count) and what
  # the human must still finish (type holes, port markers, auto-mapped stdlib calls
  # to verify, dropped-with-note items). The literal `TODO_PORT("` / `TODO[port]:`
  # marker spellings are deliberately avoided here so the banner is not itself counted
  # by `body_stats/1` or mistaken for an unfinished port by `Rian.Roundtrip.marker?/1`.
  defp report_header(body, opts) do
    %{defs: defs, holes: holes, ports: ports, mapped: mapped} = body_stats(body)
    dropped = Enum.count(body, &String.contains?(&1, "(dropped Elixir"))
    rule = "# " <> String.duplicate("─", 73)

    counts =
      [
        "#{defs} def#{plural(defs)}",
        "#{holes} type hole#{plural(holes)} (_Unk)#{if opts[:infer], do: "", else: ", types not inferred"}",
        "#{ports} port marker#{plural(ports)}",
        if(mapped > 0,
          do: "#{mapped} auto-mapped stdlib call#{plural(mapped)} (verify arg-order/edges)"
        ),
        if(dropped > 0, do: "#{dropped} dropped (no Rian image)")
      ]
      |> Enum.filter(& &1)
      |> Enum.map(&("#   " <> &1))

    todo =
      if ports == 0 and holes == 0 do
        ["# Next: equiv-lock against the Elixir oracle — no holes or markers remain."]
      else
        [
          "# To finish: fill the _Unk type holes, resolve every TODO_PORT / # TODO[port]",
          "#   marker, make matches exhaustive, then equiv-lock against the Elixir oracle."
        ]
      end

    [rule, "# rian.transpile DRAFT — NOT done (a hand-finished scaffold, not a port)."] ++
      counts ++ todo ++ [rule, ""]
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"

  # Tally the body for the report / `transpile_with_stats`: emitted def heads, port
  # markers, auto-mapped stdlib calls, and remaining `_Unk` type holes. Counted over
  # the body alone (never the report header) so the banner can't inflate its own tally.
  defp body_stats(body) do
    ports =
      Enum.count(
        body,
        &(String.contains?(&1, "TODO_PORT") or String.contains?(&1, "TODO[port]"))
      )

    # def heads — indented (inside a `mod`) or at column 0 (module-less source).
    defs = Enum.count(body, &Regex.match?(~r/^\s*(pub )?def \w+\(/, &1))

    # counts are over the code only — comment provenance lines (`# spec:` carrying the
    # original `@spec`, which can mention `List.t(` / `_Unk`) must not inflate the tally.
    code =
      body |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#")) |> Enum.join("\n")

    # auto-mapped stdlib calls (A1) — resolved inline, but flagged for a semantics check.
    mapped = Regex.scan(~r/\b(?:List|Dict|Str|Int)\.[a-z_]+\(/, code) |> length()
    holes = Regex.scan(~r/\b_Unk\b/, code) |> length()
    %{ports: ports, defs: defs, mapped: mapped, holes: holes}
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
      flat_items(body, sigmap, types, struct_anns)
    else
      [parent | hoisted] = flatten_modules(top)

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
    flat_items(other, sigmap, types, struct_anns)
  end

  # Render a statement-carrying node's declarations flat (no `mod` wrapper).
  defp flat_items(node, sigmap, types, struct_anns) do
    type_lines = if types == [], do: [], else: types ++ [""]

    items = render_items(block_stmts(node), sigmap, nil, struct_anns, referenced_attrs(node))
    type_lines ++ uniquify_test_defs(items)
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

  defp hoistable_submodule?({:defmodule, _, [_, [do: b]]}) do
    stmts = block_stmts(b)
    # Hoist only function-bearing submodules. A struct-only wrapper flattens to its
    # `struct` decl in place; an exception-only wrapper has no Rian image and is
    # dropped in place (both via `render_items`) — neither becomes a sibling `mod`.
    not struct_only_module?(stmts) and not exception_only_module?(stmts)
  end

  defp hoistable_submodule?(_), do: false

  # the `mod Name do … end` lines for one module (no header).
  defp module_lines({:defmodule, _, [aliases, [do: body]]}, sigmap, types, struct_anns) do
    name = short_name(aliases)
    referenced = referenced_attrs(body)
    # the FULL Elixir module name (`Rian.Beam`) — threaded so a `@rian_host` boundary
    # emits an `@external(:ex, Rian.Beam.fun)` reference to the real Elixir function.
    full_mod = aliases |> elem(2) |> Enum.map_join(".", &to_string/1)

    inner =
      body
      |> block_stmts()
      |> Enum.flat_map(&expand_defaults/1)
      |> render_items(sigmap, name, struct_anns, referenced, full_mod)
      |> Enum.map(&indent/1)

    # synthesized `type …` declarations (Phase B error sets, `@rian_sig type`) after `mod … do`.
    type_lines = if types == [], do: [], else: Enum.map(types, &("  " <> &1)) ++ [""]
    ["mod #{name} do" | type_lines ++ inner] ++ ["end"]
  end

  # Rian has no default arguments, so a `def f(a, opts \\ [])` expands into a real
  # clause `def f(a, opts) := body` plus one delegating clause per trailing default
  # (`def f(a) := f(a, [])`) — the same desugaring Elixir performs. Only expanded
  # when every parameter is a plain variable (so forwarding by name is sound);
  # otherwise the defaults are stripped to a single clause.
  # A guarded head `def f(a, b \\ d) when guard` wraps the call in `{:when, …}`.
  # Desugar the inner head, then re-attach the guard to every resulting clause (each
  # delegator's params are a prefix of the originals, so a guard over them stays valid).
  defp expand_defaults({df, m, [{:when, wm, [call, guard]}, kw]}) when df in [:def, :defp] do
    {df, m, [call, kw]}
    |> expand_defaults()
    |> Enum.map(fn {d, mm, [head, body]} -> {d, mm, [{:when, wm, [head, guard]}, body]} end)
  end

  defp expand_defaults({df, m, [{name, hm, params}, kw]})
       when df in [:def, :defp] and is_atom(name) and is_list(params) and
              kw != [] do
    defaulted = Enum.count(params, &match?({:\\, _, _}, &1))
    plain = Enum.map(params, &strip_default/1)

    cond do
      defaulted == 0 ->
        [{df, m, [{name, hm, params}, kw]}]

      Enum.all?(plain, &var?/1) ->
        # default args may sit in ANY position (`f(a \\ 1, b)` is legal Elixir, not just
        # trailing). For each delegating arity, omit the *rightmost* `j` defaulted params
        # (Elixir's rule) and splice their default value back at the original position.
        default_idxs = for {p, i} <- Enum.with_index(params), match?({:\\, _, _}, p), do: i

        delegators =
          for j <- defaulted..1//-1 do
            omitted = default_idxs |> Enum.take(-j) |> MapSet.new()
            kept = for {p, i} <- Enum.with_index(plain), not MapSet.member?(omitted, i), do: p

            call_args =
              for {p, i} <- Enum.with_index(params) do
                case p do
                  {:\\, _, [_, d]} ->
                    if MapSet.member?(omitted, i), do: d, else: Enum.at(plain, i)

                  _ ->
                    Enum.at(plain, i)
                end
              end

            {df, m, [{name, hm, kept}, [do: {name, [], call_args}]]}
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

  # split `@rian_sig` annotation strings into `{def sigmap, struct-by-name, [type decl]}`.
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
              IO.warn("ignoring unparseable @rian_sig annotation: #{inspect(str)}", [])
              {defs, structs, types}
          end
      end
    end)
  end

  @doc """
  Verify each `@rian_sig` against the transpiler's own inference for the same function
  (ADR-0081 safety): a declared CONCRETE type that *provably* conflicts with the inferred
  CONCRETE type (`Rian.Check.unify/2` → `:mismatch`) is a lying signature — a silent
  miscompile to every target, Rust included, which `rustc` would never allow. Returns a list
  of human-readable conflicts (empty = sound). `_Unk`/`_Infer`/un-inferred slots make no
  claim and are skipped — only concrete-vs-concrete disagreement is flagged, so the
  conservative inferer never raises a false alarm. `ctor_to_sum` (a `ctor → sum-type` map, e.g.
  `%{"ENum" => "Expr"}`) makes the check **subtype-aware**: a variant inferred where its sum is
  declared (`ENum` vs `Expr`) is compatible, not a lie.
  """
  @rian_sig "pub def verify_sigs(source String, ctor_to_sum Dict(String, String)) Vec(String)"
  @spec verify_sigs(String.t(), map()) :: [String.t()]
  def verify_sigs(source, ctor_to_sum \\ %{}) when is_binary(source) do
    ast = Code.string_to_quoted!(source)
    {sigmap, _types} = infer_program(ast)
    {def_anns, _structs, _types} = classify_annotations(Rian.Ann.from_ast(ast))

    for {{name, ar} = key, declared} <- def_anns,
        inferred = Map.get(sigmap, key),
        inferred != nil,
        msg <- sig_conflicts(name, ar, declared, inferred, ctor_to_sum) do
      msg
    end
  end

  defp sig_conflicts(name, ar, declared, inferred, ctor_to_sum) do
    ret =
      if type_conflict?(declared.ret, inferred.ret, ctor_to_sum),
        do: ["#{name}/#{ar} return: sig `#{declared.ret}` vs inferred `#{inferred.ret}`"],
        else: []

    params =
      declared.params
      |> Enum.zip(Map.get(inferred, :params, []))
      |> Enum.with_index()
      |> Enum.filter(fn {{d, i}, _} -> type_conflict?(d, i, ctor_to_sum) end)
      |> Enum.map(fn {{d, i}, idx} ->
        "#{name}/#{ar} param #{idx}: sig `#{d}` vs inferred `#{i}`"
      end)

    ret ++ params
  end

  # Is the declared sig type a *provable* lie vs the inferred type? Tvar-aware and
  # subtype-safe, so the conservative inferer never trips a false alarm:
  #   * either side mentions a type VARIABLE (`T`/`Vec(T)`/`Result(T, E)`) → compatible (a tvar
  #     unifies with anything: inference using `T` where a sig pins `Doc` is fine);
  #   * two scalar PRIMITIVES → conflict only across KINDS (`String` vs `Int*`, `Bool` vs
  #     `Float*`); same-kind width differences (`Int53` vs `Int64`) are intentional;
  #   * PRIMITIVE vs USER type → skip — a user sum can refine a primitive (`Effect`/`Status`
  #     are atom sums, narrower than `Symbol`); not a lie;
  #   * a variant inferred where its SUM is declared (`ENum` vs `Expr`, via `ctor_to_sum`) →
  #     compatible (subtype), not a lie;
  #   * two USER types with different (sum-resolved) base constructors (`Expr` vs `Pat`, `Vec`
  #     vs `Dict`) → conflict — nominally distinct, so a genuine miscompile.
  defp type_conflict?(declared, inferred, ctor_to_sum) do
    cond do
      # `_Unk` (unknown — the inferer gave up, or the sig makes no claim) and `Any` (top) are
      # compatible with everything; a confident declared type vs inferred `_Unk` just means the
      # human knows more than the conservative inferer — never a conflict.
      declared in ["_Unk", "Any"] or inferred in ["_Unk", "Any"] -> false
      # a union (`A | B`) is structural — inference often yields the variant shape of a nominal
      # sum (`Outcome` ≈ `Symbol | (Symbol, _Unk)`); not nominally comparable, so skip.
      String.contains?(declared, "|") or String.contains?(inferred, "|") -> false
      has_tvar?(declared) or has_tvar?(inferred) -> false
      prim?(declared) and prim?(inferred) -> prim_kind(declared) != prim_kind(inferred)
      prim?(declared) or prim?(inferred) -> false
      true -> resolve_sum(declared, ctor_to_sum) != resolve_sum(inferred, ctor_to_sum)
    end
  end

  # a constructor name resolves to its sum type (`ENum` → `Expr`); a sum or unknown name is
  # itself. So a variant and its sum compare equal (subtype-compatible).
  defp resolve_sum(t, ctor_to_sum) do
    base = base_name(t)
    Map.get(ctor_to_sum, base, base)
  end

  # a standalone uppercase single-letter component is a type variable (`T`, `Vec(T)`, `Result(T, E)`).
  defp has_tvar?(t), do: is_binary(t) and Regex.match?(~r/\b[A-Z]\b/, t)
  defp prim?(t), do: prim_kind(base_name(t)) != nil
  defp base_name(t) when is_binary(t), do: t |> String.split("(") |> hd() |> String.trim()
  defp base_name(_), do: ""

  defp prim_kind(t) when is_binary(t) do
    cond do
      t == "String" -> :string
      t == "Bool" -> :bool
      t == "Char" -> :char
      t == "Symbol" -> :symbol
      Regex.match?(~r/^U?Int\d*$/, t) -> :int
      Regex.match?(~r/^Float\d+$/, t) -> :float
      true -> nil
    end
  end

  defp prim_kind(_), do: nil

  # Parse a declaration annotation, returning nil instead of raising when the
  # string is not a complete declaration (e.g. a bodiless `def` head).
  defp safe_decl(str) do
    case Rian.Decl.parse_result(str) do
      {:ok, prog} -> prog
      {:error, _} -> nil
    end
  end

  # parse a Rian def signature into a sigmap entry, keyed by its own {name, arity}.
  # A dummy body makes the bodiless head a complete, parseable clause.
  defp parse_rian_sig(sig) do
    case Rian.Decl.parse_result(sig <> " := nil") do
      {:ok, %{funcs: [f | _]}} ->
        {{to_string(f.name), length(f.params)},
         %{params: Enum.map(f.params, &sig_param_type/1), ret: f.ret, tvars: f.tvars}}

      _ ->
        nil
    end
  end

  # `@rian_sig` distinguishes two underscore markers in param position (2026-06 design):
  #   * `_Infer` — "fill this param from inference" → `nil` here; the merge takes the inferred
  #     type at that slot, and an unresolved slot renders an honest `_Unk` hole. This lets a
  #     return-only sig (`pub def f(s _Infer) Ret`) pin the return without writing `_Unk` filler.
  #   * `_Unk` — *genuinely opaque* (no knowable type) → kept verbatim.
  # Any real type (`String`, a `Capitalized` name, a tvar) is kept too. So `_Unk` is reserved
  # for true opacity and never overloaded as "param I skipped".
  defp sig_param_type(%{type: "_Infer"}), do: nil
  defp sig_param_type(%{type: type}), do: type

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
          if Map.get(v, :result, false),
            do: {k, %{v | ret: "Result(#{v.ret}, Errors)"}},
            else: {k, v}
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
  @rian_sig "pub def transpile_with_stats(source String) _Unk"
  @rian_sig "pub def transpile_with_stats(source String, opts _Unk) _Unk"
  @spec transpile_with_stats(String.t(), keyword()) :: term()
  def transpile_with_stats(source, opts \\ []) when is_binary(source) do
    # Render the body once and count it directly — the report header is derived FROM
    # these counts, so it is never part of the tally (no header self-reference).
    body = body_lines(source, opts)
    text = ((report_header(body, opts) ++ body) |> Enum.join("\n")) <> "\n"
    {text, body_stats(body)}
  end

  # The markers for constructs that violate Rian's *concepts* (as opposed to merely
  # being host-FFI / not-yet-typed): truthy `&&`/`||` (no truthy operators —
  # ADR-0035) and exception flow (`def … rescue`/`catch`/`after` — errors are
  # values, ADR-0040). These are the targets of the errors-as-values migration.
  # A def with several recovery kinds renders them slash-joined (`def rescue/after`),
  # so the `def …` arm allows a `/kind` tail — otherwise a multi-kind def slips the gate.
  @incompatible_marker ~r{TODO_PORT\("(?:truthy (?:&&|\|\|)|def (?:rescue|catch|after)(?:/(?:rescue|catch|after))*) }

  @doc """
  The Rian-model-**incompatible** constructs in `source` — truthy `&&`/`||` and
  exception flow (see `@incompatible_marker`). Each is returned as the trimmed
  emitted line (carrying the original Elixir snippet). Unlike `transpile_with_stats`'
  `ports`, this excludes honest host-FFI markers and `_Unk` type holes: those are
  non-portable-but-legitimate or fillable, not *conceptual* incompatibilities.

  A function tagged `@rian_host` (a sanctioned exception boundary — `Rian.Ann`) is
  also excluded: its `rescue` converts a host/parser raise into a value, which is
  honest non-portability (ADR-0040), not a concept clash. `Mix.Tasks.Rian.Transpile`'s
  `--check` gates a codebase against regressions in what remains.
  """
  @rian_sig "pub def incompatible(source String) Vec(String)"
  @spec incompatible(String.t()) :: [String.t()]
  def incompatible(source) when is_binary(source) do
    host = MapSet.new(Rian.Ann.host_funcs(source))

    source
    |> body_lines([])
    |> Enum.filter(&Regex.match?(@incompatible_marker, &1))
    |> Enum.reject(&host_boundary_line?(&1, host))
    |> Enum.map(&String.trim/1)
  end

  # a marker line belongs to a `@rian_host`-tagged function when the `def NAME(` it
  # sits on names a tagged function (the outer def, not the `def rescue` in the marker
  # text — `rescue` is never followed immediately by `(`).
  defp host_boundary_line?(line, host) do
    case Regex.run(~r/\b(?:pub )?def (\w+)\(/, line) do
      [_, name] -> MapSet.member?(host, name)
      _ -> false
    end
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
  @rian_sig "pub def stdlib_map() _Unk"
  @spec stdlib_map() :: map()
  def stdlib_map, do: @stdlib

  @doc """
  Per-def inference ledger for `--infer-report`: `[{ {name, arity}, ledger }]`
  where each ledger lists the remaining holes and why (`:unresolved`, …).
  """
  @rian_sig "pub def infer_report(source String) _Unk"
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
  @rian_sig "pub def prime_xmod(sources Vec(String)) _Unk"
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

            if open != nil and same_group?(open, vis, clause),
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
  @rian_sig "pub def rank(entries Vec(_Unk)) _Unk"
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

  defp render_items(stmts, sigmap, mod_name, struct_anns, referenced, full_mod \\ nil) do
    host = host_reasons(stmts)

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
            # named for the module; a `@rian_sig struct …` annotation supplies the field
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

          {:drop_exception, name} ->
            # an exception-only `defmodule` has no Rian image (errors are values,
            # ADR-0035); drop with an honest note instead of a porting marker.
            {acc ++
               flush(open, sigmap) ++
               ["# (dropped Elixir exception `#{name}`: errors are values in Rian, ADR-0035)"],
             doc, nil}

          {:drop_note, text} ->
            # a host-only construct (a `defmacro`, `use Application`, a `Code.ensure_loaded?`
            # integration guard) with no Rian image — dropped with an honest note.
            {acc ++ flush(open, sigmap) ++ ["# #{text}"], doc, nil}

          {:test, name, body} ->
            {acc ++ flush(open, sigmap) ++ test_def(name, body, ""), doc, nil}

          {:describe, name, body} ->
            {acc ++ flush(open, sigmap) ++ render_describe(name, body), doc, nil}

          {:clause, vis, head, kw} ->
            clause = build_clause(head, kw, host)

            cond do
              open != nil and same_group?(open, vis, clause) ->
                {acc, doc, add_clause(open, clause)}

              true ->
                {acc ++ flush(open, sigmap), nil, new_group(vis, clause, doc, full_mod)}
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
  # `@rian_sig` annotations are HARVESTED into the signatures/struct/type decls; the
  # `use Rian.Ann` directive is annotation support — both are consumed, not ported.
  defp classify({:@, _, [{:rian_sig, _, _}]}), do: :skip
  # `@rian_host` marks a sanctioned exception boundary for the `--check` gate
  # (`Rian.Ann.host_funcs/1`); it is metadata, not a ported declaration.
  defp classify({:@, _, [{:rian_host, _, _}]}), do: :skip
  defp classify({:use, _, [{:__aliases__, _, [:Rian, :Ann]}]}), do: :skip
  # `use ExUnit.Case` (with or without options) is test-framework scaffolding with
  # no Rian analog — `@test def` is the whole surface (ADR-0060). Drop it silently.
  defp classify({:use, _, [{:__aliases__, _, [:ExUnit, :Case]} | _]}), do: :skip

  defp classify({:defmodule, _, [{:__aliases__, _, _} = al, [do: body]]}) do
    if exception_only_module?(block_stmts(body)),
      do: {:drop_exception, short_name(al)},
      else: {:submodule, short_name(al), body}
  end

  defp classify({:defstruct, _, [fields]} = n) when is_list(fields) do
    if Enum.all?(fields, &struct_field?/1), do: {:defstruct, fields}, else: {:other, n}
  end

  defp classify({:def, _, [head, kw]}), do: {:clause, :pub, head, kw}
  defp classify({:defp, _, [head, kw]}), do: {:clause, :priv, head, kw}

  # `defmacro`/`defmacrop` is host metaprogramming (ExUnit `@test`-generating macros,
  # `Rian.Ann.__using__`, Kino glue) — Rian has no syntax macros, so it has no Rian
  # image. Drop it with a one-line note (name/arity), not a body-dumping marker.
  defp classify({d, _, [head | _]}) when d in [:defmacro, :defmacrop],
    do:
      {:drop_note,
       "(dropped Elixir `defmacro #{macro_sig(head)}`: host metaprogramming, no Rian image)"}

  # `use Application` is OTP wiring — concurrency/OTP is native-per-target (ADR-0057),
  # never a Rian surface — so the behaviour has no Rian image. Drop with a note.
  defp classify({:use, _, [{:__aliases__, _, [:Application]} | _]}),
    do: {:drop_note, "(dropped Elixir `use Application`: OTP is native-per-target, ADR-0057)"}

  # A `if Code.ensure_loaded?(Mod) do … end` conditional-compilation guard wraps an
  # optional host integration (the Livebook/Kino smart cell) — host-only, present only
  # when the optional dep is loaded. Drop the whole guard with a note.
  defp classify(
         {:if, _, [{{:., _, [{:__aliases__, _, [:Code]}, :ensure_loaded?]}, _, _}, [do: _]]}
       ),
       do:
         {:drop_note,
          "(dropped: optional host integration behind a `Code.ensure_loaded?` guard — present only when the dep is loaded)"}

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

  # a wrapper whose only real declaration is a `defexception` — a host exception
  # struct (e.g. an emitter's `Unsupported`) backing a `@rian_host` raise/rescue
  # boundary. It has no Rian image: errors are values (ADR-0035), so it is dropped
  # in place with an honest note rather than a porting marker.
  defp exception_only_module?(stmts) do
    match?([{:defexception, _, _}], Enum.reject(stmts, &struct_mod_noise?/1))
  end

  defp struct_mod_noise?({:@, _, [{a, _, _}]})
       when a in [:moduledoc, :doc, :typedoc, :enforce_keys, :type, :typep],
       do: true

  defp struct_mod_noise?(_), do: false

  # a `defstruct` field: a bare atom (`:x`) or a `{atom, default}` keyword pair.
  defp struct_field?(a) when is_atom(a), do: true
  defp struct_field?({a, _default}) when is_atom(a), do: true
  defp struct_field?(_), do: false

  # `defstruct [:x, y: 0]` → `struct Mod(x Any, y Any)` (defaults dropped — the field NAMES
  # port; their types default to the dynamic `Any`, for the human to refine). `Any` not
  # `_Unk` so the draft compiles (`_Unk` is the gate-rejected fill-me marker, ADR-0034). A
  # `@rian_sig struct Mod(…)` annotation (by name) supplies the field types verbatim instead.
  defp struct_decl(mod_name, fields, struct_anns) do
    case Map.get(struct_anns, mod_name) do
      nil ->
        names =
          Enum.map(fields, fn
            {k, _default} -> k
            k -> k
          end)

        "struct #{mod_name}(#{Enum.map_join(names, ", ", &"#{&1} Any")})"

      decl ->
        to_any(decl)
    end
  end

  # A clause: name, arity, parameter/pattern nodes, optional guard, body AST. The
  # collection-only pass (`def_groups/1`, for inference seeding) needs no host context.
  defp build_clause(head, kw), do: build_clause(head, kw, %{})

  defp build_clause(head, kw, host) do
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

    has_do = kw != nil and Keyword.has_key?(kw, :do)
    recovery = has_do and recovery_keys(kw) != []
    # A `@rian_host`-tagged def is a SANCTIONED host boundary (ADR-0035/0048): the host
    # catch lives in an `@external(:ex, …)` body returning a value (ADR-0048 §2), so the
    # draft emits `@effects(host)` + `@external` (`flush/2`), not a `TODO_PORT` marker.
    host_reason = Map.get(host, name)
    host_body = if host_reason != nil, do: host_body_str(kw, recovery), else: nil

    # Distinguish a *present* `nil` body (`def f, do: nil`) from a truly bodyless
    # def (no `:do` key): both reduce to the atom `nil`, but only the former should
    # route through the `nil → Option` marker. The sentinel marks genuine absence. An
    # un-sanctioned `def … rescue/catch/after …` (Elixir exception flow) keeps `:do`
    # but its recovery has no Rian image — wrap so it surfaces as a marker rather than
    # silently emitting just the happy path.
    body =
      cond do
        recovery and host_reason != nil -> Keyword.get(kw, :do)
        recovery -> {:__recovery__, recovery_keys(kw), Keyword.get(kw, :do)}
        has_do -> Keyword.get(kw, :do)
        true -> :__no_body__
      end

    %{
      name: name,
      arity: length(args),
      args: args,
      guard: guard,
      body: body,
      host: host_reason,
      host_body: host_body
    }
  end

  # The `@external(:ex, …)` host-body string for a `@rian_host` def: the *full* host
  # expression (incl. the `rescue`/`catch`/`after` recovery that catches the host fault
  # into a value) reconstructed as a `try` block, so the catch lives in the external
  # body where it belongs — not dropped as the happy-path emission did.
  defp host_body_str(kw, true) do
    snippet({:try, [], [Keyword.take(kw, [:do, :rescue, :catch, :after, :else])]})
  end

  defp host_body_str(kw, false), do: snippet(Keyword.get(kw, :do))

  # Elixir exception-control keys on a `def`/`try` (`rescue`/`catch`/`after`) — Rian
  # has none (ADR-0035/0040: errors are values), so they cannot be ported mechanically.
  defp recovery_keys(kw), do: Enum.filter([:rescue, :catch, :after], &Keyword.has_key?(kw, &1))

  # Map each `@rian_host "reason"` to the NAME of the `def`/`defp` it immediately
  # precedes (the lib/rian convention; `Rian.Ann.host_funcs/1` is the runtime twin).
  # These names route their recovery body to the portable happy path in `build_clause/3`.
  defp host_reasons(stmts) do
    {map, _pending} =
      Enum.reduce(stmts, {%{}, nil}, fn
        {:@, _, [{:rian_host, _, [reason]}]}, {m, _} when is_binary(reason) ->
          {m, reason}

        {:@, _, [{:rian_host, _, _}]}, {m, _} ->
          {m, ""}

        {kind, _, [head | _]}, {m, r} when kind in [:def, :defp] and r != nil ->
          {Map.put(m, host_name(head), r), nil}

        # a non-def node (e.g. an intervening `@spec`/`@doc`) must NOT clear a pending
        # reason — the `@rian_host` annotation sticks until the next `def` consumes it,
        # so `@rian_host` + `@spec` + `def` (the conventional order) still maps the def.
        _other, acc ->
          acc
      end)

    map
  end

  defp host_name({:when, _, [call, _]}), do: host_name(call)
  defp host_name({name, _, _}) when is_atom(name), do: name

  # `name/arity` for a `defmacro` head (used only in its drop note).
  defp macro_sig({:when, _, [call, _]}), do: macro_sig(call)

  defp macro_sig({name, _, args}) when is_atom(name) and is_list(args),
    do: "#{name}/#{length(args)}"

  defp macro_sig({name, _, _}) when is_atom(name), do: "#{name}/0"

  defp new_group(vis, clause, doc, full_mod \\ nil),
    do: %{vis: vis, doc: doc, clauses: [clause], full_mod: full_mod}

  defp add_clause(open, clause), do: %{open | clauses: open.clauses ++ [clause]}

  defp same_group?(open, vis, clause) do
    open.vis == vis and hd(open.clauses).name == clause.name and
      hd(open.clauses).arity == clause.arity
  end

  # ── rendering a def group ───────────────────────────────────────────────────

  defp flush(nil, _sigmap), do: []

  defp flush(%{vis: vis, doc: doc, clauses: clauses} = group, sigmap) do
    kw = if vis == :pub, do: "pub def", else: "def"
    doc_lines = if doc, do: [~s(@doc "#{escape(one_line(doc))}")], else: []

    name = hd(clauses).name
    arity = hd(clauses).arity

    # inferred sig (or all-holes when inference is off / the slot is unresolved).
    sig = Map.get(sigmap, {to_string(name), arity})
    # a `nil` slot is a bare-name "infer" param the merge couldn't resolve — render it as an
    # honest `_Unk` hole (inference genuinely had no type), never silently dropped.
    ptypes =
      if sig, do: Enum.map(sig.params, &unk_if_nil/1), else: List.duplicate("_Unk", arity)

    ret = if sig, do: sig.ret, else: "_Unk"

    forall =
      if sig != nil and sig.tvars != [], do: " forall #{Enum.join(sig.tvars, ", ")}", else: ""

    # infer-local (ADR-0034): a PRIVATE function needn't declare its return — drop the
    # `_Unk` return hole so `Rian.InferLocal` recovers it once the params are typed
    # (one fewer hole per `defp`). `pub` keeps its declared boundary; a return inference
    # already resolved (a real type) is kept as useful signal.
    ret_part = if vis != :pub and ret == "_Unk", do: "", else: " #{to_any(ret)}"

    case hd(clauses).host do
      nil ->
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

      reason ->
        # A `@rian_host` boundary → real Rian surface (ADR-0048 §2 / ADR-0081 §5): the
        # host catch lives in an `@external(:ex, …)` body and the effect is declared
        # `@effects(host)` — a bodiless def, no portable body. The reason becomes the
        # `@doc` when the function has none of its own.
        host_doc = if doc, do: doc_lines, else: [~s(@doc "#{escape(one_line(reason))}")]
        # prefer a REFERENCE to the real Elixir function (`@external(:ex, Rian.Beam.fun)`,
        # ADR-0068/0081) — no escaped host blob, delegates to the tested original. Fall
        # back to the inline `try/rescue` string only when the full module is unknown
        # (a module-less / hoisted host def, which the real corpus doesn't have).
        ext =
          case Map.get(group, :full_mod) do
            nil -> ~s|@external(:ex, "#{escape(hd(clauses).host_body)}")|
            full -> "@external(:ex, #{full}.#{name})"
          end

        # a bodiless `@external` def carries NAMED params (no clauses to hold patterns) —
        # render them from the tagged clause's args, like the single-clause path.
        c = hd(clauses)

        params =
          c.args
          |> Enum.zip(ptypes)
          |> Enum.map_join(", ", fn {a, t} -> param(var_name(a), t, vis) end)

        sig_line = "#{kw} #{name}(#{params})#{ret_part}#{forall}"
        [""] ++ host_doc ++ ["@effects(host)", ext, sig_line]
    end
  end

  # A clause's body lines. A multi-statement body becomes a **block clause**
  # (`head\n  stmt\n  …\n  final\nend`); a single expression stays the inline
  # `head := expr` form. The block reads far better than the `;`-joined one-liner.
  defp clause_lines(head, {:__block__, _, [_, _ | _] = stmts}),
    do: [head] ++ Enum.map(stmts, &("  " <> stmt(&1))) ++ ["end"]

  defp clause_lines(head, body), do: ["#{head} := #{render_body(body)}"]

  # A PRIVATE parameter whose type is an unresolved hole omits the type — Rian
  # infers it (infer-local, like the dropped private return), so the draft carries
  # no `_Unk` noise. A `pub` parameter keeps its declared boundary (declare-public),
  # but a genuinely-unmodelled type renders `Any` (the dynamic top), not `_Unk` — `_Unk`
  # is the fill-me marker the gate REJECTS (`Rian.Check.check_unk`, ADR-0034), while `Any`
  # is a valid dynamic type (reaches every target but `:rs`).
  defp param(name, "_Unk", vis) when vis != :pub, do: name
  defp param(name, type, _vis), do: "#{name} #{to_any(type)}"

  # The multi-clause signature line lists param TYPES (the clauses carry the
  # patterns). For a private function with all-hole params, drop the `_Unk` types
  # to inferred placeholder names — Rian still needs a head to group the clauses.
  defp sig_params(ptypes, vis) do
    if vis != :pub and Enum.all?(ptypes, &(&1 == "_Unk")) do
      Enum.map_join(1..length(ptypes), ", ", &"p#{&1}")
    else
      Enum.map_join(ptypes, ", ", &to_any/1)
    end
  end

  # Render a genuinely-unmodelled type as `Any` (the dynamic top) rather than `_Unk` (the
  # fill-me marker the gate rejects). Substitutes at any depth, so `Vec(_Unk)` -> `Vec(Any)`,
  # `Dict(String, _Unk)` -> `Dict(String, Any)` (ADR-0034). The private bare-param / omitted
  # private-return paths render no type at all, so they never reach this.
  defp to_any(type), do: String.replace(type, "_Unk", "Any")

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
  # A bound variable's name, keyword-escaped (`mod` -> `mod_`) so an inline def head
  # param or an as-pattern binder matches the body's reference (which escapes via
  # `rian_ident`) AND does not collide with a Rian keyword. Without this an Elixir var
  # named `mod`/`type`/… emits the bare keyword in the head but `mod_` in the body.
  defp var_name({n, _, ctx}) when is_atom(n) and is_atom(ctx), do: rian_ident(n)
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
    # the test name takes whatever the (already-capped) group prefix leaves of the
    # total budget, so prefix and test name are each meaningful (not one swallowing
    # the other).
    slug = prefix <> cap_part(test_slug(name), @max_slug - byte_size(prefix))

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
    prefix = cap_part(test_slug(name), @max_prefix) <> "_"

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

  # Cap one slug component at a word boundary to `max` chars (keeps it readable).
  defp cap_part(slug, max) when byte_size(slug) <= max, do: slug

  defp cap_part(slug, max) do
    capped = slug |> binary_part(0, max) |> String.replace(~r/_[^_]*$/, "") |> String.trim("_")
    if capped == "", do: binary_part(slug, 0, max), else: capped
  end

  # Two tests can slug to the same name (a cap, or just near-identical descriptions).
  # Rian treats same-name zero-arity `@test def`s as clauses of ONE function — silently
  # merging tests — so disambiguate any later collision with a numeric suffix.
  defp uniquify_test_defs(lines) do
    {out, _seen} =
      Enum.map_reduce(lines, %{}, fn line, seen ->
        case Regex.run(~r/^@test def ([a-z][a-z0-9_]*)\(\)(.*)$/, line) do
          [_, name, rest] ->
            n = Map.get(seen, name, 0) + 1
            slug = if n == 1, do: name, else: "#{name}_#{n}"
            {"@test def #{slug}()#{rest}", Map.put(seen, name, n)}

          nil ->
            {line, seen}
        end
      end)

    out
  end

  # ── bodies ──────────────────────────────────────────────────────────────────

  defp render_body(:__no_body__), do: ~s|TODO_PORT("bodyless clause")|

  # A def whose body carries `rescue`/`catch`/`after`: Rian has no exception flow, so
  # the recovery cannot be emitted as-is — flag it (with the happy-path snippet) for
  # restructuring to a Result/Option (ADR-0040) instead of dropping it silently.
  defp render_body({:__recovery__, kinds, do_body}) do
    ks = Enum.map_join(kinds, "/", &to_string/1)

    ~s|TODO_PORT("def #{ks} (Elixir exception flow, no Rian image) — restructure to Result/Option; happy path: #{escape(snippet(do_body))}")|
  end

  # multi-statement body → Rian `;`-separated block: `x := e; …; final` (Pratt
  # parses a function body as a block of statements with a final expression).
  defp render_body({:__block__, _, stmts}) when length(stmts) > 1 do
    stmts |> value_tail() |> Enum.map_join("; ", &stmt/1)
  end

  defp render_body({:__block__, _, [one]}), do: render_body(one)
  # a bare bind as a whole body (`def f := (x = e)`, or a comprehension/lambda body that is
  # just `pat = e`) — route through the trailing-bind fixer so it ends in a value, not a bind.
  defp render_body({:=, _, _} = bind), do: [bind] |> value_tail() |> Enum.map_join("; ", &stmt/1)
  defp render_body(node), do: expr(node)

  # A Rian block must end in an EXPRESSION, never a bind (a destructuring bind desugars to a
  # single-arm `case` and needs a continuation — `Rian.Pratt`). Elixir blocks may end in
  # `pat = e` (value = `e`). So when a body's last statement is a bind, append its bound
  # value: a simple `x = e` → keep the bind, return `x`; a destructuring `pat = e` → bind a
  # fresh temp to `e` once, assert `pat` against it, return the temp (single eval, assertion
  # preserved). Reach still pins the function by its body's FFI, exactly as before.
  defp value_tail(stmts) do
    case List.last(stmts) do
      {:=, _, [pat, _e]} = bind ->
        if var?(pat) do
          stmts ++ [pat]
        else
          {:=, m, [^pat, e]} = bind
          # a non-`_`-prefixed temp (a leading `_` would render as the wildcard `_`,
          # `underscore_var/1`); `rian_bv` is internal and collision-unlikely.
          tmp = {:rian_bv, [], Elixir}
          List.replace_at(stmts, -1, {:=, m, [tmp, e]}) ++ [{:=, m, [pat, tmp]}, tmp]
        end

      _ ->
        stmts
    end
  end

  # A lambda body, unlike a clause body, is a single expression unless wrapped in an
  # explicit `do … end` block (the `;`-block ambiguity decision in `Rian.Pratt`). So a
  # multi-statement lambda body is emitted block-delimited; a single expression stays
  # bare. Eta-expanded captures (`&…`) and `fn`-case desugars are already single-expr.
  defp lambda_body({:__block__, _, stmts} = b) when length(stmts) > 1,
    do: "do #{render_body(b)} end"

  defp lambda_body(body), do: render_body(body)

  # a block statement: an Elixir bind `x = e` → Rian bind `x := e`; anything else
  # (incl. the final return expression) is a bare expression.
  #
  # A **chained** match `lhs = mid = rhs` (Elixir) has no Rian chained `:=`; unchain it to
  # two statements — bind `rhs` to `mid`, then `lhs` to `mid` — when `mid` is a variable
  # (the compiler idiom `%{…} = prog = erase(prog)`). A non-var intermediate is left to the
  # chained form (vanishingly rare); the block renderer joins these with `; ` like any stmt.
  defp stmt({:=, _, [lhs, {:=, _, [mid, _]} = chain]}) when is_tuple(mid) do
    if var?(mid),
      do: "#{stmt(chain)}; #{pat(lhs)} := #{expr(mid)}",
      else: "#{pat(lhs)} := #{expr(chain)}"
  end

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
  defp expr(a) when is_atom(a), do: atom_lit(a)

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
        case bitstr_text(segments, &expr/1) do
          nil -> ~s|TODO_PORT("binary construction #{escape(snippet(n))}")|
          v -> v
        end
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

  defp expr({op, _, [l, r]}) when is_map_key(@binops, op) do
    rop = @binops[op]
    "#{paren_operand(l, rop, :left)} #{rop} #{paren_operand(r, rop, :right)}"
  end

  # Elixir's truthy `&&`/`||` (value-returning, nil/false-falsy) have no faithful Rian
  # image: `and`/`or` are boolean-only, so `x || default` / `guard && f(guard)` must be
  # restructured to `case`/Option by hand (the self-host port does exactly this). Emit
  # an honest marker rather than a wrong boolean op or an eager `&&(l, r)` call.
  defp expr({op, _, [_l, _r]} = n) when op in [:&&, :||] do
    kind = if op == :&&, do: "&&", else: "||"

    ~s|TODO_PORT("truthy #{kind} (nil-coalescing) — restructure to case/Option: #{escape(snippet(n))}")|
  end

  # Elixir list concat `l ++ r` → the portable prelude `List.concat/2` (Rian has no
  # `++` operator).
  defp expr({:++, _, [l, r]}), do: "List.concat(#{expr(l)}, #{expr(r)})"

  # Elixir inclusive range `a..b` → the Rian `..` range operator (ADR-0036/0079); it
  # desugars in `Rian.Core` to `List.seq(a, b)`. No-space form, Elixir style.
  defp expr({:.., _, [a, b]}), do: range_text(a, b)

  # a stepped range `a..b//step`. `//1` is the default ascending range (`a..b`); `//-1`
  # is descending — `List.reverse(b..a)` (the ascending range, reversed; both portable).
  # Other steps have no Rian image yet → a greppable marker.
  defp expr({:..//, _, [a, b, 1]}), do: range_text(a, b)
  defp expr({:..//, _, [a, b, {:-, _, [1]}]}), do: "List.reverse(#{range_text(b, a)})"
  defp expr({:..//, _, [_, _, _]} = n), do: ~s|TODO_PORT("stepped range: #{escape(snippet(n))}")|

  # Elixir list subtraction `l -- r` → a portable `List.reject` over membership (Rian has
  # no `--` operator). This is *set* difference (drops every element of `l` that is in `r`),
  # faithful for the unique-list uses in the compiler (`targets -- [:ex]`, `required --
  # reached`); a true multiset `--` would differ, but the corpus subtracts sets.
  defp expr({:--, _, [l, r]}),
    do: "List.reject(#{expr(l)}, (__d) -> List.member(#{expr(r)}, __d))"

  # Elixir text/regex match `a =~ regex` → `Regex.match?(regex, a)` (host, typed `Bool`
  # in `Rian.Builtins`); Rian has no `=~` operator. The string-`contains?` form of `=~`
  # is not emitted (the corpus uses the regex form).
  defp expr({:=~, _, [l, r]}), do: "Regex.match?(#{expr(r)}, #{expr(l)})"

  # The pipe is real Rian surface (`x |> f(y)` ≡ `f(x, y)`, ADR/01_basics) — render
  # it infix. Without this it falls through to the generic local-call clause and
  # mis-renders as the prefix `|>(l, r)`.
  defp expr({:|>, _, [l, r]}), do: "#{paren_operand(l, "|>", :left)} |> #{pipe_rhs(r)}"

  # A match `=` reached in expression position (a `with`/`case` arm, a nested
  # statement) is Rian's bind `:=`, same as the block-statement path (`stmt/1`).
  # Without this it falls through to the generic local-call clause and mis-renders
  # as the prefix `=(l, r)`.
  defp expr({:=, _, [l, r]}), do: "#{pat(l)} := #{expr(r)}"

  defp expr({:-, _, [x]}), do: "-#{paren_unary(x)}"
  defp expr({:not, _, [x]}), do: "not #{paren_unary(x)}"
  defp expr({:!, _, [x]}), do: "not #{paren_unary(x)}"

  # Elixir `raise` → Rian `panic` (ADR-0035/0040): the diverging, uncatchable abort.
  # `raise Mod, msg` / `raise msg` panic with the message; bare `raise Mod` with the
  # error name. This emits valid Rian (vs the invalid bare `raise(…)`); an *expected*
  # error (one a caller should recover) is then restructured to a `Result` by hand —
  # the same draft-finishing the transpiler always requires.
  defp expr({:raise, _, args}), do: "panic(#{raise_msg(args)})"
  # `reraise exc, stacktrace` / `reraise exc, attrs, stacktrace` — the FIRST arg is the
  # exception/message and the LAST is always the stacktrace, so panic on the exception
  # (not the trailing `__STACKTRACE__`, which `raise_msg/1`'s 2-arg arm would otherwise pick).
  defp expr({:reraise, _, [exc | _]}), do: "panic(#{raise_msg([exc])})"

  defp expr({:if, _, [c, kw]}) do
    t = render_body(Keyword.get(kw, :do))
    e = if Keyword.has_key?(kw, :else), do: render_body(Keyword.get(kw, :else)), else: nil
    if e, do: "if #{expr(c)} do #{t} else #{e} end", else: "if #{expr(c)} do #{t} end"
  end

  # `unless cond do X [else Y] end` ≡ `if not cond do X [else Y] end` — Rian has no
  # `unless`, but the negation is a faithful, portable image (not host residue). The
  # condition is parenthesized so `not` binds over the whole expression (`unless a != b`
  # → `if not (a != b)`, not `if (not a) != b`).
  defp expr({:unless, _, [c, kw]}) do
    t = render_body(Keyword.get(kw, :do))
    e = if Keyword.has_key?(kw, :else), do: render_body(Keyword.get(kw, :else)), else: nil
    neg = "not (#{expr(c)})"
    if e, do: "if #{neg} do #{t} else #{e} end", else: "if #{neg} do #{t} end"
  end

  defp expr({:case, _, [subj, [do: arms]]}) do
    rendered = Enum.map_join(arms, "\n", fn arm -> indent(case_arm(arm)) end)
    "case #{expr(subj)} do\n#{rendered}\nend"
  end

  # Rian has no `cond` — lower `cond do g1 -> e1 … true -> en end` to a right-nested
  # `if/else` chain (the shape the hand-written compiler sources use). The trailing
  # `true ->` clause becomes the bare `else` value; a non-`true` last guard yields an
  # `if … do … end` with no `else` (a fall-through, as `cond` itself would raise).
  defp expr({:cond, _, [[do: clauses]]}) do
    Enum.reduce(Enum.reverse(clauses), nil, fn
      {:->, _, [[true], body]}, nil ->
        render_body(body)

      {:->, _, [[guard], body]}, nil ->
        "if #{expr(guard)} do #{render_body(body)} end"

      {:->, _, [[guard], body]}, acc ->
        "if #{expr(guard)} do #{render_body(body)} else #{acc} end"
    end)
  end

  # `with pat <- expr, … do body [else arms] end` (ADR-0040) — the Rian form. Each
  # `{:<-, …}` clause renders `pat <- expr`; a bare-expr clause is a filter. The trailing
  # keyword list carries `:do` (+ optional `:else` arms, rendered like `case` arms).
  defp expr({:with, _, args}) when is_list(args) and args != [] do
    {clauses, [kw]} = Enum.split(args, -1)
    clause_text = Enum.map_join(clauses, ", ", &with_clause/1)
    body = render_body(Keyword.fetch!(kw, :do))

    else_text =
      if Keyword.has_key?(kw, :else),
        do: " else\n" <> Enum.map_join(Keyword.get(kw, :else), "\n", &indent(case_arm(&1))),
        else: ""

    "with #{clause_text} do #{body}#{else_text} end"
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
  # (ADR-0042). A **pattern** param (`fn {k, v} -> …`) — which a Rian lambda does not
  # take (its params are plain names) — desugars to a fresh param + a single-arm `case`,
  # the same shape as a multi-clause fn.
  defp expr({:fn, _, [{:->, _, [args, body]} = arrow]}) do
    if Enum.all?(args, &simple_var?/1),
      do: "(#{Enum.map_join(args, ", ", &pat/1)}) -> #{lambda_body(body)}",
      else: fn_case_desugar([arrow])
  end

  # multi-clause `fn` → a single-clause lambda over fresh params that `case`-matches
  # on them (Rian lambdas are single-clause, ADR-0042).
  defp expr({:fn, _, [_ | _] = clauses}), do: fn_case_desugar(clauses)

  # function captures (ADR-0042) → eta-expanded Rian lambdas.
  # `&name/arity` → `(p1,…) -> name(p1,…)`
  defp expr({:&, _, [{:/, _, [{name, _, ctx}, arity]}]})
       when is_atom(name) and is_atom(ctx) and is_integer(arity) do
    ps = capture_params(arity)
    # a 2-arity capture of an operator (`&div/2`, `&+/2`) eta-expands to the INFIX form
    # `p1 div p2` — `div`/`rem`/… are reserved operators in Rian, not callable as `div(…)`.
    body =
      if arity == 2 and is_map_key(@binops, name) do
        [a, b] = ps
        "#{a} #{@binops[name]} #{b}"
      else
        "#{name}(#{Enum.join(ps, ", ")})"
      end

    "(#{Enum.join(ps, ", ")}) -> #{body}"
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

  defp expr({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: rian_ident(name)

  # anonymous-function application `f.(args)` → Rian variable application `f(args)`
  # (Rian distinguishes calling a fn-valued variable from a local call by scope).
  defp expr({{:., _, [f]}, _, args}) when is_list(args),
    do: "#{expr(f)}(#{Enum.map_join(args, ", ", &expr/1)})"

  defp expr(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

  # the panic message for an Elixir `raise`: `raise Mod, msg` / `raise msg` use the
  # message expression; a bare `raise Mod` uses the error name; a no-arg raise the
  # literal "panic".
  defp raise_msg([{:__aliases__, _, parts}]), do: expr(parts |> List.last() |> to_string())
  defp raise_msg([_mod, msg | _]), do: expr(msg)
  defp raise_msg([msg]), do: expr(msg)
  defp raise_msg(_), do: expr("panic")

  # Render an operand of the Rian operator `parent_op`, wrapping it in parens iff
  # omitting them would change the Rian re-parse. Using levels where *lower binds
  # tighter*, the operand needs parens when it binds looser than the parent, or binds
  # at the same level on the side the parent's associativity does not favour — which
  # also covers same-level non-associative parents (Rian's parser rejects those
  # unparenthesized). An atomic operand (`operand_level/1 == nil`) never needs them.
  # render a Rian `a..b` range, parenthesizing each operand by `..`'s precedence.
  defp range_text(a, b), do: "#{paren_operand(a, "..", :left)}..#{paren_operand(b, "..", :right)}"

  defp paren_operand(node, parent_op, side) do
    s = expr(node)
    plevel = @op_level[parent_op]
    passoc = Map.get(@op_assoc, parent_op, :left)

    case operand_level(node) do
      nil ->
        s

      clevel ->
        wrap? =
          cond do
            clevel > plevel -> true
            clevel < plevel -> false
            side == :left -> passoc != :left
            true -> passoc != :right
          end

        if wrap?, do: "(#{s})", else: s
    end
  end

  # A prefix `not`/`-` binds tighter than every infix operator (`Pratt.parse_prefix`
  # reads its operand above all infix binding powers), so any infix operand must be
  # parenthesized; an atomic operand is left bare.
  defp paren_unary(node) do
    s = expr(node)
    if operand_level(node), do: "(#{s})", else: s
  end

  # The Rian precedence level of an operand's top infix operator, or `nil` when the
  # operand is atomic (literal, var, call, list/tuple/map…) and never needs wrapping.
  defp operand_level({op, _, [_, _]}) when is_map_key(@binops, op), do: @op_level[@binops[op]]
  defp operand_level({:|>, _, [_, _]}), do: @op_level["|>"]
  defp operand_level({:=, _, [_, _]}), do: 13
  defp operand_level(_), do: nil

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

      var?(mod) and pipe_arity == 0 ->
        # Dynamic dispatch on a runtime module value (`mod.fun(args)`, e.g. reflection
        # or a selected-at-runtime module). Elixir's `mod.f(a)` IS `apply(mod, :f, [a])`
        # — emit that faithful BEAM-FFI lowering (non-portable; Reach pins it off
        # :rs/:js) rather than a porting marker. A piped form keeps the honest marker.
        "apply(#{m}, :#{fun}, [#{arg_strs}])"

      true ->
        ~s|TODO_PORT("remote/stdlib call: #{escape("#{m}.#{fun}(#{arg_strs})")}")|
    end
  end

  defp elixir_stdlib?({:__aliases__, _, _}, m), do: m in @elixir_stdlib
  defp elixir_stdlib?(_, _), do: false

  defp mod_str({:__aliases__, _, parts}), do: parts |> List.last() |> to_string()
  defp mod_str(a) when is_atom(a), do: ":#{a}"
  # a runtime module VALUE (`apply(mod, …)`): keyword-escape so it matches the head
  # binder (`mod` -> `mod_`), not the bare keyword that `snippet` would emit.
  defp mod_str({n, _, ctx}) when is_atom(n) and is_atom(ctx), do: rian_ident(n)
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

  defp string_part(s) when is_binary(s), do: {:ok, escape(s)}
  defp string_part({:"::", _, [interp, {:binary, _, _}]}), do: {:ok, "${#{interp_inner(interp)}}"}
  defp string_part(_), do: :error

  # an interpolated hole is usually wrapped in `Kernel.to_string`/`to_string`; unwrap.
  defp interp_inner({{:., _, [_mod, :to_string]}, _, [e]}), do: expr(e)
  defp interp_inner({:to_string, _, [e]}), do: expr(e)
  defp interp_inner(e), do: expr(e)

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

  # a `with` clause: a failable bind `pat <- expr`, or a bare-expr filter.
  defp with_clause({:<-, _, [pat, e]}), do: "#{pat(pat)} <- #{expr(e)}"
  defp with_clause(filter), do: expr(filter)

  # fresh-param lambda whose body `case`-matches the params (arity > 1 matches the tuple
  # of params); guards and per-clause patterns are preserved via `case_arm`. Used for
  # multi-clause fns AND single-clause fns with pattern params.
  defp fn_case_desugar(clauses) do
    n = fn_arity(hd(clauses))
    params = Enum.map(1..n, &"p#{&1}")
    subject = if n == 1, do: hd(params), else: "{#{Enum.join(params, ", ")}}"
    arms = Enum.map_join(clauses, "\n", &indent(case_arm(fn_clause_to_arm(&1, n))))
    "(#{Enum.join(params, ", ")}) -> case #{subject} do\n#{arms}\nend"
  end

  # a plain variable AST node (`{name, meta, ctx}` with atom name + atom context) — as
  # opposed to a pattern (tuple/list/map/struct), which a Rian lambda param can't be.
  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false

  # ── patterns ────────────────────────────────────────────────────────────────

  defp pat(n) when is_integer(n) or is_float(n), do: to_string(n)
  defp pat(s) when is_binary(s), do: ~s|"#{escape(s)}"|
  defp pat(true), do: "true"
  defp pat(false), do: "false"
  # `nil` → `None`, same as `expr/1`. Without this clause `nil` (an atom) fell to the
  # generic atom clause and rendered the empty atom `:`, which no longer matches the
  # `None` a producer emits — silently breaking every guardless/`nil`-default match.
  defp pat(nil), do: "None"
  defp pat(a) when is_atom(a), do: atom_lit(a)
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
    do:
      (case bitstr_text(segments, &pat/1) do
         nil -> ~s|TODO_PORT(#{inspect(snippet(n))})|
         v -> v
       end)

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

  # A module attribute in pattern position (`{:ok, @probe, x} = …`) matches against
  # the attribute's compile-time value — i.e. a `const`. Rian spells "match this
  # binding's value, don't rebind" as a pin (`^name`, ADR A2 §2).
  defp pat({:@, _, [{name, _, ctx}]}) when is_atom(name) and not is_list(ctx), do: "^#{name}"

  defp pat(other), do: ~s|TODO_PORT(#{inspect(snippet(other))})|

  # one Rian map pair (expression position): an atom Elixir key → the `k: v`
  # shorthand; any other key (string/module/tuple/var) → `keyExpr => v` (ADR-0033). A
  # `nil` key is a value, not the `k:` shorthand — render it `None => v` (else the
  # atom clause would emit the empty-atom key `:`).
  defp map_pair_rian({nil, v}), do: "None => #{expr(v)}"
  defp map_pair_rian({k, v}) when is_atom(k), do: "#{k}: #{expr(v)}"
  defp map_pair_rian({k, v}), do: "#{expr(k)} => #{expr(v)}"

  # one Rian map *pattern* pair: the key is a value (lowered via `expr`), the value a
  # sub-pattern (via `pat`). Atom key → `k: p`; non-atom key → `keyExpr => p`.
  defp map_pat_pair_rian({nil, p}), do: "None => #{pat(p)}"
  defp map_pat_pair_rian({k, p}) when is_atom(k), do: "#{k}: #{pat(p)}"
  defp map_pat_pair_rian({k, p}), do: "#{expr(k)} => #{pat(p)}"

  # a comprehension clause (ADR-0079): a generator `pat <- src` (any pattern — a
  # non-match skips the element) or a boolean filter.
  defp for_clause_rian({:<-, _, [lhs, src]}), do: "#{pat(lhs)} <- #{expr(src)}"

  # an Elixir comprehension **bind** clause `x = expr` (binds `x` for the later clauses /
  # body) has no Rian surface (ADR-0079), but a **singleton-list generator** `x <- [expr]`
  # is a faithful, portable image: the one-element list binds `x` to `expr` exactly once.
  defp for_clause_rian({:=, _, [lhs, rhs]}), do: "#{pat(lhs)} <- [#{expr(rhs)}]"

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
  # reduce-arms applied at the leaf. `__accᵢ` is depth-fresh so nested accumulators don't
  # shadow; it can't collide with a generator loop var because `pat/1` renders any
  # `__`-prefixed user binder as the anonymous `_`.
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
    if sa != nil and sb != nil, do: "#{sa}-#{sb}"
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
    if String.starts_with?(s, "_"), do: "_", else: rian_ident(s)
  end

  # The Rian reserved words (mirrors `Rian.Lexer`'s `@keywords`). An Elixir identifier
  # spelling one (`type`, `range`, `mod`, …) is a valid var/name in Elixir but lexes as a
  # keyword in Rian, so a `{type, x}` pattern or a `type` reference breaks. Rename it with
  # a trailing `_` — a pure function of the name, so a binding and its uses stay in sync.
  # includes Rian's **word operators** (`Rian.Lexer.@op_words`): an Elixir local named
  # `div`/`rem` (both valid Elixir identifiers) would otherwise emit bare and re-lex as an
  # operator token, not an identifier. Aligns with `bare_atom?`'s escape set below.
  @rian_keywords ~w(if do else end def type range case when struct alias mod pub const
                    macro use with for protocol impl opaque abstract
                    and or not in div rem)

  defp rian_ident(name) do
    s = to_string(name)
    if s in @rian_keywords, do: s <> "_", else: s
  end

  # An atom literal: bare `:name` when the name is parseable unquoted, else the quoted
  # `:"name"` form (which `Rian.Pratt` accepts for any name). A name is bare-safe when
  # it is an identifier, a keyword (`:if`), an operator word (`:and`), or an operator
  # run the lexer's op-atom rule scans (`:==`, `:/=`) — but NOT the bare `=` (that is
  # the bind `:=`). Elixir-AST tags like `:%`/`:{}`/`:<<>>`/`:%{}` are thus quoted.
  defp atom_lit(a) do
    s = to_string(a)
    if bare_atom?(s), do: ":#{s}", else: ~s|:"#{escape(s)}"|
  end

  defp bare_atom?(s) do
    cond do
      Regex.match?(~r/^[a-z_]\w*[?!]?$/, s) ->
        true

      s in ~w(and or not in rem div) ->
        true

      s in @rian_keywords ->
        true

      # an operator run the lexer's op-atom rule scans bare — but NOT the bind `=`,
      # nor a run carrying the bitstring delimiters `<<`/`>>` (those lex as `{:bitopen}`/
      # `{:bitclose}` before the op-atom rule, so e.g. `:<<>>` must be quoted).
      Regex.match?(~r/^[+\-*\/<>=!]+$/, s) and s != "=" and
        not String.contains?(s, "<<") and not String.contains?(s, ">>") ->
        true

      true ->
        false
    end
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

  # Escape a string for a Rian double-quoted literal. The backslash MUST be doubled
  # first (else escaping the others would themselves be re-doubled); then the quote
  # and the control chars Rian spells with an escape. Without backslash-doubling a
  # source-text value like `"\n"` (the two chars `\` `n`, e.g. from `char_source`)
  # was emitted verbatim and re-lexed as a newline.
  defp escape(s) do
    s
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
    |> String.replace("\r", "\\r")
  end
end
