defmodule Rian.Lower do
  @moduledoc """
  End-to-end **text** backend lowering for a single Rian function. Wires together:
    * type env             (Rian.Exhaustiveness)
    * pattern lowering     (Rian.PatternLower)
    * exhaustiveness       (Rian.Exhaustiveness.analyze)  -- gates dead/unreachable clauses
      and non-exhaustive `case` bodies; a non-exhaustive **function** lowers with a
      runtime fallthrough (Rust `_ => panic!(…)`, Elixir `FunctionClauseError`), matching
      `Rian.Beam`/`Rian.JS`/`Rian.JVM` (ADR-0036) rather than being refused
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
  use Rian.Ann

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
  @rian_sig "pub def compile(types Vec(Type), func Func) _Unk"
  @rian_sig "pub def compile(types Vec(Type), func Func, structs Vec(Struct)) _Unk"
  @rian_sig "pub def compile(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range)) _Unk"
  @rian_sig "pub def compile(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range), proto _Unk) _Unk"
  @rian_sig "pub def compile(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range), proto _Unk, ic Ic) _Unk"
  @spec compile(list(), map(), list(), list(), map(), map()) :: map()
  def compile(types, func, structs \\ [], ranges \\ [], proto \\ %{}, ic \\ %{}) do
    env = build_env(types, structs, ranges)
    func = check!(func, env)
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
  @rian_sig "pub def compile_elixir(types Vec(Type), func Func) _Unk"
  @rian_sig "pub def compile_elixir(types Vec(Type), func Func, structs Vec(Struct)) _Unk"
  @rian_sig "pub def compile_elixir(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range)) _Unk"
  @rian_sig "pub def compile_elixir(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range), ic Ic) _Unk"
  @spec compile_elixir(list(), map(), list(), list(), map()) :: map()
  def compile_elixir(types, func, structs \\ [], ranges \\ [], ic \\ %{}) do
    env = build_env(types, structs, ranges)
    func = check!(func, env)
    %{elixir: to_elixir(func, types, structs, build_struct_meta(structs), ic)}
  end

  @doc """
  Compile to the BEAM target only (for functions using BEAM-only constructs).
  The BEAM text view is exactly the Elixir one, so this delegates to
  `compile_elixir/4` — a distinct entry point kept for call-site intent.
  """
  @rian_sig "pub def compile_beam(types Vec(Type), func Func) _Unk"
  @rian_sig "pub def compile_beam(types Vec(Type), func Func, structs Vec(Struct)) _Unk"
  @rian_sig "pub def compile_beam(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range)) _Unk"
  @rian_sig "pub def compile_beam(types Vec(Type), func Func, structs Vec(Struct), ranges Vec(Range), ic Ic) _Unk"
  @spec compile_beam(list(), map(), list(), list(), map()) :: map()
  def compile_beam(types, func, structs \\ [], ranges \\ [], ic \\ %{}),
    do: compile_elixir(types, func, structs, ranges, ic)

  @doc """
  Compile a whole `%Rian.IR.Mod{}` to both targets: a `defmodule` (BEAM) and a
  `mod` (Rust), with its types/structs emitted once and each function wrapped at
  its declared visibility (`pub?` -> `def`/`pub fn`, else `defp`/private `fn`).
  """
  @rian_sig "pub def compile_module(m Mod, ic Ic) _Unk"
  @spec compile_module(struct(), map()) :: map()
  def compile_module(%Rian.IR.Mod{} = m, ic \\ %{}) do
    %{elixir: module_elixir(m, ic), rust: module_rust(m, ic)}
  end

  @doc "Compile a module to the BEAM target only."
  @rian_sig "pub def compile_module_beam(m Mod, ic Ic) _Unk"
  @spec compile_module_beam(struct(), map()) :: map()
  def compile_module_beam(%Rian.IR.Mod{} = m, ic \\ %{}), do: %{elixir: module_elixir(m, ic)}

  defp module_elixir(%{name: name, types: types, structs: structs, funcs: funcs} = m, ic) do
    env = build_env(types, structs, Map.get(m, :ranges, []))
    # Elixir clauses are total-by-`FunctionClauseError`, so the partiality stamp is
    # unused here; check! still runs for its hard gates (dead clauses, `case` bodies).
    Enum.each(funcs, &check!(&1, env))
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
    # stamp each func's `partial` flag so `rust_fn` appends a panic fallthrough for a
    # non-total match (Rust's `match` must be total); use the stamped funcs downstream.
    funcs = Enum.map(funcs, &check!(&1, env))
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

    # a synthesized union `enum` (ADR-0083) is emitted at the crate root, so a `mod`
    # whose body references one must `use super::*` to bring it into scope (a Rust
    # module does not inherit its parent's items). Without this, a union-typed function
    # inside a `mod` references an out-of-scope `RUnion_…` (rustc E0425).
    use_super = if String.contains?(body, "RUnion_"), do: "use super::*;\n\n", else: ""
    "mod #{PL.to_snake(name)} {\n#{use_super}#{body}\n}"
  end

  @spec const_set(list()) :: MapSet.t()
  defp const_set(consts), do: MapSet.new(consts, & &1.name)

  # type/struct names mentioned in any `pub` function's param or return types
  # (the PascalCase identifiers in those type strings)
  defp pub_sig_type_names(funcs) do
    MapSet.new(
      for f <- funcs,
          f.pub?,
          ts <- [f.ret | Enum.map(f.params, & &1.type)],
          name <- type_idents(ts),
          do: name
    )
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

  # Exhaustiveness check — returns the func, **stamping `partial: true`** when the clause
  # heads are not total (rather than refusing to emit). A partial function lowers
  # everywhere: Elixir/BEAM clauses are total-by-`FunctionClauseError`, and the Rust
  # emitter appends a `_ => panic!(…)` fallthrough (`rust_fn`) — the same runtime no-match
  # behaviour as the other backends (ADR-0036, the JS/JVM `throw`). A non-exhaustive
  # **`case`** inside a body is treated the same way (ADR-0036, 2026-06-20): BEAM/JS/JVM
  # already throw on a non-matching `case`, and `resolve_rust_pats` appends a `_ =>
  # panic!()` arm — so the `:exh_env` is stamped here for that pass. Still a HARD error:
  # dead (`unreachable`) clauses. A synthetic protocol dispatcher is exempt (ADR-0042 §3/§6).
  defp check!(%{synthetic: true} = func, _env), do: func

  defp check!(func, env) do
    arity = length(hd(func.clauses).pats)

    clauses =
      Enum.map(func.clauses, fn c ->
        PL.lower_clause(%{pats: c.pats, guard: Map.get(c, :guard) != nil}, env)
      end)

    r = E.analyze(clauses, arity, env)

    if r.unreachable != [] do
      raise "unreachable clauses in `#{func.name}`: #{inspect(r.unreachable)}"
    end

    # `Map.put` (not `%{… | …}`) so a hand-built map func (tests) without the field works.
    # `:exh_env` rides along for `resolve_rust_pats` to close a non-exhaustive body `case`.
    func |> Map.put(:partial, not r.exhaustive?) |> Map.put(:exh_env, env)
  end

  # ── Elixir backend ─────────────────────────────────────────────────────
  @rian_sig "pub def to_elixir(func Func, types Vec(Type)) _Unk"
  @rian_sig "pub def to_elixir(func Func, types Vec(Type), structs Vec(Struct)) _Unk"
  @rian_sig "pub def to_elixir(func Func, types Vec(Type), structs Vec(Struct), smeta _Unk) _Unk"
  @rian_sig "pub def to_elixir(func Func, types Vec(Type), structs Vec(Struct), smeta _Unk, ic Ic) _Unk"
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
        borrowed_vec_fields: MapSet.new(),
        ok_string: false,
        err_string: false,
        # set inside a function whose return type contains a `Fn(...)` (top-level or
        # nested, e.g. `Option(Fn(…, T))`): a value-position closure then lowers to a
        # boxed `Box::new(move …)`, cloning its captured tvar body per call when `clone?`.
        fn_box: nil,
        # user types carrying an `Fn(...)` field, name → that field's `Fn` type. Constructing
        # one boxes the closure into the field via `Rc::new` (see the `ELambda` emit).
        fn_field_types: %{},
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
  defp list_rpat?({:rpat, s, _}), do: String.starts_with?(String.trim_leading(s), "[")
  defp list_rpat?(_), do: false

  # Emit a Rust `match`, with `body_fn` rendering each arm's body (the default emits
  # it plainly; the `String`-return path coerces it). A `case` whose arms are list
  # patterns must match a slice: `&(scrut)[..]` coerces both an owned `Vec<T>` and an
  # already-borrowed `&[T]` to `&[T]` uniformly (binders stay `&T`/`&[T]`).
  defp rust_case(scrut, arms, body_fn, ec) do
    sliced? = Enum.any?(arms, fn {pt, _, _} -> list_rpat?(pt) end)
    # the scrutinee is borrowed (so arm binders are references into it, needing a `.clone()`
    # in an owned position) when it is matched as a slice (`&(scrut)[..]`, every cons case) OR
    # when it is a borrowed local (a `&`-param/binder in `ec.borrowed`, e.g. a generic tuple
    # param). The arm binders are then added to `ec.borrowed` so `rust_owned_elem` clones them.
    scrut_b? = sliced? or scrut_borrowed?(scrut, ec)

    body =
      Enum.map_join(arms, " ", fn {pt, g, b} ->
        arm_ec =
          if scrut_b?,
            do: %{ec | borrowed: MapSet.union(ec.borrowed, MapSet.new(rpat_binders(pt)))},
            else: ec

        "#{rpat(pt)}#{case_guard(g, :rust, arm_ec)} => #{body_fn.(b, arm_ec)},"
      end)

    scrut_rs = if sliced?, do: "&(#{p(scrut, 0, :rust, ec)})[..]", else: p(scrut, 0, :rust, ec)
    "match #{scrut_rs} { #{body} }"
  end

  # is a `case` scrutinee a borrowed value? A bare var that is a `&`-typed local (in
  # `ec.borrowed` — a `val` non-`Copy`/`Vec`/`String` param of a generic function, or a
  # cons-tail binder). Conservative: anything else is treated as owned (no spurious clone).
  defp scrut_borrowed?(%EId{name: n}, ec), do: MapSet.member?(ec.borrowed, n)
  defp scrut_borrowed?(_scrut, _ec), do: false

  # Gap B (ADR-0061): a `String`-returning body that is an `if`/`case` cannot mix a
  # `&str`-literal arm with a `String` arm — Rust requires both to agree. Push the
  # `&str -> String` coercion into the TAIL positions (each branch/arm leaf) so they
  # unify, rather than wrapping the whole `if`/`match` (which can't type-check).
  defp coerce_string_ast(%EIf{cond: c, then: t, else: e}, ec),
    do:
      "if #{p(c, 0, :rust, ec)} { #{coerce_string_branch(t, ec)} } else { #{coerce_string_branch(e, ec)} }"

  defp coerce_string_ast(%ECase{scrut: scrut, arms: arms}, ec),
    do: rust_case(scrut, arms, fn b, aec -> coerce_string_branch(b, aec) end, ec)

  defp coerce_string_ast(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_string_ast(e, ec)

  defp coerce_string_ast(%EBlock{} = b, ec),
    do: "({ #{emit_block(b, :rust, ec)} }).to_string()"

  defp coerce_string_ast(ast, ec), do: "(#{p(ast, 0, :rust, ec)}).to_string()"

  defp coerce_string_branch(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_string_ast(e, ec)

  defp coerce_string_branch(%EBlock{} = b, ec),
    do: "({ #{emit_block(b, :rust, ec)} }).to_string()"

  defp coerce_string_branch(e, ec), do: coerce_string_ast(e, ec)

  # a bare-tvar return whose body is an `if`/`case`: `.clone()` each TAIL leaf to the owned
  # `T` (mirrors `coerce_string_ast`), so a borrowed leaf (a returned `&T` param/binder)
  # unifies with an owned one (`T: Clone`). A no-op clone when a leaf already owns its `T`.
  defp coerce_owned_tvar_ast(%EIf{cond: c, then: t, else: e}, ec),
    do:
      "if #{p(c, 0, :rust, ec)} { #{coerce_owned_tvar_ast(t, ec)} } else { #{coerce_owned_tvar_ast(e, ec)} }"

  defp coerce_owned_tvar_ast(%ECase{scrut: scrut, arms: arms}, ec),
    do: rust_case(scrut, arms, fn b, aec -> coerce_owned_tvar_ast(b, aec) end, ec)

  defp coerce_owned_tvar_ast(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_owned_tvar_ast(e, ec)

  defp coerce_owned_tvar_ast(%EBlock{} = b, ec),
    do: "({ #{emit_block(b, :rust, ec)} }).clone()"

  defp coerce_owned_tvar_ast(ast, ec), do: "(#{p(ast, 0, :rust, ec)}).clone()"

  # A value-union RETURN (ADR-0083): the body produces a MEMBER value but the
  # signature is the synthesized enum, so wrap each TAIL leaf with `Enum::from(leaf)`,
  # pushed into `if`/`case` branches so they unify (mirrors `coerce_string_ast`). A
  # leaf already of union type (a union param, a union-returning call) passes through.
  defp coerce_union_ret_ast(%EIf{cond: c, then: t, else: e}, enum, ec),
    do:
      "if #{p(c, 0, :rust, ec)} { #{coerce_union_ret_ast(t, enum, ec)} } else { #{coerce_union_ret_ast(e, enum, ec)} }"

  defp coerce_union_ret_ast(%ECase{scrut: scrut, arms: arms}, enum, ec),
    do: rust_case(scrut, arms, fn b, aec -> coerce_union_ret_ast(b, enum, aec) end, ec)

  defp coerce_union_ret_ast(%EBlock{stmts: [{:expr, e}]}, enum, ec),
    do: coerce_union_ret_ast(e, enum, ec)

  defp coerce_union_ret_ast(%EBlock{} = b, enum, ec),
    do: union_wrap("{ #{emit_block(b, :rust, ec)} }", b, enum)

  defp coerce_union_ret_ast(ast, enum, ec), do: union_wrap(p(ast, 0, :rust, ec), ast, enum)

  # wrap a member leaf in `Enum::from`; a leaf already of union type is left as-is.
  defp union_wrap(str, ast, enum),
    do: if(union_typed?(ast), do: str, else: "#{enum}::from(#{str})")

  defp union_typed?(%{type: t}) when is_binary(t), do: String.starts_with?(t, "Union(")
  defp union_typed?(_), do: false

  # Gap E+ (ADR-0061): a `Vec`-returning body that tail-returns a BORROWED collection —
  # a `&[T]` slice binder or a `&Vec<T>` field binder destructured from a borrowed value
  # — needs `.to_vec()` to materialise the owned `Vec<T>` the signature promises. Like
  # Gap B for `String`, push the coercion into `if`/`case` TAIL leaves rather than
  # wrapping the whole expression. SELECTIVE: only a borrowed-collection leaf is cloned;
  # an owned leaf (`vec![…]`, a cons rebuild, an owned-returning call) is already
  # `Vec<T>` and is emitted untouched, so an owned-Vec return cannot regress.
  defp coerce_owned_vec_ast(%EIf{cond: c, then: t, else: e}, ec),
    do:
      "if #{p(c, 0, :rust, ec)} { #{coerce_owned_vec_ast(t, ec)} } else { #{coerce_owned_vec_ast(e, ec)} }"

  defp coerce_owned_vec_ast(%ECase{scrut: scrut, arms: arms}, ec),
    do: rust_case(scrut, arms, fn b, aec -> coerce_owned_vec_ast(b, aec) end, ec)

  defp coerce_owned_vec_ast(%EBlock{stmts: [{:expr, e}]}, ec), do: coerce_owned_vec_ast(e, ec)

  defp coerce_owned_vec_ast(%EId{name: n} = e, ec) do
    s = p(e, 0, :rust, ec)
    if borrowed_collection?(n, ec), do: "#{s}.to_vec()", else: s
  end

  defp coerce_owned_vec_ast(ast, ec), do: p(ast, 0, :rust, ec)

  # a clause var that is a `&[T]`/`&Vec<T>` at runtime: a slice binder (slice param or
  # cons-tail) or a `Vec` field binder destructured from a borrowed scrutinee.
  defp borrowed_collection?(n, ec),
    do: MapSet.member?(ec.slices, n) or MapSet.member?(ec.borrowed_vec_fields, n)

  # Resolve every `case` arm pattern in a body to its Rust spelling using the
  # type meta, storing it back into the IR as `{:rpat, str}`. After this pass the
  # Rust emitter needs no ambient meta — the IR carries the resolution.
  defp resolve_rust_pats(node, meta, us \\ %{scope: %{}, funcs: %{}})

  # a `case` over a value-union SCRUTINEE (ADR-0083): a union-typed local (a param or
  # a `x := <union>` binding) OR a union-returning call. Each type-pattern arm resolves
  # to the synthesized enum's variant pattern `Enum::Variant(binder)`; a non-union
  # scrutinee resolves its arms normally.
  defp resolve_rust_pats({:case, scrut, arms}, meta, us) do
    # A resolved case-arm pattern carries its binders (3rd elem) so `rust_case` can clone
    # them when the scrutinee is borrowed (`case p do (a, b) -> (b, a)` over a `&`-tuple, or
    # the slice cons `[h | _] -> Some(h)`): the binders are references into the scrutinee, so
    # an owned-position use needs `.clone()`. A union arm binds an owned enum value (no clone).
    resolved =
      case union_enum_of(scrut, us) do
        nil -> fn pt -> {:rpat, core_pat_rs(pt, meta), core_pat_vars(Core.from_pat(pt))} end
        enum -> fn pt -> {:rpat, union_pat_rs(pt, enum, meta), []} end
      end

    resolved_arms =
      Enum.map(arms, fn {pt, g, b} ->
        {resolved.(pt), resolve_guard(g, meta, us), resolve_rust_pats(b, meta, us)}
      end)

    {:case, resolve_rust_pats(scrut, meta, us), close_rust_case(arms, resolved_arms, us)}
  end

  defp resolve_rust_pats({:with, clauses, body, els}, meta, us) do
    {:with,
     Enum.map(clauses, fn {pt, e} ->
       {{:rpat, core_pat_rs(pt, meta)}, resolve_rust_pats(e, meta, us)}
     end), resolve_rust_pats(body, meta, us),
     Enum.map(els, fn {pt, g, b} ->
       {{:rpat, core_pat_rs(pt, meta)}, resolve_guard(g, meta, us),
        resolve_rust_pats(b, meta, us)}
     end)}
  end

  defp resolve_rust_pats(node, meta, us),
    do: Rian.Macro.map_node(node, &resolve_rust_pats(&1, meta, us))

  defp resolve_guard(nil, _meta, _us), do: nil
  defp resolve_guard(g, meta, us), do: resolve_rust_pats(g, meta, us)

  # Rust's `match` must be total (ADR-0036): a non-exhaustive body `case` gets a
  # `_ => panic!(…)` arm — BEAM/JS/JVM already throw on a non-matching `case`, so this
  # makes Rust the same runtime no-match instead of a refused compile. Needs the
  # exhaustiveness env (threaded via `us.env`, stamped on the func by `Rian.Lower.check!`);
  # an env-less path (`const`/`proto`) leaves the arms as-is, and a total case (a
  # catch-all, or a closed-variant cover) gets no arm (no `unreachable` rustc warning).
  defp close_rust_case(orig_arms, resolved_arms, us) do
    env = Map.get(us, :env, %{})

    cond do
      env == %{} -> resolved_arms
      Enum.any?(orig_arms, &catchall_arm?/1) -> resolved_arms
      rust_case_total?(orig_arms, env) -> resolved_arms
      true -> resolved_arms ++ [{{:rpat, "_"}, nil, case_panic_call()}]
    end
  end

  defp catchall_arm?({pt, g, _}), do: g == nil and catchall_pat?(Core.from_pat(pt))

  defp rust_case_total?(arms, env) do
    rows =
      Enum.map(arms, fn {pt, g, _} -> PL.lower_clause(%{pats: [pt], guard: g != nil}, env) end)

    E.analyze(rows, 1, env).exhaustive?
  end

  defp case_panic_call,
    do: {:call, {:id, "__prim_panic"}, [{:str, "case: no clause matched"}]}

  # a value-union arm pattern: a type-pattern `n Type` -> `Enum::Variant(n)`; any
  # other arm (a catch-all `_`/var) falls back to the ordinary resolution.
  defp union_pat_rs({:typed, name, tname}, enum, _meta),
    do: "#{enum}::#{variant_name(tname)}(#{name})"

  defp union_pat_rs(pt, _enum, meta), do: core_pat_rs(pt, meta)

  # the synthesized enum a union `case` scrutinee narrows over, or nil: a union-typed
  # local id (`us.scope`), or a call to a union-returning function (`us.funcs`).
  defp union_enum_of({:id, name}, us), do: us.scope |> Map.get(name) |> maybe_enum()
  defp union_enum_of({:call, {:id, f}, _args}, us), do: us.funcs |> Map.get(f) |> maybe_enum()
  defp union_enum_of(_scrut, _us), do: nil

  defp maybe_enum(nil), do: nil
  defp maybe_enum(t), do: union_enum_name(t)

  # the union-typed locals in a clause body: union params + a binding `x := e` whose
  # `e` is a union-returning call or a reference to a union local (forward scan of the
  # top-level block — the common case; a binding nested in a branch is not tracked).
  defp union_locals(pre, params, union_funcs) do
    base = for(p <- params, union_type?(p.type), into: %{}, do: {p.name, p.type})

    case pre do
      {:block, stmts} -> Enum.reduce(stmts, base, &add_union_bind(&1, union_funcs, &2))
      _ -> base
    end
  end

  defp add_union_bind({tag, name, expr}, uf, acc) when tag in [:bind, :typed_bind],
    do: add_union_bind({tag, name, nil, expr}, uf, acc)

  defp add_union_bind({_tag, name, _t, {:call, {:id, f}, _}}, uf, acc) do
    case Map.get(uf, f) do
      nil -> acc
      t -> Map.put(acc, name, t)
    end
  end

  defp add_union_bind({_tag, name, _t, {:id, y}}, _uf, acc) do
    case Map.get(acc, y) do
      nil -> acc
      t -> Map.put(acc, name, t)
    end
  end

  defp add_union_bind(_stmt, _uf, acc), do: acc

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
      # a value-union param (ADR-0083 Phase 4): wrap the member arg into the
      # synthesized enum via its `From` impl — `Enum::from(arg)` (the variant is
      # selected by the arg's Rust type). A union-typed arg (already the enum) is
      # passed through, not re-wrapped.
      String.starts_with?(pt, "RUnion_") ->
        union_from_arg(a, pt, ec)

      not borrow_type?(pt) ->
        a

      # a `&impl Fn(...)` callback param (ADR-0061): a closure/expression argument is referenced
      # (`&|x| …`), but a bare variable is already a `&impl Fn` — a caller's own param or the
      # recursive `map(t, f)` — so it is left alone (referencing it again would be `&&`).
      fn_borrow?(pt) ->
        if match?({:id, _}, a), do: a, else: {:unary, "&", a}

      # a string literal fed to a *generic* `&K` param (`K` resolves to owned `String`,
      # which has the `Clone`/`impl`s a tvar needs — `str` does not): `&"a".to_string()`.
      generic_tvar_borrow?(pt) and match?({:str, _}, a) ->
        owned_str_arg(elem(a, 1))

      # a `Symbol` literal (`:foo`) fed to the same generic `&K`: a Symbol lowers to an
      # owned `String` too, so it needs the identical owned-borrow, not a bare `&str`.
      generic_tvar_borrow?(pt) and match?({:atom, _}, a) ->
        owned_str_arg(elem(a, 1))

      # a `String`/`Symbol`-typed VAR (a `&str` param) fed to a generic `&K` that resolves to
      # owned `String` (`inc`'s `k` → `get_or`'s `&K`): `&str`/`&String` differ, so own it with
      # `&(k <> "")` (the `<>` forces `String`), matching the literal case above.
      generic_tvar_borrow?(pt) and str_typed_var?(a, ec) ->
        {:unary, "&", {:bin, "<>", a, {:str, ""}}}

      # a call result fed to a generic `&K`/`&V` is an owned value (Copy or not — e.g.
      # `get_or(m, k, zero())` where `zero() Int53`), so the borrow param needs `&(…)`.
      generic_tvar_borrow?(pt) and match?({:call, _, _}, a) ->
        {:unary, "&", a}

      owned_field_var?(a, ec) ->
        {:unary, "&", a}

      borrowed != nil ->
        borrow_value(a, borrowed)

      owned_arg?(a, funs) ->
        {:unary, "&", a}

      scalar_literal?(a) ->
        {:unary, "&", a}

      # an arithmetic result is an owned scalar (even with a non-literal operand, e.g.
      # `get_or(m, k, 0) + 1`), so a borrow param needs `&(…)`.
      arith_result?(a) ->
        {:unary, "&", a}

      true ->
        a
    end
  end

  defp arith_result?({:bin, op, _, _}), do: op in ~w(+ - * / div rem)
  defp arith_result?(_), do: false

  # an owned `String`, borrowed for the `&K` param: `&format!("{}{}", "a", "")` via the
  # `<>` concat (which lowers to `format!` → owned `String`). Cleaner builders
  # (`String::from`/`.to_string()`) need ident/method emit the `::`-path lowering and
  # identifier snake-casing get wrong, so the empty-concat is the portable route.
  defp owned_str_arg(s), do: {:unary, "&", {:bin, "<>", {:str, s}, {:str, ""}}}

  # wrap a member arg into a synthesized union enum (`Enum::from(arg)`), UNLESS the
  # arg is already a union value (a union-param id), which passes through unchanged.
  defp union_from_arg({:id, name} = a, pt, ec) do
    if Map.has_key?(Map.get(ec, :union_scope, %{}), name),
      do: a,
      else: {:call, {:id, "#{pt}::from"}, [a]}
  end

  defp union_from_arg(a, pt, _ec), do: {:call, {:id, "#{pt}::from"}, [a]}

  # a borrowed bare type variable (`&K`, not `&str`/`&[T]`): the param is generic.
  defp generic_tvar_borrow?("&" <> rest), do: tvar_name?(rest)
  defp generic_tvar_borrow?(_), do: false

  # a surface var whose inferred type is `String`/`Symbol` (so it lowered to `&str`).
  defp str_typed_var?({:id, n}, ec), do: Map.get(ec.tenv, n) in ["String", "Symbol"]
  defp str_typed_var?(_, _ec), do: false

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

  # Gap E+ (ADR-0061): the complement of `owned_field_binders` — variables bound to a
  # `Vec` field of a sum destructured in the BODY from a *borrowed* scrutinee (a plain
  # `val` param, the common `def to_list(b) := case b do Bag(xs) -> xs end`). Such a
  # binder is a `&Vec<T>`, so RETURNING it where the owned `Vec<T>` the signature
  # promises is wanted needs `.to_vec()` (`coerce_owned_vec_ast`). Only `Vec` fields are
  # collected: a `String` field is handled by the `coerce_string_ast` path, and a scalar
  # field is `Copy`. Mirrors `owned_field_binders`' walk, gated on a borrowed scrutinee.
  defp borrowed_vec_field_binders(ast, ctx), do: bvfb(ast, ctx, MapSet.new())

  defp bvfb({:case, scrut, arms}, ctx, acc) do
    acc = bvfb(scrut, ctx, acc)
    borrowed? = not owned_scrut?(scrut, ctx)

    Enum.reduce(arms, acc, fn {pat, _g, body}, a ->
      a = if borrowed?, do: collect_vec_field_vars(pat, ctx, a), else: a
      bvfb(body, ctx, a)
    end)
  end

  defp bvfb(t, ctx, acc) when is_tuple(t),
    do: Enum.reduce(Tuple.to_list(t), acc, &bvfb(&1, ctx, &2))

  defp bvfb(l, ctx, acc) when is_list(l), do: Enum.reduce(l, acc, &bvfb(&1, ctx, &2))
  defp bvfb(_, _ctx, acc), do: acc

  defp collect_vec_field_vars({:ctor, ctor, argpats}, ctx, acc) do
    case Map.get(ctx.meta, PL.to_snake(ctor)) do
      %{field_types: fts} ->
        argpats
        |> Enum.zip(fts)
        |> Enum.reduce(acc, fn
          {{:var, n}, "Vec(" <> _}, a -> MapSet.put(a, n)
          {_, _}, a -> a
        end)

      _ ->
        acc
    end
  end

  defp collect_vec_field_vars(_pat, _ctx, acc), do: acc

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
        ref? = borrow_type?(cap_param(p))
        borrowed_in_pat(Core.from_pat(pat), ref?)
      end)

    MapSet.new(direct)
  end

  # a plain var bound to a `&`-param is a reference; a cons-tail binder is `&[T]`;
  # destructured element/field binders are cloned to owned, so excluded.
  defp borrowed_in_pat(%PVar{name: n}, true), do: [n]
  defp borrowed_in_pat(%PList{tail: %PVar{name: n}}, _ref?), do: [n]
  # a tuple pattern over a `&`-tuple binds each element by-reference (match ergonomics),
  # so the element binders are borrowed too — `(a, b)` over `&(T, U)` makes `a: &T`, `b: &U`.
  defp borrowed_in_pat(%Core.PTuple{elems: es}, ref?),
    do: Enum.flat_map(es, &borrowed_in_pat(&1, ref?))

  defp borrowed_in_pat(_pat, _ref?), do: []

  # the clause vars that are a `&[T]` SLICE (a `Vec`-typed `val` param, or a cons-tail
  # `@..` binder) — distinct from a single `&T` borrow. A slice stored into an owned
  # `Vec<T>` (a field, a `Vec` return) needs `.to_vec()`, not `.clone()` (which would
  # clone the reference, staying `&[T]`). Gaps D/E (ADR-0061).
  defp slice_binders(params, pats) do
    param_slices =
      params
      |> Enum.filter(&String.starts_with?(cap_param(&1), "&["))
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
      %{params: ps} -> Enum.map(ps, fn p -> cap_param(p) end)
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

  # does this argument expression produce an owned `Vec`/`String`/user value?
  defp owned_arg?({:list_lit, _, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_from_chars"}, _}, _funs), do: true
  defp owned_arg?({:call, {:id, "__prim_str_concat"}, _}, _funs), do: true
  # a resolved construction (`Bag(xs)` -> `{:variant_lit, …}`, `Point(1, 2)` ->
  # `{:struct_lit, …}`) builds a fresh OWNED value, so feeding it to a `&T`/`&C` param
  # needs `&` — e.g. a non-generic caller of a generic function, `fcount(Bag([1,2,3]))`.
  defp owned_arg?({:variant_lit, _enum, _ctor, _named, _pairs}, _funs), do: true
  defp owned_arg?({:struct_lit, _name, _pairs}, _funs), do: true

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
  defp rpat({:rpat, s, _binders}), do: s
  defp rpat(pat), do: pat_rs(pat, %{})

  # the binders a resolved case-arm pattern introduces (empty for a 2-tuple baked pat or a
  # Core pattern reaching `rust_case` directly) — used to clone them under a borrowed scrutinee.
  defp rpat_binders({:rpat, _s, binders}), do: binders
  defp rpat_binders(_), do: []

  # Rust `with` lowering: a right-nested `match` chain. Each clause matches its
  # ok-pattern and continues, or falls through to the `else` arms (or yields the
  # non-matching value `__w` when there is no `else`) — the `?`-expansion.
  defp with_chain_rs([], body, _else_rs, _ec), do: "{ #{body} }"

  defp with_chain_rs([{pt, e} | rest], body, else_rs, ec) do
    fallback = if else_rs == "", do: "__w => __w,", else: "__w => match __w { #{else_rs} },"

    "match #{p(e, 0, :rust, ec)} { #{rpat(pt)} => #{with_chain_rs(rest, body, else_rs, ec)} #{fallback} }"
  end

  # ── `&` capture support ────────────────────────────────────────────────
  # The closure arity the Rust target must spell out is `Core.cap_arity/1` — the
  # body's highest `&N` placeholder (`&(&1 + &2)` ⇒ 2 ⇒ `|a1, a2| …`), shared
  # across every backend.

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
  @rian_sig "pub def to_rust(func Func, types Vec(Type), meta _Unk) _Unk"
  @rian_sig "pub def to_rust(func Func, types Vec(Type), meta _Unk, structs Vec(Struct)) _Unk"
  @rian_sig "pub def to_rust(func Func, types Vec(Type), meta _Unk, structs Vec(Struct), smeta _Unk) _Unk"
  @rian_sig "pub def to_rust(func Func, types Vec(Type), meta _Unk, structs Vec(Struct), smeta _Unk, proto _Unk) _Unk"
  @rian_sig "pub def to_rust(func Func, types Vec(Type), meta _Unk, structs Vec(Struct), smeta _Unk, proto _Unk, ic Ic) _Unk"
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
  @rian_sig "pub def rust_protocols(protocols _Unk, impl_decls _Unk, types Vec(Type), structs Vec(Struct)) _Unk"
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
  @rian_sig "pub def rust_program(prog Prog) _Unk"
  @rian_sig "pub def rust_program(prog Prog, ic Ic) _Unk"
  @spec rust_program(map(), map()) :: term()
  def rust_program(prog, ic \\ %{}) do
    # Erase abstract types to their base (ADR-0067) — a whole-program Rust emit
    # entry reached directly (e.g. tests), so it must erase like `Decl.compile`.
    prog = Rian.Opaque.erase(prog)
    types = Map.get(prog, :types, [])
    structs = Map.get(prog, :structs, [])
    # Stamp `:exh_env` so a non-exhaustive body `case` lowers with the `_ => panic!()`
    # fallthrough on this top-level path too (`module_rust` gets it via `check!`). Only
    # the env — NOT the full `check!` — so a partial *function*'s output is unchanged here
    # (the self-hosted Rust emitter adds no function fallthrough on this path, and the
    # fixpoint compares the two): the body-`case` fallthrough needs just the env.
    env = build_env(types, structs, Map.get(prog, :ranges, []))

    funcs =
      Map.get(prog, :funcs, [])
      |> Enum.reject(& &1.dispatch)
      |> Enum.map(&Map.put(&1, :exh_env, env))

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
      emit_ctx(%{
        proto: proto_method_traits(protocols),
        parametric: parametric,
        sigs: sigs,
        fn_field_types: fn_field_type_map(types)
      })

    c = ctx(build_meta(types), build_struct_meta(structs), MapSet.new(), sigs, ic)

    [
      # `@external(:rs, "./codec.ffi.rs", "fun")` file-references (ADR-0080 §7 b): an
      # authored foreign `.ffi.rs` is included as a Rust `mod` (the build copies it
      # beside the output); the call lowers to `mod::fun(args)`.
      rust_foreign_mods(prog),
      Enum.map_join(structs, "\n\n", &rust_struct/1),
      Enum.map_join(types, "\n\n", &rust_enum(&1, "", parametric)),
      # synthesized value-union enums (ADR-0083 Phase 4): one per distinct `A | B`
      synth_union_enums(prog),
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

  # `#[path = "codec.ffi.rs"] mod codec;` for each distinct `.ffi.rs` the program
  # references on `:rs` (ADR-0080 §7 b). The `#[path]` points at the copied basename
  # beside the output; the module name is the file's stem (`codec.ffi.rs` -> `codec`).
  defp rust_foreign_mods(prog) do
    funcs = Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    funcs
    |> Enum.flat_map(fn f ->
      case Map.get(Map.get(f, :externals, %{}), :rs) do
        {:file, path, _fun} -> [path]
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map_join("\n", fn path ->
      ~s(#[path = "#{Path.basename(path)}"] mod #{ffi_mod_name(path)};)
    end)
  end

  defp ffi_mod_name(path),
    do: path |> Path.basename() |> String.replace_suffix(".ffi.rs", "") |> PL.to_snake()

  defp proto_method_traits(protocols),
    do: for(p <- protocols, m <- p.methods, into: %{}, do: {m.name, p.name})

  defp rust_trait(%{name: name, methods: methods} = p) do
    # associated types (ADR-0074 Stage 3): `type Elem` declares `type Elem: Clone;` in
    # the trait, and each projection in a method signature becomes `Self::Elem`. The
    # `Clone` bound mirrors the `: Clone` every Rian tvar carries (the emitter clones
    # owned values liberally) — without it a consumer like `fcount`, which passes the
    # element through a generic `len_l<T: Clone>`, fails to satisfy `C::Elem: Clone`.
    assoc = Map.get(p, :assoc, [])
    type_members = Enum.map_join(assoc, "", &"    type #{&1}: Clone;\n")

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
    # the surface body (before pattern resolution) carries the `{:case, …}`/`{:ctor, …}`
    # nodes `borrowed_vec_field_binders` reads — e.g. `def to_list(b) := case b do
    # Bag(xs) -> xs end` binds `xs` to a `&Vec<T>`, which a `-> Vec<T>` method must clone.
    pre = method.body |> body_ast(c) |> rewrite_proto_calls(base_ec.proto)

    ec = %{
      base_ec
      | ok_string: ok?,
        err_string: err?,
        borrowed_vec_fields: borrowed_vec_field_binders(pre, c)
    }

    # A `Vec`-returning method coerces its borrowed-collection tail leaves to owned
    # `Vec<T>` at the AST level (Gap E+, parity with `rust_fn`); every other return keeps
    # the string-level `coerce_ret` path exactly (so `String`/scalar impls cannot regress).
    body =
      if match?("Vec(" <> _, ret_ty),
        do: proto_body_ast(method.body, c, ec) |> coerce_owned_vec_ast(ec),
        else: method.body |> rust_proto_body(c, ec) |> coerce_ret(ret_ty)

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
  defp coerce_ret(body, ret) do
    if string_repr?(ret), do: "(#{body}).to_string()", else: body
  end

  # types whose Rust representation is an owned `String` / borrowed `&str`: the literal
  # `String`, and a `Symbol` (`:foo`), which lowers to a string (ADR-0041). A body that
  # yields a `&str` (a literal, a `Symbol` value) must `.to_string()` for an owned return.
  defp string_repr?("String"), do: true
  defp string_repr?("Symbol"), do: true
  defp string_repr?(_), do: false

  # A `String | E` return wraps its value in `Ok(…)`/`Err(…)` (ADR-0040): an
  # `Ok("hi")` is `Result<&str, _>`, not the `Result<String, _>` the signature
  # promises, so the *payload* needs the same `&str -> String` coercion `coerce_ret`
  # applies to a plain `String` body. These per-function flags — folded into the
  # emitter context `ec` in `rust_fn` / `rust_impl_method` — tell the `Ok`/`Err`
  # emit whether its payload type is `String`. `.to_string()` is a no-op clone when
  # the payload is already a `String`.
  defp result_str_flags(ret) do
    case result_parts(ret) do
      {:result, ok, err} -> {string_repr?(ok), string_repr?(err)}
      _ -> {false, false}
    end
  end

  # the payload of `Ok(_)`/`Err(_)` must be owned: a borrowed `&T` (a generic ok-type,
  # `def f() Result(T, E) := {:ok, x}`) is `.clone()`d like any owned-position value
  # (`rust_owned_elem`), and a `&str` for a `String` ok/err-type additionally `.to_string()`s.
  defp result_payload(val, string?, ec) do
    s = rust_owned_elem(val, ec)
    # a `&str`/`Symbol` payload variable needs `.to_string()` for a `String` ok/err-type;
    # a string/`Symbol` *literal* is already `.to_string()`d by `rust_owned_elem`, so it
    # must not be coerced twice.
    literal? = match?(%EStr{}, val) or match?(%EAtom{}, val)
    if string? and not literal?, do: "(#{s}).to_string()", else: s
  end

  defp impl_param({name, sig_p}, rust_type) do
    {_n, ty} = name_type(sig_p)
    "#{name}: #{ref_type(ty, rust_type)}"
  end

  # lower an impl-method body through the same Rust pipeline `rust_fn` uses,
  # rewriting protocol-method calls to UFCS first. `ec` carries the proto map (for
  # the UFCS rewrite) and the per-method result-string flags (for `Ok`/`Err` emit).
  defp rust_proto_body(src, c, ec),
    do: proto_body_ast(src, c, ec) |> emit(:rust, ec) |> elem(0)

  # the impl-method body as a typed-core AST (the shared prefix of `rust_proto_body`),
  # exposed so `rust_impl_method` can route a `Vec`-returning body through the
  # `coerce_owned_vec_ast` tail coercion (Gap E+) instead of the string-level emit.
  defp proto_body_ast(src, c, ec) do
    src
    |> body_ast(c)
    |> rewrite_proto_calls(ec.proto)
    |> resolve_rust_pats(c.meta)
    |> insert_borrows(Map.get(c, :funs, %{}), ec)
    |> Rian.Check.annotate(ec.tenv, ec.ic)
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
  @rian_sig "pub def rewrite_proto_calls(node _Unk, methods _Unk) _Unk"
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

  defp rust_generics(%{tvars: tvars, bounds: bounds} = gf) do
    # a tvar captured by a boxed/`Rc` `dyn Fn` that outlives the frame needs a `'static`
    # bound (alongside `Clone`). `box_fn_type` is the relevant `Fn(...)` type — from a `Fn`
    # return OR a constructed `Fn`-field (`mk(x T) Cell` returns `Cell<T>`, so `T: 'static`).
    box = to_string(Map.get(gf, :box_fn_type, ""))

    # a tvar used as a `Map(K, V)` KEY lowers to a Rust `HashMap<K, V>` key, so it needs
    # `Eq + Hash` (the `HashMap::get`/`insert` bound) on top of `Clone` (ADR-0047).
    sig_types = Enum.map(Map.get(gf, :params, []), & &1.type) ++ [Map.get(gf, :ret)]

    map_keys =
      sig_types |> Enum.filter(&is_binary/1) |> Enum.flat_map(&map_key_tvars/1) |> MapSet.new()

    inner =
      Enum.map_join(tvars, ", ", fn tv ->
        bounds_map =
          case bounds do
            nil -> %{}
            b -> b
          end

        # `'static` for a tvar captured by a `dyn Fn`: in `box_fn_type` (a returned/constructed
        # closure), OR anywhere the signature mentions a type with an `Fn(...)` field (its
        # `Rc<dyn Fn>` field is `'static`, so a consumer's `&Cell<T>` needs `T: 'static`).
        in_box? = box != "" and String.match?(box, ~r/\b#{tv}\b/)
        static = if in_box? or Map.get(gf, :fn_field_sig?, false), do: ["'static"], else: []
        # fully-qualify `Hash` (bare `Hash` resolves to the derive macro, not the trait);
        # `Eq` is in the std prelude.
        key = if MapSet.member?(map_keys, tv), do: ["Eq", "std::hash::Hash"], else: []

        traits =
          Enum.map(Map.get(bounds_map, tv, []), &"Rian#{&1}") ++ ["Clone"] ++ static ++ key

        "#{tv}: #{Enum.join(traits, " + ")}"
      end)

    "<#{inner}>"
  end

  defp rust_generics(_), do: ""

  # Does a `Fn(arg, …, ret)` type return a bare type variable? (its last top-level
  # component is a tvar) — the case that needs a per-call `.clone()` in the closure body.
  defp fn_returns_tvar?("Fn(" <> rest, tvars) do
    rest |> String.replace_suffix(")", "") |> top_args() |> List.last() |> Kernel.in(tvars)
  end

  defp fn_returns_tvar?(_, _), do: false

  # split a comma list at paren-depth 0: `"Int53, Pair(K, V)"` → `["Int53", "Pair(K, V)"]`.
  defp top_args(s) do
    {acc, cur, _} =
      Enum.reduce(String.graphemes(s), {[], "", 0}, fn
        ",", {acc, cur, 0} -> {acc ++ [cur], "", 0}
        "(", {acc, cur, d} -> {acc, cur <> "(", d + 1}
        ")", {acc, cur, d} -> {acc, cur <> ")", d - 1}
        g, {acc, cur, d} -> {acc, cur <> g, d}
      end)

    Enum.map(acc ++ [cur], &String.trim/1)
  end

  # the `Fn(...)` substring of a (possibly nested) return type — `Option(Fn(Int53, T))`
  # → `"Fn(Int53, T)"`, `Fn(T, T)` → itself — the balanced-paren group from the first `Fn(`.
  defp extract_fn_type(ret) do
    case :binary.match(to_string(ret), "Fn(") do
      :nomatch -> ""
      {start, _} -> balanced_from(binary_part(ret, start, byte_size(ret) - start))
    end
  end

  # the KEY tvar of the first `Map(K, V)` in a type string, if `K` is a type variable
  # (`"Map(K, V)"` → `["K"]`, `"Map(String, V)"` → `[]`). Used to add `Eq + Hash` bounds.
  defp map_key_tvars(type) do
    case :binary.match(type, "Map(") do
      :nomatch ->
        []

      {start, _} ->
        inner =
          binary_part(type, start, byte_size(type) - start)
          |> balanced_from()
          |> String.replace_prefix("Map(", "")
          |> String.replace_suffix(")", "")

        case Rian.TypeStr.split_top_commas(inner) do
          [k | _] -> if tvar_name?(String.trim(k)), do: [String.trim(k)], else: []
          _ -> []
        end
    end
  end

  # the leading `Ident(...)` whose parens balance: `"Fn(a, T)) | E"` → `"Fn(a, T)"`.
  defp balanced_from(s) do
    {head, _} =
      s
      |> String.graphemes()
      |> Enum.reduce_while({"", 0}, fn
        "(", {acc, d} -> {:cont, {acc <> "(", d + 1}}
        ")", {acc, 1} -> {:halt, {acc <> ")", 0}}
        ")", {acc, d} -> {:cont, {acc <> ")", d - 1}}
        g, {acc, d} -> {:cont, {acc <> g, d}}
      end)

    head
  end

  # paren-aware top-level comma split of a parameter string
  defp pcommas(s), do: Rian.TypeStr.split_top_commas(s)

  # One Rust `fn` (no type/struct preamble). `vis` is `""` or `"pub "`.
  # an `@external` function (ADR-0068): emit the `:rs` host body verbatim. Rust uses
  # named params, so the spec references them directly — no positional binding. No
  # `:rs` body -> the function is off `:rs` (Reach pins it); reaching here is an
  # off-target compile error (ADR-0041 §2).
  defp rust_fn(func, ctx, vis, base_ec \\ nil)

  defp rust_fn(%{externals: ext} = func, _ctx, vis, _base_ec) when map_size(ext) > 0 do
    host =
      case Map.get(ext, :rs) do
        nil ->
          raise "`#{func.name}`: no `@external(:rs, …)` body — not reachable on :rs"

        # a file-reference calls the included `mod`'s function (the `mod` decl is at
        # the top of the program, `rust_foreign_mods/1`); params are passed by name.
        {:file, path, fun} ->
          "#{ffi_mod_name(path)}::#{fun}(#{Enum.map_join(func.params, ", ", & &1.name)})"

        spec ->
          Rian.External.render(spec, func.params)
      end

    param_decls =
      Enum.map_join(func.params, ", ", fn p ->
        "#{p.name}: #{cap_param(p)}"
      end)

    "#{vis}fn #{func.name}(#{param_decls}) -> #{rust_ret(func.ret)} { #{host} }"
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

    # a function that produces a closure VALUE — a `Fn(...)` return (top-level or nested,
    # `Option(Fn(…, T))`) OR a construction of a type with an `Fn(...)` FIELD (`Cell(f Fn(…,
    # T))`) — must OWN any tvar param the closure captures (a `&T` borrow can't satisfy the
    # `dyn Fn`'s `'static`), so a tvar param lowers owned. `box_fn_type` is the relevant `Fn`
    # type (for the `'static`/clone decision); `fn_rc?` picks `Rc::new` (a shared FIELD
    # closure, so the enum is `Clone`) over `Box::new` (a returned closure).
    {box_fn_type, fn_rc?} =
      cond do
        String.contains?(to_string(func.ret), "Fn(") ->
          {extract_fn_type(func.ret), false}

        true ->
          case Map.get(base_ec.fn_field_types, to_string(func.ret)) do
            nil -> {nil, false}
            ft -> {ft, true}
          end
      end

    closure_ret? = box_fn_type != nil

    gen_func =
      gen_func
      |> Map.put(:box_fn_type, box_fn_type)
      |> Map.put(:fn_field_sig?, fn_field_in_sig?(func, base_ec.fn_field_types))

    param_decls =
      Enum.map_join(func.params, ", ", fn p ->
        ptype =
          if closure_ret? and p.type in gen_func.tvars,
            do: prim_rust(p.type),
            else: cap_param(p)

        "#{p.name}: #{rustify_parametric(ptype, pinst)}"
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
    # value-position closures in a `Fn(...)`-returning function box (top-level OR nested in
    # the return type), cloning a captured tvar body per call (a reusable `Fn`, not FnOnce).
    fn_box =
      if box_fn_type,
        do: %{
          clone?: fn_returns_tvar?(box_fn_type, Map.get(func, :tvars, [])),
          rc?: fn_rc?
        },
        else: nil

    fn_ec = %{base_ec | ok_string: ok?, err_string: err?, fn_box: fn_box}

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
            borrowed_vec_fields: borrowed_vec_field_binders(pre, ctx),
            tenv: tenv,
            ic: ctx.ic
        }

        # value unions (ADR-0083): the union-typed LOCALS in scope (params + a binding
        # `x := <union call/var>`) and the program's union-RETURNING functions. A `case`
        # over a union local OR a union-returning call narrows to a `match` on the enum
        # (type-pattern arms → `Enum::Variant(binder)`); the locals also guard
        # construction wrapping (a union-typed value is already the enum, not re-wrapped).
        union_funcs =
          for {{n, _a}, sf} <- Map.get(ctx, :funs, %{}),
              union_type?(sf.ret),
              into: %{},
              do: {n, sf.ret}

        union_locals = union_locals(pre, func.params, union_funcs)
        ec = Map.put(ec, :union_scope, union_locals)

        surface =
          pre
          |> resolve_rust_pats(ctx.meta, %{
            scope: union_locals,
            funcs: union_funcs,
            env: Map.get(func, :exh_env, %{})
          })
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
        # Coerce the clause body to the owned value its signature promises (a no-rebind
        # body pushes the coercion into `if`/`case` TAIL leaves so a borrowed leaf unifies
        # with an owned one — Gap B/E). A `String` return coerces every leaf to owned
        # `String`; a `Vec` return SELECTIVELY `.to_vec()`s only the borrowed-collection
        # leaves (a `&[T]` slice or `&Vec<T>` field binder — e.g. `def drop(cs, 0) := cs`
        # or `def to_list(b) := case b do Bag(xs) -> xs end`), leaving owned leaves alone.
        arm =
          cond do
            # a value-union RETURN (ADR-0083): wrap each member-producing TAIL leaf into
            # the synthesized enum (`Enum::from(leaf)`), pushed into if/case branches; a
            # leaf already of union type passes through. With rebinds, wrap the whole arm.
            union_type?(func.ret) and rebinds == [] ->
              coerce_union_ret_ast(ast, union_enum_name(func.ret), ec)

            union_type?(func.ret) ->
              union_wrap(arm, ast, union_enum_name(func.ret))

            string_repr?(func.ret) and rebinds == [] ->
              coerce_string_ast(ast, ec)

            match?("Vec(" <> _, func.ret) and rebinds == [] ->
              coerce_owned_vec_ast(ast, ec)

            match?("Vec(" <> _, func.ret) and tail_slice_id?(ast, ec) ->
              "(#{arm}).to_vec()"

            # a generic bare-tvar return (`T`): clone borrowed leaves to the owned `T` the
            # signature promises (`T: Clone`), pushed into `if`/`case` branches so a borrowed
            # leaf (a returned param `d`) unifies with an owned one (`get(m,k)`). The `generic?`
            # guard short-circuits the `func.tvars` access for a func map lacking that key.
            generic? and func.ret in func.tvars and rebinds == [] ->
              coerce_owned_tvar_ast(ast, ec)

            true ->
              coerce_ret(arm, func.ret)
          end

        # the rebinds path can't push into branches (the body is already a `{ … }` block),
        # so wrap the whole arm — a no-op clone when it already owns its `T`.
        arm =
          if generic? and func.ret in func.tvars and rebinds != [],
            do: "(#{arm}).clone()",
            else: arm

        # (a value-position closure boxes at the `ELambda` emit, driven by `fn_ec.fn_box`,
        # so it covers a top-level return AND a `Fn` nested in a constructor — `Some((n) ->
        # x)` — uniformly; see `emit(%ELambda{}, :rust, …)`.)

        # binders bound inside a list/slice element are `&T` — a guard over them
        # must deref (`*c`); the arm body's arithmetic works on `&T` directly
        deref = Enum.flat_map(c.pats, fn p -> slice_elem_vars(Core.from_pat(p)) end)
        "        #{pat}#{guard_str(c, :rust, ec, deref)} => #{arm},"
      end)

    # Fallthrough arm. A `partial` function (non-total clause heads, stamped by
    # `check!`) gets a `_ => panic!(…)` — the totality Rust's `match` requires, matching
    # the BEAM `FunctionClauseError` / JS-JVM `throw` (ADR-0036). Otherwise the
    # per-target exhaustiveness shim (ADR-0036): a `range`-total match has literal arms
    # over an *open* base primitive (`i64`/`char`) that `rustc` sees as non-exhaustive,
    # so append an `unreachable!()` arm (the Rian gate proved totality). A closed sum
    # match needs neither (a `_`/var clause already covers the rest).
    shim =
      cond do
        Map.get(func, :partial, false) ->
          "\n        _ => panic!(#{inspect("#{func.name}: no clause matched")}),"

        rust_total_shim?(func) ->
          "\n        _ => unreachable!(),"

        true ->
          ""
      end

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

  # A fallible function returns `Result(T, E)` explicitly (the `T | E` sugar was
  # removed — ADR-0083) — the ok-type then the error set. It lowers to Rust
  # `Result<T, E>`; on the BEAM the value shape `{:ok,_}`/`{:error,_}` carries it.
  defp rust_ret(ret) do
    case result_parts(ret) do
      {:plain, t} -> prim_rust(t)
      {:result, ok, err} -> "Result<#{prim_rust(ok)}, #{prim_rust(err)}>"
    end
  end

  # parse an explicit `Result(ok, err)` -> `{:result, ok, err}`; any other type is
  # `{:plain, ret}`. (Keyed on the `Result(` head + top-level comma now, not the
  # retired `|` sugar.)
  defp result_parts("Result(" <> rest) do
    case Rian.TypeStr.split_top_commas(binary_part(rest, 0, byte_size(rest) - 1)) do
      [ok, err] -> {:result, ok, err}
      _ -> {:plain, "Result(" <> rest}
    end
  end

  defp result_parts(ret), do: {:plain, ret}

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
            fs =
              Enum.map_join(v.fields, ", ", fn f ->
                "#{f.label}: #{rust_field_type(f.type, parametric)}"
              end)

            "    #{v.ctor} { #{fs} },"

          true ->
            fs = Enum.map_join(v.fields, ", ", &rust_field_type(&1.type, parametric))
            "    #{v.ctor}(#{fs}),"
        end
      end)

    join_doc(
      rs_doc(Map.get(t, :doc), "///"),
      "#{enum_derive(t)}\n#{vis}enum #{t.name}#{enum_generics(t, parametric)} {\n#{variants}\n}"
    )
  end

  # The derive list. A type holding a CLOSURE field (`Fn(...)`) can derive only `Clone`
  # (its field is an `Rc<dyn Fn>`, which is `Clone` but not `Debug`/`PartialEq` — a closure
  # has no portable `Debug`/`Eq`). `Rian.Reach` pins a function that `==`/interpolates such a
  # type. Every other type derives the full set.
  defp enum_derive(t),
    do: if(has_fn_field?(t), do: "#[derive(Clone)]", else: "#[derive(Clone, Debug, PartialEq)]")

  defp has_fn_field?(t),
    do: Enum.any?(field_types(t), &String.contains?(to_string(&1), "Fn("))

  # an enum field's Rust type. A `Fn(...)` field is a SHARED closure — `Rc<dyn Fn>` (a `Box`
  # isn't `Clone`, so the enum couldn't derive `Clone`); `Rc::new` constructs it. A field
  # that is (exactly) a parametric user type's name instantiates with that type's params
  # (`p Pair` → `Pair<K, V>`); every other field lowers via `prim_rust`.
  defp rust_field_type(ft, parametric) do
    cond do
      String.starts_with?(to_string(ft), "Fn(") ->
        String.replace_prefix(prim_rust(ft), "Box<dyn ", "std::rc::Rc<dyn ")

      Map.has_key?(parametric, ft) ->
        "#{ft}<#{Enum.join(Map.fetch!(parametric, ft), ", ")}>"

      true ->
        prim_rust(ft)
    end
  end

  # ── synthesized value-union enums (ADR-0083 Phase 4) ──────────────────────
  # A structural union `A | B` has no native Rust type, so each DISTINCT union in
  # the program lowers to a name-mangled, de-duplicated `enum` + a `From<member>`
  # per member: construction is a member `.into()` (the call-site coercion adds it),
  # narrowing a `match` arm. A `String` member also gets `From<&str>` so a string
  # literal arg wraps without a separate `.to_string()`.
  defp synth_union_enums(prog) do
    prog |> collect_union_types() |> Enum.map_join("\n\n", &union_enum_decl/1)
  end

  defp collect_union_types(prog) do
    funcs = Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    funcs
    |> Enum.flat_map(fn f -> [f.ret | Enum.map(f.params, & &1.type)] end)
    |> Enum.filter(&union_type?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp union_type?(t), do: is_binary(t) and String.starts_with?(t, "Union(")

  defp union_members_of("Union(" <> rest),
    do: rest |> binary_part(0, byte_size(rest) - 1) |> Rian.TypeStr.split_top_commas()

  defp union_enum_name(t),
    do: "RUnion_" <> Enum.map_join(union_members_of(t), "_", &variant_name/1)

  defp variant_name(m), do: String.replace(m, ~r/[^A-Za-z0-9]/, "_")

  defp union_enum_decl(t) do
    members = union_members_of(t)
    name = union_enum_name(t)
    variants = Enum.map_join(members, " ", fn m -> "#{variant_name(m)}(#{prim_rust(m)})," end)

    froms =
      Enum.flat_map(members, fn m ->
        v = variant_name(m)
        rt = prim_rust(m)
        base = "impl From<#{rt}> for #{name} { fn from(x: #{rt}) -> Self { Self::#{v}(x) } }"

        if rt == "String",
          do: [
            base,
            "impl From<&str> for #{name} { fn from(x: &str) -> Self { Self::#{v}(x.to_string()) } }"
          ],
          else: [base]
      end)
      |> Enum.join("\n")

    "#[derive(Clone, Debug, PartialEq)]\nenum #{name} { #{variants} }\n#{froms}"
  end

  # `<K, V>` for a parametric type (its variant fields are typed by type variables),
  # else `""`. The params are the distinct field tvars in order of appearance.
  defp enum_generics(t, parametric) do
    case Map.get(parametric, t.name) do
      nil ->
        ""

      [] ->
        ""

      params ->
        # a tvar appearing in a `Fn(...)` field is captured by the field's `Rc<dyn Fn>`,
        # which is `'static`, so the param needs the `'static` bound too (besides `Clone`).
        static = fn_field_tvars(t)

        inner =
          Enum.map_join(params, ", ", fn p ->
            if MapSet.member?(static, p), do: "#{p}: Clone + 'static", else: "#{p}: Clone"
          end)

        "<#{inner}>"
    end
  end

  # the tvars a type mentions inside a `Fn(...)` field (they need a `'static` bound).
  defp fn_field_tvars(t) do
    t
    |> field_types()
    |> Enum.filter(&String.contains?(to_string(&1), "Fn("))
    |> Enum.flat_map(&type_tvars/1)
    |> MapSet.new()
  end

  # parametric user types: name -> ordered list of its field type-variable params. A field
  # that is (exactly) ANOTHER parametric type's name contributes THAT type's params
  # (`Wrap(p Pair)` is generic over Pair's `K, V`), so the map is resolved to a fixpoint to
  # propagate a chain. (`Rian.Reach` pins the un-emittable nesting shapes — self-recursion,
  # a parametric type inside a compound — so this only ever runs for shapes that compile.)
  defp parametric_param_map(types) do
    names = MapSet.new(types, & &1.name)
    converge_params(types, names, %{}) |> Enum.reject(fn {_n, p} -> p == [] end) |> Map.new()
  end

  defp converge_params(types, names, acc) do
    next = Map.new(types, fn t -> {t.name, type_param_tvars(t, names, acc)} end)
    if next == acc, do: next, else: converge_params(types, names, next)
  end

  defp type_param_tvars(t, names, acc) do
    t.variants
    |> Enum.flat_map(fn v -> Enum.map(v.fields, &Map.get(&1, :type)) end)
    |> Enum.flat_map(fn ft ->
      if MapSet.member?(names, ft), do: Map.get(acc, ft, []), else: type_tvars(ft)
    end)
    |> Enum.uniq()
  end

  # a bare type-variable name — a single capital optionally followed by ONE digit, matching
  # the `Rian.Check`/`Rian.Reach` `tvar?` convention so the emitter and the reach gate agree
  # on what counts as a tvar (a `T12`-style field would otherwise diverge between them).
  defp tvar_name?(t) when is_binary(t), do: String.match?(t, ~r/^[A-Z][0-9]?$/)
  defp tvar_name?(_), do: false

  # every type-variable token MENTIONED in a type string, in order of first appearance:
  # a bare `T` → `["T"]`, a compound `Vec(T)` → `["T"]`, `Dict(K, V)` → `["K", "V"]`.
  # (The enum's generic params are the union of these over all its fields, so a field
  # that nests a tvar — `items Vec(T)` — declares `<T>` instead of emitting an undeclared
  # `T`; ADR-0061 parametric subset.)
  defp type_tvars(type) when is_binary(type) do
    Regex.scan(~r/[A-Za-z_]\w*/, type) |> Enum.map(&hd/1) |> Enum.filter(&tvar_name?/1)
  end

  defp type_tvars(_), do: []

  # the declared type strings of a user type's variant fields.
  defp field_types(t),
    do: t.variants |> Enum.flat_map(& &1.fields) |> Enum.map(&Map.get(&1, :type))

  # user types carrying a (direct) `Fn(...)` field, name → that field's `Fn` type string —
  # a function constructing one stores the closure in an `Rc<dyn Fn>` field (`Rc::new`).
  defp fn_field_type_map(types) do
    for t <- types,
        ft = Enum.find(field_types(t), &String.contains?(to_string(&1), "Fn(")),
        ft != nil,
        into: %{},
        do: {t.name, ft}
  end

  # does a function's signature mention a type that carries an `Fn(...)` field? Such a type
  # lowers to an `Rc<dyn Fn>` (`'static`) field, so every tvar of a function touching it needs
  # a `'static` bound — a CONSUMER (`run(c Cell)`) as much as a constructor.
  defp fn_field_in_sig?(func, fn_field_types) do
    names = Map.keys(fn_field_types)
    sig = Enum.map(Map.get(func, :params, []), & &1.type) ++ [Map.get(func, :ret)]
    Enum.any?(sig, fn t -> is_binary(t) and Enum.any?(names, &word_member?(t, &1)) end)
  end

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
  # a `Symbol` pattern matches the atom's interned name as a `&str` literal (ADR-0041),
  # mirroring the value emit; the `:ok`/`:error` Result tags are handled above.
  defp pat_rs(%PAtom{name: a}, _), do: str_lit(a)
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
  @rian_sig "pub def emit_expr(src String, target Symbol) _Unk"
  @doc "Emit a single Rian expression string to :elixir or :rust."
  @spec emit_expr(String.t(), atom()) :: term()
  def emit_expr(src, target),
    do: emit(Rian.Check.annotate(Rian.Pratt.parse(src), %{}, %{}), target, emit_ctx()) |> elem(0)

  @rian_sig "pub def emit_ast(ast _Unk, target Symbol) _Unk"
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
  # a `Symbol` (`:foo`) is a native atom on the BEAM and an interned-name string
  # elsewhere (ADR-0041): equality-only, so it lowers to a Rust `&str` literal (a JS
  # string, `Rian.JS`). Erlang FFI (`:mod.fun`) stays BEAM-only.
  defp emit(%EAtom{name: a}, :elixir, _ec), do: {":" <> a, 12}
  defp emit(%EAtom{name: a}, :rust, _ec), do: {str_lit(a), 12}
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

  # `Map(K, V)` prims (ADR-0047) -> Rust `HashMap` ops. A `val` map/key/value is a borrow
  # (`&HashMap`/`&K`/`&V`), so `get` clones the value out (`.cloned().unwrap()`), `put` builds
  # a fresh owned map (clone the map, insert cloned key/value — a functional update matching
  # BEAM/JS), and `new`/`has` map directly. `K: Eq + Hash` is added by `rust_generics`.
  defp emit(%ECall{fun: %EId{name: "__prim_map_new"}, args: []}, :rust, _ec),
    do: {"std::collections::HashMap::new()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_map_get"}, args: [m, k]}, :rust, ec),
    do: {"#{p(m, 12, :rust, ec)}.get(#{p(k, 12, :rust, ec)}).cloned().unwrap()", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_map_has"}, args: [m, k]}, :rust, ec),
    do: {"#{p(m, 12, :rust, ec)}.contains_key(#{p(k, 12, :rust, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_map_put"}, args: [m, k, v]}, :rust, ec),
    do:
      {"{ let mut __m = #{p(m, 12, :rust, ec)}.clone(); " <>
         "__m.insert(#{p(k, 12, :rust, ec)}.clone(), #{p(v, 12, :rust, ec)}.clone()); __m }", 0}

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

  # runtime `Show` fallthrough for an `:unknown`-typed interpolation hole (ADR-0069 §2):
  # Elixir `to_string/1` (String.Chars) is the native runtime stringifier. Rust has no
  # universal `Display`, so `Rian.Reach` pins a caller off `:rs`; the Rust arm here is a
  # best-effort `format!("{}", …)` for the rare case it is still selected.
  defp emit(%ECall{fun: %EId{name: "__prim_to_string"}, args: [x]}, :elixir, ec),
    do: {"to_string(#{p(x, 0, :elixir, ec)})", 12}

  defp emit(%ECall{fun: %EId{name: "__prim_to_string"}, args: [x]}, :rust, ec),
    do: {"format!(\"{}\", #{p(x, 0, :rust, ec)})", 12}

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
    {"|#{closure_params(1, Core.cap_arity(body))}| #{p(body, 0, :rust, ec)}", 12}
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
  # `&` is injected by the call-site borrow pass (Rust only) — never parsed. A `&<closure>`
  # is a CALLBACK reference (`&impl Fn`, ADR-0061), never a value-position boxed closure — so
  # clear `fn_box` for it: in a `Fn(...)`-returning function the returned closure boxes, but a
  # lambda it passes to a HOF must stay a bare `|…| …` (boxing it would be `&Box::new(…)`, a
  # borrow of a temporary — rustc E0716).
  defp emit(%EUnary{op: "&", arg: %ELambda{} = x}, :rust, ec),
    do: {"&" <> p(x, 11, :rust, %{ec | fn_box: nil}), 11}

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
    body_str = p(body, 0, :rust, ec)

    # a value-position closure lowers to an owned `move`-capturing trait object: `Box<dyn Fn>`
    # for a returned closure, `Rc<dyn Fn>` for a constructed FIELD closure (`rc?` — shared, so
    # the enum is `Clone`). The captured tvar body is `.clone()`d per call (a reusable `Fn`
    # can't move its capture out). A callback-arg closure (no `fn_box`) stays a bare `|…| …`.
    case ec[:fn_box] do
      nil ->
        {"|#{ps}| #{body_str}", 12}

      %{clone?: clone?} = fb ->
        inner = if clone?, do: "(#{body_str}).clone()", else: body_str
        ctor = if Map.get(fb, :rc?), do: "std::rc::Rc::new", else: "Box::new"
        {"#{ctor}(move |#{ps}| #{inner})", 12}
    end
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
    do: {rust_case(scrut, arms, fn b, aec -> p(b, 0, :rust, aec) end, ec), 0}

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

  # a tuple value owns its elements (like a `Vec`), so a borrowed binder element is cloned
  # and a string/symbol literal `.to_string()`d (`rust_owned_elem`) — e.g. a generic
  # `(b, a)` returning `(U, T)` from `&U`/`&T` binders becomes `(b.clone(), a.clone())`.
  defp emit(%ETuple{elems: es}, :rust, ec),
    do: {"(#{Enum.map_join(es, ", ", &rust_owned_elem(&1, ec))})", 12}

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

  # membership `x in xs` — Rust has no `in` operator; lower to `.contains(&x)` over
  # the slice/Vec. (The Elixir-text path keeps `x in xs`, valid Elixir, via the
  # generic clause below.)
  defp emit(%EBin{op: "in", left: l, right: r}, :rust, ec),
    do: {"#{p(r, 12, :rust, ec)}.contains(&#{p(l, 12, :rust, ec)})", 12}

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
  defp rust_owned_elem(%EId{name: n, type: t} = e, ec) do
    s = p(e, 0, :rust, ec)

    cond do
      # a `&[T]` slice → `Vec<T>` (a `.clone()` would clone the reference, Gap D)
      slice_var?(e, ec) -> "#{s}.to_vec()"
      # a `String`/`Symbol` value is a `&str` borrow in an owned position → `.to_string()`
      # (`.clone()` on a `&str` yields `&str`, not `String` — `str` is not `Clone`).
      t in ["String", "Symbol"] -> "#{s}.to_string()"
      MapSet.member?(ec.borrowed, n) -> "#{s}.clone()"
      true -> s
    end
  end

  # a string literal / `Symbol` value (`:foo`) lowers to a `&str`, but in an owned
  # position — a `Vec(String)`/`Vec(Symbol)` element, a `String`/`Symbol` struct or
  # variant field — the owned `String` is wanted, so `.to_string()` it (ADR-0041). E.g.
  # `Words(["a", "b"])` builds `vec!["a".to_string(), "b".to_string()]` for `Vec<String>`.
  defp rust_owned_elem(%EStr{} = e, ec), do: "#{p(e, 0, :rust, ec)}.to_string()"
  defp rust_owned_elem(%EAtom{} = e, ec), do: "#{p(e, 0, :rust, ec)}.to_string()"

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
  defp prim_rust("Union(" <> _ = t), do: union_enum_name(t)
  defp prim_rust(t), do: Rian.Capability.owned(t)

  # the Rust parameter type. A value union (ADR-0083) is an OWNED synthesized enum
  # (not a borrow — it carries the moved value); everything else goes through the
  # capability mapping (`&[T]` / owned `Vec<T>` / `&T`).
  defp cap_param(%{type: t} = p) do
    if union_type?(t), do: union_enum_name(t), else: Rian.Capability.rust_param(p.cap, p.type)
  end

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
