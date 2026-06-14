defmodule Rian.Lower do
  @moduledoc """
  End-to-end **text** backend lowering for a single Rian function. Wires together:
    * type env             (Rian.Exhaustiveness)
    * pattern lowering     (Rian.PatternLower)
    * exhaustiveness gate  (Rian.Exhaustiveness.analyze)  -- refuses to emit if it fails
    * expression parsing   (Rian.Pratt)                    -- precedence-aware
  and emits idiomatic Rust **and** Elixir text.

  > #### The Elixir-text path is a DEBUG/inspection view, not the BEAM execution path
  > **`Rian.Beam`** (Erlang abstract forms → `:compile.forms` → loadable `.beam`) is
  > the real BEAM backend. The Elixir *text* this module emits is a pedagogical /
  > inspection artifact — surfaced only behind `mix rian.compile --show-elixir` and
  > labelled a debug view — never the run path. **Rust** is the genuine text target
  > here. (P3, ADR-0031: the abstract-forms pivot retired Elixir-source emission.)

  > #### Higher-order application on the Elixir text target
  > Applying a function-*valued variable* (`f(x)` where `f` is a parameter,
  > binding, lambda param, or `case`-arm binding) emits the variable application
  > `f.(x)`, while a local function call stays `f(x)`. The text emitter threads the
  > in-scope bound-name set (clause heads + `:=` binds + lambda params + `case`
  > arm patterns) exactly as the Erlang abstract-forms backend (`Rian.Beam`) does,
  > so the two Elixir paths no longer diverge.

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
    EChar,
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
  def compile(types, func, structs \\ [], ranges \\ []) do
    env = build_env(types, structs, ranges)
    :ok = check!(func, env)
    meta = build_meta(types)
    smeta = build_struct_meta(structs)

    %{
      elixir: to_elixir(func, types, structs, smeta),
      rust: to_rust(func, types, meta, structs, smeta)
    }
  end

  @doc """
  Lower only the Elixir-text view (no Rust). Used for the protocol BEAM/JS
  runtime-dispatch funcs (`dispatch: …`): their guards (`element/2`, `:tag`) are
  BEAM-only, and Rust gets traits instead (ADR-0061), so emitting their Rust is
  both wrong and a hard error.
  """
  def compile_elixir(types, func, structs \\ [], ranges \\ []) do
    env = build_env(types, structs, ranges)
    :ok = check!(func, env)
    %{elixir: to_elixir(func, types, structs, build_struct_meta(structs))}
  end

  @doc "Compile to the BEAM target only (for functions using BEAM-only constructs)."
  def compile_beam(types, func, structs \\ [], ranges \\ []) do
    env = build_env(types, structs, ranges)
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
    env = build_env(types, structs, Map.get(m, :ranges, []))
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
    env = build_env(types, structs, Map.get(m, :ranges, []))
    Enum.each(funcs, &(:ok = check!(&1, env)))
    consts = Map.get(m, :consts, [])
    # a signature table (name -> func) lets the Rust call-site borrow pass see
    # which params are `&[T]`/`&str` and which calls return owned values
    sigs = Map.new(funcs, fn f -> {f.name, f} end)
    ctx = ctx(build_meta(types), build_struct_meta(structs), const_set(consts), sigs)

    # a type/struct must be `pub` if it is exported (`pub type`) OR named in a
    # `pub` function's signature — Rust forbids a public fn exposing a private type
    needed = pub_sig_type_names(funcs)
    vis = fn name, own? -> if own? or MapSet.member?(needed, name), do: "pub ", else: "" end

    body =
      [
        rs_doc(Map.get(m, :doc), "//!"),
        Enum.map_join(Map.get(m, :uses, []), "\n", &rust_use/1),
        Enum.map_join(structs, "\n\n", &rust_struct(&1, vis.(&1.name, &1.pub?))),
        Enum.map_join(types, "\n\n", &rust_enum(&1, vis.(&1.name, &1.pub?))),
        Enum.map_join(consts, "\n", &rust_const(&1, ctx)),
        Enum.map_join(funcs, "\n\n", &rust_fn(&1, ctx, if(&1.pub?, do: "pub ", else: "")))
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    "mod #{PL.to_snake(name)} {\n#{body}\n}"
  end

  defp const_set(consts), do: MapSet.new(consts, & &1.name)

  # type/struct names mentioned in any `pub` function's param or return types
  # (the PascalCase identifiers in those type strings)
  defp pub_sig_type_names(funcs) do
    for f <- funcs,
        f.pub?,
        ts <- [f.ret | Enum.map(f.params, & &1.type)],
        name <- type_idents(ts),
        into: MapSet.new(),
        do: name
  end

  defp type_idents(nil), do: []
  defp type_idents(ts), do: Regex.scan(~r/[A-Z]\w*/, ts) |> Enum.map(&hd/1)

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
  defp build_env(types, structs, ranges) do
    env =
      Enum.reduce(Rian.Prelude.with_prelude(types), E.base_env(), fn t, env ->
        variants = Enum.map(t.variants, fn v -> {PL.to_snake(v.ctor), length(v.fields)} end)
        E.add_type(env, PL.to_snake(t.name), variants)
      end)

    # a `range` registers a finite ordinal signature (ADR-0036): its member
    # literals exhaust the type, so clause heads covering `lo..hi` are total
    env = Enum.reduce(ranges, env, fn r, env -> E.add_range(env, r.name, r.lo, r.hi) end)

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
  # A synthetic protocol dispatcher (ADR-0042 §3/§6) is exempt: protocol dispatch
  # is open by design (no case-arms, no totality requirement), unlike a user match.
  defp check!(%{synthetic: true}, _env), do: :ok

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
        # the clause head's pattern variables are in scope for the body, so a call
        # to one of them is a variable application (`f.(x)`), not a local call
        vars = Enum.flat_map(c.pats, fn p -> core_pat_vars(Core.from_pat(p)) end)
        put_ex_scope(MapSet.new(vars))
        body = c.body |> body_ast(ctx) |> Core.from_expr() |> emit(:elixir) |> elem(0)
        put_ex_scope(MapSet.new())
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
      nil ->
        ""

      g ->
        # On Rust, a binder bound inside a slice/list element is a `&T` borrow
        # (match ergonomics); a guard comparing it (`*c == 32`) must deref it.
        # `g` is a source string (Rian.Decl) or an already-parsed AST (Stage-2
        # front-end, ADR-0063) — `Pratt.parse/1` accepts either.
        ast = Pratt.parse(g) |> deref_ids(deref)
        guard_kw(target) <> (emit(Core.from_expr(ast), target) |> elem(0))
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
  # a `Char` is its codepoint integer on the BEAM/Elixir text target (ADR-0036)
  defp pat_ex(%Core.PChar{value: cp}), do: to_string(cp)
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

  # ── Rust protocol lowering (ADR-0061 §2): traits + impls ─────────────────
  # A `protocol` is a fresh, Rian-namespaced `trait Rian<Name>`; an `impl P for T`
  # is `impl RianP for <rust(T)>`. The receiver maps to `&self` (the impl's first
  # parameter is rebound to it); bounded generics (`forall T: Eq`) become
  # `fn f<T: RianEq>` in `rust_fn` and their protocol-method calls rewrite to
  # UFCS (`RianEq::eq(..)`). rustc dispatches statically — no dispatcher.
  @doc """
  Rust traits + impls from the protocol IR (ADR-0061 §2), as a self-contained
  unit: the `enum`/`struct` defs the impls reference are emitted alongside.
  """
  def rust_protocols(protocols, impl_decls, types, structs) do
    c = ctx(build_meta(types), build_struct_meta(structs), MapSet.new())
    impl_types = MapSet.new(impl_decls, & &1.type)
    # only the types an impl targets (so a protocol-only unit doesn't redeclare
    # enums already carried by the function units)
    enums =
      types
      |> Enum.filter(&MapSet.member?(impl_types, &1.name))
      |> Enum.map_join("\n\n", &rust_enum/1)

    struct_defs =
      structs
      |> Enum.filter(&MapSet.member?(impl_types, &1.name))
      |> Enum.map_join("\n\n", &rust_struct/1)

    [struct_defs, enums, trait_impl_block(protocols, impl_decls, c)]
    |> Enum.reject(&(&1 in ["", nil]))
    |> Enum.join("\n\n")
  end

  # the traits + impls alone (no type/struct preamble) — for whole-program
  # assembly, where the types are emitted once at the top.
  defp trait_impl_block(protocols, impl_decls, c) do
    traits = Enum.map_join(protocols, "\n\n", &rust_trait/1)
    impls = Enum.map_join(impl_decls, "\n\n", &rust_impl(&1, protocols, c))
    [traits, impls] |> Enum.reject(&(&1 in ["", nil])) |> Enum.join("\n\n")
  end

  @doc """
  Assemble a whole parsed program into **one** Rust module (ADR-0061): every
  `enum`/`struct`/`trait`/`impl` is emitted once, then every non-dispatch
  top-level function (the BEAM/JS runtime dispatcher is dropped — Rust uses
  traits). This composes the stdlib + protocols + generics that the per-unit
  `to_rust` cannot (it repeats type defs per unit).
  """
  def rust_program(prog) do
    types = Map.get(prog, :types, [])
    structs = Map.get(prog, :structs, [])
    funcs = Map.get(prog, :funcs, []) |> Enum.reject(& &1.dispatch)
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    Process.put(:rian_proto_methods, proto_method_traits(protocols))
    sigs = Map.new(Map.get(prog, :funcs, []), fn f -> {f.name, f} end)
    c = ctx(build_meta(types), build_struct_meta(structs), MapSet.new(), sigs)

    [
      Enum.map_join(structs, "\n\n", &rust_struct/1),
      Enum.map_join(types, "\n\n", &rust_enum/1),
      trait_impl_block(protocols, impl_decls, c),
      Enum.map_join(funcs, "\n\n", &rust_fn(&1, c, ""))
    ]
    |> Enum.reject(&(&1 in ["", nil]))
    |> Enum.join("\n\n")
  end

  defp proto_method_traits(protocols),
    do: for(p <- protocols, m <- p.methods, into: %{}, do: {m.name, p.name})

  defp rust_trait(%{name: name, methods: methods}) do
    sigs =
      Enum.map_join(methods, "\n", fn m ->
        "    fn #{m.name}(#{trait_params(m.params, "Self")}) -> #{rust_ret(self_subst(m.ret, "Self"))};"
      end)

    "trait Rian#{name} {\n#{sigs}\n}"
  end

  defp rust_impl(%{proto: proto, type: type, methods: methods}, protocols, c) do
    sig_for =
      protocols
      |> Enum.find(%{methods: []}, &(&1.name == proto))
      |> Map.fetch!(:methods)
      |> Map.new(&{&1.name, &1})

    rust_type = rust_proto_type!(type)
    bodies = Enum.map_join(methods, "\n", &rust_impl_method(&1, sig_for[&1.name], rust_type, c))
    "impl Rian#{proto} for #{rust_type} {\n#{bodies}\n}"
  end

  # the Rust spelling of an impl target type: a primitive maps via `Capability`,
  # a sum/struct keeps its (PascalCase) name.
  defp rust_proto_type!(type), do: Rian.Capability.rust_name(type)

  defp rust_impl_method(method, sig, rust_type, c) do
    [recv | rest_names] = method.params |> pcommas() |> Enum.map(&String.trim/1)
    rest_sig = tl(pcommas(sig.params))

    params =
      ["&self" | Enum.zip(rest_names, rest_sig) |> Enum.map(&impl_param(&1, rust_type))]
      |> Enum.join(", ")

    ret_ty = self_subst(sig.ret, rust_type)
    body = method.body |> rust_proto_body(c) |> coerce_ret(ret_ty)
    "    fn #{method.name}(#{params}) -> #{rust_ret(ret_ty)} { let #{recv} = self; #{body} }"
  end

  # a Rian string literal lowers to a Rust `&str`; coerce an impl method that
  # returns `String` (`.to_string()` is a no-op clone if the body is already one).
  defp coerce_ret(body, "String"), do: "(#{body}).to_string()"
  defp coerce_ret(body, _ret), do: body

  defp impl_param({name, sig_p}, rust_type) do
    {_n, ty} = name_type(sig_p)
    "#{name}: #{ref_type(ty, rust_type)}"
  end

  # lower an impl-method body through the same Rust pipeline `rust_fn` uses,
  # rewriting protocol-method calls to UFCS first.
  defp rust_proto_body(src, c) do
    src
    |> body_ast(c)
    |> rewrite_proto_calls(proto_methods())
    |> resolve_rust_pats(c.meta)
    |> insert_borrows(Map.get(c, :funs, %{}))
    |> Core.from_expr()
    |> emit(:rust)
    |> elem(0)
  end

  # trait method params from a sig string (`self Self, b Self`): receiver -> &self.
  defp trait_params(param_str, self_repr) do
    case pcommas(param_str) do
      [] -> "&self"
      [_recv | rest] -> Enum.join(["&self" | Enum.map(rest, &sig_param(&1, self_repr))], ", ")
    end
  end

  defp sig_param(p, self_repr) do
    {name, ty} = name_type(p)
    "#{name}: #{ref_type(ty, self_repr)}"
  end

  # a protocol param type -> a borrowed Rust type; `Self` -> `&<self_repr>`.
  defp ref_type("Self", self_repr), do: "&#{self_repr}"
  defp ref_type(ty, _self_repr), do: Rian.Capability.rust_param(:val, ty)

  defp name_type(p) do
    case p |> String.trim() |> String.split(~r/\s+/, trim: true) do
      [name, ty] -> {name, ty}
      [ty] -> {"_", ty}
    end
  end

  defp self_subst(t, repr), do: Regex.replace(~r/\bSelf\b/, t, repr)

  # the protocol-method -> trait-name map for the current compile (UFCS rewrite),
  # carried in the process dict (a single sequential emitter pass, like js int53).
  defp proto_methods, do: Process.get(:rian_proto_methods, %{})

  # rewrite a protocol-method call `m(recv, rest…)` to Rust **method-call** syntax
  # `recv.m(rest…)` so rustc dispatches statically. Method-call (not UFCS
  # `Trait::m(recv, …)`) auto-refs the receiver, so it works whether `recv` is a
  # `&T` parameter or an owned `T` (a cloned slice-element binder) — both reach
  # the `&self` method. Non-protocol calls pass through.
  def rewrite_proto_calls({:call, {:id, m}, [recv | rest]}, methods)
      when is_map_key(methods, m) do
    recv = rewrite_proto_calls(recv, methods)
    rest = Enum.map(rest, &rewrite_proto_calls(&1, methods))
    {:call, {:dot, recv, m}, rest}
  end

  def rewrite_proto_calls({:call, fun, args}, methods),
    do:
      {:call, rewrite_proto_calls(fun, methods),
       Enum.map(args, &rewrite_proto_calls(&1, methods))}

  def rewrite_proto_calls(node, methods) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.map(&rewrite_proto_calls(&1, methods)) |> List.to_tuple()

  def rewrite_proto_calls(list, methods) when is_list(list),
    do: Enum.map(list, &rewrite_proto_calls(&1, methods))

  def rewrite_proto_calls(other, _methods), do: other

  # `<T: RianEq + RianOrd + Clone>` from a function's `tvars`/`bounds`
  # (ADR-0061 §2/§4). `Clone` is added to every type parameter so a generic that
  # returns/constructs an owned collection from borrowed elements (`sort` building
  # a `Vec<T>`) type-checks; for our Copy primitives it is free, and over-
  # constraining a caller to `Clone` is benign. (A precise "only when owned-
  # construction occurs" bound is a future refinement.)
  defp rust_generics(%{tvars: []}), do: ""

  defp rust_generics(%{tvars: tvars, bounds: bounds}) do
    inner =
      Enum.map_join(tvars, ", ", fn tv ->
        traits = Enum.map(Map.get(bounds || %{}, tv, []), &"Rian#{&1}") ++ ["Clone"]
        "#{tv}: #{Enum.join(traits, " + ")}"
      end)

    "<#{inner}>"
  end

  defp rust_generics(_), do: ""

  # paren-aware top-level comma split of a parameter string
  defp pcommas(s), do: Rian.TypeStr.split_top_commas(s)

  # One Rust `fn` (no type/struct preamble). `vis` is `""` or `"pub "`.
  # an `@external` function (ADR-0068): emit the `:rs` host body verbatim. Rust uses
  # named params, so the spec references them directly — no positional binding. No
  # `:rs` body -> the function is off `:rs` (Reach pins it); reaching here is an
  # off-target compile error (ADR-0041 §2).
  defp rust_fn(%{externals: ext} = func, _ctx, vis) when map_size(ext) > 0 do
    case Map.get(ext, :rs) do
      nil ->
        raise "`#{func.name}`: no `@external(:rs, …)` body — not reachable on :rs"

      spec ->
        param_decls =
          Enum.map_join(func.params, ", ", fn p ->
            "#{p.name}: #{Rian.Capability.rust_param(p.cap, p.type)}"
          end)

        "#{vis}fn #{func.name}(#{param_decls}) -> #{rust_ret(func.ret)} { #{spec} }"
    end
  end

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
          |> widen_char_arith(char_vars(func.params, c.pats))
          |> rewrite_proto_calls(proto_methods())
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

    # Per-target exhaustiveness shim (ADR-0036): a `range`-total match has literal
    # arms over an *open* base primitive (`i64`/`char`), which `rustc` sees as
    # non-exhaustive. The Rian gate already proved totality, so append an
    # `unreachable!()` arm — never reached, satisfies rustc. (Sum-type matches are
    # closed and need no shim; a `_`/var clause already provides the fallthrough.)
    shim = if rust_total_shim?(func), do: "\n        _ => unreachable!(),", else: ""

    fn_str =
      "#{vis}fn #{func.name}#{rust_generics(func)}(#{param_decls}) -> #{rust_ret(func.ret)} {\n" <>
        "    match #{scrut} {\n#{arms}#{shim}\n    }\n}"

    join_doc(rs_doc(Map.get(func, :doc), "///"), fn_str)
  end

  # A function whose clause heads are literal/`Char` patterns with **no** catch-all
  # clause is total only because a `range`'s finite signature covers them — so the
  # emitted Rust `match` over the open base needs an `unreachable!()` fallthrough.
  defp rust_total_shim?(func) do
    pats = Enum.map(func.clauses, fn c -> Enum.map(c.pats, &Core.from_pat/1) end)
    flat = List.flatten(pats)
    has_catchall = Enum.any?(pats, fn ps -> Enum.all?(ps, &catchall_pat?/1) end)

    literal_headed =
      Enum.any?(flat, &match?(%PLit{}, &1)) or Enum.any?(flat, &match?(%Core.PChar{}, &1))

    has_variant = Enum.any?(flat, &match?(%PCtor{}, &1))
    not has_catchall and literal_headed and not has_variant
  end

  defp catchall_pat?(%PWild{}), do: true
  defp catchall_pat?(%PVar{}), do: true
  defp catchall_pat?(_), do: false

  # ── Char-arithmetic widening (ADR-0036, Rust only) ─────────────────────
  # On Rust a `Char` is a native `char`, and ordinal arithmetic widens to the
  # base `Int64` — so a `Char` operand of `+ - * rem div` is wrapped in
  # `__prim_char_code/1` (lowered to `char as i64`). BEAM/JS need no pass: there a
  # `Char` is already a codepoint integer, so the arithmetic runs as-is. `cvars`
  # is the set of `Char`-typed names in scope for the clause.
  @char_arith_ops ~w(+ - * rem div)

  defp widen_char_arith({:bin, op, l, r}, cvars) when op in @char_arith_ops do
    {:bin, op, wrap_char(widen_char_arith(l, cvars), cvars),
     wrap_char(widen_char_arith(r, cvars), cvars)}
  end

  defp widen_char_arith(node, cvars),
    do: Rian.Macro.map_node(node, &widen_char_arith(&1, cvars))

  defp wrap_char({:char, _} = c, _cvars), do: {:call, {:id, "__prim_char_code"}, [c]}

  defp wrap_char({:id, n} = v, cvars),
    do: if(MapSet.member?(cvars, n), do: {:call, {:id, "__prim_char_code"}, [v]}, else: v)

  defp wrap_char(other, _cvars), do: other

  # names bound at `Char` type in a clause: a `Char` param matched by a variable,
  # plus the element binders of a `Vec(Char)` param matched by a list/cons pattern
  # (the head `c` in `[c | rest]` is a `Char`; the tail `rest` is a `Vec(Char)`).
  defp char_vars(params, pats) do
    params
    |> Enum.zip(pats)
    |> Enum.reduce(MapSet.new(), fn {p, pat}, acc ->
      case p.type do
        "Char" -> add_var(acc, pat)
        "Vec(Char)" -> add_list_elem_vars(acc, pat)
        _ -> acc
      end
    end)
  end

  defp add_var(acc, {:var, n}), do: MapSet.put(acc, n)
  defp add_var(acc, _), do: acc

  defp add_list_elem_vars(acc, {:list, elems, _tail}),
    do: Enum.reduce(elems, acc, fn e, a -> add_var(a, e) end)

  defp add_list_elem_vars(acc, _), do: acc

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

  defp rust_struct(s, vis \\ "") do
    # a `pub` struct exposes its fields too (so cross-module field access works)
    fvis = if vis == "", do: "", else: "pub "
    fields = Enum.map_join(s.fields, ", ", fn f -> "#{fvis}#{f.label}: #{prim_rust(f.type)}" end)
    "#[derive(Clone, Debug, PartialEq)]\n#{vis}struct #{s.name} { #{fields} }"
  end

  defp tuple_or_one([one], f), do: f.(one)
  defp tuple_or_one(many, f), do: "(" <> Enum.map_join(many, ", ", f) <> ")"

  defp rust_enum(t, vis \\ "") do
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
      "#[derive(Clone, Debug, PartialEq)]\n#{vis}enum #{t.name} {\n#{variants}\n}"
    )
  end

  # surface pattern -> typed core IR -> Rust (ADR-0050: emitter consumes the core)
  defp core_pat_rs(surface, meta), do: pat_rs(Core.from_pat(surface), meta)

  defp pat_rs(%PWild{}, _), do: "_"
  defp pat_rs(%PVar{name: x}, _), do: x
  defp pat_rs(%PLit{value: v}, _) when is_binary(v), do: str_lit(v)
  defp pat_rs(%PLit{value: v}, _), do: to_string(v)
  # a `Char` literal pattern is a native Rust `char` literal (ADR-0036)
  defp pat_rs(%Core.PChar{value: cp}, _), do: rust_char_lit(cp)
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

  # a Unicode codepoint as a Rust `char` literal, escaping the specials; any
  # other codepoint is emitted as its UTF-8 character (Rust source is UTF-8).
  defp rust_char_lit(?\n), do: "'\\n'"
  defp rust_char_lit(?\t), do: "'\\t'"
  defp rust_char_lit(?\r), do: "'\\r'"
  defp rust_char_lit(0), do: "'\\0'"
  defp rust_char_lit(?\\), do: "'\\\\'"
  defp rust_char_lit(?'), do: "'\\''"
  defp rust_char_lit(cp), do: "'" <> <<cp::utf8>> <> "'"

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

  # ── Elixir-text scope (for the variable-application distinction) ─────────
  # On the BEAM/Elixir target, applying a function-*valued variable* (a param or
  # binding) is `f.(x)`, while a local function call is `f(x)`. We track the set
  # of in-scope bound names — grown by clause heads, `:=` binds, lambda params,
  # and `case` arm patterns — exactly as `Rian.Beam` does, so the text view
  # matches the real BEAM backend (no drift). Carried in the process dict (a
  # single sequential emitter pass); the Rust target calls closures directly and
  # never consults it.
  defp ex_scope, do: Process.get(:rian_ex_scope, MapSet.new())
  defp put_ex_scope(s), do: Process.put(:rian_ex_scope, s)

  # run `fun` with the scope extended by `names`, restoring the previous scope
  defp with_ex_scope(names, fun) do
    prev = ex_scope()
    put_ex_scope(MapSet.union(prev, MapSet.new(names)))
    result = fun.()
    put_ex_scope(prev)
    result
  end

  # the variable names a core pattern binds (for scope tracking)
  defp core_pat_vars(%PVar{name: n}), do: [n]
  defp core_pat_vars(%PCtor{args: ps}), do: Enum.flat_map(ps, &core_pat_vars/1)
  defp core_pat_vars(%PTuple{elems: ps}), do: Enum.flat_map(ps, &core_pat_vars/1)

  defp core_pat_vars(%PList{elems: ps, tail: t}),
    do: Enum.flat_map(ps, &core_pat_vars/1) ++ core_pat_vars(t)

  defp core_pat_vars(%Core.PStruct{fields: fs}),
    do: Enum.flat_map(fs, fn {_l, p} -> core_pat_vars(p) end)

  defp core_pat_vars(_), do: []

  # render a decoded `String` value as a double-quoted literal valid on *both*
  # text targets: Elixir and Rust share `\n \r \t \\ \"` plus the `\u{HEX}`
  # form, so one renderer serves the shared `emit/2` path. Printable codepoints
  # (incl. non-ASCII) pass through; other control codepoints use `\u{HEX}`.
  defp str_lit(s), do: ~s(") <> for(<<cp::utf8 <- s>>, into: "", do: str_lit_cp(cp)) <> ~s(")

  defp str_lit_cp(?\\), do: "\\\\"
  defp str_lit_cp(?"), do: "\\\""
  defp str_lit_cp(?\n), do: "\\n"
  defp str_lit_cp(?\r), do: "\\r"
  defp str_lit_cp(?\t), do: "\\t"

  defp str_lit_cp(cp) when cp < 0x20 or cp == 0x7F,
    do: "\\u{" <> Integer.to_string(cp, 16) <> "}"

  defp str_lit_cp(cp), do: <<cp::utf8>>

  defp emit(%ENum{text: n}, _t), do: {n, 12}
  # string literal — same surface on both targets (Rust yields `&str`)
  defp emit(%EStr{value: s}, _t), do: {str_lit(s), 12}
  # a `Char` (ADR-0036): a codepoint integer on the BEAM text target, a native
  # `char` literal on Rust. Convert to an integer with `__prim_char_code/1`.
  defp emit(%EChar{value: cp}, :elixir), do: {Integer.to_string(cp), 12}
  defp emit(%EChar{value: cp}, :rust), do: {rust_char_lit(cp), 12}
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
      # a Rian protocol trait — UFCS `RianEq::eq(..)`, case preserved (ADR-0061 §2)
      String.starts_with?(m, "Rian") and pascal?(m) -> {"#{m}::#{n}", 12}
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
  # are native `char` (ADR-0036 — `Char` lowers to Rust `char`); these mirror the
  # BEAM/JS lowerings so portable `Str` ops compose.
  defp emit(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}, :rust),
    do: {"#{p(s, 12, :rust)}.chars().collect::<Vec<char>>()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}, :rust),
    do: {"#{p(cs, 12, :rust)}.iter().collect::<String>()", 12}

  # a `Char`'s codepoint as an integer — the explicit Char→Int conversion
  # (ADR-0036); `char as i64` is the native widening on Rust.
  defp emit(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, :rust),
    do: {"(#{p(c, 12, :rust)} as i64)", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, :elixir),
    do: {p(c, 12, :elixir), 12}

  # integer → string (ADR-0069 interpolation): native `to_string`/`Integer.to_string`
  defp emit(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, :rust),
    do: {"#{p(n, 12, :rust)}.to_string()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, :elixir),
    do: {"Integer.to_string(#{p(n, 0, :elixir)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}, :rust),
    do: {"format!(\"{}{}\", #{p(a, 0, :rust)}, #{p(b, 0, :rust)})", 12}

  # explicit overflow ops (ADR-0035 §3) on Rust — the native `i64` methods; this
  # is the target where overflow actually bites (debug panic / release wrap), so
  # `checked_add` returns `Option<i64>` (Rian `Option(Int64)`) directly.
  defp emit(%ECall{fun: %EId{name: "__prim_wrapping_add"}, args: [a, b]}, :rust),
    do: {"#{p(a, 12, :rust)}.wrapping_add(#{p(b, 0, :rust)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_saturating_add"}, args: [a, b]}, :rust),
    do: {"#{p(a, 12, :rust)}.saturating_add(#{p(b, 0, :rust)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_checked_add"}, args: [a, b]}, :rust),
    do: {"#{p(a, 12, :rust)}.checked_add(#{p(b, 0, :rust)})", 12}

  # applying a function-valued variable on Elixir is `f.(x)`, a local call is
  # `f(x)` — decided by whether `f` is in scope (matches `Rian.Beam`)
  defp emit(%ECall{fun: %EId{name: f}, args: args}, :elixir) do
    inner = Enum.map_join(args, ", ", &p(&1, 0, :elixir))
    if MapSet.member?(ex_scope(), f), do: {"#{f}.(#{inner})", 12}, else: {"#{f}(#{inner})", 12}
  end

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
    names = Enum.map(params, fn {n, _} -> n end)
    body_str = with_ex_scope(names, fn -> p(body, 0, :elixir) end)
    {"fn #{ps} -> #{body_str} end", 12}
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
    scrut_str = p(scrut, 0, :elixir)

    body =
      Enum.map_join(arms, "; ", fn {pt, g, b} ->
        # the arm pattern's bindings are in scope for its guard and body
        with_ex_scope(core_pat_vars(pt), fn ->
          "#{pat_ex(pt)}#{case_guard(g, :elixir)} -> #{p(b, 0, :elixir)}"
        end)
      end)

    {"case #{scrut_str} do #{body} end", 0}
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
    # each `:=` binding's name enters scope for the statements that follow it, so
    # a later application of a function-valued binding is `g.(x)` (matches Beam).
    prev = ex_scope()

    {parts, _} =
      Enum.map_reduce(stmts, prev, fn stmt, sc ->
        put_ex_scope(sc)

        case stmt do
          {:bind, n, e} -> {"#{n} = #{p(e, 0, :elixir)}", MapSet.put(sc, n)}
          {:typed_bind, n, _t, e} -> {"#{n} = #{p(e, 0, :elixir)}", MapSet.put(sc, n)}
          {:expr, e} -> {p(e, 0, :elixir), sc}
        end
      end)

    put_ex_scope(prev)
    Enum.join(parts, "; ")
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
      # bare `Int` (arbitrary precision, ADR-0064) and fixed widths both -> integer()
      Regex.match?(~r/^(Int|UInt)(8|16|32|64|128)?$/, t) -> "integer()"
      Regex.match?(~r/^Float(32|64)$/, t) -> "float()"
      true -> "term()"
    end
  end
end
