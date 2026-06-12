defmodule Rian.Lower do
  @moduledoc """
  End-to-end backend lowering for a single Rian function. Wires together:
    * type env             (Rian.Exhaustiveness)
    * pattern lowering     (Rian.PatternLower)
    * exhaustiveness gate  (Rian.Exhaustiveness.analyze)  -- refuses to emit if it fails
    * expression parsing   (Rian.Pratt)                    -- precedence-aware
  and emits idiomatic Elixir AND Rust.

  > #### Known limitation — higher-order *application* on the Elixir text target {: .warning}
  > Applying a function-*valued variable* (`f(x)` where `f` is a parameter or a
  > binding) is emitted as a plain `f(x)` here, which Elixir reads as a *local
  > function call*, not the variable application it needs (`f.(x)`). Distinguishing
  > the two requires threading lexical scope through expression emission. The
  > **Erlang abstract-forms backend (`Rian.Beam`) handles this correctly** and is
  > the self-hosting bootstrap target, so higher-order execution is proven there;
  > this text backend's fix is deferred (it is a source-generation demonstration,
  > off the bootstrap path). Passing a lambda/capture to an FFI HOF
  > (`Enum.map(xs, (x) -> …)`) is unaffected — the application happens inside the
  > callee, and the value itself emits correctly.

  Inputs are the (would-be parser output) data:

      type = %{name: "Shape", variants: [
                 %{ctor: "Circle", fields: [%{label: "radius", type: "f64"}]},
                 %{ctor: "Square", fields: [%{label: "side",   type: "f64"}]}]}

      func = %{name: "area", params: [%{name: "shape", type: "Shape", cap: :val}], ret: "Float64",
               clauses: [%{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
                         %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}]}
  """
  alias Rian.Core
  alias Rian.Core.{PAtom, PCtor, PList, PLit, PTuple, PVar, PWild}

  alias Rian.Core.{
    EAtom,
    EBin,
    EBlock,
    ECall,
    ECapArg,
    ECapture,
    ECaptureNamed,
    ECase,
    EConstRef,
    EDot,
    EId,
    EIf,
    ELambda,
    EList,
    EMap,
    ENum,
    EStr,
    EStruct,
    ETuple,
    EUnary,
    EVariant,
    EWith
  }

  alias Rian.Exhaustiveness, as: E
  alias Rian.PatternLower, as: PL
  alias Rian.Pratt

  # ── Pipeline ───────────────────────────────────────────────────────────
  def compile(types, func, structs \\ []) do
    env = build_env(types, structs)
    :ok = check!(func, env)
    meta = build_meta(types)
    smeta = build_struct_meta(structs)

    %{
      elixir: to_elixir(func, types, structs, smeta),
      rust: to_rust(func, types, meta, structs, smeta)
    }
  end

  @doc "Compile to the BEAM target only (for functions using BEAM-only constructs)."
  def compile_beam(types, func, structs \\ []) do
    env = build_env(types, structs)
    :ok = check!(func, env)
    %{elixir: to_elixir(func, types, structs, build_struct_meta(structs))}
  end

  @doc """
  Compile a whole `%Rian.IR.Mod{}` to both targets: a `defmodule` (BEAM) and a
  `mod` (Rust), with its types/structs emitted once and each function wrapped at
  its declared visibility (`pub?` -> `def`/`pub fn`, else `defp`/private `fn`).
  """
  def compile_module(%Rian.IR.Mod{} = m) do
    %{elixir: module_elixir(m), rust: module_rust(m)}
  end

  @doc "Compile a module to the BEAM target only."
  def compile_module_beam(%Rian.IR.Mod{} = m), do: %{elixir: module_elixir(m)}

  defp module_elixir(%{name: name, types: types, structs: structs, funcs: funcs} = m) do
    env = build_env(types, structs)
    Enum.each(funcs, &(:ok = check!(&1, env)))
    consts = Map.get(m, :consts, [])
    ctx = ctx(build_meta(types), build_struct_meta(structs), const_set(consts))

    body =
      [
        ex_doc(Map.get(m, :doc), "moduledoc"),
        Enum.map_join(Map.get(m, :uses, []), "\n", &ex_use/1),
        Enum.map_join(structs, "\n", &ex_struct/1),
        Enum.map_join(types, "\n", &ex_typespec/1),
        Enum.map_join(consts, "\n", &ex_const(&1, ctx)),
        Enum.map_join(funcs, "\n", &elixir_clauses(&1, ctx, if(&1.pub?, do: "def", else: "defp")))
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    "defmodule #{name} do\n#{body}\nend"
  end

  # `@moduledoc`/`@doc`/`@typedoc "…"` — compile-time metadata (ADR-0051); the
  # content is a Markdown string emitted as a safe Elixir literal. `nil` -> none.
  defp ex_doc(nil, _attr), do: ""
  defp ex_doc(doc, attr), do: "@#{attr} #{inspect(doc)}"

  # rustdoc — `///` per item, `//!` for a module; one comment line per doc line
  defp rs_doc(nil, _prefix), do: ""

  defp rs_doc(doc, prefix),
    do: doc |> String.split("\n") |> Enum.map_join("\n", &"#{prefix} #{&1}")

  defp module_rust(%{name: name, types: types, structs: structs, funcs: funcs} = m) do
    env = build_env(types, structs)
    Enum.each(funcs, &(:ok = check!(&1, env)))
    consts = Map.get(m, :consts, [])
    # a signature table (name -> func) lets the Rust call-site borrow pass see
    # which params are `&[T]`/`&str` and which calls return owned values
    sigs = Map.new(funcs, fn f -> {f.name, f} end)
    ctx = ctx(build_meta(types), build_struct_meta(structs), const_set(consts), sigs)

    body =
      [
        rs_doc(Map.get(m, :doc), "//!"),
        Enum.map_join(Map.get(m, :uses, []), "\n", &rust_use/1),
        Enum.map_join(structs, "\n\n", &rust_struct/1),
        Enum.map_join(types, "\n\n", &rust_enum/1),
        Enum.map_join(consts, "\n", &rust_const(&1, ctx)),
        Enum.map_join(funcs, "\n\n", &rust_fn(&1, ctx, if(&1.pub?, do: "pub ", else: "")))
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    "mod #{PL.to_snake(name)} {\n#{body}\n}"
  end

  defp const_set(consts), do: MapSet.new(consts, & &1.name)

  # `use Path` -> `alias Path` (qualified); `use Path.(a, b)` -> `import Path`
  # (selective; name-level `only:` selectivity awaits cross-module arities).
  defp ex_use(%{path: path, names: []}), do: "alias #{path}"
  defp ex_use(%{path: path}), do: "import #{path}"

  # `use Path` -> `use a::b::c;`; `use Path.(a, b)` -> `use a::b::c::{a, b};`.
  defp rust_use(%{path: path, names: names}) do
    rp = path |> String.split(".") |> Enum.map_join("::", &to_string(PL.to_snake(&1)))
    if names == [], do: "use #{rp};", else: "use #{rp}::{#{Enum.join(names, ", ")}};"
  end

  # `const NAME Type := value` -> a 0-arity accessor on the BEAM (`def`/`defp`).
  defp ex_const(c, ctx) do
    def_kw = if c.pub?, do: "def", else: "defp"
    val = c.value |> body_ast(ctx) |> Core.from_expr() |> emit(:elixir) |> elem(0)
    "#{def_kw} #{PL.to_snake(c.name)}() do #{val} end"
  end

  # `const NAME Type := value` -> a Rust `const` (`pub const` when exported).
  defp rust_const(c, ctx) do
    vis = if c.pub?, do: "pub ", else: ""

    val =
      c.value
      |> body_ast(ctx)
      |> resolve_rust_pats(ctx.meta)
      |> Core.from_expr()
      |> emit(:rust)
      |> elem(0)

    "#{vis}const #{c.name}: #{prim_rust(c.type)} = #{val};"
  end

  # env / meta know the prelude types (e.g. `Option`) as well as the user's, so
  # `Some`/`None` resolve and `case` over them is exhaustiveness-checked — but the
  # prelude definitions are *not* emitted (they are built into each target).
  defp build_env(types, structs) do
    env =
      Enum.reduce(Rian.Prelude.with_prelude(types), E.base_env(), fn t, env ->
        variants = Enum.map(t.variants, fn v -> {PL.to_snake(v.ctor), length(v.fields)} end)
        E.add_type(env, PL.to_snake(t.name), variants)
      end)

    Enum.reduce(structs, env, fn s, env ->
      PL.add_struct(env, s.name, Enum.map(s.fields, &PL.to_snake(&1.label)))
    end)
  end

  # ctor_snake => %{enum: "Shape", labels: ["radius"], named: true}
  defp build_meta(types) do
    for t <- Rian.Prelude.with_prelude(types), v <- t.variants, into: %{} do
      labels = Enum.map(v.fields, &Map.get(&1, :label))
      named = v.fields != [] and Enum.all?(v.fields, &Map.get(&1, :label))
      {PL.to_snake(v.ctor), %{enum: t.name, ctor: v.ctor, labels: labels, named: named}}
    end
  end

  # struct_name => %{name: "Point", labels: ["x", "y"]} — keyed by the surface
  # (constructor) name so a `Name(args)` call in a body resolves to a struct lit.
  defp build_struct_meta(structs) do
    for s <- structs, into: %{} do
      {s.name, %{name: s.name, labels: Enum.map(s.fields, & &1.label)}}
    end
  end

  # Exhaustiveness GATE — emission only proceeds if the match is total & has no dead clauses.
  defp check!(func, env) do
    arity = length(hd(func.clauses).pats)

    clauses =
      Enum.map(func.clauses, fn c ->
        PL.lower_clause(%{pats: c.pats, guard: Map.get(c, :guard) != nil}, env)
      end)

    r = E.analyze(clauses, arity, env)

    cond do
      not r.exhaustive? ->
        raise "non-exhaustive `#{func.name}`: pattern `#{E.render(r.missing)}` not covered"

      r.unreachable != [] ->
        raise "unreachable clauses in `#{func.name}`: #{inspect(r.unreachable)}"

      true ->
        :ok
    end
  end

  # ── Elixir backend ─────────────────────────────────────────────────────
  def to_elixir(func, types, structs \\ [], smeta \\ %{}) do
    typespecs = Enum.map_join(types, "\n", &ex_typespec/1)
    struct_defs = Enum.map_join(structs, "\n", &ex_struct/1)
    ctx = ctx(build_meta(types), smeta, MapSet.new())

    [struct_defs, typespecs, elixir_clauses(func, ctx, "def")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # The resolution context threaded into every body: `meta` (sum-variant table),
  # `smeta` (struct table), `cset` (in-scope constant names).
  defp ctx(meta, smeta, cset, funs \\ %{}),
    do: %{meta: meta, smeta: smeta, cset: cset, funs: funs}

  # The `def`/`defp` clauses of one function (no type/struct preamble). `def_kw`
  # selects the visibility keyword (top-level is always `def`; inside a `mod` a
  # private function is `defp`).
  defp elixir_clauses(func, ctx, def_kw) do
    Enum.each(func.params, &Rian.Capability.beam_legal!(&1.cap))

    clauses =
      Enum.map_join(func.clauses, "\n", fn c ->
        head = "#{def_kw} #{func.name}(#{Enum.map_join(c.pats, ", ", &core_pat_ex/1)})"
        body = c.body |> body_ast(ctx) |> Core.from_expr() |> emit(:elixir) |> elem(0)
        "#{head}#{guard_str(c, :elixir)} do #{body} end"
      end)

    join_doc(ex_doc(Map.get(func, :doc), "doc"), clauses)
  end

  defp join_doc("", body), do: body
  defp join_doc(doc, body), do: doc <> "\n" <> body

  # Parse a body source and run the target-neutral resolution passes the emitter
  # relies on: struct construction, sum-variant construction, constant references.
  defp body_ast(src, ctx) do
    src
    |> Pratt.parse_body()
    |> resolve_structs(ctx.smeta)
    |> resolve_variants(ctx.meta)
    |> resolve_consts(ctx.cset)
  end

  # `struct Point(x Float64, y Float64)` -> a nested module carrying `defstruct`,
  # so `%Point{…}` construction and `p.x` access resolve on the BEAM.
  defp ex_struct(s) do
    fields = Enum.map_join(s.fields, ", ", fn f -> ":#{f.label}" end)
    "defmodule #{s.name} do defstruct [#{fields}] end"
  end

  # Rewrite a constructor-call `Name(v1, v2)` into a struct literal when `Name`
  # is a declared struct, zipping the positional args onto the field labels. The
  # struct meta is available here, so the emitter needs no ambient context.
  defp resolve_structs({:call, {:id, name}, args}, smeta) do
    case Map.fetch(smeta, name) do
      {:ok, %{labels: labels}} ->
        {:struct_lit, name, struct_pairs(name, labels, args, smeta)}

      :error ->
        {:call, {:id, name}, Enum.map(args, &resolve_structs(&1, smeta))}
    end
  end

  defp resolve_structs(node, smeta), do: Rian.Macro.map_node(node, &resolve_structs(&1, smeta))

  # Rewrite a sum-variant constructor — a call `Ctor(args)` or a bare nullary
  # `Ctor` — into a `{:variant_lit, …}` node carrying the enum/labels/named info
  # from `meta`, so the emitter spells it per target (a tagged tuple/atom on the
  # BEAM, an `Enum::Variant {…}` on Rust) without ambient context.
  defp resolve_variants({:call, {:id, name}, args}, meta) do
    case variant_info(meta, name) do
      nil -> {:call, {:id, name}, Enum.map(args, &resolve_variants(&1, meta))}
      info -> variant_lit(info, variant_pairs(info, args, meta))
    end
  end

  defp resolve_variants({:id, name} = node, meta) do
    case variant_info(meta, name) do
      %{labels: []} = info -> variant_lit(info, [])
      _ -> node
    end
  end

  defp resolve_variants(node, meta), do: Rian.Macro.map_node(node, &resolve_variants(&1, meta))

  defp variant_info(meta, name) when is_binary(name) do
    if pascal?(name), do: Map.get(meta, PL.to_snake(name)), else: nil
  end

  defp variant_lit(info, pairs),
    do: {:variant_lit, info.enum, info.ctor, info.named, pairs}

  # `{label_or_nil, value}` pairs in declared field order — positional args zip
  # onto the labels; all-named args (`radius: …`) are placed by name.
  defp variant_pairs(info, args, meta) do
    cond do
      args != [] and Enum.all?(args, &match?({:label, _, _}, &1)) ->
        given = Map.new(args, fn {:label, l, e} -> {l, resolve_variants(e, meta)} end)
        Enum.map(info.labels, fn l -> {l, Map.fetch!(given, l)} end)

      Enum.any?(args, &match?({:label, _, _}, &1)) ->
        raise("variant #{info.ctor}: mix of positional and named fields")

      true ->
        Enum.zip(info.labels, Enum.map(args, &resolve_variants(&1, meta)))
    end
  end

  # Rewrite a reference to an in-scope constant (`{:id, NAME}`) into a
  # `{:const_ref, NAME}` node, so the emitter spells it per target (a BEAM
  # accessor call vs. a Rust `const` name) without needing ambient context.
  defp resolve_consts({:id, name} = node, cset) do
    if MapSet.member?(cset, name), do: {:const_ref, name}, else: node
  end

  defp resolve_consts(node, cset), do: Rian.Macro.map_node(node, &resolve_consts(&1, cset))

  # Build the `{label, value}` pairs of a struct literal. All-positional args zip
  # onto the declared field order; all-named args (`x: …`) are placed by name (so
  # source order is free); a mix is rejected.
  defp struct_pairs(name, labels, args, smeta) do
    cond do
      Enum.all?(args, &match?({:label, _, _}, &1)) and args != [] ->
        given = Map.new(args, fn {:label, l, e} -> {l, resolve_structs(e, smeta)} end)
        extra = Map.keys(given) -- labels
        if extra != [], do: raise("struct #{name}: unknown field(s) #{inspect(extra)}")

        Enum.map(labels, fn l ->
          case Map.fetch(given, l) do
            {:ok, v} -> {l, v}
            :error -> raise("struct #{name}: missing field `#{l}`")
          end
        end)

      Enum.any?(args, &match?({:label, _, _}, &1)) ->
        raise("struct #{name}: mix of positional and named fields")

      true ->
        Enum.zip(labels, Enum.map(args, &resolve_structs(&1, smeta)))
    end
  end

  # Optional clause guard: `nil` or a Rian guard-expression string. Lowers to
  # `when …` on Elixir and `if …` on Rust (clauses-guards §5).
  defp guard_str(c, target, deref \\ []) do
    case Map.get(c, :guard) do
      g when is_binary(g) ->
        # On Rust, a binder bound inside a slice/list element is a `&T` borrow
        # (match ergonomics); a guard comparing it (`*c == 32`) must deref it.
        ast = Pratt.parse(g) |> deref_ids(deref)
        guard_kw(target) <> (emit(Core.from_expr(ast), target) |> elem(0))

      _ ->
        ""
    end
  end

  # rename `{:id, n}` -> `{:id, "*n"}` for each `n` in `names` (Rust guard deref)
  defp deref_ids(ast, []), do: ast
  defp deref_ids({:id, n}, names), do: if(n in names, do: {:id, "*" <> n}, else: {:id, n})

  defp deref_ids(t, names) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.map(&deref_ids(&1, names)) |> List.to_tuple()

  defp deref_ids(l, names) when is_list(l), do: Enum.map(l, &deref_ids(&1, names))
  defp deref_ids(other, _names), do: other

  defp guard_kw(:elixir), do: " when "
  defp guard_kw(:rust), do: " if "

  # A Rust match arm needs braces around a multi-statement block body; a single
  # expression (the `:= expr` case) is emitted bare.
  defp rust_arm_body(%EBlock{stmts: [_, _ | _]}, s), do: "{ #{s} }"
  defp rust_arm_body(_, s), do: s

  defp case_guard(nil, _), do: ""
  defp case_guard(g, target), do: guard_kw(target) <> (emit(g, target) |> elem(0))

  # Resolve every `case` arm pattern in a body to its Rust spelling using the
  # type meta, storing it back into the IR as `{:rpat, str}`. After this pass the
  # Rust emitter needs no ambient meta — the IR carries the resolution.
  defp resolve_rust_pats({:case, scrut, arms}, meta) do
    {:case, resolve_rust_pats(scrut, meta),
     Enum.map(arms, fn {pt, g, b} ->
       {{:rpat, core_pat_rs(pt, meta)}, g && resolve_rust_pats(g, meta),
        resolve_rust_pats(b, meta)}
     end)}
  end

  defp resolve_rust_pats({:with, clauses, body, els}, meta) do
    {:with,
     Enum.map(clauses, fn {pt, e} ->
       {{:rpat, core_pat_rs(pt, meta)}, resolve_rust_pats(e, meta)}
     end), resolve_rust_pats(body, meta),
     Enum.map(els, fn {pt, g, b} ->
       {{:rpat, core_pat_rs(pt, meta)}, g && resolve_rust_pats(g, meta),
        resolve_rust_pats(b, meta)}
     end)}
  end

  defp resolve_rust_pats(node, meta), do: Rian.Macro.map_node(node, &resolve_rust_pats(&1, meta))

  # Rust call-site borrow pass (ADR-0047): when an argument *produces* an owned
  # value (a `Vec`/`String` from a constructor or a value-returning call) but the
  # callee's parameter is a borrow (`&[T]`/`&str`), wrap it in `&` so it coerces.
  # A bare variable is left alone — it is already the borrow the param expects.
  defp insert_borrows({:call, {:id, name} = fun, args}, funs) do
    args = Enum.map(args, &insert_borrows(&1, funs))

    case param_rtypes(name, funs) do
      nil ->
        {:call, fun, args}

      ptypes ->
        borrowed =
          args
          |> Enum.zip(ptypes)
          |> Enum.map(fn {a, pt} ->
            if borrow_type?(pt) and owned_arg?(a, funs), do: {:unary, "&", a}, else: a
          end)

        {:call, fun, borrowed}
    end
  end

  defp insert_borrows(node, funs), do: Rian.Macro.map_node(node, &insert_borrows(&1, funs))

  # the callee's parameter Rust types, or nil when the callee is unknown (an
  # external/primitive call — leave its args untouched)
  defp param_rtypes(name, funs) do
    case Map.get(funs, name) do
      %{params: ps} -> Enum.map(ps, fn p -> Rian.Capability.rust_param(p.cap, p.type) end)
      _ -> nil
    end
  end

  defp borrow_type?("&" <> _), do: true
  defp borrow_type?(_), do: false

  # does this argument expression produce an owned `Vec`/`String`?
  defp owned_arg?({:list_lit, _, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_from_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_concat"}, _}, _funs), do: true

  defp owned_arg?({:call, {:id, name}, _}, funs) do
    case Map.get(funs, name) do
      %{ret: ret} -> owned_rtype?(ret)
      _ -> false
    end
  end

  defp owned_arg?(_node, _funs), do: false

  defp owned_rtype?("Vec(" <> _), do: true
  defp owned_rtype?("String"), do: true
  defp owned_rtype?(_), do: false

  defp rpat({:rpat, s}), do: s
  defp rpat(pat), do: pat_rs(pat, %{})

  # Rust `with` lowering: a right-nested `match` chain. Each clause matches its
  # ok-pattern and continues, or falls through to the `else` arms (or yields the
  # non-matching value `__w` when there is no `else`) — the `?`-expansion.
  defp with_chain_rs([], body, _else_rs), do: "{ #{body} }"

  defp with_chain_rs([{pt, e} | rest], body, else_rs) do
    fallback = if else_rs == "", do: "__w => __w,", else: "__w => match __w { #{else_rs} },"
    "match #{p(e, 0, :rust)} { #{rpat(pt)} => #{with_chain_rs(rest, body, else_rs)} #{fallback} }"
  end

  # ── `&` capture support ────────────────────────────────────────────────
  # Highest placeholder index in an anonymous-capture body → the closure arity
  # the Rust target must spell out (`&(&1 + &2)` ⇒ 2 ⇒ `|a1, a2| …`).
  defp cap_arity(%ECapArg{n: n}), do: n
  defp cap_arity(%EBin{left: l, right: r}), do: max(cap_arity(l), cap_arity(r))
  defp cap_arity(%EUnary{arg: x}), do: cap_arity(x)
  defp cap_arity(%EDot{head: o}), do: cap_arity(o)

  defp cap_arity(%EIf{cond: c, then: t, else: e}),
    do: max(cap_arity(c), max(cap_arity(t), cap_arity(e)))

  defp cap_arity(%ECall{fun: f, args: args}),
    do: Enum.reduce([f | args], 0, fn n, acc -> max(cap_arity(n), acc) end)

  defp cap_arity(%EList{elems: es, tail: tail}) do
    base = Enum.reduce(es, 0, fn e, acc -> max(cap_arity(e), acc) end)
    if tail == :close, do: base, else: max(base, cap_arity(tail))
  end

  defp cap_arity(%EMap{pairs: ps}),
    do: Enum.reduce(ps, 0, fn {_, v}, acc -> max(cap_arity(v), acc) end)

  defp cap_arity(_), do: 0

  # "aFrom, …, aTo" — empty when the range is empty (a nullary closure).
  defp closure_params(from, to) when to < from, do: ""
  defp closure_params(from, to), do: Enum.map_join(from..to, ", ", &"a#{&1}")

  defp ex_typespec(t) do
    body =
      Enum.map_join(t.variants, " | ", fn v ->
        tag = ":" <> Atom.to_string(PL.to_snake(v.ctor))

        case v.fields do
          [] -> tag
          fs -> "{#{tag}, #{Enum.map_join(fs, ", ", &prim_ex(&1.type))}}"
        end
      end)

    join_doc(ex_doc(Map.get(t, :doc), "typedoc"), "@type #{PL.to_snake(t.name)} :: #{body}")
  end

  # surface pattern -> typed core IR -> Elixir (ADR-0050: emitter consumes the core)
  defp core_pat_ex(surface), do: pat_ex(Core.from_pat(surface))

  defp pat_ex(%PWild{}), do: "_"
  defp pat_ex(%PVar{name: x}), do: x
  defp pat_ex(%PLit{value: v}) when is_binary(v), do: inspect(v)
  defp pat_ex(%PLit{value: v}), do: to_string(v)
  defp pat_ex(%PAtom{name: a}), do: ":" <> a
  defp pat_ex(%PTuple{elems: ps}), do: "{#{Enum.map_join(ps, ", ", &pat_ex/1)}}"
  defp pat_ex(%PList{elems: ps, tail: :close}), do: "[#{Enum.map_join(ps, ", ", &pat_ex/1)}]"

  defp pat_ex(%PList{elems: ps, tail: t}),
    do: "[#{Enum.map_join(ps, ", ", &pat_ex/1)} | #{pat_ex(t)}]"

  defp pat_ex(%PCtor{ctor: name, args: []}), do: ":" <> Atom.to_string(PL.to_snake(name))

  defp pat_ex(%PCtor{ctor: name, args: args}),
    do: "{:#{PL.to_snake(name)}, #{Enum.map_join(args, ", ", &pat_ex/1)}}"

  # ── Rust backend ───────────────────────────────────────────────────────
  def to_rust(func, types, meta, structs \\ [], smeta \\ %{}) do
    enums = Enum.map_join(types, "\n\n", &rust_enum/1)
    struct_defs = Enum.map_join(structs, "\n\n", &rust_struct/1)

    [struct_defs, enums, rust_fn(func, ctx(meta, smeta, MapSet.new()), "")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # One Rust `fn` (no type/struct preamble). `vis` is `""` or `"pub "`.
  defp rust_fn(func, ctx, vis) do
    param_decls =
      Enum.map_join(func.params, ", ", fn p ->
        "#{p.name}: #{Rian.Capability.rust_param(p.cap, p.type)}"
      end)

    # One param matches the value directly; N>1 match the tuple of arguments
    # (clauses-guards §5.2). A `val Vec` param lowers to a `&[T]` slice, so cons
    # patterns match it directly; an `iso Vec` param is an owned `Vec<T>`, so it
    # is matched via `.as_slice()` and its binders are made owned again
    # (`rust_rebinds/2`) — letting a cons function *return* or *rebuild* a list
    # (e.g. `cat`) lower with owned semantics (ADR-0047).
    iso = iso_cons_positions(func)
    scrut = rust_scrut(func.params, iso)

    arms =
      Enum.map_join(func.clauses, "\n", fn c ->
        pat = tuple_or_one(c.pats, &core_pat_rs(&1, ctx.meta))
        # Resolve construction (struct + variant), constant references, and `case`
        # patterns on the surface (where the meta is available), then translate to
        # the typed core IR the emitter consumes (ADR-0050).
        ast =
          c.body
          |> body_ast(ctx)
          |> resolve_rust_pats(ctx.meta)
          |> insert_borrows(Map.get(ctx, :funs, %{}))
          |> Core.from_expr()

        body = emit(ast, :rust) |> elem(0)
        rebinds = arm_rebinds(c.pats, iso)

        arm =
          if rebinds == [],
            do: rust_arm_body(ast, body),
            else: "{ #{Enum.join(rebinds, " ")} #{body} }"

        # binders bound inside a list/slice element are `&T` — a guard over them
        # must deref (`*c`); the arm body's arithmetic works on `&T` directly
        deref = Enum.flat_map(c.pats, fn p -> slice_elem_vars(Core.from_pat(p)) end)
        "        #{pat}#{guard_str(c, :rust, deref)} => #{arm},"
      end)

    fn_str =
      "#{vis}fn #{func.name}(#{param_decls}) -> #{rust_ret(func.ret)} {\n" <>
        "    match #{scrut} {\n#{arms}\n    }\n}"

    join_doc(rs_doc(Map.get(func, :doc), "///"), fn_str)
  end

  # param positions that are an owned `iso Vec` destructured by a list/cons
  # pattern — those match `param.as_slice()` and get owned rebinds in each arm
  defp iso_cons_positions(func) do
    func.params
    |> Enum.with_index()
    |> Enum.filter(fn {p, i} ->
      p.cap == :iso and match?("Vec(" <> _, p.type) and
        Enum.any?(func.clauses, fn c -> match?(%PList{}, Core.from_pat(Enum.at(c.pats, i))) end)
    end)
    |> Enum.map(fn {_, i} -> i end)
    |> MapSet.new()
  end

  defp rust_scrut(params, iso) do
    parts =
      params
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        if MapSet.member?(iso, i), do: "#{p.name}.as_slice()", else: p.name
      end)

    case parts do
      [one] -> one
      many -> "(#{Enum.join(many, ", ")})"
    end
  end

  # Make a cons clause's borrowed binders owned at arm entry, so the body uses
  # them uniformly (insert into a `Vec`, comparisons, etc.). A **head** bound in
  # a slice element is a `&T` borrow → `clone()` (works for `Copy` and non-`Copy`
  # alike); this applies to *every* cons clause. A **tail** is a `&[T]` slice;
  # only `iso` (owned-`Vec`) params rebind it via `to_vec()`, since `val` params
  # keep the slice for zero-copy recursion.
  defp arm_rebinds(pats, iso) do
    pats
    |> Enum.with_index()
    |> Enum.flat_map(fn {pat, i} ->
      core = Core.from_pat(pat)
      heads = Enum.map(slice_elem_vars(core), &"let #{&1} = #{&1}.clone();")
      tails = if MapSet.member?(iso, i), do: cons_tail_rebinds(core), else: []
      heads ++ tails
    end)
  end

  defp cons_tail_rebinds(%PList{tail: %PVar{name: n}}), do: ["let #{n} = #{n}.to_vec();"]
  defp cons_tail_rebinds(_), do: []

  # variables bound inside the *element* positions of a list pattern — under a
  # slice match they are `&T` borrows, so a guard comparing them needs `*`
  defp slice_elem_vars(%PList{elems: ps}), do: Enum.flat_map(ps, &all_pat_vars/1)
  defp slice_elem_vars(_), do: []

  defp all_pat_vars(%PVar{name: n}), do: [n]
  defp all_pat_vars(%PCtor{args: a}), do: Enum.flat_map(a, &all_pat_vars/1)
  defp all_pat_vars(%PTuple{elems: e}), do: Enum.flat_map(e, &all_pat_vars/1)

  defp all_pat_vars(%PList{elems: ps, tail: t}),
    do: Enum.flat_map(ps, &all_pat_vars/1) ++ all_pat_vars(t)

  defp all_pat_vars(_), do: []

  # `T | E` in return position is sugar for `Result(T, E)` (ADR-0040 §2) — the ok
  # type then the (single, possibly-named) error set. It lowers to Rust
  # `Result<T, E>`; on the BEAM the value shape `{:ok,_}`/`{:error,_}` carries it.
  defp rust_ret(ret) do
    case result_parts(ret) do
      {:plain, t} -> prim_rust(t)
      {:result, ok, err} -> "Result<#{prim_rust(ok)}, #{prim_rust(err)}>"
    end
  end

  defp result_parts(ret) do
    case ret |> String.split("|") |> Enum.map(&String.trim/1) do
      [_single] ->
        {:plain, ret}

      [ok, err] ->
        {:result, ok, err}

      parts ->
        raise "inline multi-tag error set must be named (ADR-0040): #{Enum.join(parts, " | ")}"
    end
  end

  defp rust_struct(s) do
    fields = Enum.map_join(s.fields, ", ", fn f -> "#{f.label}: #{prim_rust(f.type)}" end)
    "#[derive(Clone, Debug, PartialEq)]\nstruct #{s.name} { #{fields} }"
  end

  defp tuple_or_one([one], f), do: f.(one)
  defp tuple_or_one(many, f), do: "(" <> Enum.map_join(many, ", ", f) <> ")"

  defp rust_enum(t) do
    variants =
      Enum.map_join(t.variants, "\n", fn v ->
        named = v.fields != [] and Enum.all?(v.fields, &Map.get(&1, :label))

        cond do
          v.fields == [] ->
            "    #{v.ctor},"

          named ->
            fs = Enum.map_join(v.fields, ", ", fn f -> "#{f.label}: #{prim_rust(f.type)}" end)
            "    #{v.ctor} { #{fs} },"

          true ->
            fs = Enum.map_join(v.fields, ", ", &prim_rust(&1.type))
            "    #{v.ctor}(#{fs}),"
        end
      end)

    join_doc(
      rs_doc(Map.get(t, :doc), "///"),
      "#[derive(Clone, Debug, PartialEq)]\nenum #{t.name} {\n#{variants}\n}"
    )
  end

  # surface pattern -> typed core IR -> Rust (ADR-0050: emitter consumes the core)
  defp core_pat_rs(surface, meta), do: pat_rs(Core.from_pat(surface), meta)

  defp pat_rs(%PWild{}, _), do: "_"
  defp pat_rs(%PVar{name: x}, _), do: x
  defp pat_rs(%PLit{value: v}, _) when is_binary(v), do: inspect(v)
  defp pat_rs(%PLit{value: v}, _), do: to_string(v)
  defp pat_rs(%PTuple{elems: [%PAtom{name: "ok"}, p]}, m), do: "Ok(#{pat_rs(p, m)})"
  defp pat_rs(%PTuple{elems: [%PAtom{name: "error"}, p]}, m), do: "Err(#{pat_rs(p, m)})"
  defp pat_rs(%PTuple{elems: ps}, m), do: "(#{Enum.map_join(ps, ", ", &pat_rs(&1, m))})"
  defp pat_rs(%PAtom{name: a}, _), do: raise("Erlang atom pattern is BEAM-only: :#{a}")

  defp pat_rs(%PList{elems: ps, tail: :close}, m),
    do: "[#{Enum.map_join(ps, ", ", &pat_rs(&1, m))}]"

  # a cons pattern `[h, … | t]` is a Rust slice pattern `[h, …, t @ ..]` (matched
  # against a `&[T]`); the binders are made owned again by `rust_rebinds/1`
  # (ADR-0047 — Rian cons over a Vec/slice)
  defp pat_rs(%PList{elems: ps, tail: tail}, m) do
    heads = Enum.map(ps, &pat_rs(&1, m))
    "[#{Enum.join(heads ++ [rest_pat_rs(tail)], ", ")}]"
  end

  defp pat_rs(%PCtor{ctor: name, args: []}, meta) do
    info = Map.fetch!(meta, PL.to_snake(name))
    "#{info.enum}::#{info.ctor}"
  end

  defp pat_rs(%PCtor{ctor: name, args: args}, meta) do
    info = Map.fetch!(meta, PL.to_snake(name))

    if info.named do
      fields =
        info.labels
        |> Enum.zip(args)
        |> Enum.map_join(", ", fn {lbl, p} -> "#{lbl}: #{pat_rs(p, meta)}" end)

      "#{info.enum}::#{info.ctor} { #{fields} }"
    else
      "#{info.enum}::#{info.ctor}(#{Enum.map_join(args, ", ", &pat_rs(&1, meta))})"
    end
  end

  # the cons-tail of a Rust slice pattern: `t @ ..` binds the rest as `&[T]`
  defp rest_pat_rs(%PVar{name: n}), do: "#{n} @ .."
  defp rest_pat_rs(%PWild{}), do: ".."

  defp rest_pat_rs(other),
    do: raise("Rust cons tail must be a variable or `_`: #{inspect(other)}")

  # ── Expression emission (precedence-aware, target-specific) ────────────
  @doc "Emit a single Rian expression string to :elixir or :rust."
  def emit_expr(src, target), do: emit(Core.from_expr(Rian.Pratt.parse(src)), target) |> elem(0)

  @doc "Emit an already-built AST (e.g. after macro expansion / comptime folding)."
  def emit_ast(ast, target), do: emit(Core.from_expr(ast), target) |> elem(0)

  # emit/2 -> {string, prec}; p/3 wraps in parens when prec < ctx.
  defp p(node, ctx, t) do
    {s, pr} = emit(node, t)
    if pr < ctx, do: "(" <> s <> ")", else: s
  end

  defp emit(%ENum{text: n}, _t), do: {n, 12}
  # string literal — same surface on both targets (Rust yields `&str`)
  defp emit(%EStr{value: s}, _t), do: {"\"#{s}\"", 12}
  defp emit(%EId{name: "pi"}, :elixir), do: {":math.pi()", 12}
  defp emit(%EId{name: "pi"}, :rust), do: {"std::f64::consts::PI", 12}
  defp emit(%EId{name: x}, _t), do: {x, 12}
  # atom literal / Erlang FFI (BEAM-only on Rust)
  defp emit(%EAtom{name: a}, :elixir), do: {":" <> a, 12}
  defp emit(%EAtom{name: a}, :rust), do: raise("Erlang atom is BEAM-only: :#{a}")
  defp emit(%EDot{head: %EAtom{name: m}, name: n}, :elixir), do: {":#{m}.#{n}", 12}
  defp emit(%EDot{head: %EAtom{name: m}}, :rust), do: raise("Erlang FFI is BEAM-only: :#{m}")

  # dotted access: Elixir uses `.` for both module calls and field access
  defp emit(%EDot{head: head, name: n}, :elixir), do: {p(head, 12, :elixir) <> ".#{n}", 12}

  # Rust: case of head/name selects field vs module-path vs type/variant-path
  defp emit(%EDot{head: %EId{name: m}, name: n}, :rust) do
    cond do
      # value.field
      not pascal?(m) -> {"#{m}.#{n}", 12}
      # Type::Variant
      pascal?(n) -> {"#{m}::#{n}", 12}
      # module::fn
      true -> {"#{String.downcase(m)}::#{n}", 12}
    end
  end

  defp emit(%EDot{head: head, name: n}, :rust), do: {p(head, 12, :rust) <> "::#{n}", 12}

  # `String` primitives on Rust (ADR-0047 §2): a `String` is `&str`, codepoints
  # are `i64`; these mirror the BEAM/JS lowerings so portable `Str` ops compose.
  defp emit(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}, :rust),
    do: {"#{p(s, 12, :rust)}.chars().map(|c| c as i64).collect::<Vec<i64>>()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}, :rust),
    do:
      {"#{p(cs, 12, :rust)}.iter().map(|c| char::from_u32(*c as u32).unwrap()).collect::<String>()",
       12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}, :rust),
    do: {"format!(\"{}{}\", #{p(a, 0, :rust)}, #{p(b, 0, :rust)})", 12}

  defp emit(%ECall{fun: f, args: args}, t),
    do: {p(f, 12, t) <> "(" <> Enum.map_join(args, ", ", &p(&1, 0, t)) <> ")", 12}

  # `&` captures (B'). Placeholders: Elixir's native `&N`, Rust's closure args `aN`.
  defp emit(%ECapArg{n: n}, :elixir), do: {"&#{n}", 12}
  defp emit(%ECapArg{n: n}, :rust), do: {"a#{n}", 12}

  # `&(&1 + &2)` — Elixir's native capture; Rust an explicit closure `|a1, a2| …`.
  defp emit(%ECapture{body: body}, :elixir), do: {"&(#{p(body, 0, :elixir)})", 12}

  defp emit(%ECapture{body: body}, :rust) do
    {"|#{closure_params(1, cap_arity(body))}| #{p(body, 0, :rust)}", 12}
  end

  # `&name/arity` — Elixir's native capture; Rust a forwarding closure.
  defp emit(%ECaptureNamed{path: path, arity: arity}, :elixir),
    do: {"&#{p(path, 12, :elixir)}/#{arity}", 12}

  defp emit(%ECaptureNamed{path: path, arity: arity}, :rust) do
    ps = closure_params(0, arity - 1)
    {"|#{ps}| #{p(path, 12, :rust)}(#{ps})", 12}
  end

  defp emit(%EUnary{op: "-", arg: x}, t), do: {"-" <> p(x, 11, t), 11}
  defp emit(%EUnary{op: "not", arg: x}, :elixir), do: {"not " <> p(x, 11, :elixir), 11}
  defp emit(%EUnary{op: "not", arg: x}, :rust), do: {"!" <> p(x, 11, :rust), 11}
  # `&` is injected by the call-site borrow pass (Rust only) — never parsed
  defp emit(%EUnary{op: "&", arg: x}, :rust), do: {"&" <> p(x, 11, :rust), 11}

  # lambdas — Elixir anonymous fn, Rust closure
  defp emit(%ELambda{params: params, body: body}, :elixir) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"fn #{ps} -> #{p(body, 0, :elixir)} end", 12}
  end

  defp emit(%ELambda{params: params, body: body}, :rust) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"|#{ps}| #{p(body, 0, :rust)}", 12}
  end

  # if-expression
  defp emit(%EIf{cond: c, then: t, else: e}, :elixir),
    do:
      {"if #{p(c, 0, :elixir)} do #{emit_block(t, :elixir)} else #{emit_block(e, :elixir)} end",
       0}

  defp emit(%EIf{cond: c, then: t, else: e}, :rust),
    do: {"if #{p(c, 0, :rust)} { #{emit_block(t, :rust)} } else { #{emit_block(e, :rust)} }", 0}

  defp emit(%EBlock{} = b, t), do: {emit_block(b, t), 0}

  # case expression — Elixir `case … do … -> … end`; Rust `match … { … => …, }`
  defp emit(%ECase{scrut: scrut, arms: arms}, :elixir) do
    body =
      Enum.map_join(arms, "; ", fn {pt, g, b} ->
        "#{pat_ex(pt)}#{case_guard(g, :elixir)} -> #{p(b, 0, :elixir)}"
      end)

    {"case #{p(scrut, 0, :elixir)} do #{body} end", 0}
  end

  defp emit(%ECase{scrut: scrut, arms: arms}, :rust) do
    body =
      Enum.map_join(arms, " ", fn {pt, g, b} ->
        "#{rpat(pt)}#{case_guard(g, :rust)} => #{p(b, 0, :rust)},"
      end)

    {"match #{p(scrut, 0, :rust)} { #{body} }", 0}
  end

  # with expression — Elixir native `with`/`else`; Rust nested `match` chain that
  # short-circuits to the `else` arms (or yields the non-matching value).
  defp emit(%EWith{clauses: clauses, body: body, els: els}, :elixir) do
    cs = Enum.map_join(clauses, ", ", fn {pt, e} -> "#{pat_ex(pt)} <- #{p(e, 0, :elixir)}" end)

    else_str =
      if els == [],
        do: "",
        else:
          " else " <>
            Enum.map_join(els, "; ", fn {pt, g, b} ->
              "#{pat_ex(pt)}#{case_guard(g, :elixir)} -> #{p(b, 0, :elixir)}"
            end)

    {"with #{cs} do #{emit_block(body, :elixir)}#{else_str} end", 0}
  end

  defp emit(%EWith{clauses: clauses, body: body, els: els}, :rust) do
    else_rs =
      Enum.map_join(els, " ", fn {pt, g, b} ->
        "#{rpat(pt)}#{case_guard(g, :rust)} => #{p(b, 0, :rust)},"
      end)

    {with_chain_rs(clauses, emit_block(body, :rust), else_rs), 0}
  end

  # list / map literals
  defp emit(%EList{elems: elems, tail: :close}, :elixir),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir))}]", 12}

  defp emit(%EList{elems: elems, tail: tl}, :elixir),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir))} | #{p(tl, 0, :elixir)}]", 12}

  defp emit(%EList{elems: elems, tail: :close}, :rust),
    do: {"vec![#{Enum.map_join(elems, ", ", &p(&1, 0, :rust))}]", 12}

  # cons `[e1, …, en | tail]` -> prepend onto an owned copy of the tail
  # (`.to_vec()` turns the `&[T]` slice — or a `Vec` — into an owned `Vec`), in
  # reverse so the result order is `e1, …, en, tail…` (ADR-0047)
  defp emit(%EList{elems: elems, tail: tl}, :rust) do
    prepends =
      elems
      |> Enum.reverse()
      |> Enum.map_join(" ", fn e -> "__v.insert(0, #{p(e, 0, :rust)});" end)

    {"{ let mut __v = #{p(tl, 12, :rust)}.to_vec(); #{prepends} __v }", 0}
  end

  defp emit(%EMap{pairs: pairs}, :elixir),
    do: {"%{#{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :elixir)}" end)}}", 12}

  defp emit(%EMap{}, :rust), do: raise("map literals are BEAM-only in PoC")

  # constant reference — a 0-arity accessor call on the BEAM, the `const` name on Rust
  defp emit(%EConstRef{name: name}, :elixir), do: {"#{PL.to_snake(name)}()", 12}
  defp emit(%EConstRef{name: name}, :rust), do: {name, 12}

  # tuple literal — a BEAM tuple / a Rust tuple. The `{:ok, v}` / `{:error, e}`
  # shapes are the canonical Result surface (ADR-0040): they keep their tagged
  # tuple on the BEAM but lower to Rust `Ok(…)` / `Err(…)`.
  defp emit(%ETuple{elems: [%EAtom{name: "ok"}, v]}, :rust), do: {"Ok(#{p(v, 0, :rust)})", 12}
  defp emit(%ETuple{elems: [%EAtom{name: "error"}, e]}, :rust), do: {"Err(#{p(e, 0, :rust)})", 12}
  defp emit(%ETuple{elems: es}, :rust), do: {"(#{Enum.map_join(es, ", ", &p(&1, 0, :rust))})", 12}

  defp emit(%ETuple{elems: es}, :elixir),
    do: {"{#{Enum.map_join(es, ", ", &p(&1, 0, :elixir))}}", 12}

  # sum-variant construction — a snake atom / tagged tuple on the BEAM (labels
  # erased), an `Enum::Variant` path on Rust (named `{…}` or positional `(…)`).
  defp emit(%EVariant{ctor: ctor, pairs: []}, :elixir),
    do: {":" <> Atom.to_string(PL.to_snake(ctor)), 12}

  defp emit(%EVariant{ctor: ctor, pairs: pairs}, :elixir) do
    vals = Enum.map_join(pairs, ", ", fn {_l, v} -> p(v, 0, :elixir) end)
    {"{:#{PL.to_snake(ctor)}, #{vals}}", 12}
  end

  defp emit(%EVariant{enum: enum, ctor: ctor, pairs: []}, :rust), do: {"#{enum}::#{ctor}", 12}

  defp emit(%EVariant{enum: enum, ctor: ctor, named: true, pairs: pairs}, :rust) do
    fields = Enum.map_join(pairs, ", ", fn {l, v} -> "#{l}: #{p(v, 0, :rust)}" end)
    {"#{enum}::#{ctor} { #{fields} }", 12}
  end

  defp emit(%EVariant{enum: enum, ctor: ctor, named: false, pairs: pairs}, :rust) do
    {"#{enum}::#{ctor}(#{Enum.map_join(pairs, ", ", fn {_l, v} -> p(v, 0, :rust) end)})", 12}
  end

  # struct literal — `%Name{x: …}` on the BEAM, `Name { x: … }` on Rust
  defp emit(%EStruct{name: name, pairs: pairs}, :elixir),
    do:
      {"%#{name}{#{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :elixir)}" end)}}",
       12}

  defp emit(%EStruct{name: name, pairs: pairs}, :rust),
    do:
      {"#{name} { #{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :rust)}" end)} }",
       12}

  # pipe: native on Elixir, structural call on Rust
  defp emit(%EBin{op: "|>", left: l, right: r}, :elixir),
    do: {p(l, prec("|>"), :elixir) <> " |> " <> p(r, prec("|>") + 1, :elixir), prec("|>")}

  defp emit(%EBin{op: "|>", left: l, right: r}, :rust), do: emit(pipe_to_call(l, r), :rust)

  # concat: native <> on Elixir, flattened format! on Rust
  defp emit(%EBin{op: "<>", left: l, right: r}, :elixir),
    do: {p(l, prec("<>") + 1, :elixir) <> " <> " <> p(r, prec("<>"), :elixir), prec("<>")}

  defp emit(%EBin{op: "<>"} = node, :rust) do
    parts = flatten_concat(node)
    fmt = String.duplicate("{}", length(parts))
    {"format!(\"#{fmt}\", #{Enum.map_join(parts, ", ", &p(&1, 0, :rust))})", 12}
  end

  # integer div / rem
  defp emit(%EBin{op: "div", left: l, right: r}, :elixir),
    do: {"div(#{p(l, 0, :elixir)}, #{p(r, 0, :elixir)})", 12}

  defp emit(%EBin{op: "rem", left: l, right: r}, :elixir),
    do: {"rem(#{p(l, 0, :elixir)}, #{p(r, 0, :elixir)})", 12}

  defp emit(%EBin{op: "div", left: l, right: r}, :rust),
    do: {p(l, prec("div"), :rust) <> " / " <> p(r, prec("div") + 1, :rust), prec("div")}

  defp emit(%EBin{op: "rem", left: l, right: r}, :rust),
    do: {p(l, prec("rem"), :rust) <> " % " <> p(r, prec("rem") + 1, :rust), prec("rem")}

  # float division: native on Elixir, explicit f64 cast on Rust
  defp emit(%EBin{op: "/", left: l, right: r}, :elixir),
    do: {p(l, prec("/"), :elixir) <> " / " <> p(r, prec("/") + 1, :elixir), prec("/")}

  defp emit(%EBin{op: "/", left: l, right: r}, :rust),
    do: {"(#{p(l, 0, :rust)} as f64) / (#{p(r, 0, :rust)} as f64)", 10}

  # generic binary (arith, comparison, and/or) — MUST be last
  defp emit(%EBin{op: op, left: l, right: r}, t) do
    pr = prec(op)

    {lc, rc} =
      case assoc(op) do
        :left -> {pr, pr + 1}
        :right -> {pr + 1, pr}
        :none -> {pr + 1, pr + 1}
      end

    {p(l, lc, t) <> " " <> disp(op, t) <> " " <> p(r, rc, t), pr}
  end

  defp emit_block(%EBlock{stmts: []}, :elixir), do: "nil"
  defp emit_block(%EBlock{stmts: []}, :rust), do: "()"

  defp emit_block(%EBlock{stmts: stmts}, :elixir) do
    Enum.map_join(stmts, "; ", fn
      {:bind, n, e} -> "#{n} = #{p(e, 0, :elixir)}"
      {:typed_bind, n, _t, e} -> "#{n} = #{p(e, 0, :elixir)}"
      {:expr, e} -> p(e, 0, :elixir)
    end)
  end

  defp emit_block(%EBlock{stmts: stmts}, :rust) do
    Enum.map_join(stmts, " ", fn
      {:bind, n, e} -> "let #{n} = #{p(e, 0, :rust)};"
      {:typed_bind, n, _t, e} -> "let #{n} = #{p(e, 0, :rust)};"
      {:expr, e} -> p(e, 0, :rust)
    end)
  end

  defp pipe_to_call(l, %ECall{fun: f, args: args}), do: %ECall{fun: f, args: [l | args]}
  defp pipe_to_call(l, f), do: %ECall{fun: f, args: [l]}

  defp flatten_concat(%EBin{op: "<>", left: l, right: r}),
    do: flatten_concat(l) ++ flatten_concat(r)

  defp flatten_concat(x), do: [x]

  defp disp("and", :rust), do: "&&"
  defp disp("or", :rust), do: "||"
  # `<~` is capability-gated mutation (ADR-0039): BEAM rebinding / Rust
  # reassignment — both spelled `=` on the target.
  defp disp("<~", _), do: "="
  defp disp(op, _), do: op

  defp prec(op) do
    cond do
      op in ~w(* / rem div) -> 10
      op in ~w(+ -) -> 9
      op == "<>" -> 8
      op == "in" -> 7
      op == "|>" -> 6
      op in ~w(< <= > >=) -> 5
      op in ~w(== !=) -> 4
      op == "and" -> 3
      op == "or" -> 2
      op == "<~" -> 1
    end
  end

  defp assoc(op) do
    cond do
      op == "<>" or op == "<~" -> :right
      op in ~w(< <= > >= == != in) -> :none
      true -> :left
    end
  end

  # ── primitive type mapping ─────────────────────────────────────────────
  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  # Crystal source name -> Rust (owned form) / Elixir typespec (ADR-0033).
  defp prim_rust(t), do: Rian.Capability.owned(t)

  defp prim_ex("Bool"), do: "boolean()"
  defp prim_ex("String"), do: "String.t()"
  defp prim_ex("Symbol"), do: "atom()"
  defp prim_ex("Char"), do: "char()"

  defp prim_ex(t) do
    cond do
      Regex.match?(~r/^(Int|UInt)(8|16|32|64|128)$/, t) -> "integer()"
      Regex.match?(~r/^Float(32|64)$/, t) -> "float()"
      true -> "term()"
    end
  end
end
