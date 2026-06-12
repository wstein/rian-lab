defmodule Rian.CheckTest do
  use ExUnit.Case, async: true

  alias Rian.{Check, Pratt}

  describe "unification kernel" do
    test "equal unifies; unknown unifies with anything; differing concretes mismatch" do
      assert Check.unify("Int64", "Int64") == "Int64"
      assert Check.unify(:unknown, "Bool") == "Bool"
      assert Check.unify("String", :unknown) == "String"
      assert Check.unify("Int64", "Bool") == :mismatch
    end
  end

  describe "literal and operator inference" do
    defp t(src), do: Check.infer(Pratt.parse(src))

    test "literals" do
      assert t("42") == "Int64"
      assert t("3.14") == "Float64"
      assert t("\"hi\"") == "String"
      assert t("true") == "Bool"
    end

    test "operators carry their result type" do
      assert t("a < b") == "Bool"
      assert t("a and b") == "Bool"
      assert t("a <> b") == "String"
      assert t("a / b") == "Float64"
      assert t("a div b") == "Int64"
    end

    test "arithmetic unifies operands; mixed/unknown is conservative (not an error)" do
      assert Check.infer(Pratt.parse("x + 1"), %{"x" => "Int64"}) == "Int64"
      # mixing int and float does not crash the checker — it infers `:unknown`
      assert t("1 + 2.0") == :unknown
      # an unknown operand keeps the known type
      assert t("x + 1") == "Int64"
    end

    test "calls and unknown names infer :unknown (conservative)" do
      assert t("g(x)") == :unknown
      assert t("x") == :unknown
    end
  end

  describe "function return-type checking (via parsed source)" do
    test "a consistent return type passes" do
      assert Check.check("def double(n Int64) Int64 := n * 2") == :ok
    end

    test "a proven mismatch is reported" do
      assert {:error, msg} = Check.check("def f(n Int64) Bool := n + 1")
      assert msg =~ "type `Int64`"
      assert msg =~ "declared return type is `Bool`"
    end

    test "bodies it cannot pin down pass (conservative — never rejects valid code)" do
      # constructor-pattern clauses bind vars of unknown type -> :unknown -> ok
      assert Check.check("""
             type Shape := Circle(radius Float64) | Square(side Float64)

             def area(s val Shape) Float64
             def area(Circle(r)) := pi * r * r
             def area(Square(s)) := s * s
             """) == :ok

      # an FFI body is opaque to inference -> ok
      assert Check.check("def total(xs val Vec(Int64)) Int64 := :lists.sum(xs)") == :ok
    end

    test "a String return with a literal string body passes" do
      assert Check.check(~s|def name(n Int64) String := "n"|) == :ok
    end
  end

  describe "flow narrowing (ADR-0034 pillar 4)" do
    @shape "type Shape := Circle(radius Float64) | Square(side Float64)\n"

    test "a clause head narrows a constructor's bound variable to its field type" do
      # r is refined to Float64, so the first clause proves Float64 — contradicting Bool.
      assert {:error, msg} =
               Check.check("""
               #{@shape}
               def f(Shape) Bool
               def f(Circle(r)) := r
               def f(Square(s)) := true
               """)

      assert msg =~ "type `Float64`"
      assert msg =~ "`Bool`"
    end

    test "a case arm narrows the scrutinee's variant fields" do
      assert {:error, msg} =
               Check.check("""
               #{@shape}
               def describe(s val Shape) Bool
                 case s do
                   Circle(r) -> r
                   Square(x) -> x
                 end
               end
               """)

      assert msg =~ "type `Float64`"
    end

    test "narrowing lets a correct case/clause body pass (was :unknown before)" do
      assert Check.check("""
             #{@shape}
             def area(s val Shape) Float64
               case s do
                 Circle(r) -> 3.14 * r * r
                 Square(x) -> x * x
               end
             end
             """) == :ok
    end
  end

  describe "the type gate fires at compile time" do
    test "Decl.compile refuses a proven return-type mismatch" do
      assert_raise Check.Error, ~r/declared return type is `Bool`/, fn ->
        Rian.Decl.compile("def f(n Int64) Bool := n + 1")
      end
    end

    test "a well-typed program compiles through the gate" do
      assert [{"double", _}] = Rian.Decl.compile("def double(n Int64) Int64 := n * 2")
    end

    test "the gate also checks functions inside a module" do
      assert_raise Check.Error, ~r/declared return type is `Bool`/, fn ->
        Rian.Decl.compile("""
        mod M do
          pub def f(n Int64) Bool := n + 1
        end
        """)
      end
    end
  end
end
