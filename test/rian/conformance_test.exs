defmodule Rian.ConformanceTest do
  @moduledoc """
  The **Tier-1 admission gate** (ADR-0049 §5a). The portable-core conformance
  corpus — `@test`-bearing example files whose tests reach *every* Tier-1 target —
  must be **green on each Tier-1 target on every commit**: `:ex` (BEAM), `:rs`
  (Rust), `:js` (ECMAScript). A Tier-1 regression fails the build; greenness is the
  gate, not a roadmap promise.

  How it works: each corpus file's `@test def`s are compiled and *run* per target —
  `:ex` via `Rian.Test.run/1` (BEAM), `:rs` via `rustc --test`, `:js` via
  `node --test` — and every test must pass. A `reach`-matrix check first asserts the
  tests actually reach all three targets, so a portability regression (a file
  drifting off a Tier-1 target) is caught even before the run.

  **JVM is Tier 2 and is deliberately NOT run here** (§5a rule 4): its MVP does not
  claim portable-core parity (lists/maps/`case`/FFI raise `Unsupported`), so it
  cannot pass this suite — the rule working as intended, not a gap to paper over.
  JVM's own subset is exercised by `jvm_test.exs`.

  Toolchain parity (ADR-0026): the `:rs`/`:js` runs no-op when `rustc`/`node` are
  absent (as in the Erlang-only CI image), exactly like the other shell-backed tests.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  # The portable-core conformance corpus: example files whose `@test`s reach ALL of
  # `:ex`/`:rs`/`:js`. Add a file here only once it is green on every Tier-1 target.
  # `17_stdlib_eq_ord`/`18_dict_eq` (the integer-generic Eq/Ord/Dict stdlib) joined once
  # the `Int53` literal default (ADR-0064) made them JS-portable and both Rust-generic
  # gaps closed (owned-from-borrowed coercion + parametric `enum Pair<K,V>`, ADR-0061),
  # so they are green on every Tier-1 target — run per target here, every commit.
  @corpus ~w(14_test_framework conformance_core 17_stdlib_eq_ord 18_dict_eq)

  @tier1 [:ex, :rs, :js]

  defp source(file), do: File.read!("examples/rian/#{file}.rian")

  defp test_names(src),
    do: Decl.parse(src).funcs |> Enum.filter(& &1.test?) |> Enum.map(& &1.name)

  for file <- @corpus do
    describe "#{file} — Tier-1 conformance (ADR-0049 §5a)" do
      test "its @tests reach every Tier-1 target (:ex, :rs, :js)" do
        src = source(unquote(file))
        rep = Reach.analyze(Decl.parse(src))
        names = test_names(src)
        assert names != [], "#{unquote(file)} has no @test defs to gate"

        for name <- names, target <- @tier1 do
          # `Reach.entry/2` resolves the bare @test name against the `"name/arity"`-
          # keyed report (raising clearly if a gated test name is somehow absent).
          reach = Reach.entry(rep, name)[:reach] |> MapSet.to_list()

          assert target in reach,
                 "portable-core regression: #{unquote(file)}.#{name} no longer reaches #{target} " <>
                   "(reaches #{inspect(Enum.sort(reach))})"
        end
      end

      test "its @tests pass on :ex (BEAM)" do
        results = Test.run(source(unquote(file)))

        assert Enum.all?(results, fn {_n, r} -> r == :pass end),
               "failed on :ex: #{inspect(results)}"
      end

      @tag :rust
      test "its @tests pass on :rs (rustc --test)" do
        assert_target_runs(:rs, unquote(file))
      end

      @tag :js
      test "its @tests pass on :js (node --test)" do
        assert_target_runs(:js, unquote(file))
      end
    end
  end

  # ── per-target run (skips when the toolchain is absent — CI-parity) ──────────
  defp assert_target_runs(:rs, file) do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        src = Path.join(System.tmp_dir!(), "rian_conf_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(src, ".rs")
        File.write!(src, Test.rust(source(file)))

        try do
          {out, code} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
              stderr_to_stdout: true
            )

          assert code == 0, "#{file}: rustc failed:\n#{out}"
          {run, rc} = System.cmd(bin, [])
          assert rc == 0, "#{file}: rust tests exited #{rc}:\n#{run}"
          refute run =~ ~r/\b[1-9]\d* failed/, "#{file}: a rust test failed:\n#{run}"
        after
          File.rm(src)
          File.rm(bin)
        end
    end
  end

  defp assert_target_runs(:js, file) do
    case System.find_executable("node") do
      nil ->
        :ok

      node ->
        path = Path.join(System.tmp_dir!(), "rian_conf_#{System.unique_integer([:positive])}.mjs")
        File.write!(path, Test.js(source(file)))

        try do
          {out, code} = System.cmd(node, ["--test", path], stderr_to_stdout: true)
          assert code == 0, "#{file}: node --test exited #{code}:\n#{out}"
          refute out =~ ~r/\bfail [1-9]/, "#{file}: a JS test failed:\n#{out}"
        after
          File.rm(path)
        end
    end
  end
end
