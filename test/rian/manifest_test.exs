defmodule Rian.ManifestTest do
  # The `rian.toml` manifest reader (ADR-0080 §2) — the build system's foundation.
  # async: false — `with_project/2` mutates the global `:rian_manifest` app env that
  # `Rian.Reach.gate!/1` reads on every compile; a concurrent test would see it.
  use ExUnit.Case, async: false

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

    test "a comma inside a quoted array value is preserved, not split on" do
      assert {:ok, m} = Manifest.parse(~S|[project]
      name = "app"
      version = "1.0.0"
      authors = ["Hopper, Grace", "Lovelace, Ada"]|)

      assert m.authors == ["Hopper, Grace", "Lovelace, Ada"]
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

    test "a malformed string value (an embedded quote) is rejected, not silently truncated" do
      assert {:error, msg} = Manifest.parse(~S|[project]
      name = "x"
      version = "1"
      license = "a"b"|)

      assert msg =~ "malformed entry"
    end

    test "an array with junk between quoted elements is rejected" do
      assert {:error, msg} = Manifest.parse(~S|[project]
      name = "x"
      version = "1"
      authors = ["ok" junk "no"]|)

      assert msg =~ "malformed entry"
    end

    test "a backslash in a string value is rejected (the subset has no escape sequences)" do
      # a stray `\` is meaningless here and would only break a generated Cargo.toml /
      # .app.src / build.gradle.kts; reject it at the single source.
      assert {:error, msg} = Manifest.parse(~S|[project]
      name = "x"
      version = "1"
      license = "a\b"|)

      assert msg =~ "malformed entry"
    end

    test "a name that is not a lowercase identifier is rejected" do
      # the name becomes a crate / npm package / Gradle root / Erlang app atom, so it
      # must be safe to interpolate into every backend without escaping (ADR-0080 §2).
      for bad <- [~s|"My_App"|, ~s|"my app"|, ~s|"my.app"|, ~s|"1up"|] do
        assert {:error, msg} =
                 Manifest.parse("[project]\nname = #{bad}\nversion = \"1\"")

        assert msg =~ "`name` must be a lowercase identifier", "expected rejection for #{bad}"
      end

      # snake_case and kebab-case are both accepted
      assert {:ok, _} = Manifest.parse(~s|[project]\nname = "my_app"\nversion = "1"|)
      assert {:ok, _} = Manifest.parse(~s|[project]\nname = "my-app"\nversion = "1"|)
    end
  end

  describe "read/1" do
    test "a missing file is a clear error, not a crash" do
      assert {:error, msg} = Manifest.read("definitely_no_such_manifest.toml")
      assert msg =~ "cannot read"
    end
  end

  describe "locate/1 and root/1 — project-root discovery (ADR-0080 §2/§7)" do
    setup do
      base = Path.join(System.tmp_dir!(), "rian_locate_#{System.unique_integer([:positive])}")
      sub = Path.join([base, "src", "deep"])
      File.mkdir_p!(sub)
      File.write!(Path.join(base, "rian.toml"), ~s|[project]\nname = "x"\nversion = "1"\n|)
      on_exit(fn -> File.rm_rf(base) end)
      %{base: Path.expand(base), sub: sub}
    end

    test "locate/1 walks up to the nearest rian.toml", %{base: base, sub: sub} do
      assert Manifest.locate(sub) == Path.join(base, "rian.toml")
    end

    test "root/1 is the manifest's directory from anywhere inside the project", %{
      base: base,
      sub: sub
    } do
      assert Manifest.root(sub) == base
      assert Manifest.root(base) == base
    end

    test "root/1 falls back to start_dir when no manifest is above it" do
      orphan = Path.join(System.tmp_dir!(), "rian_orphan_#{System.unique_integer([:positive])}")
      File.mkdir_p!(orphan)
      on_exit(fn -> File.rm_rf(orphan) end)

      assert Manifest.locate(orphan) == nil
      assert Manifest.root(orphan) == orphan
    end

    test "with_project/2 configures :rian_manifest during fun and restores it after", %{
      base: base
    } do
      Application.delete_env(:rian_lab, :rian_manifest)
      on_exit(fn -> Application.delete_env(:rian_lab, :rian_manifest) end)

      inner =
        Manifest.with_project(base, fn ->
          Application.get_env(:rian_lab, :rian_manifest)
        end)

      assert inner == Path.join(base, "rian.toml")
      # restored to the prior (unset) state
      assert Application.get_env(:rian_lab, :rian_manifest) == nil
    end

    test "with_project/2 restores a prior value, and is a no-op when no manifest is found" do
      orphan = Path.join(System.tmp_dir!(), "rian_orphan_#{System.unique_integer([:positive])}")
      File.mkdir_p!(orphan)
      on_exit(fn -> File.rm_rf(orphan) end)
      Application.put_env(:rian_lab, :rian_manifest, "prior.toml")
      on_exit(fn -> Application.delete_env(:rian_lab, :rian_manifest) end)

      inner =
        Manifest.with_project(orphan, fn ->
          Application.get_env(:rian_lab, :rian_manifest)
        end)

      # no manifest above `orphan`, so the prior value is untouched throughout
      assert inner == "prior.toml"
      assert Application.get_env(:rian_lab, :rian_manifest) == "prior.toml"
    end
  end
end
