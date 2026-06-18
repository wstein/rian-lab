defmodule Rian.Pkg.GradleTest do
  @moduledoc "Gradle backend (ADR-0082 step 3): rian.toml manifest -> build.gradle.kts + settings."
  use ExUnit.Case, async: true

  alias Rian.Manifest
  alias Rian.Pkg.Gradle

  test "build.gradle.kts is deterministic with a pinned Kotlin plugin + JVM target" do
    m = %Manifest{name: "my_app", version: "0.1.0"}
    b = Gradle.build_gradle(m)

    assert b =~ ~s|kotlin("jvm") version "2.2.20"|
    assert b =~ "mavenCentral()"
    assert b =~ "JvmTarget.JVM_21"
    assert b =~ "options.release.set(21)"
    # deterministic: same manifest -> byte-identical output (invariant 2)
    assert Gradle.build_gradle(m) == b
  end

  test "settings.gradle.kts names the root project" do
    assert Gradle.settings_gradle(%Manifest{name: "my_app", version: "0.0.0"}) ==
             ~s(rootProject.name = "my_app"\n)
  end

  test "a non-empty [deps] is a loud error — no resolver yet (invariant 4)" do
    m = %Manifest{name: "x", version: "0.0.0", deps: %{"guava" => "33.0"}}
    assert_raise ArgumentError, ~r/no resolver/, fn -> Gradle.build_gradle(m) end
  end

  test "an application crate (kind = app) raises until the main wrapper lands" do
    m = %Manifest{name: "x", version: "0.0.0", kind: "app"}
    assert_raise ArgumentError, ~r/application packaging/, fn -> Gradle.build_gradle(m) end
  end
end
