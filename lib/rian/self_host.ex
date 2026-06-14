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
      note: "IR equals Rian.Decl over type/struct/mod/def slice; alias/protocol/generics remain"
    },
    %{
      id: :expr_parser,
      name: "Expression/pattern parser",
      role: :frontend,
      status: :partial,
      source: "selfhost_parse.rian",
      test: "test/rian/parse_fixpoint_test.exs",
      note: "AST equals Rian.Pratt over an arithmetic/precedence slice"
    },
    %{
      id: :core_ir,
      name: "Typed Core IR (from_expr/from_pat)",
      role: :frontend,
      status: :partial,
      source: "selfhost_core.rian",
      test: "test/rian/core_fixpoint_test.exs",
      note:
        "surface→Core lowering equals Rian.Core.from_expr over the literal/unary/binary slice; calls/lists/blocks/lambdas remain"
    },
    %{
      id: :checker,
      name: "Type checker (inference + error sets)",
      role: :checker,
      status: :not_started,
      source: nil,
      test: nil,
      note: "selfhost_check.rian checks a TOY language, not Rian.Check — not a port"
    },
    %{
      id: :exhaustiveness,
      name: "Exhaustiveness gate",
      role: :checker,
      status: :partial,
      source: "selfhost_exhaust.rian",
      test: "test/rian/exhaust_fixpoint_test.exs",
      note:
        "single-column nullary-constructor verdict agrees with Maranget useful?/3; ctors-with-args, multi-column, list/literal/range patterns remain"
    },
    %{
      id: :capability,
      name: "Capability checker",
      role: :checker,
      status: :partial,
      source: "selfhost_cap.rian",
      test: "test/rian/cap_fixpoint_test.exs",
      note:
        "capability→Rust lowering + ref-rejecting BEAM legality equal Rian.Capability over the scalar/String/Vec/nominal slice; deep generics + linearity remain"
    },
    %{
      id: :beam_backend,
      name: "BEAM abstract-forms backend",
      role: :backend,
      status: :not_started,
      source: nil,
      test: nil,
      note: "selfhost_codegen.rian is a toy stack VM, not the Rian.Beam emitter"
    },
    %{
      id: :text_backend,
      name: "Rust/Elixir text backend",
      role: :backend,
      status: :not_started,
      source: nil,
      test: nil,
      note: "not ported"
    },
    %{
      id: :js_backend,
      name: "ECMAScript backend",
      role: :backend,
      status: :not_started,
      source: nil,
      test: nil,
      note: "not ported"
    },
    %{
      id: :jvm_backend,
      name: "Kotlin/JVM backend",
      role: :backend,
      status: :not_started,
      source: nil,
      test: nil,
      note: "not ported"
    }
  ]

  @weights %{self_hosted: 1.0, partial: 0.5, not_started: 0.0}

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
  def status_markdown do
    rows =
      Enum.map_join(@stages, "\n", fn s ->
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
    "selfhost_modules.rian" => ["String.to_charlist"]
  }

  @doc "The declared host-FFI crutch ledger: self-host file basename -> sorted constructs."
  @spec ffi_ledger() :: %{String.t() => [String.t()]}
  def ffi_ledger, do: @ffi_ledger

  @doc "All `examples/rian/selfhost_*.rian` source paths."
  @spec selfhost_files() :: [String.t()]
  def selfhost_files, do: Path.wildcard(Path.join(@examples_dir, "selfhost_*.rian"))

  @doc """
  The *actual* host-FFI constructs a self-host source leans on — the `:ffi`/
  `:concurrency` blocker constructs `Rian.Reach` finds (Erlang `:mod.fun` / non-Rian
  `Mod.fun` calls), deduped and sorted. This is the measurement the ledger is checked
  against; `Prim.*` intrinsics are the sanctioned primitive layer, not FFI, so they do
  not appear.
  """
  @spec ffi_in_file(String.t()) :: [String.t()]
  def ffi_in_file(path) do
    path
    |> File.read!()
    |> Rian.Decl.parse()
    |> Rian.Reach.analyze()
    |> Map.values()
    |> Enum.flat_map(& &1.blockers)
    |> Enum.filter(&(&1.kind in [:ffi, :concurrency]))
    |> Enum.map(& &1.construct)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
