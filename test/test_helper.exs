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
#
# `@tag :bench` is a performance-TRACKING test (prints v1/v2/Rian.Beam compile
# times), not a correctness gate — its timings are noisy and it builds the compiler
# twice. It is excluded from BOTH the default loop AND `mix test.all`, and runs only
# on demand:  mix test --include bench
#
# `@tag :dialyzer` runs the external Dialyzer oracle (`mix rian.dialyze`, ADR-0026):
# it needs the `dialyzer` OTP app and a one-time PLT build (slow), so — like the other
# external-toolchain tags — it stays out of the default loop and back in `mix test.all`.
exclude =
  if System.get_env("RIAN_TEST_ALL") == "1",
    do: [:bench],
    else: [:rust, :js, :jvm, :dialyzer, :bench]

ExUnit.start(exclude: exclude)
