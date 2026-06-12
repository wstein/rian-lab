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
  alias Rian.Core.{EBin, EBlock, ECall, ECase, EId, EIf, EList, ENum, EStr, ETuple, EUnary, EWith}
  alias Rian.Core.{ECaptureNamed, ELambda}
  alias Rian.Core.{PCtor, PVar}
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
      true -> :mismatch
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
  def infer(ast, env \\ %{}, ic \\ %{})
  def infer(ast, env, ic) when is_tuple(ast), do: infer(Core.from_expr(ast), env, ic)

  def infer(%ENum{text: n}, _env, _ic),
    do: if(String.contains?(n, ".") or String.match?(n, ~r/[eE]/), do: "Float64", else: "Int64")

  def infer(%EStr{}, _env, _ic), do: "String"
  def infer(%EId{name: b}, _env, _ic) when b in ~w(true false), do: "Bool"
  # a name resolves to a bound var, else a nullary variant constructor, else unknown
  def infer(%EId{name: x}, env, ic), do: Map.get(env, x) || ctor_type(ic, x) || :unknown
  def infer(%EUnary{op: "-", arg: x}, env, ic), do: infer(x, env, ic)
  def infer(%EUnary{op: "not"}, _env, _ic), do: "Bool"

  def infer(%EBin{op: op, left: l, right: r}, env, ic) do
    cond do
      op in @bool_ops -> "Bool"
      op == "<>" -> "String"
      op == "/" -> "Float64"
      op in @int_ops -> "Int64"
      op in @arith -> conservative(unify(infer(l, env, ic), infer(r, env, ic)))
      true -> :unknown
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
  def infer(%ECall{fun: %EId{name: f}, args: as}, env, ic) do
    cond do
      fn_type?(ft = Map.get(env, f)) -> fn_ret(ft)
      true -> ctor_type(ic, f) || called_ret_with(ic, f, as, env)
    end
  end

  # a call to any other callable (a lambda result, a returned function) infers
  # its return type when the callee is known to be a function, else `:unknown`
  def infer(%ECall{fun: fun}, env, ic) do
    ft = infer(fun, env, ic)
    if fn_type?(ft), do: fn_ret(ft), else: :unknown
  end

  def infer(%EIf{then: t, else: e}, env, ic),
    do: conservative(unify(infer(t, env, ic), infer(e, env, ic)))

  # `case` — flow narrowing: each arm body is inferred under an env where the
  # arm pattern's bindings are refined against the scrutinee's type. The case's
  # type is the unification of all arm bodies (conservative on mismatch).
  def infer(%ECase{scrut: scrut, arms: arms}, env, ic) do
    st = infer(scrut, env, ic)

    arms
    |> Enum.map(fn {pat, _guard, body} -> infer(body, narrow(pat, st, ic, env), ic) end)
    |> Enum.reduce(:unknown, fn t, acc -> conservative(unify(acc, t)) end)
  end

  # a list literal infers `Vec(T)` (the family list type) when its elements — and
  # any cons tail — agree on a concrete element type `T`; else `:unknown`
  def infer(%EList{elems: elems, tail: tail}, env, ic) do
    elem_t =
      elems
      |> Enum.map(&infer(&1, env, ic))
      |> Enum.reduce(:unknown, &conservative(unify(&1, &2)))

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
  def annotate(ast, env \\ %{}, ic \\ %{})
  def annotate(ast, env, ic) when is_tuple(ast), do: annotate(Core.from_expr(ast), env, ic)

  def annotate(%t{} = n, env, ic) when t in [ENum, EStr, EId],
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

    if Enum.all?(tvars, &Map.has_key?(subs, &1)) do
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
  defp split_top_commas(s) do
    {parts, cur, _} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ",", {parts, cur, 0} -> {[cur | parts], "", 0}
        "(", {parts, cur, d} -> {parts, cur <> "(", d + 1}
        ")", {parts, cur, d} -> {parts, cur <> ")", d - 1}
        ch, {parts, cur, d} -> {parts, cur <> ch, d}
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1)
  end

  defp infer_block([], _env, _ic, value), do: value

  defp infer_block([{:bind, n, e} | rest], env, ic, _value) do
    t = infer(e, env, ic)
    infer_block(rest, Map.put(env, n, t), ic, t)
  end

  # a typed binding binds `n` at its *declared* type (ADR-0034 §1); enforcement
  # that the value fits the annotation is the gate's job (`check_binds/2`).
  defp infer_block([{:typed_bind, n, t, _e} | rest], env, ic, _value),
    do: infer_block(rest, Map.put(env, n, t), ic, t)

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
  defp concretize(t), do: t
  defp tvar?(t), do: String.match?(t, ~r/^[A-Z][0-9]?$/)

  # a mismatch deep in arithmetic stays conservative (we do not model coercion
  # fully yet) rather than rejecting; only the body-vs-return check rejects
  defp conservative(:mismatch), do: :unknown
  defp conservative(t), do: t

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
  def check_func(func, ic \\ %{}, eset \\ %{tsets: %{}, table: %{}})

  def check_func(%Func{} = f, ic, eset) do
    with :ok <- check_return(f, ic),
         :ok <- check_binds(f, ic),
         do: check_error_set(f, eset)
  end

  @doc """
  Check one typed binding's RHS against its declared type (ADR-0034 §1) — the
  same bidirectional rule the function-body gate applies, exposed for surfaces
  (the REPL) to enforce a top-level `name Type := expr`. `rhs` is the surface or
  core RHS expression. Returns `:ok` (well-typed, or unprovable) or
  `{:error, message}` on a proven clash blamed at the binding site.
  """
  @spec check_bind(String.t(), String.t(), term(), map(), map()) ::
          :ok | {:error, String.t()}
  def check_bind(name, ann, rhs, env \\ %{}, ic \\ %{}) do
    case bind_mismatch(name, ann, rhs, env, ic) do
      nil -> :ok
      {:error, _} = err -> err
    end
  end

  # ADR-0034 §1 — typed bindings. `x T := e` checks `e` against the declared type
  # `T`: a numeric *literal* adopts `T` (bidirectional checking — the literal takes
  # the declared width), while any already-typed RHS must *unify exactly* with `T`,
  # so `x Int32 := someInt64` is a proven mismatch (no implicit narrow/widen). An
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
      nil -> check_bind_stmts(rest, Map.put(env, name, ann), ic)
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
      literal_adopts?(ce, ann) ->
        nil

      true ->
        t = infer(ce, env, ic)

        case unify(t, ann) do
          :mismatch ->
            {:error, "`#{name}`: binding declared `#{ann}` but its value has type `#{t}`"}

          _ ->
            nil
        end
    end
  end

  # A bare numeric literal adopts a *same-kind* numeric annotation (ADR-0034 §1):
  # an integer literal takes any `Int*`/`UInt*` width; a float literal takes any
  # `Float*`. Cross-kind (an integer literal into a `Float`) is *not* adopted —
  # write an explicit float literal — so it falls through to exact unification.
  defp literal_adopts?(%ENum{text: n}, ann),
    do: if(int_literal?(n), do: int_type?(ann), else: float_type?(ann))

  defp literal_adopts?(%EUnary{op: "-", arg: arg}, ann), do: literal_adopts?(arg, ann)
  defp literal_adopts?(_e, _ann), do: false

  defp int_literal?(n), do: not (String.contains?(n, ".") or String.match?(n, ~r/[eE]/))
  defp int_type?(t), do: String.match?(t, ~r/^U?Int\d*$/)
  defp float_type?(t), do: String.match?(t, ~r/^Float\d*$/)

  defp check_return(%Func{name: name, params: ps, ret: ret, tvars: tvars, clauses: clauses}, ic) do
    # A return type mentioning a `forall` type variable is generic; we don't yet
    # unify type variables structurally, so such a function is checked
    # conservatively (its body is not contradicted). Concrete returns are checked.
    if generic_ret?(ret, tvars) do
      :ok
    else
      Enum.find_value(clauses, :ok, fn c ->
        body_t = infer(Pratt.parse_body(c.body), clause_env(c.pats, ps, ic), ic)

        case unify(body_t, ret) do
          :mismatch ->
            {:error,
             "`#{name}`: body has type `#{body_t}` but the declared return type is `#{ret}`"}

          _ ->
            nil
        end
      end)
    end
  end

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
  defp clause_env(pats, params, ic) do
    pats
    |> Enum.zip(params)
    |> Enum.reduce(%{}, fn {pat, param}, env ->
      narrow(Core.from_pat(pat), param.type, ic, env)
    end)
  end

  @doc "Parse source and check every function; returns `:ok` or the first `{:error, message}`."
  def check(src), do: src |> Rian.Decl.parse() |> check_program()

  @doc """
  Check every function in a parsed program — top-level and inside every module.
  Returns `:ok` or the first `{:error, message}`.
  """
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
  @spec program_ic(map()) :: %{tdefs: map(), funs: map(), fsigs: map(), ctors: map()}
  def program_ic(%{} = prog) do
    types = all_types(prog)

    all_funcs =
      Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    %{
      tdefs: type_table(types),
      funs: Map.new(all_funcs, fn f -> {f.name, f.ret} end),
      fsigs: Map.new(all_funcs, fn f -> {f.name, fsig(f)} end),
      ctors: ctor_types(types, prog)
    }
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
  def gate!(prog) do
    case check_program(prog) do
      :ok -> :ok
      {:error, msg} -> raise Error, msg
    end
  end
end
