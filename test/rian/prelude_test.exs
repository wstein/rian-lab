defmodule Rian.PreludeTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The portable-prelude module API (`Rian.Prelude`): which `Mod.fun` calls are
  redirected to the linked `Rian.Prelude.*` BEAM modules (ADR-0047 §2). The type
  list and BEAM linkage are exercised via `prelude_list_test`; these pin the
  redirect-table accessors.
  """

  alias Rian.Prelude

  test "module_names/0 lists the redirected portable modules" do
    assert Prelude.module_names() == ["List", "Dict", "Str", "Int"]
  end

  describe "defines?/2 — only prelude-defined calls redirect" do
    test "true for a function the prelude actually defines" do
      assert Prelude.defines?("List", "sum")
    end

    test "false for an unimplemented function (falls through to Elixir FFI)" do
      refute Prelude.defines?("List", "to_string")
    end

    test "false for a module the prelude does not provide" do
      refute Prelude.defines?("Enum", "map")
    end
  end

  test "atom/1 maps a module name to its private linked atom" do
    assert Prelude.atom("List") == :"Elixir.Rian.Prelude.List"
  end
end
