defmodule Rian.Pkg.Npm do
  @moduledoc """
  npm backend for the native packaging layer (ADR-0082, staging step 4): a pure,
  deterministic `Rian.Manifest` → `package.json` generator.

  `rian build --js -o ROOT` writes a self-contained npm package under `ROOT/_build/js/`:
  `package.json` + the emitted ESM `<name>.mjs` + the TypeScript declaration sidecar
  `<name>.d.mts` (ADR-0086 §5) + each `@external(:js)` `.ffi.mjs` copied beside it (the
  emitted relative `import` already resolves it — ADR-0082 invariant 5).

  The `"types"` field points at the `.d.mts` sidecar (derived from `main` — an ESM
  `.mjs` resolves its declarations from `.d.mts`, not `.d.ts`), so a package-name
  import (`import … from "<name>"`) is typed by the consumer's `tsc`.

  The `package.json` is hand-built with a **fixed key order** (not a map encode, whose
  order is undefined) so the output is byte-deterministic (ADR-0082 invariant 2); it
  declares `"type": "module"` (the package is ESM). Unlike Cargo/Gradle, JS needs no
  `kind` split — a module just exports its functions, so both `app` and `lib` map to the
  same shape. A non-empty `[deps]` raises — no resolver (invariant 4).
  """

  use Rian.Ann
  alias Rian.Manifest

  @doc """
  Generate `package.json` for `manifest` with `main` as the package entry point
  (deterministic — fixed key order, no timestamps). Raises on a non-empty `[deps]`
  (no resolver yet — ADR-0082 invariant 4).
  """
  @rian_sig "pub def package_json(m Manifest, main String) String"
  @spec package_json(Manifest.t(), String.t()) :: String.t()
  def package_json(%Manifest{} = m, main) do
    reject_unresolved_deps!(m)

    fields =
      [{"name", m.name}, {"version", m.version}] ++
        license_field(m.license) ++
        [{"type", "module"}, {"main", main}, {"types", types_of(main)}]

    body = Enum.map_join(fields, ",\n", fn {k, v} -> ~s(  "#{esc(k)}": "#{esc(v)}") end)
    "{\n#{body}\n}\n"
  end

  defp license_field(nil), do: []
  defp license_field(l), do: [{"license", l}]

  # the declaration sidecar that types `main`: an ESM `.mjs` resolves its types from
  # the sibling `.d.mts` (ADR-0086 §5). A non-`.mjs` entry keeps its stem + `.d.mts`.
  defp types_of(main), do: (main |> Path.rootname(".mjs")) <> ".d.mts"

  # minimal JSON string escaping — the values are project names/versions/SPDX/filenames,
  # but escape `\` and `"` so a stray character can never produce invalid JSON.
  defp esc(s), do: s |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

  defp reject_unresolved_deps!(%Manifest{deps: deps}) when map_size(deps) > 0 do
    raise ArgumentError,
          "rian.toml `[deps]` lists #{map_size(deps)} dependenc#{plural(map_size(deps))} but the " <>
            "packaging layer has no resolver yet (ADR-0082 invariant 4) — add them to " <>
            "`package.json` after `rian eject`, or vendor via `@external`"
  end

  defp reject_unresolved_deps!(_), do: :ok

  defp plural(1), do: "y"
  defp plural(_), do: "ies"
end
