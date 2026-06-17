defmodule Rian.Check do
  @moduledoc """
  Type checking — first increment of ADR-0034 (unification-based inference).

  This is a deliberately **conservative** slice: it infers the type of an
  expression where it can (literals, arithmetic, comparisons, concat, `if`/block
  value) and **only reports an error when it can *prove* a mismatch** — a body
  whose inferred concrete type differs from the function's declared return type.
  Anything it cannot pin down infers to `:unknown` and never rejects, so it can
  be grown toward the full ADR-0034 design (error sets, protocol bounds) without
  ever rejecting a valid program in the meantime.

  **Flow narrowing (ADR-0034 pillar 4)** is implemented: a `case` arm — and a
  clause head, which is a one-arm `case` on the parameters — refines a matched
  constructor's bound variables to that variant's field types, so the checker
  infers through `case` bodies and pattern clauses rather than giving up at
  `:unknown`.

  **Error sets (ADR-0034 pillar 2 / ADR-0040 §4)** are checked at the declared
  boundary: a `T | E` return type declares the error set `E`; the body's
  constructed error tags (`{:error, Tag}`) must be a *subset* of `E`
  (over-declaration is allowed). A named `E` expands to its variant tags.
  *Not yet:* inferring a private function's set from its propagated callees (the
  `with`-composition half of §4).

  **Concrete generics (ADR-0042, BEAM-first)** are inferred: a list literal is
  `Vec(T)`, a variant value/constructor-call carries its sum type, and a call
  carries the callee's declared return type — *instantiated* from the call's
  argument types when the return is generic. `def id(x T) T forall T` called
  with `id(5)` infers `Int64`, and `def head(xs Vec(T)) T forall T` called with
  `head([1, 2, 3])` infers `Int64` — so HOF-driven code prints precise types
  instead of bare values. Function-typed parameters (`Fn(A, B)`) and protocol
  bounds still contribute no bindings (a later pass).

  **Function types (ADR-0042, higher-order).** A function type is spelled
  `Fn(A1, …, An, R)` — the argument types followed by the return (last element).
  A lambda `(x) -> e` infers `Fn(_, e_t)` (un-annotated args are the `_` wildcard
  slot); `&name/arity` captures a known function as `Fn(_ × arity, return)`;
  applying a function-typed *parameter* (`f(x)` where `f Fn(…, R)`) infers `R`.
  `Fn(…)` types unify **structurally** — same arity, componentwise — so an
  inferred `Fn(_, Int64)` reconciles with a declared `Fn(Int64, Int64)` while a
  real clash (`Fn(_, Int64)` vs `Fn(Int64, Bool)`) is a `:mismatch`. This is the
  self-hosting gate: a compiler-in-Rian is map/fold-shaped, and these are now
  typed rather than `:unknown`.

  Types here are the Crystal-family primitive names (`Int64`/`Float64`/`String`/
  `Bool`, ADR-0033) plus `:unknown`. `unify/2` is the kernel: equal types unify
  to themselves, `:unknown` unifies with anything, two differing concrete types
  are a `:mismatch`.
  """
  alias Rian.{Core, Pratt}

  alias Rian.Core.{
    EBin,
    EBlock,
    ECall,
    ECase,
    EChar,
    EDot,
    EId,
    EIf,
    EList,
    ENum,
    EStr,
    ETuple,
    EUnary,
    EWith
  }

  alias Rian.Core.{ECaptureNamed, ELambda}
  alias Rian.Core.{PChar, PCtor, PLit, PVar}
  alias Rian.IR.Func

  defmodule Error do
    @moduledoc "Raised by the compile-time type gate on a proven type mismatch."
    defexception [:message]
  end

  @bool_ops ~w(< <= > >= == != and or in)
  @int_ops ~w(div rem)
  @arith ~w(+ - *)

  # ── unification kernel ─────────────────────────────────────────────────
  @doc """
  Unify two types: equal -> itself; `:unknown` -> the other; differ -> `:mismatch`.
  Function types `Fn(A.., R)` (ADR-0042) unify *structurally* — same arity and
  componentwise-unifiable args+return — so an inferred lambda type with unknown
  argument slots (`Fn(_, Int64)`) still unifies against a declared `Fn(Int64, Int64)`.
  """
  @typedoc "An inferred type: a type-name string (`\"Int53\"`, `\"Fn(...)\"`) or a sentinel atom (`:unknown`/`:mismatch`/`:bottom`)."
  @type ty :: String.t() | atom()

  @spec unify(ty(), ty()) :: ty()
  def unify(t, t), do: t
  def unify(:unknown, t), do: t
  def unify(t, :unknown), do: t
  def unify("Fn(" <> _ = a, "Fn(" <> _ = b), do: unify_fn(a, b)
  def unify(_, _), do: :mismatch

  # Componentwise unify two `Fn(...)` strings; `:mismatch` on differing arity or
  # any irreconcilable component. A `_`/`:unknown`/type-variable slot is a wildcard.
  defp unify_fn(a, b) do
    pa = fn_parts(a)
    pb = fn_parts(b)

    if length(pa) == length(pb) do
      parts = Enum.zip(pa, pb) |> Enum.map(fn {x, y} -> comp_unify(x, y) end)
      if :mismatch in parts, do: :mismatch, else: "Fn(#{Enum.join(parts, ",")})"
    else
      :mismatch
    end
  end

  defp comp_unify(x, x), do: x

  defp comp_unify(x, y) do
    cond do
      wildcard?(x) -> y
      wildcard?(y) -> x
      fn_type?(x) and fn_type?(y) -> unify_fn(x, y)
      # two compatible numeric widths reconcile to their LUB — an inferred
      # `Fn(_, Int53)` (a lambda over literals) matches a declared `Fn(Int64, Int64)`.
      (j = num_lub(x, y)) != nil -> j
      true -> :mismatch
    end
  end

  defp num_lub(x, y) do
    if num_kind(x) && num_kind(y) do
      case join(x, y) do
        :unknown -> nil
        t -> t
      end
    end
  end

  defp wildcard?("_"), do: true
  defp wildcard?(t) when is_binary(t), do: tvar?(t)
  defp wildcard?(_), do: false

  # ── inference ──────────────────────────────────────────────────────────
  # `ic` is the static inference context (a map): `:tdefs` (ctor -> field types,
  # for flow narrowing), `:funs` (function name -> declared return type),
  # `:fsigs` (function name -> `%{params, ret, tvars}` for generic
  # instantiation), and `:ctors` (ctor -> its sum-type name, so a variant value
  # infers its type). `%{}` disables them all. `env` is the per-scope variable
  # map.
  @doc """
  Infer the type of an expression under `env` (name -> type); `:unknown` when
  unsure. Accepts the **typed core IR** (`Rian.Core`); a surface tuple is
  accepted too and translated, so existing callers keep working (ADR-0050 — the
  checker consumes the core, one inference, no second representation).
  """
  @spec infer(term(), map(), map()) :: ty()
  def infer(ast, env \\ %{}, ic \\ %{})
  def infer(ast, env, ic) when is_tuple(ast), do: infer(Core.from_expr(ast), env, ic)

  def infer(%ENum{text: n}, _env, _ic),
    do: if(String.contains?(n, ".") or String.match?(n, ~r/[eE]/), do: "Float64", else: "Int53")

  def infer(%EStr{}, _env, _ic), do: "String"
  # a `Char` literal is the `Char` primitive (ADR-0036); ordinal arithmetic on it
  # widens to the `Int64` base (see `ordinal_base/1`)
  def infer(%EChar{}, _env, _ic), do: "Char"
  def infer(%EId{name: b}, _env, _ic) when b in ~w(true false), do: "Bool"
  # a name resolves to a bound var, else a nullary variant constructor, else unknown
  def infer(%EId{name: x}, env, ic), do: Map.get(env, x) || ctor_type(ic, x) || :unknown
  def infer(%EUnary{op: "-", arg: x}, env, ic), do: infer(x, env, ic)
  def infer(%EUnary{op: "not"}, _env, _ic), do: "Bool"

  def infer(%EBin{op: op, left: l, right: r}, env, ic) do
    lt = infer(l, env, ic)
    rt = infer(r, env, ic)

    cond do
      # A declared `abstract` operator (ADR-0067): `Meters + Meters -> Meters`. Takes
      # precedence over the default arithmetic rules so the result carries the nominal
      # abstract type (it erases to the base operator at emit). Falls through when the
      # operands are not an abstract this `op` is declared for.
      t = abstract_op_type(op, lt, rt, ic) ->
        t

      op in @bool_ops ->
        "Bool"

      op == "<>" ->
        "String"

      op == "/" ->
        "Float64"

      op in @int_ops or op in @arith ->
        arith_type(l, r, lt, rt)

      true ->
        :unknown
    end
  end

  # a lambda `(a, b) -> body` infers the arrow type `Fn(a_t.., body_t)`: each
  # annotated param contributes its type (an un-annotated one is the `_` wildcard),
  # and the body is inferred under those bindings (ADR-0042 higher-order inference)
  def infer(%ELambda{params: ps, body: body}, env, ic) do
    lenv = Enum.reduce(ps, env, fn {n, t}, e -> Map.put(e, n, t || :unknown) end)
    args = Enum.map(ps, fn {_n, t} -> t || :unknown end)
    build_fn(args, infer(body, lenv, ic))
  end

  # `&name/arity` captures a named function as a value: its type is
  # `Fn(_ × arity, declared-return)` when the target is a known local function
  def infer(%ECaptureNamed{path: %EId{name: n}, arity: a}, _env, ic) do
    case Map.get(Map.get(ic, :funs, %{}), n) do
      nil -> :unknown
      ret -> build_fn(List.duplicate(:unknown, a), ret)
    end
  end

  # a call through a function-typed *variable* (a parameter / bound name) infers
  # the function's return type; a call to a constructor infers its sum type; a
  # call to a known named function infers that function's declared return type
  # (concretized from the call's argument types when the return is generic —
  # `def id(x T) T forall T` called with `id(5)` infers `Int64`, ADR-0042)
  # `__prim_char_code(c) : Int53` — a `Char`'s codepoint as an integer (ADR-0036, no
  # hidden widening). `Int53` (not `Int64`) so it is portable to *every* target incl.
  # JS (a codepoint ≤ 0x10FFFF fits comfortably); an `Int64` codepoint would be
  # off-`:js`, which a char primitive must not be.
  def infer(%ECall{fun: %EId{name: "__prim_char_code"}, args: [_]}, _env, _ic), do: "Int53"

  # `__prim_int_to_float(n) : Float64` — the **explicit** Int→Float conversion
  # (ADR-0035/0034 §1: there is no *implicit* int→float, so the widening is opt-in
  # and visible at the call site). The lossy precision change (>2^53) is the
  # programmer's choice, exactly like Rust's `n as f64`.
  def infer(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [_]}, _env, _ic), do: "Float64"

  # `__prim_str_to_atom(s) : Symbol` — string interning to a BEAM atom (ADR-0047).
  # Atoms are BEAM-only; `Rian.Reach` pins a caller off `:rs`/`:js`/`:jvm`.
  def infer(%ECall{fun: %EId{name: "__prim_str_to_atom"}, args: [_]}, _env, _ic), do: "Symbol"

  # `__prim_str_concat_all(parts…) : String` — the single-shot interpolation join
  # (ADR-0069 §6); every part is already a `String` (stringified by `Rian.Interp`).
  def infer(%ECall{fun: %EId{name: "__prim_str_concat_all"}, args: _}, _env, _ic), do: "String"

  # `__prim_char_to_string(c) : String` — a `Char`'s single-character string
  # (ADR-0069 §6); portable, lowered natively per target.
  def infer(%ECall{fun: %EId{name: "__prim_char_to_string"}, args: [_]}, _env, _ic), do: "String"

  def infer(%ECall{fun: %EId{name: f}, args: as}, env, ic) do
    cond do
      fn_type?(ft = Map.get(env, f)) -> fn_ret(ft)
      true -> ctor_type(ic, f) || called_ret_with(ic, f, as, env)
    end
  end

  # `Name.of(n)` — range construction (ADR-0036): the checked constructor of a
  # `range` type returns `base | RangeError` (a `T | E` Result, ADR-0040). The
  # argument must be assignable to the range's ordinal base.
  def infer(%ECall{fun: %EDot{head: %EId{name: n}, name: "of"}} = call, env, ic) do
    cond do
      # `opaque Name := Base` (ADR-0067/ADR-0043): the constructor is *total* —
      # `Name.of(x)` (x : Base) returns the nominal `Name` itself, no Result wrap
      # (the abstraction adds no failure mode; it erases to `x` at emit).
      Map.has_key?(Map.get(ic, :opaques, %{}), n) ->
        n

      base = range_base(ic, n) ->
        "#{base} | RangeError"

      true ->
        ft = infer(call.fun, env, ic)
        if fn_type?(ft), do: fn_ret(ft), else: :unknown
    end
  end

  # `m.base()` — an `abstract` cast (ADR-0067 §2): a declared `to base() B` on the
  # value's abstract type exposes the underlying representation, returning `B`. The
  # cast is explicit (never implicit, ADR-0035) and erases to the identity at emit.
  # A zero-arg dot-call that is *not* a cast falls through to the generic logic.
  def infer(%ECall{fun: %EDot{head: h, name: cn} = fun, args: []}, env, ic) do
    case abstract_cast_ret(infer(h, env, ic), cn, ic) do
      nil ->
        ft = infer(fun, env, ic)
        if fn_type?(ft), do: fn_ret(ft), else: :unknown

      ret ->
        ret
    end
  end

  # a call to any other callable (a lambda result, a returned function) infers
  # its return type when the callee is known to be a function, else `:unknown`
  def infer(%ECall{fun: fun}, env, ic) do
    ft = infer(fun, env, ic)
    if fn_type?(ft), do: fn_ret(ft), else: :unknown
  end

  # Branch/arm *joins* use `join/2` — the least-upper-bound lattice (ADR-0059),
  # NOT strict `unify`: two differing-but-compatible concretes climb to their LUB
  # (`Int32`-vs-`Int64` arms infer `Int64`, mirroring how a binding widens), while
  # operands with no common upper bound (a signed/unsigned or int/float gap) or an
  # uninferable arm resolve to `:unknown`. `join` is commutative & associative, so
  # the N-ary `case`/list reductions below are fold-order-independent.
  def infer(%EIf{then: t, else: e}, env, ic),
    do: branch_join([{t, infer(t, env, ic)}, {e, infer(e, env, ic)}])

  # `case` — flow narrowing: each arm body is inferred under an env where the
  # arm pattern's bindings are refined against the scrutinee's type. The case's
  # type is the LUB-join of all arm bodies.
  def infer(%ECase{scrut: scrut, arms: arms}, env, ic) do
    st = infer(scrut, env, ic)

    arms
    |> Enum.map(fn {pat, _guard, body} -> {body, infer(body, narrow(pat, st, ic, env), ic)} end)
    |> branch_join()
  end

  # a list literal infers `Vec(T)` (the family list type) when its elements — and
  # any cons tail — LUB-join to a concrete element type `T`; else `:unknown`
  def infer(%EList{elems: elems, tail: tail}, env, ic) do
    elem_t =
      elems
      |> Enum.map(&infer(&1, env, ic))
      |> Enum.reduce(:bottom, &join(&1, &2))
      |> debottom()

    case {elem_t, list_elem(infer_tail(tail, env, ic))} do
      {t, te} when te == :unknown or te == t -> list_of(conservative(t))
      _ -> :unknown
    end
  end

  def infer(%EBlock{stmts: stmts}, env, ic), do: infer_block(stmts, env, ic, :unknown)
  # a `with` yields its do-block value on the happy path (clause-bound vars are
  # not tracked yet -> they infer `:unknown`, keeping the checker conservative)
  def infer(%EWith{body: body}, env, ic), do: infer(body, env, ic)
  def infer(_other, _env, _ic), do: :unknown

  # ── annotation (ADR-0050 §3: fill each node's inferred `type`) ──────────
  @doc """
  Return the core expression with every node's `type` field filled with its
  inferred type, threading `env` through `case`/`block` exactly as `infer` does.
  The type value at each node is `infer/3` (one source of truth — no second set
  of type rules), so an emitter can read representation choices off `node.type`
  (ADR-0041/0043/0046). Nodes inference can't pin down keep `type: nil`.
  """
  @spec annotate(term(), map(), map()) :: term()
  def annotate(ast, env \\ %{}, ic \\ %{})
  def annotate(ast, env, ic) when is_tuple(ast), do: annotate(Core.from_expr(ast), env, ic)

  def annotate(%t{} = n, env, ic) when t in [ENum, EStr, EChar, EId],
    do: %{n | type: infer(n, env, ic)}

  def annotate(%EUnary{arg: a} = n, env, ic),
    do: %{n | arg: annotate(a, env, ic), type: infer(n, env, ic)}

  def annotate(%EBin{left: l, right: r} = n, env, ic),
    do: %{n | left: annotate(l, env, ic), right: annotate(r, env, ic), type: infer(n, env, ic)}

  def annotate(%ECall{fun: f, args: as} = n, env, ic),
    do: %{n | fun: annotate(f, env, ic), args: ann_each(as, env, ic), type: infer(n, env, ic)}

  def annotate(%ETuple{elems: es} = n, env, ic),
    do: %{n | elems: ann_each(es, env, ic), type: infer(n, env, ic)}

  def annotate(%EList{elems: es, tail: tl} = n, env, ic) do
    tail = if tl == :close, do: :close, else: annotate(tl, env, ic)
    %{n | elems: ann_each(es, env, ic), tail: tail, type: infer(n, env, ic)}
  end

  def annotate(%EIf{cond: c, then: t, else: e} = n, env, ic) do
    %{
      n
      | cond: annotate(c, env, ic),
        then: annotate(t, env, ic),
        else: annotate(e, env, ic),
        type: infer(n, env, ic)
    }
  end

  def annotate(%EBlock{stmts: stmts} = n, env, ic),
    do: %{n | stmts: ann_stmts(stmts, env, ic), type: infer(n, env, ic)}

  def annotate(%ECase{scrut: s, arms: arms} = n, env, ic) do
    st = infer(s, env, ic)

    arms =
      Enum.map(arms, fn {pat, g, body} ->
        e = narrow(pat, st, ic, env)
        {pat, g && annotate(g, e, ic), annotate(body, e, ic)}
      end)

    %{n | scrut: annotate(s, env, ic), arms: arms, type: infer(n, env, ic)}
  end

  def annotate(%EWith{body: body} = n, env, ic),
    do: %{n | body: annotate(body, env, ic), type: infer(n, env, ic)}

  def annotate(node, _env, _ic), do: node

  defp ann_each(nodes, env, ic), do: Enum.map(nodes, &annotate(&1, env, ic))

  defp ann_stmts([], _env, _ic), do: []

  defp ann_stmts([{:bind, x, e} | rest], env, ic),
    do: [
      {:bind, x, annotate(e, env, ic)} | ann_stmts(rest, Map.put(env, x, infer(e, env, ic)), ic)
    ]

  # a typed binding displays at its *declared* type (ADR-0034 §1), not the
  # inferred one — the annotation is the contract for `x` downstream.
  defp ann_stmts([{:typed_bind, x, t, e} | rest], env, ic),
    do: [
      {:typed_bind, x, t, annotate(e, env, ic)} | ann_stmts(rest, Map.put(env, x, t), ic)
    ]

  defp ann_stmts([{:expr, e} | rest], env, ic),
    do: [{:expr, annotate(e, env, ic)} | ann_stmts(rest, env, ic)]

  defp ctor_type(ic, name), do: Map.get(Map.get(ic, :ctors, %{}), name)

  # a named function's declared return type. When the function has `forall`
  # type variables (`fsigs[f]` is present), try to *instantiate* the return
  # from the call's argument types; if some tvar can't be pinned, fall back to
  # `:unknown` (conservative). Otherwise return the declared ret directly —
  # except for a generic ret with no signature available, which is still
  # `:unknown` because pinning it to the literal `Vec(U)` would wrongly
  # contradict a concrete caller.
  defp called_ret_with(ic, f, args_ast, env) do
    case Map.get(Map.get(ic, :fsigs, %{}), f) do
      %{tvars: [_ | _]} = sig ->
        arg_types = Enum.map(args_ast, &infer(&1, env, ic))
        instantiate_ret(sig, arg_types)

      _ ->
        called_ret(ic, f)
    end
  end

  defp called_ret(ic, f) do
    case Map.get(Map.get(ic, :funs, %{}), f) do
      nil -> :unknown
      ret -> if has_tvar?(ret), do: :unknown, else: ret
    end
  end

  # Instantiate a generic return: unify each (declared-param-type, inferred-arg-
  # type) pair to bind tvars, then substitute them in `ret`. A tvar that can't
  # be pinned (no informative arg) leaves the call type as `:unknown` — sound,
  # never a lie. Function-typed params (`Fn(...)`) contribute no bindings here
  # (a real piece of work for a later pass); concrete params are also inert,
  # which is correct (they can only confirm, not instantiate, the tvars).
  defp instantiate_ret(%{params: ps, ret: ret, tvars: tvars}, arg_types) do
    subs =
      ps
      |> Enum.zip(arg_types)
      |> Enum.reduce(%{}, fn {p, a}, acc -> bind_tvar(p, a, tvars, acc) end)

    # Only the tvars that actually appear in `ret` need binding: `length(xs Vec(T))
    # Int53 forall T` returns `Int53` regardless of `T`, so a recursive `length(t)`
    # over an `:unknown` tail still infers `Int53` (not `:unknown`). A tvar that the
    # return uses but the args can't pin still yields `:unknown` — sound.
    needed = Enum.filter(tvars, &Regex.match?(~r/\b#{&1}\b/, ret))

    if Enum.all?(needed, &Map.has_key?(subs, &1)) do
      Enum.reduce(subs, ret, fn {tv, ty}, r -> Regex.replace(~r/\b#{tv}\b/, r, ty) end)
    else
      :unknown
    end
  end

  # Unify a parameter's declared type string with the inferred argument type
  # to extract `tvar -> concrete` bindings. Handles bare tvars (`T`) and
  # `Vec(T)`/structural matches; ignores conflicts (first binding wins).
  defp bind_tvar(_p, :unknown, _tvars, acc), do: acc

  defp bind_tvar(p, a, tvars, acc) when is_binary(p) and is_binary(a) do
    cond do
      p in tvars ->
        Map.put_new(acc, p, a)

      String.starts_with?(p, "Vec(") and String.starts_with?(a, "Vec(") ->
        bind_tvar(inner_of(p), inner_of(a), tvars, acc)

      true ->
        acc
    end
  end

  defp bind_tvar(_p, _a, _tvars, acc), do: acc

  defp inner_of("Vec(" <> rest), do: String.trim_trailing(rest, ")")

  # does a type string mention a standalone type variable (a single capital,
  # optionally one digit) — `U`, `Vec(U)`, `Fn(T, U)` yes; `Int64`, `Vec(Int64)` no
  defp has_tvar?(s), do: Regex.match?(~r/\b[A-Z][0-9]?\b/, s)

  defp infer_tail(:close, _env, _ic), do: :unknown
  defp infer_tail(tail, env, ic), do: infer(tail, env, ic)

  # `Vec(T)` string helpers (types are strings; concrete generics unify by ==).
  defp list_of(:unknown), do: :unknown
  defp list_of(t), do: "Vec(#{t})"

  defp list_elem("Vec(" <> rest), do: String.trim_trailing(rest, ")")
  defp list_elem(_), do: :unknown

  # `Fn(A1,..,An,R)` function-type string helpers (ADR-0042). The components are
  # the argument types followed by the return type (the last element is the
  # return); a `_` component is an unknown slot. Types remain strings.
  defp fn_type?("Fn(" <> _), do: true
  defp fn_type?(_), do: false

  defp fn_parts("Fn(" <> rest), do: rest |> String.trim_trailing(")") |> split_top_commas()

  # the return type (last component); `_` reads back as `:unknown`
  defp fn_ret(ft), do: ft |> fn_parts() |> List.last() |> deplaceholder()

  defp deplaceholder("_"), do: :unknown
  defp deplaceholder(t), do: concretize(t)

  # build `Fn(args.., ret)` from inferred component types (`:unknown` -> `_`)
  defp build_fn(args, ret), do: "Fn(#{Enum.map_join(args ++ [ret], ",", &comp_str/1)})"
  defp comp_str(:unknown), do: "_"
  defp comp_str(t), do: to_string(t)

  # split a type string on top-level commas, respecting nested `(`/`)` (so a
  # nested `Fn(Int64,Int64)` argument is one component, not two)
  defp split_top_commas(s), do: Rian.TypeStr.split_top_commas(s)

  defp infer_block([], _env, _ic, value), do: value

  defp infer_block([{:bind, n, e} | rest], env, ic, _value) do
    t = infer(e, env, ic)
    infer_block(rest, Map.put(env, n, t), ic, t)
  end

  # a typed binding binds `n` at its *declared* type (ADR-0034 §1); enforcement
  # that the value fits the annotation is the gate's job (`check_binds/2`). A
  # `range` annotation resolves to its base (representation, not newtype; ADR-0036)
  # so the binding unifies as its ordinal base downstream.
  defp infer_block([{:typed_bind, n, t, _e} | rest], env, ic, _value) do
    rt = resolve_range(t, ic)
    infer_block(rest, Map.put(env, n, rt), ic, rt)
  end

  defp infer_block([{:expr, e} | rest], env, ic, _value),
    do: infer_block(rest, env, ic, infer(e, env, ic))

  # Narrow one core pattern against the type it matches, binding its variables.
  # A `PVar` takes the matched type directly; a `PCtor` looks up its field types
  # and narrows each argument in turn. Unknown ctor / no `tdefs` -> `:unknown`.
  defp narrow(%PVar{name: name}, type, _ic, env), do: Map.put(env, name, concretize(type))

  defp narrow(%PCtor{ctor: ctor, args: args}, _type, ic, env) do
    field_types = Map.get(Map.get(ic, :tdefs, %{}), ctor, [])

    args
    |> Enum.with_index()
    |> Enum.reduce(env, fn {p, i}, env ->
      narrow(p, Enum.at(field_types, i, :unknown), ic, env)
    end)
  end

  defp narrow(_pat, _type, _ic, env), do: env

  # a field type that is a type *variable* (a generic like `Option(T)`'s `T`)
  # narrows to `:unknown` — we don't instantiate generics yet (conservative)
  defp concretize(t) when is_binary(t), do: if(tvar?(t), do: :unknown, else: t)
  # an `:infer` param (ADR-0034 infer-local) is treated as `:unknown` mid-fixpoint —
  # it imposes no constraint until `Rian.InferLocal` replaces it with a concrete type.
  defp concretize(:infer), do: :unknown
  defp concretize(t), do: t
  defp tvar?(t), do: String.match?(t, ~r/^[A-Z][0-9]?$/)

  # a mismatch deep in arithmetic stays conservative (we do not model coercion
  # fully yet) rather than rejecting; only the body-vs-return check rejects
  defp conservative(:mismatch), do: :unknown
  defp conservative(t), do: t

  # ordinal arithmetic widens to the base (ADR-0036): `Char ± _` is `Int64`, not
  # `Char` (`'9' - '0' = 9 ∉ Char`). A `Char` operand contributes its codepoint
  # base; every other type passes through unchanged.
  # `Char`'s ordinal base is `Int53` (its codepoint width, `__prim_char_code`) — the
  # portable all-target integer, so `'a' + 1` is `Int53`, JS-reachable (ADR-0036/0064).
  defp ordinal_base("Char"), do: "Int53"
  defp ordinal_base(t), do: t

  # Arithmetic result type. An integer *literal* operand is width-flexible (a
  # literal adopts any same-kind width), so `typed op literal` — and a nested
  # `(13 - lvl) * 10` over an `Int53` var — takes the typed operand's width instead
  # of forcing the literal's default `Int64`. Without this, `unify(:unknown, Int64)`
  # resolved a literal-bearing arithmetic to `Int64`, spuriously clashing with an
  # `Int53`/`Int32` return (ADR-0064). Two non-literal operands unify as before.
  defp arith_type(l, r, lt, rt) do
    cond do
      int_lit_expr?(l) and adoptable_int?(rt) -> ordinal_base(rt)
      int_lit_expr?(r) and adoptable_int?(lt) -> ordinal_base(lt)
      true -> conservative(unify(ordinal_base(lt), ordinal_base(rt)))
    end
  end

  # An integer literal may adopt a *concrete integer* neighbour, but NOT a
  # `Float`/`Bool`/`String` (`1 + 2.0` stays mixed/`:unknown` — no implicit int→float
  # coercion, ADR-0035) nor an `:unknown` one (`x + 1` with `x` unknown stays
  # `Int64`, the literal's default — the prior conservative behaviour). Because the
  # literal adopts a concrete width, a chain like `13 - lvl` over an `Int53` already
  # resolves to `Int53`, so a nested `(13 - lvl) * 10` never needs `:unknown`.
  defp adoptable_int?(t), do: int_type?(t)

  # a constant *integer* expression of literals — a bare int literal, a negation, or
  # arithmetic of such (the same op set `lit_expr_adopts?` accepts: `+ - * div rem`,
  # so the two sibling predicates agree — `4 div 2` is a width-flexible constant too).
  defp int_lit_expr?(%ENum{text: t}), do: int_literal?(t)
  defp int_lit_expr?(%EUnary{op: "-", arg: a}), do: int_lit_expr?(a)

  defp int_lit_expr?(%EBin{op: op, left: l, right: r}) when op in @arith or op in @int_ops,
    do: int_lit_expr?(l) and int_lit_expr?(r)

  # an `if`/`case` branch is a single-expression block (`do 0 end` → `{block, [0]}`)
  defp int_lit_expr?(%EBlock{stmts: [{:expr, e}]}), do: int_lit_expr?(e)
  defp int_lit_expr?(_), do: false

  # Join branch/arm types into the LUB — but an integer-*literal* branch is
  # width-flexible (it adopts any width), so it does NOT drag the join up to its
  # default `Int64`: when at least one branch is a non-literal, the result is the
  # join of only the non-literal branches (an `Int53` `then` with a literal `0`
  # `else` stays `Int53`, ADR-0064). All-literal branches join as usual (and a
  # literal return body is then handled by `body_literal_adopts?`).
  defp branch_join(typed) do
    all = Enum.map(typed, &elem(&1, 1))
    non_lit = for {e, t} <- typed, not int_lit_expr?(e), do: t

    cond do
      # all branches are integer literals — join them (a literal return body is then
      # handled by `body_literal_adopts?`); nothing to adopt from
      non_lit == [] -> join_all(all)
      # the non-literal branches join to an integer — the literal branches adopt it
      # (an `Int53` `then` with a literal `0` `else` stays `Int53`)
      int_type?(join_all(non_lit)) -> join_all(non_lit)
      # otherwise (a `Bool`/`String`/`Float` or uninferable non-literal branch) the
      # int literal cannot adopt it — join ALL branches as before (mismatch →
      # `:unknown`, so `if c do 1 else true end` stays `:unknown`, not `Bool`)
      true -> join_all(all)
    end
  end

  defp join_all(types),
    do: types |> Enum.reduce(:bottom, fn t, acc -> join(acc, t) end) |> debottom()

  # ── function checking ──────────────────────────────────────────────────
  @doc """
  Check one function. `ic` is the inference context (`:tdefs`/`:funs`/`:ctors`);
  `eset` is the error-set context (`:tsets` name->tags, `:table` the call-graph
  fixpoint). Returns `:ok` or `{:error, message}`. Two checks run:

    * **return type** — no clause body's inferred concrete type may *contradict*
      the declared return type (now including parametric `Vec(T)` and a body's
      sum-variant / function-call result, ADR-0042 — concrete generics);
    * **error set** — when the return type is `T | E`, the function's *produced*
      set — directly-built `{:error, Tag}` ∪ propagated callee sets — must be a
      subset of `E` (over-declaration allowed; ADR-0040 §4).
  """
  @spec check_func(struct(), map(), map()) :: term()
  def check_func(func, ic \\ %{}, eset \\ %{tsets: %{}, table: %{}})

  def check_func(%Func{} = f, ic, eset) do
    with :ok <- check_external_caps(f),
         :ok <- check_labels(f),
         :ok <- check_return(f, ic),
         :ok <- check_binds(f, ic),
         :ok <- check_bounds(f, ic),
         :ok <- check_numeric_mix(f, ic),
         do: check_error_set(f, eset)
  end

  # ADR-0035 / ADR-0034 §1 — **no implicit Int↔Float coercion.** An arithmetic
  # operator (`+`/`-`/`*`) whose two operands are *concretely* one integer-kind
  # and one float-kind is a proven error: a value never silently changes numeric
  # type (the widen is lossy past 2^53), and the construct is non-portable (rustc
  # rejects `i64 * f64`). The fix is explicit — a float literal (`3.0`) or
  # `Prim.int_to_float(n)`. Only fires when both kinds are known (an `:unknown`
  # operand stays conservative), so it reports only what it can prove.
  defp check_numeric_mix(%Func{params: ps, clauses: clauses}, ic) do
    Enum.find_value(clauses, :ok, fn c ->
      env = clause_env(c.pats, ps, ic)
      scan_num_mix(Pratt.parse_body(c.body), env, ic) || :ok
    end)
  end

  defp scan_num_mix({:bin, op, l, r} = node, env, ic) when op in @arith do
    num_mix_error(op, l, r, env, ic) || scan_num_mix_children(node, env, ic)
  end

  defp scan_num_mix(node, env, ic) when is_tuple(node),
    do: scan_num_mix_children(node, env, ic)

  defp scan_num_mix(list, env, ic) when is_list(list),
    do: Enum.find_value(list, nil, &scan_num_mix(&1, env, ic))

  defp scan_num_mix(_other, _env, _ic), do: nil

  defp scan_num_mix_children(node, env, ic),
    do: node |> Tuple.to_list() |> Enum.find_value(nil, &scan_num_mix(&1, env, ic))

  defp num_mix_error(op, l, r, env, ic) do
    lt = ordinal_base(infer(l, env, ic))
    rt = ordinal_base(infer(r, env, ic))

    if mixed_num?(lt, rt) do
      {:error,
       "`#{op}`: no implicit Int↔Float conversion (`#{lt} #{op} #{rt}`) — a value never " <>
         "silently becomes a float (ADR-0035/0034 §1). Convert explicitly: write a float " <>
         "literal (e.g. `3.0`) or `Prim.int_to_float(n)`."}
    end
  end

  # one operand integer-kind (`Int`/`UInt`, incl. a `Char`'s `Int53` base), the
  # other float-kind — both concretely known.
  defp mixed_num?(lt, rt) do
    case {num_kind(lt), num_kind(rt)} do
      {{lk, _}, {rk, _}} -> num_mix?(lk, rk)
      _ -> false
    end
  end

  defp num_mix?(:float, k) when k in [:int, :uint], do: true
  defp num_mix?(k, :float) when k in [:int, :uint], do: true
  defp num_mix?(_, _), do: false

  # Labeled arguments (`name: value`) are valid ONLY in struct/variant *construction*
  # — a PascalCase constructor callee (ADR-0043 / types-match §2). On a plain
  # (lowercase) function call they are rejected: labeled call args are frozen out by
  # ADR-0065 ("adopt later, not now"), and without this gate the BEAM emitter would
  # silently miscompile `foo(x: 1)` into a bogus `%{__struct__: :foo, x: 1}`.
  defp check_labels(%Func{clauses: clauses}) do
    Enum.find_value(clauses, :ok, fn
      %{body: nil} -> nil
      %{body: body} -> label_error(Pratt.parse_body(body))
    end) || :ok
  end

  defp label_error({:call, {:id, f}, args} = node) when is_list(args) do
    if Enum.any?(args, &match?({:label, _, _}, &1)) and not pascal?(f) do
      {:error,
       "`#{f}(…)`: labeled arguments (`name: value`) are only for struct/variant construction " <>
         "(a PascalCase constructor), not plain function calls (ADR-0065 — labeled call args are " <>
         "not yet a surface feature)"}
    else
      label_error_children(node)
    end
  end

  defp label_error(node) when is_tuple(node), do: label_error_children(node)
  defp label_error(list) when is_list(list), do: Enum.find_value(list, &label_error/1)
  defp label_error(_other), do: nil

  defp label_error_children(node),
    do: node |> Tuple.to_list() |> Enum.find_value(&label_error/1)

  # An `@external` function (ADR-0068) is trusted FFI: its signature is checked but
  # its host bodies are not. Linearity (`iso`/`ref`, ADR-0055) cannot be enforced
  # across a foreign boundary, so an `@external` param must be `val` or `tag`
  # (ADR-0068 open item — restrict initially). Non-external functions are unaffected.
  defp check_external_caps(%Func{externals: ext}) when map_size(ext) == 0, do: :ok

  defp check_external_caps(%Func{name: name, params: params}) do
    case Enum.find(params, &(&1.cap in [:iso, :ref])) do
      nil ->
        :ok

      p ->
        {:error,
         "`#{name}`: an `@external` parameter must be `val` or `tag` — `#{p.name}` is `#{p.cap}` " <>
           "(linearity is not enforceable across an FFI boundary, ADR-0068/0055)"}
    end
  end

  # ADR-0042 §2 — protocol bounds. At each call to a bounded generic, instantiate
  # the callee's type variables from the argument types; when a bound `T: P`
  # instantiates `T` to a *concrete* type `A` with no `impl P for A`, that is a
  # proven violation. An `:unknown` (un-pinned) instantiation never rejects —
  # like the rest of the checker, the gate reports only what it can prove.
  defp check_bounds(%Func{params: ps, clauses: clauses}, ic) do
    fbounds = Map.get(ic, :fbounds, %{})

    if fbounds == %{} do
      :ok
    else
      Enum.find_value(clauses, :ok, fn c ->
        env = clause_env(c.pats, ps, ic)
        scan_bound_calls(Pratt.parse_body(c.body), env, ic, fbounds) || :ok
      end)
    end
  end

  # walk the (surface tuple) body for call sites, checking any that target a
  # bounded generic; returns the first `{:error, msg}` or `nil`.
  defp scan_bound_calls({:call, {:id, g}, args} = node, env, ic, fbounds) do
    call_bound_error(g, args, env, ic, fbounds) || walk_children(node, env, ic, fbounds)
  end

  defp scan_bound_calls(node, env, ic, fbounds) when is_tuple(node),
    do: walk_children(node, env, ic, fbounds)

  defp scan_bound_calls(list, env, ic, fbounds) when is_list(list),
    do: Enum.find_value(list, nil, &scan_bound_calls(&1, env, ic, fbounds))

  defp scan_bound_calls(_other, _env, _ic, _fbounds), do: nil

  defp walk_children(node, env, ic, fbounds) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.find_value(nil, &scan_bound_calls(&1, env, ic, fbounds))

  # check one call against the callee's bounds, if it is a bounded generic
  defp call_bound_error(g, args, env, ic, fbounds) do
    case Map.get(fbounds, g) do
      nil ->
        nil

      %{params: ps, tvars: tvars, bounds: bounds} ->
        arg_types = Enum.map(args, &infer(&1, env, ic))

        subs =
          Enum.reduce(Enum.zip(ps, arg_types), %{}, fn {p, a}, acc ->
            bind_tvar(p, a, tvars, acc)
          end)

        first_bound_violation(g, bounds, subs, ic)
    end
  end

  defp first_bound_violation(g, bounds, subs, ic) do
    impls = Map.get(ic, :impls, %{})

    Enum.find_value(bounds, nil, fn {tvar, protos} ->
      case Map.get(subs, tvar) do
        nil -> nil
        ty -> if concrete_type?(ty), do: missing_impl(g, tvar, ty, protos, impls), else: nil
      end
    end)
  end

  defp missing_impl(g, tvar, ty, protos, impls) do
    Enum.find_value(protos, nil, fn p ->
      unless MapSet.member?(Map.get(impls, p, MapSet.new()), ty) do
        {:error,
         "`#{g}` requires `#{tvar}: #{p}`, but `#{ty}` has no `impl #{p} for #{ty}` (ADR-0042 §2)"}
      end
    end)
  end

  # a type the bound check can act on: a known concrete type, not `:unknown` and
  # not still a type variable (an un-pinned generic) — those stay conservative.
  defp concrete_type?(:unknown), do: false
  defp concrete_type?(t) when is_binary(t), do: not has_tvar?(t)
  defp concrete_type?(_), do: false

  # ADR-0034 §1 — typed bindings. `x T := e` checks `e` against the declared type
  # `T`: a numeric *literal* adopts `T` (bidirectional checking — the literal takes
  # the declared width), while any already-typed RHS must be *assignable* to `T`,
  # i.e. it may **widen losslessly** (`x Int64 := someInt32` ok) but not narrow
  # (`x Int32 := someInt64` is a proven mismatch) — amended 2026-06-13. An
  # `:unknown` RHS is left unchecked — the gate only reports *provable* clashes.
  defp check_binds(%Func{params: ps, clauses: clauses}, ic) do
    Enum.find_value(clauses, :ok, fn c ->
      {:block, stmts} = Pratt.parse_body(c.body)
      check_bind_stmts(stmts, clause_env(c.pats, ps, ic), ic)
    end)
  end

  defp check_bind_stmts([], _env, _ic), do: nil

  defp check_bind_stmts([{:typed_bind, name, ann, e} | rest], env, ic) do
    case bind_mismatch(name, ann, e, env, ic) do
      nil -> check_bind_stmts(rest, Map.put(env, name, resolve_range(ann, ic)), ic)
      err -> err
    end
  end

  defp check_bind_stmts([{:bind, name, e} | rest], env, ic),
    do: check_bind_stmts(rest, Map.put(env, name, infer(e, env, ic)), ic)

  defp check_bind_stmts([{:expr, _e} | rest], env, ic),
    do: check_bind_stmts(rest, env, ic)

  # `nil` when the binding is well-typed (or unprovable); `{:error, msg}` on a
  # proven clash between the value's type and the declared annotation.
  defp bind_mismatch(name, ann, e, env, ic) do
    ce = Core.from_expr(e)

    cond do
      range = Map.get(Map.get(ic, :ranges, %{}), ann) ->
        range_bind(name, ann, range, ce, env, ic)

      # a constant-of-literals value adopts the declared width — scalars, but also a
      # list literal adopting `Vec(W)` (and `if`/`case`/arith of literals), mirroring
      # the return-body path. It must still FIT the width's range (ADR-0064).
      lit_expr_adopts?(e, ann) ->
        lit_range_error(e, ann, name)

      # an integer literal does not silently become a float (ADR-0035 / ADR-0034 §1):
      # `x Float64 := 66` is a compile error even though `Int53 ⊑ Float64` is lossless —
      # write an explicit float. (The lossless int→float widening still applies to a
      # *typed* int value.)
      int_lit_expr?(ce) and float_type?(ann) ->
        {:error,
         "`#{name}`: an integer literal does not adopt the float type `#{ann}` — write an explicit float"}

      true ->
        t = infer(ce, env, ic)

        if assignable?(t, ann),
          do: nil,
          else: {:error, "`#{name}`: binding declared `#{ann}` but its value has type `#{t}`"}
    end
  end

  # A binding declared at a `range` type (ADR-0036). A *literal* of the matching
  # ordinal kind is checked **in-bounds at compile time** (`d Digit := 7` for
  # `0..9` passes; `:= 12` is a proven error). A non-literal value is allowed when
  # it is assignable to the base (representation-transparent) — but its bound is
  # not statically proven, so a runtime value should go through `Name.of(n)`,
  # which returns `Name | RangeError`.
  defp range_bind(name, ann, %{base: base, lo: lo, hi: hi}, ce, env, ic) do
    case literal_ordinal(ce, base) do
      {:ok, v} when v >= lo and v <= hi ->
        nil

      {:ok, v} ->
        {:error, "`#{name}`: literal #{v} is outside range `#{ann}` (#{lo}..#{hi})"}

      {:kind_mismatch, got} ->
        {:error, "`#{name}`: range `#{ann}` is over `#{base}`, but the literal is a `#{got}`"}

      :not_literal ->
        t = infer(ce, env, ic)

        if assignable?(resolve_range(t, ic), base),
          do: nil,
          else:
            {:error,
             "`#{name}`: value of type `#{t}` is not assignable to range `#{ann}` " <>
               "(base `#{base}`); use `#{ann}.of(n)` for a runtime value"}
    end
  end

  # the compile-time ordinal of a literal against a range's base, or why not:
  # an integer literal for an `Int64` base / a `Char` literal for a `Char` base;
  # `:kind_mismatch` when the literal is the wrong ordinal kind; `:not_literal`
  # for any non-literal RHS.
  defp literal_ordinal(%ENum{text: n}, "Int64") do
    if int_literal?(n),
      do: {:ok, n |> String.replace("_", "") |> String.to_integer()},
      else: :not_literal
  end

  defp literal_ordinal(%EUnary{op: "-", arg: %ENum{} = a}, "Int64") do
    case literal_ordinal(a, "Int64") do
      {:ok, v} -> {:ok, -v}
      other -> other
    end
  end

  defp literal_ordinal(%EChar{value: cp}, "Char"), do: {:ok, cp}
  defp literal_ordinal(%ENum{}, "Char"), do: {:kind_mismatch, "Int64"}
  defp literal_ordinal(%EChar{}, "Int64"), do: {:kind_mismatch, "Char"}
  defp literal_ordinal(_e, _base), do: :not_literal

  # A bare numeric literal adopts a *same-kind* numeric annotation (ADR-0034 §1):
  # an integer literal takes any `Int*`/`UInt*` width; a float literal takes any
  # `Float*`. Cross-kind (an integer literal into a `Float`) is *not* adopted —
  # write an explicit float literal — so it falls through to exact unification.
  defp literal_adopts?(%ENum{text: n}, ann),
    do: if(int_literal?(n), do: int_type?(ann), else: float_type?(ann))

  defp literal_adopts?(%EUnary{op: "-", arg: arg}, ann), do: literal_adopts?(arg, ann)
  defp literal_adopts?(_e, _ann), do: false

  # ── fixed-width literal range check (ADR-0064 soundness) ───────────────────
  # A constant integer literal adopting a fixed-width type must fit that width's
  # two's-complement range — `def f() Int8 := 9999` is a compile error (it would
  # wrap/truncate at runtime). Mirrors the ADR-0036 subrange check (`range_bind`).
  # `lit_range_error/3` takes a SURFACE expression + the declared type + the owner
  # name, and returns `{:error, msg}` for the first out-of-range literal in a
  # constant body (a bare/negated literal, a list element, or an `if`/`case`/block
  # branch), else `nil`. Arithmetic of literals is left to the runtime wrap
  # contract (a `wrapping_*` op), so it is not scanned.
  defp lit_range_error(expr, "Vec(" <> _ = type, name) do
    case Regex.run(~r/^Vec\((.+)\)$/, type) do
      [_, et] -> list_elems(expr) |> Enum.find_value(&lit_range_error(&1, et, name))
      _ -> nil
    end
  end

  defp lit_range_error(expr, type, name) do
    case width_bounds(type) do
      nil -> nil
      {lo, hi} -> oor_scan(expr, type, lo, hi, name)
    end
  end

  defp list_elems({:list_lit, elems, _}), do: elems
  defp list_elems({:block, [{:expr, e}]}), do: list_elems(e)
  defp list_elems(_), do: []

  defp oor_scan({:if, _c, t, e}, ty, lo, hi, n),
    do: oor_scan(t, ty, lo, hi, n) || oor_scan(e, ty, lo, hi, n)

  defp oor_scan({:case, _s, arms}, ty, lo, hi, n),
    do: Enum.find_value(arms, fn {_p, _g, b} -> oor_scan(b, ty, lo, hi, n) end)

  defp oor_scan({:block, [{:expr, e}]}, ty, lo, hi, n), do: oor_scan(e, ty, lo, hi, n)

  defp oor_scan(expr, ty, lo, hi, n) do
    case const_int(expr) do
      {:ok, v} when v < lo or v > hi ->
        {:error, "`#{n}`: literal #{v} is out of range for `#{ty}` (#{lo}..#{hi})"}

      _ ->
        nil
    end
  end

  defp const_int({:num, t}),
    do:
      if(int_literal?(t),
        do: {:ok, t |> String.replace("_", "") |> String.to_integer()},
        else: :no
      )

  defp const_int({:unary, "-", e}), do: with({:ok, v} <- const_int(e), do: {:ok, -v})
  defp const_int(_), do: :no

  # Two's-complement bounds for the fixed-width integer types; `nil` for the
  # arbitrary-precision `Int` (and any non-integer type) — no range to enforce.
  defp width_bounds("Int8"), do: {-128, 127}
  defp width_bounds("Int16"), do: {-32_768, 32_767}
  defp width_bounds("Int32"), do: {-2_147_483_648, 2_147_483_647}
  defp width_bounds("Int53"), do: {-9_007_199_254_740_991, 9_007_199_254_740_991}
  defp width_bounds("Int64"), do: {-9_223_372_036_854_775_808, 9_223_372_036_854_775_807}
  defp width_bounds("Int128"), do: {-Integer.pow(2, 127), Integer.pow(2, 127) - 1}
  defp width_bounds("UInt8"), do: {0, 255}
  defp width_bounds("UInt16"), do: {0, 65_535}
  defp width_bounds("UInt32"), do: {0, 4_294_967_295}
  defp width_bounds("UInt64"), do: {0, Integer.pow(2, 64) - 1}
  defp width_bounds("UInt128"), do: {0, Integer.pow(2, 128) - 1}
  defp width_bounds(_), do: nil

  defp int_literal?(n), do: not (String.contains?(n, ".") or String.match?(n, ~r/[eE]/))
  defp int_type?(t), do: is_binary(t) and String.match?(t, ~r/^U?Int\d*$/)
  defp float_type?(t), do: is_binary(t) and String.match?(t, ~r/^Float\d*$/)

  # ── lossless numeric widening (ADR-0034 §1 amendment) ──────────────────
  # Directional compatibility: may a value of type `from` stand where `to` is
  # declared? Equal / `:unknown` always; a numeric type **widens losslessly** to
  # a wider one; otherwise it must unify (Fn-structural, etc.) exactly. Widening
  # is one-directional — narrowing (`Int64 -> Int32`) stays a proven mismatch.
  defp assignable?(t, t), do: true
  defp assignable?(:unknown, _to), do: true
  defp assignable?(_from, :unknown), do: true

  defp assignable?(from, to) do
    case {num_kind(from), num_kind(to)} do
      {nil, _} -> unify(from, to) != :mismatch
      {_, nil} -> unify(from, to) != :mismatch
      {a, b} -> num_widens?(a, b)
    end
  end

  # a numeric type string -> {:int | :uint | :float, bit-width}, else nil
  defp num_kind("UInt" <> w), do: num_bits(:uint, w)
  defp num_kind("Int" <> w), do: num_bits(:int, w)
  defp num_kind("Float" <> w), do: num_bits(:float, w)
  defp num_kind(_), do: nil

  defp num_bits(kind, w) do
    case Integer.parse(w) do
      {n, ""} -> {kind, n}
      _ -> nil
    end
  end

  # `from ⊑ to` — lossless widening:
  #   Intₐ ⊑ Int_b / UIntₐ ⊑ UInt_b   for a ≤ b   (same signedness, wider)
  #   UIntₐ ⊑ Int_b                    for a < b   (unsigned range fits signed)
  #   Intₐ ⊑ Float_b   when |2^(a-1)| is exactly representable (a-1 ≤ mantissa)
  #   UIntₐ ⊑ Float_b  when 2^a-1 is exactly representable (a ≤ mantissa)
  #   Floatₐ ⊑ Float_b                 for a ≤ b
  defp num_widens?({:int, a}, {:int, b}), do: a <= b
  defp num_widens?({:uint, a}, {:uint, b}), do: a <= b
  defp num_widens?({:uint, a}, {:int, b}), do: a < b
  defp num_widens?({:int, a}, {:float, b}), do: a - 1 <= float_mantissa(b)
  defp num_widens?({:uint, a}, {:float, b}), do: a <= float_mantissa(b)
  defp num_widens?({:float, a}, {:float, b}), do: a <= b
  defp num_widens?(_, _), do: false

  # exact-integer mantissa bits: f64 is exact to 2^53, f32 to 2^24
  defp float_mantissa(64), do: 53
  defp float_mantissa(32), do: 24
  defp float_mantissa(_), do: 0

  # ── join: least-upper-bound for branch/arm/element types (ADR-0059) ─────
  # Combine the types of two branches that both execute-or-not (the arms of an
  # `if`, the arms of a `case`, the elements of a list) into the single type of
  # the surrounding expression. This is NOT `unify/2`: there `:unknown` is a
  # wildcard that adopts the other side (matching a partial inference against a
  # declaration); here `:unknown` is ABSORBING (top), so an uninferable arm
  # poisons the join and `node.type` never over-claims. `:bottom` is the fold
  # identity (the empty set of branches). Commutative and associative.
  @doc false
  @spec join(ty(), ty()) :: ty()
  def join(t, t), do: t
  def join(:bottom, t), do: t
  def join(t, :bottom), do: t
  def join(:unknown, _), do: :unknown
  def join(_, :unknown), do: :unknown

  def join(from, to) do
    case {num_kind(from), num_kind(to)} do
      {a, b} when a != nil and b != nil -> num_join(a, b)
      _ -> parametric_join(from, to)
    end
  end

  # numeric LUB over the `⊑` order (`num_widens?`): the least width/kind that
  # contains both, or `:unknown` when none exists in the vocabulary.
  @int_widths [8, 16, 32, 64, 128]
  @float_widths [32, 64]

  defp num_join({k, a}, {k, b}) when is_integer(a) and is_integer(b),
    do: "#{kind_prefix(k)}#{max(a, b)}"

  defp num_join({:uint, a}, {:int, b}), do: uint_signed_join(a, b)
  defp num_join({:int, a}, {:uint, b}), do: uint_signed_join(b, a)
  defp num_join({:int, a}, {:float, b}), do: int_float_join(a - 1, b)
  defp num_join({:float, b}, {:int, a}), do: int_float_join(a - 1, b)
  defp num_join({:uint, a}, {:float, b}), do: int_float_join(a, b)
  defp num_join({:float, b}, {:uint, a}), do: int_float_join(a, b)

  defp kind_prefix(:int), do: "Int"
  defp kind_prefix(:uint), do: "UInt"
  defp kind_prefix(:float), do: "Float"

  # `UIntₐ ⊔ Int_b` = least Int width strictly wider than `a` (to hold the
  # unsigned range) and at least `b`; none ⇒ `:unknown`.
  defp uint_signed_join(u, i) do
    case Enum.find(@int_widths, fn c -> c > u and c >= i end) do
      nil -> :unknown
      c -> "Int#{c}"
    end
  end

  # `Int/UInt ⊔ Float` = least Float width ≥ the float operand whose mantissa
  # holds the integer exactly (`exact_bits`); none ⇒ `:unknown`.
  defp int_float_join(exact_bits, fb) do
    case Enum.find(@float_widths, fn c -> c >= fb and float_mantissa(c) >= exact_bits end) do
      nil -> :unknown
      c -> "Float#{c}"
    end
  end

  # function types are NOT covariantly joined: argument positions are
  # *contravariant*, so widening an arg (`Fn(Int32,R) ⊔ Fn(Int64,R) → Fn(Int64,R)`)
  # would let a caller pass an `Int64` the `Int32` arm cannot accept — unsound.
  # Differing `Fn`s join to `:unknown` (equal ones are caught by `join(t, t)`).
  defp parametric_join("Fn(" <> _, _), do: :unknown
  defp parametric_join(_, "Fn(" <> _), do: :unknown

  # same-constructor covariant join: `Vec(A) ⊔ Vec(B) = Vec(A⊔B)`,
  # `Option(A) ⊔ Option(B) = Option(A⊔B)`, componentwise for any `Name(args)`.
  # Different constructors / non-parametric differing types ⇒ `:unknown` — the
  # lattice never promotes across constructors (ADR-0035, ADR-0059 §4).
  defp parametric_join(from, to) do
    with {n, fa} when is_list(fa) <- parse_parametric(from),
         {^n, ta} when length(ta) == length(fa) <- parse_parametric(to) do
      parts = Enum.zip(fa, ta) |> Enum.map(fn {x, y} -> join(x, y) end)
      if :unknown in parts, do: :unknown, else: "#{n}(#{Enum.join(parts, ",")})"
    else
      _ -> :unknown
    end
  end

  # "Vec(Int64)" -> {"Vec", ["Int64"]}; "Result(A,E)" -> {"Result", ["A","E"]};
  # a non-parametric type -> `:error`. (`split_top_commas/1` — the existing
  # paren-aware splitter — keeps a nested `Vec(B,C)` as one component.)
  defp parse_parametric(s) when is_binary(s) do
    case Regex.run(~r/^([A-Za-z_]\w*)\((.*)\)$/, s) do
      [_, name, inner] -> {name, split_top_commas(inner)}
      _ -> :error
    end
  end

  defp parse_parametric(_), do: :error

  # a leftover `:bottom` (empty branch set) surfaces as `:unknown` to callers.
  defp debottom(:bottom), do: :unknown
  defp debottom(t), do: t

  defp check_return(%Func{name: name, params: ps, ret: ret, tvars: tvars, clauses: clauses}, ic) do
    # A return type mentioning a `forall` type variable is generic; we don't yet
    # unify type variables structurally, so such a function is checked
    # conservatively (its body is not contradicted). Concrete returns are checked.
    if generic_ret?(ret, tvars) do
      :ok
    else
      Enum.find_value(clauses, :ok, fn c ->
        body_ast = Pratt.parse_body(c.body)
        body_t = infer(body_ast, clause_env(c.pats, ps, ic), ic)

        cond do
          # a constant-of-literals body adopts the declared width — but it must FIT
          # the width's range (`def f() Int8 := 9999` is rejected, ADR-0064)
          body_literal_adopts?(body_ast, ret) ->
            lit_range_error(body_ast, ret, name)

          assignable?(body_t, ret) ->
            nil

          true ->
            {:error,
             "`#{name}`: body has type `#{body_t}` but the declared return type is `#{ret}`"}
        end
      end)
    end
  end

  # A clause whose body is a *constant numeric expression of literals* adopts the
  # declared integer/float return *width*, exactly as a typed binding does
  # (`literal_adopts?`). "Constant of literals" includes a bare literal
  # (`count([]) := 0`), a negation/arithmetic of literals (`sign := … 0 - 1 …`),
  # and an `if`/`case` *all* of whose branches are such (`sign := if … 1 … 0`).
  # Without this a literal infers the default `Int64` and spuriously clashes with an
  # `Int53`/`Int32` return — so a function returning the portable `Int53` could not
  # have a literal base case or a literal `if`-chain (ADR-0064). It only *relaxes*
  # the return check (an OR with `assignable?`), so it cannot reject valid code.
  defp body_literal_adopts?({:block, [{:expr, e}]}, ret), do: lit_expr_adopts?(e, ret)
  defp body_literal_adopts?(_ast, _ret), do: false

  defp lit_expr_adopts?({:if, _c, t, e}, ret),
    do: lit_expr_adopts?(t, ret) and lit_expr_adopts?(e, ret)

  defp lit_expr_adopts?({:case, _s, arms}, ret),
    do: arms != [] and Enum.all?(arms, fn {_p, _g, b} -> lit_expr_adopts?(b, ret) end)

  defp lit_expr_adopts?({:block, [{:expr, e}]}, ret), do: lit_expr_adopts?(e, ret)

  defp lit_expr_adopts?({:bin, op, l, r}, ret) when op in ~w(+ - * div rem),
    do: lit_expr_adopts?(l, ret) and lit_expr_adopts?(r, ret)

  # a closed list literal of constant elements adopts `Vec(ElemT)` — every element
  # adopts the element type (`[2, 3, 5, 7] : Vec(Int53)`, ADR-0064).
  defp lit_expr_adopts?({:list_lit, elems, nil}, ret) do
    case Regex.run(~r/^Vec\((.+)\)$/, ret) do
      [_, et] -> Enum.all?(elems, &lit_expr_adopts?(&1, et))
      _ -> false
    end
  end

  defp lit_expr_adopts?(e, ret), do: literal_adopts?(Core.from_expr(e), ret)

  defp generic_ret?(_ret, []), do: false
  defp generic_ret?(ret, tvars), do: Enum.any?(tvars, &Regex.match?(~r/\b#{&1}\b/, ret))

  # ADR-0040 §4: a `T | E` return type declares the error set `E`; the function's
  # *produced* set — the tags it builds directly **plus** the error sets it
  # propagates from callees (a `with`-clause source whose error isn't handled by
  # an `else`) — must be a subset of `E`. The propagated part is read from `table`
  # (the call-graph fixpoint, `solve_error_sets/2`). Non-`Result` returns are
  # unconstrained here.
  defp check_error_set(%Func{ret: ret} = f, %{tsets: tsets, table: table}) do
    case declared_set(ret, tsets) do
      nil ->
        :ok

      {err_t, declared} ->
        case MapSet.difference(produced_set(f, table), declared) |> MapSet.to_list() do
          [] ->
            :ok

          extra ->
            {:error,
             "`#{f.name}`: returns error(s) #{inspect(extra)} not in its declared set `#{err_t}`"}
        end
    end
  end

  defp check_error_set(_f, _eset), do: :ok

  # `T | E` -> `{E, MapSet of E's tags}` (a named `E` expands to its variants); else nil.
  defp declared_set(ret, tsets) do
    case String.split(ret, "|") |> Enum.map(&String.trim/1) do
      [ok_t, err_t] when ok_t != "" -> {err_t, MapSet.new(Map.get(tsets, err_t, [err_t]))}
      _ -> nil
    end
  end

  # the tags a function actually produces: directly-built `{:error, Tag}` ∪ the
  # error sets of the callees whose errors it propagates (from `table`)
  defp produced_set(f, table) do
    propagated =
      f
      |> propagated_callees()
      |> Enum.reduce(MapSet.new(), fn c, acc ->
        MapSet.union(acc, Map.get(table, c, MapSet.new()))
      end)

    MapSet.union(direct_tags(f), propagated)
  end

  defp direct_tags(f) do
    f.clauses
    |> Enum.flat_map(fn c -> c.body |> Pratt.parse_body() |> error_tags() end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp propagated_callees(f),
    do: f.clauses |> Enum.flat_map(fn c -> c.body |> Pratt.parse_body() |> with_callees() end)

  # Solve every function's error set by call-graph fixpoint: a function with a
  # declared `E` exposes exactly `E` (the contract boundary); an unannotated one
  # infers `direct ∪ ⋃ callee-set`, iterated until stable (sets only grow).
  defp solve_error_sets(funcs, tsets) do
    facts =
      Map.new(funcs, fn f ->
        declared = with({_e, set} <- declared_set(f.ret, tsets), do: set, else: (_ -> nil))
        {f.name, %{direct: direct_tags(f), callees: propagated_callees(f), declared: declared}}
      end)

    fixpoint(facts, Map.new(facts, fn {n, fc} -> {n, fc.declared || fc.direct} end))
  end

  defp fixpoint(facts, table) do
    next =
      Map.new(facts, fn
        {n, %{declared: d}} when not is_nil(d) ->
          {n, d}

        {n, %{direct: direct, callees: callees}} ->
          {n, Enum.reduce(callees, direct, &MapSet.union(&2, Map.get(table, &1, MapSet.new())))}
      end)

    if next == table, do: table, else: fixpoint(facts, next)
  end

  # Collect the tag names of every `{:error, Tag}` constructed in an expression.
  defp error_tags({:tuple, [{:atom, "error"}, e]}), do: [tag_name(e) | error_tags(e)]
  defp error_tags(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.flat_map(&error_tags/1)
  defp error_tags(l) when is_list(l), do: Enum.flat_map(l, &error_tags/1)
  defp error_tags(_), do: []

  # Names of functions whose errors propagate: a `with`-clause source `f(…)` when
  # the `with` has NO `else` (an `else` is taken to handle the clause errors —
  # conservative; a re-raising `else` only under-approximates, never over-).
  defp with_callees({:with, clauses, body, []}) do
    Enum.flat_map(clauses, fn {_p, src} -> call_name(src) end) ++
      with_callees(body) ++ Enum.flat_map(clauses, fn {_p, s} -> with_callees(s) end)
  end

  defp with_callees(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.flat_map(&with_callees/1)

  defp with_callees(l) when is_list(l), do: Enum.flat_map(l, &with_callees/1)
  defp with_callees(_), do: []

  defp call_name({:call, {:id, n}, _}), do: [n]
  # A module-/protocol-qualified call `M.f(…)` propagates `f`'s error set too: the
  # call-graph table is keyed by *bare* name (`solve_error_sets` flattens module
  # funcs), so extracting the method name is consistent with how callees are stored.
  # A truly external dot-call (`String.upcase`) names no local function -> the
  # `table` lookup is empty -> harmless no-op (no false propagation). Without this
  # clause an error routed through a qualified call silently escaped the declared
  # set (ADR-0040 §4 soundness hole).
  defp call_name({:call, {:dot, _, n}, _}), do: [n]
  defp call_name(_), do: []

  # An error tag is a PascalCase constructor (`NotFound`, `DivByZero(…)`). A
  # lowercase identifier in error position is a *bound variable* re-propagating an
  # existing error (`{:error, e} -> {:error, e}`), not a newly-constructed tag.
  defp tag_name({:id, n}), do: if(pascal?(n), do: n)
  defp tag_name({:call, {:id, n}, _}), do: if(pascal?(n), do: n)
  defp tag_name(_), do: nil

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  # Bind names introduced by the clause head, narrowing constructor patterns
  # against their parameter type (flow narrowing applies to clause heads too —
  # a clause head is a one-arm `case` on the parameters).
  @doc """
  The typing environment (`name -> type`) for a clause: each clause-head pattern
  flow-narrowed against its parameter's declared type. Public so the emitters can
  build the same per-clause env the checker uses, to annotate the typed Core IR
  (ADR-0050 §3).
  """
  @spec clause_env([term()], [map()], map()) :: map()
  def clause_env(pats, params, ic) do
    pats
    |> Enum.zip(params)
    |> Enum.reduce(%{}, fn {pat, param}, env ->
      narrow(Core.from_pat(pat), param.type, ic, env)
    end)
  end

  @doc """
  Infer a private function's RETURN type from its clause bodies — the join of each
  clause's inferred body type, given the inference context `ic` (`program_ic/1`).

  Returns a concrete type string, or `:unknown` when no clause pins it (a clause
  inferring `:unknown`/`:mismatch`, or branches that don't join). Sound by
  construction: a concrete result means *every* clause inferred concretely and they
  agree under `join`. This is the engine behind `Rian.InferLocal` filling the return
  of an untyped private function (infer-local / declare-public, ADR-0034).
  """
  @spec infer_return_type(Rian.IR.Func.t(), map()) :: String.t() | :unknown
  def infer_return_type(%Func{params: ps, clauses: clauses, tvars: tvs}, ic) do
    types =
      Enum.map(clauses, fn c ->
        env = c.pats |> clause_env(ps, ic) |> bind_tvar_params(c.pats, ps, tvs)
        infer(Pratt.parse_body(c.body), env, ic)
      end)

    if Enum.any?(types, &(&1 in [:unknown, :mismatch, :bottom])) do
      :unknown
    else
      case join_all(types) do
        t when is_binary(t) -> t
        _ -> :unknown
      end
    end
  end

  # `clause_env` concretizes a generic param's tvar to `:unknown` (it doesn't
  # instantiate generics). For a function's OWN type variables, though, the body must
  # see the parameter AS its tvar so a pass-through (`def id(x) := x`, auto-generalized
  # to `forall T`) can infer the return `T`. Re-bind each var-pattern param whose type
  # is one of `tvs` to that tvar string.
  defp bind_tvar_params(env, pats, ps, tvs) do
    pats
    |> Enum.zip(ps)
    |> Enum.reduce(env, fn {pat, p}, env ->
      case Core.from_pat(pat) do
        %PVar{name: vn} -> if p.type in tvs, do: Map.put(env, vn, p.type), else: env
        _ -> env
      end
    end)
  end

  @doc """
  Infer a private function parameter's type at position `i`, bidirectionally
  (Dunfield–Krishnaswami "checking", realized locally): an arithmetic/compare
  operator, a string concat, or a typed callee parameter pushes its *expected* type
  onto the variable flowing into it; a literal/ctor clause-head pattern constrains the
  scrutinee directly. Returns a concrete type string; `:unknown` when nothing
  constrains the parameter (a parametric/pass-through use — `Rian.InferLocal`
  generalizes it to `forall T`); `:mismatch` on a provable conflict (the parameter
  used at two incompatible types). The engine behind private *parameter* inference
  (infer-local / declare-public, ADR-0034).
  """
  @spec infer_param_type(Rian.IR.Func.t(), non_neg_integer(), map()) :: ty()
  def infer_param_type(%Func{params: ps, clauses: clauses}, i, ic) do
    Enum.reduce(clauses, :unknown, fn c, acc ->
      ct =
        case c.pats |> Enum.at(i) |> Core.from_pat() do
          %PVar{name: vn} ->
            var_constraint(
              vn,
              Core.from_expr(Pratt.parse_body(c.body)),
              clause_env(c.pats, ps, ic),
              ic
            )

          other ->
            pattern_type(other, ic)
        end

      fold_constraint(acc, ct)
    end)
  end

  # the type a clause-head pattern requires of its scrutinee (the parameter).
  defp pattern_type(%PLit{value: v}, _ic) when is_integer(v), do: "Int53"
  defp pattern_type(%PLit{value: v}, _ic) when is_binary(v), do: "String"
  defp pattern_type(%PChar{}, _ic), do: "Char"
  defp pattern_type(%PCtor{ctor: c}, ic), do: ctor_type(ic, c) || :unknown
  defp pattern_type(_pat, _ic), do: :unknown

  # unify two parameter-type constraints: `:unknown` is the identity (no information),
  # a concrete type wins, two differing concretes conflict (`:mismatch`).
  defp fold_constraint(:unknown, t), do: t
  defp fold_constraint(t, :unknown), do: t
  defp fold_constraint(:mismatch, _), do: :mismatch
  defp fold_constraint(_, :mismatch), do: :mismatch
  defp fold_constraint(a, b), do: conservative(unify(a, b)) |> nilable_mismatch(a, b)

  # `unify` returns `:mismatch` on a real clash, but `conservative` softens it to
  # `:unknown`. For parameter inference a clash IS the signal, so restore it.
  defp nilable_mismatch(:unknown, a, b) when a != b and is_binary(a) and is_binary(b),
    do: :mismatch

  defp nilable_mismatch(t, _a, _b), do: t

  # Collect the type the body forces on variable `name` (bidirectional "expected type
  # in"): an arithmetic/compare operator, a string concat, or a typed callee parameter
  # constrains the variable flowing into it. Recurses through compound expressions.
  defp var_constraint(name, %EBin{op: op, left: l, right: r}, env, ic) do
    here =
      cond do
        op == "<>" and (var?(l, name) or var?(r, name)) -> "String"
        (op in @arith or op in @int_ops) and var?(l, name) -> num_hint(infer(r, env, ic))
        (op in @arith or op in @int_ops) and var?(r, name) -> num_hint(infer(l, env, ic))
        op in @bool_ops and var?(l, name) -> concretize(infer(r, env, ic))
        op in @bool_ops and var?(r, name) -> concretize(infer(l, env, ic))
        true -> :unknown
      end

    [here, var_constraint(name, l, env, ic), var_constraint(name, r, env, ic)]
    |> Enum.reduce(:unknown, fn c, acc -> fold_constraint(acc, c) end)
  end

  defp var_constraint(name, %ECall{fun: %EId{name: f}, args: as}, env, ic) do
    sig = Map.get(Map.get(ic, :fsigs, %{}), f)

    from_callee =
      if sig do
        as
        |> Enum.with_index()
        |> Enum.reduce(:unknown, fn {a, i}, acc ->
          if var?(a, name),
            do: fold_constraint(acc, concretize(Enum.at(sig.params, i, :unknown))),
            else: acc
        end)
      else
        :unknown
      end

    Enum.reduce(as, from_callee, fn a, acc ->
      fold_constraint(acc, var_constraint(name, a, env, ic))
    end)
  end

  defp var_constraint(name, %ECall{args: as}, env, ic),
    do:
      Enum.reduce(as, :unknown, fn a, acc ->
        fold_constraint(acc, var_constraint(name, a, env, ic))
      end)

  defp var_constraint(name, %EUnary{arg: a}, env, ic), do: var_constraint(name, a, env, ic)

  defp var_constraint(name, %EIf{cond: c, then: t, else: e}, env, ic),
    do:
      Enum.reduce([c, t, e], :unknown, fn n, acc ->
        fold_constraint(acc, var_constraint(name, n, env, ic))
      end)

  defp var_constraint(name, %EBlock{stmts: ss}, env, ic) do
    Enum.reduce(ss, :unknown, fn
      {:expr, e}, acc -> fold_constraint(acc, var_constraint(name, e, env, ic))
      {:bind, _n, e}, acc -> fold_constraint(acc, var_constraint(name, e, env, ic))
      {:typed_bind, _n, _t, e}, acc -> fold_constraint(acc, var_constraint(name, e, env, ic))
      _, acc -> acc
    end)
  end

  defp var_constraint(name, %ECase{scrut: s, arms: arms}, env, ic) do
    # `case x do <pat> -> …` — when the scrutinee IS the variable, each arm's head
    # pattern constrains it (a literal/ctor arm pins the type; conflicting arms clash).
    from_scrut =
      if var?(s, name) do
        Enum.reduce(arms, :unknown, fn {p, _g, _b}, acc ->
          fold_constraint(acc, pattern_type(p, ic))
        end)
      else
        :unknown
      end

    Enum.reduce(arms, fold_constraint(from_scrut, var_constraint(name, s, env, ic)), fn {_p, _g,
                                                                                         body},
                                                                                        acc ->
      fold_constraint(acc, var_constraint(name, body, env, ic))
    end)
  end

  defp var_constraint(name, %EList{elems: es}, env, ic),
    do:
      Enum.reduce(es, :unknown, fn e, acc ->
        fold_constraint(acc, var_constraint(name, e, env, ic))
      end)

  defp var_constraint(_name, _leaf, _env, _ic), do: :unknown

  # an arithmetic neighbour's type pins the variable when it is a concrete integer,
  # else the portable default `Int53` (a bare `x + 1` makes `x : Int53`, ADR-0064).
  defp num_hint(t) when is_binary(t), do: if(int_type?(t), do: ordinal_base(t), else: :unknown)
  defp num_hint(_), do: "Int53"

  defp var?(%EId{name: n}, n), do: true
  defp var?(_, _), do: false

  @doc "Parse source and check every function; returns `:ok` or the first `{:error, message}`."
  @spec check(String.t()) :: term()
  def check(src), do: src |> Rian.Decl.parse() |> check_program()

  @doc """
  Check every function in a parsed program — top-level and inside every module.
  Returns `:ok` or the first `{:error, message}`.
  """
  @spec check_program(map()) :: term()
  def check_program(%{funcs: funcs} = prog) do
    ic = program_ic(prog)
    all_funcs = funcs ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)
    tsets = error_sets(all_types(prog))
    eset = %{tsets: tsets, table: solve_error_sets(all_funcs, tsets)}
    Enum.find_value(all_funcs, :ok, fn f -> with :ok <- check_func(f, ic, eset), do: nil end)
  end

  @doc """
  Build the inference context (`:tdefs`/`:funs`/`:ctors`) for a parsed program.

  Exposed so callers that only need *inference* — notably `Rian.Repl`, which
  threads session declarations into expression typing — can reuse the same
  context-building rules as `check_program/1` without re-running the checker.
  """
  @spec program_ic(map()) :: %{
          tdefs: map(),
          funs: map(),
          fsigs: map(),
          ctors: map(),
          ranges: map(),
          opaques: map(),
          impls: map(),
          fbounds: map()
        }
  @spec program_ic(map()) :: map()
  def program_ic(%{} = prog) do
    types = all_types(prog)

    all_funcs =
      Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    %{
      tdefs: type_table(types),
      funs: Map.new(all_funcs, fn f -> {f.name, f.ret} end),
      fsigs: Map.new(all_funcs, fn f -> {f.name, fsig(f)} end),
      ctors: ctor_types(types, prog),
      ranges: range_table(prog),
      opaques: opaque_table(prog),
      impls: impl_table(prog),
      fbounds: fbound_table(all_funcs)
    }
  end

  # protocol name -> the set of types that `impl` it (ADR-0042 §2), from the
  # program's preserved `impls` facts.
  defp impl_table(prog) do
    Map.get(prog, :impls, [])
    |> Enum.reduce(%{}, fn {proto, type}, acc ->
      Map.update(acc, proto, MapSet.new([type]), &MapSet.put(&1, type))
    end)
  end

  # bounded generics only: function name -> %{params, tvars, bounds}, consulted at
  # call sites to instantiate a tvar and check its protocol bound.
  defp fbound_table(funcs) do
    for f <- funcs, f.bounds != %{}, into: %{} do
      {f.name, %{params: Enum.map(f.params, & &1.type), tvars: f.tvars, bounds: f.bounds}}
    end
  end

  # `range Name := lo..hi` (ADR-0036) records, keyed by name -> %{base, lo, hi}.
  # A range is *representation, not newtype*: its base (`Int64`/`Char`) is what it
  # unifies as; the `lo..hi` bound is what a literal binding is checked against.
  defp range_table(prog) do
    ranges =
      Map.get(prog, :ranges, []) ++
        for(m <- Map.get(prog, :mods, []), r <- Map.get(m, :ranges, []), do: r)

    Map.new(ranges, fn r -> {r.name, %{base: r.base, lo: r.lo, hi: r.hi}} end)
  end

  # `opaque Name := Base` (ADR-0067/ADR-0043) records, keyed by name -> %{base}.
  # Unlike a `range`, an opaque is *nominal*: it does NOT resolve to its base in
  # type positions (that distinctness is the whole point). Its only checker effect
  # is the total `Name.of(x)` constructor (`x : Base -> Name`) below.
  defp opaque_table(prog) do
    opaques =
      Map.get(prog, :opaques, []) ++
        for(m <- Map.get(prog, :mods, []), o <- Map.get(m, :opaques, []), do: o)

    Map.new(opaques, fn o ->
      {o.name, %{base: o.base, ops: Map.get(o, :ops, []), casts: Map.get(o, :casts, [])}}
    end)
  end

  # The declared return type of an `abstract` operator (ADR-0067) matching `op` with
  # operands of types `lt`/`rt`, or nil if no abstract overloads this operator for
  # these operands. Scans every abstract's `ops`; the first match wins.
  defp abstract_op_type(op, lt, rt, ic) do
    ic
    |> Map.get(:opaques, %{})
    |> Enum.find_value(fn {_name, info} ->
      Enum.find_value(Map.get(info, :ops, []), fn
        %{op: ^op, params: [p1, p2], ret: ret} ->
          if assignable?(lt, p1) and assignable?(rt, p2), do: ret

        _ ->
          nil
      end)
    end)
  end

  # The return type of an `abstract` cast named `cn` on a value of type `ht`, or nil
  # if `ht` is not an abstract with such a cast (ADR-0067 §2).
  defp abstract_cast_ret(ht, cn, ic) do
    case Map.get(Map.get(ic, :opaques, %{}), ht) do
      %{casts: casts} ->
        Enum.find_value(casts, fn
          %{name: ^cn, ret: ret} -> ret
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  # the ordinal base of a `range` named `n`, or nil if `n` is not a range
  defp range_base(ic, n) do
    case Map.get(Map.get(ic, :ranges, %{}), n) do
      %{base: base} -> base
      _ -> nil
    end
  end

  # a range name resolves to its base type; any other type is unchanged
  defp resolve_range(t, ic) do
    case Map.get(Map.get(ic, :ranges, %{}), t) do
      %{base: base} -> base
      _ -> t
    end
  end

  # The parts of a function signature `instantiate_ret/2` needs: parameter type
  # strings (in order), the declared return, and the function's `forall` type
  # variables. Stored alongside `:funs` so the simpler `name -> ret` map remains
  # the public surface for non-generic call inference (and the public test
  # contract — see `Check.infer/3`'s `ic` shape).
  defp fsig(f) do
    %{
      params: Enum.map(f.params, & &1.type),
      ret: f.ret,
      tvars: f.tvars
    }
  end

  # ctor name -> the sum type it builds (so a variant value/call infers its type);
  # struct names map to themselves (a struct constructor builds its own type).
  defp ctor_types(types, prog) do
    structs =
      Map.get(prog, :structs, []) ++ for(m <- Map.get(prog, :mods, []), s <- m.structs, do: s)

    from_variants = for t <- types, v <- t.variants, into: %{}, do: {v.ctor, t.name}
    Enum.reduce(structs, from_variants, fn s, acc -> Map.put(acc, s.name, s.name) end)
  end

  defp all_types(prog) do
    Rian.Prelude.with_prelude(
      Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)
    )
  end

  # Constructor table for flow narrowing: every sum-type variant mapped to its
  # ordered field types.
  defp type_table(types) do
    for t <- types, v <- t.variants, into: %{} do
      {v.ctor, Enum.map(v.fields, & &1.type)}
    end
  end

  # Error-set table (ADR-0040 §4): a sum type's name -> its tag (variant) names,
  # so a declared `T | E` can be expanded when `E` is a named set.
  defp error_sets(types) do
    for t <- types, into: %{} do
      {t.name, Enum.map(t.variants, & &1.ctor)}
    end
  end

  @doc "The compile-time type gate: raise `Rian.Check.Error` on a proven mismatch, else `:ok`."
  @spec gate!(map()) :: :ok
  def gate!(prog) do
    case check_program(prog) do
      :ok -> :ok
      {:error, msg} -> raise Error, msg
    end
  end
end
