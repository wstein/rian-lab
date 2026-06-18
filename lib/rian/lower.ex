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
    ELabel,
    ELambda,
    EList,
    EMap,
    EMapUpdate,
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
  # `proto` is the protocol-method -> trait-name map for the Rust UFCS call-site
  # rewrite (ADR-0061 §2). `Decl.compile` passes it (a function unit's body may
  # call a protocol method); a direct caller that uses no protocols omits it.
  @spec compile(list(), map(), list(), list(), map(), map()) :: map()
  def compile(types, func, structs \\ [], ranges \\ [], proto \\ %{}, ic \\ %{}) do
    env = build_env(types, structs, ranges)
    :ok = check!(func, env)
    meta = build_meta(types)
    smeta = build_struct_meta(structs)

    %{
      elixir: to_elixir(func, types, structs, smeta, ic),
      rust: to_rust(func, types, meta, structs, smeta, proto, ic)
    }
  end

  @doc """
  Lower only the Elixir-text view (no Rust). Used for the protocol BEAM/JS
  runtime-dispatch funcs (`dispatch: …`): their guards (`element/2`, `:tag`) are
  BEAM-only, and Rust gets traits instead (ADR-0061), so emitting their Rust is
  both wrong and a hard error.
  """
  @spec compile_elixir(list(), map(), list(), list(), map()) :: map()
  def compile_elixir(types, func, structs \\ [], ranges \\ [], ic \\ %{}) do
    env = build_env(types, structs, ranges)
    :ok = check!(func, env)
    %{elixir: to_elixir(func, types, structs, build_struct_meta(structs), ic)}
  end

  @doc """
  Compile to the BEAM target only (for functions using BEAM-only constructs).
  The BEAM text view is exactly the Elixir one, so this delegates to
  `compile_elixir/4` — a distinct entry point kept for call-site intent.
  """
  @spec compile_beam(list(), map(), list(), list(), map()) :: map()
  def compile_beam(types, func, structs \\ [], ranges \\ [], ic \\ %{}),
    do: compile_elixir(types, func, structs, ranges, ic)

  @doc """
  Compile a whole `%Rian.IR.Mod{}` to both targets: a `defmodule` (BEAM) and a
  `mod` (Rust), with its types/structs emitted once and each function wrapped at
  its declared visibility (`pub?` -> `def`/`pub fn`, else `defp`/private `fn`).
  """
  @spec compile_module(struct(), map()) :: map()
  def compile_module(%Rian.IR.Mod{} = m, ic \\ %{}) do
    %{elixir: module_elixir(m, ic), rust: module_rust(m, ic)}
  end

  @doc "Compile a module to the BEAM target only."
  @spec compile_module_beam(struct(), map()) :: map()
  def compile_module_beam(%Rian.IR.Mod{} = m, ic \\ %{}), do: %{elixir: module_elixir(m, ic)}

  defp module_elixir(%{name: name, types: types, structs: structs, funcs: funcs} = m, ic) do
    env = build_env(types, structs, Map.get(m, :ranges, []))
    Enum.each(funcs, &(:ok = check!(&1, env)))
    consts = Map.get(m, :consts, [])
    ctx = ctx(build_meta(types), build_struct_meta(structs), const_set(consts), %{}, ic)

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

  defp module_rust(%{name: name, types: types, structs: structs, funcs: funcs} = m, ic) do
    env = build_env(types, structs, Map.get(m, :ranges, []))
    Enum.each(funcs, &(:ok = check!(&1, env)))
    consts = Map.get(m, :consts, [])
    # a signature table ({name, arity} -> func) lets the Rust call-site borrow pass
    # see which params are `&[T]`/`&str` and which calls return owned values
    sigs = Map.new(funcs, fn f -> {{f.name, length(f.params)}, f} end)
    ctx = ctx(build_meta(types), build_struct_meta(structs), const_set(consts), sigs, ic)

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

  @spec const_set(list()) :: MapSet.t()
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

    val =
      c.value
      |> body_ast(ctx)
      |> Rian.Check.annotate(%{}, ctx.ic)
      |> emit(:elixir, emit_ctx(%{ic: ctx.ic}))
      |> elem(0)

    "#{def_kw} #{PL.to_snake(c.name)}() do #{val} end"
  end

  # `const NAME Type := value` -> a Rust `const` (`pub const` when exported).
  defp rust_const(c, ctx) do
    vis = if c.pub?, do: "pub ", else: ""

    val =
      c.value
      |> body_ast(ctx)
      |> resolve_rust_pats(ctx.meta)
      |> Rian.Check.annotate(%{}, ctx.ic)
      |> emit(:rust, emit_ctx(%{ic: ctx.ic}))
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
      field_types = Enum.map(v.fields, &Map.get(&1, :type))

      {PL.to_snake(v.ctor),
       %{enum: t.name, ctor: v.ctor, labels: labels, named: named, field_types: field_types}}
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
        # clause HEADS are total — now gate every `case` reachable in the body too.
        E.check_case_bodies!([func], env)
    end
  end

  # ── Elixir backend ─────────────────────────────────────────────────────
  @spec to_elixir(map(), list(), list(), map(), map()) :: term()
  def to_elixir(func, types, structs \\ [], smeta \\ %{}, ic \\ %{}) do
    typespecs = Enum.map_join(types, "\n", &ex_typespec/1)
    struct_defs = Enum.map_join(structs, "\n", &ex_struct/1)
    ctx = ctx(build_meta(types), smeta, MapSet.new(), %{}, ic)

    [struct_defs, typespecs, elixir_clauses(func, ctx, "def")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # The resolution context threaded into every body: `meta` (sum-variant table),
  # `smeta` (struct table), `cset` (in-scope constant names). `cset`'s `MapSet.t()`
  # is declared explicitly so it stays opaque through the field access in
  # `resolve_consts/2` (otherwise its element type is inferred structurally).
  @typep rctx :: %{meta: map(), smeta: map(), cset: MapSet.t(), funs: map(), ic: map()}
  @spec ctx(map(), map(), MapSet.t()) :: rctx()
  @spec ctx(map(), map(), MapSet.t(), map()) :: rctx()
  @spec ctx(map(), map(), MapSet.t(), map(), map()) :: rctx()
  # `ic` is the program inference context (`Check.program_ic`); threaded so the
  # clause emitters can annotate the body's typed core IR (ADR-0050 §3).
  defp ctx(meta, smeta, cset, funs \\ %{}, ic \\ %{}),
    do: %{meta: meta, smeta: smeta, cset: cset, funs: funs, ic: ic}

  # The **emitter context** `ec` — the ambient data the expression emitter
  # (`emit`/`p`/`emit_block`) needs, threaded as an explicit immutable map
  # instead of the process dictionary. Distinct from `ctx` (the surface-
  # resolution context). All fields default; a caller overrides only what its
  # phase establishes (per-clause borrow/slice sets, per-function result-string
  # flags, the Elixir scope, and the program-wide proto/parametric/sigs maps).
  defp emit_ctx(opts \\ %{}) do
    Map.merge(
      %{
        borrowed: MapSet.new(),
        slices: MapSet.new(),
        owned_fields: MapSet.new(),
        ok_string: false,
        err_string: false,
        ex_scope: MapSet.new(),
        proto: %{},
        parametric: %{},
        sigs: %{},
        # the per-clause typing env + program inference context, so the body/guard
        # leaves can lower from the typed core IR (ADR-0050 §3)
        tenv: %{},
        ic: %{}
      },
      opts
    )
  end

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
        # the per-clause typing env types the body's core IR (ADR-0050 §3).
        tenv = Rian.Check.clause_env(c.pats, func.params, ctx.ic)
        ec = emit_ctx(%{ex_scope: MapSet.new(vars), tenv: tenv, ic: ctx.ic})

        body =
          c.body
          |> body_ast(ctx)
          |> Rian.Check.annotate(tenv, ctx.ic)
          |> emit(:elixir, ec)
          |> elem(0)

        "#{head}#{guard_str(c, :elixir, ec)} do #{body} end"
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
  @spec resolve_consts(term(), MapSet.t()) :: term()
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
  defp guard_str(c, target, ec, deref \\ []) do
    case Map.get(c, :guard) do
      nil ->
        ""

      g ->
        # On Rust, a binder bound inside a slice/list element is a `&T` borrow
        # (match ergonomics); a guard comparing it (`*c == 32`) must deref it.
        # `g` is a source string (Rian.Decl) or an already-parsed AST (Stage-2
        # front-end, ADR-0063) — `Pratt.parse/1` accepts either.
        ast = Pratt.parse(g) |> deref_ids(deref)

        guard_kw(target) <>
          (emit(Rian.Check.annotate(ast, ec.tenv, ec.ic), target, ec) |> elem(0))
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

  defp case_guard(nil, _, _ec), do: ""
  defp case_guard(g, target, ec), do: guard_kw(target) <> (emit(g, target, ec) |> elem(0))

  # a resolved Rust arm pattern that is a list/slice pattern (`[…]`) — its `case`
  # scrutinee must be matched as a slice (`&(scrut)[..]`).
  defp list_rpat?({:rpat, s}), do: String.starts_with?(String.trim_leading(s), "[")
  defp list_rpat?(_), do: false

  # Emit a Rust `match`, with `body_fn` rendering each arm's body (the default emits
  # it plainly; the `String`-return path coerces it). A `case` whose arms are list
  # patterns must match a slice: `&(scrut)[..]` coerces both an owned `Vec<T>` and an
  # already-borrowed `&[T]` to `&[T]` uniformly (binders stay `&T`/`&[T]`).
  defp rust_case(scrut, arms, body_fn, ec) do
    body =
      Enum.map_join(arms, " ", fn {pt, g, b} ->
        "#{rpat(pt)}#{case_guard(g, :rust, ec)} => #{body_fn.(b)},"
      end)

    scrut_rs =
      if Enum.any?(arms, fn {pt, _, _} -> list_rpat?(pt) end),
        do: "&(#{p(scrut, 0, :rust, ec)})[..]",
        else: p(scrut, 0, :rust, ec)

    "match #{scrut_rs} { #{body} }"
  end

  # Gap B (ADR-0061): a `String`-returning body that is an `if`/`case` cannot mix a
  # `&str`-literal arm with a `String` arm — Rust requires both to agree. Push the
  # `&str -> String` coercion into the TAIL positions (each branch/arm leaf) so they
  # unify, rather than wrapping the whole `if`/`match` (which can't type-check).
  defp coerce_string_ast(%EIf{cond: c, then: t, else: e}, ec),
    do:
      "if #{p(c, 0, :rust, ec)} { #{coerce_string_branch(t, ec)} } else { #{coerce_string_branch(e, ec)} }"

  defp coerce_string_ast(%ECase{scrut: scrut, arms: arms}, ec),
    do: rust_case(scrut, arms, &coerce_string_branch(&1, ec), ec)

  defp coerce_string_ast(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_string_ast(e, ec)

  defp coerce_string_ast(%EBlock{} = b, ec),
    do: "({ #{emit_block(b, :rust, ec)} }).to_string()"

  defp coerce_string_ast(ast, ec), do: "(#{p(ast, 0, :rust, ec)}).to_string()"

  defp coerce_string_branch(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_string_ast(e, ec)

  defp coerce_string_branch(%EBlock{} = b, ec),
    do: "({ #{emit_block(b, :rust, ec)} }).to_string()"

  defp coerce_string_branch(e, ec), do: coerce_string_ast(e, ec)

  # Resolve every `case` arm pattern in a body to its Rust spelling using the
  # type meta, storing it back into the IR as `{:rpat, str}`. After this pass the
  # Rust emitter needs no ambient meta — the IR carries the resolution.
  defp resolve_rust_pats({:case, scrut, arms}, meta) do
    {:case, resolve_rust_pats(scrut, meta),
     Enum.map(arms, fn {pt, g, b} ->
       {{:rpat, core_pat_rs(pt, meta)},
        case g do
          nil -> nil
          g -> resolve_rust_pats(g, meta)
        end, resolve_rust_pats(b, meta)}
     end)}
  end

  defp resolve_rust_pats({:with, clauses, body, els}, meta) do
    {:with,
     Enum.map(clauses, fn {pt, e} ->
       {{:rpat, core_pat_rs(pt, meta)}, resolve_rust_pats(e, meta)}
     end), resolve_rust_pats(body, meta),
     Enum.map(els, fn {pt, g, b} ->
       {{:rpat, core_pat_rs(pt, meta)},
        case g do
          nil -> nil
          g -> resolve_rust_pats(g, meta)
        end, resolve_rust_pats(b, meta)}
     end)}
  end

  defp resolve_rust_pats(node, meta), do: Rian.Macro.map_node(node, &resolve_rust_pats(&1, meta))

  # Rust call-site borrow pass (ADR-0047): when an argument *produces* an owned
  # value (a `Vec`/`String` from a constructor or a value-returning call) but the
  # callee's parameter is a borrow (`&[T]`/`&str`), wrap it in `&` so it coerces.
  # A bare variable is left alone — it is already the borrow the param expects.
  defp insert_borrows(node, funs, ec, borrowed \\ nil)

  defp insert_borrows({:call, {:id, name} = fun, args}, funs, ec, borrowed) do
    args = Enum.map(args, &insert_borrows(&1, funs, ec, borrowed))

    case param_rtypes(name, length(args), funs) do
      nil ->
        {:call, fun, args}

      ptypes ->
        coerced =
          args
          |> Enum.zip(ptypes)
          |> Enum.map(fn {a, pt} -> borrow_arg(a, pt, funs, borrowed, ec) end)

        {:call, fun, coerced}
    end
  end

  # a protocol-method call `recv.m(rest…)` (post-`rewrite_proto_calls`): the receiver
  # auto-refs, but each `rest` arg goes to a `&T`/`&Self` method param — in a generic
  # function an owned value among them needs `&` (the same owned→borrow coercion).
  defp insert_borrows({:call, {:dot, recv, m}, rest}, funs, ec, borrowed) do
    recv = insert_borrows(recv, funs, ec, borrowed)
    rest = Enum.map(rest, &insert_borrows(&1, funs, ec, borrowed))
    rest = if borrowed, do: Enum.map(rest, &borrow_value(&1, borrowed)), else: rest
    {:call, {:dot, recv, m}, rest}
  end

  defp insert_borrows(node, funs, ec, borrowed),
    do: Rian.Macro.map_node(node, &insert_borrows(&1, funs, ec, borrowed))

  # coerce one call argument to the borrow its (`&`-typed) parameter expects. The
  # decision keys on the *callee* param: a `&T`/`&[T]`/`&str` param fed an owned value
  # needs `&`. An owned `Vec`/`String` producer and a scalar literal need `&` from
  # *any* caller (a literal `0` to a generic `&T` is `&0`); inside a generic function
  # an owned *var* (a cloned binder, not a `&`-ref) does too.
  defp borrow_arg(a, pt, funs, borrowed, ec) do
    cond do
      not borrow_type?(pt) -> a
      # a `&impl Fn(...)` callback param (ADR-0061): a closure/expression argument is referenced
      # (`&|x| …`), but a bare variable is already a `&impl Fn` — a caller's own param or the
      # recursive `map(t, f)` — so it is left alone (referencing it again would be `&&`).
      fn_borrow?(pt) -> if match?({:id, _}, a), do: a, else: {:unary, "&", a}
      # a string literal fed to a *generic* `&K` param (`K` resolves to owned `String`,
      # which has the `Clone`/`impl`s a tvar needs — `str` does not): `&"a".to_string()`.
      generic_tvar_borrow?(pt) and match?({:str, _}, a) -> owned_str_arg(elem(a, 1))
      owned_field_var?(a, ec) -> {:unary, "&", a}
      borrowed != nil -> borrow_value(a, borrowed)
      owned_arg?(a, funs) -> {:unary, "&", a}
      scalar_literal?(a) -> {:unary, "&", a}
      true -> a
    end
  end

  # an owned `String`, borrowed for the `&K` param: `&format!("{}{}", "a", "")` via the
  # `<>` concat (which lowers to `format!` → owned `String`). Cleaner builders
  # (`String::from`/`.to_string()`) need ident/method emit the `::`-path lowering and
  # identifier snake-casing get wrong, so the empty-concat is the portable route.
  defp owned_str_arg(s), do: {:unary, "&", {:bin, "<>", {:str, s}, {:str, ""}}}

  # a borrowed bare type variable (`&K`, not `&str`/`&[T]`): the param is generic.
  defp generic_tvar_borrow?("&" <> rest), do: tvar_name?(rest)
  defp generic_tvar_borrow?(_), do: false

  # `&`-borrow a value unless it is already a `&`-reference: a var bound to a `&`-param
  # or cons-tail (`borrowed`), an already-inserted `&`, or a string literal (`&str`).
  defp borrow_value({:unary, "&", _} = a, _borrowed), do: a
  defp borrow_value({:str, _} = a, _borrowed), do: a

  defp borrow_value({:id, v} = a, borrowed),
    do: if(MapSet.member?(borrowed, v), do: a, else: {:unary, "&", a})

  defp borrow_value(a, _borrowed), do: {:unary, "&", a}

  # a numeric / char literal (or arithmetic of them, `0 - 1`) is an owned value
  # (`i64`/`char`); fed to a `&T` param it needs `&`. A string literal is already
  # `&str`, so it is not included here.
  defp scalar_literal?({:num, _}), do: true
  defp scalar_literal?({:char_lit, _}), do: true
  defp scalar_literal?({:unary, "-", a}), do: scalar_literal?(a)

  defp scalar_literal?({:bin, op, l, r}) when op in ~w(+ - * div rem),
    do: scalar_literal?(l) and scalar_literal?(r)

  defp scalar_literal?(_), do: false

  # Gap C (ADR-0061): variables bound to an owned `Vec`/`String` field of a sum
  # destructured in the BODY — a nested `case` over an OWNED-returning scrutinee
  # (a constructor, or a local call returning `Vec`/`String`/a user type). Such a
  # binder is an owned value, so passing it to a `&[T]`/`&str` param needs `&`.
  # Collected from the surface body BEFORE pattern resolution (`{:ctor, …}` arms);
  # clause-head ctor patterns are not `{:case}` nodes here, so they are untouched.
  defp owned_field_binders(ast, ctx), do: ofb(ast, ctx, MapSet.new())

  defp ofb({:case, scrut, arms}, ctx, acc) do
    acc = ofb(scrut, ctx, acc)
    owned? = owned_scrut?(scrut, ctx)

    Enum.reduce(arms, acc, fn {pat, _g, body}, a ->
      a = if owned?, do: collect_owned_field_vars(pat, ctx, a), else: a
      ofb(body, ctx, a)
    end)
  end

  defp ofb(t, ctx, acc) when is_tuple(t),
    do: Enum.reduce(Tuple.to_list(t), acc, &ofb(&1, ctx, &2))

  defp ofb(l, ctx, acc) when is_list(l), do: Enum.reduce(l, acc, &ofb(&1, ctx, &2))
  defp ofb(_, _ctx, acc), do: acc

  defp collect_owned_field_vars({:ctor, ctor, argpats}, ctx, acc) do
    case Map.get(ctx.meta, PL.to_snake(ctor)) do
      %{field_types: fts} ->
        argpats
        |> Enum.zip(fts)
        |> Enum.reduce(acc, fn
          {{:var, n}, ft}, a -> if owned_value_type?(ft), do: MapSet.put(a, n), else: a
          {_, _}, a -> a
        end)

      _ ->
        acc
    end
  end

  defp collect_owned_field_vars(_pat, _ctx, acc), do: acc

  defp owned_scrut?({:ctor, _, _}, _ctx), do: true

  defp owned_scrut?({:call, {:id, f}, args}, ctx) do
    case Map.get(ctx.funs, {f, length(args)}) do
      %{ret: ret} -> owned_value_type?(ret) or user_type?(ret, ctx)
      _ -> false
    end
  end

  defp owned_scrut?(_, _ctx), do: false

  defp owned_value_type?("Vec(" <> _), do: true
  defp owned_value_type?("String"), do: true
  defp owned_value_type?(_), do: false

  defp user_type?(t, ctx),
    do: Map.has_key?(ctx.smeta, t) or Enum.any?(ctx.meta, fn {_, m} -> m.enum == t end)

  defp owned_field_var?({:id, v}, ec),
    do: MapSet.member?(ec.owned_fields, v)

  defp owned_field_var?(_, _ec), do: false

  # the clause vars that are a runtime `&`-reference (see `rust_fn`): a pattern var
  # binding a `&`-typed param, plus any cons-tail (`@..`) binder. Cloned element/field
  # binders and literals are owned and excluded.
  defp borrowed_vars(params, pats) do
    direct =
      Enum.zip(params, pats)
      |> Enum.flat_map(fn {p, pat} ->
        ref? = borrow_type?(Rian.Capability.rust_param(p.cap, p.type))
        borrowed_in_pat(Core.from_pat(pat), ref?)
      end)

    MapSet.new(direct)
  end

  # a plain var bound to a `&`-param is a reference; a cons-tail binder is `&[T]`;
  # destructured element/field binders are cloned to owned, so excluded.
  defp borrowed_in_pat(%PVar{name: n}, true), do: [n]
  defp borrowed_in_pat(%PList{tail: %PVar{name: n}}, _ref?), do: [n]
  defp borrowed_in_pat(_pat, _ref?), do: []

  # the clause vars that are a `&[T]` SLICE (a `Vec`-typed `val` param, or a cons-tail
  # `@..` binder) — distinct from a single `&T` borrow. A slice stored into an owned
  # `Vec<T>` (a field, a `Vec` return) needs `.to_vec()`, not `.clone()` (which would
  # clone the reference, staying `&[T]`). Gaps D/E (ADR-0061).
  defp slice_binders(params, pats) do
    param_slices =
      params
      |> Enum.filter(&String.starts_with?(Rian.Capability.rust_param(&1.cap, &1.type), "&["))
      |> Enum.map(& &1.name)

    tails = Enum.flat_map(pats, fn pat -> cons_tail_names(Core.from_pat(pat)) end)
    MapSet.new(param_slices ++ tails)
  end

  defp cons_tail_names(%PList{tail: %PVar{name: n}}), do: [n]
  defp cons_tail_names(_), do: []

  defp slice_var?(%EId{name: n}, ec),
    do: MapSet.member?(ec.slices, n)

  defp slice_var?(_, _ec), do: false

  # a clause body (a single-expression block) whose value is a `&[T]` slice binder
  defp tail_slice_id?(%EBlock{stmts: [{:expr, e}]}, ec), do: slice_var?(e, ec)
  defp tail_slice_id?(e, ec), do: slice_var?(e, ec)

  # the callee's parameter Rust types, or nil when the callee is unknown (an
  # external/primitive call — leave its args untouched)
  defp param_rtypes(name, arity, funs) do
    case Map.get(funs, {name, arity}) do
      %{params: ps} -> Enum.map(ps, fn p -> Rian.Capability.rust_param(p.cap, p.type) end)
      _ -> nil
    end
  end

  defp borrow_type?("&" <> _), do: true
  defp borrow_type?(_), do: false

  # a `&impl Fn(...)` callback param — the by-reference closure lowering (ADR-0061).
  defp fn_borrow?("&impl Fn(" <> _), do: true
  defp fn_borrow?(_), do: false

  # an owned bare variable cloned into a by-value closure-call argument (the `&impl Fn`
  # callback takes its args by value); a computed expression or literal is already owned.
  defp closure_arg(%Core.EId{} = a, ec), do: p(a, 12, :rust, ec) <> ".clone()"
  defp closure_arg(a, ec), do: p(a, 0, :rust, ec)

  # does this argument expression produce an owned `Vec`/`String`?
  defp owned_arg?({:list_lit, _, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_from_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_concat"}, _}, _funs), do: true

  defp owned_arg?({:call, {:id, name}, args}, funs) do
    case Map.get(funs, {name, length(args)}) do
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
  defp with_chain_rs([], body, _else_rs, _ec), do: "{ #{body} }"

  defp with_chain_rs([{pt, e} | rest], body, else_rs, ec) do
    fallback = if else_rs == "", do: "__w => __w,", else: "__w => match __w { #{else_rs} },"

    "match #{p(e, 0, :rust, ec)} { #{rpat(pt)} => #{with_chain_rs(rest, body, else_rs, ec)} #{fallback} }"
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

  defp cap_arity(%EMapUpdate{base: base, pairs: ps}),
    do: Enum.reduce(ps, cap_arity(base), fn {_, v}, acc -> max(cap_arity(v), acc) end)

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
  # as-pattern `name @ pat` → Elixir `pat = name`.
  defp pat_ex(%Core.PAs{name: n, pat: p}), do: "#{pat_ex(p)} = #{n}"
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

  # a pin `^x` → Elixir `^x` (the `:elixir` text path is a BEAM verification backend).
  defp pat_ex(%Core.PPin{expr: {:id, name}}), do: "^#{name}"

  # bitstring pattern (ADR-0078) — the `:elixir` text path is a BEAM verification
  # backend, so it emits real `<<seg::spec>>`; each segment value is itself a pattern.
  defp pat_ex(%Core.PBitstr{segments: segs}),
    do: "<<#{Enum.map_join(segs, ", ", fn {v, specs} -> bitseg_pat_ex(v, specs) end)}>>"

  defp bitseg_pat_ex(value, specs) do
    v = pat_ex(value)
    if specs == [], do: v, else: "#{v}::#{Enum.map_join(specs, "-", &bitspec_elixir/1)}"
  end

  # ── Rust backend ───────────────────────────────────────────────────────
  @spec to_rust(map(), list(), term(), list(), map(), map(), map()) :: term()
  def to_rust(func, types, meta, structs \\ [], smeta \\ %{}, proto \\ %{}, ic \\ %{}) do
    enums = Enum.map_join(types, "\n\n", &rust_enum/1)
    struct_defs = Enum.map_join(structs, "\n\n", &rust_struct/1)
    base_ec = emit_ctx(%{proto: proto})

    [struct_defs, enums, rust_fn(func, ctx(meta, smeta, MapSet.new(), %{}, ic), "", base_ec)]
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
  @spec rust_protocols(list(), list(), list(), list()) :: term()
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

    base_ec = emit_ctx(%{proto: proto_method_traits(protocols)})

    [struct_defs, enums, trait_impl_block(protocols, impl_decls, c, base_ec)]
    |> Enum.reject(&(&1 in ["", nil]))
    |> Enum.join("\n\n")
  end

  # the traits + impls alone (no type/struct preamble) — for whole-program
  # assembly, where the types are emitted once at the top. `base_ec` carries the
  # program-wide proto map the impl-method bodies need for the UFCS rewrite.
  defp trait_impl_block(protocols, impl_decls, c, base_ec) do
    traits = Enum.map_join(protocols, "\n\n", &rust_trait/1)
    impls = Enum.map_join(impl_decls, "\n\n", &rust_impl(&1, protocols, c, base_ec))
    [traits, impls] |> Enum.reject(&(&1 in ["", nil])) |> Enum.join("\n\n")
  end

  @doc """
  Assemble a whole parsed program into **one** Rust module (ADR-0061): every
  `enum`/`struct`/`trait`/`impl` is emitted once, then every non-dispatch
  top-level function (the BEAM/JS runtime dispatcher is dropped — Rust uses
  traits). This composes the stdlib + protocols + generics that the per-unit
  `to_rust` cannot (it repeats type defs per unit).
  """
  @spec rust_program(map(), map()) :: term()
  def rust_program(prog, ic \\ %{}) do
    # Erase abstract types to their base (ADR-0067) — a whole-program Rust emit
    # entry reached directly (e.g. tests), so it must erase like `Decl.compile`.
    prog = Rian.Opaque.erase(prog)
    types = Map.get(prog, :types, [])
    structs = Map.get(prog, :structs, [])
    funcs = Map.get(prog, :funcs, []) |> Enum.reject(& &1.dispatch)
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    sigs = Map.new(Map.get(prog, :funcs, []), fn f -> {{f.name, length(f.params)}, f} end)
    # parametric user types (ADR-0061): `type Pair := P(k K, v V)` -> %{"Pair" => ["K","V"]}.
    # Rian writes them bare (`Vec(Pair)`); Rust needs `Pair<K, V>`, so the enum is emitted
    # with `<…>` params and every signature/return mentioning `Pair` is rewritten to its
    # instantiation (the function's tvars, or concrete args inferred from a builder's body).
    parametric = parametric_param_map(types)
    # the program-wide emitter context: the proto/parametric/sigs maps that the
    # per-function/per-clause ec extends. Threaded explicitly (no process dict).
    base_ec =
      emit_ctx(%{proto: proto_method_traits(protocols), parametric: parametric, sigs: sigs})

    c = ctx(build_meta(types), build_struct_meta(structs), MapSet.new(), sigs, ic)

    [
      Enum.map_join(structs, "\n\n", &rust_struct/1),
      Enum.map_join(types, "\n\n", &rust_enum(&1, "", parametric)),
      trait_impl_block(protocols, impl_decls, c, base_ec),
      Enum.map_join(funcs, "\n\n", &rust_fn(&1, c, "", base_ec)),
      # sibling `mod`s become Rust `mod snake { … }` (each self-contained — see
      # `module_rust/1`), so a cross-module call `Mod.fun(…)` -> `snake::fun(…)`
      # resolves. This is how the injected `Show` (ADR-0069 `${float}`) is emitted.
      Enum.map_join(Map.get(prog, :mods, []), "\n\n", &module_rust(&1, ic))
    ]
    |> Enum.reject(&(&1 in ["", nil]))
    |> Enum.join("\n\n")
  end

  defp proto_method_traits(protocols),
    do: for(p <- protocols, m <- p.methods, into: %{}, do: {m.name, p.name})

  defp rust_trait(%{name: name, methods: methods} = p) do
    # associated types (ADR-0074 Stage 3): `type Elem` declares `type Elem;` in the
    # trait, and each projection in a method signature becomes `Self::Elem`.
    assoc = Map.get(p, :assoc, [])
    type_members = Enum.map_join(assoc, "", &"    type #{&1};\n")

    sigs =
      Enum.map_join(methods, "\n", fn m ->
        sig =
          "    fn #{m.name}(#{trait_params(m.params, "Self")}) -> #{rust_ret(self_subst(m.ret, "Self"))};"

        assoc_proj(sig, assoc)
      end)

    "trait Rian#{name} {\n#{type_members}#{sigs}\n}"
  end

  # project each associated-type name to its `Self::Name` use inside a trait sig.
  defp assoc_proj(s, assoc),
    do: Enum.reduce(assoc, s, fn a, acc -> word_replace(acc, a, "Self::#{a}") end)

  # substitute each associated-type name with its concrete Rust type (the impl side):
  # `%{"Elem" => "i64"}` turns `Vec<Elem>` into `Vec<i64>`.
  defp subst_assoc(t, assoc_rust),
    do: Enum.reduce(assoc_rust, t, fn {a, r}, acc -> word_replace(acc, a, r) end)

  defp rust_impl(%{proto: proto, type: type, methods: methods} = impl, protocols, c, base_ec) do
    # associated-type bindings (ADR-0074 Stage 3): `type Elem := Int53` emits
    # `type Elem = i64;` in the impl, and every `Elem` in the protocol's method sigs is
    # substituted to the concrete Rust type for this impl (so a `-> Vec<Elem>` becomes
    # `-> Vec<i64>` and the body's coerce_ret sees a real type).
    assoc_rust = Map.new(Map.get(impl, :assoc, %{}), fn {a, ty} -> {a, prim_rust(ty)} end)
    type_members = Enum.map_join(assoc_rust, "", fn {a, r} -> "    type #{a} = #{r};\n" end)

    sig_for =
      protocols
      |> Enum.find(%{methods: []}, &(&1.name == proto))
      |> Map.fetch!(:methods)
      |> Map.new(fn m ->
        {m.name,
         %{m | ret: subst_assoc(m.ret, assoc_rust), params: subst_assoc(m.params, assoc_rust)}}
      end)

    rust_type = rust_proto_type!(type)
    copy_recv? = Rian.Capability.copy?(type)

    bodies =
      Enum.map_join(
        methods,
        "\n",
        &rust_impl_method(&1, sig_for[&1.name], rust_type, c, copy_recv?, base_ec)
      )

    "impl Rian#{proto} for #{rust_type} {\n#{type_members}#{bodies}\n}"
  end

  # the Rust spelling of an impl target type: a primitive maps via `Capability`,
  # a sum/struct keeps its (PascalCase) name.
  defp rust_proto_type!(type), do: Rian.Capability.rust_name(type)

  defp rust_impl_method(method, sig, rust_type, c, copy_recv?, base_ec) do
    [recv | rest_names] = method.params |> pcommas() |> Enum.map(&String.trim/1)
    rest_sig = tl(pcommas(sig.params))

    params =
      ["&self" | Enum.zip(rest_names, rest_sig) |> Enum.map(&impl_param(&1, rust_type))]
      |> Enum.join(", ")

    ret_ty = self_subst(sig.ret, rust_type)
    {ok?, err?} = result_str_flags(ret_ty)
    ec = %{base_ec | ok_string: ok?, err_string: err?}
    body = method.body |> rust_proto_body(c, ec) |> coerce_ret(ret_ty)
    # A Copy-primitive receiver used as a *value* — an `if` condition, arithmetic —
    # needs an owned binding: `&self` cannot stand where `bool`/`i64` is expected
    # (rustc E0308, e.g. `Show for Bool`'s `if b`). Deref-copy it when the impl target
    # is Copy AND no *other* param is `Self`: a comparison method (`eq(a Self, b Self)`)
    # keeps both operands borrowed so `&T == &T` still type-checks, while a
    # single-receiver method (`show`) is exactly the value case.
    other_self? = Enum.any?(rest_sig, fn p -> elem(name_type(p), 1) == "Self" end)
    recv_rhs = if copy_recv? and not other_self?, do: "*self", else: "self"

    "    fn #{method.name}(#{params}) -> #{rust_ret(ret_ty)} { let #{recv} = #{recv_rhs}; #{body} }"
  end

  # a Rian string literal lowers to a Rust `&str`, so a function (or impl method)
  # declared to return `String` must coerce its body to the owned type the
  # signature promises. Applied per clause arm in `rust_fn` and to impl-method
  # bodies in `rust_impl_method`; `.to_string()` is a no-op clone when the body
  # already yields a `String` (e.g. a `<>` concat that lowered to `format!`).
  defp coerce_ret(body, "String"), do: "(#{body}).to_string()"
  defp coerce_ret(body, _ret), do: body

  # A `String | E` return wraps its value in `Ok(…)`/`Err(…)` (ADR-0040): an
  # `Ok("hi")` is `Result<&str, _>`, not the `Result<String, _>` the signature
  # promises, so the *payload* needs the same `&str -> String` coercion `coerce_ret`
  # applies to a plain `String` body. These per-function flags — folded into the
  # emitter context `ec` in `rust_fn` / `rust_impl_method` — tell the `Ok`/`Err`
  # emit whether its payload type is `String`. `.to_string()` is a no-op clone when
  # the payload is already a `String`.
  defp result_str_flags(ret) do
    case result_parts(ret) do
      {:result, ok, err} -> {ok == "String", err == "String"}
      _ -> {false, false}
    end
  end

  # the payload of `Ok(_)`/`Err(_)` must be owned: a borrowed `&T` (a generic ok-type,
  # `def f() T | E := {:ok, x}`) is `.clone()`d like any owned-position value
  # (`rust_owned_elem`), and a `&str` for a `String` ok/err-type additionally `.to_string()`s.
  defp result_payload(val, string?, ec) do
    s = rust_owned_elem(val, ec)
    if string?, do: "(#{s}).to_string()", else: s
  end

  defp impl_param({name, sig_p}, rust_type) do
    {_n, ty} = name_type(sig_p)
    "#{name}: #{ref_type(ty, rust_type)}"
  end

  # lower an impl-method body through the same Rust pipeline `rust_fn` uses,
  # rewriting protocol-method calls to UFCS first. `ec` carries the proto map (for
  # the UFCS rewrite) and the per-method result-string flags (for `Ok`/`Err` emit).
  defp rust_proto_body(src, c, ec) do
    src
    |> body_ast(c)
    |> rewrite_proto_calls(ec.proto)
    |> resolve_rust_pats(c.meta)
    |> insert_borrows(Map.get(c, :funs, %{}), ec)
    |> Rian.Check.annotate(ec.tenv, ec.ic)
    |> emit(:rust, ec)
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

  defp self_subst(t, repr), do: word_replace(t, "Self", repr)

  # rewrite a protocol-method call `m(recv, rest…)` to Rust **method-call** syntax
  # `recv.m(rest…)` so rustc dispatches statically. Method-call (not UFCS
  # `Trait::m(recv, …)`) auto-refs the receiver, so it works whether `recv` is a
  # `&T` parameter or an owned `T` (a cloned slice-element binder) — both reach
  # the `&self` method. Non-protocol calls pass through.
  @spec rewrite_proto_calls(term(), term()) :: term()
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
        bounds_map =
          case bounds do
            nil -> %{}
            b -> b
          end

        traits = Enum.map(Map.get(bounds_map, tv, []), &"Rian#{&1}") ++ ["Clone"]
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
  defp rust_fn(func, ctx, vis, base_ec \\ nil)

  defp rust_fn(%{externals: ext} = func, _ctx, vis, _base_ec) when map_size(ext) > 0 do
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

  defp rust_fn(func, ctx, vis, base_ec) do
    # the program-wide emitter context (proto/parametric/sigs). A per-unit entry
    # (`to_rust`/`module_rust`) passes none — default to empty maps.
    base_ec =
      case base_ec do
        nil -> emit_ctx()
        v -> v
      end

    # parametric-type instantiation for this function (ADR-0061): `Pair` -> `Pair<K, V>`
    # (a generic function reuses `Pair`'s param names) or `Pair<i64, i64>` (a concrete
    # builder, inferred from its body). `pinst` rewrites the Rust type strings; `gen_func`
    # carries any free parametric tvars (e.g. `has`'s `V`) into the generic list.
    pinst = pair_inst(func, base_ec)
    gen_func = Map.put(func, :tvars, fn_all_tvars(func, pinst, base_ec))

    param_decls =
      Enum.map_join(func.params, ", ", fn p ->
        "#{p.name}: #{rustify_parametric(Rian.Capability.rust_param(p.cap, p.type), pinst)}"
      end)

    # One param matches the value directly; N>1 match the tuple of arguments
    # (clauses-guards §5.2). A `val Vec` param lowers to a `&[T]` slice, so cons
    # patterns match it directly; an `iso Vec` param is an owned `Vec<T>`, so it
    # is matched via `.as_slice()` and its binders are made owned again
    # (`rust_rebinds/2`) — letting a cons function *return* or *rebuild* a list
    # (e.g. `cat`) lower with owned semantics (ADR-0047).
    iso = iso_cons_positions(func)
    scrut = rust_scrut(func.params, iso)
    # a `String | E` return makes `Ok(payload)` need the payload coerced to owned
    # `String` (an `Ok("hi")` is `Result<&str, _>`); flag it for the `Ok`/`Err` emit.
    {ok?, err?} = result_str_flags(func.ret)
    fn_ec = %{base_ec | ok_string: ok?, err_string: err?}

    # A generic function (ADR-0061) borrows its `T`/`Vec(T)`/`String` params as
    # `&T`/`&[T]`/`&str`, so an *owned* value (a literal, a cloned slice/field binder,
    # an owned-returning call) passed to a `&T` param needs `&`, and a *borrowed* value
    # returned/constructed where an owned `T` is wanted needs `.clone()`. The owned↔
    # borrow coercion below is gated on `tvars != []`: a non-generic function keeps the
    # existing path exactly (it never had this gap), so this cannot regress it.
    generic? = Map.get(func, :tvars, []) != []

    arms =
      Enum.map_join(func.clauses, "\n", fn c ->
        pat = tuple_or_one(c.pats, &core_pat_rs(&1, ctx.meta))
        # `borrowed`: the clause vars that are a `&`-reference at runtime — a pattern
        # var binding a `&`-typed param, and a cons-tail (`@..`) binder. Every other
        # value (literal, cloned element/field binder, owned call) is owned.
        borrowed = if generic?, do: borrowed_vars(func.params, c.pats), else: nil

        # Resolve construction (struct + variant), constant references, and `case`
        # patterns on the surface (where the meta is available), then translate to
        # the typed core IR the emitter consumes (ADR-0050).
        pre =
          c.body
          |> body_ast(ctx)
          |> widen_char_arith(char_vars(func.params, c.pats))
          |> rewrite_proto_calls(base_ec.proto)

        # the per-clause emitter context: the per-function flags/program maps (`fn_ec`)
        # plus this clause's borrow/slice/owned-field sets. `owned_fields` (Gap C) must
        # be collected from the structured `{:ctor, …}` arms in `pre`, before
        # `resolve_rust_pats` stringifies them.
        # the per-clause typing env types the body's core IR (ADR-0050 §3).
        tenv = Rian.Check.clause_env(c.pats, func.params, ctx.ic)

        ec = %{
          fn_ec
          | borrowed:
              case borrowed do
                nil -> MapSet.new()
                v -> v
              end,
            slices: slice_binders(func.params, c.pats),
            owned_fields: owned_field_binders(pre, ctx),
            tenv: tenv,
            ic: ctx.ic
        }

        surface =
          pre
          |> resolve_rust_pats(ctx.meta)
          |> insert_borrows(Map.get(ctx, :funs, %{}), ec, borrowed)

        ast = Rian.Check.annotate(surface, tenv, ctx.ic)
        body = emit(ast, :rust, ec) |> elem(0)
        rebinds = arm_rebinds(c.pats, iso, used_ids(surface))

        arm =
          if rebinds == [],
            do: rust_arm_body(ast, body),
            else: "{ #{Enum.join(rebinds, " ")} #{body} }"

        # a `String`-returning function lowers its clause bodies to `&str`; coerce
        # the arm so the owned `String` the signature promises is produced (a
        # no-op clone if the arm already yields a `String`). For a no-rebind body
        # the coercion is pushed into `if`/`case` TAIL leaves (Gap B) so a `&str`
        # literal arm unifies with a `String` arm; otherwise it wraps the arm.
        arm =
          if func.ret == "String" and rebinds == [],
            do: coerce_string_ast(ast, ec),
            else: coerce_ret(arm, func.ret)

        # Gap E: a clause that returns a bare `&[T]` slice binder where a `Vec<T>` is
        # promised needs `.to_vec()` (e.g. `def drop(cs, 0) := cs`). The body is a
        # single-expression block, so unwrap it to reach the bare binder.
        arm =
          if match?("Vec(" <> _, func.ret) and tail_slice_id?(ast, ec),
            do: "(#{arm}).to_vec()",
            else: arm

        # a generic function returning a bare owned type variable (`T`) yields a
        # borrowed `&T` in its base arms (a returned param); `.clone()` to the owned
        # `T` the signature promises (`T: Clone`, `rust_generics`). A no-op clone when
        # the arm already owns its `T`. `Vec(T)` returns are owned constructions already.
        arm = if generic? and func.ret in func.tvars, do: "(#{arm}).clone()", else: arm

        # a closure-RETURNING function (`… Fn(args, ret) := (x) -> …`, ADR-0061): the
        # return type lowered to `Box<dyn Fn…>` (see `Capability.owned`), so the returned
        # closure is boxed and `move`-captures (it outlives the function frame). Applies
        # when the arm is a bare closure (`|…| …`); a more complex tail stays off `:rs`.
        arm =
          if match?("Fn(" <> _, func.ret) and String.starts_with?(arm, "|"),
            do: "Box::new(move #{arm})",
            else: arm

        # binders bound inside a list/slice element are `&T` — a guard over them
        # must deref (`*c`); the arm body's arithmetic works on `&T` directly
        deref = Enum.flat_map(c.pats, fn p -> slice_elem_vars(Core.from_pat(p)) end)
        "        #{pat}#{guard_str(c, :rust, ec, deref)} => #{arm},"
      end)

    # Per-target exhaustiveness shim (ADR-0036): a `range`-total match has literal
    # arms over an *open* base primitive (`i64`/`char`), which `rustc` sees as
    # non-exhaustive. The Rian gate already proved totality, so append an
    # `unreachable!()` arm — never reached, satisfies rustc. (Sum-type matches are
    # closed and need no shim; a `_`/var clause already provides the fallthrough.)
    shim = if rust_total_shim?(func), do: "\n        _ => unreachable!(),", else: ""

    fn_str =
      "#{vis}fn #{func.name}#{rust_generics(gen_func)}(#{param_decls}) -> " <>
        "#{rustify_parametric(rust_ret(func.ret), pinst)} {\n" <>
        "    match #{scrut} {\n#{arms}#{shim}\n    }\n}"

    join_doc(rs_doc(Map.get(func, :doc), "///"), fn_str)
  end

  # the instantiation of each parametric type this function's signature mentions:
  # `%{"Pair" => "<K, V>"}` (generic — reuse the type's param names) or
  # `%{"Pair" => "<i64, i64>"}` (a concrete builder — inferred from the body).
  defp pair_inst(func, ec) do
    pmap = ec.parametric
    generic? = Map.get(func, :tvars, []) != []

    for {name, params} <- pmap, parametric_used?(func, name), into: %{} do
      args = if generic?, do: params, else: infer_concrete_params(func, params, ec)
      {name, "<#{Enum.join(args, ", ")}>"}
    end
  end

  # does a parametric type `name` appear (as a whole word) in the function's signature?
  defp parametric_used?(func, name) do
    sig = Enum.map(func.params, & &1.type) ++ [func.ret]
    Enum.any?(sig, fn t -> is_binary(t) and word_member?(t, name) end)
  end

  # all generic params for a parametric-using generic function: its own tvars plus any
  # free param tvars of the parametric types it uses (e.g. `has` over `Pair` gains `V`).
  defp fn_all_tvars(func, pinst, ec) do
    tvars = Map.get(func, :tvars, [])

    if tvars == [] do
      tvars
    else
      pmap = ec.parametric
      extra = pinst |> Map.keys() |> Enum.flat_map(&Map.get(pmap, &1, [])) |> Enum.uniq()
      tvars ++ (extra -- tvars)
    end
  end

  # rewrite each parametric type name in a Rust type string to its instantiation:
  # `&[Pair]` + `%{"Pair" => "<K, V>"}` -> `&[Pair<K, V>]`.
  defp rustify_parametric(rust_type, pinst) do
    Enum.reduce(pinst, rust_type, fn {name, args}, acc ->
      word_replace(acc, name, "#{name}#{args}")
    end)
  end

  # Whole-word string substitution — the char-scan port of `~r/\bname\b/` from the
  # self-hosted compiler/rust.rian (`splice_one`/`splice_scan`). No regex engine, no
  # `Regex.escape` foot-gun: a match fires only when the chars bracketing `name` are
  # non-word (word chars are `[A-Za-z0-9_]`, matching `\w`). `prev` carries whether
  # the char just emitted was a word char (the left boundary).
  defp word_replace(str, name, repl),
    do: word_scan(String.to_charlist(str), String.to_charlist(name), repl, false)

  defp word_scan([], _name, _repl, _prev), do: ""

  defp word_scan([c | cs] = chars, name, repl, prev) do
    case strip_prefix(chars, name) do
      {:ok, rest} when not prev ->
        if head_word?(rest),
          do: <<c::utf8>> <> word_scan(cs, name, repl, word_char?(c)),
          else: repl <> word_scan(rest, name, repl, true)

      _ ->
        <<c::utf8>> <> word_scan(cs, name, repl, word_char?(c))
    end
  end

  # does `name` occur as a whole word in `str`? (the predicate side of `word_replace`)
  defp word_member?(str, name),
    do: member_scan(String.to_charlist(str), String.to_charlist(name), false)

  defp member_scan([], _name, _prev), do: false

  defp member_scan([c | cs] = chars, name, prev) do
    case strip_prefix(chars, name) do
      {:ok, rest} when not prev -> not head_word?(rest) or member_scan(cs, name, word_char?(c))
      _ -> member_scan(cs, name, word_char?(c))
    end
  end

  defp strip_prefix(rest, []), do: {:ok, rest}
  defp strip_prefix([c | cs], [c | ps]), do: strip_prefix(cs, ps)
  defp strip_prefix(_chars, _name), do: :nomatch

  defp head_word?([c | _]), do: word_char?(c)
  defp head_word?([]), do: false

  defp word_char?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_

  # concrete instantiation for a non-generic builder (`sample`/`names`): infer the
  # parametric type's args from the body's tail — a call to a generic constructor
  # (`put`) binds the type's params from its argument literal types.
  defp infer_concrete_params(func, params, ec) do
    binding =
      func.clauses
      |> hd()
      |> Map.fetch!(:body)
      |> Pratt.parse_body()
      |> tail_expr()
      |> infer_tvar_binding(ec)

    Enum.map(params, fn tv -> Map.get(binding, tv, "i64") end)
  end

  defp tail_expr({:block, stmts}) do
    case List.last(stmts) do
      {:expr, e} -> e
      other -> other
    end
  end

  defp tail_expr(e), do: e

  defp infer_tvar_binding({:call, {:id, f}, args}, ec) do
    case Map.get(ec.sigs, {f, length(args)}) do
      %{params: ps, tvars: tvs} when tvs != [] ->
        Enum.zip(ps, args)
        |> Enum.reduce(%{}, fn {p, a}, acc ->
          if p.type in tvs, do: Map.put(acc, p.type, rust_lit_type(a)), else: acc
        end)

      _ ->
        %{}
    end
  end

  defp infer_tvar_binding(_, _ec), do: %{}

  # the Rust type of a literal argument (for concrete parametric instantiation).
  defp rust_lit_type({:num, n}), do: if(String.contains?(n, "."), do: "f64", else: "i64")
  defp rust_lit_type({:str, _}), do: "String"
  defp rust_lit_type({:char_lit, _}), do: "char"
  defp rust_lit_type(_), do: "i64"

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
  defp arm_rebinds(pats, iso, used) do
    pats
    |> Enum.with_index()
    |> Enum.flat_map(fn {pat, i} ->
      core = Core.from_pat(pat)

      # Only rebind a head the body actually uses: a binder used solely by the
      # guard (`*c == 32`) needs no owned `let c = c.clone();`, which `rustc`
      # would flag as an unused variable.
      heads =
        core
        |> slice_elem_vars()
        |> Enum.filter(&MapSet.member?(used, &1))
        |> Enum.map(&"let #{&1} = #{&1}.clone();")

      tails = if MapSet.member?(iso, i), do: cons_tail_rebinds(core), else: []
      heads ++ tails
    end)
  end

  defp cons_tail_rebinds(%PList{tail: %PVar{name: n}}), do: ["let #{n} = #{n}.to_vec();"]
  defp cons_tail_rebinds(_), do: []

  # identifier names referenced anywhere in a surface-tuple expression
  defp used_ids(ast), do: collect_ids(ast, MapSet.new())
  defp collect_ids({:id, n}, acc), do: MapSet.put(acc, n)

  defp collect_ids(t, acc) when is_tuple(t),
    do: Enum.reduce(Tuple.to_list(t), acc, &collect_ids/2)

  defp collect_ids(l, acc) when is_list(l), do: Enum.reduce(l, acc, &collect_ids/2)
  defp collect_ids(_, acc), do: acc

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

  defp rust_enum(t, vis \\ "", parametric \\ %{}) do
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
      "#[derive(Clone, Debug, PartialEq)]\n#{vis}enum #{t.name}#{enum_generics(t.name, parametric)} {\n#{variants}\n}"
    )
  end

  # `<K, V>` for a parametric type (its variant fields are typed by type variables),
  # else `""`. The params are the distinct field tvars in order of appearance.
  defp enum_generics(name, parametric) do
    case Map.get(parametric, name) do
      nil -> ""
      [] -> ""
      params -> "<#{Enum.map_join(params, ", ", &"#{&1}: Clone")}>"
    end
  end

  # parametric user types: name -> ordered list of its field type-variable params.
  defp parametric_param_map(types) do
    for t <- types, params = type_param_tvars(t), params != [], into: %{}, do: {t.name, params}
  end

  defp type_param_tvars(t) do
    t.variants
    |> Enum.flat_map(fn v -> Enum.map(v.fields, &Map.get(&1, :type)) end)
    |> Enum.filter(&tvar_name?/1)
    |> Enum.uniq()
  end

  # a bare type variable name: a single uppercase letter optionally followed by digits
  defp tvar_name?(t) when is_binary(t), do: String.match?(t, ~r/^[A-Z][0-9]*$/)
  defp tvar_name?(_), do: false

  # surface pattern -> typed core IR -> Rust (ADR-0050: emitter consumes the core)
  defp core_pat_rs(surface, meta), do: pat_rs(Core.from_pat(surface), meta)

  defp pat_rs(%PWild{}, _), do: "_"
  defp pat_rs(%PVar{name: x}, _), do: x
  # as-pattern: Rust spells it `name @ pat`.
  defp pat_rs(%Core.PAs{name: n, pat: p}, m), do: "#{n} @ #{pat_rs(p, m)}"
  defp pat_rs(%PLit{value: v}, _) when is_binary(v), do: str_lit(v)
  defp pat_rs(%PLit{value: v}, _), do: to_string(v)
  # a `Char` literal pattern is a native Rust `char` literal (ADR-0036)
  defp pat_rs(%Core.PChar{value: cp}, _), do: rust_char_lit(cp)
  defp pat_rs(%PTuple{elems: [%PAtom{name: "ok"}, p]}, m), do: "Ok(#{pat_rs(p, m)})"
  defp pat_rs(%PTuple{elems: [%PAtom{name: "error"}, p]}, m), do: "Err(#{pat_rs(p, m)})"
  defp pat_rs(%PTuple{elems: ps}, m), do: "(#{Enum.map_join(ps, ", ", &pat_rs(&1, m))})"
  defp pat_rs(%PAtom{name: a}, _), do: raise("Erlang atom pattern is BEAM-only: :#{a}")
  defp pat_rs(%Core.PBitstr{}, _), do: raise("bitstring patterns are BEAM-only (ADR-0078)")
  defp pat_rs(%Core.PPin{}, _), do: raise("pin patterns not yet lowered to Rust (guard form)")

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
  @spec emit_expr(String.t(), atom()) :: term()
  def emit_expr(src, target),
    do: emit(Rian.Check.annotate(Rian.Pratt.parse(src), %{}, %{}), target, emit_ctx()) |> elem(0)

  @doc "Emit an already-built AST (e.g. after macro expansion / comptime folding)."
  @spec emit_ast(term(), atom()) :: term()
  def emit_ast(ast, target),
    do: emit(Rian.Check.annotate(ast, %{}, %{}), target, emit_ctx()) |> elem(0)

  # emit/3 -> {string, prec}; p/4 wraps in parens when prec < ctx.
  defp p(node, ctx, t, ec) do
    {s, pr} = emit(node, t, ec)
    if pr < ctx, do: "(" <> s <> ")", else: s
  end

  # ── Elixir-text scope (for the variable-application distinction) ─────────
  # On the BEAM/Elixir target, applying a function-*valued variable* (a param or
  # binding) is `f.(x)`, while a local function call is `f(x)`. We track the set
  # of in-scope bound names — grown by clause heads, `:=` binds, lambda params,
  # and `case` arm patterns — exactly as `Rian.Beam` does, so the text view
  # matches the real BEAM backend (no drift). Carried in `ec.ex_scope` and
  # extended functionally per subtree; the Rust target calls closures directly
  # and never consults it.

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
  defp str_lit(s),
    do: ~s(") <> for(cp <- String.to_charlist(s), into: "", do: str_lit_cp(cp)) <> ~s(")

  defp str_lit_cp(?\\), do: "\\\\"
  defp str_lit_cp(?"), do: "\\\""
  defp str_lit_cp(?\n), do: "\\n"
  defp str_lit_cp(?\r), do: "\\r"
  defp str_lit_cp(?\t), do: "\\t"

  defp str_lit_cp(cp) when cp < 0x20 or cp == 0x7F,
    do: "\\u{" <> Integer.to_string(cp, 16) <> "}"

  defp str_lit_cp(cp), do: <<cp::utf8>>

  defp emit(%ENum{text: n}, _t, _ec), do: {n, 12}
  # string literal — same surface on both targets (Rust yields `&str`)
  defp emit(%EStr{value: s}, _t, _ec), do: {str_lit(s), 12}
  # a `Char` (ADR-0036): a codepoint integer on the BEAM text target, a native
  # `char` literal on Rust. Convert to an integer with `__prim_char_code/1`.
  defp emit(%EChar{value: cp}, :elixir, _ec), do: {Integer.to_string(cp), 12}
  defp emit(%EChar{value: cp}, :rust, _ec), do: {rust_char_lit(cp), 12}
  defp emit(%EId{name: "pi"}, :elixir, _ec), do: {":math.pi()", 12}
  defp emit(%EId{name: "pi"}, :rust, _ec), do: {"std::f64::consts::PI", 12}
  defp emit(%EId{name: x}, _t, _ec), do: {x, 12}
  # atom literal / Erlang FFI (BEAM-only on Rust)
  defp emit(%EAtom{name: a}, :elixir, _ec), do: {":" <> a, 12}
  defp emit(%EAtom{name: a}, :rust, _ec), do: raise("Erlang atom is BEAM-only: :#{a}")
  defp emit(%EDot{head: %EAtom{name: m}, name: n}, :elixir, _ec), do: {":#{m}.#{n}", 12}

  defp emit(%EDot{head: %EAtom{name: m}}, :rust, _ec),
    do: raise("Erlang FFI is BEAM-only: :#{m}")

  # dotted access: Elixir uses `.` for both module calls and field access
  defp emit(%EDot{head: head, name: n}, :elixir, ec),
    do: {p(head, 12, :elixir, ec) <> ".#{n}", 12}

  # Rust: case of head/name selects field vs module-path vs type/variant-path
  defp emit(%EDot{head: %EId{name: m}, name: n}, :rust, _ec) do
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

  defp emit(%EDot{head: head, name: n}, :rust, ec), do: {p(head, 12, :rust, ec) <> "::#{n}", 12}

  # `String` primitives on Rust (ADR-0047 §2): a `String` is `&str`, codepoints
  # are native `char` (ADR-0036 — `Char` lowers to Rust `char`); these mirror the
  # BEAM/JS lowerings so portable `Str` ops compose.
  defp emit(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}, :rust, ec),
    do: {"#{p(s, 12, :rust, ec)}.chars().collect::<Vec<char>>()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}, :rust, ec),
    do: {"#{p(cs, 12, :rust, ec)}.iter().collect::<String>()", 12}

  # a `Char`'s codepoint as an integer — the explicit Char→Int conversion
  # (ADR-0036); `char as i64` is the native widening on Rust.
  defp emit(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, :rust, ec),
    do: {"(#{p(c, 12, :rust, ec)} as i64)", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, :elixir, ec),
    do: {p(c, 12, :elixir, ec), 12}

  # integer → string (ADR-0069 interpolation): native `to_string`/`Integer.to_string`
  defp emit(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, :rust, ec),
    do: {"#{p(n, 12, :rust, ec)}.to_string()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, :elixir, ec),
    do: {"Integer.to_string(#{p(n, 0, :elixir, ec)})", 12}

  # diverging abort (ADR-0035/0040): Rust `panic!` (type `!`, an expression) /
  # Elixir `raise`. Never returns, so it is well-typed in any position.
  defp emit(%ECall{fun: %EId{name: "__prim_panic"}, args: [msg]}, :rust, ec),
    do: {"panic!(\"{}\", #{p(msg, 0, :rust, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_panic"}, args: [msg]}, :elixir, ec),
    do: {"raise(#{p(msg, 0, :elixir, ec)})", 12}

  # float → shortest-round-trip scientific (ADR-0069 Float64 unlock); `Rian.Show.float`
  # normalizes it to the ECMAScript canonical. Rust `{:e}` and Erlang `[:short]` both
  # carry the unique shortest digits (different presentation, same digits).
  defp emit(%ECall{fun: %EId{name: "__prim_float_repr"}, args: [n]}, :rust, ec),
    do: {"format!(\"{:e}\", #{p(n, 0, :rust, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_float_repr"}, args: [n]}, :elixir, ec),
    do: {":erlang.float_to_binary(#{p(n, 0, :elixir, ec)}, [:short])", 12}

  # integer → float (ADR-0035 explicit conversion): Rust `n as f64`, Elixir `n * 1.0`
  defp emit(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [n]}, :rust, ec),
    do: {"(#{p(n, 12, :rust, ec)} as f64)", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [n]}, :elixir, ec),
    do: {"(#{p(n, 0, :elixir, ec)} * 1.0)", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}, :rust, ec),
    do: {"format!(\"{}{}\", #{p(a, 0, :rust, ec)}, #{p(b, 0, :rust, ec)})", 12}

  # variadic single-shot join (ADR-0069 §6): one `format!` (Rust, one allocation),
  # one binary comprehension (Elixir). Every part is already a `String`.
  defp emit(%ECall{fun: %EId{name: "__prim_str_concat_all"}, args: args}, :rust, ec),
    do:
      {"format!(\"#{String.duplicate("{}", length(args))}\", " <>
         Enum.map_join(args, ", ", &p(&1, 0, :rust, ec)) <> ")", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_str_concat_all"}, args: args}, :elixir, ec),
    do: {"<<" <> Enum.map_join(args, ", ", &(p(&1, 0, :elixir, ec) <> "::binary")) <> ">>", 12}

  # a `Char`'s single-character string (ADR-0069 §6): Rust `char` has `.to_string()`;
  # on Elixir a `Char` is a codepoint integer, so `<<cp::utf8>>` is its encoding.
  defp emit(%ECall{fun: %EId{name: "__prim_char_to_string"}, args: [c]}, :rust, ec),
    do: {"#{p(c, 12, :rust, ec)}.to_string()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_char_to_string"}, args: [c]}, :elixir, ec),
    do: {"<<#{p(c, 0, :elixir, ec)}::utf8>>", 12}

  # explicit overflow ops (ADR-0035 §3) on Rust — the native `i64` methods; this
  # is the target where overflow actually bites (debug panic / release wrap), so
  # `checked_add` returns `Option<i64>` (Rian `Option(Int64)`) directly.
  defp emit(%ECall{fun: %EId{name: "__prim_wrapping_add"}, args: [a, b]}, :rust, ec),
    do: {"#{p(a, 12, :rust, ec)}.wrapping_add(#{p(b, 0, :rust, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_saturating_add"}, args: [a, b]}, :rust, ec),
    do: {"#{p(a, 12, :rust, ec)}.saturating_add(#{p(b, 0, :rust, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_checked_add"}, args: [a, b]}, :rust, ec),
    do: {"#{p(a, 12, :rust, ec)}.checked_add(#{p(b, 0, :rust, ec)})", 12}

  # A named construction `Name(field: v, …)` (labeled args) lowers to the same
  # `__struct__`-tagged map `Rian.Beam` builds — `%{__struct__: :tag, field: v, …}`
  # with `tag = to_snake(Name)` — so the two backends stay forms-equivalent even
  # when `Name` is a struct not declared in this module.
  defp emit(%ECall{fun: %EId{name: f}, args: [%ELabel{} | _] = labels}, :elixir, ec) do
    fields =
      Enum.map_join(labels, ", ", fn %ELabel{name: k, expr: v} ->
        "#{k}: #{p(v, 0, :elixir, ec)}"
      end)

    {"%{__struct__: :#{PL.to_snake(f)}, #{fields}}", 12}
  end

  # applying a function-valued variable on Elixir is `f.(x)`, a local call is
  # `f(x)` — decided by whether `f` is in scope (matches `Rian.Beam`)
  defp emit(%ECall{fun: %EId{name: f}, args: args}, :elixir, ec) do
    inner = Enum.map_join(args, ", ", &p(&1, 0, :elixir, ec))

    if MapSet.member?(ec.ex_scope, f),
      do: {"#{f}.(#{inner})", 12},
      else: {"#{f}(#{inner})", 12}
  end

  # a closure-PARAMETER call `f(args)` on Rust: the `&impl Fn(...)` callback takes its args
  # by VALUE (ADR-0061), so clone a bare-variable argument — the binding stays usable for a
  # later use (e.g. `filter`'s `insert(0, h)`) and a borrowed param (`&U`) coerces to owned `U`.
  # A function NAME is `:unknown`-typed (not bound in the clause env), so only true closure
  # variables (whose type is the `Fn(...)` string) take this path.
  defp emit(%ECall{fun: %Core.EId{type: "Fn(" <> _} = f, args: args}, :rust, ec),
    do: {p(f, 12, :rust, ec) <> "(" <> Enum.map_join(args, ", ", &closure_arg(&1, ec)) <> ")", 12}

  defp emit(%ECall{fun: f, args: args}, t, ec),
    do: {p(f, 12, t, ec) <> "(" <> Enum.map_join(args, ", ", &p(&1, 0, t, ec)) <> ")", 12}

  # `&` captures (B'). Placeholders: Elixir's native `&N`, Rust's closure args `aN`.
  defp emit(%ECapArg{n: n}, :elixir, _ec), do: {"&#{n}", 12}
  defp emit(%ECapArg{n: n}, :rust, _ec), do: {"a#{n}", 12}

  # `&(&1 + &2)` — Elixir's native capture; Rust an explicit closure `|a1, a2| …`.
  defp emit(%ECapture{body: body}, :elixir, ec), do: {"&(#{p(body, 0, :elixir, ec)})", 12}

  defp emit(%ECapture{body: body}, :rust, ec) do
    {"|#{closure_params(1, cap_arity(body))}| #{p(body, 0, :rust, ec)}", 12}
  end

  # `&name/arity` — Elixir's native capture; Rust a forwarding closure.
  defp emit(%ECaptureNamed{path: path, arity: arity}, :elixir, ec),
    do: {"&#{p(path, 12, :elixir, ec)}/#{arity}", 12}

  defp emit(%ECaptureNamed{path: path, arity: arity}, :rust, ec) do
    ps = closure_params(0, arity - 1)
    {"|#{ps}| #{p(path, 12, :rust, ec)}(#{ps})", 12}
  end

  defp emit(%EUnary{op: "-", arg: x}, t, ec), do: {"-" <> p(x, 11, t, ec), 11}
  defp emit(%EUnary{op: "not", arg: x}, :elixir, ec), do: {"not " <> p(x, 11, :elixir, ec), 11}
  defp emit(%EUnary{op: "not", arg: x}, :rust, ec), do: {"!" <> p(x, 11, :rust, ec), 11}
  # `&` is injected by the call-site borrow pass (Rust only) — never parsed
  defp emit(%EUnary{op: "&", arg: x}, :rust, ec), do: {"&" <> p(x, 11, :rust, ec), 11}

  # lambdas — Elixir anonymous fn, Rust closure
  defp emit(%ELambda{params: params, body: body}, :elixir, ec) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    names = Enum.map(params, fn {n, _} -> n end)
    ec2 = %{ec | ex_scope: MapSet.union(ec.ex_scope, MapSet.new(names))}
    body_str = p(body, 0, :elixir, ec2)
    {"fn #{ps} -> #{body_str} end", 12}
  end

  defp emit(%ELambda{params: params, body: body}, :rust, ec) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"|#{ps}| #{p(body, 0, :rust, ec)}", 12}
  end

  # if-expression
  defp emit(%EIf{cond: c, then: t, else: e}, :elixir, ec),
    do:
      {"if #{p(c, 0, :elixir, ec)} do #{emit_block(t, :elixir, ec)} else #{emit_block(e, :elixir, ec)} end",
       0}

  defp emit(%EIf{cond: c, then: t, else: e}, :rust, ec),
    do:
      {"if #{p(c, 0, :rust, ec)} { #{emit_block(t, :rust, ec)} } else { #{emit_block(e, :rust, ec)} }",
       0}

  defp emit(%EBlock{} = b, t, ec), do: {emit_block(b, t, ec), 0}

  # case expression — Elixir `case … do … -> … end`; Rust `match … { … => …, }`
  defp emit(%ECase{scrut: scrut, arms: arms}, :elixir, ec) do
    scrut_str = p(scrut, 0, :elixir, ec)

    body =
      Enum.map_join(arms, "; ", fn {pt, g, b} ->
        # the arm pattern's bindings are in scope for its guard and body
        ec2 = %{ec | ex_scope: MapSet.union(ec.ex_scope, MapSet.new(core_pat_vars(pt)))}
        "#{pat_ex(pt)}#{case_guard(g, :elixir, ec2)} -> #{p(b, 0, :elixir, ec2)}"
      end)

    {"case #{scrut_str} do #{body} end", 0}
  end

  defp emit(%ECase{scrut: scrut, arms: arms}, :rust, ec),
    do: {rust_case(scrut, arms, &p(&1, 0, :rust, ec), ec), 0}

  # with expression — Elixir native `with`/`else`; Rust nested `match` chain that
  # short-circuits to the `else` arms (or yields the non-matching value).
  defp emit(%EWith{clauses: clauses, body: body, els: els}, :elixir, ec) do
    cs =
      Enum.map_join(clauses, ", ", fn {pt, e} -> "#{pat_ex(pt)} <- #{p(e, 0, :elixir, ec)}" end)

    else_str =
      if els == [],
        do: "",
        else:
          " else " <>
            Enum.map_join(els, "; ", fn {pt, g, b} ->
              "#{pat_ex(pt)}#{case_guard(g, :elixir, ec)} -> #{p(b, 0, :elixir, ec)}"
            end)

    {"with #{cs} do #{emit_block(body, :elixir, ec)}#{else_str} end", 0}
  end

  defp emit(%EWith{clauses: clauses, body: body, els: els}, :rust, ec) do
    else_rs =
      Enum.map_join(els, " ", fn {pt, g, b} ->
        "#{rpat(pt)}#{case_guard(g, :rust, ec)} => #{p(b, 0, :rust, ec)},"
      end)

    {with_chain_rs(clauses, emit_block(body, :rust, ec), else_rs, ec), 0}
  end

  # list / map literals
  defp emit(%EList{elems: elems, tail: :close}, :elixir, ec),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir, ec))}]", 12}

  defp emit(%EList{elems: elems, tail: tl}, :elixir, ec),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir, ec))} | #{p(tl, 0, :elixir, ec)}]", 12}

  defp emit(%EList{elems: elems, tail: :close}, :rust, ec),
    do: {"vec![#{Enum.map_join(elems, ", ", &rust_owned_elem(&1, ec))}]", 12}

  # cons `[e1, …, en | tail]` -> prepend onto an owned copy of the tail
  # (`.to_vec()` turns the `&[T]` slice — or a `Vec` — into an owned `Vec`), in
  # reverse so the result order is `e1, …, en, tail…` (ADR-0047)
  defp emit(%EList{elems: elems, tail: tl}, :rust, ec) do
    prepends =
      elems
      |> Enum.reverse()
      |> Enum.map_join(" ", fn e -> "__v.insert(0, #{rust_owned_elem(e, ec)});" end)

    {"{ let mut __v = #{p(tl, 12, :rust, ec)}.to_vec(); #{prepends} __v }", 0}
  end

  defp emit(%EMap{pairs: pairs}, :elixir, ec),
    do: {"%{#{Enum.map_join(pairs, ", ", &map_pair_elixir(&1, ec))}}", 12}

  defp emit(%EMap{}, :rust, _ec), do: raise("map literals are BEAM-only in PoC")

  # bitstring (ADR-0078): the `:elixir` text path is a BEAM verification backend
  # (Elixir has native `<<>>`), so it emits real bitstring syntax; Rust has no
  # bit-level lowering yet (Reach pins bitstring functions off `:rs`).
  defp emit(%Core.EBitstr{segments: segs}, :elixir, ec),
    do: {"<<#{Enum.map_join(segs, ", ", &bitseg_elixir(&1, ec))}>>", 12}

  defp emit(%Core.EBitstr{}, :rust, _ec), do: raise("bitstrings are BEAM-only (ADR-0078)")

  defp emit(%EMapUpdate{base: base, pairs: pairs}, :elixir, ec) do
    fields = Enum.map_join(pairs, ", ", &map_pair_elixir(&1, ec))
    {"%{#{p(base, 0, :elixir, ec)} | #{fields}}", 12}
  end

  defp emit(%EMapUpdate{}, :rust, _ec), do: raise("map updates are BEAM-only in PoC")

  # constant reference — a 0-arity accessor call on the BEAM, the `const` name on Rust
  defp emit(%EConstRef{name: name}, :elixir, _ec), do: {"#{PL.to_snake(name)}()", 12}
  defp emit(%EConstRef{name: name}, :rust, _ec), do: {name, 12}

  # tuple literal — a BEAM tuple / a Rust tuple. The `{:ok, v}` / `{:error, e}`
  # shapes are the canonical Result surface (ADR-0040): they keep their tagged
  # tuple on the BEAM but lower to Rust `Ok(…)` / `Err(…)`.
  defp emit(%ETuple{elems: [%EAtom{name: "ok"}, v]}, :rust, ec),
    do: {"Ok(#{result_payload(v, ec.ok_string, ec)})", 12}

  defp emit(%ETuple{elems: [%EAtom{name: "error"}, e]}, :rust, ec),
    do: {"Err(#{result_payload(e, ec.err_string, ec)})", 12}

  defp emit(%ETuple{elems: es}, :rust, ec),
    do: {"(#{Enum.map_join(es, ", ", &p(&1, 0, :rust, ec))})", 12}

  defp emit(%ETuple{elems: es}, :elixir, ec),
    do: {"{#{Enum.map_join(es, ", ", &p(&1, 0, :elixir, ec))}}", 12}

  # sum-variant construction — a snake atom / tagged tuple on the BEAM (labels
  # erased), an `Enum::Variant` path on Rust (named `{…}` or positional `(…)`).
  defp emit(%EVariant{ctor: ctor, pairs: []}, :elixir, _ec),
    do: {":" <> Atom.to_string(PL.to_snake(ctor)), 12}

  defp emit(%EVariant{ctor: ctor, pairs: pairs}, :elixir, ec) do
    vals = Enum.map_join(pairs, ", ", fn {_l, v} -> p(v, 0, :elixir, ec) end)
    {"{:#{PL.to_snake(ctor)}, #{vals}}", 12}
  end

  defp emit(%EVariant{enum: enum, ctor: ctor, pairs: []}, :rust, _ec),
    do: {"#{enum}::#{ctor}", 12}

  defp emit(%EVariant{enum: enum, ctor: ctor, named: true, pairs: pairs}, :rust, ec) do
    fields = Enum.map_join(pairs, ", ", fn {l, v} -> "#{l}: #{rust_owned_elem(v, ec)}" end)
    {"#{enum}::#{ctor} { #{fields} }", 12}
  end

  defp emit(%EVariant{enum: enum, ctor: ctor, named: false, pairs: pairs}, :rust, ec) do
    {"#{enum}::#{ctor}(#{Enum.map_join(pairs, ", ", fn {_l, v} -> rust_owned_elem(v, ec) end)})",
     12}
  end

  # struct literal — `%Name{x: …}` on the BEAM, `Name { x: … }` on Rust
  defp emit(%EStruct{name: name, pairs: pairs}, :elixir, ec),
    do:
      {"%#{name}{#{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :elixir, ec)}" end)}}",
       12}

  defp emit(%EStruct{name: name, pairs: pairs}, :rust, ec),
    do:
      {"#{name} { #{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :rust, ec)}" end)} }",
       12}

  # pipe: native on Elixir, structural call on Rust
  defp emit(%EBin{op: "|>", left: l, right: r}, :elixir, ec),
    do: {p(l, prec("|>"), :elixir, ec) <> " |> " <> p(r, prec("|>") + 1, :elixir, ec), prec("|>")}

  defp emit(%EBin{op: "|>", left: l, right: r}, :rust, ec),
    do: emit(pipe_to_call(l, r), :rust, ec)

  # concat: native <> on Elixir, flattened format! on Rust
  defp emit(%EBin{op: "<>", left: l, right: r}, :elixir, ec),
    do: {p(l, prec("<>") + 1, :elixir, ec) <> " <> " <> p(r, prec("<>"), :elixir, ec), prec("<>")}

  defp emit(%EBin{op: "<>"} = node, :rust, ec) do
    parts = flatten_concat(node)
    fmt = String.duplicate("{}", length(parts))
    {"format!(\"#{fmt}\", #{Enum.map_join(parts, ", ", &p(&1, 0, :rust, ec))})", 12}
  end

  # integer div / rem
  defp emit(%EBin{op: "div", left: l, right: r}, :elixir, ec),
    do: {"div(#{p(l, 0, :elixir, ec)}, #{p(r, 0, :elixir, ec)})", 12}

  defp emit(%EBin{op: "rem", left: l, right: r}, :elixir, ec),
    do: {"rem(#{p(l, 0, :elixir, ec)}, #{p(r, 0, :elixir, ec)})", 12}

  defp emit(%EBin{op: "div", left: l, right: r}, :rust, ec),
    do: {p(l, prec("div"), :rust, ec) <> " / " <> p(r, prec("div") + 1, :rust, ec), prec("div")}

  defp emit(%EBin{op: "rem", left: l, right: r}, :rust, ec),
    do: {p(l, prec("rem"), :rust, ec) <> " % " <> p(r, prec("rem") + 1, :rust, ec), prec("rem")}

  # float division: native on Elixir, explicit f64 cast on Rust
  defp emit(%EBin{op: "/", left: l, right: r}, :elixir, ec),
    do: {p(l, prec("/"), :elixir, ec) <> " / " <> p(r, prec("/") + 1, :elixir, ec), prec("/")}

  defp emit(%EBin{op: "/", left: l, right: r}, :rust, ec),
    do: {"(#{p(l, 0, :rust, ec)} as f64) / (#{p(r, 0, :rust, ec)} as f64)", 10}

  # generic binary (arith, comparison, and/or) — MUST be last
  defp emit(%EBin{op: op, left: l, right: r}, t, ec) do
    pr = prec(op)

    {lc, rc} =
      case assoc(op) do
        :left -> {pr, pr + 1}
        :right -> {pr + 1, pr}
        :none -> {pr + 1, pr + 1}
      end

    {p(l, lc, t, ec) <> " " <> disp(op, t) <> " " <> p(r, rc, t, ec), pr}
  end

  # one Elixir-text map pair: atom-key shorthand `k: v`, or a computed key
  # `keyExpr => v` (ADR-0033 non-atom keys).
  defp map_pair_elixir({{:key, k}, v}, ec),
    do: "#{p(k, 0, :elixir, ec)} => #{p(v, 0, :elixir, ec)}"

  defp map_pair_elixir({k, v}, ec), do: "#{k}: #{p(v, 0, :elixir, ec)}"

  # one bitstring segment as Elixir text (ADR-0078): `value` or `value::spec-spec`.
  defp bitseg_elixir({value, specs}, ec) do
    v = p(value, 0, :elixir, ec)
    if specs == [], do: v, else: "#{v}::#{Enum.map_join(specs, "-", &bitspec_elixir/1)}"
  end

  defp bitspec_elixir({:type, name}), do: name
  defp bitspec_elixir({:size, n}), do: Integer.to_string(n)
  defp bitspec_elixir({:unit, n}), do: "unit(#{n})"

  # an element stored into an owned `Vec<T>` must be owned `T`; a borrowed `&T`
  # element (a var bound to a `&`-param, in a generic function — `ec.borrowed`)
  # is `.clone()`d. Literals and cloned binders are already owned (no clone).
  defp rust_owned_elem(%EId{name: n} = e, ec) do
    s = p(e, 0, :rust, ec)

    cond do
      # a `&[T]` slice → `Vec<T>` (a `.clone()` would clone the reference, Gap D)
      slice_var?(e, ec) -> "#{s}.to_vec()"
      MapSet.member?(ec.borrowed, n) -> "#{s}.clone()"
      true -> s
    end
  end

  defp rust_owned_elem(e, ec), do: p(e, 0, :rust, ec)

  defp emit_block(%EBlock{stmts: []}, :elixir, _ec), do: "nil"
  defp emit_block(%EBlock{stmts: []}, :rust, _ec), do: "()"

  defp emit_block(%EBlock{stmts: stmts}, :elixir, ec) do
    # each `:=` binding's name enters scope for the statements that follow it, so
    # a later application of a function-valued binding is `g.(x)` (matches Beam).
    {parts, _} =
      Enum.map_reduce(stmts, ec.ex_scope, fn stmt, sc ->
        sec = %{ec | ex_scope: sc}

        case stmt do
          {:bind, n, e} -> {"#{n} = #{p(e, 0, :elixir, sec)}", MapSet.put(sc, n)}
          {:typed_bind, n, _t, e} -> {"#{n} = #{p(e, 0, :elixir, sec)}", MapSet.put(sc, n)}
          {:expr, e} -> {p(e, 0, :elixir, sec), sc}
        end
      end)

    Enum.join(parts, "; ")
  end

  defp emit_block(%EBlock{stmts: stmts}, :rust, ec) do
    # A `:=` binding to a borrowed `&T` param (`y := x`, generic `x: &T`) makes the
    # binder a reference too, so a later owned construction over it (`Some(y)`,
    # `Ok(y)`) would store `&T` where `T` is expected (rustc E0308). Clone such a
    # rebind to an owned `T` here — `rust_owned_elem` clones a borrowed-var RHS and
    # passes everything else through — so the binder is owned and downstream
    # construction needs no further coercion (mirrors destructured-binder cloning).
    Enum.map_join(stmts, " ", fn
      {:bind, n, e} -> "let #{n} = #{rust_owned_elem(e, ec)};"
      {:typed_bind, n, _t, e} -> "let #{n} = #{rust_owned_elem(e, ec)};"
      {:expr, e} -> p(e, 0, :rust, ec)
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
