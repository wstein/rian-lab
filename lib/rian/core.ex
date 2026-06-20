defmodule Rian.Core do
  @moduledoc """
  The **typed core IR** (ADR-0050) — the single representation that the checker
  and *all* emitters are migrating onto, replacing the loose surface tuples the
  parser produces. Sealed-sum / typed-struct nodes (not tuples) mean one node
  shape, `@enforce_keys`-guaranteed, changed in one place — and, once the
  compiler is self-hosted, exhaustiveness over its *own* IR (ADR-0050 §4).

  Each node carries an optional `type` (the inferred type, ADR-0050 §3 / ADR-0034)
  the emitter reads off for representation choices (ADR-0041/0043/0046); it is
  `nil` until the checker fills it.

  ## Migration status

  The **pattern and expression** node catalogues exist (`from_pat/1`,
  `from_expr/1`), including the resolved construction nodes
  (`EVariant`/`EStruct`/`EConstRef`). **Every expression/pattern consumer now
  reads the core:** the abstract-forms emitter ([`Rian.Beam`](beam.ex)), the
  ECMAScript emitter ([`Rian.JS`](js.ex)), **all of [`Rian.Lower`](lower.ex)**
  (its `emit/2` and both pattern emitters), and the **type checker**
  ([`Rian.Check`](check.ex)) — `infer/3` dispatches on core nodes and
  `annotate/3` fills each node's `type` (§3). One representation, one inference.

  The exhaustiveness normalizer ([`Rian.PatternLower`](pattern_lower.ex)) consumes
  the core too (with a surface shim for back-compat). **Every parser-downstream
  pass now reads one representation.** Remaining (the §3 *payoff*, future work):
  emitters *reading* `node.type` for representation choices (closed-set symbols,
  opaque erasure, monomorphization) rather than recomputing from meta.
  """

  use Rian.Ann

  # ── Rian-surface type schema for the Core IR (ADR-0050) ──────────────────────
  # Harvested by the Elixir→Rian transpiler to fill its `_Unk` holes (ADR-0080 §2
  # type-design track). The two sums classify the nodes; each `struct` annotation types
  # one node's fields. `type` is the inferred type-repr (a type string; `nil` until the
  # checker fills it, per the moduledoc). Genuinely-heterogeneous fields — a literal
  # `value`, a cons `tail`, `case` arms, `with` clauses, block `stmts`, map/struct/
  # bitstring `pairs`/`fields`/`segments`, lambda `params` — stay `_Unk` honestly (no
  # single Rian type; they need their own node types a later pass can model).
  @rian_sig "type Pat := PWild | PVar | PLit | PChar | PAtom | PTuple | PList | PCtor | PAs | PPin | PStruct | PMap | PBitstr | PTyped"
  @rian_sig "type Expr := ENum | EStr | EChar | EId | EAtom | EUnary | EBin | ECall | EDot | EIf | ECase | EWith | EBlock | EList | EMap | EMapUpdate | EBitstr | ETuple | ELambda | ECapture | ECaptureNamed | ECapArg | ELabel | EVariant | EStruct | EConstRef"
  @rian_sig "struct PWild(type String)"
  @rian_sig "struct PVar(name String, type String)"
  @rian_sig "struct PLit(value _Unk, type String)"
  @rian_sig "struct PChar(value Int53, type String)"
  @rian_sig "struct PAtom(name String, type String)"
  @rian_sig "struct PTuple(elems Vec(Pat), type String)"
  @rian_sig "struct PList(elems Vec(Pat), tail _Unk, type String)"
  @rian_sig "struct PCtor(ctor String, args Vec(Pat), type String)"
  @rian_sig "struct PAs(name String, pat Pat, type String)"
  @rian_sig "struct PPin(expr Expr, type String)"
  @rian_sig "struct PStruct(name String, fields _Unk, type String)"
  @rian_sig "struct PMap(pairs _Unk, type String)"
  @rian_sig "struct PBitstr(segments _Unk, type String)"
  @rian_sig "struct PTyped(name String, tname String, type String)"
  @rian_sig "struct ENum(text String, type String)"
  @rian_sig "struct EStr(value String, type String)"
  @rian_sig "struct EChar(value Int53, type String)"
  @rian_sig "struct EId(name String, type String)"
  @rian_sig "struct EAtom(name String, type String)"
  @rian_sig "struct EUnary(op String, arg Expr, type String)"
  @rian_sig "struct EBin(op String, left Expr, right Expr, type String)"
  @rian_sig "struct ECall(fun Expr, args Vec(Expr), type String)"
  @rian_sig "struct EDot(head Expr, name String, type String)"
  @rian_sig "struct EIf(cond Expr, then Expr, else Expr, type String)"
  @rian_sig "struct ECase(scrut Expr, arms _Unk, type String)"
  @rian_sig "struct EWith(clauses _Unk, body Expr, els _Unk, type String)"
  @rian_sig "struct EBlock(stmts _Unk, type String)"
  @rian_sig "struct EList(elems Vec(Expr), tail _Unk, type String)"
  @rian_sig "struct EMap(pairs _Unk, type String)"
  @rian_sig "struct EMapUpdate(base Expr, pairs _Unk, type String)"
  @rian_sig "struct EBitstr(segments _Unk, type String)"
  @rian_sig "struct ETuple(elems Vec(Expr), type String)"
  @rian_sig "struct ELambda(params _Unk, body Expr, type String)"
  @rian_sig "struct ECapture(body Expr, type String)"
  @rian_sig "struct ECaptureNamed(path String, arity Int53, type String)"
  @rian_sig "struct ECapArg(n Int53, type String)"
  @rian_sig "struct ELabel(name String, expr Expr, type String)"
  @rian_sig "struct EVariant(enum String, ctor String, named _Unk, pairs _Unk, type String)"
  @rian_sig "struct EStruct(name String, pairs _Unk, type String)"
  @rian_sig "struct EConstRef(name String, type String)"

  defmodule PWild do
    @moduledoc "`_` — matches anything."
    defstruct type: nil
  end

  defmodule PVar do
    @moduledoc "A variable binding pattern."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule PLit do
    @moduledoc "A literal pattern (integer or string)."
    @enforce_keys [:value]
    defstruct [:value, type: nil]
  end

  defmodule PChar do
    @moduledoc """
    A `Char` literal pattern (ADR-0036), carrying its integer codepoint
    `value`. Matches a codepoint integer on the BEAM/JS and a native `char` on
    Rust; for exhaustiveness it is the same `{:lit, codepoint}` constructor as
    an integer literal.
    """
    @enforce_keys [:value]
    defstruct [:value, type: nil]
  end

  defmodule PAtom do
    @moduledoc "An atom pattern (`:ok`)."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule PTuple do
    @moduledoc "A tuple pattern `{p1, …}`."
    defstruct elems: [], type: nil
  end

  defmodule PList do
    @moduledoc "A list pattern; `tail` is `:close` (`[a, b]`) or a pattern (`[a | t]`)."
    defstruct elems: [], tail: :close, type: nil
  end

  defmodule PCtor do
    @moduledoc "A sum-variant pattern `Ctor(args…)` (nullary when `args == []`)."
    @enforce_keys [:ctor]
    defstruct ctor: nil, args: [], type: nil
  end

  defmodule PAs do
    @moduledoc "An as-pattern `name @ pat` (binds `name` to the whole match)."
    @enforce_keys [:name, :pat]
    defstruct [:name, :pat, type: nil]
  end

  defmodule PTyped do
    @moduledoc """
    A type-pattern `name Type` (ADR-0083) — binds `name`, matching only when the
    scrutinee's runtime type is `tname`. The narrowing form for a value union;
    after a match the binding is narrowed to `tname`.

    `disc` is an OPTIONAL pre-resolved discriminator an emitter may bake in when it
    cannot reach its type registry at the pattern site (the JS emitter does this):
    `{:sum, ctor_tags}` or `{:struct, name}`. `nil` means a primitive discriminator
    the emitter resolves itself.
    """
    @enforce_keys [:name, :tname]
    defstruct [:name, :tname, disc: nil, type: nil]
  end

  defmodule PPin do
    @moduledoc "A pin `^expr` — matches the value of `expr` (refutable)."
    @enforce_keys [:expr]
    defstruct [:expr, type: nil]
  end

  defmodule PStruct do
    @moduledoc "A struct pattern `%Name{field: pat, …}`; `fields` are `{field, pat}`."
    @enforce_keys [:name]
    defstruct [:name, fields: [], type: nil]
  end

  defmodule PMap do
    @moduledoc "A map pattern `%{key => pat, …}`; `pairs` are `{key, pat}` (refutable when non-empty)."
    defstruct pairs: [], type: nil
  end

  defmodule PBitstr do
    @moduledoc """
    A bitstring pattern `<<seg::spec, …>>` (ADR-0078); `segments` are `{value, specs}`
    where `value` is a sub-pattern (binder/literal) and `specs` is the type/size list
    (as in `EBitstr`). Refutable; BEAM-native (off `:rs`/`:js`/`:jvm` via `Rian.Reach`).
    """
    defstruct segments: [], type: nil
  end

  # ── expression nodes ───────────────────────────────────────────────────
  defmodule ENum do
    @moduledoc "A numeric literal (the source text; `Int64` or `Float64` by form)."
    @enforce_keys [:text]
    defstruct [:text, type: nil]
  end

  defmodule EStr do
    @moduledoc "A string literal."
    @enforce_keys [:value]
    defstruct [:value, type: nil]
  end

  defmodule EChar do
    @moduledoc """
    A `Char` literal (ADR-0036), carrying its Unicode `value` (an integer
    codepoint). Lowers to a codepoint integer on the BEAM/JS and a native
    `char` on Rust; typed `Char` by the checker.
    """
    @enforce_keys [:value]
    defstruct [:value, type: nil]
  end

  defmodule EId do
    @moduledoc "A name reference (variable, nullary constructor, or qualifier head)."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule EAtom do
    @moduledoc "An atom literal (`:ok`)."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  defmodule EUnary do
    @moduledoc "A unary operator application."
    @enforce_keys [:op, :arg]
    defstruct [:op, :arg, type: nil]
  end

  defmodule EBin do
    @moduledoc "A binary operator application."
    @enforce_keys [:op, :left, :right]
    defstruct [:op, :left, :right, type: nil]
  end

  defmodule ECall do
    @moduledoc "A call `fun(args…)` (`fun` is an expression — id, dot, …)."
    @enforce_keys [:fun, :args]
    defstruct [:fun, :args, type: nil]
  end

  defmodule EDot do
    @moduledoc "Qualified/field access `head.name`."
    @enforce_keys [:head, :name]
    defstruct [:head, :name, type: nil]
  end

  defmodule EIf do
    @moduledoc "An `if` expression; `then`/`else` are blocks."
    @enforce_keys [:cond, :then, :else]
    defstruct [:cond, :then, :else, type: nil]
  end

  defmodule ECase do
    @moduledoc "A `case`; `arms` are `{pattern, guard | nil, body}` (core nodes)."
    @enforce_keys [:scrut, :arms]
    defstruct [:scrut, :arms, type: nil]
  end

  defmodule EWith do
    @moduledoc "A `with`; `clauses` are `{pattern, expr}`, `els` are case-style arms."
    @enforce_keys [:clauses, :body]
    defstruct [:clauses, :body, els: [], type: nil]
  end

  defmodule EBlock do
    @moduledoc "A statement block; `stmts` are `{:bind, name, expr}` | `{:typed_bind, name, type, expr}` | `{:expr, expr}`."
    defstruct stmts: [], type: nil
  end

  defmodule EList do
    @moduledoc "A list literal; `tail` is `:close` or a cons-tail expression."
    defstruct elems: [], tail: :close, type: nil
  end

  defmodule EMap do
    @moduledoc "A map literal; `pairs` are `{key, expr}`."
    defstruct pairs: [], type: nil
  end

  defmodule EMapUpdate do
    @moduledoc """
    A map update `%{base | k: v, …}` (ADR-0033): the `base` map with each named
    key replaced by a new value. Every updated key must already be present (BEAM
    `:=` exact-assoc / Elixir `%{m | k: v}`). `pairs` are `{key, expr}`.
    """
    @enforce_keys [:base]
    defstruct base: nil, pairs: [], type: nil
  end

  defmodule EBitstr do
    @moduledoc """
    A bitstring `<<seg::spec, …>>` (ADR-0078). `segments` are `{value, specs}` where
    `specs` is a list of `{:type, name} | {:size, n} | {:unit, n}` (empty = default).
    BEAM-native; non-BEAM emitters raise `Unsupported` and `Rian.Reach` pins it off
    `:rs`/`:js`/`:jvm`.
    """
    defstruct segments: [], type: nil
  end

  defmodule ETuple do
    @moduledoc "A tuple literal."
    defstruct elems: [], type: nil
  end

  defmodule ELambda do
    @moduledoc "An anonymous function; `params` are `{name, type | nil}`."
    @enforce_keys [:params, :body]
    defstruct [:params, :body, type: nil]
  end

  defmodule ECapture do
    @moduledoc "An anonymous capture `&(…)` with `&N` placeholders."
    @enforce_keys [:body]
    defstruct [:body, type: nil]
  end

  defmodule ECaptureNamed do
    @moduledoc "A named capture `&path/arity`."
    @enforce_keys [:path, :arity]
    defstruct [:path, :arity, type: nil]
  end

  defmodule ECapArg do
    @moduledoc "A capture placeholder `&N`."
    @enforce_keys [:n]
    defstruct [:n, type: nil]
  end

  defmodule ELabel do
    @moduledoc "A labeled argument `name: expr` (named construction)."
    @enforce_keys [:name, :expr]
    defstruct [:name, :expr, type: nil]
  end

  # ── resolved construction nodes (produced by Rian.Lower's resolution passes) ──
  defmodule EVariant do
    @moduledoc "A resolved sum-variant construction; `pairs` are `{label | nil, value}`."
    @enforce_keys [:enum, :ctor, :named]
    defstruct [:enum, :ctor, :named, pairs: [], type: nil]
  end

  defmodule EStruct do
    @moduledoc "A resolved struct construction `%Name{…}`; `pairs` are `{label, value}`."
    @enforce_keys [:name]
    defstruct [:name, pairs: [], type: nil]
  end

  defmodule EConstRef do
    @moduledoc "A resolved reference to a module constant."
    @enforce_keys [:name]
    defstruct [:name, type: nil]
  end

  @doc "Translate a surface expression (the `Rian.Pratt` tuple AST) into the typed core."
  @rian_sig "pub def from_expr(surface _Unk) Expr"
  @spec from_expr(tuple()) :: struct()
  def from_expr({:num, n}), do: %ENum{text: n}
  def from_expr({:str, s}), do: %EStr{value: s}

  # String interpolation (ADR-0069) is resolved to a `<>`/stringify chain by
  # `Rian.Interp` in the declaration pass, before Core. One reaching here means it
  # appeared somewhere that pass doesn't cover (e.g. a clause guard) — fail clearly.
  def from_expr({:str_interp, _}),
    do:
      raise(
        ArgumentError,
        "string interpolation is not supported here (e.g. in a guard) — ADR-0069"
      )

  def from_expr({:char, cp}), do: %EChar{value: cp}
  def from_expr({:id, x}), do: %EId{name: x}
  def from_expr({:atom, a}), do: %EAtom{name: a}
  def from_expr({:unary, op, x}), do: %EUnary{op: op, arg: from_expr(x)}

  # the pipe `a |> f(b, …)` desugars to a plain call `f(a, b, …)` at the surface→Core
  # boundary, so every Core backend (`Beam`/`JS`/`JVM`) lowers it as an ordinary call —
  # there is no `|>` EBin downstream. A bare callee (`a |> f` / `a |> M.f`) gets `a` as
  # its sole argument.
  def from_expr({:bin, "|>", l, r}), do: from_expr(pipe_into(l, r))

  def from_expr({:bin, op, l, r}), do: %EBin{op: op, left: from_expr(l), right: from_expr(r)}

  def from_expr({:call, f, args}),
    do: %ECall{fun: from_expr(f), args: Enum.map(args, &from_expr/1)}

  def from_expr({:dot, head, name}), do: %EDot{head: from_expr(head), name: name}

  def from_expr({:if, c, t, e}),
    do: %EIf{cond: from_expr(c), then: from_expr(t), else: from_expr(e)}

  def from_expr({:tuple, es}), do: %ETuple{elems: Enum.map(es, &from_expr/1)}

  def from_expr({:map_lit, ps}),
    do: %EMap{pairs: Enum.map(ps, &map_pair/1)}

  def from_expr({:bitstr, segs}),
    do: %EBitstr{segments: Enum.map(segs, fn {:bitseg, v, specs} -> {from_expr(v), specs} end)}

  def from_expr({:map_update, base, ps}),
    do: %EMapUpdate{
      base: from_expr(base),
      pairs: Enum.map(ps, &map_pair/1)
    }

  def from_expr({:cap_arg, n}), do: %ECapArg{n: n}
  def from_expr({:capture, b}), do: %ECapture{body: from_expr(b)}
  def from_expr({:capture_named, p, a}), do: %ECaptureNamed{path: from_expr(p), arity: a}
  def from_expr({:label, n, e}), do: %ELabel{name: n, expr: from_expr(e)}
  def from_expr({:lambda, ps, b}), do: %ELambda{params: ps, body: from_expr(b)}

  # a comprehension `for p <- src, filter, … do body end` (ADR-0079) desugars to
  # nested `List.flat_map`/`if`/`[body]` over the portable prelude (ADR-0047), so it
  # is just ordinary Core nodes downstream — no emitter/checker/exhaustiveness clause.
  def from_expr({:comprehension, clauses, body}),
    do: desugar_for(clauses, body, comp_ids({clauses, body}))

  # resolved construction nodes (Rian.Lower's resolve_* passes produce these)
  def from_expr({:variant_lit, enum, ctor, named, pairs}),
    do: %EVariant{enum: enum, ctor: ctor, named: named, pairs: from_pairs(pairs)}

  def from_expr({:struct_lit, name, pairs}), do: %EStruct{name: name, pairs: from_pairs(pairs)}
  def from_expr({:const_ref, name}), do: %EConstRef{name: name}

  def from_expr({:list_lit, es, tail}),
    do: %EList{elems: Enum.map(es, &from_expr/1), tail: from_tail(tail)}

  def from_expr({:block, stmts}) do
    block_terminal!(stmts)
    %EBlock{stmts: Enum.map(stmts, &from_stmt/1)}
  end

  def from_expr({:case, scrut, arms}),
    do: %ECase{scrut: from_expr(scrut), arms: Enum.map(arms, &from_arm/1)}

  def from_expr({:with, clauses, body, els}) do
    %EWith{
      clauses: Enum.map(clauses, fn {p, e} -> {from_pat(p), from_expr(e)} end),
      body: from_expr(body),
      els: Enum.map(els, &from_arm/1)
    }
  end

  # `a |> f(args)` → `f(a, args)`; `a |> f` / `a |> M.f` → `f(a)` (bare callee).
  defp pipe_into(l, {:call, fun, args}), do: {:call, fun, [l | args]}
  defp pipe_into(l, callee), do: {:call, callee, [l]}

  defp from_tail(nil), do: :close
  defp from_tail(:close), do: :close
  defp from_tail({:tail, e}), do: from_expr(e)

  defp from_pairs(pairs), do: Enum.map(pairs, fn {label, v} -> {label, from_expr(v)} end)

  defp from_stmt({:bind, n, e}), do: {:bind, n, from_expr(e)}
  defp from_stmt({:typed_bind, n, t, e}), do: {:typed_bind, n, t, from_expr(e)}
  defp from_stmt({:expr, e}), do: {:expr, from_expr(e)}

  defp from_arm({pat, guard, body}),
    do: {from_pat(pat), from_guard(guard), from_expr(body)}

  # an arm's optional guard: absent (`nil`) stays absent, else lowers like any expr.
  defp from_guard(nil), do: nil
  defp from_guard(guard), do: from_expr(guard)

  # ADR-0035 (No Hidden Control Flow): a block's value is its **final expression**
  # (ML-family discipline — OCaml/Haskell/F#/Rust all require a trailing expression,
  # never a bare `let`). A block whose last statement is a binding is rejected: it
  # has no portable value. The BEAM would return the bound RHS (Elixir's `=` is an
  # expression), but Rust lowers `let x = e;` to a `()`-typed block — a silent
  # cross-target divergence (`rustc` rejects `().to_string()`). One chokepoint here
  # covers function bodies, `if`/`case`/`with`/lambda arms, and macro-expanded blocks.
  defp block_terminal!(stmts) do
    case List.last(stmts) do
      {:bind, name, _} -> raise_trailing_bind(name)
      {:typed_bind, name, _, _} -> raise_trailing_bind(name)
      _ -> :ok
    end
  end

  @spec raise_trailing_bind(String.t()) :: no_return()
  defp raise_trailing_bind(name) do
    raise ArgumentError,
          "a block body must end in an expression, not the binding `#{name} := …` " <>
            "(ADR-0035): a binding has no portable value. Make the value the final " <>
            "line (e.g. add `#{name}`), or use a `:= expr` one-liner for a single-" <>
            "expression body."
  end

  @doc "Translate a surface pattern (the `Rian.Pratt` tuple AST) into the typed core."
  # `{:rpat, str}` is a pre-rendered Rust pattern baked by `Rian.Lower`'s
  # Rust-only pass (it carries the type meta); pass it through unchanged.
  @rian_sig "pub def from_pat(surface _Unk) Pat"
  @spec from_pat(tuple() | :wild) :: struct() | tuple()
  def from_pat({:rpat, _} = baked), do: baked
  def from_pat(:wild), do: %PWild{}
  def from_pat({:var, name}), do: %PVar{name: name}
  def from_pat({:lit, value}), do: %PLit{value: value}
  def from_pat({:char_lit, cp}), do: %PChar{value: cp}
  def from_pat({:atom, name}), do: %PAtom{name: name}
  def from_pat({:tuple, ps}), do: %PTuple{elems: Enum.map(ps, &from_pat/1)}
  def from_pat({:ctor, ctor, args}), do: %PCtor{ctor: ctor, args: Enum.map(args, &from_pat/1)}
  def from_pat({:list, ps, :close}), do: %PList{elems: Enum.map(ps, &from_pat/1), tail: :close}

  def from_pat({:list, ps, {:tail, t}}),
    do: %PList{elems: Enum.map(ps, &from_pat/1), tail: from_pat(t)}

  def from_pat({:as, name, p}), do: %PAs{name: name, pat: from_pat(p)}
  def from_pat({:typed, name, tname}), do: %PTyped{name: name, tname: tname}
  def from_pat({:typed, name, tname, disc}), do: %PTyped{name: name, tname: tname, disc: disc}
  # the pinned expression is carried verbatim — it is matched at runtime, not
  # destructured, and the exhaustiveness lowerer treats a pin as a guard
  def from_pat({:pin, e}), do: %PPin{expr: e}

  def from_pat({:struct, name, fields}),
    do: %PStruct{name: name, fields: Enum.map(fields, fn {f, p} -> {f, from_pat(p)} end)}

  def from_pat({:map, kvs}),
    do: %PMap{pairs: Enum.map(kvs, &map_pat_pair/1)}

  def from_pat({:bitstr_pat, segs}),
    do: %PBitstr{segments: Enum.map(segs, fn {:bitseg, v, specs} -> {from_pat(v), specs} end)}

  # a map pair (literal/update): an atom key stays a bare key string `{k, value}`;
  # a computed key `keyExpr => v` keeps the key as a wrapped Core *expression*
  # `{{:key, expr}, value}` (ADR-0033 non-atom keys).
  defp map_pair({{:key, k}, v}), do: {{:key, from_expr(k)}, from_expr(v)}
  defp map_pair({k, v}), do: {k, from_expr(v)}

  # a map *pattern* pair: the value is a sub-pattern, but the key is always a value
  # (an expression looked up in the map), so a computed key lowers via `from_expr`.
  defp map_pat_pair({{:key, k}, p}), do: {{:key, from_expr(k)}, from_pat(p)}
  defp map_pat_pair({k, p}), do: {k, from_pat(p)}

  # comprehension desugar (ADR-0079), right-to-left over the clause list. `used` is the
  # set of identifier names appearing anywhere in the comprehension; a pattern
  # generator's synthetic callback parameter is **gensym'd against it** so it can never
  # capture a user variable (a body referencing `__g0`, a nested pattern generator, …).
  #   ⟦ [], body ⟧               = [body]                       (singleton list leaf)
  #   ⟦ (var <- src)  :: r ⟧     = List.flat_map(src, (var) -> ⟦ r ⟧)
  #   ⟦ (pat <- src)  :: r ⟧     = List.flat_map(src, (g) -> case g do
  #                                  pat -> ⟦ r ⟧ ; _ -> [] end)   (g fresh; non-match SKIPS)
  #   ⟦ (filter)      :: r ⟧     = if filter do ⟦ r ⟧ else [] end
  defp desugar_for([], body, _used), do: %EList{elems: [from_expr(body)], tail: :close}

  # a plain-variable generator always matches → a direct lambda binding on the user's
  # own name (intentional shadowing, no fresh name needed).
  defp desugar_for([{:gen, {:var, name}, src} | rest], body, used) do
    flat_map(src, %ELambda{params: [{name, nil}], body: desugar_for(rest, body, used)})
  end

  # any other generator pattern wraps the continuation in a `case` whose wildcard arm
  # yields `[]`, dropping non-matching elements. The scrutinee var is gensym'd and added
  # to `used` so a deeper pattern generator picks a *different* fresh name.
  defp desugar_for([{:gen, pat, src} | rest], body, used) do
    g = fresh_id("__g", used)
    inner = desugar_for(rest, body, MapSet.put(used, g))

    callback = %ELambda{
      params: [{g, nil}],
      body: %ECase{
        scrut: %EId{name: g},
        arms: [
          {from_pat(pat), nil, inner},
          {%PWild{}, nil, %EList{elems: [], tail: :close}}
        ]
      }
    }

    flat_map(src, callback)
  end

  defp desugar_for([{:filter, cond} | rest], body, used) do
    %EIf{
      cond: from_expr(cond),
      then: desugar_for(rest, body, used),
      else: %EList{elems: [], tail: :close}
    }
  end

  defp flat_map(src, callback) do
    %ECall{
      fun: %EDot{head: %EId{name: "List"}, name: "flat_map"},
      args: [from_expr(src), callback]
    }
  end

  # every identifier name (`{:id, n}` / `{:var, n}`) anywhere in a surface term — the
  # avoid-set for comprehension gensym (over-approximates; that is safe).
  defp comp_ids(term), do: comp_ids(term, MapSet.new())
  defp comp_ids({tag, n}, acc) when tag in [:id, :var] and is_binary(n), do: MapSet.put(acc, n)
  defp comp_ids(t, acc) when is_tuple(t), do: comp_ids(Tuple.to_list(t), acc)
  defp comp_ids(l, acc) when is_list(l), do: Enum.reduce(l, acc, &comp_ids/2)
  defp comp_ids(_, acc), do: acc

  # `base`, else `base0`, `base1`, … — the first not present in `used`.
  defp fresh_id(base, used) do
    if MapSet.member?(used, base), do: fresh_id_n(base, 0, used), else: base
  end

  defp fresh_id_n(base, n, used) do
    cand = base <> Integer.to_string(n)
    if MapSet.member?(used, cand), do: fresh_id_n(base, n + 1, used), else: cand
  end

  @rian_sig "pub def first_unsupported(node Expr, unsup Dict(_Unk, _Unk)) _Unk"
  @doc """
  Generic typed-core walk used by the partial emitters (`Rian.JS`, `Rian.JVM`):
  the friendly label of the first node whose struct is a key in `unsup`, else
  `nil`. Each emitter supplies its own struct→label map and raises its own
  `Unsupported` from the result. (Mirrors `Rian.Reach.scan/3`'s shape.)
  """
  @spec first_unsupported(term(), map()) :: term()
  def first_unsupported(node, unsup) when is_struct(node) do
    case Map.get(unsup, node.__struct__) do
      nil ->
        node
        |> Map.from_struct()
        |> Map.values()
        |> Enum.find_value(&first_unsupported(&1, unsup))

      label ->
        label
    end
  end

  def first_unsupported(l, unsup) when is_list(l),
    do: Enum.find_value(l, &first_unsupported(&1, unsup))

  def first_unsupported(t, unsup) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.find_value(&first_unsupported(&1, unsup))

  def first_unsupported(_node, _unsup), do: nil

  @rian_sig "pub def reject_unsupported!(funcs Vec(Func), unsup Dict(_Unk, _Unk), target Symbol, exception Symbol) Symbol"
  @doc """
  Reject any function whose body uses a construct a partial emitter cannot lower.
  For each clause, parse the body, find the first node whose struct is in `unsup`
  (`first_unsupported/2`), and `raise exception` naming the function, the
  construct, and `target`. Shared by `Rian.JS` and `Rian.JVM`; each passes its own
  struct→label map, target atom, and module-local `Unsupported` exception.
  """
  @spec reject_unsupported!([map()], map(), atom(), module()) :: :ok
  def reject_unsupported!(funcs, unsup, target, exception) do
    Enum.each(funcs, fn f ->
      Enum.each(f.clauses, fn c ->
        body = c.body |> Rian.Pratt.parse_body() |> from_expr()

        case first_unsupported(body, unsup) do
          nil -> :ok
          label -> raise exception, "`#{f.name}`: #{label} is not yet supported on :#{target}"
        end
      end)
    end)
  end
end
