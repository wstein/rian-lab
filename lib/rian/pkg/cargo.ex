defmodule Rian.Pkg.Cargo do
  @moduledoc """
  Cargo backend for the native packaging layer (ADR-0082, staging step 1): a pure,
  deterministic `Rian.Manifest` → `Cargo.toml` function plus the crate's source layout.

  `rian build --rust -o ROOT` writes a self-contained crate under `ROOT/_build/rs/`
  (`Cargo.toml` + `src/<root>.rs` + the `@external(:rs)` `.ffi.rs` files copied into
  `src/`, where the emitter's `#[path] mod` resolves them — ADR-0082 invariant 5). The
  same backend will feed the future PULL Cargo plugin (ADR-0082 §3).

  **Honesty (ADR-0000 / ADR-0082 invariant 4):** a generated `Cargo.toml` is a claim it
  builds, so the backend only lands with a `cargo build` test that builds through it
  (`Rian.BuildTest`). A non-empty `[deps]` raises — the resolver is not built, and a
  silently dropped dependency would be a false claim. `kind = "app"` (a `[[bin]]` crate)
  is not built yet: a Rian `main` is not a Rust `fn main()` without a wrapper, so it
  raises rather than emit a crate that won't compile.
  """

  use Rian.Ann
  alias Rian.Manifest

  # pinned, not derived — determinism (ADR-0082 invariant 2).
  @edition "2021"

  @doc """
  Generate the `Cargo.toml` for `manifest` (deterministic: fixed key order, pinned
  `edition`, no timestamps). Raises on a non-empty `[deps]` (no resolver — ADR-0082
  invariant 4) or `kind = "app"` (a bin crate needs a `main` wrapper — not yet built).
  """
  @rian_sig "pub def cargo_toml(m Manifest) String"
  @spec cargo_toml(Manifest.t()) :: String.t()
  def cargo_toml(%Manifest{} = m) do
    reject_unresolved_deps!(m)
    reject_bin!(m)

    [
      "[package]",
      ~s(name = "#{crate_name(m.name)}"),
      ~s(version = "#{m.version}"),
      ~s(edition = "#{@edition}"),
      license_line(m.license),
      authors_line(m.authors),
      "",
      "[lib]",
      ~s(name = "#{crate_name(m.name)}"),
      ~s(path = "#{root_rel(m)}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc "The crate's root source file, relative to the crate dir (`src/lib.rs`)."
  @rian_sig "pub def root_rel(m Manifest) String"
  @spec root_rel(Manifest.t()) :: String.t()
  def root_rel(%Manifest{}), do: "src/lib.rs"

  # Cargo crate identifiers use underscores; a snake_case Rian name already is one, but
  # a `-` (legal in a package name) is not legal in the `[lib] name`.
  defp crate_name(name), do: String.replace(name, "-", "_")

  defp license_line(nil), do: nil
  defp license_line(l), do: ~s(license = "#{l}")

  defp authors_line([]), do: nil

  defp authors_line(authors),
    do: "authors = [" <> Enum.map_join(authors, ", ", &~s("#{&1}")) <> "]"

  defp reject_unresolved_deps!(%Manifest{deps: deps}) when map_size(deps) > 0 do
    raise ArgumentError,
          "rian.toml `[deps]` lists #{map_size(deps)} dependenc#{plural(map_size(deps))} but the " <>
            "packaging layer has no resolver yet (ADR-0082 invariant 4) — vendor them via " <>
            "`@external`, or `rian eject` to manage Cargo deps natively"
  end

  defp reject_unresolved_deps!(_), do: :ok

  defp reject_bin!(%Manifest{kind: "app"}) do
    raise ArgumentError,
          "Cargo bin packaging (`kind = \"app\"`) is not yet built — a Rian `main` is not a Rust " <>
            "`fn main()` without a wrapper (ADR-0082 staging). Use `kind = \"lib\"` for now"
  end

  defp reject_bin!(_), do: :ok

  defp plural(1), do: "y"
  defp plural(_), do: "ies"
end
