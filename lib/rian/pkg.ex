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

  Implemented backends: `Rian.Pkg.Cargo` (Rust, ADR-0082 staging step 1). The BEAM
  (`rebar.config`), Gradle, and npm backends are staged behind it.
  """
end
