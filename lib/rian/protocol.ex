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

  Impls dispatch over **primitive** types (`is_integer`/`is_boolean`/…), **sum**
  types (by constructor tag — `element/2` on the tagged tuple, or a bare atom for
  a nullary variant), and **structs** (by `:__struct__`). This covers the
  compiler's own data (`Token`, `Expr`), so a real `Eq`/`Show` can be written.

  **Coherence** (ADR-0061 §5) — one impl per `(protocol, type)`, method-set/arity
  match, runtime-discriminator presence and non-overlap — is owned by
  `Rian.Coherence`, which `expand/5` consults before codegen. The runtime
  discriminator that the shared-guard rule and this module's dispatcher share is
  also `Rian.Coherence`'s (`guard_for!/3`), so rule and codegen agree by
  construction.

  ## MVP limits (deferred, ADR-0042)

    * the generic `forall T: Bound` call path is future work (bounds parsed-and-dropped);
    * the Rust/JS lowerings are not emitted here (BEAM-first);
    * the orphan rule is not enforced across modules yet (single-program scope).
  """

  use Rian.Ann

  @doc """
  Expand the collected `protocols` (`name => [sig_raw_map]`) and `impls`
  (`[{proto, type, [method_raw_map]}]`) into a list of raw `def` maps to append
  to a scope's function stream. Raises `Rian.Coherence.Error` on any coherence
  violation.
  """
  @rian_sig "pub def expand(protocols _Unk, impls Vec(_Unk), types Vec(Type)) _Unk"
  @rian_sig "pub def expand(protocols _Unk, impls Vec(_Unk), types Vec(Type), structs Vec(Struct)) _Unk"
  @rian_sig "pub def expand(protocols _Unk, impls Vec(_Unk), types Vec(Type), structs Vec(Struct), targets _Unk) _Unk"
  @spec expand(map(), list(), list(), list(), term()) :: term()
  def expand(protocols, impls, types \\ [], structs \\ [], targets \\ nil) do
    reg = Rian.Coherence.registry(types, structs)
    Rian.Coherence.check!(protocols, impls, reg, targets)

    dispatchers =
      for {name, sigs} <- protocols, sig <- sigs, do: dispatcher(name, sig, impls, reg)

    methods = Enum.flat_map(impls, &impl_methods(&1, protocols))

    List.flatten(dispatchers) ++ methods
  end

  # ── dispatcher: one guarded clause per impl ──────────────────────────────
  defp dispatcher(proto, sig, impls, reg) do
    arity = sig.params |> split_commas() |> length()
    vars = Enum.map(0..(arity - 1)//1, &"v#{&1}")
    pat = Enum.join(vars, ", ")
    argv = pat

    clauses =
      for {^proto, type, _methods, _assoc} <- impls do
        %{
          name: sig.name,
          params: pat,
          ret: nil,
          guard: Rian.Coherence.guard_for!(type, proto, reg),
          body: "#{mangle(proto, type, sig.name)}(#{argv})",
          pub: false,
          tvars: [],
          dispatch: :dispatcher
        }
      end

    # a protocol with no impls emits no dispatcher (a bodiless signature with no
    # clauses is not a function) — it may still be named in a `forall T: P` bound.
    if clauses == [] do
      []
    else
      # the protocol's associated types (the keys each impl binds, ADR-0074) — collected
      # from this proto's impls. They join `Self` as the dispatcher's **type variables**
      # so the return-type gate treats a `Vec(Elem)` return as polymorphic: each clause
      # returns a *resolved* concrete type (`Vec(Int53)` / `Vec(String)`) that unifies
      # with `Vec(Elem)` per clause, exactly as `Self` does for the receiver.
      assoc_tvars =
        for({^proto, _t, _m, a} <- impls, k <- Map.keys(a), do: k) |> Enum.uniq()

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
        tvars: Enum.uniq(["Self" | Map.get(sig, :tvars, [])] ++ assoc_tvars),
        synthetic: true,
        dispatch: :dispatcher
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
  # `Rian.Coherence` has already verified the method set and arity, so the
  # `names`/`types` zip below is total.
  defp impl_methods({proto, type, methods, assoc}, protocols) do
    sigs = Map.new(protocols[proto], &{&1.name, &1})

    Enum.map(methods, fn m ->
      sig = sigs[m.name]
      names = m.params |> split_commas() |> Enum.map(&String.trim/1)
      types = sig.params |> split_commas() |> Enum.map(&param_type/1)

      # Resolve BOTH `Self` (-> the impl type) and each associated type (`Elem` -> its
      # `type Elem := Int53` binding, ADR-0074 W1) in the generated method's declared
      # types. Without the assoc resolution the impl declares `Vec(Elem)` while its body
      # returns `Vec(Int53)`, and `Check.gate!` rejects the impl on every gated path
      # (`Decl.compile`/`Rian.JVM`); the dispatcher stays polymorphic in `Elem`.
      resolve = fn t -> t |> subst_self(type) |> subst_assoc(assoc) end

      params =
        Enum.zip(names, types)
        |> Enum.map_join(", ", fn {n, t} -> "#{n} #{resolve.(t)}" end)

      %{
        name: mangle(proto, type, m.name),
        params: params,
        ret: resolve.(sig.ret),
        guard: m.guard,
        body: m.body,
        pub: false,
        tvars: [],
        dispatch: :impl
      }
    end)
  end

  # substitute each associated-type binding (`%{"Elem" => "Int53"}`) into a type string —
  # `Vec(Elem)` -> `Vec(Int53)` for the impl that bound it (ADR-0074, expansion-time).
  defp subst_assoc(nil, _assoc), do: nil

  defp subst_assoc(t, assoc),
    do:
      Enum.reduce(assoc, t, fn {a, conc}, acc ->
        Regex.replace(~r/\b#{Regex.escape(a)}\b/, acc, conc)
      end)

  # ── helpers ──────────────────────────────────────────────────────────────
  defp mangle(proto, type, method),
    do: "impl_#{String.downcase(proto)}_#{String.downcase(type)}_#{method}"

  defp subst_self(nil, _type), do: nil
  defp subst_self(t, type), do: Regex.replace(~r/\bSelf\b/, t, type)

  # the type of a `name Type` (or bare `Type`) parameter — the last whitespace
  # token (capabilities like `val`/`ref` and the name precede it).
  defp param_type(p), do: p |> String.trim() |> String.split(~r/\s+/) |> List.last()

  # split a parameter list on **top-level** commas only — a comma inside a
  # parametric type (`Map(String, Int64)`, `Result(A, E)`, `Fn(A, B)`) is part of
  # that one parameter's type, not a parameter separator.
  defp split_commas(s), do: Rian.TypeStr.split_top_commas(s)
end
