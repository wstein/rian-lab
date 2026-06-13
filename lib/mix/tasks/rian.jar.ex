defmodule Mix.Tasks.Rian.Jar do
  @shortdoc "Assemble a .rian file into a runnable JVM .jar (Kotlin, ADR-0049 Tier 2)"

  @moduledoc """
  Build a Rian source file into a JVM `.jar` — the **rung-B** JVM path (ADR-0062):
  emit Kotlin (`Rian.JVM`) and assemble it with `kotlinc -include-runtime`. A real,
  runnable artifact, but via the host Kotlin compiler — a transpile step, not yet
  direct bytecode (rung C, the analog of `Rian.Beam`'s abstract forms).

      mix rian.jar FILE [-o OUT.jar] [--main FUNC]

    * `-o`/`--output`  the jar path (default: the source basename + `.jar`)
    * `--main FUNC`    wrap a **zero-arg** function in a generated `fun main()` so
                       the jar runs with `java -jar OUT.jar`; omit for a library jar
                       whose top-level functions are callable as `<File>Kt.fn(…)`

  Requires `kotlinc` (and `java` to run the result) on `PATH`. Exits non-zero on a
  parse/type/reachability error, an unsupported construct, or a `kotlinc` failure.

      mix rian.jar examples/rian/selfhost_opt.rian -o opt.jar
      mix rian.jar calc.rian --main answer && java -jar calc.jar
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args, strict: [output: :string, main: :string], aliases: [o: :output])

    file =
      case argv do
        [f] -> f
        [] -> Mix.raise("usage: mix rian.jar FILE [-o OUT.jar] [--main FUNC]")
        _ -> Mix.raise("build one file at a time")
      end

    if not File.exists?(file), do: Mix.raise("no such file: #{file}")

    Mix.Task.run("compile")
    src = File.read!(file)
    prog = Rian.Decl.parse(src)
    :ok = Rian.Check.gate!(prog)
    :ok = Rian.Reach.gate!(prog)

    out = opts[:output] || Path.rootname(Path.basename(file)) <> ".jar"
    {:ok, jar} = Rian.JVM.to_jar(src, out, main: opts[:main])

    size = File.stat!(jar).size
    Mix.shell().info("# #{file} → #{jar} (Kotlin/JVM, ADR-0049 Tier 2; #{size} bytes)")
    if opts[:main], do: Mix.shell().info("  run: java -jar #{jar}")
  rescue
    e in [Rian.Decl.Error, Rian.Check.Error, Rian.Reach.Error, Rian.JVM.Unsupported, RuntimeError] ->
      Mix.raise(Exception.message(e))
  end
end
