defmodule Rian.ManifestTest do
  # The `rian.toml` manifest reader (ADR-0080 §2) — the build system's foundation.
  use ExUnit.Case, async: true

  alias Rian.Manifest

  describe "parse/1 — a valid manifest" do
    test "reads the full project table, deps, and lint into a struct" do
      toml = ~S"""
      [project]
      name    = "my_app"      # the app name
      version = "0.1.0"
      kind    = "app"
      license = "Apache-2.0"
      authors = ["Ada Lovelace <ada@example.com>", "Grace Hopper <grace@example.com>"]
      targets = ["ex", "rs", "js"]

      [deps]
      some_lib = "1.0"

      [lint]
      max_severity = "warn"
      """

      assert {:ok, m} = Manifest.parse(toml)
      assert m.name == "my_app"
      assert m.version == "0.1.0"
      assert m.kind == "app"
      assert m.license == "Apache-2.0"
      assert m.authors == ["Ada Lovelace <ada@example.com>", "Grace Hopper <grace@example.com>"]
      # targets become validated atoms (the Reach portability contract, ADR-0058)
      assert m.targets == [:ex, :rs, :js]
      assert m.deps == %{"some_lib" => "1.0"}
      assert m.lint == %{"max_severity" => "warn"}
    end

    test "kind defaults to `lib`; optional fields default empty" do
      assert {:ok, m} = Manifest.parse(~S|[project]
      name = "lib_only"
      version = "0.0.1"|)

      assert m.kind == "lib"
      assert m.targets == []
      assert m.authors == []
      assert m.deps == %{}
      assert m.lint == %{}
    end

    test "a `#` inside a string value is not treated as a comment" do
      assert {:ok, m} = Manifest.parse(~S|[project]
      name = "app"
      version = "1.0.0"
      license = "LicenseRef-my#tag"|)

      assert m.license == "LicenseRef-my#tag"
    end
  end

  describe "parse/1 — validation errors (clear, never a silent misread)" do
    test "an unknown target is rejected against the closed vocabulary" do
      assert {:error, msg} =
               Manifest.parse(~S|[project]
               name = "x"
               version = "1"
               targets = ["ex", "wasm"]|)

      assert msg =~ "unknown target(s) [\"wasm\"]"
    end

    test "a missing name/version is rejected" do
      assert {:error, msg} = Manifest.parse(~S|[project]
      version = "1"|)

      assert msg =~ "missing a non-empty `name`"
    end

    test "an unknown kind is rejected" do
      assert {:error, msg} = Manifest.parse(~S|[project]
      name = "x"
      version = "1"
      kind = "weird"|)

      assert msg =~ "`kind` must be one of"
    end

    test "a key outside any [table] is rejected" do
      assert {:error, msg} = Manifest.parse(~S|name = "x"|)
      assert msg =~ "key outside any [table]"
    end

    test "a value outside the supported subset (a bare number/bool) is a clear error" do
      assert {:error, msg} = Manifest.parse(~S|[project]
      name = "x"
      version = 1|)

      assert msg =~ "malformed entry"
    end
  end

  describe "read/1" do
    test "a missing file is a clear error, not a crash" do
      assert {:error, msg} = Manifest.read("definitely_no_such_manifest.toml")
      assert msg =~ "cannot read"
    end
  end
end
