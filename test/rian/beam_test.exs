defmodule Rian.BeamTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  describe "Erlang abstract-forms backend (ADR-0031) — real :compile.forms bytecode" do
    test "a one-liner compiles to loadable bytecode and runs" do
      {:ok, mod} = Beam.load("def double(n Int64) Int64 := n * 2", :rian_beam_double)
      assert mod.double(21) == 42
      assert {:file, _} = :code.is_loaded(:rian_beam_double)
    end

    test "multi-clause with a `when` guard" do
      {:ok, mod} =
        Beam.load(
          """
          def max2(a Int64, b Int64) Int64
          def max2(a, b) when a >= b := a
          def max2(_, b) := b
          """,
          :rian_beam_max2
        )

      assert mod.max2(3, 7) == 7
      assert mod.max2(9, 2) == 9
    end

    test "cons-list recursion (the self-hosting shape) compiles to real bytecode" do
      {:ok, mod} =
        Beam.load(
          """
          def sum(xs Vec(Int64)) Int64
          def sum([]) := 0
          def sum([h | t]) := h + sum(t)
          """,
          :rian_beam_sum
        )

      assert mod.sum([1, 2, 3, 4]) == 10
      assert mod.sum([]) == 0
    end

    test "`case` over literals and an `if` expression compile and run" do
      {:ok, mod} =
        Beam.load(
          """
          def sign(n Int64) Int64
            case n do
              0 -> 0
              _ -> if n > 0 do 1 else 0 end
            end
          end
          """,
          :rian_beam_sign
        )

      assert mod.sign(0) == 0
      assert mod.sign(5) == 1
      assert mod.sign(-3) == 0
    end

    test "a construct outside the core raises a clear Unsupported (never a miscompile)" do
      # sum-variant construction needs the variant→tagged-tuple meta (next increment)
      assert_raise Beam.Unsupported, ~r/constructor\/type `Red`/, fn ->
        Beam.compile("type C := Red | Green\ndef pick(b Bool) C := Red", :rian_beam_bad)
      end

      # String literals / `<>` are not in this increment either
      assert_raise Beam.Unsupported, fn ->
        Beam.compile(~s|def g(n Int64) String := "hi"|, :rian_beam_bad2)
      end
    end
  end
end
