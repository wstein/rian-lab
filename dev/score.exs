# Per-file build scoreboard for the generated `rian/src` draft corpus.
#
#   mix run dev/score.exs            # isolated: each file compiled alone
#   mix run dev/score.exs --asm      # assembled: each file + the Rian prelude
#
# "Assembled" mode prepends the hand-written portable prelude (List/Dict/Str/Int,
# examples/rian/prelude_*.rian) so a `List.map`/`Dict.get`/`Str.*` call resolves —
# i.e. it measures the corpus as part of a whole program rather than one file in a
# vacuum, separating a real compiler gap from a measurement artifact (the prelude
# not being in scope). See the memory note `rian-src-nested-repo-generated`.
#
# Both modes report parse totals + per-target reach (beam/rust/js/jvm) and a
# per-target histogram of the FIRST blocker per file, so the actual frontier
# (what to fix next, per backend) is visible, not just a count.

asm? = "--asm" in System.argv()

prelude =
  if asm? do
    Path.wildcard("examples/rian/prelude_{list,dict,str,int}.rian")
    |> Enum.map(&File.read!/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n\n")
  else
    ""
  end

files = Path.wildcard("rian/src/**/*.rian") |> Enum.sort()

# coarse category for a first-blocker message, so the histogram is readable
categorize = fn msg ->
  cond do
    msg =~ "no `Show`" -> "interp: unresolved hole (no Show)"
    msg =~ "not supported here" -> "interp: survived to Core"
    msg =~ "cannot infer the return type" -> "infer: private return"
    msg =~ "mod" and msg =~ "not closed" -> "parse: mod not closed"
    msg =~ "cannot scan" -> "lex: cannot scan (sigil/op)"
    msg =~ "expected `,` or `)`" -> "parse: expected , or )"
    msg =~ "trailing tokens" -> "parse: trailing tokens"
    msg =~ "unsupported pattern" -> "parse: unsupported pattern"
    msg =~ "bad parameter" -> "parse: bad parameter"
    msg =~ "reserved namespace" -> "parse: reserved namespace"
    msg =~ "unexpected token" -> "parse: unexpected token"
    msg =~ "destructuring bind" -> "parse: destructuring bind"
    msg =~ "compile.forms failed" -> "beam: forms failed"
    msg =~ "undefined_function" -> "beam: undefined function"
    true -> "other: " <> String.slice(msg, 0, 40)
  end
end

run = fn fun ->
  try do
    fun.()
    :ok
  rescue
    e -> {:fail, Exception.message(e) |> String.split("\n") |> hd()}
  catch
    k, v -> {:fail, "#{k}: #{inspect(v)}" |> String.slice(0, 60)}
  end
end

# Drive each emitter from source the same way `mix rian.compile` does, so the
# scoreboard tracks the real targets (not just BEAM): Rust via Rian.Lower,
# JS via Rian.JS, Kotlin via Rian.JVM. Each target is attempted independently
# (one raising does not mask the others), so a file's reach set is honest.
targets = [
  {:beam, fn src -> Rian.Beam.compile_program(src) end},
  {:rust, fn src -> Rian.Lower.rust_program(Rian.Decl.parse(src)) end},
  {:js, fn src -> Rian.JS.compile(src) end},
  {:jvm, fn src -> Rian.JVM.compile(src) end}
]

results =
  Enum.map(files, fn f ->
    src = prelude <> File.read!(f)
    rel = Path.relative_to(f, "rian/src")

    case run.(fn -> Rian.Decl.parse(src) end) do
      :ok ->
        reach =
          Map.new(targets, fn {t, fun} ->
            {t,
             case run.(fn -> fun.(src) end) do
               :ok -> :ok
               {:fail, m} -> {:fail, categorize.(m)}
             end}
          end)

        {rel, :parsed, reach}

      {:fail, m} ->
        {rel, :fail, %{parse: {:fail, categorize.(m)}}}
    end
  end)

ok? = fn reach, t -> match?(:ok, Map.get(reach, t)) end

parse = Enum.count(results, fn {_, s, _} -> s == :parsed end)
count = fn t -> Enum.count(results, fn {_, _, reach} -> ok?.(reach, t) end) end

IO.puts("\n=== rian/src scoreboard (#{if asm?, do: "ASSEMBLED + prelude", else: "isolated"}) ===")
IO.puts("parse #{parse}/#{length(files)}")

IO.puts(
  "reach  beam #{count.(:beam)}   rust #{count.(:rust)}   js #{count.(:js)}   jvm #{count.(:jvm)}\n"
)

# Per-target first-blocker histogram: for each target, why the parsed files that
# DON'T reach it stop. The parse failures are reported once under :parse.
for {t, label} <- [
      {:parse, "PARSE (file never parsed)"},
      {:beam, "BEAM"},
      {:rust, "RUST"},
      {:js, "JS"},
      {:jvm, "JVM"}
    ] do
  hist =
    results
    |> Enum.flat_map(fn {_, _, reach} ->
      case Map.get(reach, t) do
        {:fail, cat} -> [cat]
        _ -> []
      end
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, n} -> -n end)

  if hist != [] do
    IO.puts("#{label} first-blocker histogram:")

    Enum.each(hist, fn {cat, n} -> IO.puts("  #{String.pad_trailing(to_string(n), 3)} #{cat}") end)

    IO.puts("")
  end
end
