defmodule Rian.Tour do
  @moduledoc """
  The compiler-derived data behind the **"Rian by Example"** tour page
  (`site/src/pages/by-example.astro`) and the homepage/playground that reuse it.

  Each cell is a small, self-contained Rian program. `generate/0` runs the *real*
  emitters — `Rian.Lower.rust_program/1` (Rust), `Rian.JS.compile/1` (ECMAScript),
  `Rian.JVM.compile/1` (Kotlin), and the Elixir-text debug view via
  `Rian.Decl.compile/1` — together with the reachability analysis
  (`Rian.Reach.analyze/1`). So the per-target code the site shows is exactly what
  this compiler produces, never a hand-transcribed approximation: the page cannot
  drift from the language.

  Alongside the curated `@cells` (hand-tuned minimal teaching snippets) the
  dataset carries an `"examples"` section built by `Rian.Tour.Examples.dataset/0`
  directly from the `examples/rian/NN_*.rian` corpus — each file's title, kind,
  declared/inferred reach, and extracted doctests (ADR-0091). So the by-example
  files are *inputs* to the published tour, not a parallel copy: a drift between a
  file and the site data fails the same freshness gate.

  The committed `site/src/data/tour.json` is the JSON of `generate/0`; the
  `mix rian.tour` task regenerates it and `Rian.TourTest` fails the build if the
  committed file and `generate/0` ever disagree.

  The data is JSON-shaped (string keys, lists where order matters), so a decoded
  `tour.json` compares equal to `generate/0` directly.
  """

  use Rian.Ann

  alias Rian.{Decl, JS, JVM, Lower, Reach}

  @targets ~w(ex rs js jvm)

  # Ordered tour cells. Each is a minimal program that teaches one idea and
  # reaches all four targets, so every pane is real emitted code.
  @cells [
    %{
      id: "basics",
      title: "The basics",
      file: "twice.rian",
      blurb:
        "Rian is expression-oriented and `:=` is single-assignment. A typed " <>
          "head is the type boundary; the body is the value.",
      covers: ["def", ":=", "type ascription"],
      source: """
      # expression-oriented · := single assignment
      def twice(n Int53) Int53 := n * 2
      """
    },
    %{
      id: "types",
      title: "Types & match",
      file: "area.rian",
      blurb:
        "A sealed sum and clause-per-constructor dispatch. The same definition " <>
          "becomes a tagged match on the BEAM, an `enum` + `match` on Rust, a tag " <>
          "switch on JS, and a sealed `when` on Kotlin.",
      covers: ["type", "constructors", "pattern clauses"],
      source: """
      type Shape := Circle(radius Float64) | Square(side Float64)

      def area(s val Shape) Float64
      def area(Circle(r)) := 3.14159 * r * r
      def area(Square(s)) := s * s
      """
    },
    %{
      id: "clauses",
      title: "Clauses & guards",
      file: "classify.rian",
      blurb:
        "Ordered clauses with a restricted guard sublanguage. The Maranget " <>
          "exhaustiveness gate proves the set total before any target is emitted — " <>
          "a missing case is a compile error, not a runtime surprise.",
      covers: ["when", "literal patterns", "exhaustiveness"],
      source: """
      def classify(n Int53) String
      def classify(n) when n < 0 := "negative"
      def classify(0) := "zero"
      def classify(n) := "positive"
      """
    },
    %{
      id: "capabilities",
      title: "Capabilities",
      file: "capability.rian",
      blurb:
        "A parameter's reference capability drives its Rust signature and its " <>
          "BEAM-side linearity — you never write a lifetime. `val` borrows " <>
          "(`&Shape`); `iso` owns and is consumed once (an owned `Shape`).",
      covers: ["val", "iso", "ownership"],
      source: """
      type Shape := Circle(radius Float64) | Square(side Float64)

      def area(s val Shape) Float64
      def area(Circle(r)) := 3.14159 * r * r
      def area(Square(s)) := s * s

      # `iso`: owned, consumed exactly once
      def consume(s iso Shape) Float64 := area(s)
      """
    },
    %{
      id: "case",
      title: "The `case` expression",
      file: "code.rian",
      blurb:
        "`case` is an expression that yields a value, proven total by the same " <>
          "exhaustiveness gate as clauses. It becomes a tagged match on the BEAM, " <>
          "an `enum` match on Rust, a tag switch on JS, and a labelled `run` on Kotlin.",
      covers: ["case", "arms (`->`)", "exhaustiveness"],
      source: """
      type Color := Red | Green | Blue

      def code(c val Color) Int53 := case c do
        Red -> 1
        Green -> 2
        Blue -> 3
      end
      """
    },
    %{
      id: "interpolation",
      title: "String interpolation",
      file: "greet.rian",
      blurb:
        "A `${expr}` hole stringifies by its statically-inferred type and lowers " <>
          "to a single-shot join (ADR-0069). `String` and `Int*` holes are " <>
          "byte-identical across every target — no hidden `Show` dispatch.",
      covers: ["${…}", "auto-stringify", "single-shot join"],
      source: """
      def greet(name String, age Int53) String := "hi ${name}, you are ${age}"
      """
    }
  ]

  # Functions whose inferred reachability is NOT the full set — the honest matrix
  # (ADR-0057): portability is inferred, and some capabilities/FFI pin a function
  # to a subset. Rendered as the page's reachability strip and the homepage matrix.
  @reach_examples [
    %{
      name: "area",
      sig: "area(s val Shape) Float64",
      blurb: "Pure, portable — reaches every target."
    },
    %{
      name: "scale",
      sig: "scale(s ref Vec(Float64), k Float64) Vec(Float64)",
      blurb: "`ref` (&mut) is BEAM-rejected (no process-local proof in the PoC).",
      defs: """
      def mul_each(xs val Vec(Float64), k Float64) Vec(Float64) := xs
      def scale(s ref Vec(Float64), k Float64) Vec(Float64) := mul_each(s, k)
      """
    },
    %{
      name: "shout",
      sig: "shout(s String) String := String.upcase(s)",
      blurb: "Host FFI is native-per-target, so it pins to the BEAM.",
      defs: "def shout(s String) String := String.upcase(s)\n"
    }
  ]

  @doc """
  Build the full tour dataset as JSON-shaped Elixir terms (string keys).
  """
  @rian_sig "pub def generate() _Unk"
  @spec generate() :: map()
  def generate do
    %{
      "targets" => @targets,
      "cells" => Enum.map(@cells, &build_cell/1),
      "examples" => Rian.Tour.Examples.dataset(),
      "reachExamples" => Enum.map(@reach_examples, &build_reach_example/1)
    }
  end

  @doc "Render `generate/0` as deterministic, pretty-printed JSON (sorted keys)."
  @rian_sig "pub def to_json() String"
  @spec to_json() :: String.t()
  def to_json, do: generate() |> encode(0) |> IO.iodata_to_binary()

  defp build_cell(%{id: id, source: source} = cell) do
    src = String.trim_trailing(source) <> "\n"
    prog = Decl.parse(src)
    reach = reach_map(prog)

    %{
      "id" => id,
      "title" => cell.title,
      "file" => cell.file,
      "blurb" => cell.blurb,
      "covers" => cell.covers,
      "source" => String.trim_trailing(src),
      "panes" => %{
        "ex" => elixir_module(src),
        "rs" => Lower.rust_program(prog),
        "js" => String.trim_trailing(JS.compile(src)),
        "jvm" => String.trim_trailing(JVM.compile(src))
      },
      "reach" => reach
    }
  end

  defp build_reach_example(%{name: name, sig: sig, blurb: blurb} = ex) do
    src = Map.get(ex, :defs, "def #{name}() Int53 := 0\n")
    reach = src |> Decl.parse() |> reach_map() |> Map.fetch!(name)
    %{"name" => name, "sig" => sig, "blurb" => blurb, "reach" => reach}
  end

  defp reach_map(prog) do
    prog
    |> Reach.analyze()
    |> Map.new(fn {key, %{reach: reach}} ->
      # the report keys by `"name/arity"` (arity overloading); the tour's single
      # non-overloaded examples are looked up by bare name, so strip the arity.
      {Reach.bare_name(key), reach |> MapSet.to_list() |> Enum.map(&to_string/1) |> Enum.sort()}
    end)
  end

  # Assemble the per-function Elixir-text debug view into one module, emitting the
  # shared `@type` declarations once.
  defp elixir_module(src) do
    units =
      for {_name, out} <- Decl.compile(src), out[:elixir], do: out[:elixir]

    {type_lines, body_blocks} =
      Enum.reduce(units, {[], []}, fn text, {types, blocks} ->
        {ts, rest} = text |> String.split("\n") |> Enum.split_with(&String.starts_with?(&1, "@"))
        {types ++ ts, blocks ++ [Enum.join(rest, "\n") |> String.trim()]}
      end)

    [Enum.uniq(type_lines), Enum.reject(body_blocks, &(&1 == ""))]
    |> List.flatten()
    |> Enum.join("\n")
    |> String.trim()
  end

  # ── deterministic JSON encoder (sorted object keys, 2-space indent) ──
  # `generate/0` produces a closed JSON shape — objects, arrays, and strings (the
  # `examples` section can carry empty `pins`/`doctests`). Should a future cell
  # introduce another value type (a number/bool), the round-trip test
  # (`Rian.TourTest`) fails loudly on the missing clause rather than letting an
  # untested branch ship; add the clause with its case then.

  defp encode(map, _indent) when map == %{}, do: "{}"

  defp encode([], _indent), do: "[]"

  defp encode(map, indent) when is_map(map) do
    pad = String.duplicate("  ", indent + 1)
    close = String.duplicate("  ", indent)

    body =
      map
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join(",\n", fn k ->
        [pad, encode_string(to_string(k)), ": ", encode(Map.fetch!(map, k), indent + 1)]
      end)

    ["{\n", body, "\n", close, "}"]
  end

  defp encode(list, indent) when is_list(list) do
    pad = String.duplicate("  ", indent + 1)
    close = String.duplicate("  ", indent)
    body = Enum.map_join(list, ",\n", fn v -> [pad, encode(v, indent + 1)] end)
    ["[\n", body, "\n", close, "]"]
  end

  defp encode(s, _indent) when is_binary(s), do: encode_string(s)

  defp encode_string(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\t", "\\t")
      |> String.replace("\r", "\\r")

    [?", escaped, ?"]
  end
end
