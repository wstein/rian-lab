defmodule Rian.Coherence do
  @moduledoc """
  The single authority for **protocol/impl coherence** (ADR-0061 §5).

  Coherence is the set of rules that keep `protocol`/`impl` dispatch unambiguous
  and lowerable on every target a module declares. They are checked here — as a
  pure pass returning structured violations — so the *same* rule logic backs both
  the parse-time fast-fail (`Rian.Protocol.expand`, `Rian.Decl`) and the
  whole-program type gate (`Rian.Check`), rather than living incidentally inside
  the BEAM desugar. ADR-0061 §5 (amended 2026-06-21) promotes this from an
  *implicit* (per-scope side-effect) check to an *explicit, checked* one.

  The rules, and where each applies:

    * **unknown protocol** — an `impl` names a protocol that is not in scope;
    * **method set** — an `impl` defines exactly the protocol's method *names*
      (no missing, no extra);
    * **method arity** — each impl method's parameter count matches the
      protocol signature's;
    * **runtime discriminator** — an `impl` type has a runtime shape to dispatch
      on (a primitive, sum, or struct — not a type variable or unknown);
    * **one impl per `(protocol, type)`** — required on every target;
    * **no shared runtime discriminator** — two impl types of one protocol may
      not select on the same runtime shape (`Int64`+`Char`, both `is_integer`).
      Required only on the **runtime-dispatch** targets (`:ex`/`:js`); a Rust-only
      `@targets(rs)` module dispatches on static types, so it is exempt.

  Associated-type coherence (ADR-0074 Stage 2) lives in `check_assoc!/2`.

  This module also owns the **type → runtime discriminator** classification
  (`classify/2`/`guard_for!/3`): the equivalence the shared-discriminator rule
  keys on *is* the BEAM dispatch guard, so the rule and the codegen
  (`Rian.Protocol`) share one source.
  """

  use Rian.Ann

  defmodule Error do
    @moduledoc "Raised on a protocol/impl coherence violation."
    defexception [:message]
  end

  @typedoc "A structured coherence violation: the `rule`, the offending `(proto, type)`, and a message."
  @type violation :: %{
          rule: atom(),
          proto: String.t(),
          type: String.t() | nil,
          message: String.t()
        }

  # ── entry points ──────────────────────────────────────────────────────────

  @doc """
  Raise `Error` on the first coherence violation among `impls`, else `:ok`.

  `protocols` is `name => [sig]`; each `impl` is `{proto, type, methods, assoc}`;
  `reg` is `registry/2`; `targets` is the module's `@targets` (`nil` = all).
  """
  @rian_sig "pub def check!(protocols _Unk, impls Vec(_Unk), reg _Unk, targets Option(Vec(Symbol))) _Unk"
  @spec check!(map(), list(), map(), term()) :: :ok
  def check!(protocols, impls, reg, targets) do
    case violations(protocols, impls, reg, targets) do
      [] -> :ok
      [%{message: msg} | _] -> raise(Error, msg)
    end
  end

  @doc """
  The coherence violations among `impls`, in check order — an empty list means
  coherent. Pure: the introspectable form behind `check!/4` and the `Rian.Check`
  gate.
  """
  @rian_sig "pub def violations(protocols _Unk, impls Vec(_Unk), reg _Unk, targets Option(Vec(Symbol))) Vec(_Unk)"
  @spec violations(map(), list(), map(), term()) :: [violation()]
  def violations(protocols, impls, reg, targets) do
    Enum.flat_map(impls, &impl_violations(&1, protocols, reg)) ++
      overlap_violations(impls, reg, targets)
  end

  @doc """
  The dispatchable types in scope: sum types (`name -> variants`) and struct
  names — the basis for the runtime tag-membership guards `classify/2` builds.
  """
  @rian_sig "pub def registry(types Vec(Type), structs Vec(Struct)) _Unk"
  @spec registry(list(), list()) :: map()
  def registry(types, structs) do
    %{
      sums: Map.new(types, &{&1.name, &1.variants}),
      structs: MapSet.new(Enum.map(structs, & &1.name))
    }
  end

  # ── per-impl rules ──────────────────────────────────────────────────────────
  defp impl_violations({proto, type, methods, _assoc}, protocols, reg) do
    case protocols[proto] do
      nil ->
        [v(:unknown_protocol, proto, type, "`impl … for #{type}`: unknown protocol `#{proto}`")]

      sigs ->
        method_set_violations(proto, type, sigs, methods) ++
          arity_violations(proto, type, sigs, methods) ++
          discriminator_violations(proto, type, reg)
    end
  end

  defp method_set_violations(proto, type, sigs, methods) do
    want = sigs |> Enum.map(& &1.name) |> MapSet.new()
    got = methods |> Enum.map(& &1.name) |> MapSet.new()

    if MapSet.equal?(want, got) do
      []
    else
      missing = MapSet.difference(want, got) |> Enum.to_list()
      extra = MapSet.difference(got, want) |> Enum.to_list()

      [
        v(
          :method_set,
          proto,
          type,
          "`impl #{proto} for #{type}` does not match the protocol: " <>
            "missing #{inspect(missing)}, extra #{inspect(extra)}"
        )
      ]
    end
  end

  # each impl method that the protocol *declares* must take the same number of
  # parameters as the signature (a method not in the protocol is a method-set
  # violation, reported separately — skip it here so we never deref a nil sig).
  defp arity_violations(proto, type, sigs, methods) do
    by_name = Map.new(sigs, &{&1.name, &1})

    for m <- methods,
        sig = by_name[m.name],
        sig != nil,
        (got = m.params |> split_commas() |> length()) !=
          (want = sig.params |> split_commas() |> length()) do
      v(
        :method_arity,
        proto,
        type,
        "`impl #{proto} for #{type}`: method `#{m.name}` has #{got} " <>
          "parameter(s) but the protocol declares #{want}"
      )
    end
  end

  defp discriminator_violations(proto, type, reg) do
    case classify(type, reg) do
      {:ok, _guard} ->
        []

      :error ->
        [
          v(
            :discriminator,
            proto,
            type,
            "`impl #{proto} for #{type}`: no runtime discriminator for `#{type}` " <>
              "(a type variable or unknown type); dispatch needs a concrete primitive, sum, or struct type"
          )
        ]
    end
  end

  # ── cross-impl rules: one per (proto,type); no shared runtime discriminator ──
  defp overlap_violations(impls, reg, targets) do
    discriminator? = runtime_dispatch_target?(targets)

    {violations, _seen} =
      Enum.reduce(impls, {[], %{}}, fn {proto, type, _, _}, {vs, seen} ->
        key = {proto, type}

        if Map.has_key?(seen, key) do
          # a duplicate `(proto, type)` — reported once as a duplicate; it is the
          # *same* type, not two different types sharing a guard, so the
          # shared-discriminator test is skipped (and `seen` is unchanged).
          {vs ++ [v(:duplicate, proto, type, "duplicate `impl #{proto} for #{type}`")], seen}
        else
          # a type with no discriminator is already a per-impl violation; skip the
          # overlap test for it rather than deref a guard it does not have.
          {ambiguous, seen} =
            case classify(type, reg) do
              {:ok, guard} ->
                gkey = {proto, guard}
                other = Map.get(seen, gkey)

                amb =
                  if discriminator? and other,
                    do: [
                      v(
                        :shared_discriminator,
                        proto,
                        type,
                        "ambiguous dispatch: `impl #{proto} for #{type}` and " <>
                          "`impl #{proto} for #{other}` select on the same runtime shape " <>
                          "(allowed only on a Rust-only `@targets(rs)` module)"
                      )
                    ],
                    else: []

                {amb, Map.put(seen, gkey, type)}

              :error ->
                {[], seen}
            end

          {vs ++ ambiguous, Map.put(seen, key, true)}
        end
      end)

    violations
  end

  # the runtime-discriminator rule applies when the module can reach a runtime
  # dispatch target (`:ex`/`:js`); an unannotated module (`nil`) reaches all.
  @spec runtime_dispatch_target?(term()) :: boolean()
  defp runtime_dispatch_target?(nil), do: true
  defp runtime_dispatch_target?(targets), do: :ex in targets or :js in targets

  # ── associated-type coherence (ADR-0074 Stage 2) ────────────────────────────
  @doc """
  Every `impl` must bind **exactly** the associated types its protocol declares —
  a `type Elem := …` for each declared `type Elem`, none undeclared, none left
  bare. Operates on the structured IR (`prog.protocols`/`prog.impl_decls`, each
  carrying `:assoc`). Raises `Error`; the type-side analogue of the method-set
  rule. A protocol with no associated types is unaffected.
  """
  @rian_sig "pub def check_assoc!(protocols Vec(_Unk), impl_decls Vec(_Unk)) _Unk"
  @spec check_assoc!(list(), list()) :: :ok
  def check_assoc!(protocols, impl_decls) do
    declared = Map.new(protocols, fn p -> {p.name, MapSet.new(Map.get(p, :assoc, []))} end)

    Enum.each(impl_decls, fn impl ->
      want = Map.get(declared, impl.proto, MapSet.new())
      assoc = Map.get(impl, :assoc, %{})
      bound = assoc |> Map.keys() |> MapSet.new()

      missing = MapSet.difference(want, bound) |> Enum.to_list()
      extra = MapSet.difference(bound, want) |> Enum.to_list()
      unbound = for {k, nil} <- assoc, do: k

      cond do
        missing != [] ->
          raise(
            Error,
            "`impl #{impl.proto} for #{impl.type}` is missing associated type " <>
              "binding(s) #{inspect(missing)} — add `type Elem := …`"
          )

        extra != [] ->
          raise(
            Error,
            "`impl #{impl.proto} for #{impl.type}` binds undeclared associated " <>
              "type(s) #{inspect(extra)}"
          )

        unbound != [] ->
          raise(
            Error,
            "`impl #{impl.proto} for #{impl.type}`: associated type(s) #{inspect(unbound)} " <>
              "need a binding (`type Elem := …`, not bare `type Elem`)"
          )

        true ->
          :ok
      end
    end)

    :ok
  end

  # ── type → runtime discriminator (shared by the rule and the BEAM codegen) ──
  @doc """
  The BEAM dispatch guard (over the first dispatch var `v0`) selecting the impl
  for `type` by the receiver's runtime shape, or raise `Error` if `type` has no
  runtime discriminator. Used by `Rian.Protocol` for dispatcher codegen.
  """
  @rian_sig "pub def guard_for!(type String, proto String, reg _Unk) String"
  @spec guard_for!(String.t(), String.t(), map()) :: String.t()
  def guard_for!(type, proto, reg) do
    case classify(type, reg) do
      {:ok, guard} ->
        guard

      :error ->
        raise(
          Error,
          "`impl #{proto} for #{type}`: no runtime discriminator for `#{type}` " <>
            "(a type variable or unknown type); dispatch needs a concrete primitive, sum, or struct type"
        )
    end
  end

  # Classify `type` to its BEAM dispatch guard string, or `:error` when it has no
  # runtime discriminator. The pure core of `guard_for!/3`; the shared-discriminator
  # rule keys on the `{:ok, guard}` value so two types overlap iff their guards do.
  @spec classify(String.t(), map()) :: {:ok, String.t()} | :error
  defp classify(type, reg) do
    cond do
      type == "Bool" -> {:ok, "is_boolean(v0)"}
      type == "String" -> {:ok, "is_binary(v0)"}
      type == "Char" -> {:ok, "is_integer(v0)"}
      String.match?(type, ~r/^U?Int\d*$/) -> {:ok, "is_integer(v0)"}
      String.match?(type, ~r/^Float\d*$/) -> {:ok, "is_float(v0)"}
      Map.has_key?(reg.sums, type) -> {:ok, sum_guard(reg.sums[type])}
      MapSet.member?(reg.structs, type) -> {:ok, struct_guard(snake(type))}
      true -> :error
    end
  end

  # the tag-membership guard for a sum type's variants. A field-carrying variant
  # is a tagged tuple (matched by `element/2`, which fails safely on a non-tuple
  # in guard position); a nullary variant is a bare atom.
  defp sum_guard(variants) do
    {nullary, tupled} = Enum.split_with(variants, &(&1.fields == []))

    tupled_part =
      if tupled == [],
        do: [],
        else: ["(is_tuple(v0) and (#{tag_disjunction(tupled, "element(1, v0) ==")}))"]

    nullary_part =
      if nullary == [], do: [], else: ["(#{tag_disjunction(nullary, "v0 ==")})"]

    Enum.join(tupled_part ++ nullary_part, " or ")
  end

  defp tag_disjunction(variants, lhs),
    do: Enum.map_join(variants, " or ", &"#{lhs} :#{snake(&1.ctor)}")

  # a struct value is either a tagged tuple (positional construction `Name(a, b)`)
  # or a `:__struct__` map (named construction `Name(f: v)`) — accept both.
  defp struct_guard(tag) do
    # bare `map_get/2` is NOT a guard BIF — `cannot invoke local map_get/2 inside a
    # guard`. Use the auto-imported `is_map_key/2` to confirm the key, then the
    # remote guard BIF `:erlang.map_get/2` to read it (both valid in guards).
    "(is_tuple(v0) and element(1, v0) == :#{tag}) or " <>
      "(is_map(v0) and is_map_key(:__struct__, v0) and :erlang.map_get(:__struct__, v0) == :#{tag})"
  end

  defp snake(name), do: Rian.PatternLower.to_snake(name)

  # split a parameter list on **top-level** commas only — a comma inside a
  # parametric type (`Map(String, Int64)`, `Result(A, E)`, `Fn(A, B)`) is part of
  # that one parameter's type, not a parameter separator.
  defp split_commas(s), do: Rian.TypeStr.split_top_commas(s)

  defp v(rule, proto, type, message),
    do: %{rule: rule, proto: proto, type: type, message: message}
end
