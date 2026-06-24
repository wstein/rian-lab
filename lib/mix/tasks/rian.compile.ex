defmodule Mix.Tasks.Rian.Compile do
  @shortdoc "Compile a .rian source file to BEAM bytecode and/or Rust/JS/JVM source"

  @moduledoc """
  Compile a Rian source file (Stage 0.1 declaration surface) for each top-level
  function and module.

      mix rian.compile FILE [--beam | --rust | --js | --jvm] [--show-elixir] [--no-fold]

  The two **real** targets are emitted by default:

    * **BEAM** — compiled to loadable bytecode through the Erlang abstract-forms
      backend (`Rian.Beam`, the canonical BEAM path); the task reports each
      module, its exports, and its `.beam` byte size. Erlang FFI (`:lists.sum`,
      `String.upcase`) is permitted — it lowers to native remote calls.
    * **Rust** — emitted as idiomatic source text (`Rian.Lower`).

  Options:

    * `--beam`         BEAM bytecode only
    * `--rust`         Rust source only
    * `--js`           ECMAScript source only (`Rian.JS`, ADR-0049 Tier 1) — run it
                       with `node`: `mix rian.compile FILE --js > out.mjs && node out.mjs`
    * `--jvm`          Kotlin/JVM source only (`Rian.JVM`, ADR-0049 Tier 2)
    * `--show-elixir`  *additionally* print the Elixir-text **debug** view
                       (`Rian.Lower`'s text emitter — a pedagogical artifact, not
                       the execution path; BEAM runs from bytecode, not this text)
    * `--no-fold`      skip automatic constant folding (ADR-0046) — keep the emitted
                       source faithful to what you wrote, for debugging/stepping

  Exits non-zero on a parse, exhaustiveness, or type-check error.

      mix rian.compile examples/area.rian
      mix rian.compile examples/rian/05_modules.rian --rust
      mix rian.compile examples/rian/08_lambdas_collections.rian --beam --show-elixir
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} =
      OptionParser.parse(args,
        strict: [
          beam: :boolean,
          rust: :boolean,
          js: :boolean,
          jvm: :boolean,
          show_elixir: :boolean,
          no_fold: :boolean
        ]
      )

    if invalid != [],
      do: Mix.raise("unknown option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")

    # `--no-fold` (ADR-0046): keep emitted source faithful to what you wrote — skip automatic
    # constant folding — for debugging/stepping. Scoped to this build invocation.
    if Keyword.get(opts, :no_fold, false), do: Application.put_env(:rian, :comptime_fold, false)

    file =
      case argv do
        [f] -> f
        [] -> Mix.raise("usage: mix rian.compile FILE [--beam | --rust] [--show-elixir]")
        _ -> Mix.raise("compile one file at a time")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    # ensure the project (and Rian.*) is compiled before we call into it
    Mix.Task.run("compile")
    # honor the project's `rian.toml` targets (ADR-0080 §2), scoped to this build
    Rian.Manifest.with_project(Path.dirname(file), fn -> compile_and_print(file, opts) end)
  end

  defp compile_and_print(file, opts) do
    src = File.read!(file)
    show = targets(opts)

    Mix.shell().info("# #{file}\n")

    if :beam in show, do: print_beam(src)
    if :rust in show, do: print_rust(src)
    if :js in show, do: print_js(src)
    if :jvm in show, do: print_jvm(src)
    if :elixir in show, do: print_elixir_debug(src)
  rescue
    e in [Rian.Decl.Error, Rian.Check.Error, Rian.Reach.Error, ArgumentError, RuntimeError] ->
      Mix.raise("#{file}: #{Exception.message(e)}")
  end

  # ── BEAM: the canonical path — real bytecode via `Rian.Beam` ─────────────
  defp print_beam(src) do
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)

    mods =
      case prog do
        %{mods: [_ | _]} -> Rian.Beam.compile_program(src)
        _ -> [single_module(src)]
      end

    Mix.shell().info("══ BEAM bytecode (Rian.Beam → :compile.forms) ══")

    Enum.each(mods, fn {atom, bin} ->
      Mix.shell().info("  #{atom}  —  #{byte_size(bin)} bytes  ·  exports #{exports(bin)}")
    end)

    Mix.shell().info("")
  end

  defp single_module(src) do
    {:ok, atom, bin} = Rian.Beam.compile(src, :"Elixir.RianCompiled")
    {atom, bin}
  end

  # read the `-export([...])` chunk back from the produced bytecode so the report
  # reflects what actually compiled, not what we intended to compile.
  defp exports(bin) do
    {:ok, {_mod, [{:exports, exps}]}} = :beam_lib.chunks(bin, [:exports])

    exps
    |> Enum.reject(fn {name, _a} -> name in [:module_info] end)
    |> Enum.map_join(", ", fn {name, a} -> "#{name}/#{a}" end)
  end

  # ── Rust: the real text target ───────────────────────────────────────────
  defp print_rust(src) do
    Rian.Decl.compile(src)
    |> Enum.each(fn {name, out} ->
      if out[:rust] do
        Mix.shell().info("══ #{name} — Rust ══\n#{out.rust}\n")
      end
    end)
  end

  # ── JS: ECMAScript source via `Rian.JS` (ADR-0049 Tier 1) — one whole module ──
  defp print_js(src) do
    Mix.shell().info("══ JavaScript (ECMAScript) ══\n#{Rian.JS.compile(src)}\n")
  end

  # ── JVM: Kotlin source via `Rian.JVM` (ADR-0049 Tier 2) ──────────────────
  defp print_jvm(src) do
    Mix.shell().info("══ JVM (Kotlin) ══\n#{Rian.JVM.compile(src)}\n")
  end

  # ── Elixir: the demoted debug view (text emitter, not the run path) ──────
  defp print_elixir_debug(src) do
    Mix.shell().info("══ Elixir (DEBUG text view — not the execution path) ══\n")

    Rian.Decl.compile(src)
    |> Enum.each(fn {name, out} ->
      if out[:elixir] do
        Mix.shell().info("── #{name} ──\n#{out.elixir}\n")
      end
    end)
  end

  # default shows both real targets; an explicit `--beam`/`--rust` narrows them.
  # `--show-elixir` is additive: it appends the debug Elixir text either way.
  defp targets(opts) do
    base =
      cond do
        opts[:js] -> [:js]
        opts[:jvm] -> [:jvm]
        opts[:beam] && opts[:rust] -> [:beam, :rust]
        opts[:beam] -> [:beam]
        opts[:rust] -> [:rust]
        true -> [:beam, :rust]
      end

    if opts[:show_elixir], do: base ++ [:elixir], else: base
  end
end
