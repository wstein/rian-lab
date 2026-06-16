defmodule Rian.ShowStdlib do
  @moduledoc false
  # The canonical `Show` stdlib module (ADR-0069 §6 — `${float}` interpolation),
  # parsed ONCE at compile time from the documented source and baked into the BEAM
  # as a literal. `Rian.Decl.inject_stdlib/1` injects it when a program interpolates
  # a `Float64` and does not already define its own `Show`.
  #
  # Compile-time evaluation replaces the former runtime `:persistent_term` memo:
  # no mutable global state, and the parse cost is paid once at build time rather
  # than on first use. (`Rian.Decl.parse/1` is pure, so it is safe to call here;
  # parsing the `Show` source is non-recursive — `inject_stdlib` is a no-op for a
  # program that already defines `Show`.) A compile-time dependency on `Rian.Decl`
  # only — `Decl` calls back at runtime, so there is no compile cycle.

  @path Path.join([__DIR__, "..", "..", "examples", "rian", "stdlib_show.rian"])
  @external_resource @path

  @module @path
          |> File.read!()
          |> Rian.Decl.parse()
          |> Map.fetch!(:mods)
          |> Enum.find(&(&1.name == "Show"))

  @doc "The parsed `Show` stdlib `%Rian.IR.Mod{}`, evaluated at compile time."
  @spec module() :: struct()
  def module, do: @module
end
