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

  Remaining (ADR-0050 §5): the exhaustiveness normalizer
  ([`Rian.PatternLower`](pattern_lower.ex)) still consumes surface patterns
  (it keeps a documented surface contract with direct tests); and emitters do
  not yet *read* `node.type` for representation choices (the §3 payoff).
  """

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
    @moduledoc "A statement block; `stmts` are `{:bind, name, expr}` | `{:expr, expr}`."
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
  def from_expr({:num, n}), do: %ENum{text: n}
  def from_expr({:str, s}), do: %EStr{value: s}
  def from_expr({:id, x}), do: %EId{name: x}
  def from_expr({:atom, a}), do: %EAtom{name: a}
  def from_expr({:unary, op, x}), do: %EUnary{op: op, arg: from_expr(x)}
  def from_expr({:bin, op, l, r}), do: %EBin{op: op, left: from_expr(l), right: from_expr(r)}

  def from_expr({:call, f, args}),
    do: %ECall{fun: from_expr(f), args: Enum.map(args, &from_expr/1)}

  def from_expr({:dot, head, name}), do: %EDot{head: from_expr(head), name: name}

  def from_expr({:if, c, t, e}),
    do: %EIf{cond: from_expr(c), then: from_expr(t), else: from_expr(e)}

  def from_expr({:tuple, es}), do: %ETuple{elems: Enum.map(es, &from_expr/1)}

  def from_expr({:map_lit, ps}),
    do: %EMap{pairs: Enum.map(ps, fn {k, v} -> {k, from_expr(v)} end)}

  def from_expr({:cap_arg, n}), do: %ECapArg{n: n}
  def from_expr({:capture, b}), do: %ECapture{body: from_expr(b)}
  def from_expr({:capture_named, p, a}), do: %ECaptureNamed{path: from_expr(p), arity: a}
  def from_expr({:label, n, e}), do: %ELabel{name: n, expr: from_expr(e)}
  def from_expr({:lambda, ps, b}), do: %ELambda{params: ps, body: from_expr(b)}

  # resolved construction nodes (Rian.Lower's resolve_* passes produce these)
  def from_expr({:variant_lit, enum, ctor, named, pairs}),
    do: %EVariant{enum: enum, ctor: ctor, named: named, pairs: from_pairs(pairs)}

  def from_expr({:struct_lit, name, pairs}), do: %EStruct{name: name, pairs: from_pairs(pairs)}
  def from_expr({:const_ref, name}), do: %EConstRef{name: name}

  def from_expr({:list_lit, es, tail}),
    do: %EList{elems: Enum.map(es, &from_expr/1), tail: from_tail(tail)}

  def from_expr({:block, stmts}), do: %EBlock{stmts: Enum.map(stmts, &from_stmt/1)}

  def from_expr({:case, scrut, arms}),
    do: %ECase{scrut: from_expr(scrut), arms: Enum.map(arms, &from_arm/1)}

  def from_expr({:with, clauses, body, els}) do
    %EWith{
      clauses: Enum.map(clauses, fn {p, e} -> {from_pat(p), from_expr(e)} end),
      body: from_expr(body),
      els: Enum.map(els, &from_arm/1)
    }
  end

  defp from_tail(nil), do: :close
  defp from_tail(:close), do: :close
  defp from_tail({:tail, e}), do: from_expr(e)

  defp from_pairs(pairs), do: Enum.map(pairs, fn {label, v} -> {label, from_expr(v)} end)

  defp from_stmt({:bind, n, e}), do: {:bind, n, from_expr(e)}
  defp from_stmt({:expr, e}), do: {:expr, from_expr(e)}

  defp from_arm({pat, guard, body}),
    do: {from_pat(pat), guard && from_expr(guard), from_expr(body)}

  @doc "Translate a surface pattern (the `Rian.Pratt` tuple AST) into the typed core."
  # `{:rpat, str}` is a pre-rendered Rust pattern baked by `Rian.Lower`'s
  # Rust-only pass (it carries the type meta); pass it through unchanged.
  def from_pat({:rpat, _} = baked), do: baked
  def from_pat(:wild), do: %PWild{}
  def from_pat({:var, name}), do: %PVar{name: name}
  def from_pat({:lit, value}), do: %PLit{value: value}
  def from_pat({:atom, name}), do: %PAtom{name: name}
  def from_pat({:tuple, ps}), do: %PTuple{elems: Enum.map(ps, &from_pat/1)}
  def from_pat({:ctor, ctor, args}), do: %PCtor{ctor: ctor, args: Enum.map(args, &from_pat/1)}
  def from_pat({:list, ps, :close}), do: %PList{elems: Enum.map(ps, &from_pat/1), tail: :close}

  def from_pat({:list, ps, {:tail, t}}),
    do: %PList{elems: Enum.map(ps, &from_pat/1), tail: from_pat(t)}
end
