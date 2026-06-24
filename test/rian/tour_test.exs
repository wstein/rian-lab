defmodule Rian.TourTest do
  use ExUnit.Case, async: true

  alias Rian.Tour

  @json_path Path.expand("../../site/src/data/tour.json", __DIR__)

  describe "generate/0 derives every pane from the real emitters" do
    setup do
      %{data: Tour.generate()}
    end

    test "every cell reaches all four targets and emits non-empty code per pane", %{data: data} do
      assert data["targets"] == ~w(ex rs js jvm)
      assert length(data["cells"]) == 8

      for cell <- data["cells"] do
        for t <- ~w(ex rs js jvm) do
          assert is_binary(cell["panes"][t]) and cell["panes"][t] != "",
                 "#{cell["id"]}/#{t} pane is empty"
        end

        for {fn_name, reach} <- cell["reach"] do
          assert Enum.sort(reach) == ~w(ex js jvm rs),
                 "#{cell["id"]}: #{fn_name} should reach all four targets, got #{inspect(reach)}"
        end
      end
    end

    # Specific emitter-output assertions for these cells live with the emitters
    # they exercise — `fn area(s: &Shape)` / `fn consume(s: Shape)` in
    # `Rian.LowerTest`, the JVM guard form in `Rian.JVMTest` — so the tour tests
    # the tour data, not emitter correctness (ADR-0091). The non-empty-pane check
    # above is the tour-level guarantee.

    test "the basics JS pane is the clean single-clause form (no `a0`/throw)", %{data: data} do
      basics = Enum.find(data["cells"], &(&1["id"] == "basics"))
      # a single all-var clause names its param directly and drops the dead throw,
      # matching the Elixir pane's cleanliness (the playground's first impression).
      assert basics["panes"]["js"] == "function twice(n) { return (n * 2); }"
    end

    test "a sum variant lowers to a tagged object with positional keys (`a0._0`, ADR-0049 §3b)",
         %{
           data: data
         } do
      js = Enum.find(data["cells"], &(&1["id"] == "types"))["panes"]["js"]
      # JS keeps positional field keys (`_0`); the JVM `data class` is the named-field backend
      assert js =~ ~s|a0.$ === "Circle"|
      assert js =~ "const r = a0._0;"
      refute js =~ "a0.radius"
    end

    test "the same variant lowers to a Kotlin `data class` with named fields (JVM keeps labels)",
         %{
           data: data
         } do
      jvm = Enum.find(data["cells"], &(&1["id"] == "types"))["panes"]["jvm"]
      # the declared field name is the `data class` param and the smart-cast accessor — not `f0`
      assert jvm =~ "data class Circle(val radius: Double)"
      assert jvm =~ "data class Square(val side: Double)"
      assert jvm =~ "a0.radius"
      refute jvm =~ ".f0"
    end

    test "the reachability strip is the honest, inferred matrix (ADR-0057)", %{data: data} do
      by_name = Map.new(data["reachExamples"], &{&1["name"], &1["reach"]})

      assert Enum.sort(by_name["area"]) == ~w(ex js jvm rs)
      # `ref` is BEAM-rejected — off :ex, but still reaches the others
      refute "ex" in by_name["scale"]
      assert Enum.sort(by_name["scale"]) == ~w(js jvm rs)
      # host FFI is native-per-target — pinned to the BEAM
      assert by_name["shout"] == ["ex"]
    end
  end

  test "the committed tour.json is up to date (run `mix rian.tour` if this fails)" do
    committed = @json_path |> File.read!() |> :json.decode()

    assert committed == Tour.generate(),
           "site/src/data/tour.json is stale — regenerate it with `mix rian.tour`"
  end

  describe "to_json/0 — the deterministic encoder the mix task writes" do
    test "round-trips through a standard JSON decoder back to generate/0" do
      json = Tour.to_json()
      assert is_binary(json)
      # the bespoke encoder must agree with a standard decoder on the real dataset
      # (exercises map/list/string encoding and `\n`/`\"`/`\\` escaping in sources).
      assert :json.decode(json) == Tour.generate()
    end

    test "is deterministic — identical bytes on repeated calls, with sorted object keys" do
      assert Tour.to_json() == Tour.to_json()
      # object keys are emitted in sorted order, so `cells` precedes `reachExamples`
      # and `targets`, and within a cell `blurb` precedes `covers` precedes `file`.
      json = Tour.to_json()
      assert :binary.match(json, "\"cells\"") < :binary.match(json, "\"reachExamples\"")
      assert :binary.match(json, "\"blurb\"") < :binary.match(json, "\"covers\"")
    end

    test "pretty-prints with 2-space indentation and escapes newlines in sources" do
      json = Tour.to_json()
      assert String.starts_with?(json, "{\n  \"cells\": [\n")
      # multi-line Rian sources keep their newlines as `\n` escapes, not raw breaks
      assert json =~ "\\n"
    end
  end
end
