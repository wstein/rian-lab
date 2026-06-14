defmodule Rian.SelfHost do
  @moduledoc """
  Self-hosting instrumentation (ADR-0063 §4) — turns "we ported some files" into a
  **measured boundary** and a **counted** FFI-crutch ledger, so the marching front
  is a number, not a vibe.

  Two things live here:

    * **Stage status** (`stages/0`, `percent/0`, `status_markdown/0`) — each pipeline
      stage's self-host state, the `% self-hosted` headline, and the rendered table
      that `docs/self-host-status.md` is a snapshot of. A self-hosted stage cites a
      Rian source (`examples/rian/selfhost_*.rian`) and an equivalence/fixpoint test;
      `test/rian/self_host_status_test.exs` checks the snapshot is current and the
      cited evidence exists, so the number cannot drift away from reality.

    * **The `@selfhost_ffi` ledger** (`ffi_ledger/0`, `ffi_in_file/1`) — every host-FFI
      crutch the self-host sources still lean on ("permitted, but counted", ADR-0063 §4).
      `ffi_in_file/1` extracts the *actual* FFI calls from a source via `Rian.Reach`
      (the same `:ffi`/`:concurrency` classification the reach gate uses), and
      `test/rian/self_host_ffi_test.exs` asserts they equal the ledger — so an
      **unlisted** crutch fails the build, and a **stale** ledger line (a crutch a P5
      swap removed) fails too. Each portability swap must delete both.

  This separates the **BEAM** self-hosting terminus (the Stage 0–3 ladder) from the
  far-further **portable** one (compiling the compiler to Rust/JS), per ADR-0063 §4.
  """

  @examples_dir Path.join([File.cwd!(), "examples", "rian"])

  @typedoc "A pipeline stage's self-host state."
  @type status :: :self_hosted | :partial | :not_started

  # The compile pipeline (CLAUDE.md / ADR-0050), front to back, with each stage's
  # honest self-host state. `:self_hosted` = a Rian port equivalence-locked against
  # the reference; `:partial` = a verified slice with remaining vocabulary;
  # `:not_started` = no Rian port (a *toy-language* spike like `selfhost_check`/
  # `selfhost_codegen` does NOT count — it does not re-implement the real stage).
  @stages [
    %{
      id: :lexer,
      name: "Lexer",
      role: :frontend,
      status: :self_hosted,
      source: "selfhost_lexer_v2.rian",
      test: "test/rian/fixpoint_test.exs",
      note: "token stream equals Rian.Lexer over slices 1-5 (incl. tokenize/1, {:nl})"
    },
    %{
      id: :decl_parser,
      name: "Declaration parser",
      role: :frontend,
      status: :partial,
      source: "selfhost_decl.rian",
      test: "test/rian/decl_fixpoint_test.exs",
      note:
        "IR equals Rian.Decl over type/struct/mod/def slice incl. `forall` generics (tvars/bounds, ADR-0042); alias/protocol/doc-comments remain"
    },
    %{
      id: :expr_parser,
      name: "Expression/pattern parser",
      role: :frontend,
      status: :self_hosted,
      source: "selfhost_parse.rian",
      test: "test/rian/parse_fixpoint_test.exs",
      note:
        "the full Rian.Pratt grammar — prefix/primary (if/case/with/list/map/tuple/lambda/capture/atom/str/char/num/id), postfix dot/call, labelled args, precedence climbing, AND the full pattern grammar + blocks — equals Rian.Pratt.parse with no projection; string-interpolation/`<-`-propagation sugar is out of scope; FFI-free — the `:if`/`:case`/`:with`/`:struct` keyword-atom tags are quoted-atom literals (`:\"if\"`)"
    },
    %{
      id: :core_ir,
      name: "Typed Core IR (from_expr/from_pat)",
      role: :frontend,
      status: :self_hosted,
      source: "selfhost_core.rian",
      test: "test/rian/core_fixpoint_test.exs",
      note:
        "the full surface→Core lowering — every Pratt-produced expression (literals/unary/binary/call/label/dot/if/tuple/list/map/block/case/lambda/capture/with) and pattern (wild/var/lit/char/atom/tuple/ctor/list/struct/map) — equals Rian.Core.from_expr/from_pat; the Lower-internal resolved nodes + never-parsed as/pin patterns are not surface-reachable"
    },
    %{
      id: :checker,
      name: "Type checker (inference + error sets)",
      role: :checker,
      status: :partial,
      source: "selfhost_checker.rian",
      test: "test/rian/checker_infer_fixpoint_test.exs",
      note:
        "type inference agrees with the REAL Rian.Check.infer over closed integer expressions; env/floats/calls/lambdas/case remain (selfhost_check.rian is a separate TOY-language spike)"
    },
    %{
      id: :exhaustiveness,
      name: "Exhaustiveness gate",
      role: :checker,
      status: :self_hosted,
      source: "selfhost_exhaust.rian",
      test: "test/rian/exhaust_fixpoint_test.exs",
      note:
        "the complete Maranget useful?/3 (specialize/default/signature over single+multi-column matrices, ctors-with-args, finite/infinite types) reproduces Rian.Exhaustiveness.useful? — the gate decision; only the witness/counterexample diagnostic (algorithm I) is unported"
    },
    %{
      id: :capability,
      name: "Capability checker",
      role: :checker,
      status: :self_hosted,
      source: "selfhost_cap.rian",
      test: "test/rian/cap_fixpoint_test.exs",
      note:
        "the full capability→Rust mapping (every Copy width, String, nominal, nested Vec, parametric generics incl. the val-generic quirk) + ref-rejecting BEAM legality equal Rian.Capability over the whole matrix; type-string tokenisation is the type-parser's stage, the BEAM linearity check is native typestate"
    },
    %{
      id: :beam_backend,
      name: "BEAM abstract-forms backend",
      role: :backend,
      status: :self_hosted,
      source: "selfhost_beam.rian",
      test: "test/rian/beam_module_fixpoint_test.exs",
      note:
        "the whole-module abstract-forms emitter — functions with native multi-clause dispatch (patterns ARE the forms), operators, if, case, variants/tuples/lists, guards — compiles via :compile.forms and RUNS identically to Rian.Beam; strings/prims/maps/structs/shadowed-binds are out of scope (selfhost_codegen.rian is a separate toy stack VM)"
    },
    %{
      id: :text_backend,
      name: "Rust text backend",
      role: :backend,
      status: :self_hosted,
      source: "selfhost_rust.rian",
      test: "test/rian/rust_module_fixpoint_test.exs",
      note:
        "the whole-module Rust emitter — sum types → derive'd enums, structs → derive'd records (construct + field access), functions with match-over-param-tuple multi-clause dispatch (capability-lowered signatures), operators, if, variant construct+match, guards, closed + cons lists, generic `<T: Clone>` signatures + bare-tvar-return clone, list PATTERNS (`[h | t]` → slice `[h, t @ ..]`) with the slice-element clone rebind, non-generic call-site owned→borrow coercion (an owned `vec![…]` arg to a `&`-typed param is `&`-wrapped), the generic borrowed-set element clone (a borrowed `&T` binder stored into a closed list / cons head / non-Result variant payload is `.clone()`d), parametric-enum monomorphization (a parametric sum → `enum Name<K: Clone, …>`; every parametric type name in a signature spliced to its instantiation at identifier boundaries — param AND nested, `&Pair`→`&Pair<K,V>`, `Vec<Box>`→`Vec<Box<T>>` — a generic fn using the type's params, a non-generic builder the `i64`-per-param default `Box`→`Box<i64>`) — equals Rian.Lower.rust_program; the emitter consumes RESOLVED + capability-LOWERED Core (resolution = parser/Core stage, capability lowering = the self-hosted capability stage). The rest (concrete instantiation inferred from a generic-CALL builder tail, owned-String/owned-returning-call arg producers, borrowed args at generic call sites, maps, String-return coercion, the Elixir text target, struct *patterns* — a reference gap, Rian.Lower raises) remain out of scope"
    },
    %{
      id: :js_backend,
      name: "ECMAScript backend",
      role: :backend,
      status: :self_hosted,
      source: "selfhost_js.rian",
      test: "test/rian/js_module_fixpoint_test.exs",
      note:
        "the whole-module JS emitter — functions with multi-clause pattern dispatch, sum variants (tagged arrays), structs/tuples/lists/maps, .field, if (ternary), case (IIFE), operators, atoms, prims — equals Rian.JS.compile; protocol dispatch + whole-program int-mode + Shadow are out of scope (program-level / separate-subsystem concerns)"
    },
    %{
      id: :jvm_backend,
      name: "Kotlin/JVM backend",
      role: :backend,
      status: :self_hosted,
      source: "selfhost_jvm.rian",
      test: "test/rian/jvm_module_fixpoint_test.exs",
      note:
        "the whole-module Kotlin emitter — sum types (sealed interface + object/data class), functions with multi-clause pattern dispatch (is/smart-cast tests + binds + trailing throw), if, operators, prims — equals Rian.JVM.compile over its full SUPPORTED surface; lists/maps/case/lambda/@external/Shadow are reference gaps, not port gaps"
    }
  ]

  @weights %{self_hosted: 1.0, partial: 0.5, not_started: 0.0}

  # COMPOSITION axis (ADR-0063 Step 3) — measured SEPARATELY from per-stage
  # equivalence. `percent/0` above counts how many stages match the reference in
  # ISOLATION (each fixpoint uses Elixir projection glue). That can reach 100% and
  # still not be a self-hosting LOOP. This tracks the orthogonal question: how many
  # stages hand their Rian output to the next Rian stage DIRECTLY, no glue. The full
  # bootstrap terminus (Stage 3: v1==v2) is gated on this reaching the whole
  # pipeline — not on `percent`.
  @composition %{
    rung: "SelfhostParse.parse → lower → SelfhostBeam.compile_forms → inflate → load",
    stages: 4,
    subset:
      "a whole multi-function module (arithmetic + `if`/comparison/boolean) whose BODIES are parsed by the equivalence-locked selfhost_parse port and compiled by the equivalence-locked selfhost_beam port — BOTH called CROSS-MODULE, no toy reimplementation of either",
    source: "selfhost_compose_real_front.rian",
    test: "test/rian/compose_real_front_fixpoint_test.exs",
    note:
      "Rungs 1-6 built a driver owning the source→loaded-module loop over a TOY pipeline. Rung 7 made the BACKEND the verified `selfhost_beam` port (cross-module `SelfhostBeam.compile_forms`). Rung 8 makes the FRONT-END's hardest piece verified too: each clause body is parsed by the equivalence-locked `selfhost_parse` port (the full Rian.Pratt grammar) via cross-module `SelfhostParse.parse`, its raw surface lowered to selfhost_beam Core. TWO verified stages now compose end to end — connected only by driver-local lexing, declaration-splitting, and a raw-surface→Core lowering, none of which reimplements either stage. Both ports load under :\"Elixir.Selfhost*\" atoms so the Pascal-qualified calls resolve (ADR-0041); both are sibling self-host ports, so the calls are composition, not host crutches (excluded from the FFI ledger). The only host FFI is still :compile.forms/:code.load_binary. The fixpoint calls only build/2 and runs the result identically to the full Elixir toolchain — now with the REAL parser (real precedence/surface) AND the real backend. Remaining toy piece: the declaration layer (selfhost_decl is :partial); promoting it, then feeding build a slice of the compiler's own source, is the path to the v1==v2 fixed point"
  }

  @doc """
  The composition rung (ADR-0063 Step 3) — measured separately from `percent/0`.
  Per-stage equivalence (`percent`) verifies each stage against the reference in
  isolation; composition verifies that stages connect end-to-end with no glue. The
  bootstrap loop (Stage 3) is gated on composition, not on the per-stage number.
  """
  @spec composition() :: map()
  def composition, do: @composition

  @doc "The declared pipeline stages with their self-host state."
  @spec stages() :: [map()]
  def stages, do: @stages

  @doc """
  The self-hosted fraction of the BEAM front-end→backend pipeline, as a 0–100
  integer percent. `:self_hosted` counts 1.0, `:partial` 0.5, `:not_started` 0.0.
  """
  @spec percent() :: integer()
  def percent do
    total = length(@stages)
    sum = Enum.reduce(@stages, 0.0, fn s, acc -> acc + Map.fetch!(@weights, s.status) end)
    round(sum / total * 100)
  end

  @doc "Count of stages in a given status."
  @spec count(status()) :: non_neg_integer()
  def count(status), do: Enum.count(@stages, &(&1.status == status))

  @doc """
  Render the stage-status report `docs/self-host-status.md` is a snapshot of: a
  `% self-hosted` headline plus a per-stage table. Generated, never hand-edited.
  """
  @spec status_markdown() :: String.t()
  def status_markdown, do: status_markdown(@stages)

  @doc """
  Render the report for an explicit stage list — the `/0` form passes `@stages`.
  The list parameter is the test seam that exercises every status badge (incl.
  `:not_started`, which no real stage currently carries) without faking the data.
  """
  @spec status_markdown([map()]) :: String.t()
  def status_markdown(stages) do
    rows =
      Enum.map_join(stages, "\n", fn s ->
        "| #{s.name} | #{s.role} | #{badge(s.status)} | #{evidence(s)} | #{s.note} |"
      end)

    """
    # Self-hosting status (generated — do not edit by hand)

    Generated by `Rian.SelfHost.status_markdown/0`; regenerate with `mix test` (the
    snapshot is gated by `test/rian/self_host_status_test.exs`). This measures **BEAM**
    self-hosting (ADR-0063 §4) — the Rian compiler compiling its own source to `.beam`.
    **Portable** self-hosting (the compiler lowered to Rust/JS) is a separate, further
    terminus and is *not* measured here.

    **#{percent()}% self-hosted** — #{count(:self_hosted)} stage(s) self-hosted,
    #{count(:partial)} partial, #{count(:not_started)} not started, of #{length(@stages)}.

    **Composition (ADR-0063 Step 3) — a separate axis.** The percentage above counts
    stages verified against the reference *in isolation* (each fixpoint uses Elixir
    projection glue); it can reach 100% without the pipeline ever closing a loop. The
    composition rung measures the orthogonal question — stages handing their Rian output
    to the next Rian stage with **no glue**. Current rung: **#{@composition.rung}**
    (#{@composition.stages} stages), over the #{@composition.subset}. #{@composition.note}.
    Source: `#{@composition.source}`, fixpoint: `#{@composition.test}`. The bootstrap
    terminus (Stage 3, v1==v2) is gated on this reaching the whole pipeline — not on the
    per-stage percentage.

    | Stage | Role | Self-hosted | Evidence | Notes |
    | --- | --- | --- | --- | --- |
    #{rows}

    A stage is `self-hosted` only when a Rian port is **equivalence-locked** against the
    reference (the fixpoint method); `partial` is a verified slice with remaining
    vocabulary; `not-started` has no Rian port (a toy-language spike does not count).
    """
  end

  defp badge(:self_hosted), do: "✅ yes"
  defp badge(:partial), do: "🟡 partial"
  defp badge(:not_started), do: "—"

  defp evidence(%{source: nil}), do: "—"

  defp evidence(%{source: src, test: test}),
    do: "`examples/rian/#{src}`" <> if(test, do: " · `#{test}`", else: "")

  @doc "The self-host Rian sources cited as evidence (absolute paths)."
  @spec evidence_files() :: [String.t()]
  def evidence_files do
    for s <- @stages, s.source, do: Path.join(@examples_dir, s.source)
  end

  # ── @selfhost_ffi ledger (ADR-0063 §4 — permitted, but counted) ────────────

  # Every host-FFI crutch the self-host sources still lean on, keyed by file. These
  # are NOT portable (`Rian.Reach` pins them off `:rs`/`:js`); the portable prelude
  # (ADR-0047) is meant to own them. A P5 swap that replaces one with portable Rian
  # MUST delete its line here (the test fails on a stale entry), and any NEW host FFI
  # MUST be added here (the test fails on an unlisted crutch). Sorted, deduped.
  @ffi_ledger %{
    "selfhost_calc.rian" => [
      ":lists.reverse",
      "List.to_string",
      "Map.get",
      "Map.put",
      "String.to_charlist"
    ],
    "selfhost_check.rian" => ["Map.get", "Map.put"],
    "selfhost_codegen.rian" => ["Map.get", "Map.put"],
    "selfhost_eval.rian" => ["Map.get", "Map.put"],
    "selfhost_funcs.rian" => ["Map.get", "Map.put"],
    "selfhost_modules.rian" => ["String.to_charlist"],
    # the composition-driver capstone owns the whole source->loaded-module loop in
    # Rian; the two irreducible BEAM toolchain calls are @external(:ex) FFI (ADR-0068),
    # counted here. Everything between them is portable Rian (ADR-0063 §4).
    "selfhost_compose_driver.rian" => [":code.load_binary", ":compile.forms"],
    # rung 6 widens the driver's surface (if/comparisons/boolean) but keeps the
    # same two BEAM toolchain calls as its only FFI (ADR-0063 §4 / ADR-0068).
    "selfhost_compose_cond.rian" => [":code.load_binary", ":compile.forms"],
    # rung 7 wires the VERIFIED beam backend into the driver via a cross-module call
    # to SelfhostBeam.compile_forms (composition — excluded from this count, see
    # ffi_in_file/1). Its only host FFI is still the two BEAM toolchain calls.
    "selfhost_compose_real_beam.rian" => [":code.load_binary", ":compile.forms"],
    # rung 8 adds the verified FRONT-END: bodies parsed by SelfhostParse.parse, then
    # the SelfhostBeam backend (both cross-module composition, excluded). Same two
    # BEAM toolchain calls as the only host FFI.
    "selfhost_compose_real_front.rian" => [":code.load_binary", ":compile.forms"]
  }

  @doc "The declared host-FFI crutch ledger: self-host file basename -> sorted constructs."
  @spec ffi_ledger() :: %{String.t() => [String.t()]}
  def ffi_ledger, do: @ffi_ledger

  @doc "All `examples/rian/selfhost_*.rian` source paths."
  @spec selfhost_files() :: [String.t()]
  def selfhost_files, do: Path.wildcard(Path.join(@examples_dir, "selfhost_*.rian"))

  @doc """
  The `mod <Name>` module names declared across the self-host sources — the set of
  *sibling self-host ports*. A Pascal-qualified call to one of these (e.g.
  `SelfhostBeam.compile_forms`) is intra-self-host **composition**, not a host
  crutch, so `ffi_in_file/1` excludes it from the FFI count (it is the loop closing,
  tracked by the composition axis — counting it would perversely make composing more
  verified stages look like more host dependency).
  """
  @spec selfhost_module_names() :: [String.t()]
  def selfhost_module_names do
    for path <- selfhost_files(),
        [_, name] <- Regex.scan(~r/^\s*mod\s+(\w+)\s+do/m, File.read!(path)) do
      name
    end
    |> Enum.uniq()
  end

  @doc """
  The *actual* host-FFI constructs a self-host source leans on — the `:ffi`/
  `:concurrency` blocker constructs `Rian.Reach` finds (Erlang `:mod.fun` / non-Rian
  `Mod.fun` calls in bodies) **plus** the host calls inside `@external(:target, …)`
  bodies (ADR-0068), deduped and sorted. This is the measurement the ledger is checked
  against; `Prim.*` intrinsics are the sanctioned primitive layer, not FFI, so they do
  not appear.

  `@external` needs explicit handling: a bodiless `@external` def reaches exactly its
  declared targets and carries *no* Reach blocker (ADR-0068 §2), so the host call it
  splices would otherwise be invisible to the ledger — under-reporting the crutch.
  We scan each external spec for `:mod.fun` host MFAs so the toolchain FFI a BEAM
  bootstrap driver leans on (`:compile.forms`, `:code.load_binary`) is counted.

  Cross-module calls to a *sibling self-host port* (`SelfhostBeam.compile_forms`) are
  excluded: they are composition (one verified stage feeding the next), not a host
  crutch (see `selfhost_module_names/0`). Genuine host `Mod.fun` calls (`String.to_atom`)
  stay counted — their module head is not a self-host port.
  """
  @spec ffi_in_file(String.t()) :: [String.t()]
  def ffi_in_file(path) do
    prog = path |> File.read!() |> Rian.Decl.parse()

    body_ffi =
      prog
      |> Rian.Reach.analyze()
      |> Map.values()
      |> Enum.flat_map(& &1.blockers)
      |> Enum.filter(&(&1.kind in [:ffi, :concurrency]))
      |> Enum.map(& &1.construct)

    siblings = MapSet.new(selfhost_module_names())

    (body_ffi ++ external_host_calls(prog))
    |> Enum.reject(&sibling_compose_call?(&1, siblings))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # true for a Pascal-qualified call `Mod.fun` whose `Mod` is a sibling self-host
  # port — intra-self-host composition, not host FFI. Host MFAs (`:compile.forms`,
  # `String.to_atom`) have a non-self-host head and are kept.
  defp sibling_compose_call?(construct, siblings) do
    case String.split(construct, ".", parts: 2) do
      [head, _fun] -> MapSet.member?(siblings, head)
      _ -> false
    end
  end

  # the `:mod.fun` host MFAs spliced by every `@external(:target, spec)` body in a
  # program (top-level + every module's funcs). A spec like `:compile.forms(forms, …)`
  # yields `":compile.forms"`; plain atoms (`:return_errors`) carry no `.fun` and are
  # ignored. Surfacing these keeps the ledger honest about `@external` FFI (ADR-0068).
  defp external_host_calls(prog) do
    funcs =
      Map.get(prog, :funcs, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :funcs, []))

    for f <- funcs,
        {_target, spec} <- Map.get(f, :externals, %{}),
        [_, m, fun] <- Regex.scan(~r/:([a-z_]\w*)\.([a-z_]\w*)/, spec) do
      ":#{m}.#{fun}"
    end
  end
end
