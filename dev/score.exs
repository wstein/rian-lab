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
# Both modes report parse/beam totals and a histogram of the FIRST blocker per file,
# so the actual frontier (what to fix next) is visible, not just a count.

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

results =
  Enum.map(files, fn f ->
    src = prelude <> File.read!(f)
    rel = Path.relative_to(f, "rian/src")

    case run.(fn -> Rian.Decl.parse(src) end) do
      :ok ->
        case run.(fn -> Rian.Beam.compile_program(src) end) do
          :ok -> {rel, :beam, nil}
          {:fail, m} -> {rel, :parse_only, categorize.(m)}
        end

      {:fail, m} ->
        {rel, :fail, categorize.(m)}
    end
  end)

parse = Enum.count(results, fn {_, s, _} -> s in [:beam, :parse_only] end)
beam = Enum.count(results, fn {_, s, _} -> s == :beam end)

IO.puts("\n=== rian/src scoreboard (#{if asm?, do: "ASSEMBLED + prelude", else: "isolated"}) ===")
IO.puts("parse #{parse}/#{length(files)}   beam #{beam}\n")

IO.puts("first-blocker histogram (non-building files):")

results
|> Enum.reject(fn {_, s, _} -> s == :beam end)
|> Enum.map(fn {_, _, cat} -> cat end)
|> Enum.frequencies()
|> Enum.sort_by(fn {_, n} -> -n end)
|> Enum.each(fn {cat, n} -> IO.puts("  #{String.pad_trailing(to_string(n), 3)} #{cat}") end)
