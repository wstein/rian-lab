# External-toolchain tests are EXCLUDED from the default `mix test` for inner-loop
# speed. They spawn slow subprocesses — `@tag :jvm` (kotlinc + java; kotlinc's
# `-include-runtime` rebundles the Kotlin stdlib per test, the dominant cost),
# `@tag :rust` (rustc), `@tag :js` (node) — that together dominate the runtime.
# They are NOT dropped:
#
#   mix test.all                 # everything; the enforced CI gate (sets RIAN_TEST_ALL=1)
#   mix test --include jvm       # add one toolchain back (rust | js | jvm)
#
# `mix test.all` sets RIAN_TEST_ALL=1 to opt the whole set back in. Coverage
# (`mix test --cover`, threshold 95) must be measured this way — the toolchain
# tests exercise the Rust/JVM emitters, so the honest number is `mix test.all --cover`.
exclude = if System.get_env("RIAN_TEST_ALL") == "1", do: [], else: [:rust, :js, :jvm]

ExUnit.start(exclude: exclude)
