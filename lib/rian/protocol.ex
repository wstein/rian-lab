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
      clause per impl, selecting the impl by the first argument's runtime type
      (`is_integer`/`is_float`/`is_boolean`/`is_binary`). This is the BEAM
      "consolidated protocol dispatch" of ADR-0042 §4, static-where-known by the
      guard.

  ## Coherence (ADR-0042 §5)

    * an `impl` for an undeclared protocol is rejected;
    * an `impl` must define exactly the protocol's method set (no missing / extra);
    * at most one `impl` per `(protocol, type)` pair — and no two impl types may
      share a dispatch guard (e.g. `Int64` and `Char` both test `is_integer`),
      which would make dispatch ambiguous.

  ## MVP limits (deferred, ADR-0042)

    * impls are over **primitive** types only (a sum-type tag dispatcher and the
      generic `forall T: Bound` call path are future work);
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
  def expand(protocols, impls) do
    Enum.each(impls, &check_impl(&1, protocols))
    check_no_overlap(impls)

    dispatchers = for {name, sigs} <- protocols, sig <- sigs, do: dispatcher(name, sig, impls)
    methods = Enum.flat_map(impls, &impl_methods(&1, protocols))

    List.flatten(dispatchers) ++ methods
  end

  # ── coherence ───────────────────────────────────────────────────────────
  defp check_impl({proto, type, methods}, protocols) do
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

    # reject non-primitive impl types early (so the message names the construct,
    # not a downstream guard failure)
    _ = guard_fun!(type, proto)
  end

  defp check_no_overlap(impls) do
    impls
    |> Enum.reduce(%{}, fn {proto, type, _}, seen ->
      key = {proto, type}
      if Map.has_key?(seen, key), do: raise(Error, "duplicate `impl #{proto} for #{type}`")

      gkey = {proto, guard_fun!(type, proto)}

      if other = Map.get(seen, gkey) do
        raise(
          Error,
          "ambiguous dispatch: `impl #{proto} for #{type}` and `impl #{proto} for #{other}` " <>
            "share the runtime guard `#{guard_fun!(type, proto)}`"
        )
      end

      seen |> Map.put(key, true) |> Map.put(gkey, type)
    end)
  end

  # ── dispatcher: one guarded clause per impl ──────────────────────────────
  defp dispatcher(proto, sig, impls) do
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
          guard: "#{guard_fun!(type, proto)}(v0)",
          body: "#{mangle(proto, type, sig.name)}(#{argv})",
          pub: false,
          tvars: []
        }
      end

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

  # the runtime guard BIF selecting an impl by its first argument's type, or a
  # hard error for a not-yet-supported (non-primitive) type.
  defp guard_fun!(type, proto) do
    cond do
      type == "Bool" ->
        "is_boolean"

      type == "String" ->
        "is_binary"

      type == "Char" ->
        "is_integer"

      String.match?(type, ~r/^U?Int\d*$/) ->
        "is_integer"

      String.match?(type, ~r/^Float\d*$/) ->
        "is_float"

      true ->
        raise(
          Error,
          "`impl #{proto} for #{type}`: dispatch for non-primitive types is not yet supported (MVP, ADR-0042)"
        )
    end
  end

  defp subst_self(nil, _type), do: nil
  defp subst_self(t, type), do: Regex.replace(~r/\bSelf\b/, t, type)

  # the type of a `name Type` (or bare `Type`) parameter — the last whitespace
  # token (capabilities like `val`/`ref` and the name precede it).
  defp param_type(p), do: p |> String.trim() |> String.split(~r/\s+/) |> List.last()

  defp split_commas(""), do: []
  defp split_commas(s), do: String.split(s, ",", trim: true) |> Enum.map(&String.trim/1)
end
