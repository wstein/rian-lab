defmodule Mix.Tasks.Rian.Tour do
  @shortdoc "Regenerate site/src/data/tour.json from the real emitters"

  @moduledoc """
  Regenerate the **"Rian by Example"** dataset the site consumes.

      mix rian.tour [--check]

  `Rian.Tour.generate/0` runs the real Rust/JS/Kotlin emitters and the
  reachability analysis over the curated tour programs and writes the result to
  `site/src/data/tour.json`. The site pages (by-example, homepage, playground,
  docs reader) import that file, so the per-target code they show is exactly what
  the compiler produces — it cannot drift from the language.

    * (no flags)  write `site/src/data/tour.json`
    * `--check`   exit non-zero if the committed file is stale, **and** run the
                  by-example reach gate (`Rian.Tour.Examples.check!/0`): every
                  `examples/rian/NN_*.rian` file must honour its `#@reach` /
                  `#@reach-pin` / `#@illustrative` header. CI and the
                  `Rian.TourTest` / `Rian.TourReachTest` suites run the same checks.
  """
  use Mix.Task

  @path "site/src/data/tour.json"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _} = OptionParser.parse(args, strict: [check: :boolean])
    Mix.Task.run("compile")

    json = Rian.Tour.to_json() <> "\n"

    if opts[:check] do
      check(json)
      check_examples()
    else
      File.mkdir_p!(Path.dirname(@path))
      File.write!(@path, json)
      Mix.shell().info("wrote #{@path} (#{byte_size(json)} bytes)")
    end
  end

  defp check(json) do
    case File.read(@path) do
      {:ok, ^json} ->
        Mix.shell().info("#{@path} is up to date ✓")

      _ ->
        Mix.raise("#{@path} is stale — run `mix rian.tour` and commit the result")
    end
  end

  defp check_examples do
    Rian.Tour.Examples.check!()
    n = length(Rian.Tour.Examples.files())
    Mix.shell().info("by-example reach gate: all #{n} files honour their headers ✓")
  rescue
    e in Rian.Tour.Examples.Error -> Mix.raise(Exception.message(e))
  end
end
