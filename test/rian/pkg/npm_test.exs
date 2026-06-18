defmodule Rian.Pkg.NpmTest do
  @moduledoc "npm backend (ADR-0082 step 4): rian.toml manifest -> package.json."
  use ExUnit.Case, async: true

  alias Rian.Manifest
  alias Rian.Pkg.Npm

  test "package.json is deterministic ESM with name/version/license/main" do
    m = %Manifest{name: "my_app", version: "0.1.0", license: "Apache-2.0"}
    j = Npm.package_json(m, "my_app.mjs")

    assert j =~ ~s("name": "my_app")
    assert j =~ ~s("version": "0.1.0")
    assert j =~ ~s("license": "Apache-2.0")
    assert j =~ ~s("type": "module")
    assert j =~ ~s("main": "my_app.mjs")
    # deterministic: same manifest -> byte-identical output (invariant 2)
    assert Npm.package_json(m, "my_app.mjs") == j
  end

  test "omits license when absent" do
    refute Npm.package_json(%Manifest{name: "x", version: "0.0.0"}, "x.mjs") =~ "license"
  end

  test "a non-empty [deps] is a loud error — no resolver yet (invariant 4)" do
    m = %Manifest{name: "x", version: "0.0.0", deps: %{"left-pad" => "1.0"}}
    assert_raise ArgumentError, ~r/no resolver/, fn -> Npm.package_json(m, "x.mjs") end
  end
end
