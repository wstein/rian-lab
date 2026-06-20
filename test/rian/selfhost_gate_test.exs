defmodule Rian.SelfhostGateTest do
  # async: false — `Rian.Lower.rust_program/1` is pure, but a few sources are large;
  # keeping this serial avoids contending with the toolchain suites for CPU.
  use ExUnit.Case, async: false

  # The self-host compiler is built to BEAM through `Rian.Beam.compile`/`load`, which run
  # ONLY `Rian.Reach.gate!` — they skip `Check.gate!` AND clause-exhaustiveness (the BEAM
  # emit is a low-level primitive; the type/exhaustiveness gates live at `Decl.compile`
  # and the portable emitters). So "self-hosts to BEAM" does not, by itself, type-check or
  # totality-check the compiler — a real divergence (SELFHOST.md): the BEAM path silently
  # accepts non-total and return-type-mismatched functions that the gated targets reject.
  #
  # These tests close the verified half of that gap (type-correctness is now enforced) and
  # ratchet the remaining half (totality — gated only by the Rust emitter) so it can only
  # shrink toward a Rust-self-hostable compiler.

  @sources Path.wildcard("compiler/*.rian")

  test "the corpus is non-empty (guard against a glob that silently matches nothing)" do
    assert length(@sources) >= 15
  end

  describe "type-correctness — the Check gate the BEAM path skips" do
    test "every compiler/*.rian passes Check.gate!, not just Reach" do
      failures =
        for f <- @sources,
            prog = Rian.Decl.parse(File.read!(f)),
            (r = check(prog)) != :ok,
            do: "#{Path.basename(f)}: #{r}"

      assert failures == [],
             "self-host type errors (BEAM accepts these, portable targets reject):\n" <>
               Enum.join(failures, "\n")
    end
  end

  describe "totality — non-total functions lower with a fallthrough, none refused (ADR-0034)" do
    # `Rian.Lower` (2da702a) now lowers a non-total TOP-LEVEL function with a runtime
    # fallthrough (`_ => panic!(…)`), matching how BEAM/JS/JVM throw at runtime, instead
    # of refusing it — so the self-host corpus has ZERO totality refusals (the prior
    # 9-entry ratchet bottomed out). A non-exhaustive `case` *inside a body* lowers the
    # same way (ADR-0036, 2026-06-20); the only remaining refusal is a dead/unreachable
    # clause. This guards that the corpus STAYS clean (`non_total_fn` reports any refusal).
    test "no compiler/*.rian function is refused for non-exhaustiveness" do
      refused =
        for f <- @sources, name = non_total_fn(f), name, do: {Path.basename(f), name}

      assert refused == [],
             "a self-host function is refused for non-exhaustiveness — give its `case` a " <>
               "total set of arms (a top-level `def` lowers with a fallthrough): " <>
               inspect(refused)
    end
  end

  # `Check.gate!` as a value (`:ok` or the error message), matching the gated targets.
  defp check(prog) do
    Rian.Check.gate!(prog)
    :ok
  rescue
    e in [Rian.Check.Error] -> Exception.message(e)
  end

  # the first non-total function `Rian.Lower`'s exhaustiveness gate reports for `file`
  # (its `check!` runs over every function before any emit, so a totality failure
  # surfaces ahead of any emit-`Unsupported`), or `nil` when the source is total.
  defp non_total_fn(file) do
    Rian.Lower.rust_program(Rian.Decl.parse(File.read!(file)))
    nil
  rescue
    e ->
      case Regex.run(~r/^non-exhaustive `([^`]+)`/, Exception.message(e)) do
        [_, name] -> name
        _ -> nil
      end
  end
end
