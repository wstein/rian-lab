defmodule Rian.ProtocolTest do
  # async: false — loads compiled modules into the VM.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl}
  alias Rian.Protocol.Error, as: CoherenceError

  defp load(src, mod) do
    {:ok, ^mod} = Beam.load(src, mod)
    mod
  end

  describe "protocol / impl dispatch on the BEAM (ADR-0042 part 2)" do
    test "a single-arg protocol (Show) dispatches by the receiver's runtime type" do
      m =
        load(
          """
          protocol Show do
            def show(self Self) String
          end

          impl Show for Bool do
            def show(b) := if b do "yes" else "no" end
          end

          impl Show for Int64 do
            def show(n) := "an int"
          end

          impl Show for String do
            def show(s) := s
          end
          """,
          :rian_proto_show
        )

      assert m.show(true) == "yes"
      assert m.show(false) == "no"
      assert m.show(42) == "an int"
      assert m.show("hi") == "hi"
    end

    test "a two-arg protocol (Eq) dispatches on the first argument" do
      m =
        load(
          """
          protocol Eq do
            def eq(a Self, b Self) Bool
          end

          impl Eq for Int64 do
            def eq(a, b) := a == b
          end
          """,
          :rian_proto_eq
        )

      assert m.eq(3, 3) == true
      assert m.eq(3, 4) == false
    end

    test "the impl methods are real callable functions under mangled names" do
      funcs =
        Decl.parse("""
        protocol Show do
          def show(self Self) String
        end

        impl Show for Int64 do
          def show(n) := "i"
        end
        """).funcs

      names = Enum.map(funcs, & &1.name) |> Enum.sort()
      assert names == ["impl_show_int64_show", "show"]
    end

    test "protocols work inside a module too" do
      [atom] =
        Beam.load_program("""
        mod Render do
          protocol Show do
            def show(self Self) String
          end

          impl Show for Bool do
            def show(b) := if b do "T" else "F" end
          end
        end
        """)

      assert atom.show(true) == "T"
      assert atom.show(false) == "F"
    end

    test "a method with a parametric-typed param (comma in the type) parses correctly" do
      # `Map(String, Int64)` is ONE parameter — the comma inside it must not be
      # counted as a parameter separator (paren-aware split)
      m =
        load(
          """
          protocol Keyed do
            def pick(self Self, m Map(String, Int64)) Int64
          end

          impl Keyed for Int64 do
            def pick(self, m) := self
          end

          def call(n Int64) Int64 := pick(n, %{})
          """,
          :rian_proto_parametric
        )

      assert m.call(42) == 42
    end
  end

  describe "the type gate accepts a well-typed protocol program" do
    test "Decl.compile passes the gate and emits the dispatcher + impl" do
      units =
        Decl.compile("""
        protocol Eq do
          def eq(a Self, b Self) Bool
        end

        impl Eq for Int64 do
          def eq(a, b) := a == b
        end
        """)

      assert Enum.map(units, &elem(&1, 0)) |> Enum.sort() == ["eq", "impl_eq_int64_eq"]
    end
  end

  describe "coherence (ADR-0042 §5)" do
    test "an impl for an unknown protocol is rejected" do
      assert_raise CoherenceError, ~r/unknown protocol `Nope`/, fn ->
        Decl.parse("impl Nope for Int64 do\n  def f(x) := x\nend\n")
      end
    end

    test "duplicate impls for the same (protocol, type) are rejected" do
      assert_raise CoherenceError, ~r/duplicate `impl P for Int64`/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def m(x) := true
        end

        impl P for Int64 do
          def m(x) := false
        end
        """)
      end
    end

    test "an impl whose methods do not match the protocol is rejected" do
      assert_raise CoherenceError, ~r/does not match the protocol/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def wrong(x) := true
        end
        """)
      end
    end

    test "two impl types sharing a runtime dispatch guard are rejected as ambiguous" do
      assert_raise CoherenceError, ~r/ambiguous dispatch/, fn ->
        Decl.parse("""
        protocol P do
          def m(self Self) Bool
        end

        impl P for Int64 do
          def m(x) := true
        end

        impl P for Char do
          def m(x) := false
        end
        """)
      end
    end

    test "an impl for a non-primitive type is rejected (MVP limit)" do
      assert_raise CoherenceError, ~r/non-primitive types is not yet supported/, fn ->
        Decl.parse("""
        type Color := Red | Green

        protocol Show do
          def show(self Self) String
        end

        impl Show for Color do
          def show(c) := "color"
        end
        """)
      end
    end
  end
end
