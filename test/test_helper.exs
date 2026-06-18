# External-toolchain tests are EXCLUDED from the default `mix test` for inner-loop
# speed. They spawn slow subprocesses — `@tag :jvm` (kotlinc + java; kotlinc's
# `-include-runtime` rebundles the Kotlin stdlib per test, the dominant cost),
# `@tag :rust` (rustc), `@tag :js` (node), `@tag :rebar` (rebar3) and `@tag :gradle`
# (gradle — native packaging, ADR-0082) — that together dominate the runtime.
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
# external-toolchain tags — it stays out of the default loop and back in `mix test.all`
# (but only when the `dialyzer` app is installed; see below).
# `:dialyzer` re-enters only when the `dialyzer` OTP app is actually installed
# (some OTP builds omit it); otherwise it stays excluded so `mix test.all` is green
# on that install. The availability guard itself is covered by untagged tests.
dialyzer? = match?({:module, _}, Code.ensure_loaded(:dialyzer))

exclude =
  cond do
    System.get_env("RIAN_TEST_ALL") != "1" ->
      [:rust, :js, :jvm, :rebar, :gradle, :dialyzer, :bench]

    dialyzer? ->
      [:bench]

    true ->
      [:bench, :dialyzer]
  end

ExUnit.start(exclude: exclude)
