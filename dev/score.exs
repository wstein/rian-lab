# Build scoreboard for the generated `rian/src` draft corpus.
#
#   mix run dev/score.exs            # isolated: each file compiled alone
#   mix run dev/score.exs --asm      # assembled: each file + the Rian prelude
#   mix run dev/score.exs --program  # whole corpus: all parsing files as ONE program
#
# "Assembled"/"program" modes prepend the hand-written portable prelude (List/Dict/
# Str/Int, examples/rian/prelude_*.rian) so a `List.map`/`Dict.get`/`Str.*` call
# resolves — measuring the corpus as part of a whole program rather than one file in
# a vacuum, separating a real compiler gap from a measurement artifact (the prelude
# not being in scope). See the memory note `rian-src-nested-repo-generated`.
#
# The prelude is **per target**: the `Int` module (`prelude_int.rian`) is built on
# `Int64` + the explicit 64-bit overflow prims, which are off `:js` BY DESIGN
# (ADR-0064 — `Int64` exceeds 2^53, the overflow prims pin off `:js`). Including it
# in the JS assembly would zero JS for the whole corpus on a constraint that is not
# a bug, so JS gets `list`/`dict`/`str` only — an honest assembly, not a trick.
#
# `--program` is the honest number for an *interconnected* compiler: per-file
# isolated scoring understates reach because a cross-module call (`List.map`, a
# struct from another module) is unresolved in a single file but fine in the whole.

mode =
  cond do
    "--program" in System.argv() -> :program
    "--asm" in System.argv() -> :asm
    true -> :isolated
  end

prelude_src = fn names ->
  names
  |> Enum.map(fn n -> File.read!("examples/rian/prelude_#{n}.rian") end)
  |> Enum.join("\n\n")
  |> Kernel.<>("\n\n")
end

# Per-target prelude: JS can't take the `Int64`/overflow-prim module (ADR-0064), so
# it gets list/dict/str only; the others get the full set. Empty in isolated mode.
prelude_for = fn target ->
  cond do
    mode == :isolated -> ""
    target == :js -> prelude_src.(~w(list dict str))
    true -> prelude_src.(~w(list dict str int))
  end
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
    true -> "other: " <> String.slice(msg, 0, 44)
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
# scoreboard tracks the real targets (not just BEAM): Rust via Rian.Lower, JS via
# Rian.JS, Kotlin via Rian.JVM. Each target is attempted independently (one raising
# does not mask the others), so a reach set is honest.
targets = [
  {:beam, fn src -> Rian.Beam.compile_program(src) end},
  {:rust, fn src -> Rian.Lower.rust_program(Rian.Decl.parse(src)) end},
  {:js, fn src -> Rian.JS.compile(src) end},
  {:jvm, fn src -> Rian.JVM.compile(src) end}
]

if mode == :program do
  # Assemble every file that parses in isolation into one program (a non-parsing
  # file would break the whole compile), then measure each target ONCE on it.
  parsing =
    Enum.filter(files, fn f -> match?(:ok, run.(fn -> Rian.Decl.parse(File.read!(f)) end)) end)

  corpus = parsing |> Enum.map(&File.read!/1) |> Enum.join("\n\n")

  IO.puts("\n=== rian/src scoreboard (WHOLE PROGRAM) ===")
  IO.puts("assembled #{length(parsing)}/#{length(files)} parsing files into one program\n")

  for {t, fun} <- targets do
    case run.(fn -> fun.(prelude_for.(t) <> corpus) end) do
      :ok ->
        IO.puts("  #{String.pad_trailing(to_string(t), 5)} ✓ reaches")

      {:fail, m} ->
        IO.puts("  #{String.pad_trailing(to_string(t), 5)} · #{categorize.(m)}")
    end
  end

  IO.puts("")
else
  results =
    Enum.map(files, fn f ->
      file_src = File.read!(f)
      rel = Path.relative_to(f, "rian/src")

      # parse with the full (beam) prelude assembled in `--asm`, file-only otherwise
      case run.(fn -> Rian.Decl.parse(prelude_for.(:beam) <> file_src) end) do
        :ok ->
          reach =
            Map.new(targets, fn {t, fun} ->
              {t,
               case run.(fn -> fun.(prelude_for.(t) <> file_src) end) do
                 :ok -> :ok
                 {:fail, m} -> {:fail, categorize.(m)}
               end}
            end)

          {rel, :parsed, reach}

        {:fail, m} ->
          {rel, :fail, %{parse: {:fail, categorize.(m)}}}
      end
    end)

  parse = Enum.count(results, fn {_, s, _} -> s == :parsed end)
  count = fn t -> Enum.count(results, fn {_, _, reach} -> match?(:ok, Map.get(reach, t)) end) end

  label = if mode == :asm, do: "ASSEMBLED + prelude", else: "isolated"
  IO.puts("\n=== rian/src scoreboard (#{label}) ===")
  IO.puts("parse #{parse}/#{length(files)}")

  IO.puts(
    "reach  beam #{count.(:beam)}   rust #{count.(:rust)}   js #{count.(:js)}   jvm #{count.(:jvm)}\n"
  )

  # Per-target first-blocker histogram: for each target, why the parsed files that
  # DON'T reach it stop. The parse failures are reported once under :parse.
  for {t, hist_label} <- [
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
      IO.puts("#{hist_label} first-blocker histogram:")

      Enum.each(hist, fn {cat, n} ->
        IO.puts("  #{String.pad_trailing(to_string(n), 3)} #{cat}")
      end)

      IO.puts("")
    end
  end
end
