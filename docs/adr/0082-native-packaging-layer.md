# ADR-0082 — Native packaging layer: generate native build files from `rian.toml`

**Status:** Proposed
**Implemented:** partial — staging **steps 1–4 landed** (all four target backends) **+ step 5 begun** (the BEAM PULL plugin) **+ step 6** (`rian eject`). Step 1: `Rian.Pkg.Cargo` generates a deterministic `Cargo.toml`, and `rian build --rust -o ROOT` writes a self-contained crate under `ROOT/_build/rs/` with the `@external(:rs)` FFI wired into `src/`, gated by a `cargo build` test. Step 2: `Rian.Pkg.Rebar` generates `rebar.config` + an OTP `<app>.app.src` (the default Erlang-native BEAM flavor), and `rian build -o ROOT` packages an OTP app under `ROOT/_build/ex/` (`ebin/*.beam` incl. bundled `@external(:ex)` FFI via `Rian.External.lower_beam`), proven by loading+running the package and a `rebar3 compile` test (`@tag :rebar`). Step 3: `Rian.Pkg.Gradle` generates `build.gradle.kts` + `settings.gradle.kts` (Kotlin DSL, pinned plugin + JVM target), and `rian build --jvm -o ROOT` packages a Gradle project under `ROOT/_build/jvm/` (the emitted Kotlin + each `@external(:jvm)` `.ffi.kt` in `src/main/kotlin/`), verified by `kotlinc` (the JVM harness) and a real `gradle build` (`@tag :gradle`). Step 4: `Rian.Pkg.Npm` generates a deterministic ESM `package.json`, and `rian build --js -o ROOT` packages an npm package under `ROOT/_build/js/` (the emitted ESM + each `@external(:js)` `.ffi.mjs`), verified by `npm pack` + a `node` run (`@tag :js`). A non-empty `[deps]` (all backends) and a `kind="app"` Cargo/Gradle project fail closed (invariant 4). Step 5 (PULL, begun): `Mix.Tasks.Compile.Rian` — a Mix **compiler** (`compilers: [:rian]`) that builds a host Mix project's `.rian` via `Rian.Beam` during `mix compile` (the ADR-0026 §3 model, invariant 3), with parse/type errors as compiler diagnostics. Step 6: `rian eject <ex|rs|js|jvm> [-o DEST]` (`Rian.Build.eject`) promotes a generated `_build/<target>/` to a user-owned directory (moved out of `_build/`, which `rian build` regenerates) — the explicit one-way invariant-2 exception; fail-closed (the source must exist, the destination must be free). Tests: `Rian.Pkg.{CargoTest,RebarTest,GradleTest,NpmTest}`, `Mix.Tasks.Compile.RianTest`, `Rian.BuildTest`. The other PULL plugins (rebar3, a Cargo build-dependency, a Gradle plugin — separate-ecosystem packages), the opt-in `mix.exs` flavor, and `kind="app"` packaging remain. Closes (in part) the ADR-0026 "Hex/Cargo/npm metadata mapping from a Rian manifest" open item and the ADR-0080 §2 "packaging layer" / `[deps]` defer
**Refs:** ADR-0026 (ecosystem integration — rebar3 plugin + Mix compiler, no fork), ADR-0080 (project layout — `_build/<target>/`, the `rian.toml` manifest), ADR-0057/0058 (one source → a target *set*; portability inferred), ADR-0068/ADR-0080 §7 (`@external` foreign files), ADR-0000 (honesty bar), ADR-0050 (per-target emitter structure the generator mirrors)
**Owners:** Maya Lin (architecture) · Liam Davis (ecosystem) · Kira Neri (honesty/toolchain) · Elena Rostova (FFI) · Samir Patel (rigor) · Rachel Okafor (PM) · Arthur Pendelton (disambiguation)

## Context

Rian lowers one source to source-emitting targets — Rust (`Rian.Lower`), JVM/Kotlin
(`Rian.JVM`), ECMAScript (`Rian.JS`) — and to BEAM bytecode (`Rian.Beam`). Each of
those ecosystems has a **native build system** (Cargo, Gradle, npm, rebar3/Mix) that
owns dependency resolution, incremental compilation, caching, and IDE integration.
Today `rian build`/`mix rian.compile` emit only the *source* (and copy `@external`
foreign files beside it via `copy_foreign`, [build.ex](../../lib/rian/build.ex)); the
emitted code is not yet a buildable native project.

Two integration shapes were proposed (2026-06-18 design debate):

- **PUSH** — the Rian compile step *generates* the native build files (`Cargo.toml`,
  `rebar.config`/`mix.exs`, `build.gradle.kts`, `package.json`).
- **PULL** — compiling Rian → target language is a *pre-build step the native build
  system invokes* (a Cargo build-dependency, a Gradle codegen task, the rebar3/Mix
  compiler ADR-0026 §3 already commits to — the Gleam `rebar_gleam`/`mix_gleam` model).

The debate rejected picking one. PULL alone strands the greenfield "`rian build &&
./run`" path; PUSH alone strands the enterprise dropping Rian into an existing build
graph, and — taken naïvely — re-couples us to a host we deliberately decoupled from
(ADR-0080 chose `rian.toml`, "**not an executable `mix.exs`**"). It also tempts Rian
into *becoming* Cargo: owning three dependency resolvers and three lockfile formats.

The resolution is **one generator, two delivery modes, five invariants** — recorded
here because the codebase treats ADRs as authoritative and this one re-opens the
output layout, the FFI wiring, and the BEAM build-tool flavor.

## Decision

A single `rian.toml → native manifest` generator (`Rian.Pkg`, with per-target
backends mirroring the emitters) feeds **both** a PUSH front-end (`rian build` writes a
self-contained native project under `_build/<target>/`) and a PULL front-end (native
plugins call the same generator to embed Rian in an existing project). It is governed
by five invariants.

### Invariant 1 — One generator, one source of truth

`rian.toml [project]` is the **single source**; every native manifest is a pure,
deterministic function of it. `Rian.Pkg.Cargo`, `Rian.Pkg.Rebar` (+ optional
`Rian.Pkg.Mix`), `Rian.Pkg.Gradle`, `Rian.Pkg.Npm` are backends shaped like the
existing emitters (`Beam`/`Lower`/`JS`/`JVM`, ADR-0050). The PUSH and PULL front-ends
call the **same** backend, so a generated `_build/rs/Cargo.toml` and a plugin-driven
one can never disagree (Arthur's anti-ambiguity rule). The metadata mapping is
mechanical: `name` → package name (target-cased), `version` → semver, `license` →
SPDX, `authors` → the native author field, `kind` (`app`/`lib`) → bin-vs-lib crate /
application-vs-library shape.

### Invariant 2 — PUSH writes only `_build/<target>/`, never a user file

`rian build`/`mix rian.compile` regenerate a complete, deterministic native project
under `_build/<target>/` (ADR-0080 §1: "generated per-target output — gitignored,
never authored"). Because `_build/` is regenerated wholesale, **there is no "update"
problem — only overwrite**; the user's "create/update during compile" is satisfied by
deterministic regeneration, *not* by merging into a hand-written file. Rian never
writes a path the user authored. Determinism is mandatory: sorted keys, pinned
`edition`/`gradle`/`otp` versions, no timestamps or randomness — so the output never
churns git or busts the native cache.

### Invariant 3 — PULL ships as native plugins calling the same generator

For embedding Rian in an existing native project, ship the ADR-0026 §3 plugins — the
**Mix compiler + rebar3 plugin first** (precedented, half-specced), then a Cargo
build-dependency/`build.rs` and a Gradle codegen task. Each plugin invokes the **same**
`Rian.Pkg`/emitter path; it generates *source + wiring*, never a competing root
manifest. Here the user owns their `Cargo.toml`/`build.gradle`/`mix.exs` and adds
native dependencies the native way — which is also how PULL sidesteps the deps tarpit
(it *delegates* deps to the human instead of *promising* to resolve them).

### Invariant 4 — Nothing ships unless a real native build passes through it

A generated manifest is a **claim** ("this produces a working crate/app"); the honesty
bar (ADR-0000) forbids claims we don't prove. So a backend may only land with a
toolchain test that **builds through the generated manifest** — `cargo build`, `gradle
build`, `mix compile`/`rebar3 compile` on the generated project — tagged like the
existing `:rust`/`:jvm`/`:js` tests and run under `mix test.all`, never a string-snippet
compile. FFI wiring (Invariant 5) is part of that build. A non-empty `[deps]` with no
resolver built is a **loud error** (mirroring how `Rian.Reach` pins a target it can't
reach), never a silently dropped dependency.

### Invariant 5 — The generated manifest wires in `@external` foreign files

`@external(:rs|:jvm|:js, "./x.ffi.*", …)` (ADR-0080 §7) ships foreign source that must
be wired into the native build. The §7(b) emitters already wire it for a **single-file**
toolchain build (a Rust `#[path] mod`, an ESM `import`, a same-package JVM call; the BEAM
case via `Rian.External.lower_beam`) and `copy_foreign` drops the file beside the output —
enough for `rustc file.rs`, but not a real crate. Packaging **elevates** this into the
native project: the generated manifest/source-tree places and declares the foreign file
as a first-class module (a Rust `mod` under `src/`, a Gradle `sourceSet`, an npm export, a
`:ex` module on the load path). This wiring is generated in PUSH, documented for the user
in PULL, and is part of the Invariant-4 build test either way.

### The BEAM/"Elixir" flavor

Default the BEAM backend to **`rebar.config` (Erlang-native)** — it keeps ADR-0080's
host-decoupling ("not an executable `mix.exs`") and ADR-0026's first-class-Erlang
stance. Offer `mix.exs` generation as an **opt-in** for users embedding in an Elixir
project; do **not** make `mix.exs` the canonical BEAM output.

### `rian eject` — the one-way escape hatch

`rian eject <target>` promotes `_build/<target>/` into a **user-owned** native project
(no longer regenerated). It is the explicit, deliberate exit for anyone who outgrows
generation — real `[deps]`, custom build logic, workspace integration. After eject,
Rian is a codegen step (PULL) for that target, not the owner. This is the only path by
which Rian-generated content becomes a file the user maintains (Invariant 2's exception,
made explicit rather than implicit).

## Ratings

| Option | Rating | Note |
| --- | --- | --- |
| **P3** one generator, two modes (this ADR) | 5/5 | greenfield *and* embedding; one mapping, no drift |
| **P2** PULL-only (plugins) | 4/5 | honest, native idioms, but no zero-config greenfield |
| **P4** minimal + `eject` | 4/5 | folds in as the deps-era escape hatch (adopted) |
| **P1** PUSH-only, Rian owns the build | 2/5 | reinvents three package managers; untested-deps dishonesty |
| Generate `mix.exs` as the canonical BEAM manifest | 2/5 | re-couples to the Elixir host (reject; ADR-0080) |
| A Rian-owned `[deps]` resolver inside `rian build` | 1/5 | the tarpit ADR-0080 §2 explicitly defers (reject) |

## Staging (by adoption value)

1. **`Rian.Pkg` + Cargo backend** — dependency-free, FFI-wired, into `_build/rs/`,
   gated by a `cargo build` test. (Highest demo value; smallest honest slice; exercises
   the FFI rung.)
2. **BEAM backend** (`rebar.config` first) — cheapest, precedented; reuses
   `Rian.External.lower_beam`.
3. **Gradle backend** — long tail; reuse the JVM toolchain test harness.
4. **npm `package.json`** — trivial; land with Gradle.
5. **Plugins (PULL)** — Mix compiler + rebar3 first (ADR-0026 §3), then a Cargo
   build-dependency, then a Gradle plugin — each calling the same generator.
6. **`rian eject`** — once two backends exist and the shape is proven.

A prerequisite that lands with step 1: **restructure build output to `_build/<target>/`**
(today `emit_source` writes flat into `-o DIR`, [build.ex](../../lib/rian/build.ex)) —
aligning with ADR-0080 §1 and giving each target a real project root, which also fixes
the FFI-resolution fragility of `copy_foreign`. The restructure **rolls out per target
with its backend** (Rust under step 1; JS/JVM/BEAM with their steps), so a target without
a backend yet keeps the flat `-o`/stdout path until then.

## Consequences

- A new `Rian.Pkg` namespace parallels the emitters; the per-feature drift tax
  (CLAUDE.md) now extends to packaging, but only for backends that exist — non-emitted
  targets carry no packaging code.
- `rian build`'s output layout changes from flat `-o DIR` to `_build/<target>/`; the
  `-o` flag selects the root, the target subdir is implied. This rolls out per target with
  its backend — **all four targets are live** (`-o ROOT` → `ROOT/_build/{rs,ex,jvm,js}/`).
  Without `-o`, BEAM still writes flat `.beam` into the cwd and a source target prints to
  stdout (the quick compile/inspection paths).
- `mix test.all` gains real native-build steps (`cargo build`, `rebar3 compile`, `gradle
  build`, `npm pack`, …) — slower but the only honest signal (Invariant 4). These are
  `:rust`/`:jvm`/`:js`/`:rebar`/`:gradle` tagged, excluded from the fast inner loop like
  the existing toolchain tests.
- `Rian.Manifest` gains the project metadata the backends read; `[deps]` stays a
  **loud-error stub** until the resolver lands.

## Open items

- **`[deps]` resolver + `rian.lock`** (ADR-0026's standing open item). Two **kinds** of
  dependency, two sourcing paths — the distinction the "must not become Cargo" rule
  actually rests on:
  - **Native deps** (a Rust crate, a Hex package, an npm module) are **per-target** and
    are **delegated to the native build system** (PULL / `eject`); Rian never reimplements
    Cargo's/Hex's/npm's resolver (rated 1/5 above). They live in the native manifest the
    user owns, not in `rian.toml`.
  - **Rian-source deps** (another Rian package — portable, lowering to the *same* target
    set) inherently cannot be delegated to one native build system, so Rian must fetch
    them itself. The directive: **source them from online version-control repositories —
    git, fossil, mercurial, … — not a single centralized registry.** VCS sourcing is
    decentralized and registry-agnostic, which is the same host-decoupling stance that
    made the manifest `rian.toml` rather than `mix.exs` (ADR-0080) and rejected forking a
    host ecosystem (ADR-0026): no gatekeeper, the same source reachable for every target.
    Reproducibility (Samir's bar) comes from **commit-hash pinning in `rian.lock`**, not a
    registry's mutable version index. A registry, if ever added, is an *optional* index in
    front of VCS URLs, never the only way in.
  This split is the boundary where PUSH defers to PULL/`eject` (native deps) versus where
  Rian owns a *minimal, VCS-only* fetcher (Rian-source deps) — deliberately not a general
  package resolver.
- **`[workspace]`** (ADR-0080 open item) — multi-package repos; cargo-style.
- **Incremental/caching** — the strongest long-term argument for PULL; PUSH must not
  try to out-cache the native tools.
- **IDE integration** — a real generated `Cargo.toml`/`build.gradle.kts` is what makes
  rust-analyzer / IntelliJ light up on emitted code; track as an adoption lever, not a
  task yet.
