defmodule RianLabTest do
  use ExUnit.Case, async: true

  test "exposes the project version" do
    assert RianLab.version() =~ ~r/^\d+\.\d+\.\d+/
  end
end
