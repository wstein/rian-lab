defmodule Mix.Tasks.Rian.Dialyze do
  @shortdoc "Cross-check a Rian source's emitted BEAM with Dialyzer (external oracle)"

  @moduledoc """
  Compile a Rian source to BEAM (with the Dialyzer `-spec`s of ADR-0026) and run
  **Dialyzer** on it as an independent second-opinion type-checker (ADR-0076 §5).

      mix rian.dialyze FILE.rian

  Dialyzer uses *success typings* — it never false-positives, so any discrepancy it
  reports is a real bug in Rian's checker or codegen. This is the same discipline as
  the equiv-lock harness: an external, sound oracle that can only be right. Exit
  status is non-zero when Dialyzer reports a warning.

  The OTP PLT (erts/kernel/stdlib) is built once and cached under the build path;
  the first run is slow, subsequent runs are fast.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    file =
      case args do
        [f | _] -> f
        [] -> Mix.raise("usage: mix rian.dialyze FILE.rian")
      end

    unless File.regular?(file), do: Mix.raise("no such file: #{file}")
    ensure_dialyzer!()

    beam = compile_to_beam(file)

    try do
      plt = ensure_plt()

      # `:dialyzer` is an OTP tool, available at runtime but not loaded at compile
      # time — call it dynamically so it stays an optional dev dependency.
      warnings =
        apply(:dialyzer, :run, [
          [
            analysis_type: :succ_typings,
            files: [String.to_charlist(beam)],
            plts: [String.to_charlist(plt)],
            warnings: [:unknown]
          ]
        ])

      report(warnings)
    after
      File.rm_rf(Path.dirname(beam))
    end
  end

  @doc false
  # `:dialyzer` ships with most OTP distributions but is not auto-loaded (and some
  # slim installs omit it). Fail with a clear, actionable message rather than an
  # `UndefinedFunctionError` deep in `run/1`.
  def dialyzer_available? do
    match?({:module, _}, Code.ensure_loaded(:dialyzer))
  end

  defp ensure_dialyzer! do
    unless dialyzer_available?() do
      Mix.raise(
        "Dialyzer is not available in this OTP install (no `dialyzer` app). " <>
          "Install it (it ships with most full Erlang/OTP distributions) and retry."
      )
    end
  end

  # compile the Rian source to a real `.beam` (debug_info + -specs) in a temp dir.
  defp compile_to_beam(file) do
    mod = :"Elixir.RianDialyze"
    {:ok, ^mod, bin} = Rian.Beam.compile(File.read!(file), mod)
    dir = Path.join(System.tmp_dir!(), "rian_dialyze_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{mod}.beam")
    File.write!(path, bin)
    path
  end

  # build/cache an OTP PLT once under the build path.
  defp ensure_plt do
    plt = Path.join(Mix.Project.build_path(), "rian-dialyzer.plt")

    unless File.exists?(plt) do
      Mix.shell().info("building Dialyzer PLT (one-time, slow) → #{plt}")
      File.mkdir_p!(Path.dirname(plt))

      apply(:dialyzer, :run, [
        [
          analysis_type: :plt_build,
          apps: [:erts, :kernel, :stdlib],
          output_plt: String.to_charlist(plt)
        ]
      ])
    end

    plt
  end

  defp report([]) do
    Mix.shell().info("Dialyzer: no warnings — clean ✓")
  end

  defp report(warnings) do
    for w <- warnings,
        do: Mix.shell().error(apply(:dialyzer, :format_warning, [w]) |> to_string())

    Mix.shell().error("\nDialyzer: #{length(warnings)} warning(s)")
    exit({:shutdown, 1})
  end
end
