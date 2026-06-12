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

    test "sum-variant construction + patterns compile to tagged tuples / atoms" do
      {:ok, mod} =
        Beam.load(
          """
          type V := Num(Int64) | Zero
          def eval(v V) Int64
          def eval(Num(n)) := n * 2
          def eval(Zero) := 0
          """,
          :rian_beam_variant
        )

      # Num(n) -> {:num, n}, Zero -> :zero (tag = snake(Ctor))
      assert mod.eval({:num, 21}) == 42
      assert mod.eval(:zero) == 0
    end

    test "the full self-hosting lexer compiles to real bytecode (variants + FFI + recursion)" do
      {:ok, mod} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_lexer)

      assert mod.tokenize("1 + 2") == [{:t_num, 1}, :t_plus, {:t_num, 2}]
      assert {:file, _} = :code.is_loaded(:rian_beam_lexer)
    end

    test "a construct outside the core raises a clear Unsupported (never a miscompile)" do
      # struct declarations need %Name{} map forms (next increment)
      assert_raise Beam.Unsupported, ~r/struct/, fn ->
        Beam.compile("struct P(x Int64)\ndef o(n Int64) P := P(n)", :rian_beam_bad)
      end

      # String `<>` concatenation is not in this increment
      assert_raise Beam.Unsupported, fn ->
        Beam.compile("def g(a String, b String) String := a <> b", :rian_beam_bad2)
      end
    end
  end
end
