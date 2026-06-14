defmodule Rian.ReachRustHonestyTest do
  @moduledoc """
  Gate-honesty regression (ADR-0049 §5a · ADR-0057 · ADR-0061): `Rian.Reach` must
  not claim `:rs` for the integer-generic stdlib slices `17_stdlib_eq_ord` and
  `18_dict_eq` whose Rust the emitter cannot yet produce. Two real `Rian.Lower`
  gaps drive the pins:

    * **owned-generic return** — a generic returning `Vec(T)`/`T` (e.g. `insert`,
      `sort`, `maximum`, `get`) needs its `&T` params `.clone()`d into the owned
      result (and an owned local re-borrowed at a `&Self` protocol-method arg).
      The emitter does no such borrow→owned coercion → `rustc` E0308.
    * **parametric user type** — `type Pair := P(k K, v V)` lowers to `enum Pair {`
      with no `<K, V>` params, and the per-unit emitter repeats the def → duplicate
      `enum Pair` (E0428) + undeclared type params.

  Both are substantial emitter features, tracked as open items; until they land the
  honest move is for Reach to pin the affected functions off `:rs` so
  `mix rian.targets`/the conformance gate stop green-lighting Rust for code `rustc`
  rejects. The `@tag :rust` test ties the two together: it asserts `rustc` still
  *fails* on the emitted Rust — so if a future emitter fix makes it compile, this
  test fails and flags that the Reach blocker (and the conformance-corpus exclusion)
  should be lifted.

  The Bool-returning bounded generics (`contains`/`eq`/`lt`) and concrete protocol
  impls the emitter *does* lower keep `:rs` — guarding against over-blocking.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  defp reach(file),
    do: File.read!("examples/rian/#{file}.rian") |> Decl.parse() |> Reach.analyze()

  defp targets(rep, name), do: rep[name].reach |> MapSet.to_list() |> Enum.sort()
  defp blocker_kinds(rep, name), do: rep[name].blockers |> Enum.map(& &1.kind)

  describe "17_stdlib_eq_ord — Reach is honest about :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("17_stdlib_eq_ord")}

    test "a generic returning an owned type variable is pinned off :rs", %{rep: rep} do
      for f <- ~w(insert sort maximum) do
        refute :rs in targets(rep, f), "#{f} should not claim :rs (owned generic return)"
        assert :generic in blocker_kinds(rep, f), "#{f} should carry a :generic blocker"
      end
    end

    test "the off-:rs pin propagates to @test callers", %{rep: rep} do
      for f <- ~w(sort_orders sort_idempotent maximum_folds),
          do: refute(:rs in targets(rep, f), "#{f} inherits the off-:rs pin via its callees")
    end

    test "Bool-returning bounded generics / concrete impls keep :rs (no over-block)", %{rep: rep} do
      for f <- ~w(contains eq lt impl_eq_string_eq),
          do: assert(:rs in targets(rep, f), "#{f} lowers to Rust and must keep :rs")
    end
  end

  describe "18_dict_eq — Reach is honest about :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("18_dict_eq")}

    test "a signature over the parametric `Pair` type is pinned off :rs", %{rep: rep} do
      for f <- ~w(get has put sample names) do
        refute :rs in targets(rep, f), "#{f} should not claim :rs (parametric user type)"
        assert :generic in blocker_kinds(rep, f), "#{f} should carry a :generic blocker"
      end
    end

    test "every @test function is pinned off :rs (directly or via callees)", %{rep: rep} do
      for f <- ~w(get_finds_value get_returns_default put_shadows_earlier_key
                  has_present has_absent string_keys_work),
          do: refute(:rs in targets(rep, f), "#{f} must not green-light :rs")
    end
  end

  # The justification for the pins: rustc genuinely rejects the emitted Rust. If a
  # future Lower fix makes either compile, this test fails — lift the blocker and
  # promote the file into the Tier-1 conformance corpus.
  @tag :rust
  test "rustc still rejects the emitted Rust for both files (pin is justified)" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        for file <- ~w(17_stdlib_eq_ord 18_dict_eq) do
          src =
            Path.join(System.tmp_dir!(), "rian_honesty_#{System.unique_integer([:positive])}.rs")

          bin = String.trim_trailing(src, ".rs")
          File.write!(src, Test.rust(File.read!("examples/rian/#{file}.rian")))

          try do
            {_out, code} =
              System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
                stderr_to_stdout: true
              )

            assert code != 0,
                   "#{file}: rustc now COMPILES — lift the Reach :rs blocker and add it to the " <>
                     "conformance corpus"
          after
            File.rm(src)
            File.rm(bin)
          end
        end
    end
  end
end
