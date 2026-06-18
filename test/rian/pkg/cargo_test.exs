defmodule Rian.Pkg.CargoTest do
  @moduledoc "Cargo backend (ADR-0082 step 1): rian.toml manifest -> deterministic Cargo.toml."
  use ExUnit.Case, async: true

  alias Rian.Manifest
  alias Rian.Pkg.Cargo

  test "generates a deterministic lib Cargo.toml from the manifest" do
    m = %Manifest{
      name: "my_app",
      version: "0.1.0",
      license: "Apache-2.0",
      authors: ["Ada <a@x.io>"]
    }

    toml = Cargo.cargo_toml(m)

    assert toml =~ ~s(name = "my_app")
    assert toml =~ ~s(version = "0.1.0")
    assert toml =~ ~s(edition = "2021")
    assert toml =~ ~s(license = "Apache-2.0")
    assert toml =~ ~s(authors = ["Ada <a@x.io>"])
    assert toml =~ "[lib]"
    assert toml =~ ~s(path = "src/lib.rs")
    # deterministic: same manifest -> byte-identical output (invariant 2)
    assert Cargo.cargo_toml(m) == toml
  end

  test "omits license/authors when absent" do
    toml = Cargo.cargo_toml(%Manifest{name: "x", version: "0.0.0"})
    refute toml =~ "license"
    refute toml =~ "authors"
  end

  test "a hyphenated package name becomes an underscore crate identifier" do
    assert Cargo.cargo_toml(%Manifest{name: "my-app", version: "0.0.0"}) =~ ~s(name = "my_app")
  end

  test "a non-empty [deps] is a loud error — no resolver yet (invariant 4)" do
    m = %Manifest{name: "x", version: "0.0.0", deps: %{"foo" => "1.0"}}
    assert_raise ArgumentError, ~r/no resolver/, fn -> Cargo.cargo_toml(m) end
  end

  test "a bin crate (kind = app) raises until the main wrapper lands" do
    m = %Manifest{name: "x", version: "0.0.0", kind: "app"}
    assert_raise ArgumentError, ~r/bin packaging/, fn -> Cargo.cargo_toml(m) end
  end
end
