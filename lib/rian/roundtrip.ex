defmodule Rian.Roundtrip do
  @moduledoc """
  The **Elixir→Rian→Elixir roundtrip** harness: drives an Elixir source — one or
  more modules — through the three-step pipeline and reports, per stage, whether it
  survives. Rian modules are flat, so a nested Elixir module is hoisted to a
  sibling top-level `mod`; the harness compiles every module and compares the
  **merged** normalized forms, so nothing is silently dropped.

      lib/foo.ex ──transpile──▶ tmp/rian/foo.rian ─┬─Rian.Beam─────────▶ BEAM (path 2)
                                                    └─Rian.Lower(Elixir)─▶ tmp/ex/foo.ex ─▶ BEAM (path 3)

  Two backends produce BEAM from the *same* Rian draft — `Rian.Beam` (abstract
  forms, the canonical path) and `Rian.Lower`'s Elixir-text emitter fed back
  through the Elixir compiler — and the harness cross-checks them against each
  other and against the original module's bytecode (`Rian.FormsEquiv`):

    * `beam_direct`      — does the draft compile through `Rian.Beam`?
    * `elixir`           — does it re-render to Elixir source (`Rian.Lower`)?
    * `beam_via_elixir`  — does that Elixir source compile?
    * `equiv_two_paths`  — do the two backends agree (forms-equivalent)?
    * `equiv_vs_origin`  — does the roundtripped module match the *original*
                           Elixir (the `lib/rian == tmp/ex` check, at forms level)?

  A transpiled draft only reaches the BEAM stages once its `TODO_PORT` markers are
  resolved and its types are annotated — a `_Unk` hole compiles (it is an open
  type), but a marker or an unportable construct does not. So the report is the
  honest gate for "how far does this module roundtrip".

  Both equivalence checks compare **function forms**. A declaration-only module
  (only `type`/`struct`, no functions) contributes no comparable forms — its
  declarations erase to data on the BEAM (ADR-0043) — so the check is `:skipped`,
  never `:equiv` (the oracle verified nothing; a trivial `[] == []` would be a
  false green). And the two backends genuinely diverge on a `struct`: `Rian.Beam`
  erases it to a tagged map (no accessor forms), while `Rian.Lower`'s Elixir text
  emits a real `defstruct` (with `__struct__/0,1`) — surfaced honestly as a
  `equiv_two_paths` divergence rather than hidden by dropping the nested module.
  """

  alias Rian.{Beam, Decl, Format, FormsEquiv, Lower, Transpile}

  # Every backend compiles into this one throwaway module so (a) the BEAM binaries
  # line up for `Rian.FormsEquiv` and (b) compiling a `lib/rian/*.ex` source — or
  # the regenerated `defmodule Range` — never clobbers the live compiler module (or
  # a built-in like `Range`) the harness is itself running on.
  @probe :"Elixir.RoundtripProbe"

  @type stage :: :ok | {:error, String.t()}
  @type report :: %{
          rian: String.t(),
          elixir: String.t() | nil,
          beam_direct: stage,
          beam_via_elixir: stage,
          equiv_two_paths: :equiv | :diverges | :skipped,
          equiv_vs_origin: :equiv | :diverges | :skipped
        }

  @doc "Run the full roundtrip on one Elixir source string, returning a `t:report/0`."
  @spec run(String.t()) :: report()
  def run(ex_src) when is_binary(ex_src) do
    # link the portable prelude so a transpiled `List`/`Dict`/`Str` call the draft
    # carries can compile and run on the BEAM path (idempotent).
    Rian.Prelude.load()
    rian = ex_src |> Transpile.transpile() |> format_rian()
    mods = split_top_mods(rian)
    origin = safe(fn -> origin_forms(ex_src) end)
    elixir = safe(fn -> render_elixir(mods) end)

    # An unresolved `TODO_PORT(...)` marker compiles as an ordinary call to an
    # undefined function — it would not *lie* about being a finished port, so the
    # BEAM stages are reported as failed while the draft still carries one. A
    # `_Unk` type hole is fine (it is an open type that compiles).
    {direct, via} =
      if marker?(rian) do
        unresolved = {:error, "unresolved TODO_PORT marker(s)"}
        {unresolved, unresolved}
      else
        {safe(fn -> beam_forms(mods) end), safe(fn -> elixir_forms(mods) end)}
      end

    %{
      rian: rian,
      elixir: ok_value(elixir),
      beam_direct: as_stage(direct),
      beam_via_elixir: as_stage(via),
      equiv_two_paths: equiv(direct, via),
      equiv_vs_origin: equiv(via, origin)
    }
  end

  @doc """
  Transpile + roundtrip an Elixir file; write the `<out>/rian` and `<out>/ex`
  artifacts under `stem` (a relative path without extension, so sources that share
  a basename — e.g. `cli.ex` and `format/cli.ex` — do not collide).
  """
  @spec run_file(Path.t(), Path.t(), String.t()) :: report()
  def run_file(file, out_dir, stem) do
    report = run(File.read!(file))

    write(Path.join([out_dir, "rian", "#{stem}.rian"]), report.rian)
    if report.elixir, do: write(Path.join([out_dir, "ex", "#{stem}.ex"]), report.elixir)
    report
  end

  # ── stages ──────────────────────────────────────────────────────────────────
  #
  # Rian is flat (the transpiler hoists nested modules to siblings), so the program
  # is one source per top-level module. Each module is compiled independently and
  # its normalized forms merged, so the comparison spans the whole program rather
  # than silently covering only the first module.

  # path 2 — each module through the canonical abstract-forms backend (`Rian.Beam`).
  defp beam_forms(mods), do: merged_forms(mods, &beam_one/1)

  # path 3 — each module rendered to Elixir (`Rian.Lower`) and recompiled. The
  # rendered Elixir can NEST modules (a `struct` lowers to `defmodule … defstruct`),
  # so EVERY compiled module's forms are collected — exactly as `origin_forms/1`
  # does for the original — or a struct-only module would silently contribute
  # nothing and report a false `equiv` (the harness's "nothing silently dropped"
  # contract). The two backends legitimately differ here: `Rian.Beam` erases a
  # `struct` to a tagged map (no accessor forms, ADR-0043), while `Rian.Lower`'s
  # Elixir text emits a real `defstruct` (with `__struct__/0,1`) — collecting all
  # modules surfaces that difference honestly instead of masking it.
  defp elixir_forms(mods),
    do:
      mods
      |> Enum.flat_map(fn m -> m |> rian_to_elixir() |> compile_elixir_forms() end)
      |> Enum.sort()

  defp merged_forms(mods, compile_one),
    do: mods |> Enum.flat_map(&FormsEquiv.normalize(compile_one.(&1))) |> Enum.sort()

  defp beam_one(mod_src) do
    {:ok, @probe, bin} = Beam.compile(mod_src, @probe)
    purge(@probe)
    bin
  end

  # the combined Elixir text of every module (for `tmp/ex` and inspection).
  defp render_elixir(mods), do: Enum.map_join(mods, "\n\n", &rian_to_elixir/1)

  defp rian_to_elixir(mod_src) do
    case Decl.parse(mod_src) do
      # `compile_module_beam/1` renders only the Elixir text (path 3 target); the
      # full `compile_module/1` would also eagerly emit Rust, which is irrelevant
      # here and not defined for an undeclared cross-module construction.
      %{mods: [m | _]} -> Lower.compile_module_beam(m).elixir |> format_ex()
      _ -> raise "no module in Rian source"
    end
  end

  # The merged normalized forms of every module the original Elixir defines (it may
  # nest modules); renamed so compiling it cannot clobber a live module.
  defp origin_forms(ex_src) do
    quoted = ex_src |> Code.string_to_quoted!() |> rename_to_probe()

    with_debug_info(fn ->
      mods = Code.compile_quoted(quoted)
      forms = mods |> Enum.flat_map(fn {_m, bin} -> FormsEquiv.normalize(bin) end) |> Enum.sort()
      Enum.each(mods, fn {m, _} -> purge(m) end)
      forms
    end)
  end

  # Split the formatted Rian into one source string per top-level module — each
  # `mod … end` closing at a column-0 `end` (Rian is flat).
  defp split_top_mods(rian) do
    {blocks, _cur} =
      rian
      |> String.split("\n")
      |> Enum.reduce({[], []}, fn line, {blocks, cur} ->
        cur = [line | cur]

        if line == "end" and Enum.any?(cur, &String.starts_with?(&1, "mod ")),
          do: {[Enum.reverse(cur) | blocks], []},
          else: {blocks, cur}
      end)

    blocks |> Enum.reverse() |> Enum.map(&Enum.join(&1, "\n"))
  end

  # Generated artifacts are emitted formatted — `Rian.Format` for Rian, the Elixir
  # formatter for Elixir. A draft that still carries markers may not parse for the
  # Rian formatter, so it falls back to the raw text.
  defp format_rian(src) do
    case Format.format_result(src) do
      {:ok, out} -> out
      {:error, _} -> src
    end
  end

  defp format_ex(src) do
    IO.iodata_to_binary(Code.format_string!(src)) <> "\n"
  rescue
    _ -> src
  end

  # Compile Elixir source text (the top module renamed to `@probe` so nothing live
  # is clobbered) and return the normalized forms of **every** module it defines —
  # not just the outer one, so a nested `defmodule … defstruct` is not silently
  # dropped. `debug_info` is required so `Rian.FormsEquiv` can read the abstract
  # code back; every defined module is purged after so the harness leaves nothing
  # loaded in the VM.
  defp compile_elixir_forms(src) do
    quoted = src |> Code.string_to_quoted!() |> rename_to_probe()

    with_debug_info(fn ->
      mods = Code.compile_quoted(quoted)
      forms = Enum.flat_map(mods, fn {_m, bin} -> FormsEquiv.normalize(bin) end)
      Enum.each(mods, fn {m, _} -> purge(m) end)
      forms
    end)
  end

  # `debug_info` is required so `Rian.FormsEquiv` can read the abstract code back;
  # restored after so the harness leaves the compiler option as it found it.
  defp with_debug_info(fun) do
    prev = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      fun.()
    after
      Code.put_compiler_option(:debug_info, prev)
    end
  end

  # Rename the outermost `defmodule` to `@probe`; nested modules keep their (now
  # `RoundtripProbe`-scoped) names.
  defp rename_to_probe({:defmodule, m, [_alias, body]}),
    do: {:defmodule, m, [{:__aliases__, [], [:RoundtripProbe]}, body]}

  defp rename_to_probe(_), do: raise("source is not a single module")

  defp purge(atom) do
    :code.purge(atom)
    :code.delete(atom)
  end

  # A real marker is an emitted `TODO_PORT("…")` call or a `# TODO[port]: …` line —
  # NOT the draft header, which merely *names* both forms (`TODO_PORT(...)`,
  # `` `# TODO[port]` ``) in prose without the quote/colon.
  #
  # This is **deliberately text-based**, not a structural AST scan. It is a fail-safe
  # gate, and the safe bias is to never report an unfinished draft as a finished port:
  # a false negative is worse than a false positive here. A structural walk would have
  # to enumerate *every* place a marker can appear (clause bodies, const values, the
  # `# TODO[port]` comment — which is stripped from the AST entirely) and would silently
  # miss any it didn't, passing a draft as a clean roundtrip. The text scan cannot miss
  # one. Matching the call-open `TODO_PORT("` and the comment form `TODO[port]:` (not a
  # bare mention) keeps the residual false-positive surface to source that literally
  # contains the marker syntax in a comment/string — rare and harmlessly conservative.
  defp marker?(rian), do: String.contains?(rian, ["TODO_PORT(\"", "TODO[port]:"])

  # ── result plumbing ───────────────────────────────────────────────────────────

  defp safe(fun) do
    {:ok, fun.()}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # two programs are equivalent when their merged normalized forms match — compared
  # only when both stages produced forms. Two *empty* form lists are NOT a verified
  # equivalence: it means neither side contributed a comparable function (e.g. a
  # struct-/type-only module, whose declarations erase to data on the BEAM, ADR-0043).
  # Reporting `equiv` there would be a false green — the oracle verified nothing — so
  # it is `:skipped` ("—"), reserving `equiv` for an actual matched function set.
  defp equiv({:ok, []}, {:ok, []}), do: :skipped

  defp equiv({:ok, a}, {:ok, b}) when is_list(a) and is_list(b),
    do: if(a == b, do: :equiv, else: :diverges)

  defp equiv(_, _), do: :skipped

  defp ok_value({:ok, v}), do: v
  defp ok_value({:error, _}), do: nil

  # a stage reports `:ok`/`{:error, reason}` — the forms themselves are internal.
  defp as_stage({:ok, _forms}), do: :ok
  defp as_stage({:error, _} = e), do: e

  defp write(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
