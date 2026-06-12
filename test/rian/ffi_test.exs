defmodule Rian.FfiTest do
  use ExUnit.Case, async: false
  alias Rian.Lower

  setup_all do
    defs =
      [
        %{
          name: "total",
          params: [%{name: "xs", type: "Vec(Int64)", cap: :val}],
          ret: "Int64",
          clauses: [%{pats: [{:var, "xs"}], body: ":lists.sum(xs)"}]
        },
        %{
          name: "rev",
          params: [%{name: "xs", type: "Vec(Int64)", cap: :val}],
          ret: "Vec(Int64)",
          clauses: [%{pats: [{:var, "xs"}], body: ":lists.reverse(xs)"}]
        },
        %{
          name: "shout",
          params: [%{name: "s", type: "String", cap: :val}],
          ret: "String",
          clauses: [%{pats: [{:var, "s"}], body: "String.upcase(s)"}]
        },
        %{
          name: "clean",
          params: [%{name: "s", type: "String", cap: :val}],
          ret: "String",
          clauses: [%{pats: [{:var, "s"}], body: "String.trim(String.downcase(s))"}]
        }
      ]
      |> Enum.map_join("\n", fn f ->
        Lower.compile_beam([], f).elixir |> String.split("\n") |> List.last()
      end)

    Code.eval_string("defmodule FfiT do\n#{defs}\nend")
    :ok
  end

  describe "FFI lowering" do
    test "lowercase module head -> Erlang module call (:mod.fun)" do
      assert Lower.emit_expr(":lists.sum(xs)", :elixir) == ":lists.sum(xs)"
      assert Lower.emit_expr(":lists.reverse(xs)", :elixir) == ":lists.reverse(xs)"
      assert Lower.emit_expr(":maps.get(k, m)", :elixir) == ":maps.get(k, m)"
    end

    test "PascalCase module head -> Elixir module call (Mod.fun)" do
      assert Lower.emit_expr("String.upcase(s)", :elixir) == "String.upcase(s)"
      assert Lower.emit_expr("Enum.map(xs, f)", :elixir) == "Enum.map(xs, f)"
    end

    test "nested FFI calls compose" do
      assert Lower.emit_expr("String.trim(String.downcase(s))", :elixir) ==
               "String.trim(String.downcase(s))"
    end

    test "user module path still lowers as an Elixir module" do
      assert Lower.emit_expr("Geometry.area(x)", :elixir) == "Geometry.area(x)"
    end
  end

  describe "compiled FFI executes on the BEAM" do
    test "Erlang :lists FFI" do
      assert FfiT.total([1, 2, 3, 4]) == 10
      assert FfiT.rev([1, 2, 3]) == [3, 2, 1]
    end

    test "Elixir String FFI (incl. nested)" do
      assert FfiT.shout("hi") == "HI"
      assert FfiT.clean("  HeLLo  ") == "hello"
    end
  end
end
