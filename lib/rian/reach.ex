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
    parametric = parametric_type_names(prog)

    facts =
      Map.new(funs, fn f ->
        {blockers, callees} = scan_func(f, modnames, parametric)
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
  defp scan_func(f, modnames, parametric) do
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
    # then rejects (the gate lying). They pin the function off `:rs` only — the
    # Bool-returning bounded generics (`contains`/`equal3`) and non-parametric sums
    # that the emitter *does* lower keep `:rs`.
    #
    # (1) A generic whose RETURN type mentions a type variable: its `&T` params
    # would have to be `.clone()`d into the owned `T`/`Vec<T>` it returns (and an
    # owned local re-borrowed at a `&Self` protocol-method arg). The Rust emitter
    # does no such type-directed coercion, so `insert`/`sort`/`maximum` (→ `Vec(T)`
    # /`T`) fail rustc E0308 while `contains` (→ `Bool`) compiles.
    owned_gen = if sig_returns_tvar?(f), do: [owned_generic_blocker()], else: []
    # (2) A signature referencing a PARAMETRIC user type (`type Pair := P(k K, v V)`):
    # `rust_enum` emits `enum Pair {` with no `<K,V>` params, and the per-unit emitter
    # repeats the def → duplicate `enum Pair` (E0428) plus undeclared type params.
    param_ty = if uses_parametric_type?(f, parametric), do: [parametric_type_blocker()], else: []

    Enum.reduce(f.clauses, {ref ++ int ++ width ++ owned_gen ++ param_ty, MapSet.new()}, fn c,
                                                                                            acc ->
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

  defp owned_generic_blocker,
    do: %{
      construct: "generic returning an owned type variable (no Rust borrow→owned coercion)",
      kind: :generic,
      kills: [:rs]
    }

  defp parametric_type_blocker,
    do: %{
      construct: "parametric user type in signature (Rust enum has no generic params)",
      kind: :generic,
      kills: [:rs]
    }

  # A bare value atom (`:foo`, a `Symbol` literal) has no JS/JVM/Rust representation:
  # `Rian.JS`/`Rian.JVM` raise `Unsupported` on it and `Rian.Lower` raises "atom is
  # BEAM-only". ADR-0041 deems atoms *architecturally* portable, but no emitter lowers
  # one, so Reach pins the function to `:ex` — the matrix matches the emitters, not the
  # ADR's aspiration (the ADR-0000 open item). FFI module-head atoms and Result tags
  # are consumed by their own `scan` clauses, so this fires only on *value* atoms.
  defp bare_atom_blocker,
    do: %{construct: "bare atom literal (`:foo`)", kind: :atom, kills: [:js, :jvm, :rs]}

  # A `Result` value `{:ok, _}` / `{:error, _}` (ADR-0040): lowered on the BEAM (tagged
  # tuple) and on Rust (`Ok`/`Err`), but **not** on JS/JVM — their emitters do not lower
  # the tag atom (`Rian.JS` has no `EAtom` clause; `Rian.JVM` lists atoms unsupported).
  # So a constructed Result pins the function off `:js`/`:jvm` (honest matrix).
  defp result_value_blocker,
    do: %{construct: "Result value (`{:ok,_}`/`{:error,_}`)", kind: :result, kills: [:js, :jvm]}

  # A function is generic-in-its-result iff its declared return type mentions a type
  # variable (`T`/`Vec(T)`/`V`) — only a `forall` tvar can appear there, so this
  # already implies the function is generic. The Rust emitter borrows every generic
  # param (`&T`) and never coerces back to an owned `T`/`Vec<T>`, so such a function
  # cannot lower (ADR-0061/0047). A `Bool`/`Int64` return is unaffected.
  defp sig_returns_tvar?(f), do: type_has_tvar?(Map.get(f, :ret))

  # Does this function's signature (params or return) name a parametric user type?
  defp uses_parametric_type?(f, parametric) do
    sig_types = Enum.map(Map.get(f, :params, []), & &1.type) ++ [Map.get(f, :ret)]
    Enum.any?(sig_types, fn t -> Enum.any?(type_idents(t), &MapSet.member?(parametric, &1)) end)
  end

  # The set of user `type` names that are parametric — a variant field typed by a
  # type variable (`type Pair := P(k K, v V)` → K/V). Such an enum needs `<…>`
  # generic params the Rust emitter does not emit, so any signature touching it is
  # off `:rs`. Scans top-level and module-local type decls.
  defp parametric_type_names(prog) do
    types =
      Map.get(prog, :types, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :types, []))

    for t <- types, parametric_type?(t), into: MapSet.new(), do: t.name
  end

  defp parametric_type?(t) do
    Enum.any?(t.variants, fn v ->
      Enum.any?(v.fields, fn fld -> type_has_tvar?(Map.get(fld, :type)) end)
    end)
  end

  # Does a type string contain a type-variable token? `tvar?` is the compiler-wide
  # convention (`Rian.Check`): a single capital optionally followed by a digit.
  defp type_has_tvar?(t) when is_binary(t), do: Enum.any?(type_idents(t), &tvar?/1)
  defp type_has_tvar?(_), do: false

  # the identifier tokens of a type string: `Vec(Pair)` → `["Vec", "Pair"]`,
  # `Tree(T)` → `["Tree", "T"]`.
  defp type_idents(t) when is_binary(t), do: Regex.scan(~r/[A-Za-z_]\w*/, t) |> Enum.map(&hd/1)
  defp type_idents(_), do: []

  defp tvar?(t), do: String.match?(t, ~r/^[A-Z][0-9]?$/)

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

  # a bare value atom that escaped the FFI-head and Result-tag `scan` clauses above —
  # off every non-BEAM target (no emitter lowers it).
  defp classify(%Core.EAtom{}, _modnames, {bl, ca}), do: {[bare_atom_blocker() | bl], ca}

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
