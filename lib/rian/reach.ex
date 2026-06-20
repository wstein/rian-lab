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
    * Clause-head patterns are scanned only for bitstring patterns (`<<…>>`) and
      pins (`^x`) — emitter gaps off the typed/JVM targets; the FFI blocker lives in
      call bodies/guards.

  Reach models **architectural** reachability (what a target *can* run — `ref` off
  the BEAM, `Int64` off JS, FFI off non-BEAM). It deliberately does NOT track an
  emitter's **implementation status** (a bitstring not *yet* lowered on JS;
  map-update/arity-≥4 tuples not *yet* on the Tier-2 JVM) — those are portable by
  design (ADR-0041/0040/0049) and will land. That gap is reported by a per-emitter
  capability pre-check (`Rian.JS`/`Rian.JVM` `reject_unsupported!`), which fails fast
  with a clear "not yet supported on :js/:jvm" message — keeping this matrix honest
  about *architecture* while the emitters report their own *coverage*.
  """

  use Rian.Ann
  alias Rian.{Core, Pratt}

  defmodule Error do
    @moduledoc "Raised when a `@targets(…)` module contract is not met (ADR-0058 §2)."
    defexception [:message]
  end

  @targets [:ex, :rs, :js, :jvm]

  # The effect names a function may declare (ADR-0048 §2). `host` = calls fallible host
  # FFI; `spawn` = a concurrency primitive (both Reach-gating — they kill the non-BEAM
  # targets, so over-declaring is a portability lie, ADR-0081 §2). The world categories
  # `io`/`fs`/`clock`/`random`/`net` are inferred ALONGSIDE `host` for known host
  # modules (a raw `:rand.uniform` is both `host` — non-portable FFI — and `random`);
  # they stand alone only once a portable effectful stdlib lowers them per target
  # (ADR-0047, not yet built).
  @effect_names [:host, :spawn, :io, :fs, :clock, :random, :net]

  # Known host modules → their world effect category (ADR-0048 §2). Module-root keyed
  # (the construct is `Mod.fun`/`:mod.fun`); an uncatalogued host call is `host`-only
  # (correct but coarse — add the module here to refine). `clock` is function-keyed
  # (the time primitives) since its modules (`:os`/`:erlang`/`System`) are mixed.
  @effect_mods %{
    "IO" => :io,
    "io" => :io,
    "File" => :fs,
    "file" => :fs,
    "rand" => :random,
    "random" => :random,
    "gen_tcp" => :net,
    "gen_udp" => :net,
    "gen_sctp" => :net,
    "ssl" => :net,
    "inet" => :net,
    "httpc" => :net
  }
  @clock_funs ~w(system_time monotonic_time os_time timestamp now)
  @clock_mods ~w(os erlang System)

  @typedoc "A lowering target (emitter-backed)."
  @type target :: :ex | :rs | :js | :jvm

  @typedoc "A tracked effect (ADR-0048 §2)."
  @type effect :: :host | :spawn | :io | :fs | :clock | :random | :net

  # Erlang modules that are concurrency/process/state (ex-only AND native-per-target)
  @conc_erl ~w(ets dets mnesia gen_server gen_statem gen_event global pg pg2 sys supervisor)
  @conc_erl_fun ~w(spawn spawn_link spawn_monitor send send_after start_timer monitor link)
  # Elixir modules that are concurrency/process/state
  @conc_ex ~w(GenServer Task Process Agent Supervisor DynamicSupervisor Registry GenStage GenEvent Node)

  @rian_sig "pub def targets() Vec(Symbol)"
  @doc "The closed target vocabulary (emitter-backed). Extends only when an emitter lands."
  @spec targets() :: [target()]
  def targets, do: @targets

  @rian_sig "pub def effect_names() Vec(Symbol)"
  @doc "The effect names a function may declare today (inferable + Reach-gating, ADR-0048 §2)."
  @spec effect_names() :: [effect()]
  def effect_names, do: @effect_names

  @doc """
  Analyze a parsed program (`Rian.Decl.parse/1` output).

  Returns `%{"name/arity" => %{reach: MapSet.t(target), blockers: [blocker]}}` where
  a `blocker` is `%{construct: String.t(), kind: :ffi | :concurrency, kills: [target]}`.
  The report is keyed by `"name/arity"` (arity overloading, ADR-0057) — **look an
  entry up with `entry/2`**, not a raw `report[name]` index, which silently returns
  `nil` for a bare name and crashes downstream.
  """
  @rian_sig "pub def analyze(prog Prog) Dict(String, _Unk)"
  @spec analyze(map()) :: map()
  def analyze(prog) do
    funs = all_funcs(prog)
    modnames = MapSet.new(Enum.map(Map.get(prog, :mods, []), & &1.name))
    local_names = MapSet.new(Enum.map(funs, & &1.name))
    pctx = parametric_ctx(prog, funs)

    facts =
      Map.new(funs, fn f ->
        {blockers, callees} = scan_func(f, modnames, pctx)
        # local reach = the closed vocabulary minus every target any blocker kills.
        # Host FFI/concurrency kill the non-BEAM targets; a `ref` capability kills
        # `:ex` (BEAM-rejected, ADR-0055/P5) — so the two compose correctly.
        killed = MapSet.new(Enum.flat_map(blockers, & &1.kills))

        # an `@external` function has no portable body — its reach is *exactly* the
        # targets that declare a host body (ADR-0068 §2). It has no call-graph edges.
        {local, callees} =
          case Map.get(f, :externals, %{}) do
            ext when map_size(ext) > 0 -> {MapSet.new(Map.keys(ext)), MapSet.new()}
            _ -> {MapSet.difference(MapSet.new(@targets), killed), callees}
          end

        {{f.name, length(f.params)},
         %{local: local, callees: MapSet.intersection(callees, local_names), blockers: blockers}}
      end)

    reach = fixpoint(facts, Map.new(facts, fn {n, fc} -> {n, fc.local} end))

    Map.new(facts, fn {{name, arity} = n, fc} ->
      {"#{name}/#{arity}", %{reach: Map.fetch!(reach, n), blockers: Enum.reverse(fc.blockers)}}
    end)
  end

  @doc """
  The inferred effect set of every function, keyed `"name/arity"` (ADR-0048 §3).

  A function's effects = its **direct** effects ∪ the effects of every callee, run to
  a call-graph fixpoint (union semantics — a caller has an effect iff it or any callee
  does). Direct effects come from the **same `scan_func` blockers `analyze/1` uses**, so
  the effect view and the reach view never disagree: a host-FFI blocker (`:ffi`) →
  `host`, a concurrency blocker (`:concurrency`) → `spawn`. An `@external` function has
  no portable body, so its effects are its **declared** set (the host body is the leaf,
  not inferable). Returns `%{"name/arity" => MapSet.t(effect)}`.
  """
  @rian_sig "pub def effect_sets(prog Prog) Dict(String, _Unk)"
  @spec effect_sets(map()) :: %{String.t() => MapSet.t(effect())}
  def effect_sets(prog) do
    funs = all_funcs(prog)
    modnames = MapSet.new(Enum.map(Map.get(prog, :mods, []), & &1.name))
    local_names = MapSet.new(Enum.map(funs, & &1.name))
    pctx = parametric_ctx(prog, funs)

    facts =
      Map.new(funs, fn f ->
        {blockers, callees} = scan_func(f, modnames, pctx)

        {direct, callees} =
          case Map.get(f, :externals, %{}) do
            ext when map_size(ext) > 0 ->
              {MapSet.new(Map.get(f, :effects, [])), MapSet.new()}

            _ ->
              {MapSet.new(Enum.flat_map(blockers, &effect_of/1)), callees}
          end

        {{f.name, length(f.params)},
         %{direct: direct, callees: MapSet.intersection(callees, local_names)}}
      end)

    effects = effect_fixpoint(facts, Map.new(facts, fn {n, fc} -> {n, fc.direct} end))
    Map.new(effects, fn {{name, arity}, set} -> {"#{name}/#{arity}", set} end)
  end

  # a blocker's effect contribution: host FFI carries `host` plus its world category
  # (a known module — `io`/`fs`/`random`/`net`, or a clock primitive), a concurrency
  # primitive `spawn`. Every other blocker kind (`ref`/`Int`/width/map/…) is a reach
  # concern, not an effect — it contributes nothing here.
  defp effect_of(%{kind: :ffi, construct: c}), do: [:host | ffi_category(c)]
  defp effect_of(%{kind: :concurrency}), do: [:spawn]
  defp effect_of(_blocker), do: []

  # the world-effect category of an FFI construct (`Mod.fun`/`:mod.fun`), or `[]` for
  # an uncatalogued host module (it stays `host`-only). Module-root for the clean
  # categories; function name for `clock` (its modules are mixed).
  defp ffi_category(construct) do
    segs = construct |> String.trim_leading(":") |> String.split(".")
    modroot = hd(segs)
    fun = List.last(segs)

    cond do
      Map.has_key?(@effect_mods, modroot) -> [Map.fetch!(@effect_mods, modroot)]
      fun in @clock_funs and modroot in @clock_mods -> [:clock]
      true -> []
    end
  end

  # effects(f) = direct(f) ∪ ⋃ effects(callee) — monotone-increasing, runs to a fixpoint.
  defp effect_fixpoint(facts, table) do
    next =
      Map.new(facts, fn {n, %{direct: direct, callees: cs}} ->
        {n, Enum.reduce(cs, direct, fn c, acc -> MapSet.union(acc, effect_for(table, c)) end)}
      end)

    if next == table, do: table, else: effect_fixpoint(facts, next)
  end

  # a name-folded callee contributes the *union* of its arities' effect sets — the
  # over-approximate (honest) direction for effects: never under-claim an effect a
  # caller might perform. No matching arity (external/unknown) contributes nothing.
  defp effect_for(table, name) do
    for({{^name, _arity}, s} <- table, do: s)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  @doc """
  Look a function's entry up in an `analyze/1` report.

  `key` is either the exact `"name/arity"` key or a **bare name** (the common case
  for non-overloaded code). The report keys by `"name/arity"`, so a raw
  `report[name]` index silently returns `nil` for a bare name and then crashes
  downstream — this resolves the bare name and **raises a clear error** when the
  name is absent or overloaded (ambiguous), naming the available keys. Pass the
  full `"name/arity"` key to disambiguate an overload.
  """
  @rian_sig "pub def entry(report Dict(String, _Unk), key String) _Unk"
  @spec entry(map(), String.t()) :: map()
  def entry(report, key) when is_map_key(report, key), do: report[key]

  def entry(report, name) do
    case Enum.filter(report, fn {k, _v} -> bare_name(k) == name end) do
      [{_k, v}] ->
        v

      [] ->
        raise KeyError,
          message:
            "no function #{inspect(name)} in reach report (have: #{inspect(Map.keys(report) |> Enum.sort())})"

      many ->
        raise ArgumentError,
              "#{inspect(name)} is overloaded (#{inspect(Enum.map(many, &elem(&1, 0)) |> Enum.sort())}); " <>
                "pass the full \"name/arity\" key"
    end
  end

  @rian_sig "pub def bare_name(key String) String"
  @doc "The bare function name of a `\"name/arity\"` report key (drops `/arity`)."
  @spec bare_name(String.t()) :: String.t()
  def bare_name(key), do: key |> String.split("/") |> hd()

  @doc """
  Check every `mod`'s `@targets(…)` contract (ADR-0058 §2): each `pub` function
  in a module that declares a target set must *reach* every target in it. A
  module with no contract (`targets: nil`) falls back to the **build default**
  (`default`, ADR-0058 §2 — `mix.exs` `rian: [targets: […]]`); when that is also
  nil the module is not gated — constraints are selected by need. Returns `:ok`
  or `{:error, message}`.
  """
  @rian_sig "pub def check_contracts(prog Prog) _Unk"
  @rian_sig "pub def check_contracts(prog Prog, default _Unk) _Unk"
  @spec check_contracts(map(), term()) :: :ok | {:error, String.t()}
  def check_contracts(prog, default \\ nil) do
    reach = analyze(prog)

    violations =
      for mod <- Map.get(prog, :mods, []),
          required = or_default(mod.targets, default),
          required != nil,
          f <- mod.funcs,
          f.pub?,
          key = "#{f.name}/#{length(f.params)}",
          missing =
            required -- MapSet.to_list(or_default(reach[key][:reach], MapSet.new(@targets))),
          missing != [] do
        {mod.name, f.name, Enum.sort(missing)}
      end

    case violations do
      [] -> :ok
      vs -> {:error, contract_message(vs)}
    end
  end

  # a value, or the fallback when it is absent (`nil`) — explicit nil-match in place
  # of the truthy `||`, so it lowers to clean clause dispatch on every target.
  defp or_default(nil, fallback), do: fallback
  defp or_default(value, _fallback), do: value

  @doc "Raise `Rian.Reach.Error` on any unmet `@targets(…)` contract, else `:ok`."
  @rian_sig "pub def gate!(prog Prog) Symbol"
  @spec gate!(map()) :: :ok
  def gate!(prog), do: gate!(prog, build_default())

  @doc "Gate against an explicit build-default target set (`nil` = none)."
  @rian_sig "pub def gate!(prog Prog, default _Unk) Symbol"
  @spec gate!(map(), term()) :: :ok
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
  @rian_sig "pub def symbol_lint!(prog Prog) Symbol"
  @spec symbol_lint!(map()) :: :ok
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
  The build-default target set (ADR-0058 §2) for modules that declare no `@targets`,
  resolved in priority: a `rian.toml` manifest's `targets` (ADR-0080 §2, the canonical
  source for a real Rian project) — consulted only when its path is configured via the
  `:rian_lab` app env `:rian_manifest` (the escript CLI sets it at `main/1`) — else the
  `:rian_lab` app env `:rian_targets`, else `mix.exs`'s `rian: [targets: […]]`, else
  `nil` (no default gate).

  The manifest is sourced from configuration, **never** read from the working directory
  by the deep per-compile `gate!/1`: a REPL/test/library compile is never silently
  re-gated by a stray `rian.toml` in whatever directory it happens to run from.
  """
  @rian_sig "pub def build_default() Vec(Symbol)"
  def build_default do
    # priority fall-through without truthy `||` (errors-as-values, ADR-0035): each
    # source returns `nil` when absent; `with nil <- …` carries the first non-nil out.
    resolved =
      with nil <- manifest_default(),
           nil <- app_env_default() do
        mix_default()
      end

    validate_default(resolved)
  end

  # the manifest is the single project-metadata source (ADR-0080 §2); its `targets`
  # are already validated by `Rian.Manifest`. It is read only from the configured
  # `:rian_manifest` path (the build CLI's project context) — never the CWD on its own,
  # so the gate stays deterministic outside a build. Absent/invalid -> fall through.
  defp manifest_default do
    with path when is_binary(path) <- Application.get_env(:rian_lab, :rian_manifest),
         {:ok, %Rian.Manifest{targets: [_ | _] = ts}} <- Rian.Manifest.read(path) do
      ts
    else
      _ -> nil
    end
  end

  defp app_env_default, do: Application.get_env(:rian_lab, :rian_targets)

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
           MapSet.intersection(acc, reach_for(table, c))
         end)}
      end)

    if next == table, do: table, else: fixpoint(facts, next)
  end

  # The local call graph names callees by bare name (arity is not tracked on the
  # edge), while the reach table is keyed by `{name, arity}` (arity overloading).
  # A name-folded callee therefore contributes the *intersection* of its arities'
  # reaches: a caller keeps a target only if every same-named definition reaches
  # it. This is the conservative direction — it can under-claim an overloaded
  # callee's reach but never over-claims (the honesty bar). No matching arity
  # (an external/unknown name) imposes no constraint.
  defp reach_for(table, name) do
    case for {{^name, _arity}, r} <- table, do: r do
      [] -> MapSet.new(@targets)
      rs -> Enum.reduce(rs, &MapSet.intersection/2)
    end
  end

  defp all_funcs(prog),
    do: Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

  # scan every clause body (and guard) of one function for ex-only constructs + local-call edges
  defp scan_func(f, modnames, pctx) do
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
    # `Any` is the deliberate top type (ADR-0034) — a value of genuinely-dynamic shape. The
    # BEAM erases type annotations (native), JS is dynamic (an untyped value), and JVM maps it
    # to Kotlin `Any` — so `Any` reaches those three. Only Rust has no ergonomic top value, so
    # `Any` pins off `:rs` alone. This is distinct from `_Unk`, an *unfinished* hole that
    # `Rian.Check` rejects outright — `Any` is a real, reported reach contract.
    any = if Enum.any?(sig_types, &type_mentions_any?/1), do: [any_blocker()], else: []
    # `Any` reaches `:jvm` only as a *pass-through* value (Kotlin `Any`): union erasure,
    # `List<Any>`, a returned/forwarded param. Kotlin `Any` has NO operators, so an `Any`
    # value fed to a non-equality operator (`x + 1`, `x < y`, `x <> s`, `x and y`) does not
    # compile — kotlinc rejects `plus`/`compareTo`/… on `Any`. Pin `:jvm` when a clause
    # applies such an operator directly to an `Any`-typed parameter (`:js` stays — JS is
    # dynamic and runs it). RESIDUAL: an `Any` value reaching an operator *indirectly* (via
    # a `:=` bind or an `Any`-returning call) is not yet detected — the direct-operand case
    # is the common, demonstrated one (the matrix can still over-claim `:jvm` for the rest).
    any_op = if any_param_in_jvm_op?(f), do: [any_jvm_op_blocker()], else: []
    # a value-union type `A | B` (canonical `Union(...)`, ADR-0083). A NARROWABLE union
    # (every member primitive/sum/struct with a DISTINCT runtime discriminator) narrows
    # on every target — BEAM/JS (`is`/`typeof`/tag/`__struct__`), JVM (`Any`+`when is`),
    # Rust (synthesized `enum`+`match`+`From`, construction-wrapped at call AND return) —
    # in both parameter and return position, so it kills nothing. A non-narrowable union
    # (a tvar member, a discriminator clash, or a nested union) pins off EVERY target.
    union_kills = sig_types |> Enum.flat_map(&union_kills(&1, pctx)) |> Enum.uniq()
    union = if union_kills == [], do: [], else: [union_blocker(union_kills)]
    # Two Rust-generic emitter gaps (ADR-0061/0047) the reach matrix must own up to,
    # or `mix rian.targets`/the conformance gate green-lights `:rs` for code `rustc`
    # then rejects (the gate lying). It pins the function off `:rs` only — generics the
    # emitter *does* lower (`contains`/`sort`/`maximum`, and parametric `Pair` over
    # `enum Pair<K,V>`) keep `:rs`.
    #
    # An `Fn(...)` function type anywhere in the signature (a parameter or the return)
    # `Fn(...)` lowering is complete (ADR-0061): a callback PARAMETER → `&impl Fn(...)`, a
    # returned closure → `Box<dyn Fn(...)>` (`Box::new(move …)`) whether the `Fn` is
    # top-level (`adder() Fn(Int53, Int53)`, `mk(x T) Fn(Int53, T)`) or NESTED in the return
    # (`Option`/`Result`/`Vec(Fn(…, T))` — a value-position closure boxes at the `ELambda`
    # emit), and HOFs (`map(f Fn(T, U), …)`). So no `Fn`-bearing signature is pinned off
    # `:rs` any more. (The owned↔borrow coercion for bare `T`/`Vec(T)` returns and
    # `Option(T)`/`Result(T, E)`/sum-over-`T` landed 2026-06-14 and is likewise not blocked.)
    # A function whose signature touches a *parametric* user type (`Pair`, `enum
    # Pair<K,V>`) reaches `:rs` only for the narrow shape the emitter actually lowers
    # (`Rian.Lower`): the type's tvar fields are all *bare* tvars, and the function
    # either only matches/passes the value, constructs it with positionally-aligned
    # tvar args, or is a non-generic builder whose tail is a direct call to a generic
    # helper (so the concrete instantiation is inferable). Everything else emits
    # undeclared generics or the wrong `i64` instantiation, so it pins off `:rs` —
    # the matrix stays honest rather than green-lighting code rustc rejects (ADR-0061).
    param = if parametric_rs_ok?(f, pctx), do: [], else: [parametric_blocker()]
    # a bitstring pattern in a clause head is BEAM-only (ADR-0078) — inspect the
    # heads (the one place a clause-head pattern is checked) so the matrix matches
    # the emitters. (An as-pattern `name @ pat` lowers on every target now, so it
    # pins nothing.)
    bit_pat =
      if Enum.any?(f.clauses, fn c -> Enum.any?(c.pats, &pat_has_bitstr?/1) end),
        do: [bitstr_blocker()],
        else: []

    # a pin `^x` in a clause head: lowered on BEAM (repeated-var equality) and JS/JVM
    # (an `==` test against the pinned value); Rust has no match-guard transform yet,
    # so a pin pins the function off `:rs` only (honest against the emitters).
    pin =
      if Enum.any?(f.clauses, fn c -> Enum.any?(c.pats, &pat_has_pin?/1) end),
        do: [pin_blocker()],
        else: []

    # a generated runtime protocol DISPATCHER (`dispatch: :dispatcher`, ADR-0042) is a
    # guarded runtime type-test that selects an impl by the value's shape. Every target
    # lowers it now — BEAM (guarded clauses), JS (`typeof`/tag), Rust (monomorphised
    # trait), and JVM (a `when (a0)` over `is <Type>`). An **associated type** (ADR-0074)
    # in the return is fine when it sits in a covariant `Vec(...)` — it erases to JVM
    # `List<Any>` (`Foldable.to_list() Vec(Elem)` reaches `:jvm`). It only pins off `:jvm`
    # when it appears where the JVM can't erase it: a parameter (contravariant) or a bare
    # non-`Vec` return. Callers inherit the pin through the reach fixpoint.
    disp =
      if Map.get(f, :dispatch) == :dispatcher and assoc_blocks_jvm?(f, pctx.assoc),
        do: [dispatch_blocker()],
        else: []

    Enum.reduce(
      f.clauses,
      {ref ++
         int ++
         width ++
         any ++ any_op ++ union ++ param ++ bit_pat ++ pin ++ disp, MapSet.new()},
      fn c, acc ->
        acc = scan(core(c.body, &Pratt.parse_body/1), modnames, acc)
        if c.guard, do: scan(core(c.guard, &Pratt.parse/1), modnames, acc), else: acc
      end
    )
  end

  # a surface clause-head pattern contains a bitstring pattern `{:bitstr_pat, …}`?
  defp pat_has_bitstr?({:bitstr_pat, _segs}), do: true

  defp pat_has_bitstr?(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.any?(&pat_has_bitstr?/1)

  defp pat_has_bitstr?(l) when is_list(l), do: Enum.any?(l, &pat_has_bitstr?/1)
  defp pat_has_bitstr?(_), do: false

  # a surface clause-head pattern contains a pin `{:pin, expr}`?
  defp pat_has_pin?({:pin, _expr}), do: true

  defp pat_has_pin?(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.any?(&pat_has_pin?/1)

  defp pat_has_pin?(l) when is_list(l), do: Enum.any?(l, &pat_has_pin?/1)
  defp pat_has_pin?(_), do: false

  defp ref_blocker, do: %{construct: "ref capability (&mut)", kind: :capability, kills: [:ex]}

  defp int_blocker,
    do: %{construct: "Int (arbitrary precision)", kind: :numeric, kills: [:rs, :jvm]}

  defp any_blocker,
    do: %{construct: "Any (top type)", kind: :typed, kills: [:rs]}

  defp any_jvm_op_blocker,
    do: %{
      construct: "Any value in a typed operator (Kotlin `Any` has no operators)",
      kind: :typed,
      kills: [:jvm]
    }

  # Kotlin `Any` supports only structural equality; every other operator needs a concrete
  # operand type, so an `Any`-typed operand there does not compile (kotlinc `unresolved
  # reference 'plus'/'compareTo'/…`). `:js` is dynamic and runs them, so only `:jvm` pins.
  @any_jvm_ok_ops ["==", "!="]

  # Does a clause apply a non-equality operator directly to an `Any`-typed parameter?
  defp any_param_in_jvm_op?(f) do
    any_names =
      for p <- Map.get(f, :params, []), p.type == "Any", into: MapSet.new(), do: p.name

    any_names != MapSet.new() and
      Enum.any?(Map.get(f, :clauses, []), fn c ->
        c.body |> core(&Pratt.parse_body/1) |> any_op_node?(any_names)
      end)
  end

  defp any_op_node?(%Core.EBin{op: op, left: l, right: r}, names) do
    (op not in @any_jvm_ok_ops and (any_operand?(l, names) or any_operand?(r, names))) or
      any_op_node?(l, names) or any_op_node?(r, names)
  end

  defp any_op_node?(node, names) when is_struct(node),
    do: node |> Map.from_struct() |> Map.values() |> Enum.any?(&any_op_node?(&1, names))

  defp any_op_node?(list, names) when is_list(list), do: Enum.any?(list, &any_op_node?(&1, names))

  defp any_op_node?(tuple, names) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&any_op_node?(&1, names))

  defp any_op_node?(_, _names), do: false

  defp any_operand?(%Core.EId{name: n}, names), do: MapSet.member?(names, n)
  defp any_operand?(_, _names), do: false

  # a signature type that *is* `Any` or mentions it inside a generic (`Vec(Any)`, `Dict(String,
  # Any)`): the dynamic value flows through, so the pin applies. Word-boundary match avoids
  # false hits on user types that merely contain the substring (`AnyThing`).
  defp type_mentions_any?(t) when is_binary(t), do: Regex.match?(~r/\bAny\b/, t)
  defp type_mentions_any?(_), do: false

  defp union_blocker(kills),
    do: %{construct: "value union (A | B)", kind: :typed, kills: kills}

  # the targets a value-union signature type kills (ADR-0083), in any position. A
  # `:narrowable` union — every member runtime-discriminable (a primitive `is`/`typeof`,
  # a sum tag, or a struct `__struct__`) with DISTINCT discriminators — narrows on EVERY
  # target (BEAM, JS, JVM, Rust), constructed by `Enum::from` at the call site and the
  # return tail, so it kills nothing. `:neither` (a tvar member, a discriminator clash
  # like `Int32 | Char`, or a nested union) kills all.
  defp union_kills(t, pctx) when is_binary(t) do
    case union_class(t, pctx) do
      :none -> []
      :narrowable -> []
      :neither -> [:ex, :rs, :js, :jvm]
    end
  end

  defp union_kills(_, _), do: []

  # classify a union type string: `:none` (not a union), `:narrowable` (every member a
  # primitive/sum/struct with a runtime discriminator, all DISTINCT), or `:neither` (a
  # tvar member, a clash — `Int32 | Char` both test `is_integer`, a dead arm — or a
  # nested/malformed union).
  defp union_class(t, pctx) do
    if String.contains?(t, "Union(") do
      case union_members(t) do
        nil ->
          :neither

        members ->
          discs = Enum.map(members, &discriminator(&1, pctx))
          distinct? = Enum.all?(discs, &(&1 != nil)) and length(Enum.uniq(discs)) == length(discs)
          if distinct?, do: :narrowable, else: :neither
      end
    else
      :none
    end
  end

  # the members of a TOP-LEVEL `Union(...)`, or nil if malformed or nested (a member
  # mentioning `Union(` can't be narrowed by a flat type-pattern).
  defp union_members("Union(" <> rest) do
    if String.ends_with?(rest, ")") do
      members = rest |> binary_part(0, byte_size(rest) - 1) |> Rian.TypeStr.split_top_commas()
      if Enum.any?(members, &String.contains?(&1, "Union(")), do: nil, else: members
    else
      nil
    end
  end

  defp union_members(_), do: nil

  # the runtime discriminator a member narrows under: a primitive's `is_*`/`typeof`
  # class, a UNIQUE `{:sum, name}`/`{:struct, name}` for a user type (distinct ctors
  # make distinct sums distinguishable), or nil for a tvar / unknown type. `Char`/`Int*`/
  # `UInt*` share `:integer` (a clash).
  defp discriminator(t, pctx) do
    cond do
      t == "Bool" -> :boolean
      t == "String" -> :binary
      t == "Char" -> :integer
      Regex.match?(~r/^U?Int\d*$/, t) -> :integer
      Regex.match?(~r/^Float\d*$/, t) -> :float
      MapSet.member?(Map.get(pctx, :sum_names, MapSet.new()), t) -> {:sum, t}
      MapSet.member?(Map.get(pctx, :struct_names, MapSet.new()), t) -> {:struct, t}
      true -> nil
    end
  end

  defp width_blocker,
    do: %{
      construct: "fixed-width integer >2^53 (no JS representation)",
      kind: :numeric,
      kills: [:js]
    }

  defp wide_prim_blocker,
    do: %{construct: "64-bit overflow op (no JS representation)", kind: :numeric, kills: [:js]}

  # `__prim_to_string` is the runtime `Show` fallthrough for an `:unknown`-typed
  # interpolation hole (ADR-0069 §2). BEAM/JS/JVM have a universal runtime stringifier
  # (`String.Chars.to_string` / `String(x)` / `.toString()`), but Rust has no universal
  # `Display`, so a body that runtime-stringifies an unknown value is off `:rs` — the gate
  # matches the emitters (the Rust arm is best-effort and not selected for a portable fn).
  defp to_string_prim_blocker,
    do: %{
      construct: "`Prim.to_string` (runtime Show — no universal Rust Display)",
      kind: :prim,
      kills: [:rs]
    }

  # `__prim_str_to_atom` interns a string to a BEAM atom — only the BEAM emitter
  # lowers it (Rust/JS/JVM have no atom value). A body that calls it is BEAM-only,
  # so the gate matches the emitters (off `:rs`/`:js`/`:jvm`), never lying.
  defp atom_prim_blocker,
    do: %{
      construct: "`Prim.str_to_atom` (atom is BEAM-only)",
      kind: :atom,
      kills: [:rs, :js, :jvm]
    }

  defp parametric_blocker,
    do: %{
      construct: "parametric user type beyond the Rust emitter's monomorphic subset",
      kind: :generic,
      kills: [:rs]
    }

  # A map literal `%{…}` (ADR-0033): lowered on the BEAM (native map) and on JS (a
  # plain object, `Rian.JS`'s `EMap` clause), but **not** on Rust (`Rian.Lower` raises
  # "map literals are BEAM-only in PoC") or JVM (`Core.EMap` is in `@jvm_unsupported`).
  # A constructed map therefore pins the function off `:rs`/`:jvm` — the matrix reports
  # what the emitters actually lower, not the aspiration (same principle as bare atoms,
  # ADR-0000). The map *update* form `%{base | k: v}` (ADR-0033, `Core.EMapUpdate`) has
  # the same target story — BEAM/JS lower it, Rust/JVM raise — so it carries its own
  # blocker below; both surface as `kind: :map`.
  defp map_literal_blocker(pairs) do
    if Enum.any?(pairs, &computed_key_pair?/1),
      do: %{construct: "non-atom map key (`%{expr => v}`)", kind: :map, kills: [:rs, :js, :jvm]},
      else: %{construct: "map literal (`%{…}`)", kind: :map, kills: [:rs, :jvm]}
  end

  # a computed (non-atom) map pair `{{:key, expr}, value}` vs an atom-key `{k, value}`.
  defp computed_key_pair?({{:key, _}, _}), do: true
  defp computed_key_pair?(_), do: false

  # A bitstring `<<seg::spec, …>>` (ADR-0078): lowered natively on the BEAM (Erlang
  # bitstring forms) and via `Rian.Lower`'s Elixir text, but **not** on Rust/JS/JVM
  # (no faithful bit-level lowering yet — those emitters raise `Unsupported`). So a
  # bitstring pins the function BEAM-only — the matrix matches the emitters (ADR-0000).
  defp bitstr_blocker,
    do: %{construct: "bitstring (`<<…>>`)", kind: :bitstring, kills: [:rs, :js, :jvm]}

  # A pin `^x` (ADR-0050): the BEAM lowers it (repeated-var equality), JS/JVM emit an
  # `==` test against the pinned value, and `Rian.Lower`'s Elixir text emits `^x`; only
  # the Rust emitter lacks a match-guard transform, so a pin pins the function off `:rs`.
  defp pin_blocker,
    do: %{construct: "pin (`^x`)", kind: :pin, kills: [:rs]}

  # does an associated type appear where the JVM can't erase it to `Any` — a parameter
  # (contravariant) or a bare/non-`Vec` return? Inside a covariant `Vec(...)` return it
  # erases to `List<Any>` (`Foldable.to_list() Vec(Elem)` reaches `:jvm`), so the `Vec(...)`
  # wrapper is stripped before the check. Mirrors `Rian.JVM.assoc_blocks_jvm?`.
  defp assoc_blocks_jvm?(f, assoc) do
    param_types = Enum.map(Map.get(f, :params, []), & &1.type)
    ret_bare = f |> Map.get(:ret) |> to_string() |> String.replace(~r/Vec\([^()]*\)/, "")

    Enum.any?([ret_bare | param_types], fn t ->
      Enum.any?(assoc, &Regex.match?(~r/\b#{Regex.escape(&1)}\b/, t))
    end)
  end

  # A protocol dispatcher whose associated type sits in a position the JVM can't erase
  # (a parameter or a bare return, ADR-0074): every other dispatcher lowers, but this one
  # has no concrete Kotlin shape there, so `Rian.JVM` drops it and it pins off `:jvm`.
  defp dispatch_blocker,
    do: %{construct: "associated-type protocol dispatch", kind: :dispatch, kills: [:jvm]}

  defp map_update_blocker(pairs) do
    if Enum.any?(pairs, &computed_key_pair?/1),
      do: %{
        construct: "non-atom map key (`%{base | expr => v}`)",
        kind: :map,
        kills: [:rs, :js, :jvm]
      },
      else: %{construct: "map update (`%{base | …}`)", kind: :map, kills: [:rs, :jvm]}
  end

  # A `Result` value `{:ok, _}` / `{:error, _}` (ADR-0040): lowered on the BEAM (tagged
  # tuple), Rust (`Ok`/`Err`), and JS (`["ok", v]`, `Rian.JS`), but **not** on JVM (its
  # emitter has no tuple/`case` lowering yet). So a constructed Result pins the function
  # off `:jvm` only — honest against the emitters.
  defp result_value_blocker,
    do: %{construct: "Result value (`{:ok,_}`/`{:error,_}`)", kind: :result, kills: [:jvm]}

  # Does a type string contain a type-variable token? `tvar?` is the compiler-wide
  # convention (`Rian.Check`): a single capital optionally followed by a digit.
  defp type_has_tvar?(t) when is_binary(t), do: Enum.any?(type_idents(t), &tvar?/1)
  defp type_has_tvar?(_), do: false

  # the identifier tokens of a type string: `Vec(Pair)` → `["Vec", "Pair"]`,
  # `Tree(T)` → `["Tree", "T"]`.
  defp type_idents(t) when is_binary(t), do: Regex.scan(~r/[A-Za-z_]\w*/, t) |> Enum.map(&hd/1)

  defp tvar?(t), do: String.match?(t, ~r/^[A-Z][0-9]?$/)

  # ── parametric user types: the Rust monomorphic-emit subset (ADR-0061) ──────
  # Program-wide facts the parametric `:rs` gate needs: which user types are
  # parametric and which of those the emitter can lower, each parametric
  # constructor's ordered field tvars, and which local functions are generic (a
  # non-generic builder is lowerable only when its tail calls a generic helper).
  defp parametric_ctx(prog, funs) do
    types =
      Map.get(prog, :types, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :types, []))

    ptypes = expand_ptypes(types)

    structs =
      Map.get(prog, :structs, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :structs, []))

    %{
      names: MapSet.new(ptypes, & &1.name),
      # all sum + struct type names — a value-union member of one of these is
      # runtime-discriminable (a tag / `__struct__` test), so it narrows on
      # `:ex`/`:jvm`/`:rs` (ADR-0083). A non-parametric sum is included (a tvar is not).
      sum_names: MapSet.new(types, & &1.name),
      struct_names: MapSet.new(structs, & &1.name),
      emittable: emittable_map(ptypes, MapSet.new(ptypes, & &1.name)),
      ctors:
        for(
          t <- ptypes,
          v <- t.variants,
          into: %{},
          do: {v.ctor, Enum.map(v.fields, &Map.get(&1, :type))}
        ),
      generics: MapSet.new(for f <- funs, Map.get(f, :tvars, []) != [], do: f.name),
      # user types with an `Fn(...)` field: their Rust `Rc<dyn Fn>` field is not `PartialEq`/
      # `Debug`, so a function that `==`/`!=`s such a value can't lower (pinned off `:rs`).
      fn_field_names:
        MapSet.new(
          for t <- types,
              Enum.any?(t.variants, fn v ->
                Enum.any?(v.fields, &String.contains?(to_string(Map.get(&1, :type)), "Fn("))
              end),
              do: t.name
        ),
      # associated-type names (ADR-0074): a dispatcher returning one can't be given a
      # concrete Kotlin return type, so it stays off `:jvm` (`Rian.JVM` drops it).
      assoc:
        Map.get(prog, :protocols, [])
        |> Enum.flat_map(&Map.get(&1, :assoc, []))
        |> MapSet.new()
    }
  end

  # The parametric user types: those with a tvar field, PLUS any type that references one
  # (a `Wrap(p Pair)`/`Bag(ps Vec(Pair))` is itself generic over the nested type's params,
  # so it needs its own emittability gating). A fixpoint outward from the tvar-bearing base.
  defp expand_ptypes(types) do
    base = MapSet.new(Enum.filter(types, &parametric_type?/1), & &1.name)
    names = grow_ptypes(types, base)
    Enum.filter(types, &MapSet.member?(names, &1.name))
  end

  defp grow_ptypes(types, names) do
    next =
      MapSet.union(names, MapSet.new(for t <- types, references?(t, names), do: t.name))

    if next == names, do: names, else: grow_ptypes(types, next)
  end

  defp references?(t, names) do
    t.variants
    |> Enum.flat_map(& &1.fields)
    |> Enum.any?(fn f ->
      Enum.any?(type_idents(to_string(Map.get(f, :type))), &MapSet.member?(names, &1))
    end)
  end

  # A user `type` is *directly* parametric iff some variant field's type mentions a tvar.
  defp parametric_type?(t) do
    Enum.any?(t.variants, fn v -> Enum.any?(v.fields, &type_has_tvar?(Map.get(&1, :type))) end)
  end

  # Which parametric types the Rust emitter can lower, as a name→bool map. A type is
  # emittable when every field is lowerable: a non-reference tvar field (bare / `Vec` /
  # `Option` / `Result`, via `lowerable_field?`), a concrete field, OR an exact-bare
  # reference to ANOTHER parametric type that is itself emittable (`Wrap(p Pair)` →
  # `enum Wrap<K,V> { W { p: Pair<K,V> } }`, ADR-0061). A monotone fixpoint from
  # all-false: a leaf resolves first, a chain resolves outward, and a reference CYCLE
  # (self- or mutual-recursion — an infinitely-sized Rust type that would need `Box`)
  # never bootstraps, so it stays pinned. A parametric name nested in a compound
  # (`Vec(Pair)`) surfaces no args and is likewise not lowerable.
  defp emittable_map(ptypes, pnames) do
    converge_emittable(ptypes, pnames, Map.new(ptypes, &{&1.name, false}))
  end

  defp converge_emittable(ptypes, pnames, acc) do
    next = Map.new(ptypes, fn t -> {t.name, all_fields_emittable?(t, pnames, acc)} end)
    if next == acc, do: next, else: converge_emittable(ptypes, pnames, next)
  end

  defp all_fields_emittable?(t, pnames, acc) do
    t.variants
    |> Enum.flat_map(& &1.fields)
    |> Enum.map(&Map.get(&1, :type))
    |> Enum.all?(&field_emittable?(&1, pnames, acc))
  end

  defp field_emittable?(ft, pnames, acc) do
    cond do
      MapSet.member?(pnames, ft) -> Map.get(acc, ft, false)
      mentions_any?(ft, pnames) -> false
      type_has_tvar?(ft) -> lowerable_field?(ft)
      true -> true
    end
  end

  # does a type string name any of `pnames` among its identifier tokens?
  defp mentions_any?(ft, pnames), do: Enum.any?(type_idents(ft), &MapSet.member?(pnames, &1))

  # a tvar-bearing field type the Rust emitter lowers correctly (see `field_emittable?`).
  defp lowerable_field?(type) do
    cond do
      not type_has_tvar?(type) ->
        true

      tvar?(type) ->
        true

      # an `Fn(...)` field lowers to a shared `Rc<dyn Fn>` field (ADR-0061): the type is
      # `Clone` (not `Debug`/`PartialEq`), so construction/storage/call reach `:rs`; a
      # function that `==`/interpolates such a value is pinned separately (`compares_fn_field?`).
      String.starts_with?(type, "Fn(") ->
        true

      true ->
        case compound_args(type) do
          nil -> false
          args -> Enum.all?(args, &lowerable_field?/1)
        end
    end
  end

  # the type args of a supported generic wrapper (`Vec`/`Option`/`Result`), else `nil`:
  # `"Vec(T)"` → `["T"]`, `"Result(T, E)"` → `["T", "E"]`, `"Dict(K, V)"` → `nil`.
  defp compound_args(type) do
    case Regex.run(~r/^(?:Vec|Option|Result)\((.*)\)$/, type) do
      [_, inner] -> Rian.TypeStr.split_top_commas(inner)
      _ -> nil
    end
  end

  # Does the function's signature (params or return) name a parametric type?
  defp uses_parametric?(f, names) do
    f
    |> sig_idents()
    |> Enum.any?(&MapSet.member?(names, &1))
  end

  defp sig_idents(f) do
    sig = Enum.map(Map.get(f, :params, []), & &1.type) ++ [Map.get(f, :ret)]
    for t <- sig, is_binary(t), id <- type_idents(t), do: id
  end

  # The parametric `:rs` allow-list. A function reaches `:rs` (parametric-wise) iff
  # it uses no parametric type, or every used type is emittable AND its construction
  # / builder shape is one the emitter monomorphizes correctly. Default-deny: any
  # shape outside the verified subset pins off `:rs` so the matrix never oversells.
  defp parametric_rs_ok?(f, pctx) do
    cond do
      # a type with an `Fn(...)` field lowers to an `Rc<dyn Fn>` field — `Clone` but NOT
      # `PartialEq` (a closure has no portable equality), so a function that `==`/`!=`s such
      # a value can't lower to Rust; pin it (the data-flow shapes still reach `:rs`).
      compares_fn_field?(f, pctx) ->
        false

      not uses_parametric?(f, pctx.names) ->
        true

      # F2: a used parametric type has a non-bare-tvar field → undeclared generics.
      not all_emittable?(f, pctx) ->
        false

      Map.get(f, :tvars, []) != [] ->
        # F3: a generic builder is correct only when every construction's args match
        # the field tvars positionally (`P(key, value)` with key:K, value:V).
        Enum.all?(parametric_constructions(f, pctx.ctors), &ctor_aligned?(&1, f))

      true ->
        # F1: a non-generic function must not construct a parametric type directly
        # (no instantiation to infer) and must tail-call a generic helper, the only
        # shape `Rian.Lower.infer_concrete_params` binds to a concrete `Pair<…>`.
        parametric_constructions(f, pctx.ctors) == [] and builder_tail_ok?(f, pctx.generics)
    end
  end

  # a function whose signature mentions a type with an `Fn(...)` field AND whose body does an
  # equality (`==`/`!=`) — conservatively pinned off `:rs` (the `Rc<dyn Fn>` field is not
  # `PartialEq`). Construction/storage/call of such a type are unaffected and reach `:rs`.
  defp compares_fn_field?(f, pctx) do
    uses_parametric?(f, pctx.fn_field_names) and body_has_eq?(f)
  end

  defp body_has_eq?(f) do
    Enum.any?(Map.get(f, :clauses, []), fn c -> has_eq?(core(c.body, &Pratt.parse_body/1)) end)
  end

  defp has_eq?(%Core.EBin{op: op}) when op in ["==", "!="], do: true

  defp has_eq?(node) when is_struct(node),
    do: node |> Map.from_struct() |> Map.values() |> Enum.any?(&has_eq?/1)

  defp has_eq?(list) when is_list(list), do: Enum.any?(list, &has_eq?/1)
  defp has_eq?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.any?(&has_eq?/1)
  defp has_eq?(_), do: false

  defp all_emittable?(f, pctx) do
    f
    |> sig_idents()
    |> Enum.filter(&MapSet.member?(pctx.names, &1))
    |> Enum.uniq()
    |> Enum.all?(&Map.get(pctx.emittable, &1, false))
  end

  # Every parametric construction `P(args)` reachable in the body, as
  # `{ordered_field_tvars, args}` (args are core nodes).
  defp parametric_constructions(f, ctors) do
    Enum.flat_map(f.clauses, fn c -> collect_ctors(core(c.body, &Pratt.parse_body/1), ctors) end)
  end

  defp collect_ctors(%Core.ECall{fun: %Core.EId{name: n}, args: args}, ctors) do
    here = if Map.has_key?(ctors, n), do: [{Map.fetch!(ctors, n), args}], else: []
    here ++ Enum.flat_map(args, &collect_ctors(&1, ctors))
  end

  defp collect_ctors(node, ctors) when is_struct(node),
    do: node |> Map.from_struct() |> Map.values() |> Enum.flat_map(&collect_ctors(&1, ctors))

  defp collect_ctors(list, ctors) when is_list(list),
    do: Enum.flat_map(list, &collect_ctors(&1, ctors))

  defp collect_ctors(tuple, ctors) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.flat_map(&collect_ctors(&1, ctors))

  defp collect_ctors(_other, _ctors), do: []

  # A construction is emittable iff each field/arg pair lowers: a *bare-tvar* field needs a
  # bare-parameter arg whose declared type is exactly that tvar (the emitter assigns the
  # field type with no coercion, so a mismatch is rustc E0308); a *lowerable compound* field
  # (`Vec(T)`/`Option(T)`/…) accepts any well-typed arg — the construction coercion clones
  # the payload (`S([x | items])`, `B(Some(x))` are rustc-verified, ADR-0061).
  defp ctor_aligned?({field_types, args}, f) do
    ptypes = Map.new(Map.get(f, :params, []), &{&1.name, &1.type})

    length(field_types) == length(args) and
      field_types
      |> Enum.zip(args)
      |> Enum.all?(fn {ft, arg} ->
        cond do
          tvar?(ft) -> match?(%Core.EId{}, arg) and Map.get(ptypes, arg.name) == ft
          true -> lowerable_field?(ft)
        end
      end)
  end

  defp builder_tail_ok?(f, generics) do
    Enum.all?(f.clauses, fn c ->
      case core(c.body, &Pratt.parse_body/1) do
        %Core.EBlock{stmts: stmts} -> tail_calls_generic?(List.last(stmts), generics)
        _ -> false
      end
    end)
  end

  defp tail_calls_generic?({:expr, %Core.ECall{fun: %Core.EId{name: h}}}, generics),
    do: MapSet.member?(generics, h)

  defp tail_calls_generic?(_stmt, _generics), do: false

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

  # A Result value `{:ok, v}` / `{:error, e}` (ADR-0040): off `:js`/`:jvm` (their
  # emitters don't lower the tag atom), fine on `:ex`/`:rs`. Scan only the payload —
  # the `:ok`/`:error` tag is consumed here, NOT re-flagged as a bare value atom
  # (which would wrongly also kill `:rs`, where Rust lowers it to `Ok`/`Err`).
  defp scan(%Core.ETuple{elems: [%Core.EAtom{name: t}, v]}, modnames, {bl, ca})
       when t in ~w(ok error),
       do: scan(v, modnames, {[result_value_blocker() | bl], ca})

  # An Erlang FFI call `:mod.fun(args)`: classify it (the FFI blocker) then scan only
  # the args — the `:mod` atom head is the FFI module name, already covered, not a
  # value atom to re-flag as a bare-atom blocker.
  defp scan(%Core.ECall{fun: %Core.EDot{head: %Core.EAtom{}}, args: args} = node, modnames, acc),
    do: Enum.reduce(args, classify(node, modnames, acc), &scan(&1, modnames, &2))

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

  # Elixir-module call `Mod.fun(…)` — host FFI unless `Mod` is a Rian module here,
  # or a portable-prelude module (`List`/`Dict`/`Str`/`Int`, written in Rian over
  # the per-target primitive layer, ADR-0047 §2 — portable by construction).
  defp classify(
         %Core.ECall{fun: %Core.EDot{head: %Core.EId{name: m}, name: fun}},
         modnames,
         {bl, ca}
       ) do
    cond do
      not pascal?(m) -> {bl, ca}
      MapSet.member?(modnames, m) -> {bl, ca}
      Rian.Prelude.defines?(m, fun) -> {bl, ca}
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

  # `__prim_str_to_atom` — atom interning, only the BEAM lowers it (off non-BEAM).
  # Must precede the generic `EId` local-call edge below (no local def of that name).
  defp classify(%Core.ECall{fun: %Core.EId{name: "__prim_str_to_atom"}}, _modnames, {bl, ca}),
    do: {[atom_prim_blocker() | bl], ca}

  # `__prim_to_string` — runtime Show fallthrough (ADR-0069 §2). Off `:rs` (no universal
  # Display); reaches `:ex`/`:js`/`:jvm`. Must precede the generic `EId` local-call edge.
  defp classify(%Core.ECall{fun: %Core.EId{name: "__prim_to_string"}}, _modnames, {bl, ca}),
    do: {[to_string_prim_blocker() | bl], ca}

  # local function application — a call-graph edge
  defp classify(%Core.ECall{fun: %Core.EId{name: f}}, _modnames, {bl, ca}),
    do: {bl, MapSet.put(ca, f)}

  # a bare value atom (`:foo`) is a `Symbol` — portable everywhere (ADR-0041): a native
  # atom on the BEAM, an interned-name string on JS/Rust/JVM (`Rian.JS`/`Rian.Lower`/
  # `Rian.JVM` all lower it). No blocker. (FFI module-head atoms and Result tags are
  # consumed by their own `scan` clauses above; ordering a `Symbol` is a separate compile
  # error — `find_atom_ordering` — since atom term-order isn't portable.)
  defp classify(%Core.EAtom{}, _modnames, acc), do: acc

  # a map literal `%{…}` — atom-key maps lower on BEAM/JS (off Rust/JVM); a non-atom
  # (computed) key `%{expr => v}` has no faithful JS-object lowering (`Rian.JS` raises),
  # so it is BEAM-only — the matrix matches the emitters (ADR-0033/ADR-0000).
  defp classify(%Core.EMap{pairs: ps}, _modnames, {bl, ca}),
    do: {[map_literal_blocker(ps) | bl], ca}

  # a bitstring `<<…>>` — BEAM-native only (ADR-0078), off Rust/JS/JVM.
  defp classify(%Core.EBitstr{}, _modnames, {bl, ca}), do: {[bitstr_blocker() | bl], ca}

  # a map update `%{base | …}` — same story: atom-key BEAM/JS, computed-key BEAM-only.
  defp classify(%Core.EMapUpdate{pairs: ps}, _modnames, {bl, ca}),
    do: {[map_update_blocker(ps) | bl], ca}

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
