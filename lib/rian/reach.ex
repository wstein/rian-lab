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
    * Clause-head patterns are scanned only for as-patterns (`name @ pat`) and
      bitstring patterns (`<<…>>`) — emitter gaps off the typed/JVM targets; all other
      blockers (FFI, atoms) live in bodies/guards.

  Reach models **architectural** reachability (what a target *can* run — `ref` off
  the BEAM, `Int64` off JS, FFI off non-BEAM). It deliberately does NOT track an
  emitter's **implementation status** (atoms/`with`/lambdas not *yet* lowered on JS;
  tuples/lists/maps not *yet* on the Tier-2 JVM) — those are portable by
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

  @typedoc "A lowering target (emitter-backed)."
  @type target :: :ex | :rs | :js | :jvm

  # Erlang modules that are concurrency/process/state (ex-only AND native-per-target)
  @conc_erl ~w(ets dets mnesia gen_server gen_statem gen_event global pg pg2 sys supervisor)
  @conc_erl_fun ~w(spawn spawn_link spawn_monitor send send_after start_timer monitor link)
  # Elixir modules that are concurrency/process/state
  @conc_ex ~w(GenServer Task Process Agent Supervisor DynamicSupervisor Registry GenStage GenEvent Node)

  @doc "The closed target vocabulary (emitter-backed). Extends only when an emitter lands."
  @spec targets() :: [target()]
  def targets, do: @targets

  @doc """
  Analyze a parsed program (`Rian.Decl.parse/1` output).

  Returns `%{"name/arity" => %{reach: MapSet.t(target), blockers: [blocker]}}` where
  a `blocker` is `%{construct: String.t(), kind: :ffi | :concurrency, kills: [target]}`.
  The report is keyed by `"name/arity"` (arity overloading, ADR-0057) — **look an
  entry up with `entry/2`**, not a raw `report[name]` index, which silently returns
  `nil` for a bare name and crashes downstream.
  """
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
  Look a function's entry up in an `analyze/1` report.

  `key` is either the exact `"name/arity"` key or a **bare name** (the common case
  for non-overloaded code). The report keys by `"name/arity"`, so a raw
  `report[name]` index silently returns `nil` for a bare name and then crashes
  downstream — this resolves the bare name and **raises a clear error** when the
  name is absent or overloaded (ambiguous), naming the available keys. Pass the
  full `"name/arity"` key to disambiguate an overload.
  """
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
  @spec check_contracts(map(), term()) :: :ok | {:error, String.t()}
  def check_contracts(prog, default \\ nil) do
    reach = analyze(prog)

    violations =
      for mod <- Map.get(prog, :mods, []),
          required = mod.targets || default,
          required != nil,
          f <- mod.funcs,
          f.pub?,
          key = "#{f.name}/#{length(f.params)}",
          missing = required -- MapSet.to_list(reach[key][:reach] || MapSet.new(@targets)),
          missing != [] do
        {mod.name, f.name, Enum.sort(missing)}
      end

    case violations do
      [] -> :ok
      vs -> {:error, contract_message(vs)}
    end
  end

  @doc "Raise `Rian.Reach.Error` on any unmet `@targets(…)` contract, else `:ok`."
  @spec gate!(map()) :: :ok
  def gate!(prog), do: gate!(prog, build_default())

  @doc "Gate against an explicit build-default target set (`nil` = none)."
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
    # Two Rust-generic emitter gaps (ADR-0061/0047) the reach matrix must own up to,
    # or `mix rian.targets`/the conformance gate green-lights `:rs` for code `rustc`
    # then rejects (the gate lying). It pins the function off `:rs` only — generics the
    # emitter *does* lower (`contains`/`sort`/`maximum`, and parametric `Pair` over
    # `enum Pair<K,V>`) keep `:rs`.
    #
    # An `Fn(...)` function type anywhere in the signature (a parameter or the return)
    # has no Rust lowering: a closure-as-value needs `impl Fn`/`Box<dyn Fn>` and the
    # text emitter spells it as the bare trait `Fn<...>` (rustc E0782) — and an `Fn`
    # *parameter* additionally mangles to an undeclared type (E0425). This holds
    # whether the `Fn` mentions a tvar or not (`adder() Fn(Int53, Int53)`,
    # `apply_twice(f Fn(Int53, Int53), …)`, generic `map(f Fn(T, U), …)` all fail), so
    # the gate pins any `Fn(`-bearing signature off `:rs`. (The owned↔borrow coercion
    # for bare `T`/`Vec(T)` returns and `Option(T)`/`T | E`/sum-over-`T` landed
    # 2026-06-14, so those are *not* blocked — only `Fn` remains unlowerable.)
    owned_gen = if sig_uses_fn_type?(f), do: [fn_type_blocker()], else: []
    # A function whose signature touches a *parametric* user type (`Pair`, `enum
    # Pair<K,V>`) reaches `:rs` only for the narrow shape the emitter actually lowers
    # (`Rian.Lower`): the type's tvar fields are all *bare* tvars, and the function
    # either only matches/passes the value, constructs it with positionally-aligned
    # tvar args, or is a non-generic builder whose tail is a direct call to a generic
    # helper (so the concrete instantiation is inferable). Everything else emits
    # undeclared generics or the wrong `i64` instantiation, so it pins off `:rs` —
    # the matrix stays honest rather than green-lighting code rustc rejects (ADR-0061).
    param = if parametric_rs_ok?(f, pctx), do: [], else: [parametric_blocker()]
    # an as-pattern (`name @ pat`, ADR-0050) in a clause head is lowered on BEAM/Rust
    # (`Rian.PatternLower`) but the JS/JVM emitters raise `Unsupported` for it, so it
    # pins the function off `:js`/`:jvm` — else the matrix shows a target whose emitter
    # then raises (the gate lie `reach_test` guards against). This is the one place a
    # clause-head pattern is inspected (FFI/atom blockers live in bodies/guards).
    as_pat =
      if Enum.any?(f.clauses, fn c -> Enum.any?(c.pats, &pat_has_as?/1) end),
        do: [as_pat_blocker()],
        else: []

    # a bitstring pattern in a clause head is BEAM-only (ADR-0078) — like an
    # as-pattern, inspect the heads so the matrix matches the emitters.
    bit_pat =
      if Enum.any?(f.clauses, fn c -> Enum.any?(c.pats, &pat_has_bitstr?/1) end),
        do: [bitstr_blocker()],
        else: []

    Enum.reduce(
      f.clauses,
      {ref ++ int ++ width ++ owned_gen ++ param ++ as_pat ++ bit_pat, MapSet.new()},
      fn c, acc ->
        acc = scan(core(c.body, &Pratt.parse_body/1), modnames, acc)
        if c.guard, do: scan(core(c.guard, &Pratt.parse/1), modnames, acc), else: acc
      end
    )
  end

  # a surface clause-head pattern contains an as-pattern `{:as, name, pat}` (anywhere)?
  defp pat_has_as?({:as, _name, _pat}), do: true
  defp pat_has_as?(t) when is_tuple(t), do: t |> Tuple.to_list() |> Enum.any?(&pat_has_as?/1)
  defp pat_has_as?(l) when is_list(l), do: Enum.any?(l, &pat_has_as?/1)
  defp pat_has_as?(_), do: false

  # a surface clause-head pattern contains a bitstring pattern `{:bitstr_pat, …}`?
  defp pat_has_bitstr?({:bitstr_pat, _segs}), do: true

  defp pat_has_bitstr?(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.any?(&pat_has_bitstr?/1)

  defp pat_has_bitstr?(l) when is_list(l), do: Enum.any?(l, &pat_has_bitstr?/1)
  defp pat_has_bitstr?(_), do: false

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

  # `__prim_str_to_atom` interns a string to a BEAM atom — only the BEAM emitter
  # lowers it (Rust/JS/JVM have no atom value). A body that calls it is BEAM-only,
  # so the gate matches the emitters (off `:rs`/`:js`/`:jvm`), never lying.
  defp atom_prim_blocker,
    do: %{
      construct: "`Prim.str_to_atom` (atom is BEAM-only)",
      kind: :atom,
      kills: [:rs, :js, :jvm]
    }

  defp fn_type_blocker,
    do: %{
      construct:
        "returned closure over a type variable / nested Fn (no owned-capture + 'static yet)",
      kind: :generic,
      kills: [:rs]
    }

  defp parametric_blocker,
    do: %{
      construct: "parametric user type beyond the Rust emitter's monomorphic subset",
      kind: :generic,
      kills: [:rs]
    }

  # A bare value atom (`:foo`, a `Symbol` literal): lowered on the BEAM (native atom)
  # and on JS (a string, `Rian.JS` `EAtom` clause), but **not** on Rust (`Rian.Lower`
  # raises "atom is BEAM-only") or JVM (atoms listed unsupported). ADR-0041 deems atoms
  # architecturally portable; Reach reports what the emitters actually lower (the matrix
  # matches the emitters, not the aspiration — ADR-0000). FFI module-head atoms and
  # Result tags are consumed by their own `scan` clauses, so this fires only on values.
  defp bare_atom_blocker,
    do: %{construct: "bare atom literal (`:foo`)", kind: :atom, kills: [:rs, :jvm]}

  # A map literal `%{…}` (ADR-0033): lowered on the BEAM (native map) and on JS (a
  # plain object, `Rian.JS`'s `EMap` clause), but **not** on Rust (`Rian.Lower` raises
  # "map literals are BEAM-only in PoC") or JVM (`Core.EMap` is in `@jvm_unsupported`).
  # A constructed map therefore pins the function off `:rs`/`:jvm` — the matrix reports
  # what the emitters actually lower, not the aspiration (same principle as bare atoms,
  # ADR-0000). The map *update* form `%{base | k: v}` (ADR-0033, `Core.EMapUpdate`) has
  # the same target story — BEAM/JS lower it, Rust/JVM raise — so it carries its own
  # blocker below; both surface as `kind: :map`.
  defp map_blocker,
    do: %{construct: "map literal (`%{…}`)", kind: :map, kills: [:rs, :jvm]}

  # A bitstring `<<seg::spec, …>>` (ADR-0078): lowered natively on the BEAM (Erlang
  # bitstring forms) and via `Rian.Lower`'s Elixir text, but **not** on Rust/JS/JVM
  # (no faithful bit-level lowering yet — those emitters raise `Unsupported`). So a
  # bitstring pins the function BEAM-only — the matrix matches the emitters (ADR-0000).
  defp bitstr_blocker,
    do: %{construct: "bitstring (`<<…>>`)", kind: :bitstring, kills: [:rs, :js, :jvm]}

  defp map_update_blocker,
    do: %{construct: "map update (`%{base | …}`)", kind: :map, kills: [:rs, :jvm]}

  # An as-pattern `name @ pat` (ADR-0050): lowered on the BEAM/Rust via
  # `Rian.PatternLower`, but the JS/JVM emitters raise `Unsupported`, so it pins the
  # function off `:js`/`:jvm` (honest against the emitters).
  defp as_pat_blocker,
    do: %{construct: "as-pattern (`name @ pat`)", kind: :pattern, kills: [:js, :jvm]}

  # A `Result` value `{:ok, _}` / `{:error, _}` (ADR-0040): lowered on the BEAM (tagged
  # tuple), Rust (`Ok`/`Err`), and JS (`["ok", v]`, `Rian.JS`), but **not** on JVM (its
  # emitter has no tuple/`case` lowering yet). So a constructed Result pins the function
  # off `:jvm` only — honest against the emitters.
  defp result_value_blocker,
    do: %{construct: "Result value (`{:ok,_}`/`{:error,_}`)", kind: :result, kills: [:jvm]}

  # Closure-as-value lowering landed (ADR-0061, 2026-06-17): a `Fn(...)` callback
  # PARAMETER lowers to `&impl Fn(...)` and a CONCRETE returned closure to a
  # `Box<dyn Fn(...)>` (`Box::new(move …)`), both rustc-verified. What still has no
  # Rust lowering — and so still pins `:rs` — is a returned closure that mentions a
  # TYPE VARIABLE (`mk(x T) Fn(Int53, T)`) or is NESTED in another type
  # (`Option(Fn(Int53, T))`): the boxed `dyn Fn` there needs owned capture of a
  # borrowed param plus a `T: 'static` bound, not yet emitted. Param-`Fn` and concrete
  # top-level `Fn(...)` returns are NOT blocked.
  defp sig_uses_fn_type?(f) do
    ret = Map.get(f, :ret)

    is_binary(ret) and String.contains?(ret, "Fn(") and
      not concrete_fn_return?(ret, Map.get(f, :tvars, []))
  end

  # a bare top-level `Fn(args, ret)` return with no type variable — lowered to a concrete
  # `Box<dyn Fn(...)>` + `Box::new(move …)` (e.g. `adder`); supported on `:rs`.
  defp concrete_fn_return?(ret, tvars) do
    String.starts_with?(ret, "Fn(") and not Enum.any?(tvars, &String.match?(ret, ~r/\b#{&1}\b/))
  end

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

    ptypes = Enum.filter(types, &parametric_type?/1)

    %{
      names: MapSet.new(ptypes, & &1.name),
      emittable: Map.new(ptypes, fn t -> {t.name, emittable_parametric?(t)} end),
      ctors:
        for(
          t <- ptypes,
          v <- t.variants,
          into: %{},
          do: {v.ctor, Enum.map(v.fields, &Map.get(&1, :type))}
        ),
      generics: MapSet.new(for f <- funs, Map.get(f, :tvars, []) != [], do: f.name)
    }
  end

  # A user `type` is parametric iff some variant field's type mentions a tvar.
  defp parametric_type?(t) do
    Enum.any?(t.variants, fn v -> Enum.any?(v.fields, &type_has_tvar?(Map.get(&1, :type))) end)
  end

  # The Rust emitter lowers a parametric type only when every tvar-bearing field is
  # a *bare* tvar (`k K`) — that becomes a declared `enum Pair<K, V>` param. A field
  # nesting a tvar in a compound (`items Vec(T)`) emits an undeclared `T` (rustc
  # E0412), so such a type is not emittable.
  defp emittable_parametric?(t) do
    t.variants
    |> Enum.flat_map(& &1.fields)
    |> Enum.map(&Map.get(&1, :type))
    |> Enum.filter(&type_has_tvar?/1)
    |> Enum.all?(&tvar?/1)
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

  # A construction is emittable iff each positional arg is a bare parameter
  # reference whose declared type is exactly the field's tvar — the emitter assigns
  # the field type (`K`) to the arg with no coercion, so a mismatch is rustc E0308.
  defp ctor_aligned?({field_tvars, args}, f) do
    ptypes = Map.new(Map.get(f, :params, []), &{&1.name, &1.type})

    length(field_tvars) == length(args) and
      field_tvars
      |> Enum.zip(args)
      |> Enum.all?(fn {tv, arg} ->
        match?(%Core.EId{}, arg) and Map.get(ptypes, arg.name) == tv
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

  # local function application — a call-graph edge
  defp classify(%Core.ECall{fun: %Core.EId{name: f}}, _modnames, {bl, ca}),
    do: {bl, MapSet.put(ca, f)}

  # a bare value atom that escaped the FFI-head and Result-tag `scan` clauses above —
  # off every non-BEAM target (no emitter lowers it).
  defp classify(%Core.EAtom{}, _modnames, {bl, ca}), do: {[bare_atom_blocker() | bl], ca}

  # a map literal `%{…}` — lowered on BEAM/JS, but not on Rust/JVM (see `map_blocker/0`).
  defp classify(%Core.EMap{}, _modnames, {bl, ca}), do: {[map_blocker() | bl], ca}

  # a bitstring `<<…>>` — BEAM-native only (ADR-0078), off Rust/JS/JVM.
  defp classify(%Core.EBitstr{}, _modnames, {bl, ca}), do: {[bitstr_blocker() | bl], ca}

  # a map update `%{base | …}` — same BEAM/JS-only story (see `map_update_blocker/0`).
  defp classify(%Core.EMapUpdate{}, _modnames, {bl, ca}), do: {[map_update_blocker() | bl], ca}

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
