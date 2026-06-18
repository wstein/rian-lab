defmodule Rian.Build do
  use Rian.Ann

  @moduledoc """
  Toolchain-free build/inspect verbs for the `rian` escript (ADR-0026/0031): the
  same operations as `mix rian.compile`/`rian.targets` surfaced with no Elixir/mix
  on the host. Each `*/1` takes argv and returns an exit code (`Rian.CLI` halts on it).

    * `build/1`   — compile a `.rian` to BEAM `.beam` files (the backend a rebar3
      plugin shells out to), or print Rust/JS/JVM source.
    * `check/1`   — run the parse/type/exhaustiveness gates; exit 0 / non-zero.
    * `targets/1` — per-function target reachability (`Rian.Reach`); `--require` gates.
  """

  @doc """
  `rian build FILE [-o ROOT] [--rust|--js|--jvm]` — compile a `.rian`. With `-o ROOT`,
  PUSH-packages a native project under `ROOT/_build/<target>/` (ADR-0082): BEAM → an OTP
  app (`rebar.config` + `src/<app>.app.src` + `ebin/*.beam`), Rust → a Cargo crate; JS/JVM
  write their source plus any copied `@external` FFI into `ROOT` (their backends pending).
  Without `-o`, BEAM writes flat `.beam` into the cwd and a source target prints to stdout.
  Returns an exit code.
  """
  @spec build([String.t()]) :: non_neg_integer()
  def build(argv) do
    case OptionParser.parse(argv,
           strict: [out: :string, rust: :boolean, js: :boolean, jvm: :boolean],
           aliases: [o: :out]
         ) do
      {_opts, _, [_ | _] = bad} ->
        err("build: unknown option #{inspect(Enum.map(bad, &elem(&1, 0)))}")

      {opts, [file], _} ->
        case File.read(file) do
          {:ok, src} -> resolve_then_emit(opts, file, src)
          {:error, reason} -> err(error_text(reason))
        end

      {_opts, _, _} ->
        err("usage: rian build FILE [-o DIR] [--rust|--js|--jvm]")
    end
  end

  # Resolve every file-reference `@external` against the **project root** — the nearest
  # `rian.toml` dir, else the source's own dir (ADR-0080 §7 a/c): a missing foreign file
  # / absent export fails the build closed, never a silent stub. Anchoring on the root
  # makes a reference stable regardless of which entry inside the project is built. A
  # program with no file-references resolves trivially. Parse errors-as-values here.
  defp resolve_then_emit(opts, file, src) do
    src_dir = Rian.Manifest.root(Path.dirname(file))

    with {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.External.resolve(prog, src_dir) do
      emit(opts, file, src, prog, src_dir)
    else
      {:error, reason} -> err(error_text(reason))
    end
  end

  # The emit step is the one remaining boundary: a `--rust`/`--js`/`--jvm` lowering
  # (or BEAM codegen) can still raise on an unsupported construct or a gate failure
  # — converted to an exit code here rather than escaping the escript. Parse/IO
  # errors above are already values; this isolates the genuine emitter boundary.
  @rian_host "emit boundary: a lowering / BEAM codegen raise becomes an exit code"
  defp emit(opts, file, src, prog, src_dir) do
    cond do
      opts[:rust] ->
        # ADR-0082 step 1: `-o ROOT` generates a Cargo crate under ROOT/_build/rs/;
        # no `-o` keeps the flat stdout source-inspection path.
        case Keyword.get(opts, :out) do
          nil -> print(Rian.Lower.rust_program(Rian.Decl.parse(src)))
          root -> build_cargo(root, file, prog, src, src_dir)
        end

      opts[:js] ->
        # ADR-0082 step 4: `-o ROOT` generates an npm package under ROOT/_build/js/;
        # no `-o` keeps the flat stdout source-inspection path.
        case Keyword.get(opts, :out) do
          nil -> print(Rian.JS.compile(src))
          root -> build_npm(root, file, prog, src, src_dir)
        end

      opts[:jvm] ->
        # ADR-0082 step 3: `-o ROOT` generates a Gradle project under ROOT/_build/jvm/;
        # no `-o` keeps the flat stdout source-inspection path.
        case Keyword.get(opts, :out) do
          nil -> print(Rian.JVM.compile(src))
          root -> build_gradle(root, file, prog, src, src_dir)
        end

      true ->
        # ADR-0082 step 2: `-o ROOT` packages an OTP app under ROOT/_build/ex/
        # (rebar.config + src/<app>.app.src + ebin/*.beam); no `-o` writes flat `.beam`
        # into the cwd (the quick compile/run path).
        build_beam(opts, file, src, prog, src_dir)
    end
  rescue
    e -> err(Exception.message(e))
  end

  # `rian build --js -o ROOT` (ADR-0082 step 4): generate a self-contained npm package
  # under ROOT/_build/js/ — `package.json` from the manifest, the emitted ESM as
  # `<name>.mjs`, and each `@external(:js)` `.ffi.mjs` copied beside it (where the emitted
  # relative `import` resolves it, ADR-0082 invariant 5). Manifest generation runs first,
  # so a non-empty `[deps]` fails before any write.
  defp build_npm(root, file, prog, src, src_dir) do
    manifest = project_manifest(file, src_dir)
    main = Path.basename(file, ".rian") <> ".mjs"
    pkg = Rian.Pkg.Npm.package_json(manifest, main)
    js = Rian.JS.compile(src)

    proj = Path.join([root, "_build", "js"])
    File.mkdir_p!(proj)

    write_file(Path.join(proj, "package.json"), pkg)
    write_file(Path.join(proj, main), js)
    copy_foreign(prog, :js, src_dir, proj)
    0
  end

  # copy each distinct `.ffi.*` file the program references for `target` into `dir`,
  # preserving its basename (the co-located convention, ADR-0080 §7) so the emitted
  # relative `import`/`mod` finds it.
  defp copy_foreign(prog, target, src_dir, dir) do
    funcs = Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    paths =
      for f <- funcs,
          {^target, {:file, path, _fun}} <- Map.get(f, :externals, %{}),
          uniq: true,
          do: path

    Enum.each(paths, fn path ->
      dest = Path.join(dir, Path.basename(path))
      File.cp!(Path.expand(path, src_dir), dest)
      IO.puts(dest)
    end)
  end

  # `rian build --rust -o ROOT` (ADR-0082 step 1): generate a self-contained Cargo crate
  # under ROOT/_build/rs/ — `Cargo.toml` from the project manifest, the emitted Rust as
  # `src/lib.rs`, and each `@external(:rs)` `.ffi.rs` copied into `src/` (where the
  # emitter's `#[path] mod` resolves it, ADR-0082 invariant 5). `cargo_toml/1` fails
  # closed on a non-empty `[deps]` / a bin crate (invariant 4) — caught by `emit/5`.
  defp build_cargo(root, file, prog, src, src_dir) do
    manifest = project_manifest(file, src_dir)
    crate = Path.join([root, "_build", "rs"])
    src_out = Path.join(crate, "src")
    File.mkdir_p!(src_out)

    cargo = Path.join(crate, "Cargo.toml")
    File.write!(cargo, Rian.Pkg.Cargo.cargo_toml(manifest))
    IO.puts(cargo)

    lib = Path.join(crate, Rian.Pkg.Cargo.root_rel(manifest))
    File.write!(lib, Rian.Lower.rust_program(Rian.Decl.parse(src)))
    IO.puts(lib)

    copy_foreign(prog, :rs, src_dir, src_out)
    0
  end

  # `rian build --jvm -o ROOT` (ADR-0082 step 3): generate a self-contained Gradle/Kotlin
  # project under ROOT/_build/jvm/ — `settings.gradle.kts` + `build.gradle.kts` from the
  # manifest, the emitted Kotlin as `src/main/kotlin/<name>.kt`, and each `@external(:jvm)`
  # `.ffi.kt` copied into the same source set (invariant 5). Manifest generation runs
  # first, so a non-empty `[deps]` / a `kind="app"` project fails before any write.
  defp build_gradle(root, file, prog, src, src_dir) do
    manifest = project_manifest(file, src_dir)
    settings = Rian.Pkg.Gradle.settings_gradle(manifest)
    build = Rian.Pkg.Gradle.build_gradle(manifest)
    kotlin = Rian.JVM.compile(src)

    proj = Path.join([root, "_build", "jvm"])
    kt_dir = Path.join([proj, "src", "main", "kotlin"])
    File.mkdir_p!(kt_dir)

    write_file(Path.join(proj, "settings.gradle.kts"), settings)
    write_file(Path.join(proj, "build.gradle.kts"), build)
    write_file(Path.join(kt_dir, Path.basename(file, ".rian") <> ".kt"), kotlin)
    copy_foreign(prog, :jvm, src_dir, kt_dir)
    0
  end

  # the project manifest the packaging backend reads (ADR-0082 invariant 1: rian.toml is
  # the single source) — the project's `rian.toml` if present, else a synthesized `lib`
  # default named after the source file so a loose `.rian` still packages.
  defp project_manifest(file, src_dir) do
    case Rian.Manifest.read(Path.join(src_dir, "rian.toml")) do
      {:ok, m} -> m
      {:error, _} -> %Rian.Manifest{name: Path.basename(file, ".rian"), version: "0.0.0"}
    end
  end

  # Compile to BEAM, then either write flat `.beam` into the cwd (no `-o`, the quick
  # compile/run path) or package an OTP application under ROOT/_build/ex/ (`-o ROOT`,
  # ADR-0082 step 2). A `:ex` file-reference `@external` is bundled (ADR-0080 §7 b): the
  # foreign `.ffi.ex` is compiled and shipped as a real module beside the app.
  defp build_beam(opts, file, src, prog, src_dir) do
    case beam_modules(prog, src, src_dir) do
      {:error, msg} ->
        err(msg)

      {:ok, beams} ->
        case Keyword.get(opts, :out) do
          nil ->
            Enum.each(beams, &write_beam(&1, "."))
            0

          root ->
            build_otp(root, project_manifest(file, src_dir), beams)
        end
    end
  end

  # the `[{module_atom, beam_binary}]` for `prog`, bundling any `:ex` file-reference FFI.
  defp beam_modules(prog, src, src_dir) do
    if Rian.External.has_beam_file_ref?(prog) do
      case Rian.External.lower_beam(prog, src_dir) do
        {:error, _} = e -> e
        {:ok, lowered, ffi_beams} -> {:ok, compile_modules_ir(lowered) ++ ffi_beams}
      end
    else
      {:ok, compile_modules(src)}
    end
  end

  # package a self-contained OTP application (ADR-0082 step 2): `rebar.config` +
  # `src/<app>.app.src` (generated from the manifest, `Rian.Pkg.Rebar`) + the compiled
  # `ebin/*.beam`, all under ROOT/_build/ex/ — `rebar3 compile` builds straight through
  # it. Manifest-generation runs first, so a non-empty `[deps]` fails before any write.
  defp build_otp(root, manifest, beams) do
    rebar = Rian.Pkg.Rebar.rebar_config(manifest)
    appsrc = Rian.Pkg.Rebar.app_src(manifest, Enum.map(beams, &elem(&1, 0)))

    app = Path.join([root, "_build", "ex"])
    File.mkdir_p!(Path.join(app, "src"))
    File.mkdir_p!(Path.join(app, "ebin"))

    write_file(Path.join(app, "rebar.config"), rebar)
    write_file(Path.join([app, "src", "#{Rian.Pkg.Rebar.app_name(manifest)}.app.src"]), appsrc)

    Enum.each(beams, fn {atom, bin} ->
      write_file(Path.join([app, "ebin", "#{atom}.beam"]), bin)
    end)

    0
  end

  defp write_file(path, content) do
    File.write!(path, content)
    IO.puts(path)
  end

  defp write_beam({atom, bin}, dir) do
    path = Path.join(dir, "#{atom}.beam")
    File.write!(path, bin)
    IO.puts(path)
  end

  # mods-xor-flat, mirroring `mix rian.compile`'s BEAM path: a file of `mod`s gives
  # one `Elixir.<Mod>.beam` each; a flat top-level file gives one `Elixir.RianCompiled`.
  defp compile_modules(src) do
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)

    case prog do
      %{mods: [_ | _]} ->
        Rian.Beam.compile_program(src)

      _ ->
        {:ok, atom, bin} = Rian.Beam.compile(src, :"Elixir.RianCompiled")
        [{atom, bin}]
    end
  end

  # the IR twin of `compile_modules/1`, for the bundled path: a program whose
  # file-references have been lowered to module-references (`Rian.External.lower_beam/2`)
  # is compiled straight from IR, skipping a re-parse that would re-derive the file-refs.
  defp compile_modules_ir(prog) do
    :ok = Rian.Check.gate!(prog)
    :ok = Rian.Reach.gate!(prog)

    case prog do
      %{mods: [_ | _]} ->
        Rian.Beam.compile_program_ir(prog)

      _ ->
        {:ok, atom, bin} = Rian.Beam.compile_ir(prog, :"Elixir.RianCompiled")
        [{atom, bin}]
    end
  end

  @doc "`rian check FILE` — run the gates; print `ok` (exit 0) or the error (exit 1)."
  @spec check([String.t()]) :: non_neg_integer()
  def check([file]) do
    with {:ok, src} <- File.read(file),
         {:ok, prog} <- Rian.Decl.parse_result(src),
         :ok <- Rian.Check.check_program(prog) do
      IO.puts("#{file}: ok")
      0
    else
      {:error, reason} ->
        IO.puts(:stderr, "rian check: #{error_text(reason)}")
        1
    end
  end

  def check(_), do: err("usage: rian check FILE")

  @doc """
  `rian targets FILE [--require ex,rs,js]` — print per-function reachability. With
  `--require`, the listed targets are required: a function missing any is reported
  and the exit code is non-zero (the CI portability gate, toolchain-free).
  """
  @spec targets([String.t()]) :: non_neg_integer()
  def targets(argv) do
    case OptionParser.parse(argv, strict: [require: :string]) do
      {opts, [file], _} ->
        case File.read(file) do
          {:ok, src} -> targets_report(src, parse_required(opts[:require]))
          {:error, reason} -> err("targets: #{error_text(reason)}")
        end

      _ ->
        err("usage: rian targets FILE [--require ex,rs,js]")
    end
  end

  defp targets_report(src, required) do
    case Rian.Decl.parse_result(src) do
      {:error, msg} -> err("targets: #{msg}")
      {:ok, prog} -> targets_report(prog, required, Rian.Reach.analyze(prog))
    end
  end

  defp targets_report(_prog, required, report) do
    rows = Enum.sort_by(report, &elem(&1, 0))

    for {name, %{reach: reach}} <- rows do
      ts = Rian.Reach.targets() |> Enum.filter(&(&1 in reach)) |> Enum.map_join(",", &to_string/1)
      IO.puts("  #{name}: #{ts}")
    end

    missing =
      for {name, %{reach: reach}} <- rows,
          gap = required -- MapSet.to_list(reach),
          gap != [],
          do: {name, gap}

    case {required, missing} do
      {[], _} ->
        0

      {_, []} ->
        IO.puts("\nall functions reach #{inspect(required)} ✓")
        0

      {_, gaps} ->
        report_missing(gaps, required)
    end
  end

  defp report_missing(gaps, required) do
    IO.puts(:stderr, "\n#{length(gaps)} function(s) cannot reach #{inspect(required)}:")
    for {name, gap} <- gaps, do: IO.puts(:stderr, "  #{name} — missing #{inspect(gap)}")
    1
  end

  defp parse_required(nil), do: []

  defp parse_required(s),
    do: s |> String.split(",", trim: true) |> Enum.map(&String.to_atom(String.trim(&1)))

  defp print(text) do
    IO.puts(text)
    0
  end

  defp err(msg) when is_binary(msg) do
    IO.puts(:stderr, "rian: #{msg}")
    2
  end

  # render an error value for display: a gate/parse message is already a string; a
  # `File.read/1` failure is a posix atom, formatted via `:file.format_error/1`.
  defp error_text(msg) when is_binary(msg), do: msg
  defp error_text(posix), do: posix |> :file.format_error() |> List.to_string()
end
