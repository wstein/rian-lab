defmodule Rian.StdlibEqOrdTest do
  @moduledoc """
  The portable `Eq`/`Ord` stdlib slice (examples/rian/17_stdlib_eq_ord.rian) run
  *as Rian*: its `@test def`s and its `@doc` doctests each surface as an ExUnit
  case. This exercises the whole protocol stack end-to-end — bound enforcement
  (ADR-0042 §2) + runtime dispatch (§3) + the bounded-generic List ops — and
  fails the build if any of it (or a documented example) drifts.
  """
  use ExUnit.Case, async: false
  require Rian.Test
  require Rian.Doctest

  @src_path "examples/rian/17_stdlib_eq_ord.rian"

  # each `@test def` -> an ExUnit case
  Rian.Test.exunit("examples/rian/17_stdlib_eq_ord.rian")
  # each `expr #=> expected` doctest -> an ExUnit case
  Rian.Doctest.exunit("examples/rian/17_stdlib_eq_ord.rian")

  test "the stdlib's bounded-generic List ops run on the BEAM" do
    {:ok, m} = Rian.Beam.load(File.read!(@src_path), :rian_stdlib_eqord_direct)
    assert m.contains([1, 2, 3], 2) == true
    assert m.sort([5, 4, 3, 2, 1]) == [1, 2, 3, 4, 5]
    assert m.maximum([3, 7, 2, 5], 0) == 7
  end
end
