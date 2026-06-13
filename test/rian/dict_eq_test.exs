defmodule Rian.DictEqTest do
  @moduledoc """
  The `Dict` over `Eq` (examples/rian/18_dict_eq.rian) run as Rian: its `@test`
  proofs and `@doc` doctests each surface as an ExUnit case. Exercises bounded
  generics (`forall K: Eq`) + protocol dispatch + a generic `Pair(k K, v V)`
  end-to-end, and fails the build if any of it (or a documented example) drifts.
  """
  use ExUnit.Case, async: false
  require Rian.Test
  require Rian.Doctest

  @src_path "examples/rian/18_dict_eq.rian"

  Rian.Test.exunit("examples/rian/18_dict_eq.rian")
  Rian.Doctest.exunit("examples/rian/18_dict_eq.rian")

  test "the Dict runs on the BEAM with Int64 and String keys" do
    {:ok, m} = Rian.Beam.load(File.read!(@src_path), :rian_dict_eq_direct)
    assert m.demo_get_hit() == 20
    assert m.demo_get_miss() == -1
    assert m.demo_has() == true
    assert m.demo_absent() == false
    assert m.demo_string_key() == 2
  end

  test "the `K: Eq` bound is enforced — a key type without `Eq` is rejected" do
    src =
      File.read!(@src_path) <> "\ndef lookup_bool(b Bool) Bool := has(sample(), b)\n"

    assert_raise Rian.Check.Error, ~r/`has` requires `K: Eq`.*no `impl Eq for Bool`/, fn ->
      Rian.Decl.compile(src)
    end
  end
end
