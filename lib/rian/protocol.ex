defmodule Rian.Protocol do
  @moduledoc """
  `protocol` / `impl` expansion — the MVP of ADR-0042 part 2.

  A `protocol` names method *signatures*; an `impl P for T` supplies their bodies
  for one concrete type. This module desugars both into ordinary `def`s — the
  raw-def maps `Rian.Decl.build_func/1` already consumes — so the whole existing
  pipeline (param parsing, clause/guard lowering, the BEAM backend) is reused
  with no new codegen:

    * each `impl P for T` method becomes a private function `impl_<p>_<t>_<m>`
      (the protocol's parameter types, the impl's body);
    * each protocol method `m` becomes a **guarded dispatcher** `def m` with one
      clause per impl, selecting the impl by the first argument's runtime shape
      (a type-test BIF for a primitive, the constructor tag for a sum, the
      `:__struct__` tag for a struct). This is the BEAM "consolidated protocol
      dispatch" of ADR-0042 §4, static-where-known by the guard.

  ## Coherence (ADR-0042 §5)

    * an `impl` for an undeclared protocol is rejected;
    * an `impl` must define exactly the protocol's method set (no missing / extra);
    * at most one `impl` per `(protocol, type)` pair — and no two impl types may
      share a dispatch guard (e.g. `Int64` and `Char` both test `is_integer`),
      which would make dispatch ambiguous.

  Impls dispatch over **primitive** types (`is_integer`/`is_boolean`/…), **sum**
  types (by constructor tag — `element/2` on the tagged tuple, or a bare atom for
  a nullary variant), and **structs** (by `:__struct__`). This covers the
  compiler's own data (`Token`, `Expr`), so a real `Eq`/`Show` can be written.

  ## MVP limits (deferred, ADR-0042)

    * the generic `forall T: Bound` call path is future work (bounds parsed-and-dropped);
    * the Rust/JS lowerings are not emitted here (BEAM-first);
    * the orphan rule is not enforced across modules yet (single-program scope).
  """

  defmodule Error do
    @moduledoc "Raised on a protocol/impl coherence violation."
    defexception [:message]
  end

  @doc """
  Expand the collected `protocols` (`name => [sig_raw_map]`) and `impls`
  (`[{proto, type, [method_raw_map]}]`) into a list of raw `def` maps to append
  to a scope's function stream. Raises `Error` on any coherence violation.
  """
  def expand(protocols, impls, types \\ [], structs \\ []) do
    reg = registry(types, structs)
    Enum.each(impls, &check_impl(&1, protocols, reg))
    check_no_overlap(impls, reg)

    dispatchers =
      for {name, sigs} <- protocols, sig <- sigs, do: dispatcher(name, sig, impls, reg)

    methods = Enum.flat_map(impls, &impl_methods(&1, protocols))

    List.flatten(dispatchers) ++ methods
  end

  # the dispatchable types in scope: sum types (name -> variants) and struct
  # names — the basis for runtime tag-membership guards.
  defp registry(types, structs) do
    %{
      sums: Map.new(types, &{&1.name, &1.variants}),
      structs: MapSet.new(Enum.map(structs, & &1.name))
    }
  end

  # ── coherence ───────────────────────────────────────────────────────────
  defp check_impl({proto, type, methods}, protocols, reg) do
    sigs = protocols[proto] || raise(Error, "`impl … for #{type}`: unknown protocol `#{proto}`")

    want = sigs |> Enum.map(& &1.name) |> MapSet.new()
    got = methods |> Enum.map(& &1.name) |> MapSet.new()

    unless MapSet.equal?(want, got) do
      missing = MapSet.difference(want, got) |> Enum.to_list()
      extra = MapSet.difference(got, want) |> Enum.to_list()

      raise(
        Error,
        "`impl #{proto} for #{type}` does not match the protocol: " <>
          "missing #{inspect(missing)}, extra #{inspect(extra)}"
      )
    end

    # reject unsupported impl types early (so the message names the construct,
    # not a downstream guard failure)
    _ = guard_for!(type, proto, reg)
  end

  defp check_no_overlap(impls, reg) do
    impls
    |> Enum.reduce(%{}, fn {proto, type, _}, seen ->
      key = {proto, type}
      if Map.has_key?(seen, key), do: raise(Error, "duplicate `impl #{proto} for #{type}`")

      gkey = {proto, guard_for!(type, proto, reg)}

      if other = Map.get(seen, gkey) do
        raise(
          Error,
          "ambiguous dispatch: `impl #{proto} for #{type}` and `impl #{proto} for #{other}` " <>
            "select on the same runtime shape"
        )
      end

      seen |> Map.put(key, true) |> Map.put(gkey, type)
    end)
  end

  # ── dispatcher: one guarded clause per impl ──────────────────────────────
  defp dispatcher(proto, sig, impls, reg) do
    arity = sig.params |> split_commas() |> length()
    vars = Enum.map(0..(arity - 1)//1, &"v#{&1}")
    pat = Enum.join(vars, ", ")
    argv = pat

    clauses =
      for {^proto, type, _methods} <- impls do
        %{
          name: sig.name,
          params: pat,
          ret: nil,
          guard: guard_for!(type, proto, reg),
          body: "#{mangle(proto, type, sig.name)}(#{argv})",
          pub: false,
          tvars: []
        }
      end

    # a protocol with no impls emits no dispatcher (a bodiless signature with no
    # clauses is not a function) — it may still be named in a `forall T: P` bound.
    if clauses == [] do
      []
    else
      # a bodiless signature heads the multi-clause group; `Self` is listed as a
      # type variable so the return-type gate treats a `Self`-mentioning return as
      # generic (the dispatcher is polymorphic in the receiver).
      sig_map = %{
        name: sig.name,
        params: dispatcher_params(sig.params, vars),
        ret: sig.ret,
        guard: nil,
        body: nil,
        pub: true,
        tvars: ["Self" | sig[:tvars] || []],
        synthetic: true
      }

      [sig_map | clauses]
    end
  end

  # the dispatcher signature keeps the protocol's parameter *types* but renames
  # the parameters to the dispatch vars (`v0`, `v1`, …).
  defp dispatcher_params(sig_params, vars) do
    sig_params
    |> split_commas()
    |> Enum.zip(vars)
    |> Enum.map_join(", ", fn {p, v} -> "#{v} #{param_type(p)}" end)
  end

  # ── impl methods: mangled single-clause functions ────────────────────────
  defp impl_methods({proto, type, methods}, protocols) do
    sigs = Map.new(protocols[proto], &{&1.name, &1})

    Enum.map(methods, fn m ->
      sig = sigs[m.name]
      names = m.params |> split_commas() |> Enum.map(&String.trim/1)
      types = sig.params |> split_commas() |> Enum.map(&param_type/1)

      unless length(names) == length(types) do
        raise(
          Error,
          "`impl #{proto} for #{type}`: method `#{m.name}` has #{length(names)} " <>
            "parameter(s) but the protocol declares #{length(types)}"
        )
      end

      params =
        Enum.zip(names, types)
        |> Enum.map_join(", ", fn {n, t} -> "#{n} #{subst_self(t, type)}" end)

      %{
        name: mangle(proto, type, m.name),
        params: params,
        ret: subst_self(sig.ret, type),
        guard: m.guard,
        body: m.body,
        pub: false,
        tvars: []
      }
    end)
  end

  # ── helpers ──────────────────────────────────────────────────────────────
  defp mangle(proto, type, method),
    do: "impl_#{String.downcase(proto)}_#{String.downcase(type)}_#{method}"

  # A boolean guard expression (over the first dispatch var `v0`) selecting the
  # impl for `type` by the receiver's runtime shape:
  #   * primitives -> a type-test BIF (`is_integer`/`is_boolean`/…);
  #   * a sum type -> its constructor tags (nullary -> a bare atom; field-carrying
  #     -> a tagged tuple `{:tag, …}`, tested via `element/2`);
  #   * a struct -> a map carrying `:__struct__ => :name`.
  # Raises for a type with no runtime discriminator (a type variable, an unknown).
  defp guard_for!(type, proto, reg) do
    cond do
      type == "Bool" ->
        "is_boolean(v0)"

      type == "String" ->
        "is_binary(v0)"

      type == "Char" ->
        "is_integer(v0)"

      String.match?(type, ~r/^U?Int\d*$/) ->
        "is_integer(v0)"

      String.match?(type, ~r/^Float\d*$/) ->
        "is_float(v0)"

      Map.has_key?(reg.sums, type) ->
        sum_guard(reg.sums[type])

      MapSet.member?(reg.structs, type) ->
        struct_guard(snake(type))

      true ->
        raise(
          Error,
          "`impl #{proto} for #{type}`: no runtime discriminator for `#{type}` (a type variable or unknown type); dispatch needs a concrete primitive, sum, or struct type"
        )
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
    "(is_tuple(v0) and element(1, v0) == :#{tag}) or " <>
      "(is_map(v0) and map_get(:__struct__, v0) == :#{tag})"
  end

  defp snake(name), do: Rian.PatternLower.to_snake(name)

  defp subst_self(nil, _type), do: nil
  defp subst_self(t, type), do: Regex.replace(~r/\bSelf\b/, t, type)

  # the type of a `name Type` (or bare `Type`) parameter — the last whitespace
  # token (capabilities like `val`/`ref` and the name precede it).
  defp param_type(p), do: p |> String.trim() |> String.split(~r/\s+/) |> List.last()

  # split a parameter list on **top-level** commas only — a comma inside a
  # parametric type (`Map(String, Int64)`, `Result(A, E)`, `Fn(A, B)`) is part of
  # that one parameter's type, not a parameter separator.
  defp split_commas(""), do: []

  defp split_commas(s) do
    {parts, cur, _depth} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ",", {parts, cur, 0} -> {[cur | parts], "", 0}
        "(", {parts, cur, d} -> {parts, cur <> "(", d + 1}
        ")", {parts, cur, d} -> {parts, cur <> ")", d - 1}
        ch, {parts, cur, d} -> {parts, cur <> ch, d}
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end
