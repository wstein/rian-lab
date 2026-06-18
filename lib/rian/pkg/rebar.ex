defmodule Rian.Pkg.Rebar do
  @moduledoc """
  BEAM backend for the native packaging layer (ADR-0082, staging step 2): a pure,
  deterministic `Rian.Manifest` → `rebar.config` + OTP `<app>.app.src` generator.

  `rebar.config` is the **default** BEAM flavor (Erlang-native, keeping ADR-0080's
  host-decoupling — *not* an executable `mix.exs`, which is an opt-in for a later step).
  `rian build -o ROOT` writes a self-contained OTP application under `ROOT/_build/ex/`:
  `rebar.config` + `src/<app>.app.src` + the Rian-compiled `ebin/*.beam` (the FFI is
  already a real module via `Rian.External.lower_beam`, ADR-0082 invariant 5). `rebar3
  compile` builds straight through it — prebuilt beams in `ebin/` are accepted.

  **Honesty (ADR-0082 invariant 4):** a non-empty `[deps]` raises — no resolver is built,
  and a silently dropped dependency would be a false claim.
  """

  use Rian.Ann
  alias Rian.Manifest

  @doc """
  Generate `rebar.config` for `manifest` (deterministic — fixed contents, no timestamps).
  Raises on a non-empty `[deps]` (no resolver yet — ADR-0082 invariant 4).
  """
  @rian_sig "pub def rebar_config(m Manifest) String"
  @spec rebar_config(Manifest.t()) :: String.t()
  def rebar_config(%Manifest{} = m) do
    reject_unresolved_deps!(m)
    "{erl_opts, [debug_info]}.\n{deps, []}.\n"
  end

  @doc """
  Generate the OTP application resource `<app>.app.src` for `manifest`, listing the
  Rian-compiled `modules` (their BEAM module atoms). Deterministic in `modules` order.
  """
  @rian_sig "pub def app_src(m Manifest, modules Vec(Symbol)) String"
  @spec app_src(Manifest.t(), [atom()]) :: String.t()
  def app_src(%Manifest{} = m, modules) do
    """
    {application, #{app_name(m)},
     [{description, "#{m.name}"},
      {vsn, "#{m.version}"},
      {registered, []},
      {applications, [kernel, stdlib]},
      {modules, [#{Enum.map_join(modules, ", ", &erl_atom/1)}]},
      {env, []}]}.
    """
  end

  @doc "The OTP application name (the project name, hyphens → underscores for a valid atom)."
  @rian_sig "pub def app_name(m Manifest) String"
  @spec app_name(Manifest.t()) :: String.t()
  def app_name(%Manifest{name: name}), do: String.replace(name, "-", "_")

  # an Erlang quoted atom — a BEAM module atom (`Elixir.Foo`) carries dots/case that
  # require quoting in `.app.src` term syntax.
  defp erl_atom(atom), do: "'#{atom}'"

  defp reject_unresolved_deps!(%Manifest{deps: deps}) when map_size(deps) > 0 do
    raise ArgumentError,
          "rian.toml `[deps]` lists #{map_size(deps)} dependenc#{plural(map_size(deps))} but the " <>
            "packaging layer has no resolver yet (ADR-0082 invariant 4) — add them to `rebar.config` " <>
            "after `rian eject`, or vendor via `@external`"
  end

  defp reject_unresolved_deps!(_), do: :ok

  defp plural(1), do: "y"
  defp plural(_), do: "ies"
end
