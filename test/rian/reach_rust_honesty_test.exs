defmodule Rian.ReachRustHonestyTest do
  @moduledoc """
  Gate-honesty regression (ADR-0049 §5a · ADR-0057 · ADR-0061): `Rian.Reach`'s `:rs`
  claims for the integer-generic stdlib slices match what `Rian.Lower` can emit.

  Both historical Rust-generic gaps are now closed and both slices compile to and run
  on Rust, so Reach claims `:rs` for them:

    * **owned-from-borrowed coercion** (`insert`/`sort`/`maximum`/`get`) — `Rian.Lower`
      clones a returned `&T`, `&`-borrows owned call/element args, and clones elements
      stored into an owned `Vec` (gated on a generic function).
    * **parametric user type** — `type Pair := P(k K, v V)` lowers to `enum Pair<K, V>`;
      a generic function reuses the param names (`Pair<K, V>`, plus any free tvar like
      `has`'s `V`), and a non-generic builder (`sample`/`names`) gets its concrete
      instantiation (`Pair<i64, i64>` / `Pair<String, i64>`) inferred from its body.

  The `@tag :rust` cases tie the matrix to reality: both slices must `rustc --test` green.
  """
  use ExUnit.Case, async: false

  alias Rian.{Decl, Reach, Test}

  defp reach(file),
    do: File.read!("examples/rian/#{file}.rian") |> Decl.parse() |> Reach.analyze()

  defp targets(rep, name), do: rep[name].reach |> MapSet.to_list() |> Enum.sort()
  defp blocker_kinds(rep, name), do: rep[name].blockers |> Enum.map(& &1.kind)

  describe "17_stdlib_eq_ord — owned-generic return reaches :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("17_stdlib_eq_ord")}

    test "the owned-generic-return functions reach :rs (the coercion landed)", %{rep: rep} do
      for f <- ~w(insert sort maximum contains eq3) do
        assert :rs in targets(rep, f), "#{f} lowers to Rust and must claim :rs"
        refute :generic in blocker_kinds(rep, f), "#{f} should carry no :generic blocker"
      end
    end

    test "every function in the slice reaches :rs", %{rep: rep} do
      for {name, info} <- rep,
          do: assert(:rs in (info.reach |> MapSet.to_list()), "#{name} should reach :rs")
    end
  end

  describe "18_dict_eq — the parametric `Pair` type reaches :rs (ADR-0061)" do
    setup do: {:ok, rep: reach("18_dict_eq")}

    test "signatures over the parametric `Pair` type reach :rs (enum Pair<K,V> landed)", %{
      rep: rep
    } do
      for f <- ~w(get has put sample names) do
        assert :rs in targets(rep, f), "#{f} lowers over `enum Pair<K,V>` and must claim :rs"
        refute :generic in blocker_kinds(rep, f), "#{f} should carry no :generic blocker"
      end
    end

    test "every @test function reaches :rs", %{rep: rep} do
      for f <- ~w(get_finds_value get_returns_default put_shadows_earlier_key
                  has_present has_absent string_keys_work),
          do: assert(:rs in targets(rep, f), "#{f} should reach :rs")
    end
  end

  # The :rs claims are justified — rustc compiles AND runs each slice's `@test`s.
  @tag :rust
  test "rustc compiles and runs the @tests of both Rust-portable stdlib slices" do
    case System.find_executable("rustc") do
      nil ->
        :ok

      rustc ->
        for file <- ~w(17_stdlib_eq_ord 18_dict_eq) do
          src = Path.join(System.tmp_dir!(), "rian_h_#{System.unique_integer([:positive])}.rs")
          bin = String.trim_trailing(src, ".rs")
          File.write!(src, Test.rust(File.read!("examples/rian/#{file}.rian")))

          try do
            {out, code} =
              System.cmd(rustc, ["--test", "-A", "warnings", "--edition", "2021", src, "-o", bin],
                stderr_to_stdout: true
              )

            assert code == 0, "#{file} should compile on rustc:\n#{out}"
            {run, rc} = System.cmd(bin, [])
            assert rc == 0, "#{file}'s @tests should pass under rustc --test:\n#{run}"
          after
            File.rm(src)
            File.rm(bin)
          end
        end
    end
  end
end
