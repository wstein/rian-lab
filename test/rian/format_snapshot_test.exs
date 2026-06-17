defmodule Rian.FormatSnapshotTest do
  use ExUnit.Case, async: true

  alias Rian.Format

  @moduledoc """
  Snapshot (golden-file) tests for the formatter — `gofmt`'s `testdata/*.golden`
  model (ADR-0045/ADR-0077). Each case is a pair under `test/rian/fixtures/format/`:

      <name>.in.rian    — a deliberately messy-but-valid input
      <name>.out.rian   — the committed, human-reviewed idiomatic output

  These are the one thing the property tests (idempotence, significant-token
  equivalence, ≤98 cols — `format_test.exs`/`format_property_test.exs`) cannot
  assert: that a given input produces the *exact readable* output we intend. They
  double as executable documentation of the canonical style.

  Each snapshot is *layered on* the safety invariants, so a golden file can never
  silently encode an unsound or unstable output:

    * `format(in)  == out`  — the snapshot itself,
    * `format(out) == out`  — idempotence (the output is a fixed point), and
    * the inputs are also swept by `format_test.exs`'s significant-token oracle
      (its `@corpus` includes `fixtures/format/*.in.rian`), so meaning is proven
      preserved — a golden file is never a license to change the program.

  Regenerate after an intentional style change and **review the diff** (never
  rubber-stamp it):

      RIAN_FORMAT_SNAPSHOT_UPDATE=1 mix test test/rian/format_snapshot_test.exs
  """

  @dir Path.join([__DIR__, "fixtures", "format"])
  @inputs Path.wildcard(Path.join(@dir, "*.in.rian"))

  test "there are snapshot fixtures (guards against a bad glob)" do
    assert @inputs != [], "no *.in.rian fixtures under #{@dir}"
  end

  for input <- @inputs do
    @input input
    @golden String.replace_suffix(input, ".in.rian", ".out.rian")
    name = input |> Path.basename(".in.rian")

    test "snapshot: #{name}" do
      formatted = Format.format(File.read!(@input))

      if System.get_env("RIAN_FORMAT_SNAPSHOT_UPDATE") == "1" do
        File.write!(@golden, formatted)
      else
        assert File.exists?(@golden),
               "missing golden file #{@golden} — run with RIAN_FORMAT_SNAPSHOT_UPDATE=1"

        assert formatted == File.read!(@golden),
               "formatted output drifted from the golden file. If intentional, " <>
                 "regenerate with RIAN_FORMAT_SNAPSHOT_UPDATE=1 and review the diff."

        # the golden output is itself a fixed point of the formatter
        assert Format.format(formatted) == formatted, "golden output is not idempotent"
      end
    end
  end
end
