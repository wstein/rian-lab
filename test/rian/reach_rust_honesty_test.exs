defmodule Rian.ReachRustHonestyTest do
  @moduledoc """
  Gate-honesty regression (ADR-0049 §5a · ADR-0057 · ADR-0061): `Rian.Reach`'s `:rs`
  claims for the integer-generic stdlib slices must match what `Rian.Lower` can emit.

  Two `Rian.Lower` gaps drove the historical pins:

    * **owned-generic return** — a generic returning `Vec(T)`/`T` (`insert`/`sort`/
      `maximum`/`get`) needs its `&T` params `.clone()`d into the owned result and an
      owned local re-borrowed (`&`) at a `&T`/`&Self` call arg. **Implemented** — the
      owned↔borrow coercion (`Rian.Lower`: `borrow_arg`/`borrow_value`/`rust_owned_elem`
      + the bare-tvar return clone, gated on a generic function). `17_stdlib_eq_ord`
      now compiles to and runs on Rust, so Reach no longer pins it off `:rs`.
    * **parametric user type** — `type Pair := P(k K, v V)` lowers to `enum Pair {`
      with no `<K, V>` params (E0425/E0428). **Still open**, so any signature over
      `Pair` (the `18_dict_eq` slice) stays honestly pinned off `:rs`.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  defp reach(file),
    do: File.read!("examples/rian/#{file}.rian") |> Decl.parse() |> Reach.analyze()

  defp targets(rep, name), do: rep[name].reach |> MapSet.to_list() |> Enum.sort()
  defp blocker_kinds(rep, name), do: rep[name].blockers |> Enum.map(& &1.kind)

  describe "17_stdlib_eq_ord — owned-generic return now reaches :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("17_stdlib_eq_ord")}

    test "the owned-generic-return functions now reach :rs (the coercion landed)", %{rep: rep} do
      for f <- ~w(insert sort maximum contains eq3) do
        assert :rs in targets(rep, f), "#{f} now lowers to Rust and must claim :rs"
        refute :generic in blocker_kinds(rep, f), "#{f} should carry no :generic blocker"
      end
    end

    test "every function in the slice reaches :rs (no residual pin)", %{rep: rep} do
      for {name, info} <- rep do
        assert :rs in (info.reach |> MapSet.to_list()),
               "#{name} should reach :rs — the slice is fully Rust-portable now"
      end
    end
  end

  describe "18_dict_eq — the parametric `Pair` type is still off :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("18_dict_eq")}

    test "a signature over the parametric `Pair` type is pinned off :rs", %{rep: rep} do
      for f <- ~w(get has put sample names) do
        refute :rs in targets(rep, f), "#{f} should not claim :rs (parametric user type, gap 2)"
        assert :generic in blocker_kinds(rep, f), "#{f} should carry a :generic blocker"
      end
    end

    test "every @test function is pinned off :rs (directly or via callees)", %{rep: rep} do
      for f <- ~w(get_finds_value get_returns_default put_shadows_earlier_key
                  has_present has_absent string_keys_work),
          do: refute(:rs in targets(rep, f), "#{f} must not green-light :rs")
    end
  end

  # 17 is justified ON :rs — rustc compiles AND runs its `@test`s.
  @tag :rust
  test "rustc compiles and runs 17_stdlib_eq_ord's @tests (the :rs claim is real)" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        src = Path.join(System.tmp_dir!(), "rian_h17_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(src, ".rs")
        File.write!(src, Test.rust(File.read!("examples/rian/17_stdlib_eq_ord.rian")))

        try do
          {out, code} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
              stderr_to_stdout: true
            )

          assert code == 0, "17 should compile on rustc now:\n#{out}"
          {run, rc} = System.cmd(bin, [])
          assert rc == 0, "17's @tests should pass under rustc --test:\n#{run}"
        after
          File.rm(src)
          File.rm(bin)
        end
    end
  end

  # 18 is justified OFF :rs — rustc still rejects its parametric `Pair` emit. If a
  # future Lower fix makes it compile, this fails — lift the blocker and promote it.
  @tag :rust
  test "rustc still rejects 18_dict_eq (the parametric-type pin is justified)" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        src = Path.join(System.tmp_dir!(), "rian_h18_#{System.unique_integer([:positive])}.rs")
        bin = String.trim_trailing(src, ".rs")
        File.write!(src, Test.rust(File.read!("examples/rian/18_dict_eq.rian")))

        try do
          {_out, code} =
            System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
              stderr_to_stdout: true
            )

          assert code != 0,
                 "18 now COMPILES — implement parametric enums, lift the Reach :rs blocker, " <>
                   "and add it to the conformance corpus"
        after
          File.rm(src)
          File.rm(bin)
        end
    end
  end
end
