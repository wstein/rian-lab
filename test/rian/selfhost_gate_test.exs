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

  describe "totality — the exhaustiveness gate only the Rust emitter enforces" do
    # The BEAM path accepts these non-total functions; the Rust emitter (`Rian.Lower`)
    # rejects them, so each is a blocker on the road to Rust self-hosting. Listed as a
    # ratchet: the set may only SHRINK (make a function total, then drop it here).
    @known_non_total MapSet.new([
                       {"beam.rian", "i64_project"},
                       {"cap.rian", "scalar"},
                       {"checker.rian", "bin_ty"},
                       {"decl.rian", "parse_fldpats"},
                       {"js.rian", "init_of"},
                       {"jvm.rian", "init_of"},
                       {"lexer_v2.rian", "scan_hole"},
                       {"parse.rian", "parse_paren"},
                       {"rust.rian", "named_fields"}
                     ])

    test "no NEW non-total self-host function appears (ratchet toward Rust-total)" do
      found =
        MapSet.new(
          for f <- @sources, fn_name = non_total_fn(f), fn_name, do: {Path.basename(f), fn_name}
        )

      new = MapSet.difference(found, @known_non_total)

      assert MapSet.size(new) == 0,
             "new non-total self-host function(s) — make them total or update the baseline: " <>
               inspect(MapSet.to_list(new))
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
