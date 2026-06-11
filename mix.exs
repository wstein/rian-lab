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
      extras:
        ["README.md", "docs/README.md"] ++
          Path.wildcard("docs/adr/*.md") ++ Path.wildcard("docs/spec/*.md"),
      groups_for_extras: [
        Overview: ["README.md", "docs/README.md"],
        "Architecture Decisions": Path.wildcard("docs/adr/*.md"),
        Specifications: Path.wildcard("docs/spec/*.md")
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
      # `mix examples` runs every demonstration script through the compiled app.
      examples: ["run --no-start examples/lower_run.exs"]
    ]
  end
end
