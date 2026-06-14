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
      assert length(data["cells"]) == 4

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

  defp cell(data, id), do: Enum.find(data["cells"], &(&1["id"] == id))
end
