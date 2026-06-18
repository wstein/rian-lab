# ADR-0080 — Standard project layout, `rian new` skeleton, and editor/tool config

**Status:** Proposed (direction) · not yet implemented — this ADR fixes the **one canonical project
shape** and the manifest, so every Rian project looks the same and the future `rian new` has a single
template to emit. It resolves the long-standing "Rian manifest" open item in ADR-0026/ADR-0031.
**Implemented:** partial — the **`rian.toml` reader** is built (`Rian.Manifest`, §2: parse + validate
`[project]`/`[deps]`/`[lint]`; `Rian.Reach.build_default` reads its `targets`; `test/rian/manifest_test.exs`),
as **Phase 1 of the build system** (the foreign-file pipeline that unblocks ADR-0068 §7 / inline-string
removal, then `rian build`/bundle/package, then `rian new`, build on it). Still **not** built: `rian new`,
per-target foreign-file resolve/bundle (§7), and the Mix-compiler/Hex mapping. The layout below is the
contract those remaining tools implement.
**Refs:** ADR-0026 (BEAM ecosystem / Hex / rebar3+mix — the manifest open item this closes), ADR-0031
(bootstrap: self-contained `rian` escript ships these commands; manifest-schema open item), ADR-0045
(formatter — **zero-config**, so there is *no* formatter config file by design), ADR-0077 (linter —
the only style knobs live here, advisory), ADR-0058 (configurable target environments — the manifest's
`targets` set), ADR-0060 (spec-by-example — what lives under `test/`), ADR-0034/0033 (casing: file ↔
module name), ADR-0035 (one obvious way — the same discipline applied to project structure)
**Owners:** Kira Neri (toolchain / `rian new` / CI) · Liam Davis (conventions / ecosystem) · Maya Lin
(architecture / manifest schema) · Rachel Okafor (PM)

## Context

Rian has a formatter (ADR-0045), a linter (ADR-0077), a target model (ADR-0041/0058), and a packaging
direction (ADR-0026/0031) — but **no decision on what a Rian project looks like on disk**. There is no
manifest format, no `src/`↔`test/` convention, no starter template, and nothing that tells an editor or
a sibling toolchain how Rian source is laid out. ADR-0026 and ADR-0031 both list "a Rian manifest
(app/version/deps → Hex metadata)" as an *open item* and stop there.

Family and adjacent languages all converge on the same answer, and they win adoption partly *because*
of it: `cargo new` → `Cargo.toml` + `src/`, `mix new` → `mix.exs` + `lib/`+`test/`, `gleam new` →
`gleam.toml` + `src/`+`test/`. A young language that ships **one** project shape ends structure
bikeshedding before it starts — the same "one obvious way" discipline (ADR-0035) the formatter applied
to layout, now applied to the *project*.

The governing question, exactly as for the formatter, is **how much is configurable**. The answer is
the same: **the structure and the formatter are fixed; only genuinely per-project facts (name, version,
deps, target set, lint severity) are configurable**, and they live in one manifest.

## Decision

### 1. One canonical layout (the `cargo`/`gleam` model)

A Rian project is exactly this tree. `rian new <name>` emits it; tools assume it.

```
my_app/
├── rian.toml             # manifest — the single source of project metadata (§2)
├── README.md             # human entry point (title, one-liner, build/run, targets)
├── LICENSE               # SPDX-identified; default Apache-2.0 (matches the corpus)
├── AGENTS.md             # canonical agent/contributor guidance (§5); CLAUDE.md is a pointer to it
├── .editorconfig         # mirrors the canonical formatter style for non-Rian files/editors (§4)
├── .gitignore            # ignores _build/ and target output (§4)
├── src/
│   └── my_app.rian       # root module `MyApp` (file name ↔ module name, §3)
├── test/
│   └── my_app_test.rian  # spec-by-example (ADR-0060)
└── _build/               # generated per-target output — gitignored, never authored
    ├── ex/  rs/  js/  …  # one subdir per emitted target
```

- **`src/` holds authored Rian; `test/` holds spec-by-example; `_build/` is generated.** Generated code
  is never committed and never hand-edited (it is the emitters' output, ADR-0050).
- **Library vs application is a manifest fact, not a different tree** (§2 `kind`). An application adds a
  `pub def main()` entry in its root module; a library omits it. The directory shape is identical — the
  one-shape rule holds.
- **`examples/`** (optional) and **`bench/`** (optional) are reserved sibling dirs with the obvious
  meaning; `rian new` does not create them but tools recognize them.

### 2. The manifest: `rian.toml` (resolves the ADR-0026/0031 open item)

The manifest is **TOML** (declarative, diffable, the `Cargo`/`gleam` choice — *not* an executable
`mix.exs`, which would couple every project to the Elixir host the language is trying to outgrow). It is
the **single source** of project metadata; tools read it, never infer from the tree.

```toml
[project]
name    = "my_app"          # snake_case; root module is its PascalCase (MyApp)
version = "0.1.0"           # semver → Hex/Cargo/npm metadata (ADR-0026)
kind    = "app"             # "app" (has main) | "lib"
license = "Apache-2.0"      # SPDX
authors = ["Ada Lovelace <ada@example.com>"]

# The target set this project commits to building+verifying (ADR-0058).
# Reach (ADR-0057/0058) gates every function against exactly this set — the
# matrix stays honest because the project declares its ambition here.
targets = ["ex", "rs", "js"]

[deps]
# name = "version"  — mapped to Hex/Cargo/npm per target by the packaging layer (ADR-0026)

[lint]                      # the ONLY style knobs (ADR-0077); omit for defaults
# max_severity = "warn"     # CI gate threshold; default: advisory-only (no gate)
# allow = ["deep-nesting"]  # silence a lint by id
```

- **`targets` is the project's portability contract.** It feeds `Rian.Reach` (ADR-0058): a function
  that can't reach a declared target is an error, not a silent drop — the honesty bar (ADR-0000).
- **No formatter section exists, by design** (§4). The manifest carries only what is genuinely
  per-project.

### 3. File ↔ module naming

- **One root module per project**, named the **PascalCase** of `project.name` (`my_app` → `MyApp`),
  living in `src/<name>.rian`. Submodules live in `src/<name>/<sub>.rian` as `MyApp.Sub`. This is the
  Elixir/Gleam path↔module convention and the casing rule of ADR-0033/0034 (snake_case files,
  PascalCase modules).
- **`.rian` is the only source extension.** Test files end `_test.rian` (ADR-0060).

### 4. Editor & tool config — fixed, minimal, and *not* a formatter knob

The formatter is **zero-config** (ADR-0045): there is **no** `.rianfmt`, no `[format]` table, no style
file — a project cannot reconfigure the canonical style, and that is the whole point. What the skeleton
*does* ship is config that helps **non-Rian tools** match that one style:

- **`.editorconfig`** — mirrors the formatter's fixed rules so editors lay out *sibling* files
  (`rian.toml`, `.md`, future `.rs`/`.js` you read alongside generated output) consistently, and so an
  editor's default behavior matches before the formatter runs:

  ```ini
  root = true

  [*]
  charset = utf-8
  end_of_line = lf
  insert_final_newline = true
  trim_trailing_whitespace = true
  indent_style = space
  indent_size = 2

  [*.rian]
  max_line_length = 98          # the formatter's fixed budget (ADR-0045)

  [*.md]
  trim_trailing_whitespace = false   # trailing 2-space = hard break in Markdown
  ```

  `.editorconfig` is a *convenience that agrees with* `mix rian.format`; the formatter remains the
  canonical authority and the CI gate (`mix rian.format --check`). They never conflict because the
  `.editorconfig` only encodes rules the formatter already enforces.

- **`.gitignore`** — ignores generated output and local cruft:

  ```gitignore
  /_build/
  *.beam
  erl_crash.dump
  .DS_Store
  ```

- **Linter config** — lives in the manifest's `[lint]` table (§2), **not** a separate dotfile. It is
  advisory (ADR-0077); the default is no gate. This keeps every per-project knob in one file.

### 5. Skeleton contents (`rian new` emits these)

- **`src/my_app.rian`** — a runnable hello-world for an app (`kind = "app"`):

  ```rian
  mod MyApp do
    # Pure, portable greeting — reaches every target in `rian.toml` (ADR-0069 interpolation).
    pub def greet(name String) String :=
      "Hello, ${name}!"

    # Entry point. `IO.puts` is host FFI → pins `main` to :ex (ADR-0068/0057); the
    # portable logic above stays target-agnostic. A lib skeleton omits `main`.
    pub def main() :=
      IO.puts(greet("world"))
  end
  ```

- **`test/my_app_test.rian`** — one spec-by-example (ADR-0060), value-returning, no Gherkin:

  ```rian
  mod MyAppTest do
    use MyApp.(greet)

    pub def test_greet() := assert(greet("Rian") == "Hello, Rian!")
  end
  ```

- **`README.md`** — title, one-line description, `rian build`/`rian test`/`rian run`, and the declared
  `targets`. **`LICENSE`** — Apache-2.0 text by default (the corpus license), SPDX-tagged.
- **`AGENTS.md`** is the canonical, **vendor-neutral** agent/contributor guidance file (build commands,
  the ADRs-are-truth rule, the format/lint gates). **`CLAUDE.md`** ships as a one-line pointer
  (`See [AGENTS.md](AGENTS.md).`) so Claude Code and any other tool find the same single source — no
  drift between per-tool copies.

### 6. `rian new` and the command surface (future)

`rian new <name> [--lib] [--license SPDX] [--targets ex,rs,js]` emits §1 with §5 filled from the flags.
It ships in the self-contained `rian` escript (ADR-0031) alongside `rian fmt` (ADR-0045) and the future
`rian build`/`test`/`run`, which all read `rian.toml`. The Mix-compiler / Hex mapping (ADR-0026) reads
the **same** manifest, so a Rian project drops into an Elixir umbrella without a second metadata file.

### 7. Foreign-FFI file layout & bundling (the home for `@external` references — ADR-0068 §1b)

`@external`'s **reference** form (`@external(:js, "./ffi.mjs", "fun")`, ADR-0068 §1b) needs foreign code
to live in real, per-target files this layout defines. **Resolution + BEAM bundling implemented** —
`rian build` resolves each file-reference and fails closed (a + c below) and bundles a BEAM `.ffi.ex`
into the app (b); JS/Rust/JVM bundling is the remaining phase before inline-string specs can be removed.

- **Location — co-located, target-suffixed (the Gleam convention).** A foreign file sits beside the
  `.rian` that references it, named by the module + target: for `src/codec.rian`,
  - `src/codec.ffi.ex` (BEAM/Erlang), `src/codec.ffi.mjs` (ECMAScript), `src/codec.ffi.rs` (Rust),
    `src/codec.ffi.kt` (Kotlin/JVM).
  - A `@external(:ex, Mod.fun)` reference to an *existing host module* (e.g. `:erlang.binary_to_list`,
    `Rian.Beam.load_result`) needs **no** file — it names a module already on the host path. The `.ffi.*`
    files are for **authored** foreign code (the `@external(:js, "./codec.ffi.mjs", "encode")` form).
- **Build responsibilities (`rian build`).** Per target, the build (a) **resolves** each file-reference
  (the file exists, exports the named function) — extending the §1b boundary check from host-loadable
  modules to authored files; (b) **bundles** the foreign file into the target output (BEAM: compile
  `.ffi.ex` into the app; JS: copy/bundle `.ffi.mjs` and emit a relative `import`; Rust: include the
  `.ffi.rs` as a module; JVM: compile `.ffi.kt`); (c) **fails closed** if a referenced file/function is
  missing (ADR-0041 §2 — never a silent stub).
  - **(a) + (c) are implemented** (`Rian.External.resolve/2`, wired into `Rian.Build.build/1`): each
    file-reference resolves against the source's directory, a `.ex`/`.exs` is verified to define the
    named function at the Rian def's arity (from its AST), and a missing file/export fails the build.
    Other targets (`.mjs`/`.rs`/`.kt`) are existence-checked only — export verification lands with each
    backend's bundler. **(b) is implemented for BEAM** (`Rian.External.lower_beam/2`): the build compiles
    the `.ffi.ex`, rewrites the `@external` to a module-reference, and writes the foreign `.beam` beside
    the app, so the call lowers via the existing reference path. **JS/Rust/JVM bundling is the next
    phase** (a JS `import`, a Rust `mod`, a JVM compile); until then an emitter refuses a non-BEAM
    file-reference (`Rian.External.render/2` raises) rather than emit a call to unbundled code.
- **Packaging.** `rian.toml` (§2) lists the foreign files so a published package ships them. A Hex
  package carries `.ffi.ex`; a package that also targets JS/Rust ships those `.ffi.*` too (consumers on
  a target without the matching file get an honest Reach pin off it, not a runtime failure).

`@external` supports the **inline-string** spec (all targets) and the **host-module reference**
(`Mod.fun`/`:erlang.fun`, no foreign file needed); the **file-reference** form is parsed, **resolved**,
and **bundled for BEAM** at build time, with **JS/Rust/JVM bundling** the remaining §7 phase
(ADR-0068 §1b).

## Ratings

| Decision | Rating |
|---|---|
| One canonical layout, `src/`+`test/`+`_build/` (cargo/gleam model) | 5/5 |
| `rian.toml` (declarative TOML), not an executable `mix.exs` — decouples from the host | 5/5 |
| `targets` in the manifest as the project portability contract feeding Reach (ADR-0058) | 5/5 |
| File↔module casing convention (ADR-0033/0034) | 5/5 |
| `.editorconfig` that *mirrors* (never overrides) the zero-config formatter | 4/5 |
| Lint knobs in `[lint]`, not a dotfile; formatter has no config at all | 5/5 |
| `AGENTS.md` canonical + `CLAUDE.md` pointer (one source, vendor-neutral) | 4/5 |
| A separate `[format]`/`.rianfmt` style file | 1/5 (rejected — breaks ADR-0045's whole-ecosystem one-style guarantee) |
| Library and application as different trees | 2/5 (rejected — `kind` is one manifest line; one shape) |

## Consequences

- **Closes the ADR-0026/ADR-0031 manifest open item** with a concrete schema both the packaging layer
  and `rian new` implement; Hex/Cargo/npm metadata is a mechanical mapping from `[project]`.
- **The target set becomes a first-class, declared contract** (ADR-0058): Reach gates against
  `rian.toml`'s `targets`, so "what should this build for?" has one honest answer per project.
- **The repo itself is not retrofitted.** RianLab is the *compiler* (a Mix project), not a generated
  Rian *project* — it keeps `mix.exs`/`lib/`. This ADR governs **user** projects and the `examples/`
  tour; it does not impose `rian.toml` on the compiler's own tree.
- **No new gates today.** Nothing here is wired until `rian new` / the manifest reader land; the ADR is
  the contract they target.

## Open items

- **Dependency resolution & lockfile** — `[deps]` semantics (per-target source: Hex vs Cargo vs npm)
  and whether a `rian.lock` is needed are deferred to the packaging work (ADR-0026); this ADR fixes only
  the manifest's *shape*.
- **Multi-package workspaces** — a `[workspace]` table (cargo-style) for a repo of several Rian packages
  is out of scope for v1; single-package is the committed shape.
- **`_build/` layout per target** — the exact subdir naming and artifact placement track the emitters
  (ADR-0050/0049) and the `rian build` command, not yet built.
- **License default** — Apache-2.0 matches the corpus; revisit if the project picks a different OSS
  license before 1.0.
