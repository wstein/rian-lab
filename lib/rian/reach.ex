defmodule Rian.Reach do
  @moduledoc """
  Target-reachability analysis (ADR-0057).

  For each function it computes the set of **target environments** it can lower
  to — `:ex` (Elixir/BEAM), `:rs` (Rust), `:js` (ECMAScript), `:jvm` (Kotlin/JVM,
  ADR-0049 Tier 2). A function is
  portable (reaches all targets) unless it uses an `ex`-only construct: **host
  FFI** — an Erlang remote call `:mod.fun(…)` or an Elixir-module call
  `Mod.fun(…)` to a module that is *not* a Rian module in the same program. That
  set includes all **concurrency / process / state** FFI (`:erlang.spawn`,
  `GenServer`, `Task`, `Process`, `:ets`, …), which is native-per-target **by
  design** (ADR-0057) and so never portable.

  Reachability propagates along the local call graph — a function is at most as
  portable as the least-portable local function it calls — by the same fixpoint
  shape as the error-set solver in `Rian.Check`. The label lattice is
  `{:ex, :rs, :js, :jvm}` today and is structured to relabel to effects (ADR-0048)
  later: classify *constructs*, intersect over callees, iterate to a fixpoint.

  This is the engine behind `mix rian.targets` and the portability gate; it does
  not itself raise — declaring a required target set is a separate concern.

  ## Known v1 conservativeness
    * Cross-module Rian calls (`OtherMod.fun(…)`) are treated as portable rather
      than threaded through the callee's reach (under-approximates a blocker that
      hides behind a sibling module; never over-approximates a direct FFI).
    * Bare atom *literals* are not classified (they are Symbols/Result tags,
      portable per ADR-0041); only FFI *calls* are flagged.
    * Clause-head patterns are not scanned (FFI lives in bodies/guards).

  Reach models **architectural** reachability (what a target *can* run — `ref` off
  the BEAM, `Int64` off JS, FFI off non-BEAM). It deliberately does NOT track an
  emitter's **implementation status** (atoms/`with`/lambdas not *yet* lowered on JS;
  tuples/lists/maps/`case` not *yet* on the Tier-2 JVM) — those are portable by
  design (ADR-0041/0040/0049) and will land. That gap is reported by a per-emitter
  capability pre-check (`Rian.JS`/`Rian.JVM` `reject_unsupported!`), which fails fast
  with a clear "not yet supported on :js/:jvm" message — keeping this matrix honest
  about *architecture* while the emitters report their own *coverage*.
  """

  alias Rian.{Core, Pratt}

  defmodule Error do
    @moduledoc "Raised when a `@targets(…)` module contract is not met (ADR-0058 §2)."
    defexception [:message]
  end

  @targets [:ex, :rs, :js, :jvm]

  # Erlang modules that are concurrency/process/state (ex-only AND native-per-target)
  @conc_erl ~w(ets dets mnesia gen_server gen_statem gen_event global pg pg2 sys supervisor)
  @conc_erl_fun ~w(spawn spawn_link spawn_monitor send send_after start_timer monitor link)
  # Elixir modules that are concurrency/process/state
  @conc_ex ~w(GenServer Task Process Agent Supervisor DynamicSupervisor Registry GenStage GenEvent Node)

  @doc "The closed target vocabulary (emitter-backed). Extends only when an emitter lands."
  def targets, do: @targets

  @doc """
  Analyze a parsed program (`Rian.Decl.parse/1` output).

  Returns `%{fun_name => %{reach: MapSet.t(target), blockers: [blocker]}}` where a
  `blocker` is `%{construct: String.t(), kind: :ffi | :concurrency, kills: [target]}`.
  """
  def analyze(prog) do
    funs = all_funcs(prog)
    modnames = MapSet.new(Enum.map(Map.get(prog, :mods, []), & &1.name))
    local_names = MapSet.new(Enum.map(funs, & &1.name))

    facts =
      Map.new(funs, fn f ->
        {blockers, callees} = scan_func(f, modnames)
        # local reach = the closed vocabulary minus every target any blocker kills.
        # Host FFI/concurrency kill the non-BEAM targets; a `ref` capability kills
        # `:ex` (BEAM-rejected, ADR-0055/P5) — so the two compose correctly.
        killed = MapSet.new(Enum.flat_map(blockers, & &1.kills))
        local = MapSet.difference(MapSet.new(@targets), killed)

        {f.name,
         %{local: local, callees: MapSet.intersection(callees, local_names), blockers: blockers}}
      end)

    reach = fixpoint(facts, Map.new(facts, fn {n, fc} -> {n, fc.local} end))

    Map.new(facts, fn {n, fc} ->
      {n, %{reach: Map.fetch!(reach, n), blockers: Enum.reverse(fc.blockers)}}
    end)
  end

  @doc """
  Check every `mod`'s `@targets(…)` contract (ADR-0058 §2): each `pub` function
  in a module that declares a target set must *reach* every target in it. A
  module with no contract (`targets: nil`) falls back to the **build default**
  (`default`, ADR-0058 §2 — `mix.exs` `rian: [targets: […]]`); when that is also
  nil the module is not gated — constraints are selected by need. Returns `:ok`
  or `{:error, message}`.
  """
  def check_contracts(prog, default \\ nil) do
    reach = analyze(prog)

    violations =
      for mod <- Map.get(prog, :mods, []),
          required = mod.targets || default,
          required != nil,
          f <- mod.funcs,
          f.pub?,
          missing = required -- MapSet.to_list(reach[f.name][:reach] || MapSet.new(@targets)),
          missing != [] do
        {mod.name, f.name, Enum.sort(missing)}
      end

    case violations do
      [] -> :ok
      vs -> {:error, contract_message(vs)}
    end
  end

  @doc "Raise `Rian.Reach.Error` on any unmet `@targets(…)` contract, else `:ok`."
  def gate!(prog), do: gate!(prog, build_default())

  @doc "Gate against an explicit build-default target set (`nil` = none)."
  def gate!(prog, default) do
    :ok = symbol_lint!(prog)

    case check_contracts(prog, default) do
      :ok -> :ok
      {:error, msg} -> raise Error, msg
    end
  end

  # Symbol ordering operators (`< <= > >=`) — the equality-only boundary (ADR-0041 §2).
  @ord_ops ~w(< <= > >=)

  @doc """
  Lint the equality-only boundary (ADR-0041 §2, P9): a `Symbol`/atom literal is
  comparable by `==`/`!=` only — **ordering is not portable** (atom term-order on
  the BEAM is atom-table position, which won't match `&str`/enum order elsewhere).
  Ordering an atom literal is a cross-target divergence, so it is a compile error
  here rather than a silent per-target difference. Returns `:ok` or raises.
  """
  def symbol_lint!(prog) do
    case Enum.flat_map(all_funcs(prog), &func_symbol_violations/1) do
      [] ->
        :ok

      [{op, atom} | _] ->
        raise Error,
              "`Symbol`/atom `:#{atom}` compared with `#{op}` — Symbols are equality-only " <>
                "across targets (no portable ordering, ADR-0041 §2); use `==`/`!=`"
    end
  end

  defp func_symbol_violations(f) do
    Enum.flat_map(f.clauses, fn c ->
      guard = if c.guard, do: find_atom_ordering(Pratt.parse(c.guard)), else: []
      find_atom_ordering(Pratt.parse_body(c.body)) ++ guard
    end)
  end

  # generic surface-AST walk: every `{:bin, <ord>, l, r}` with an atom-literal operand.
  defp find_atom_ordering({:bin, op, l, r} = node) when op in @ord_ops do
    here = for a <- [l, r], match?({:atom, _}, a), do: {op, elem(a, 1)}
    here ++ deep(node)
  end

  defp find_atom_ordering(t) when is_tuple(t), do: deep(t)
  defp find_atom_ordering(l) when is_list(l), do: Enum.flat_map(l, &find_atom_ordering/1)
  defp find_atom_ordering(_), do: []

  defp deep(t), do: t |> Tuple.to_list() |> Enum.flat_map(&find_atom_ordering/1)

  @doc """
  The build-default target set (ADR-0058 §2) for modules that declare no
  `@targets`: the `:rian_lab` app env `:rian_targets`, else `mix.exs`'s
  `rian: [targets: […]]`, else `nil` (no default gate).
  """
  def build_default do
    validate_default(Application.get_env(:rian_lab, :rian_targets) || mix_default())
  end

  defp mix_default do
    if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() do
      get_in(Mix.Project.config(), [:rian, :targets])
    end
  end

  # the build-default runs on every compile (`gate!/1`); validate it against the
  # same closed vocabulary the `@targets` annotation checks, so a typo or wrong
  # type (`["ex"]`, `:foo`) fails with a clear message rather than silently
  # mis-gating every module with confusing "missing" violations.
  defp validate_default(nil), do: nil

  defp validate_default(ts) when is_list(ts) do
    case ts -- @targets do
      [] ->
        ts

      bad ->
        raise Error,
              "invalid build-default target(s) #{inspect(bad)}; known: #{inspect(@targets)}"
    end
  end

  defp validate_default(other),
    do:
      raise(
        Error,
        "build-default targets must be a list of #{inspect(@targets)}, got: #{inspect(other)}"
      )

  defp contract_message(violations) do
    lines =
      Enum.map_join(violations, "\n", fn {mod, fun, missing} ->
        "  #{mod}.#{fun} cannot reach #{inspect(missing)} required by `@targets`"
      end)

    "module `@targets` contract not met (ADR-0058 §2):\n" <> lines
  end

  # reach(f) = local(f) ∩ ⋂ reach(callee) — monotone-decreasing, runs to a fixpoint
  defp fixpoint(facts, table) do
    next =
      Map.new(facts, fn {n, %{local: local, callees: cs}} ->
        {n,
         Enum.reduce(cs, local, fn c, acc ->
           MapSet.intersection(acc, Map.get(table, c, MapSet.new(@targets)))
         end)}
      end)

    if next == table, do: table, else: fixpoint(facts, next)
  end

  defp all_funcs(prog),
    do: Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

  # scan every clause body (and guard) of one function for ex-only constructs + local-call edges
  defp scan_func(f, modnames) do
    # the `ref` capability (`&mut`) is BEAM-rejected (ADR-0055/0025, P5): a `ref`
    # parameter pins the function off `:ex` — it is outside the portable capability
    # core, so the reach report says so instead of overselling a tidy four.
    ref = if Enum.any?(Map.get(f, :params, []), &(&1.cap == :ref)), do: [ref_blocker()], else: []
    # arbitrary-precision `Int` (ADR-0064) is native on BEAM/JS but needs a bignum
    # on Rust/JVM (not yet implemented), so it pins the function off `:rs`/`:jvm`.
    sig_types = Enum.map(Map.get(f, :params, []), & &1.type) ++ [Map.get(f, :ret)]
    int = if Enum.any?(sig_types, &(&1 == "Int")), do: [int_blocker()], else: []
    # fixed-width integers wider than the JS safe-integer range — `Int64`/`Int128`/
    # `UInt64`/`UInt128` (ADR-0064) — have no faithful JS representation (a 2^53
    # `Number` can't hold them, and we decline to silently elevate to `BigInt`). So
    # they pin the function off `:js`. `Int53` is the portable fixed-width ceiling
    # (JS `Number`, `i64` elsewhere) and `Int32`/smaller stay JS-native — neither
    # blocks.
    width = if Enum.any?(sig_types, &js_wide_int?/1), do: [width_blocker()], else: []

    Enum.reduce(f.clauses, {ref ++ int ++ width, MapSet.new()}, fn c, acc ->
      acc = scan(core(c.body, &Pratt.parse_body/1), modnames, acc)
      if c.guard, do: scan(core(c.guard, &Pratt.parse/1), modnames, acc), else: acc
    end)
  end

  defp ref_blocker, do: %{construct: "ref capability (&mut)", kind: :capability, kills: [:ex]}

  defp int_blocker,
    do: %{construct: "Int (arbitrary precision)", kind: :numeric, kills: [:rs, :jvm]}

  defp width_blocker,
    do: %{
      construct: "fixed-width integer >2^53 (no JS representation)",
      kind: :numeric,
      kills: [:js]
    }

  defp wide_prim_blocker,
    do: %{construct: "64-bit overflow op (no JS representation)", kind: :numeric, kills: [:js]}

  # the explicit 64-bit overflow prims carry the fixed-width-64 contract — the JS
  # emitter refuses them (ADR-0064 §2a), so a body that *calls* one is off `:js`
  # even when the function's own signature is JS-valid (e.g. an `Int53` wrapper).
  # Canonical list lives in `Rian.Prim` so it and the JS emitter never drift.
  @wide_prims Rian.Prim.overflow_ops()

  # Fixed-width integers too wide for a JS `Number` (the 2^53-exact double): the
  # 64- and 128-bit widths. `Int53` and `Int32`/smaller fit and are JS-native.
  @js_wide_int ~r/^(Int|UInt)(64|128)$/
  defp js_wide_int?(t), do: is_binary(t) and Regex.match?(@js_wide_int, t)

  defp core(src, parser), do: src |> parser.() |> Core.from_expr()

  # generic deep walk over the typed-core AST: classify each node, recurse children
  defp scan(node, modnames, acc) when is_struct(node) do
    acc = classify(node, modnames, acc)
    node |> Map.from_struct() |> Map.values() |> Enum.reduce(acc, &scan(&1, modnames, &2))
  end

  defp scan(list, modnames, acc) when is_list(list),
    do: Enum.reduce(list, acc, &scan(&1, modnames, &2))

  defp scan(tuple, modnames, acc) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.reduce(acc, &scan(&1, modnames, &2))

  defp scan(_other, _modnames, acc), do: acc

  # Erlang remote call `:mod.fun(…)` — always host FFI, ex-only
  defp classify(
         %Core.ECall{fun: %Core.EDot{head: %Core.EAtom{name: m}, name: fun}},
         _modnames,
         {bl, ca}
       ),
       do: {[ffi(":#{m}.#{fun}", conc_erl?(m, fun)) | bl], ca}

  # Elixir-module call `Mod.fun(…)` — host FFI unless `Mod` is a Rian module here
  defp classify(
         %Core.ECall{fun: %Core.EDot{head: %Core.EId{name: m}, name: fun}},
         modnames,
         {bl, ca}
       ) do
    cond do
      not pascal?(m) -> {bl, ca}
      MapSet.member?(modnames, m) -> {bl, ca}
      true -> {[ffi("#{m}.#{fun}", m in @conc_ex) | bl], ca}
    end
  end

  # an explicit 64-bit overflow prim (`__prim_wrapping_add` …) — off `:js` (ADR-0064
  # §2a, `Rian.JS` refuses it) even when the enclosing function's *signature* is
  # JS-valid, e.g. an `Int53` wrapper whose body calls `wrapping_add`. Without this
  # the prim falls through to the local-call edge below (no local def of that name),
  # so the gate would report `:js`-reachable and the JS emitter would then raise —
  # the gate lying. Must precede the generic `EId` clause.
  defp classify(%Core.ECall{fun: %Core.EId{name: f}}, _modnames, {bl, ca}) when f in @wide_prims,
    do: {[wide_prim_blocker() | bl], ca}

  # local function application — a call-graph edge
  defp classify(%Core.ECall{fun: %Core.EId{name: f}}, _modnames, {bl, ca}),
    do: {bl, MapSet.put(ca, f)}

  defp classify(_node, _modnames, acc), do: acc

  defp ffi(construct, conc?),
    do: %{
      construct: construct,
      kind: if(conc?, do: :concurrency, else: :ffi),
      kills: @targets -- [:ex]
    }

  defp conc_erl?(m, fun), do: m in @conc_erl or (m == "erlang" and fun in @conc_erl_fun)

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)
end
