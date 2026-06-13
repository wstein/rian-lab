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

  ## MVP scope

  Doctests on **top-level** function docs (the synthesised checks are top-level
  functions that call them). Module-internal doctests and `docs/spec/*.md` fence
  extraction are follow-ups (ADR-0060 open items). Comparison is BEAM-first; the
  Rust/JS harness is deferred.
  """
  alias Rian.{Beam, Decl}

  @marker "#=>"
  @line ~r/^\s*(?<expr>\S.*?)\s+#=>\s+(?<expected>\S.*?)\s*$/

  @doc "Extract `{expr, expected}` example pairs from a source's top-level `@doc`s."
  def extract(src) do
    Decl.parse(src).funcs
    |> Enum.flat_map(fn f -> pairs(f.doc) end)
  end

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
  # synthesised functions carry any value the example produces.
  defp augment(src, examples) do
    defs =
      examples
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {{expr, exp}, i} ->
        "def __dt_#{i}() Int64 := #{expr}\ndef __dt_#{i}_e() Int64 := #{exp}"
      end)

    src <> "\n\n" <> defs <> "\n"
  end

  @doc """
  Define one ExUnit `test` per doctest in the `.rian` file at `path` (read at
  compile time). Expand inside a `use ExUnit.Case` module.
  """
  defmacro exunit(path) do
    src = File.read!(path)
    examples = extract(src)
    mod = :"rian_doctest_#{:erlang.phash2(path)}"

    cases =
      for {{expr, expected}, i} <- Enum.with_index(examples) do
        label = "doctest: #{expr} #{@marker} #{expected}"

        quote do
          test unquote(label) do
            results = Rian.Doctest.run(unquote(src), unquote(mod))
            assert Enum.at(results, unquote(i)) |> elem(1) == :pass
          end
        end
      end

    quote do
      unquote(cases)
    end
  end
end
