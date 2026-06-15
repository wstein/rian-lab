defmodule RianLab.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/wstein/rian_lab"

  def project do
    [
      app: :rian_lab,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      # `Rian.DocFormatter` (the ExDoc/Starlight formatter under `dev/`) uses ExDoc
      # internals, and ExDoc is `only: [:dev, :test]` — so it must be compiled only
      # where ExDoc is available, never in `:prod` (where `%ExDoc.Autolink{}` is an
      # undefined struct). Docs build in `:dev` (`mix docs`); the suite is `:test`.
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: test_coverage(),
      deps: deps(),
      name: "RianLab",
      description:
        "Reference implementation and design corpus for Rian — a typed, " <>
          "capability-disciplined language that lowers to the BEAM and to idiomatic Rust.",
      source_url: @source_url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # `test.all` is an alias, so it would default to the `:dev` env; force `:test`.
  def cli do
    [preferred_envs: ["test.all": :test]]
  end

  # `dev/` holds the ExDoc-dependent doc tooling (`Rian.DocFormatter`); it compiles
  # only in `:dev`/`:test`, where ExDoc is a dependency. `:prod` builds `lib/` alone.
  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "dev"]

  # `mix test --cover` (built-in) gate. Excluded from the denominator:
  #   * `Rian.DocFormatter*` — the dev-only ExDoc/Starlight doc formatter (it
  #     drives ExDoc, exercised by `mix docs`, not unit-tested);
  #   * `Mix.Tasks.Rian.*` — CLI entry points (thin `Mix.shell` wrappers over the
  #     library code, which *is* covered).
  defp test_coverage do
    [
      summary: [threshold: 95],
      ignore_modules: [~r/^Rian\.DocFormatter/, ~r/^Mix\.Tasks\./]
    ]
  end

  defp deps do
    [
      # `:test` too — `Rian.DocFormatter` (in `lib/`) references `ExDoc.Autolink`,
      # so the test env must be able to compile it (CI runs `MIX_ENV=test`).
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
    ]
  end

  # ExDoc groups the design corpus alongside the reference modules.
  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      # html for comparison; Rian.DocFormatter is the Starlight production path
      formatters: ["html", Rian.DocFormatter],
      # the docs tooling itself is not public API — keep it out of the docs
      filter_modules: fn module, _meta ->
        module not in [Rian.DocFormatter, Rian.DocFormatter.MDX]
      end,
      # Explicit slugs/titles for the same-named READMEs so they do not collide
      # (root README.md keeps the `readme` slug that `main: "readme"` resolves to).
      extras:
        [
          "README.md",
          {"docs/rian-in-10-minutes.md",
           filename: "rian-in-10-minutes", title: "Rian in 10 Minutes"},
          {"docs/README.md", filename: "design-corpus", title: "Design Corpus"},
          {"examples/rian/README.md", filename: "rian-by-example", title: "Rian by Example"}
        ] ++
          Path.wildcard("docs/adr/*.md") ++ Path.wildcard("docs/spec/*.md"),
      groups_for_extras: [
        Overview: ["README.md", "docs/rian-in-10-minutes.md", "docs/README.md"],
        "Architecture Decisions": Path.wildcard("docs/adr/*.md"),
        Specifications: Path.wildcard("docs/spec/*.md"),
        Examples: ["examples/rian/README.md"]
      ],
      groups_for_modules: [
        "Front-end": [Rian.Decl, Rian.Pratt],
        "Checking & lowering": [
          Rian.Exhaustiveness,
          Rian.PatternLower,
          Rian.Capability,
          Rian.Lower
        ],
        Metaprogramming: [Rian.Macro, Rian.Comptime]
      ]
    ]
  end

  defp aliases do
    [
      # `mix examples` runs the end-to-end area/1 lowering demo through the
      # compiled app. Each driver in examples/*.exs is independently runnable
      # via `mix run`; the annotated source tour lives in examples/rian/.
      examples: ["run --no-start examples/lower_run.exs"],
      # `mix test.all` runs EVERYTHING incl. the external-toolchain tests
      # (kotlinc/rustc/node) that the default `mix test` excludes for speed.
      # CI runs this — it is the enforced gate (see test/test_helper.exs).
      "test.all": &test_all/1
    ]
  end

  # Run the full suite with the external-toolchain tags included. The exclude
  # policy lives in `test/test_helper.exs`, keyed off RIAN_TEST_ALL — this just
  # flips that switch, so the env var is the single source of truth. Forwards any
  # extra args (e.g. `mix test.all --cover`).
  defp test_all(args) do
    System.put_env("RIAN_TEST_ALL", "1")
    Mix.Task.run("test", args)
  end
end
