defmodule Rian.Pkg do
  @moduledoc """
  The native packaging layer (ADR-0082): one `rian.toml` → native-manifest generator,
  with a backend per target shaped like the emitters (`Beam`/`Lower`/`JS`/`JVM`,
  ADR-0050). A backend is a **pure, deterministic** function of the `Rian.Manifest` —
  same manifest in, byte-identical manifest out (sorted/fixed keys, pinned tool
  versions, no timestamps), so a generated project never churns git or busts the native
  cache (ADR-0082 invariant 2).

  The same backend feeds both delivery modes (ADR-0082): **PUSH** — `rian build` writes a
  self-contained native project under `_build/<target>/` — and (future) **PULL** — a
  native plugin embeds Rian in an existing project. They share the backend, so the two
  can never disagree.

  Implemented backends (ADR-0082 staging steps 1–4): `Rian.Pkg.Cargo` (Rust →
  `Cargo.toml`), `Rian.Pkg.Rebar` (BEAM → `rebar.config`), `Rian.Pkg.Gradle`
  (JVM/Kotlin → `build.gradle.kts`), and `Rian.Pkg.Npm` (ECMAScript → `package.json`).
  """
end
