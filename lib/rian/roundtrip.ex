defmodule Rian.Roundtrip do
  @moduledoc """
  The **Elixir→Rian→Elixir roundtrip** harness: drives one Elixir module through
  the three-step pipeline and reports, per stage, whether it survives.

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
  """

  alias Rian.{Beam, Decl, FormsEquiv, Lower, Transpile}

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
    rian = Transpile.transpile(ex_src)
    origin = safe(fn -> compile_elixir(ex_src) end)

    # An unresolved `TODO_PORT(...)` marker compiles as an ordinary call to an
    # undefined function — it would not *lie* about being a finished port, so the
    # BEAM stages are reported as failed while the draft still carries one. A
    # `_Unk` type hole is fine (it is an open type that compiles).
    {direct, elixir, via} =
      if marker?(rian) do
        unresolved = {:error, "unresolved TODO_PORT marker(s)"}
        {unresolved, safe(fn -> rian_to_elixir(rian) end), unresolved}
      else
        {elixir, via} = via_elixir(rian)
        {safe(fn -> beam_direct(rian) end), elixir, via}
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

  # Rian draft → BEAM through the canonical abstract-forms backend, into `@probe`.
  defp beam_direct(rian) do
    {:ok, @probe, bin} = Beam.compile(rian, @probe)
    purge(@probe)
    bin
  end

  # Rian draft → Elixir module source (`Rian.Lower`) → BEAM. Returns the rendered
  # Elixir (for `tmp/ex` and inspection) alongside the compile result.
  defp via_elixir(rian) do
    elixir = safe(fn -> rian_to_elixir(rian) end)

    case elixir do
      {:ok, text} -> {elixir, safe(fn -> compile_elixir(text) end)}
      {:error, _} = e -> {elixir, e}
    end
  end

  defp rian_to_elixir(rian) do
    case Decl.parse(rian) do
      # `compile_module_beam/1` renders only the Elixir text (path 3 target); the
      # full `compile_module/1` would also eagerly emit Rust, which is irrelevant
      # here and not defined for an undeclared cross-module construction.
      %{mods: [m | _]} -> Lower.compile_module_beam(m).elixir
      _ -> raise "no module in Rian source"
    end
  end

  # Compile Elixir source text into `@probe` (the top module renamed so nothing
  # live is clobbered), returning the bytecode. `debug_info` is required so
  # `Rian.FormsEquiv` can read the abstract code back; every defined module is
  # purged after so the harness leaves nothing loaded in the VM.
  defp compile_elixir(src) do
    quoted = src |> Code.string_to_quoted!() |> rename_to_probe()
    prev = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      mods = Code.compile_quoted(quoted)
      {@probe, bin} = List.keyfind(mods, @probe, 0)
      Enum.each(mods, fn {m, _} -> purge(m) end)
      bin
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
  defp marker?(rian), do: String.contains?(rian, ["TODO_PORT(\"", "TODO[port]:"])

  # ── result plumbing ───────────────────────────────────────────────────────────

  defp safe(fun) do
    {:ok, fun.()}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # the two BEAM binaries are forms-equivalent only if both stages produced one.
  defp equiv({:ok, a}, {:ok, b}) when is_binary(a) and is_binary(b),
    do: if(FormsEquiv.equivalent?(a, b), do: :equiv, else: :diverges)

  defp equiv(_, _), do: :skipped

  defp ok_value({:ok, v}), do: v
  defp ok_value({:error, _}), do: nil

  # a BEAM stage reports `:ok`/`{:error, reason}` — the binary itself is internal.
  defp as_stage({:ok, _bin}), do: :ok
  defp as_stage({:error, _} = e), do: e

  defp write(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
