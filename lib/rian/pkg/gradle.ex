defmodule Rian.Pkg.Gradle do
  @moduledoc """
  Gradle/Kotlin backend for the native packaging layer (ADR-0082, staging step 3): a
  pure, deterministic `Rian.Manifest` → `build.gradle.kts` + `settings.gradle.kts`
  generator (Kotlin DSL).

  `rian build --jvm -o ROOT` writes a self-contained Gradle project under
  `ROOT/_build/jvm/`: the build scripts + `src/main/kotlin/<name>.kt` + each
  `@external(:jvm)` `.ffi.kt` copied into the same `src/main/kotlin/` source set (so the
  default-package call resolves — ADR-0082 invariant 5). `gradle build` builds straight
  through it.

  Determinism (ADR-0082 invariant 2): the Kotlin plugin and JVM target are **pinned**,
  not derived, so the output never churns. The pinned plugin (2.2.x) runs on current
  JDKs, and the JVM target keeps `compileKotlin`/`compileJava` consistent regardless of
  the host JDK.

  **Honesty (ADR-0082 invariant 4):** a non-empty `[deps]` raises (no resolver), and
  `kind = "app"` raises (the `application` plugin + a Rian-`main` wrapper is a later step)
  — never a manifest that won't build.
  """

  use Rian.Ann
  alias Rian.Manifest

  # pinned, not derived (ADR-0082 invariant 2). 2.2.x runs on modern JDKs; JVM_21 is a
  # widely-supported target that keeps the Kotlin/Java compile tasks consistent.
  @kotlin_plugin "2.2.20"
  @jvm_target "21"

  @doc """
  Generate `build.gradle.kts` for `manifest` (deterministic — pinned plugin + JVM
  target, no timestamps). Raises on a non-empty `[deps]` (no resolver) or `kind = "app"`
  — ADR-0082 invariant 4.
  """
  @rian_sig "pub def build_gradle(m Manifest) String"
  @spec build_gradle(Manifest.t()) :: String.t()
  def build_gradle(%Manifest{} = m) do
    reject_unresolved_deps!(m)
    reject_app!(m)

    """
    import org.jetbrains.kotlin.gradle.dsl.JvmTarget

    plugins {
        kotlin("jvm") version "#{@kotlin_plugin}"
    }

    repositories {
        mavenCentral()
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_#{@jvm_target})
        }
    }

    tasks.withType<JavaCompile> {
        options.release.set(#{@jvm_target})
    }
    """
  end

  @doc "Generate `settings.gradle.kts` (the Gradle root project name) for `manifest`."
  @rian_sig "pub def settings_gradle(m Manifest) String"
  @spec settings_gradle(Manifest.t()) :: String.t()
  def settings_gradle(%Manifest{name: name}), do: ~s(rootProject.name = "#{name}"\n)

  defp reject_unresolved_deps!(%Manifest{deps: deps}) when map_size(deps) > 0 do
    raise ArgumentError,
          "rian.toml `[deps]` lists #{map_size(deps)} dependenc#{plural(map_size(deps))} but the " <>
            "packaging layer has no resolver yet (ADR-0082 invariant 4) — add them to " <>
            "`build.gradle.kts` after `rian eject`, or vendor via `@external`"
  end

  defp reject_unresolved_deps!(_), do: :ok

  defp reject_app!(%Manifest{kind: "app"}) do
    raise ArgumentError,
          "Gradle application packaging (`kind = \"app\"`) is not yet built — it needs the " <>
            "`application` plugin + a Rian-`main` wrapper (ADR-0082 staging). Use `kind = \"lib\"`"
  end

  defp reject_app!(_), do: :ok

  defp plural(1), do: "y"
  defp plural(_), do: "ies"
end
