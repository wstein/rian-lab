defmodule Rian.Doctest do
  @moduledoc """
  Spec-by-example / doctests — ADR-0060 tier B: *documentation that cannot drift*.

  An example lives in a `@doc`/`@moduledoc` heredoc (ADR-0051) as one or more
  lines of the form

      expr  #=> expected

  where both `expr` and `expected` are ordinary Rian expressions. The runner
  compiles the source, synthesises a pair of zero-arity functions per example
  (`expr` and `expected`), runs them on the BEAM, and asserts the two values are
  equal. Because both sides are *real Rian* evaluated the same way, no value
  needs to be parsed into a host term, and a drifted example fails the build —
  closing the stale-example bug-class (ADR-0060 §Consequences) at its source.

  Assertions are values, not exceptions (ADR-0035): `run/1` returns
  `[{expr, :pass | {:fail, got, expected}}]`; `exunit/1` maps a failure to an
  ExUnit failure (the per-target harness of ADR-0060 §2).

  ## Scope

  Doctests live in `@doc`/`@moduledoc` heredocs on **top-level** functions and on
  **functions inside a single `mod`** (the synthesised checks are injected into
  that module so unqualified references resolve). `run_markdown/1` extracts each
  ` ```rian ` fence from a `docs/spec/*.md` file and runs it as a self-contained
  program — turning the spec corpus executable (ADR-0060). Comparison is
  BEAM-first; the Rust/JS harness is deferred.
  """
  alias Rian.{Beam, Decl}

  @marker "#=>"
  @line ~r/^\s*(?<expr>\S.*?)\s+#=>\s+(?<expected>\S.*?)\s*$/

  @doc """
  Extract `{expr, expected}` example pairs from a source's `@doc`s — top-level
  functions and functions inside a single `mod`.
  """
  def extract(src) do
    prog = Decl.parse(src)
    docs = Enum.map(prog.funcs, & &1.doc) ++ module_doc_strings(prog)
    Enum.flat_map(docs, &pairs/1)
  end

  # the `@doc`/`@moduledoc` strings of a single enclosed module (for module-internal
  # doctests); multi-module programs only expose their top-level docs for now.
  defp module_doc_strings(%{mods: [m]}), do: [m.doc | Enum.map(m.funcs, & &1.doc)]
  defp module_doc_strings(_prog), do: []

  defp pairs(nil), do: []

  defp pairs(doc) when is_binary(doc) do
    doc
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.named_captures(@line, line) do
        %{"expr" => e, "expected" => x} -> [{String.trim(e), String.trim(x)}]
        nil -> []
      end
    end)
  end

  @doc """
  Compile `src` with its doctests and run them. Returns
  `[{expr, :pass | {:fail, got, expected}}]`, one per example.
  """
  def run(src, mod \\ nil) do
    case extract(src) do
      [] ->
        []

      examples ->
        mod = mod || :"rian_doctest_#{:erlang.phash2(src)}"
        {:ok, ^mod} = Beam.load(augment(src, examples), mod)

        examples
        |> Enum.with_index()
        |> Enum.map(fn {{expr, _expected}, i} ->
          got = apply(mod, :"__dt_#{i}", [])
          want = apply(mod, :"__dt_#{i}_e", [])
          {expr, if(got == want, do: :pass, else: {:fail, got, want})}
        end)
    end
  end

  # append a pair of zero-arity functions per example. The dummy `Int64` return
  # type is erased on the BEAM (types are representation intent, not a runtime
  # contract — ADR-0034 §1) and `Beam.compile` does not run the type gate, so the
  # synthesised functions carry any value the example produces. For a single-`mod`
  # program the checks are injected *inside* the module (before its closing `end`)
  # so unqualified, module-local references resolve.
  defp augment(src, examples) do
    defs =
      examples
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {{expr, exp}, i} ->
        "def __dt_#{i}() Int64 := #{expr}\ndef __dt_#{i}_e() Int64 := #{exp}"
      end)

    if single_module?(src),
      do: inject_before_last_end(src, defs),
      else: src <> "\n\n" <> defs <> "\n"
  end

  defp single_module?(src) do
    case Decl.parse(src) do
      %{funcs: [], mods: [_]} -> true
      _ -> false
    end
  end

  # insert `defs` before the source's final `end` (the enclosing module's).
  defp inject_before_last_end(src, defs) do
    lines = String.split(src, "\n")
    idx = lines |> Enum.reverse() |> Enum.find_index(&(String.trim(&1) == "end"))
    at = length(lines) - 1 - idx
    {before, [the_end | rest]} = Enum.split(lines, at)
    Enum.join(before ++ [defs, the_end | rest], "\n")
  end

  @doc """
  Define one ExUnit `test` per doctest in the `.rian` file at `path` (read at
  compile time). Expand inside a `use ExUnit.Case` module.
  """
  defmacro exunit(path) do
    src = File.read!(path)
    cases = exunit_cases(src, :"rian_doctest_#{:erlang.phash2(path)}")
    quote(do: unquote(cases))
  end

  # ── Markdown (docs/spec/*.md) ────────────────────────────────────────────
  @fence ~r/```rian\n(?<body>.*?)\n```/s

  @doc "Each ` ```rian ` fenced block in `md`, as a Rian source string."
  def fences(md), do: Regex.scan(@fence, md, capture: ["body"]) |> Enum.map(&hd/1)

  @doc """
  Run every ` ```rian ` fence in a Markdown string as a self-contained program,
  returning `[{expr, :pass | {:fail, got, expected}}]` across all fences.
  """
  def run_markdown(md), do: md |> fences() |> Enum.flat_map(&run/1)

  @doc """
  Define one ExUnit `test` per doctest across all ` ```rian ` fences in the
  Markdown file at `path`. Expand inside a `use ExUnit.Case` module.
  """
  defmacro exunit_markdown(path) do
    cases =
      path
      |> File.read!()
      |> Rian.Doctest.fences()
      |> Enum.with_index()
      |> Enum.flat_map(fn {src, fi} ->
        exunit_cases(src, :"rian_doctest_md_#{:erlang.phash2(path)}_#{fi}")
      end)

    quote(do: unquote(cases))
  end

  # build the per-example ExUnit `test` ASTs for one Rian source
  defp exunit_cases(src, mod) do
    for {{expr, expected}, i} <- Enum.with_index(extract(src)) do
      label = "doctest: #{expr} #{@marker} #{expected}"

      quote do
        test unquote(label) do
          results = Rian.Doctest.run(unquote(src), unquote(mod))
          assert Enum.at(results, unquote(i)) |> elem(1) == :pass
        end
      end
    end
  end
end
