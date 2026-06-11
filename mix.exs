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

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # ExDoc groups the design corpus alongside the reference modules.
  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      # Explicit slugs/titles for the same-named READMEs so they do not collide
      # (root README.md keeps the `readme` slug that `main: "readme"` resolves to).
      extras:
        [
          "README.md",
          {"docs/README.md", filename: "design-corpus", title: "Design Corpus"},
          {"examples/rian/README.md", filename: "rian-by-example", title: "Rian by Example"}
        ] ++
          Path.wildcard("docs/adr/*.md") ++ Path.wildcard("docs/spec/*.md"),
      groups_for_extras: [
        Overview: ["README.md", "docs/README.md"],
        "Architecture Decisions": Path.wildcard("docs/adr/*.md"),
        Specifications: Path.wildcard("docs/spec/*.md"),
        Examples: ["examples/rian/README.md"]
      ],
      groups_for_modules: [
        "Front-end": [Rian.Pratt],
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
      examples: ["run --no-start examples/lower_run.exs"]
    ]
  end
end
