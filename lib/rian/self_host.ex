defmodule Rian.SelfHost do
  @moduledoc """
  Self-hosting instrumentation (ADR-0063 §4) — turns "we ported some files" into a
  **measured boundary** and a **counted** FFI-crutch ledger, so the marching front
  is a number, not a vibe.

  Two things live here:

    * **Stage status** (`stages/0`, `percent/0`, `status_markdown/0`) — each pipeline
      stage's self-host state, the `% self-hosted` headline, and the rendered table
      that `docs/self-host-status.md` is a snapshot of. A self-hosted stage cites a
      Rian source (`compiler/*.rian`) and an equivalence/fixpoint test;
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

  @compiler_dir Path.join([File.cwd!(), "compiler"])

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
      source: "lexer_v2.rian",
      test: "test/rian/fixpoint_test.exs",
      note: "token stream equals Rian.Lexer over slices 1-5 (incl. tokenize/1, {:nl})"
    },
    %{
      id: :decl_parser,
      name: "Declaration parser",
      role: :frontend,
      status: :partial,
      source: "decl.rian",
      test: "test/rian/decl_fixpoint_test.exs",
      note:
        "IR equals Rian.Decl over type/struct/mod/def slice incl. `forall` generics (tvars/bounds, ADR-0042), `if … do … else … end` expressions (single-expr branches → `{:if, c, {:block,…}, {:block,…}}`, ADR-0063), String/Char literals + patterns (`def tag() String := \"ok\"`, `def m(\"x\") := 1`), multi-statement block bodies (`<nl> b := e <nl> e end` → `{:block, [{:bind,…}, {:expr,…}]}`), and `case … do … end` (single-expr arms + `when` guards → `{:case, scrut, [{pat, g, body}, …]}`); alias/protocol/doc-comments remain"
    },
    %{
      id: :expr_parser,
      name: "Expression/pattern parser",
      role: :frontend,
      status: :self_hosted,
      source: "parse.rian",
      test: "test/rian/parse_fixpoint_test.exs",
      note:
        "the full Rian.Pratt grammar — prefix/primary (if/case/with/list/map/tuple/lambda/capture/atom/str/char/num/id), postfix dot/call, labelled args, precedence climbing, AND the full pattern grammar + blocks — equals Rian.Pratt.parse with no projection; string-interpolation/`<-`-propagation sugar is out of scope; FFI-free — the `:if`/`:case`/`:with`/`:struct` keyword-atom tags are quoted-atom literals (`:\"if\"`)"
    },
    %{
      id: :core_ir,
      name: "Typed Core IR (from_expr/from_pat)",
      role: :frontend,
      status: :self_hosted,
      source: "core.rian",
      test: "test/rian/core_fixpoint_test.exs",
      note:
        "the full surface→Core lowering — every Pratt-produced expression (literals/unary/binary/call/label/dot/if/tuple/list/map/block/case/lambda/capture/with) and pattern (wild/var/lit/char/atom/tuple/ctor/list/struct/map) — equals Rian.Core.from_expr/from_pat; the Lower-internal resolved nodes + never-parsed as/pin patterns are not surface-reachable"
    },
    %{
      id: :checker,
      name: "Type checker (inference + error sets)",
      role: :checker,
      status: :partial,
      source: "checker.rian",
      test: "test/rian/checker_infer_fixpoint_test.exs",
      note:
        "type inference agrees with the REAL Rian.Check.infer over ALL 12 Core nodes AND the FULL inference context `ic` — literals incl. float/char, ids in a typing env, unary/binary with operand-directed arithmetic + cross-width widening, prim calls, `if`/`case` (with flow narrowing), lists, lambdas (`Fn(...)`), higher-order calls, constructor sum types + non-generic function returns, GENERIC-return instantiation (`ic.fsigs` + type variables — unify params with arg types, substitute bound tvars in the return) and constructor-pattern field narrowing (`ic.tdefs`). Inference is complete, and the first TWO error sets — numeric mix (`num_mix`, ADR-0035: a `+`/`-`/`*` mixing int and float) and return-type mismatch (`ret_bad`, ADR-0064: a body whose inferred type contradicts the declared return), locked by `checker_nummix_fixpoint_test`/`checker_rettype_fixpoint_test` — are now ported AND wired into `build`, so the self-built compiler REJECTS an int↔float or return-mismatched program (`compose_type_gate_fixpoint_test`); the remaining error sets (binding/bounds/error-set) and d_clause coverage are the tail (check.rian is a separate TOY-language spike)"
    },
    %{
      id: :exhaustiveness,
      name: "Exhaustiveness gate",
      role: :checker,
      status: :self_hosted,
      source: "exhaust.rian",
      test: "test/rian/exhaust_fixpoint_test.exs",
      note:
        "the complete Maranget useful?/3 (specialize/default/signature over single+multi-column matrices, ctors-with-args, finite/infinite types) reproduces Rian.Exhaustiveness.useful? — the gate decision; only the witness/counterexample diagnostic (algorithm I) is unported"
    },
    %{
      id: :capability,
      name: "Capability checker",
      role: :checker,
      status: :self_hosted,
      source: "cap.rian",
      test: "test/rian/cap_fixpoint_test.exs",
      note:
        "the full capability→Rust mapping (every Copy width, String, nominal, nested Vec, parametric generics incl. the val-generic quirk) + ref-rejecting BEAM legality equal Rian.Capability over the whole matrix; type-string tokenisation is the type-parser's stage, the BEAM linearity check is native typestate"
    },
    %{
      id: :beam_backend,
      name: "BEAM abstract-forms backend",
      role: :backend,
      status: :self_hosted,
      source: "beam.rian",
      test: "test/rian/beam_module_fixpoint_test.exs",
      note:
        "the whole-module abstract-forms emitter — functions with native multi-clause dispatch (patterns ARE the forms), operators, if, case, variants/tuples/lists, guards — compiles via :compile.forms and RUNS identically to Rian.Beam; strings/prims/maps/structs/shadowed-binds are out of scope (codegen.rian is a separate toy stack VM)"
    },
    %{
      id: :text_backend,
      name: "Rust text backend",
      role: :backend,
      status: :self_hosted,
      source: "rust.rian",
      test: "test/rian/rust_module_fixpoint_test.exs",
      note:
        "the whole-module Rust emitter — sum types → derive'd enums, structs → derive'd records (construct + field access), functions with match-over-param-tuple multi-clause dispatch (capability-lowered signatures), operators, if, variant construct+match, guards, closed + cons lists, generic `<T: Clone>` signatures + bare-tvar-return clone, list PATTERNS (`[h | t]` → slice `[h, t @ ..]`) with the slice-element clone rebind, non-generic call-site owned→borrow coercion (an owned `vec![…]` arg to a `&`-typed param is `&`-wrapped), the generic borrowed-set element clone (a borrowed `&T` binder stored into a closed list / cons head / non-Result variant payload is `.clone()`d), parametric-enum monomorphization (a parametric sum → `enum Name<K: Clone, …>`; every parametric type name in a signature spliced to its instantiation at identifier boundaries — param AND nested, `&Pair`→`&Pair<K,V>`, `Vec<Box>`→`Vec<Box<T>>` — a generic fn using the type's params, a non-generic builder the `i64`-per-param default `Box`→`Box<i64>`) — equals Rian.Lower.rust_program; the emitter consumes RESOLVED + capability-LOWERED Core (resolution = parser/Core stage, capability lowering = the self-hosted capability stage). The rest (concrete instantiation inferred from a generic-CALL builder tail, owned-String/owned-returning-call arg producers, borrowed args at generic call sites, maps, String-return coercion, the Elixir text target, struct *patterns* — a reference gap, Rian.Lower raises) remain out of scope"
    },
    %{
      id: :js_backend,
      name: "ECMAScript backend",
      role: :backend,
      status: :self_hosted,
      source: "js.rian",
      test: "test/rian/js_module_fixpoint_test.exs",
      note:
        "the whole-module JS emitter — functions with multi-clause pattern dispatch, sum variants (tagged arrays), structs/tuples/lists/maps, .field, if (ternary), case (IIFE), operators, atoms, prims — equals Rian.JS.compile; protocol dispatch + whole-program int-mode + Shadow are out of scope (program-level / separate-subsystem concerns)"
    },
    %{
      id: :jvm_backend,
      name: "Kotlin/JVM backend",
      role: :backend,
      status: :self_hosted,
      source: "jvm.rian",
      test: "test/rian/jvm_module_fixpoint_test.exs",
      note:
        "the whole-module Kotlin emitter — sum types (sealed interface + object/data class), functions with multi-clause pattern dispatch (is/smart-cast tests + binds + trailing throw), if, operators, prims — equals Rian.JVM.compile over its full SUPPORTED surface; lists/maps/lambda/@external/Shadow are reference gaps, not port gaps (`case` is a reference feature the port's surface does not yet emit)"
    }
  ]

  @weights %{self_hosted: 1.0, partial: 0.5, not_started: 0.0}

  # AUXILIARY PASSES (ADR-0063 #2) — compiler passes that are NOT one of the 11 pipeline
  # @stages: they run at the parse boundary (Prim normalization, interpolation,
  # comptime-fold), pre-emit (opaque erasure), or as analysis (reachability). Each is
  # drained from Elixir into a Rian port equivalence-locked against its oracle. Tracked
  # SEPARATELY so they neither inflate the stage count nor distort `percent/0`.
  @passes [
    %{
      id: :prim_norm,
      name: "Prim normalization (`Prim.* → __prim_*`)",
      oracle: "Rian.Prim.normalize",
      source: "prim.rian",
      test: "test/rian/prim_fixpoint_test.exs",
      note:
        "PrimNorm.normalize rewrites `Prim.<name>(args)` → `__prim_<name>(args)` for the closed prim set, recursing through every expression position; equivalence-locked vs Rian.Prim.normalize over hand-built raw surface trees (ADR-0047 §2). Tail: the oracle RAISES on an unknown `Prim.x`; the port leaves it (no host raise)."
    },
    %{
      id: :comptime_fold,
      name: "Comptime fold (`comptime(expr)` → literal)",
      oracle: "Rian.Comptime.fold",
      source: "comptime.rian",
      test: "test/rian/comptime_fixpoint_test.exs",
      note:
        "Comptime.fold evaluates a `comptime(expr)` in a pure sandbox (integer literals, unary `-`/`not`, arithmetic `+ - * div rem`, comparisons) and replaces it with its literal, recursing through the rest of the tree; equivalence-locked vs Rian.Comptime.fold (ADR-0009/0056). Tails: FLOAT results are unported (no `float → string` prim), and the oracle RAISES on a non-foldable body where the port leaves the call."
    },
    %{
      id: :interp_desugar,
      name: "Interpolation desugar (`${expr}` → `<>`/stringify)",
      oracle: "Rian.Interp.resolve (desugar half)",
      source: "interp.rian",
      test: "test/rian/interp_fixpoint_test.exs",
      note:
        "Interp.desugar rewrites a `${…}` string into a single-shot `__prim_str_concat_all` chain, stringifying each hole by its STATIC type (String→identity, Int*/UInt*→__prim_int_to_string, Bool→if, Char→__prim_char_to_string, Float64→Show.float, impl-Show type→show); equivalence-locked vs Rian.Interp.resolve's desugar (ADR-0069). Inference is delegated to the separately-ported checker (the test feeds the types Check.infer produces). Tails: the Show.float Process-flag side-effect, Float32/no-Show RAISE (port emits a marker), and nested interpolation inside a hole."
    }
  ]

  # COMPOSITION axis (ADR-0063 Step 3) — measured SEPARATELY from per-stage
  # equivalence. `percent/0` above counts how many stages match the reference in
  # ISOLATION (each fixpoint uses Elixir projection glue). That can reach 100% and
  # still not be a self-hosting LOOP. This tracks the orthogonal question: how many
  # stages hand their Rian output to the next Rian stage DIRECTLY, no glue. The full
  # bootstrap terminus (Stage 3: v1==v2) is gated on this reaching the whole
  # pipeline — not on `percent`.
  @composition %{
    rung: "LexerV2.tokenize → Decl.parse_program → lower → Beam.compile_forms → load",
    stages: 4,
    subset:
      "whole real compiler-stage files whose ENTIRE front-end is verified ports — tokenized by selfhost_lexer_v2, parsed by selfhost_decl (def heads, multi-clause patterns incl. cons-LISTS and TUPLES, SUM-TYPE/STRUCT declarations + constructor dispatch, `if`, `case` with guards, strings/chars, atoms, struct field access, `@external` FFI, `forall` generics, arithmetic + calls) — and compiled by the selfhost_beam backend; all THREE ports called CROSS-MODULE (incl. remote calls), with only a surface→Core lowering + Form inflater as driver glue",
    source: "compose_real_sum.rian",
    test: "test/rian/compose_real_sum_fixpoint_test.exs",
    # honesty distinction (ADR-0063): the composed loop is self-COMPILING (codegen —
    # lex→parse→lower→emit→load). It is now PARTIALLY self-CHECKING: the two STRUCTURAL
    # gates — EXHAUSTIVENESS (`build` REFUSES a non-exhaustive sum dispatch, via Exhaust)
    # and CAPABILITY (refuses a BEAM-illegal `ref` param, via Cap.beam_legal) — PLUS the
    # first TWO TYPE-checker error sets: NUMERIC MIX (an int↔float `+`/`-`/`*`) and
    # RETURN-TYPE mismatch (a body whose type contradicts the declared return), in a
    # `d_func`, via the locked Checker.num_mix/ret_bad (ADR-0035/0064, P3). FULL
    # self-checking is NOT reached — the rest of Rian.Check's error sets
    # (binding/bounds/error-set) and d_clause coverage are still out of the loop, so
    # `build` rejects only those two classes of ill-typed program. Tracked granularly so
    # partial gates cannot masquerade as the whole checker.
    self_compiling: true,
    self_checking: false,
    exhaustiveness_gated: true,
    capability_gated: true,
    type_gated: true,
    # has `build` compiled a real selfhost_*.rian slice (not a toy corpus)? Yes —
    # the WHOLE capability checker (cap.rian) and the whole lexer/decl/beam/
    # core/exhaust stages compile + run identically to Rian.Beam.
    closed_on_real_source:
      "cap.rian (whole file) — plus the whole lexer/decl/beam/core/exhaust stages and the driver itself",
    real_source_test: "test/rian/compose_selfcompile_fixpoint_test.exs",
    # has the bootstrap fixed point closed? Yes, for the Rian compiler (self-compiling):
    # gen1 == gen2 over the four compiler sources, identical forms + bit-identical .beam.
    bootstrap_v1_v2: true,
    bootstrap_test: "test/rian/selfhost_v1_v2_fixpoint_test.exs",
    note:
      "The driver owns NO lexing or parsing — the whole front-end AND the back-end are equivalence-locked ports (`selfhost_lexer_v2` → `selfhost_decl` → `selfhost_beam`), composed cross-module under :\"Elixir.*\" atoms (Pascal calls, ADR-0041). `LexerV2.tokenize` feeds `Decl.parse_program` with NO projection (same token tags). The only driver-local glue reimplements no stage: the surface→Core lowering (selfhost_decl's Expr/Pat IR → selfhost_beam Core/Pat) and the Form inflater. The composed build's surface now spans the whole compiler-stage vocabulary — multi-clause patterns incl. cons-lists and tuples, sum-type/struct declarations + ctor dispatch, `if`, `case` with guards, strings/chars, atoms, struct field access (`maps:get`), cross-module remote calls, `@external` FFI bodies (parsed-and-spliced per ADR-0068), and `forall` generics. Whole-file self-compile locks cover lexer/decl/beam/driver (`compose_*_whole`) plus cap/core/exhaust (`compose_selfcompile`/`compose_stage_whole`). The bootstrap fixed point `v1 == v2` is CLOSED for the Rian compiler (`selfhost_v1_v2_fixpoint_test`): gen0 (Elixir-host-compiled) compiles the four compiler sources → gen1; gen1 recompiles them → gen2; gen1 == gen2 in canonical forms AND bit-identical `.beam` (`:deterministic`). This is self-COMPILING and PARTIALLY self-CHECKING: four gates are wired into the build loop — the two STRUCTURAL ones (`build` refuses a non-exhaustive sum dispatch via Exhaust, and a BEAM-illegal `ref` parameter via Cap.beam_legal) PLUS the first two TYPE-checker error sets, NUMERIC MIX (an int↔float `+`/`-`/`*`) and RETURN-TYPE mismatch (a body whose inferred type contradicts the declared return), in a `d_func`, via the equivalence-locked `Checker.num_mix`/`Checker.ret_bad` (ADR-0035/0064) — all via `:erlang.error` (`compose_exhaust_gate_fixpoint_test`, `compose_type_gate_fixpoint_test`). FULL self-CHECKING remains the next terminus: the checker port (checker.rian) covers 12/12 Core nodes WITH a typing env and now its first two error sets, but the remaining error sets (binding/bounds/error-set) and d_clause coverage are still out of the loop, so `build` rejects only those two classes of ill-typed program. Host FFI in the loop: :compile.forms/:code.load_binary/:erlang.error."
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

  @doc "The auxiliary self-hosted passes (not pipeline stages; excluded from `percent/0`)."
  @spec passes() :: [map()]
  def passes, do: @passes

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

    pass_rows =
      Enum.map_join(@passes, "\n", fn p ->
        "| #{p.name} | `#{p.oracle}` | `compiler/#{p.source}` · `#{p.test}` | #{p.note} |"
      end)

    """
    # Self-compiling status — BEAM, forms-level (generated — do not edit by hand)

    Generated by `Rian.SelfHost.status_markdown/0`; regenerate with `mix test` (the
    snapshot is gated by `test/rian/self_host_status_test.exs`). This measures the
    **BEAM** bootstrap (ADR-0063 §4) — the Rian compiler compiling its own source to
    `.beam`. The honest claim is **self-COMPILING (BEAM, forms-level), v1==v2 closed** —
    *not* bare "self-hosting": the loop does not yet self-CHECK, isn't multi-backend, and
    compiles its own subset of Rian (see the "What `v1 == v2` does NOT mean" box).
    **Portable** self-hosting (the compiler lowered to Rust/JS) is a separate, further
    terminus and is *not* measured here.

    **Two axes, two numbers** — one headline can't carry both, so neither is hidden:

    * **#{percent()}% per-stage equivalence** — #{count(:self_hosted)} stage(s)
      self-hosted, #{count(:partial)} partial, #{count(:not_started)} not started, of
      #{length(@stages)}, each matched against the reference **in isolation** (Elixir
      projection glue per fixpoint). This is NOT a loop number.
    * **Bootstrap loop: CLOSED** — `v1 == v2` over #{@composition.stages} compiler
      modules, **self-compiling** (forms-level, BEAM); **partially self-checking** — the
      first two type-checker error sets (numeric mix + return-type) are now in the loop,
      the rest are not. Evidence: `#{@composition.bootstrap_test}`.

    **Composition (ADR-0063 Step 3) — a separate axis.** The percentage above counts
    stages verified against the reference *in isolation* (each fixpoint uses Elixir
    projection glue); it can reach 100% without the pipeline ever closing a loop. The
    composition rung measures the orthogonal question — stages handing their Rian output
    to the next Rian stage with **no glue**. Current rung: **#{@composition.rung}**
    (#{@composition.stages} stages), over the #{@composition.subset}. #{@composition.note}.
    Source: `#{@composition.source}`, fixpoint: `#{@composition.test}`. The bootstrap
    terminus (Stage 3, v1==v2) was gated on this reaching the whole pipeline — not on the
    per-stage percentage — and it now has (4 stages, loop closed).

    **What `v1 == v2` does NOT mean.** The closed loop is a genuine bootstrap fixed point,
    but it is deliberately scoped — three real gaps, none hidden:

    * **Only the first two error sets** — the loop is self-*compiling* and only *partially*
      self-*checking*. Four gates run in `build`: the two **structural** ones
      (exhaustiveness, capability) **and** the first two TYPE-checker error sets — **numeric
      mix** (an int↔float `+`/`-`/`*`) and **return-type mismatch** (a body whose inferred
      type contradicts the declared return), in a `d_func`, via the locked
      `Checker.num_mix`/`ret_bad` (ADR-0035/0064). The rest of `Rian.Check`'s error sets
      (binding/bounds/error-set) and d_clause coverage are **not** yet in the loop, so
      `build` still compiles most ill-typed programs it should reject.
    * **BEAM-only** — the fixed point is forms-level `.beam`. Compiling the compiler to
      Rust/JS (the *portable* terminus) is unstarted.
    * **A subset of Rian** — `build` compiles the compiler's own source shape, not
      *arbitrary* Rian (the prelude/examples). Widening this is gated behind the checker
      port + `decl_parser` leaving `:partial`.

    **Loop closed on real source:** `build` compiles a verbatim slice of a real compiler
    stage — **#{@composition.closed_on_real_source}** — and runs identically to
    `Rian.Beam` (`#{@composition.real_source_test}`). This is a stage compiling its own
    source, not a toy corpus. `build`'s surface now spans the whole compiler-stage
    vocabulary, and `v1 == v2` is **closed** (`#{@composition.bootstrap_test}`); the
    remaining work is self-CHECKING (the checker port) and *arbitrary*-Rian breadth.

    | Stage | Role | Self-hosted | Evidence | Notes |
    | --- | --- | --- | --- | --- |
    #{rows}

    A stage is `self-hosted` only when a Rian port is **equivalence-locked** against the
    reference (the fixpoint method); `partial` is a verified slice with remaining
    vocabulary; `not-started` has no Rian port (a toy-language spike does not count).

    ## Auxiliary passes (self-hosted; not pipeline stages)

    Compiler passes drained from Elixir into Rian that are not one of the 11 pipeline
    stages above (they run at the parse boundary / pre-emit / as analysis), so they are
    tracked here and excluded from the per-stage `%` (ADR-0063 #2).

    | Pass | Oracle | Evidence | Notes |
    | --- | --- | --- | --- |
    #{pass_rows}
    """
  end

  defp badge(:self_hosted), do: "✅ yes"
  defp badge(:partial), do: "🟡 partial"
  defp badge(:not_started), do: "—"

  defp evidence(%{source: nil}), do: "—"

  defp evidence(%{source: src, test: test}),
    do: "`compiler/#{src}`" <> if(test, do: " · `#{test}`", else: "")

  @doc "The self-host Rian sources cited as evidence (absolute paths)."
  @spec evidence_files() :: [String.t()]
  def evidence_files do
    for s <- @stages, s.source, do: Path.join(@compiler_dir, s.source)
  end

  # ── @selfhost_ffi ledger (ADR-0063 §4 — permitted, but counted) ────────────

  # Every host-FFI crutch the self-host sources still lean on, keyed by file. These
  # are NOT portable (`Rian.Reach` pins them off `:rs`/`:js`); the portable prelude
  # (ADR-0047) is meant to own them. A P5 swap that replaces one with portable Rian
  # MUST delete its line here (the test fails on a stale entry), and any NEW host FFI
  # MUST be added here (the test fails on an unlisted crutch). Sorted, deduped.
  @ffi_ledger %{
    # `compose_real_sum.rian` is the ACTIVE driver: it wires the verified ports
    # (LexerV2.tokenize → Decl.parse_program → Beam.compile_forms, all cross-module
    # composition, excluded from the FFI count — see ffi_in_file/1) over a surface
    # spanning sum types + ctor dispatch, and runs the exhaustiveness + capability
    # gates. Its host FFI: the two BEAM toolchain calls, plus `:erlang.binary_to_list`
    # (a String's BYTES for the `{:string, L, Cs}` bin-segment of a string literal's
    # form — matching Rian.Beam.str_form; codepoints would truncate >255 in an 8-bit
    # segment) and `:erlang.error` (the gate-refusal raise). The earlier graduated
    # rungs (compose_real_beam/front/decl/lex) were retired — superseded by this
    # driver + the verified ports, none depended on by the bootstrap loop.
    "compose_real_sum.rian" => [
      ":code.load_binary",
      ":compile.forms",
      ":erlang.binary_to_list",
      ":erlang.error"
    ]
  }

  @doc "The declared host-FFI crutch ledger: self-host file basename -> sorted constructs."
  @spec ffi_ledger() :: %{String.t() => [String.t()]}
  def ffi_ledger, do: @ffi_ledger

  @doc "All `compiler/*.rian` source paths."
  @spec selfhost_files() :: [String.t()]
  def selfhost_files, do: Path.wildcard(Path.join(@compiler_dir, "*.rian"))

  @doc """
  The `mod <Name>` module names declared across the self-host sources — the set of
  *sibling self-host ports*. A Pascal-qualified call to one of these (e.g.
  `Beam.compile_forms`) is intra-self-host **composition**, not a host
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

  Cross-module calls to a *sibling self-host port* (`Beam.compile_forms`) are
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
