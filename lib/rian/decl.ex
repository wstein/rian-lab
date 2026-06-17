defmodule Rian.Decl do
  @moduledoc """
  Stage 0.1 declaration parser (ADR-0031) — the gate from "verified components"
  to "a language that reads source files."

  Parses `.rian` declaration source into the IR the lowering pipeline already
  consumes (`Rian.Lower.compile/2`), then drives it. Surface follows ADR-0033:
  `def`, juxtaposed types, Crystal primitive names, `:=` bodies.

  ## Implementation

  Token-driven recursive descent over `Rian.Lexer.tokenize/1`: `do`/`end`/`;`
  and significant `{:nl}` tokens drive declaration boundaries and block bodies,
  so block bodies — which the earlier line-joining MVP could not parse — work.
  Token *ranges* (params, patterns, bodies) are detokenized and handed to the
  string content helpers below; bodies are re-parsed by `Rian.Pratt.parse_body/1`.

  ## Supported

    * `type Name := Ctor(field Type, …) | Ctor2 | …` — sum declarations.
    * `def` functions, single- or multi-parameter:
      * single typed clause — `def add(x Int64, y Int64) Int64 := x + y`
      * bodiless signature + pattern clauses —
        `def max2(a Int64, b Int64) Int64` then `def max2(a, b) when a >= b := a`
    * `:=` one-liner bodies **and** multiline `… end` **block bodies**, including
      `case … do … end` expressions, string literals, and `when` guards.
    * `alias Name := Type` — transparent synonyms, resolved by substituting the
      name out of every type position (introduces no runtime form).
    * `opaque Name := Base` (ADR-0043 / ADR-0067) — an **abstract** type: nominally
      distinct from `Base` in the checker (so `Name`≠`Base`) but **erased to `Base`**
      at zero cost on every target by `Rian.Opaque.erase/1` (after the gates).
      Constructed by the total `Name.of(x)` (`x : Base`).
    * `abstract Name := Base do op +(a Name, b Name) Name … ; to base() Base end`
      (ADR-0067 P1b/P1c) — `opaque` plus an **operator** surface (`op` rules forward
      to the base operator: `Name + Name` types as `Name`, no implicit decay) and
      explicit **casts** (`to base() Base` → `v.base()` exposes the underlying value,
      erased to the identity). Same zero-cost erasure as `opaque`.
    * `struct Name(field Type, …)` — product types; lower to `defstruct` (BEAM) /
      `struct {…}` (Rust) and are built with positional `Name(v1, v2)` or named
      `Name(field: v, …)` constructor calls.
    * `mod Name do … end` — modules grouping types/structs/consts/defs; lower to
      a `defmodule` (BEAM) / `mod` (Rust). `pub` exports a `def`/`type`/`struct`/
      `const` (`def`/`pub fn`/`pub const`); unmarked items are private.
    * `const NAME Type := value` — module-scoped constants; lower to a 0-arity
      accessor (BEAM) / a `const` (Rust); references resolve per target.
    * `use Path` / `use Path.(name, …)` — module-scoped imports; lower to
      `alias`/`import` (BEAM) and `use …;`/`use …::{…};` (Rust).
    * `@moduledoc`/`@doc`/`@typedoc "…"` doc comments (ADR-0051, heredoc-capable)
      attach to the following declaration and lower to `@moduledoc`/`@doc` (BEAM)
      / rustdoc `//!`/`///` (Rust).
    * `@external(:target, "host expression")` (ADR-0068) — one-or-more precede a
      *bodiless* `def` to give it per-target host (FFI) bodies and no portable body;
      `Rian.Reach` reads them for an honest target set, each emitter lowers its spec.
    * `protocol Name do … end` / `impl Protocol for Type do … end` (ADR-0042 §3)
      — desugar to a guarded dispatcher + mangled impl functions via
      `Rian.Protocol`; coherence-checked. Dispatch over primitive / sum / struct
      types (BEAM). `forall T: Bound` bounds are parsed and enforced by the checker.

    * `macro name(params) := template` / `… do … end` (ADR-0030) — a declarative
      hygienic macro. Calls are expanded AST->AST in `assemble/3` before the
      checker; the macro itself emits no IR. In a `@targets` module the expansion
      is portable-gated (a template introducing a failable bind is rejected,
      ADR-0035/0058). Macros are scope-local (a `mod`'s macros are visible to its
      functions; top-level macros to top-level functions).

  ## Not yet supported

  A top-level `const`/`use` (outside any `mod`) is rejected. Macro *fragment
  kinds* (`expr`/`pat`/`type` positions) and macro calls inside clause *guards*
  are not yet handled; other reserved keywords raise `Rian.Decl.Error`.
  """
  alias Rian.{Check, Lexer, Lower, Pratt}

  alias Rian.IR.{
    Clause,
    Const,
    Field,
    Func,
    Mod,
    Opaque,
    Param,
    Range,
    Struct,
    Type,
    Use,
    Variant
  }

  defmodule Error do
    defexception [:message]
  end

  @caps ~w(val iso ref tag)

  # ── Public API ─────────────────────────────────────────────────────────
  @doc "Parse source into `%{types: [...], structs: [...], funcs: [...], mods: [...]}` (pipeline IR)."
  @spec parse(String.t()) :: map()
  def parse(src) do
    decls = src |> Lexer.tokenize() |> split_decls()
    aliases = collect_aliases(decls)
    prog = assemble(decls, aliases)

    # `const` and `use` are module-scoped: a top-level one has no enclosing module
    # to hold its accessor / import (ADR-0033 / modules: items live in a `mod`).
    if prog.consts != [], do: raise(Error, "`const` must appear inside a `mod`")
    if prog.uses != [], do: raise(Error, "`use` must appear inside a `mod`")

    mods =
      for {:mod, name, inner, doc, targets} <- decls do
        # `Prim` is the reserved intrinsic namespace (ADR-0047 §2): a `Prim.x(…)`
        # call rewrites to the `__prim_x` intrinsic, so a user `mod Prim` would be
        # shadowed (its calls hijacked). Reject it outright rather than miscompile.
        if name == "Prim",
          do:
            raise(
              Error,
              "`Prim` is a reserved namespace (ADR-0047 §2); name the module differently"
            )

        # top-level aliases are visible inside a module; module-local aliases add to them
        scoped = Map.merge(aliases, collect_aliases(inner))
        p = assemble(inner, scoped, targets)

        %Mod{
          name: name,
          uses: p.uses,
          types: p.types,
          ranges: p.ranges,
          opaques: p.opaques,
          structs: p.structs,
          consts: p.consts,
          funcs: p.funcs,
          doc: doc,
          targets: targets
        }
      end

    protocols = all_protocols(decls)
    impl_decls = all_impl_decls(decls)
    # associated-type coherence (ADR-0074 Stage 2): each impl binds exactly its
    # protocol's declared associated types. Raises `Rian.Protocol.Error` at parse time,
    # alongside the method-set coherence the desugar already ran.
    Rian.Protocol.check_assoc!(protocols, impl_decls)

    prog
    |> Map.drop([:consts, :uses])
    |> Map.put(:mods, mods)
    |> Map.put(:impls, all_impls(decls))
    |> Map.put(:protocols, protocols)
    |> Map.put(:impl_decls, impl_decls)
    |> inject_stdlib()
    # infer-local (ADR-0034): fill undeclared private-function return types so the
    # rest of the pipeline sees fully-typed functions. A no-op unless a private
    # function omitted its return.
    |> Rian.InferLocal.fill_returns()
  end

  # Prelude-function injection (ADR-0047 / ADR-0069 §6): a program that interpolates
  # a `Float64` calls `Show.float`, so supply the `Show` module unless the program
  # already defines one. Conditional — injected ONLY when used, so a non-float
  # program is untouched (and never inherits `Show`'s list helpers, which the JVM
  # emitter cannot yet lower).
  #
  # The need is read straight off the rewritten program — `Rian.Interp` emits a
  # `Show.float` call iff a `Float64` hole was interpolated — rather than from a
  # process-dict flag set during desugar, so the interpolation pass stays pure.
  defp inject_stdlib(prog) do
    if needs_show_float?(prog) and not Enum.any?(prog.mods, &(&1.name == "Show")) do
      %{prog | mods: [Rian.ShowStdlib.module() | prog.mods]}
    else
      prog
    end
  end

  # does any clause body call `Show.float`? (the interpolation desugar's signal that
  # the `Show` stdlib is needed — see `Rian.Interp`'s `Float64` case.)
  defp needs_show_float?(prog) do
    (prog.funcs ++ Enum.flat_map(prog.mods, & &1.funcs))
    |> Enum.any?(fn f -> Enum.any?(f.clauses, &calls_show_float?(&1.body)) end)
  end

  defp calls_show_float?({:call, {:dot, {:id, "Show"}, "float"}, _args}), do: true
  defp calls_show_float?(t) when is_tuple(t), do: t |> Tuple.to_list() |> calls_show_float?()
  defp calls_show_float?(list) when is_list(list), do: Enum.any?(list, &calls_show_float?/1)
  defp calls_show_float?(_), do: false

  # Structured `protocol`/`impl` IR preserved for the Rust/JS emitters (ADR-0061):
  # the BEAM desugar (`protocol_defs/3`) discards them, but Rust reads protocols as
  # traits and JS generates its own dispatcher, so both need the original shapes.
  defp all_protocols(decls) do
    in_scope(decls, fn d ->
      for {:protocol, name, inner, _doc} <- d, do: protocol_struct(name, inner)
    end)
  end

  defp protocol_struct(name, inner) do
    methods = for {:def, raw} <- inner, do: %{name: raw.name, params: raw.params, ret: raw.ret}
    # associated types (ADR-0074 Stage 1): a bodiless `type Elem` line declares an
    # associated type the methods may project as `Self.Elem`. Parse + IR only — the
    # checker resolution + lowering are later stages; the BEAM desugar ignores them.
    assoc = for {:type, t, _, _} <- inner, do: String.trim(t)
    %{name: name, methods: methods, assoc: assoc}
  end

  defp all_impl_decls(decls) do
    in_scope(decls, fn d ->
      for {:impl, proto, type, inner, _doc} <- d, do: impl_struct(proto, type, inner)
    end)
  end

  defp impl_struct(proto, type, inner) do
    methods =
      for {:def, raw} <- inner,
          do: %{name: raw.name, params: raw.params, body: raw.body, guard: raw.guard}

    # associated-type bindings (ADR-0074 Stage 1): each `type Elem := Concrete` line
    # fixes the protocol's associated type for this impl. `%{"Elem" => "Int53"}`.
    assoc = for {:type, t, _, _} <- inner, into: %{}, do: parse_assoc_binding(t)
    %{proto: proto, type: type, methods: methods, assoc: assoc}
  end

  # `"Elem := Int53"` -> `{"Elem", "Int53"}`; a binding-less `"Elem"` (an impl error a
  # later checker stage will flag) keeps `nil`.
  defp parse_assoc_binding(t) do
    case String.split(t, ":=", parts: 2) do
      [name, ty] -> {String.trim(name), String.trim(ty)}
      [name] -> {String.trim(name), nil}
    end
  end

  # apply `f` to the top-level decls and to each module's inner decls, concatenating
  defp in_scope(decls, f) do
    f.(decls) ++
      Enum.flat_map(decls, fn
        {:mod, _n, inner, _d, _t} -> f.(inner)
        _ -> []
      end)
  end

  # `(protocol, type)` pairs for every `impl` in the program (top-level and inside
  # any `mod`) — the impl table the checker consults to enforce `forall T: Bound`
  # (ADR-0042 §2). The desugaring in `protocol_defs/3` discards the impls; this
  # keeps the membership facts the bound check needs.
  defp all_impls(decls) do
    top = for {:impl, proto, type, _inner, _doc} <- decls, do: {proto, type}

    nested =
      for {:mod, _n, inner, _d, _t} <- decls,
          {:impl, proto, type, _i, _dd} <- inner,
          do: {proto, type}

    top ++ nested
  end

  # `alias Name := Type` is a transparent synonym: collect the name->type map so
  # the name can be substituted out of every type position (ADR-0033 / types-match:
  # aliases introduce no runtime form).
  # `alias` synonyms plus `range` names — both substitute out of type positions
  # (a `range Name := lo..hi` resolves to its ordinal `base`, ADR-0036's
  # "representation, not newtype"). The `Range` records are kept separately (for
  # the finite exhaustiveness signature); here only the name→base mapping matters.
  defp collect_aliases(decls) do
    aliases = Map.new(for {:alias, t} <- decls, do: parse_alias(t))

    Enum.reduce(decls, aliases, fn
      {:range, text, pub?, doc}, acc ->
        r = parse_range(text, pub?, doc)
        Map.put(acc, r.name, r.base)

      _, acc ->
        acc
    end)
  end

  # One scope's declarations (top level, or one module's body) -> typed IR.
  # `targets` is the enclosing `mod`'s `@targets` (nil at top level / unannotated),
  # used to select the target-relative coherence rules (ADR-0061 §5).
  defp assemble(decls, aliases, targets \\ nil) do
    types =
      for({:type, t, pub?, doc} <- decls, do: parse_type(t, pub?, doc))
      |> Enum.map(&subst_type(&1, aliases))

    ranges = for {:range, r, pub?, doc} <- decls, do: parse_range(r, pub?, doc)

    opaques =
      for({:opaque, o, pub?, doc} <- decls, do: parse_opaque(o, pub?, doc)) ++
        for {:abstract, h, b, pub?, doc} <- decls, do: parse_abstract(h, b, pub?, doc)

    structs =
      for({:struct, s, pub?, doc} <- decls, do: parse_struct(s, pub?, doc))
      |> Enum.map(&subst_struct(&1, aliases))

    user_defs =
      Enum.flat_map(decls, fn
        {:def, raw} -> [raw]
        _ -> []
      end)

    assembled_funcs =
      (user_defs ++ protocol_defs(decls, types, structs, targets))
      # group by name AND arity, so same-name clauses of different arity form
      # separate functions (`f/1` vs `f/2`, like Elixir/Erlang — exported per
      # `{name, arity}` on the BEAM). Same-arity clauses stay one multi-clause group.
      |> Enum.chunk_by(&{&1.name, raw_arity(&1)})
      |> Enum.map(&build_func/1)
      |> Enum.map(&subst_func(&1, aliases))

    # Inference context for the interpolation pass (ADR-0069): with the scope's
    # function signatures in hand, a `${call()}` hole resolves the callee's declared
    # return type, not just literals/params — so an interpolated call result (e.g. a
    # matcher's `"expected ${want}, got ${got()}"`) stringifies instead of erroring.
    # Built inline (not `Check.program_ic`, which pulls in `Rian.Prelude` and would
    # cycle at compile time when the prelude module itself parses); `:funs`/`:fsigs`
    # are all `Check.infer` needs to type a sibling call.
    interp_ic = %{
      funs: Map.new(assembled_funcs, fn f -> {{f.name, length(f.params)}, f.ret} end),
      fsigs:
        Map.new(assembled_funcs, fn f ->
          {{f.name, length(f.params)},
           %{params: Enum.map(f.params, & &1.type), ret: f.ret, tvars: f.tvars}}
        end)
    }

    funcs = lower_meta(assembled_funcs, decls, targets, interp_ic)

    consts =
      for({:const, c, pub?, doc} <- decls, do: parse_const(c, pub?, doc))
      |> Enum.map(&subst_const(&1, aliases))

    uses = for {:use, u} <- decls, do: parse_use(u)

    %{
      types: types,
      ranges: ranges,
      opaques: opaques,
      structs: structs,
      consts: consts,
      uses: uses,
      funcs: funcs
    }
  end

  # The pre-typecheck metaprogramming pass over this scope's function bodies: pure
  # AST->AST transforms that must run *before* the checker and every emitter —
  # `macro` expansion (ADR-0030) then `comptime` folding (ADR-0046, "compile-time
  # by default"). The transformed `{:block, …}` AST is stored back into each
  # clause's `body`, which all body consumers re-parse transparently
  # (`Pratt.parse_body/1` passes an AST through). Macro expansion is
  # `portable: true` when the enclosing `mod` declares `@targets` (ADR-0058): a
  # template introducing a failable bind is then rejected (ADR-0035). Synthetic
  # funcs (protocol dispatchers/impls) carry no user `macro`/`comptime`, so they
  # are skipped to keep their generated bodies as the emitters produced them.
  defp lower_meta(funcs, decls, targets, ic) do
    env = collect_macros(decls)
    portable? = targets != nil
    # types with an `impl Show for T` (ADR-0069 §6, user `Show`) — a hole of such a
    # type lowers to `show(value)` instead of erroring.
    show_types = MapSet.new(for {"Show", t} <- all_impls(decls), do: t)

    Enum.map(funcs, fn
      %Func{synthetic: true} = f ->
        f

      %Func{clauses: cs, params: ps} = f ->
        %{f | clauses: Enum.map(cs, &meta_clause(&1, env, portable?, ps, show_types, ic))}
    end)
  end

  defp meta_clause(%Clause{body: nil} = c, _env, _p, _params, _show, _ic), do: c

  defp meta_clause(%Clause{body: body} = c, env, portable?, params, show, ic)
       when is_binary(body) do
    ast = Pratt.parse_body(body)
    expanded = if env == %{}, do: ast, else: Rian.Macro.expand(env, ast, portable: portable?)
    folded = Rian.Comptime.fold(expanded)
    # ADR-0069: resolve `\(expr)` interpolation here, where the clause's parameter
    # types AND the scope's function signatures (`ic`) are in scope, so each hole
    # stringifies by its static type — incl. a `${call()}` hole — before the checker
    # and emitters see a plain `<>`/stringify chain.
    out = Rian.Interp.resolve(folded, clause_env(c, params), ic, show)

    # Only swap the source-string body for an AST when a transform actually fired;
    # bodies with no macro/`comptime`/interpolation keep their string form (and the
    # invariant that an untouched clause body is its source text).
    if out == ast, do: c, else: %{c | body: out}
  end

  # name->type for a clause's variable parameters, by zipping its argument
  # patterns against the function signature's typed params (ADR-0069 — gives
  # interpolation the static type of a `\(param)` hole). Non-`var` patterns
  # (literals, ctors) contribute nothing; a pattern-bound field's type is not
  # threaded yet (an interpolation hole over one infers `:unknown` → error).
  defp clause_env(%Clause{pats: pats}, params) do
    pats
    |> Enum.zip(params)
    |> Enum.flat_map(fn
      {{:var, v}, %Param{type: t}} -> [{v, t}]
      _ -> []
    end)
    |> Map.new()
  end

  defp collect_macros(decls) do
    defs =
      for {:macro, raw} <- decls do
        if raw.body == nil, do: raise(Error, "macro `#{raw.name}` has no template body")
        %{name: raw.name, params: macro_param_names(raw.params), template: raw.body}
      end

    Rian.Macro.build_env(defs)
  end

  # A macro parameter is a bare substitution name (the leading identifier of each
  # comma-separated slot); any trailing type annotation is ignored.
  defp macro_param_names(pstr) do
    pstr
    |> split_top(",")
    |> Enum.map(&(&1 |> String.trim() |> String.split() |> List.first()))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # `protocol`/`impl` (ADR-0042 §3) desugar to ordinary raw `def` maps — a
  # guarded dispatcher per protocol method plus one mangled function per impl
  # method — so they flow through `build_func` like any other function. The sum
  # `types` and `structs` in scope let the dispatcher discriminate by runtime
  # tag; coherence is enforced by `Rian.Protocol.expand/4`.
  defp protocol_defs(decls, types, structs, targets) do
    protocols =
      for {:protocol, name, inner, _doc} <- decls, into: %{} do
        {name, for({:def, raw} <- inner, do: raw)}
      end

    impls =
      for {:impl, proto, type, inner, _doc} <- decls do
        {proto, type, for({:def, raw} <- inner, do: raw)}
      end

    if protocols == %{} and impls == [],
      do: [],
      else: Rian.Protocol.expand(protocols, impls, types, structs, targets)
  end

  defp parse_alias(text) do
    case split_once(text, ":=") do
      {name, type} -> {strip_type_params(name), type}
      :none -> raise Error, "alias needs `:=`: #{text}"
    end
  end

  # whole-word substitution of every alias name in a type string (transitive)
  defp subst_type_str(type, aliases) do
    resolved =
      Enum.reduce(aliases, type, fn {name, val}, acc ->
        Regex.replace(~r/\b#{Regex.escape(name)}\b/, acc, val)
      end)

    if resolved == type, do: resolved, else: subst_type_str(resolved, aliases)
  end

  defp subst_func(%Func{params: ps, ret: ret} = f, aliases) do
    params =
      Enum.map(ps, fn %Param{} = p -> %Param{p | type: subst_type_str(p.type, aliases)} end)

    %Func{f | params: params, ret: subst_type_str(ret, aliases)}
  end

  defp subst_type(%Type{variants: vs} = t, aliases) do
    %Type{t | variants: Enum.map(vs, &subst_variant(&1, aliases))}
  end

  defp subst_variant(%Variant{fields: fs} = v, aliases) do
    %Variant{v | fields: subst_fields(fs, aliases)}
  end

  defp subst_struct(%Struct{fields: fs} = s, aliases) do
    %Struct{s | fields: subst_fields(fs, aliases)}
  end

  # `range Name := lo..hi` (ADR-0036): an inclusive ordinal interval over `Int64`
  # or `Char`. Bounds are compile-time constant ordinals (a `Char` bound is its
  # codepoint); both must share the base and satisfy `lo <= hi`.
  defp parse_range(text, pub?, doc) do
    case split_once(text, ":=") do
      {left, right} ->
        {lo, hi, base} = parse_bounds(String.trim(right))
        %Range{name: strip_type_params(left), base: base, lo: lo, hi: hi, pub?: pub?, doc: doc}

      :none ->
        raise Error, "range declaration needs `:=`: #{text}"
    end
  end

  # `opaque Name := Base` (ADR-0067 / ADR-0043): an abstract type, nominally
  # distinct from `Base` in the checker but erased to `Base` at emit. Unlike a
  # `range`, it is *not* substituted out of type positions here (that is what makes
  # it nominal); `Rian.Opaque.erase/1` performs the substitution after the gates.
  defp parse_opaque(text, pub?, doc) do
    case split_once(text, ":=") do
      {left, right} ->
        %Opaque{
          name: strip_type_params(left),
          base: collapse_parens(String.trim(right)),
          pub?: pub?,
          doc: doc
        }

      :none ->
        raise Error, "opaque declaration needs `:=`: #{text}"
    end
  end

  # `abstract Name := Base do … end` (ADR-0067): an `opaque` (same nominal,
  # zero-cost erasure) carrying declared `op` operator rules and `to` casts. The
  # operators forward to the base operator on the underlying representation, so
  # erasure needs only the type substitution `Rian.Opaque.erase/1` already does.
  defp parse_abstract(head, body_toks, pub?, doc) do
    {name, base} =
      case split_once(head, ":=") do
        {l, r} -> {strip_type_params(l), collapse_parens(String.trim(r))}
        :none -> raise Error, "abstract declaration needs `:=`: #{head}"
      end

    {ops, casts} = parse_abstract_members(body_toks)
    %Opaque{name: name, base: base, pub?: pub?, doc: doc, ops: ops, casts: casts}
  end

  # Split the `do … end` token body into `op` rules and `to` casts, one per line.
  defp parse_abstract_members(toks) do
    toks
    |> Enum.chunk_by(&match?({:nl}, &1))
    |> Enum.reject(fn [h | _] -> match?({:nl}, h) end)
    |> Enum.map(&String.trim(Lexer.detokenize(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], []}, fn line, {ops, casts} ->
      cond do
        String.starts_with?(line, "op ") -> {ops ++ [parse_op_rule(line)], casts}
        String.starts_with?(line, "to ") -> {ops, casts ++ [parse_cast_rule(line)]}
        true -> raise Error, "unexpected `abstract` member (need `op`/`to`): #{line}"
      end
    end)
  end

  # `op +(a T, b T) Ret` -> %{op: "+", params: ["T", "T"], ret: "Ret"}.
  defp parse_op_rule("op " <> rest) do
    case Regex.run(~r/^(\S+?)\s*\((.*)\)\s*(.*)$/, String.trim(rest)) do
      [_, op_sym, params, ret] ->
        %{op: op_sym, params: Enum.map(parse_params(params), & &1.type), ret: String.trim(ret)}

      _ ->
        raise Error, "malformed `op` in abstract: op #{rest}"
    end
  end

  # `to base() Type` -> %{name: "base", ret: "Type"} (ADR-0067 §2 explicit cast).
  defp parse_cast_rule("to " <> rest) do
    case Regex.run(~r/^(\w+)\s*\(\s*\)\s*(.*)$/, String.trim(rest)) do
      [_, cast_name, ret] -> %{name: cast_name, ret: String.trim(ret)}
      _ -> raise Error, "malformed `to` cast in abstract: to #{rest}"
    end
  end

  defp take_until_do([{:kw, "do"} | _] = rest, acc), do: {Enum.reverse(acc), rest}
  defp take_until_do([t | rest], acc), do: take_until_do(rest, [t | acc])
  defp take_until_do([], _acc), do: raise(Error, "`abstract` needs a `do … end` block")

  defp parse_bounds(text) do
    case String.split(text, "..", parts: 2) do
      [lo_s, hi_s] ->
        {lo, lk} = parse_ordinal(String.trim(lo_s))
        {hi, hk} = parse_ordinal(String.trim(hi_s))

        if lk != hk,
          do: raise(Error, "range bounds must share a base (both Int64 or both Char): #{text}")

        if lo > hi, do: raise(Error, "empty/inverted range (need lo <= hi): #{text}")
        {lo, hi, if(lk == :char, do: "Char", else: "Int64")}

      _ ->
        raise Error, "range needs `lo..hi`: #{text}"
    end
  end

  # an ordinal bound: a `Char` literal -> {codepoint, :char}; else an integer
  defp parse_ordinal("'" <> _ = s) do
    case Lexer.expr_tokens(s) do
      [{:char, cp}] -> {cp, :char}
      _ -> raise Error, "invalid Char bound: #{s}"
    end
  end

  defp parse_ordinal(s), do: {s |> String.replace(" ", "") |> String.to_integer(), :int}

  defp subst_fields(fs, aliases) do
    Enum.map(fs, fn %Field{} = fl -> %Field{fl | type: subst_type_str(fl.type, aliases)} end)
  end

  @doc """
  Parse and lower to both targets: `[{name, %{elixir, rust}}]`. Top-level
  functions lower one entry each; a `mod` lowers to one entry (its module text)
  keyed by the module name.
  """
  @spec compile(String.t()) :: [{String.t(), term()}]
  def compile(src) do
    prog = parse(src)
    :ok = Check.gate!(prog)
    :ok = Rian.Reach.gate!(prog)

    # Erase abstract types to their base *after* the gates checked them nominally
    # (ADR-0067): every emitter below sees `String`, never `opaque Token`.
    %{types: types, ranges: ranges, structs: structs, funcs: funcs, mods: mods} =
      prog = Rian.Opaque.erase(prog)

    # protocol-method -> trait name, for the Rust UFCS call-site rewrite (ADR-0061
    # §2). Threaded into `Lower.compile` so `rust_fn` sees it; sums/impls flow
    # per-target. (`Lower` carries it explicitly in its emitter context, no longer
    # via the process dictionary.)
    proto = proto_method_traits(prog)
    # the program inference context — `Lower` annotates each clause body's typed
    # core IR with it (ADR-0050 §3).
    ic = Check.program_ic(prog)

    funs =
      Enum.map(funcs, fn f ->
        # a protocol's BEAM/JS dispatcher + `impl_*` methods are not the Rust shape
        # (Rust gets traits, ADR-0061 §1/§2) — lower only their Elixir debug view;
        # their guards (`element/2`, `:tag`) are BEAM-only and would crash `to_rust`.
        out =
          if f.dispatch,
            do: Lower.compile_elixir(types, f, structs, ranges, ic),
            else: Lower.compile(types, f, structs, ranges, proto, ic)

        {"#{f.name}/#{length(f.params)}", out}
      end)

    mod_units = Enum.map(mods, fn m -> {m.name, Lower.compile_module(m, ic)} end)
    funs ++ mod_units ++ protocol_unit(prog, types, structs)
  end

  # protocol-method name -> its protocol (trait) name, for UFCS rewriting on Rust.
  defp proto_method_traits(prog) do
    for p <- Map.get(prog, :protocols, []), m <- p.methods, into: %{}, do: {m.name, p.name}
  end

  # the Rust trait+impl block for the program's protocols, as a single unit (no
  # Elixir/BEAM counterpart — those use the runtime dispatcher). Empty when none.
  defp protocol_unit(prog, types, structs) do
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    if protocols == [] and impl_decls == [] do
      []
    else
      rust = Lower.rust_protocols(protocols, impl_decls, types, structs)
      [{"protocols", %{rust: rust}}]
    end
  end

  @doc "Parse and lower to the BEAM target only (FFI / BEAM-only bodies)."
  @spec compile_beam(String.t()) :: [{String.t(), term()}]
  def compile_beam(src) do
    prog = parse(src)
    :ok = Check.gate!(prog)
    :ok = Rian.Reach.gate!(prog)

    %{types: types, ranges: ranges, structs: structs, funcs: funcs, mods: mods} =
      prog = Rian.Opaque.erase(prog)

    ic = Check.program_ic(prog)

    funs =
      Enum.map(funcs, fn f ->
        {"#{f.name}/#{length(f.params)}", Lower.compile_beam(types, f, structs, ranges, ic)}
      end)

    funs ++ Enum.map(mods, fn m -> {m.name, Lower.compile_module_beam(m, ic)} end)
  end

  # ── Tokens -> declarations (recursive descent) ─────────────────────────
  # Parse a flat declaration list, one declaration at a time, until the tokens
  # run out (top level) or the enclosing `mod`'s `end` is reached.
  defp split_decls([]), do: []
  defp split_decls([{:nl} | rest]), do: split_decls(rest)

  defp split_decls(tokens) do
    {decl, rest} = take_decl(tokens)
    [decl | split_decls(rest)]
  end

  # `@doc`/`@moduledoc`/`@typedoc "…"` attaches Markdown to the next declaration
  # (ADR-0051). Any other `@name` annotation is not yet supported.
  defp take_decl([{:annot, a}, {:str, doc} | rest]) when a in ~w(doc moduledoc typedoc) do
    {decl, rest} = take_decl(skip_nl(rest))
    {attach_doc(decl, doc), rest}
  end

  # `@test def name() Bool := …` marks the following `def` as a test (ADR-0057) —
  # a zero-arity `Bool` function the `Rian.Test` runner executes.
  defp take_decl([{:annot, "test"} | rest]) do
    {decl, rest} = take_decl(skip_nl(rest))
    {mark_test(decl), rest}
  end

  # `@targets(ex, rs, js) mod … ` — the module's portability contract (ADR-0058
  # §2): every `pub` function in the module must reach the listed targets.
  defp take_decl([{:annot, "targets"}, {:lparen} | rest]) do
    {tgt_toks, rest} = take_parens(rest, 0, [])
    targets = parse_targets(tgt_toks)
    {decl, rest} = take_decl(skip_nl(rest))
    {attach_targets(decl, targets), rest}
  end

  defp take_decl([{:annot, "targets"} | _]),
    do: raise(Error, "expected `@targets(ex, rs, js)`")

  # `@external(:target, "host expression")` — a target-scoped FFI body (ADR-0068).
  # One or more precede a *bodiless* `def`; the function has no portable Rian body,
  # only per-target host bodies. `Rian.Reach` reads the externals for an honest
  # target set; each emitter lowers the spec for its target.
  defp take_decl([{:annot, "external"}, {:lparen} | rest]) do
    {arg_toks, rest} = take_parens(rest, 0, [])
    {target, spec} = parse_external(arg_toks)
    {decl, rest} = take_decl(skip_nl(rest))
    {attach_external(decl, target, spec), rest}
  end

  defp take_decl([{:annot, "external"} | _]),
    do: raise(Error, ~S|expected `@external(:target, "host expression")`|)

  defp take_decl([{:annot, a} | _]),
    do:
      raise(
        Error,
        "unsupported annotation `@#{a}` (expected `@doc`/`@moduledoc`/`@typedoc \"…\"`)"
      )

  # `pub` exports the declaration that follows it (def / type / struct).
  defp take_decl([{:kw, "pub"} | rest]) do
    {decl, rest} = take_decl(rest)
    {mark_pub(decl), rest}
  end

  defp take_decl([{:kw, "type"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:type, Lexer.detokenize(toks), false, nil}, rest}
  end

  defp take_decl([{:kw, "range"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:range, Lexer.detokenize(toks), false, nil}, rest}
  end

  defp take_decl([{:kw, "opaque"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:opaque, Lexer.detokenize(toks), false, nil}, rest}
  end

  # `abstract Name := Base do op …(…) Ret … ; to base() Type end` (ADR-0067):
  # `opaque` plus an operator/cast surface. The header (`Name := Base`) parses
  # like `opaque`; the `do … end` block holds `op`/`to` members.
  defp take_decl([{:kw, "abstract"} | rest]) do
    {head, rest} = take_until_do(rest, [])
    [{:kw, "do"} | inner] = rest
    {body, rest} = take_block(inner, 1, [])
    {{:abstract, Lexer.detokenize(head), body, false, nil}, rest}
  end

  defp take_decl([{:kw, "struct"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:struct, Lexer.detokenize(toks), false, nil}, rest}
  end

  defp take_decl([{:kw, "alias"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:alias, Lexer.detokenize(toks)}, rest}
  end

  defp take_decl([{:kw, "const"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:const, Lexer.detokenize(toks), false, nil}, rest}
  end

  defp take_decl([{:kw, "use"} | rest]) do
    {toks, rest} = take_type(rest, [])
    {{:use, Lexer.detokenize(toks)}, rest}
  end

  defp take_decl([{:kw, "def"} | rest]) do
    {raw, rest} = take_def(rest)
    {{:def, raw}, rest}
  end

  # `macro name(p, …) := template` (or a `do … end` block body) — a declarative,
  # hygienic AST->AST macro (ADR-0030). Reuses the `def` head/body grammar; the
  # body is the template, the params are bare substitution names. Macros emit no
  # IR — they are expanded into call sites in `assemble/3` before the checker.
  defp take_decl([{:kw, "macro"} | rest]) do
    {raw, rest} = take_def(rest)
    {{:macro, raw}, rest}
  end

  # `mod Name do <declarations> end` — parse the body declaration-by-declaration
  # (a `do`/`end` depth count cannot be used: function block bodies close with a
  # bare `end` that has no matching `do`).
  defp take_decl([{:kw, "mod"}, {:id, name}, {:kw, "do"} | rest]) do
    {inner, rest} = take_mod_body(rest, [])
    {{:mod, name, inner, nil, nil}, rest}
  end

  defp take_decl([{:kw, "mod"} | _]),
    do: raise(Error, "expected `mod Name do … end`")

  # `protocol Name do <def heads> end` (ADR-0042 §3) — method signatures, no
  # bodies; reuses the `mod` body collector (each line is a bodiless `def`).
  defp take_decl([{:kw, "protocol"}, {:id, name}, {:kw, "do"} | rest]) do
    {inner, rest} = take_mod_body(rest, [])
    {{:protocol, name, inner, nil}, rest}
  end

  defp take_decl([{:kw, "protocol"} | _]),
    do: raise(Error, "expected `protocol Name do … end`")

  # `impl Protocol for Type do <defs> end` (ADR-0042 §3). `for` is the keyword token
  # `{:kw, "for"}` here (shared with the comprehension, ADR-0079) — declaration
  # position disambiguates it from an expression `for`.
  defp take_decl([{:kw, "impl"}, {:id, proto}, {:kw, "for"}, {:id, type}, {:kw, "do"} | rest]) do
    {inner, rest} = take_mod_body(rest, [])
    {{:impl, proto, type, inner, nil}, rest}
  end

  defp take_decl([{:kw, "impl"} | _]),
    do: raise(Error, "expected `impl Protocol for Type do … end`")

  defp take_decl([{:kw, kw} | _]),
    do:
      raise(
        Error,
        "unsupported declaration `#{kw}` (supported: `mod` / `type` / `struct` / `def` / `alias`, optionally `pub`)"
      )

  defp take_decl([tok | _]), do: raise(Error, "expected a declaration, got #{inspect(tok)}")

  defp take_mod_body([{:nl} | rest], acc), do: take_mod_body(rest, acc)
  defp take_mod_body([{:kw, "end"} | rest], acc), do: {Enum.reverse(acc), rest}
  defp take_mod_body([], _acc), do: raise(Error, "`mod` body not closed by `end`")

  defp take_mod_body(tokens, acc) do
    {decl, rest} = take_decl(tokens)
    take_mod_body(rest, [decl | acc])
  end

  defp mark_pub({:type, s, _, doc}), do: {:type, s, true, doc}
  defp mark_pub({:range, s, _, doc}), do: {:range, s, true, doc}
  defp mark_pub({:opaque, s, _, doc}), do: {:opaque, s, true, doc}
  defp mark_pub({:abstract, h, b, _, doc}), do: {:abstract, h, b, true, doc}
  defp mark_pub({:struct, s, _, doc}), do: {:struct, s, true, doc}
  defp mark_pub({:const, s, _, doc}), do: {:const, s, true, doc}
  defp mark_pub({:def, raw}), do: {:def, Map.put(raw, :pub, true)}

  defp mark_pub(_other),
    do: raise(Error, "`pub` may only precede `def` / `type` / `struct` / `const`")

  defp mark_test({:def, raw}), do: {:def, Map.put(raw, :test, true)}
  defp mark_test(_other), do: raise(Error, "`@test` may only precede a `def`")

  defp attach_targets({:mod, n, inner, doc, _}, targets), do: {:mod, n, inner, doc, targets}
  defp attach_targets(_other, _t), do: raise(Error, "`@targets(…)` may only precede a `mod`")

  # `@targets(ex, rs, js)` token list -> a deduped list of target atoms, each
  # validated against the closed target vocabulary (ADR-0058 §1).
  defp parse_targets(toks) do
    targets =
      for {:id, t} <- toks do
        atom = String.to_atom(t)

        unless atom in Rian.Reach.targets() do
          raise(
            Error,
            "unknown target `#{t}` in `@targets`; known: #{inspect(Rian.Reach.targets())}"
          )
        end

        atom
      end

    if targets == [],
      do: raise(Error, "`@targets(…)` needs at least one target"),
      else: Enum.uniq(targets)
  end

  # `@external(:target, "spec")` args -> `{target_atom, spec_string}` (ADR-0068).
  # The target is validated against the closed vocabulary; the spec is a raw
  # host-expression string the matching emitter lowers (FFI is trusted, not parsed).
  defp parse_external([{:op, ":"}, {:id, t}, {:comma}, {:str, spec}]) do
    atom = String.to_atom(t)

    unless atom in Rian.Reach.targets() do
      raise(
        Error,
        "unknown target `:#{t}` in `@external`; known: #{inspect(Rian.Reach.targets())}"
      )
    end

    {atom, spec}
  end

  defp parse_external(_other),
    do: raise(Error, ~S|`@external` takes a target atom and a string: `@external(:js, "expr")`|)

  # attach one `@external(:target, spec)` to the bodiless `def` that follows. An
  # `@external` function must have NO portable body for that target (ADR-0068 §1),
  # and no two `@external`s may name the same target.
  defp attach_external({:def, %{body: body} = raw}, target, spec) do
    if not is_nil(body) do
      raise(Error, "`#{raw.name}`: `@external(:#{target}, …)` cannot accompany a portable body")
    end

    if Map.has_key?(raw.externals, target) do
      raise(Error, "`#{raw.name}`: duplicate `@external(:#{target}, …)`")
    end

    {:def, %{raw | externals: Map.put(raw.externals, target, spec)}}
  end

  defp attach_external(_other, _target, _spec),
    do: raise(Error, "`@external(…)` may only precede a `def`")

  # attach a doc string to the declaration that follows the `@doc`/… annotation
  defp attach_doc({:type, s, pub, _}, doc), do: {:type, s, pub, doc}
  defp attach_doc({:range, s, pub, _}, doc), do: {:range, s, pub, doc}
  defp attach_doc({:struct, s, pub, _}, doc), do: {:struct, s, pub, doc}
  defp attach_doc({:const, s, pub, _}, doc), do: {:const, s, pub, doc}
  defp attach_doc({:mod, n, inner, _, t}, doc), do: {:mod, n, inner, doc, t}
  defp attach_doc({:def, raw}, doc), do: {:def, Map.put(raw, :doc, doc)}
  defp attach_doc(other, _doc), do: other

  defp skip_nl([{:nl} | rest]), do: skip_nl(rest)
  defp skip_nl(tokens), do: tokens

  # A `type` runs to the newline that begins the next declaration (variant lines
  # beginning with `|` are continuations) or the enclosing module's `end`.
  defp take_type([], acc), do: {Enum.reverse(acc), []}

  defp take_type([{:nl} | rest], acc) do
    if rest == [] or decl_boundary?(rest),
      do: {Enum.reverse(acc), rest},
      else: take_type(rest, acc)
  end

  defp take_type([t | rest], acc), do: take_type(rest, [t | acc])

  # A declaration ends where the next one begins, or at the enclosing `mod`'s `end`.
  defp decl_boundary?([{:kw, "end"} | _]), do: true
  defp decl_boundary?([{:annot, _} | _]), do: true
  defp decl_boundary?(toks), do: decl_kw?(toks)

  defp decl_kw?([{:kw, k} | _]),
    do:
      k in ~w(type def struct alias mod pub const macro use import protocol impl opaque abstract)

  defp decl_kw?(_), do: false

  # `def name(params) <head>` then a body: `:= expr` (to newline), a block
  # (`<nl> stmts end`), or nothing (a bodiless signature).
  defp take_def([{:id, name} | rest]) do
    {param_toks, rest} = balanced_parens(rest)
    take_head(name, Lexer.detokenize(param_toks), rest, [])
  end

  defp take_def(other),
    do: raise(Error, "expected a function name after `def`: #{inspect(other)}")

  defp take_head(name, params, [{:op, ":="} | rest], head) do
    {body_toks, rest} = take_line(rest, [])
    {def_raw(name, params, head, Lexer.detokenize(body_toks)), rest}
  end

  defp take_head(name, params, [{:nl} | rest], head) do
    if rest == [] or decl_boundary?(rest) do
      {def_raw(name, params, head, nil), rest}
    else
      {block_toks, rest} = take_block(rest, 1, [])
      {def_raw(name, params, head, detok_block(block_toks)), rest}
    end
  end

  defp take_head(name, params, [], head), do: {def_raw(name, params, head, nil), []}
  defp take_head(name, params, [t | rest], head), do: take_head(name, params, rest, [t | head])

  defp def_raw(name, params, head_rev, body) do
    {head, tvars, bounds} = split_forall(Lexer.detokenize(Enum.reverse(head_rev)))
    {ret, guard} = parse_head(head)
    # normalize parenthesized type spacing (`Vec ( Int64 )` -> `Vec(Int64)`) so the
    # declared return type matches inferred parametric types (ADR-0042 checking)
    ret =
      case ret do
        nil -> nil
        r -> collapse_parens(r)
      end

    %{
      name: name,
      params: params,
      ret: ret,
      guard: guard,
      body: body,
      pub: false,
      tvars: tvars,
      bounds: bounds,
      externals: %{}
    }
  end

  # `Ret forall T, U: Bound + Other` — split off the `forall` binder list
  # (ADR-0042). Returns `{ret, tvar_names, %{tvar => [protocol_bounds]}}`; a tvar
  # with no `:` bound is absent from the bounds map (it has no constraints).
  defp split_forall(head) do
    case String.split(head, " forall ", parts: 2) do
      [ret] ->
        {ret, [], %{}}

      [ret, binders] ->
        parsed = parse_binders(binders)
        bounds = for {n, bs} <- parsed, bs != [], into: %{}, do: {n, bs}
        {ret, Enum.map(parsed, &elem(&1, 0)), bounds}
    end
  end

  # one `forall` binder `T` or `T: Eq + Ord` -> `{tvar, [protocols]}`
  defp parse_binders(binders) do
    binders
    |> split_top(",")
    |> Enum.map(&parse_binder/1)
    |> Enum.reject(fn {n, _} -> n == "" end)
  end

  defp parse_binder(b) do
    case String.split(b, ":", parts: 2) do
      [name] ->
        {String.trim(name), []}

      [name, bounds] ->
        protos =
          bounds |> String.split("+") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

        {String.trim(name), protos}
    end
  end

  # Binary operators that continue a `:=` body across a newline when they trail the
  # current line or lead the next (P1: newline-tolerant bodies).
  @cont_ops ~w(+ - * / < > <= >= == != <> |> and or in rem div)

  # Collect a `:=` body. A newline ends it (the one-line default), EXCEPT when the
  # body plainly continues: inside unbalanced `(`/`[`/`{`/`%{`, after a trailing
  # binary operator, before a leading one, or when the body simply starts on the
  # next line — so a `:=` expression may now span multiple lines (P1).
  defp take_line(tokens, acc), do: take_line(tokens, acc, 0)

  defp take_line([], acc, _depth), do: {Enum.reverse(acc), []}

  # leading newline(s): the body may begin on the next line — skip them, unless the
  # next token starts a new declaration (then the body is empty).
  defp take_line([{:nl} | rest], [], depth) do
    if decl_boundary?(rest), do: {[], rest}, else: take_line(rest, [], depth)
  end

  defp take_line([{open} = t | rest], acc, depth)
       when open in [:lparen, :lbracket, :lbrace, :mapopen, :bitopen],
       do: take_line(rest, [t | acc], depth + 1)

  defp take_line([{close} = t | rest], acc, depth)
       when close in [:rparen, :rbracket, :rbrace, :bitclose],
       do: take_line(rest, [t | acc], max(depth - 1, 0))

  # a `do … end` block inside a `:=` body (a multi-line `case`/`if`/`with`) deepens
  # like a bracket, so its arm/branch newlines continue the body to the matching
  # `end` instead of leaking each line as a bogus declaration (P1).
  defp take_line([{:kw, "do"} = t | rest], acc, depth),
    do: take_line(rest, [t | acc], depth + 1)

  defp take_line([{:kw, "end"} = t | rest], acc, depth),
    do: take_line(rest, [t | acc], max(depth - 1, 0))

  defp take_line([{:nl} | rest], acc, depth) do
    if depth > 0 or line_continues?(acc, rest),
      do: take_line(rest, acc, depth),
      else: {Enum.reverse(acc), rest}
  end

  defp take_line([t | rest], acc, depth), do: take_line(rest, [t | acc], depth)

  defp line_continues?([{:op, o} | _], _rest) when o in @cont_ops, do: true
  defp line_continues?(_acc, [{:op, o} | _]) when o in @cont_ops, do: true
  defp line_continues?(_acc, _rest), do: false

  # Collect a block body up to the `end` that closes it; `do` (from nested
  # `if`/`case`) deepens, `end` un-deepens, depth 1's `end` closes the body.
  defp take_block([{:kw, "do"} = t | rest], depth, acc),
    do: take_block(rest, depth + 1, [t | acc])

  defp take_block([{:kw, "end"} | rest], 1, acc), do: {Enum.reverse(acc), rest}

  defp take_block([{:kw, "end"} = t | rest], depth, acc),
    do: take_block(rest, depth - 1, [t | acc])

  defp take_block([t | rest], depth, acc), do: take_block(rest, depth, [t | acc])
  defp take_block([], _depth, _acc), do: raise(Error, "block body not closed by `end`")

  defp balanced_parens([{:lparen} | rest]), do: take_parens(rest, 0, [])

  defp balanced_parens(other),
    do: raise(Error, "expected `(` after the function name: #{inspect(other)}")

  defp take_parens([{:rparen} | rest], 0, acc), do: {Enum.reverse(acc), rest}
  defp take_parens([{:lparen} = t | rest], d, acc), do: take_parens(rest, d + 1, [t | acc])
  defp take_parens([{:rparen} = t | rest], d, acc), do: take_parens(rest, d - 1, [t | acc])
  defp take_parens([t | rest], d, acc), do: take_parens(rest, d, [t | acc])
  defp take_parens([], _, _), do: raise(Error, "unbalanced `(` in the parameter list")

  # Detokenize a block body: a newline at block level separates statements (`;`);
  # a newline inside a nested `do … end` (a `case`/`if`), a `with`-header, OR
  # unbalanced `(`/`[`/`{`/`%{` is insignificant (those self-delimit or continue),
  # so it becomes whitespace. The paren depth `p` keeps a multi-line expression —
  # `Em(s: …,\n pr: …)`, a wrapped call/list/map — from taking a spurious `;`
  # (symmetric with the `:=`-body `take_line` newline-tolerance).
  defp detok_block(tokens), do: tokens |> block_seps(0, 0, 0, []) |> Lexer.detokenize()

  # `d` = `do`/`end` depth, `w` = open `with`-headers (between `with` and its `do`,
  # newlines separate comma-joined clauses, not statements), `p` = bracket depth.
  defp block_seps([], _d, _w, _p, acc), do: Enum.reverse(acc)

  defp block_seps([{:kw, "with"} = t | r], d, w, p, acc),
    do: block_seps(r, d, w + 1, p, [t | acc])

  defp block_seps([{:kw, "do"} = t | r], d, w, p, acc) when w > 0,
    do: block_seps(r, d + 1, w - 1, p, [t | acc])

  defp block_seps([{:kw, "do"} = t | r], d, w, p, acc), do: block_seps(r, d + 1, w, p, [t | acc])
  defp block_seps([{:kw, "end"} = t | r], d, w, p, acc), do: block_seps(r, d - 1, w, p, [t | acc])

  defp block_seps([{open} = t | r], d, w, p, acc)
       when open in [:lparen, :lbracket, :lbrace, :mapopen, :bitopen],
       do: block_seps(r, d, w, p + 1, [t | acc])

  defp block_seps([{close} = t | r], d, w, p, acc)
       when close in [:rparen, :rbracket, :rbrace, :bitclose],
       do: block_seps(r, d, w, max(p - 1, 0), [t | acc])

  defp block_seps([{:nl} | r], 0, 0, 0, acc), do: block_seps(r, 0, 0, 0, [{:semi} | acc])
  defp block_seps([{:nl} | r], d, w, p, acc), do: block_seps(r, d, w, p, acc)
  defp block_seps([t | r], d, w, p, acc), do: block_seps(r, d, w, p, [t | acc])

  # ── `type` declarations ────────────────────────────────────────────────
  defp parse_type(rest, pub?, doc) do
    case split_once(rest, ":=") do
      {left, right} ->
        %Type{
          name: strip_type_params(left),
          variants: right |> split_top("|") |> Enum.map(&variant/1),
          pub?: pub?,
          doc: doc
        }

      :none ->
        raise Error, "type declaration needs `:=`: #{rest}"
    end
  end

  defp strip_type_params(name), do: name |> String.split("(", parts: 2) |> hd() |> String.trim()

  # ── `struct` declarations ──────────────────────────────────────────────
  # `struct Name(field Type, …)` — a product type: one constructor named after
  # the type, with labeled fields (a bare `struct Name` is a zero-field record).
  defp parse_struct(text, pub?, doc) do
    case extract_parens(text) do
      {name, inside, ""} ->
        %Struct{name: String.trim(name), fields: fields(inside), pub?: pub?, doc: doc}

      {_, _, rest} ->
        raise Error, "trailing tokens after struct `#{text}`: #{rest}"

      :none ->
        %Struct{name: String.trim(text), fields: [], pub?: pub?, doc: doc}
    end
  end

  # ── `const` declarations ───────────────────────────────────────────────
  # `const NAME Type := value` — a named compile-time constant (juxtaposed type,
  # like a parameter without a capability).
  defp parse_const(text, pub?, doc) do
    case split_once(text, ":=") do
      {decl, value} ->
        # The type is optional (`const NAME := value`): when omitted it is inferred
        # from the value's literal shape, like Crystal. `nil` means "infer".
        case decl |> collapse_parens() |> String.split(~r/\s+/, trim: true) do
          [name, type] ->
            %Const{name: name, type: type, value: value, pub?: pub?, doc: doc}

          [name] ->
            %Const{name: name, type: infer_const_type(value), value: value, pub?: pub?, doc: doc}

          _ ->
            raise Error, "const needs `NAME [Type] := value`: #{text}"
        end

      :none ->
        raise Error, "const needs `:=`: #{text}"
    end
  end

  # Infer a const's type from its literal value (the value is always a literal,
  # ADR-0009/IR.Const). Returns a type string, or `nil` when the shape is not a
  # recognized literal — downstream then treats the type as unknown.
  defp infer_const_type(value) do
    case Pratt.parse_body(value) do
      {:block, [expr: node]} -> literal_type(node)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp literal_type({:num, n}), do: if(String.contains?(n, "."), do: "Float64", else: "Int53")
  defp literal_type({:str, _}), do: "String"
  defp literal_type({:istr, _}), do: "String"
  defp literal_type({:atom, _}), do: "Symbol"
  defp literal_type({:id, b}) when b in ~w(true false), do: "Bool"

  defp literal_type({:list_lit, [e | _], _}),
    do: with(t when is_binary(t) <- literal_type(e), do: "Vec(#{t})")

  defp literal_type(_), do: nil

  defp subst_const(%Const{type: t} = c, aliases), do: %Const{c | type: subst_type_str(t, aliases)}

  # ── `use` imports ──────────────────────────────────────────────────────
  # `use Path` (qualified) or `use Path.(name, …)` (selective). Detokenized
  # strings space their dots/parens; normalize both before splitting.
  defp parse_use(text) do
    s = text |> collapse_parens() |> String.replace(~r/\s*\.\s*/, ".")

    case extract_parens(s) do
      {path, inside, ""} ->
        names = inside |> split_top(",")
        %Use{path: String.trim_trailing(path, "."), names: names}

      {_, _, rest} ->
        raise Error, "trailing tokens after use `#{text}`: #{rest}"

      :none ->
        %Use{path: s, names: []}
    end
  end

  # Detokenized type strings space their parens/commas (`Vec ( Int64 )`); collapse
  # them back so a parenthesized type is one whitespace-split token (`Vec(Int64)`).
  defp collapse_parens(s), do: Regex.replace(~r/\s*([(),])\s*/, s, "\\1")

  defp variant(v) do
    case extract_parens(v) do
      {ctor, inside, ""} -> %Variant{ctor: String.trim(ctor), fields: fields(inside)}
      {_, _, rest} -> raise Error, "trailing tokens after variant `#{v}`: #{rest}"
      :none -> %Variant{ctor: String.trim(v), fields: []}
    end
  end

  defp fields(inside) do
    case String.trim(inside) do
      "" -> []
      s -> s |> split_top(",") |> Enum.map(&field/1)
    end
  end

  defp field(f) do
    case f
         |> collapse_parens()
         |> String.split(~r/\s+/, trim: true)
         |> Enum.reject(&(&1 in @caps)) do
      [type] -> %Field{type: type}
      [label, type] -> %Field{label: label, type: type}
      _ -> raise Error, "bad field `#{f}`"
    end
  end

  # ── `def` raw maps -> grouped functions ────────────────────────────────
  defp parse_head(head) do
    cond do
      head == "" ->
        {nil, nil}

      String.starts_with?(head, "when ") ->
        {nil, String.trim_leading(head, "when ")}

      String.contains?(head, " when ") ->
        head |> split2(" when ") |> then(fn {r, g} -> {nz(r), g} end)

      true ->
        {nz(head), nil}
    end
  end

  # multi-clause: bodiless signature followed by >=1 pattern clauses. `pub` (if
  # any) sits on the signature; the clause defs that follow are not re-marked.
  @spec build_func([map()]) :: map()
  # arity for grouping — a top-level-comma count at the TOKEN level, so a char/string
  # literal (a single token) never contributes a stray comma (`[',' | rest]`) and all
  # bracket kinds nest. A signature's type params and its clauses' patterns yield the
  # same count, so a sig stays grouped with its clauses; different arities split.
  defp raw_arity(%{params: p}) do
    params_str =
      case p do
        nil -> ""
        v -> v
      end

    count_params(to_string(params_str))
  end

  defp count_params(p) do
    case String.trim(p) do
      "" ->
        0

      s ->
        {commas, _depth} =
          s
          |> Lexer.expr_tokens()
          |> Enum.reduce({0, 0}, fn
            {:comma}, {c, 0} ->
              {c + 1, 0}

            t, {c, d} when t in [{:lparen}, {:lbracket}, {:lbrace}, {:mapopen}, {:bitopen}] ->
              {c, d + 1}

            t, {c, d} when t in [{:rparen}, {:rbracket}, {:rbrace}, {:bitclose}] ->
              {c, d - 1}

            _t, acc ->
              acc
          end)

        commas + 1
    end
  end

  def build_func([%{body: nil} = sig | [_ | _] = clauses]) do
    params = parse_params(sig.params)
    params = if sig[:pub] == true, do: boundary_params(params), else: params

    %Func{
      name: sig.name,
      params: params,
      ret: req_ret(sig),
      clauses: Enum.map(clauses, &clause(&1, length(params))),
      pub?: sig[:pub] == true,
      tvars: Map.get(sig, :tvars, []),
      bounds: Map.get(sig, :bounds, %{}),
      doc: sig[:doc],
      synthetic: sig[:synthetic] == true,
      test?: sig[:test] == true,
      dispatch: sig[:dispatch]
    }
  end

  # single typed clause — each parameter binds itself as the clause pattern
  def build_func([%{body: body} = d]) when not is_nil(body) do
    params = parse_params(d.params)
    params = if d[:pub] == true, do: boundary_params(params), else: params

    %Func{
      name: d.name,
      params: params,
      ret: req_ret(d),
      clauses: [%Clause{pats: Enum.map(params, &{:var, &1.name}), body: body, guard: d.guard}],
      pub?: d[:pub] == true,
      tvars: Map.get(d, :tvars, []),
      bounds: Map.get(d, :bounds, %{}),
      doc: d[:doc],
      synthetic: d[:synthetic] == true,
      test?: d[:test] == true,
      dispatch: d[:dispatch]
    }
  end

  # an `@external` function (ADR-0068): a bodiless signature with one or more
  # per-target host bodies and NO portable clauses. The signature is checked once;
  # `Rian.Reach` reads `externals` for the target set; each emitter lowers its spec.
  def build_func([%{body: nil, externals: ext} = sig]) when map_size(ext) > 0 do
    params = boundary_params(parse_params(sig.params))

    %Func{
      name: sig.name,
      params: params,
      ret: req_ret(sig),
      clauses: [],
      externals: ext,
      pub?: sig[:pub] == true,
      tvars: Map.get(sig, :tvars, []),
      bounds: Map.get(sig, :bounds, %{}),
      doc: sig[:doc]
    }
  end

  def build_func([%{body: nil, name: n}]),
    do: raise(Error, "function `#{n}` has a signature but no clauses")

  def build_func(group),
    do: raise(Error, "cannot group clauses of `#{hd(group).name}`")

  defp clause(%{body: nil, name: n}, _arity), do: raise(Error, "clause of `#{n}` has no body")

  defp clause(%{params: pstr, body: body, guard: guard}, arity) do
    # one parser (ADR-0050 §2): clause-head patterns are parsed by the same
    # `Rian.Pratt` token parser the `case` arms use — no separate string parser.
    pats = Pratt.parse_pats(pstr)

    if length(pats) != arity do
      raise Error, "clause has #{length(pats)} patterns but the signature has arity #{arity}"
    end

    %Clause{pats: pats, body: body, guard: guard}
  end

  defp parse_params(str) do
    str
    |> split_top(",")
    |> Enum.with_index()
    |> Enum.map(fn {p, i} ->
      {name, cap, type} = param(p)

      %Param{
        name:
          case name do
            nil -> "arg#{i}"
            n -> n
          end,
        type: type,
        cap: cap
      }
    end)
  end

  defp param(p) do
    {caps, rest} =
      p
      |> collapse_parens()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.split_with(&(&1 in @caps))

    cap =
      case caps do
        [] -> :val
        [c] -> String.to_atom(c)
        _ -> raise Error, "multiple capabilities on `#{p}`"
      end

    case rest do
      [tok] -> if type_token?(tok), do: {nil, cap, tok}, else: {tok, cap, :infer}
      [name, type] -> {name, cap, type}
      _ -> raise Error, "bad parameter `#{p}`"
    end
  end

  # A lone parameter token is a TYPE when it looks like one — type names and
  # constructors are PascalCase (`Int53`, `Vec(Int)`, `Shape`), a type variable is
  # an upper-case letter (`T`). A lowercase lone token is a VALUE name whose type is
  # INFERRED (`:infer`, ADR-0034 infer-local params): `def f(x) := x + 1` binds `x`
  # and `Rian.InferLocal` recovers its type. `pub`/`@external` boundaries reject
  # `:infer` (a public boundary must be annotated — see `reject_infer_boundary/3`).
  defp type_token?(<<c::utf8, _::binary>>) when c in ?A..?Z, do: true
  defp type_token?(_), do: false

  # infer-local applies to PRIVATE functions only (ADR-0034). On a `pub`/`@external`
  # boundary a lowercase lone token keeps its legacy *permissive anonymous-typed*
  # reading (the token is the param's type, name synthesized) — backward-compatible
  # with the self-hosted dispatchers (`pub def lower_pat(p) Pat`) that take untyped
  # surface AST with no nominal Rian type. So a boundary param is never `:infer`.
  defp boundary_params(params) do
    params
    |> Enum.with_index()
    |> Enum.map(fn
      {%Param{name: tok, type: :infer} = p, i} -> %{p | name: "arg#{i}", type: tok}
      {p, _i} -> p
    end)
  end

  # declare-public / infer-local (ADR-0034): a `pub` function MUST declare its return
  # type (the explicit boundary); a private function MAY omit it (`ret: nil`) — it is
  # filled by `Rian.InferLocal` after parsing.
  defp req_ret(%{ret: ret}) when not is_nil(ret), do: ret

  defp req_ret(%{ret: nil} = d) do
    if d[:pub] == true,
      do: raise(Error, "public function `#{d[:name]}` needs a return type"),
      else: nil
  end

  # ── string helpers ─────────────────────────────────────────────────────
  defp nz(s), do: if(String.trim(s) == "", do: nil, else: String.trim(s))

  defp split_once(str, sep) do
    case :binary.split(str, sep) do
      [l, r] -> {String.trim(l), String.trim(r)}
      [_] -> :none
    end
  end

  defp split2(str, sep) do
    [l, r] = String.split(str, sep, parts: 2)
    {l, String.trim(r)}
  end

  # split on a single-char separator at bracket-depth 0 (`(…)` and `{…}`); trims,
  # drops empties
  defp split_top(str, sep) do
    {parts, {cur, _}} =
      str
      |> String.graphemes()
      |> Enum.reduce({[], {"", 0}}, fn ch, {parts, {cur, depth}} ->
        cond do
          ch == sep and depth == 0 -> {[cur | parts], {"", 0}}
          ch in ["(", "{", "["] -> {parts, {cur <> ch, depth + 1}}
          ch in [")", "}", "]"] -> {parts, {cur <> ch, depth - 1}}
          true -> {parts, {cur <> ch, depth}}
        end
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # "name(inside)rest" -> {name, inside, rest}; :none if no parens
  defp extract_parens(str) do
    case String.split(str, "(", parts: 2) do
      [_no_paren] ->
        :none

      [name, after_open] ->
        {inside, rest} = match_paren(after_open, 0, "")
        {name, inside, String.trim(rest)}
    end
  end

  defp match_paren("(" <> t, depth, acc), do: match_paren(t, depth + 1, acc <> "(")
  defp match_paren(")" <> t, 0, acc), do: {acc, t}
  defp match_paren(")" <> t, depth, acc), do: match_paren(t, depth - 1, acc <> ")")

  defp match_paren(<<c::utf8, t::binary>>, depth, acc),
    do: match_paren(t, depth, acc <> <<c::utf8>>)

  defp match_paren("", _depth, acc), do: {acc, ""}
end
