defmodule Rian.PrimitiveTest do
  # ADR-0033: Crystal-family primitive vocabulary. Source names (`Int64`,
  # `Float64`, `String`, `Bool`, `Symbol`) are Rian's, and map to each target.
  use ExUnit.Case, async: true

  alias Rian.{Capability, Lower}

  # one variant carrying a field of each primitive -> exercises prim_ex (Elixir
  # typespec) and prim_rust (Rust field type) for all five in one shot.
  defp types do
    [
      %{
        name: "Prim",
        variants: [
          %{
            ctor: "P",
            fields: [
              %{type: "Int64"},
              %{type: "Float64"},
              %{type: "String"},
              %{type: "Bool"},
              %{type: "Symbol"}
            ]
          }
        ]
      }
    ]
  end

  defp func do
    %{
      name: "tag",
      param_name: "p",
      param_type: "Prim",
      param_cap: :val,
      ret: "Int64",
      clauses: [
        %{pats: [{:ctor, "P", Enum.map(~w(a b c d e), &{:var, &1})}], body: "0"}
      ]
    }
  end

  test "Elixir typespec maps Crystal primitives" do
    el = Lower.compile(types(), func()).elixir
    assert el =~ "{:p, integer(), float(), String.t(), boolean(), atom()}"
  end

  test "Rust enum fields map Crystal primitives to Rust spellings" do
    assert Lower.compile(types(), func()).rust =~ "P(i64, f64, String, bool, Symbol)"
  end

  test "return type lowers per target (Int64 -> i64 / integer())" do
    out = Lower.compile(types(), func())
    assert out.rust =~ "-> i64"
  end

  test "rust_name maps width-explicit scalars; nominal/String pass through" do
    assert Capability.rust_name("Int32") == "i32"
    assert Capability.rust_name("UInt64") == "u64"
    assert Capability.rust_name("Float32") == "f32"
    assert Capability.rust_name("Bool") == "bool"
    assert Capability.rust_name("Char") == "char"
    assert Capability.rust_name("String") == "String"
    assert Capability.rust_name("Shape") == "Shape"
  end
end
