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
      assert length(data["cells"]) == 6

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

    test "the capabilities cell shows the val-borrow vs iso-owned Rust distinction", %{data: data} do
      rust = cell(data, "capabilities")["panes"]["rs"]
      assert rust =~ "fn area(s: &Shape)"
      assert rust =~ "fn consume(s: Shape)"
    end

    test "the clauses cell carries the JVM guard fix (no invalid empty `if ()`)", %{data: data} do
      jvm = cell(data, "clauses")["panes"]["jvm"]
      refute jvm =~ "if ()"
      assert jvm =~ "run { val n = a0; if ((n < 0L)) { return \"negative\" } }"
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

  defp cell(data, id), do: Enum.find(data["cells"], &(&1["id"] == id))
end
