defmodule Mix.Tasks.Compile.Rian do
  use Mix.Task.Compiler

  @moduledoc """
  A Mix **compiler** that builds a project's `.rian` sources during `mix compile` — the
  BEAM **PULL** plugin of the native packaging layer (ADR-0082 invariant 3, the ADR-0026
  §3 Mix-compiler model, like Gleam's `mix_gleam`). Unlike PUSH (`rian build`, which
  generates a whole project under `_build/<target>/`), this embeds Rian in an *existing*
  Mix project: the user owns their `mix.exs` and adds Rian as a compile step.

  Wire it in `mix.exs`:

      def project do
        [
          # …
          compilers: [:rian] ++ Mix.compilers(),
          rian_paths: ["src"]          # where the `.rian` sources live (default: ["src"])
        ]
      end

  Each `.rian` is compiled with the **same backend as everything else** (`Rian.Beam` →
  real `:compile.forms` bytecode, ADR-0082 invariant 1): a file of `mod` declarations
  emits one `Elixir.<Mod>.beam` each; a flat top-level file emits a module named after the
  file (`thing.rian` → `Thing`). The `.beam` land in the project's compile path beside its
  Elixir output, so they load and run with no extra step. A parse/type/reachability error
  becomes a compiler **diagnostic** (not a raised exception), the Mix-native shape.

  (No incremental manifest yet — every `mix compile` rebuilds every `.rian`; the
  caching story is an ADR-0082 open item. File-reference `@external` FFI in PULL is also
  a refinement: use a module reference `@external(:ex, Mod.fun)` to a module the host
  build already compiles.)
  """

  alias Mix.Task.Compiler.Diagnostic

  @impl Mix.Task.Compiler
  def run(_argv) do
    config = Mix.Project.config()
    # mix runs compilers with the CWD at the project root; source paths are relative to it.
    compile(config[:rian_paths] || ["src"], File.cwd!(), Mix.Project.compile_path(config))
  end

  @doc """
  The testable core: compile every `.rian` under `paths` (relative to `root`) to BEAM
  bytecode written into `dest`. Returns the `Mix.Task.Compiler` `{status, diagnostics}`
  pair — `:noop` when there are no sources, `:ok` when all compiled, `:error` with a
  diagnostic per failed file.
  """
  @spec compile([Path.t()], Path.t(), Path.t()) ::
          {:ok | :noop | :error, [Diagnostic.t()]}
  def compile(paths, root, dest) do
    File.mkdir_p!(dest)

    files =
      paths
      |> Enum.flat_map(fn p -> Path.wildcard(Path.join([root, p, "**", "*.rian"])) end)
      |> Enum.sort()

    diagnostics = files |> Enum.map(&compile_file(&1, dest)) |> Enum.reject(&(&1 == :ok))

    status =
      cond do
        diagnostics != [] -> :error
        files == [] -> :noop
        true -> :ok
      end

    {status, diagnostics}
  end

  defp compile_file(file, dest) do
    src = File.read!(file)
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)

    file
    |> beams_for(src, prog)
    |> Enum.each(fn {atom, bin} -> File.write!(Path.join(dest, "#{atom}.beam"), bin) end)

    :ok
  rescue
    e ->
      %Diagnostic{
        compiler_name: "rian",
        file: file,
        severity: :error,
        message: Exception.message(e),
        position: 0
      }
  end

  # a file of `mod`s → one `Elixir.<Mod>` each (`Rian.Beam.compile_program`); a flat file
  # → a single module named after the file (ADR-0080 §3 file↔module casing).
  defp beams_for(file, src, prog) do
    case prog do
      %{mods: [_ | _]} ->
        Rian.Beam.compile_program(src)

      _ ->
        mod = Module.concat([Macro.camelize(Path.basename(file, ".rian"))])
        {:ok, atom, bin} = Rian.Beam.compile(src, mod)
        [{atom, bin}]
    end
  end
end
