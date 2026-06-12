defmodule Rian.CheckTest do
  # async: false — exercises `Rian.Decl.compile`, which touches the global VM
  # (compiler/code server); concurrent module compilation races otherwise.
  use ExUnit.Case, async: false

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

  describe "typed bindings (ADR-0034 §1)" do
    test "a numeric literal adopts the declared width" do
      assert Check.check("def f(n Int64) Int64 := x Int32 := 66 ; n") == :ok
    end

    test "a typed binding displays at its declared type, not the inferred one" do
      # the final expression is `x`, so the block's type is `x`'s declared `Int32`
      assert Check.infer(Pratt.parse_body("x Int32 := 66 ; x")) == "Int32"
    end

    test "an integer literal does not adopt a non-numeric annotation" do
      assert {:error, msg} = Check.check("def f(n Int64) Int64 := b Bool := 66 ; n")
      assert msg =~ "declared `Bool`"
      assert msg =~ "type `Int64`"
    end

    test "an integer literal does not adopt a float annotation (write an explicit float)" do
      assert {:error, _} = Check.check("def f(n Int64) Int64 := x Float64 := 66 ; n")
    end

    test "an already-typed value must unify exactly — no implicit narrow" do
      # `n` is Int64; binding it at Int32 is a proven mismatch
      assert {:error, msg} = Check.check("def f(n Int64) Int64 := x Int32 := n ; n")
      assert msg =~ "declared `Int32`"
    end

    test "an already-typed value matching its annotation passes" do
      assert Check.check("def f(n Int64) Int64 := x Int64 := n ; x") == :ok
    end

    test "an already-typed value widens losslessly into a wider annotation (ADR-0034 §1)" do
      # Int32 -> Int64 (same signedness, wider)
      assert Check.check("def f(n Int32) Int64 := x Int64 := n ; x") == :ok
      # UInt32 -> Int64 (unsigned range fits signed)
      assert Check.check("def f(n UInt32) Int64 := x Int64 := n ; x") == :ok
      # Int32 -> Float64 (exactly representable)
      assert Check.check("def f(n Int32) Float64 := x Float64 := n ; x") == :ok

      # but lossy/narrowing widths are still proven mismatches
      assert {:error, _} = Check.check("def f(n UInt32) Int32 := x Int32 := n ; x")
      assert {:error, _} = Check.check("def f(n Int64) Float64 := x Float64 := n ; x")
    end

    test "the return type also accepts a losslessly-wider body" do
      assert Check.check("def g(n Int32) Int64 := n") == :ok
      assert {:error, _} = Check.check("def g(n Int64) Int32 := n")
    end

    test "a string value is checked against its annotation" do
      assert Check.check(~s|def f(n Int64) String := s String := "hi" ; s|) == :ok
      assert {:error, _} = Check.check(~s|def f(n Int64) Int64 := x Int32 := "hi" ; n|)
    end

    test "an arithmetic RHS stays conservative (no false mismatch)" do
      # `x` is Int32, so `x + 1` is Int32-vs-Int64 — conservative `:unknown`, not an error
      assert Check.check("def f(n Int64) Int64 := x Int32 := 5 ; y Int32 := x + 1 ; n") == :ok
    end

    test "a parametric annotation is enforced against the inferred element type" do
      assert Check.check("def f(n Int64) Int64 := xs Vec(Int64) := [1, 2, 3] ; n") == :ok

      assert {:error, msg} = Check.check("def f(n Int64) Int64 := xs Vec(Bool) := [1, 2, 3] ; n")
      assert msg =~ "declared `Vec(Bool)`"
      assert msg =~ "type `Vec(Int64)`"
    end

    test "a parametric binding displays at its declared type" do
      assert Check.infer(Pratt.parse_body("xs Vec(Int64) := [1, 2, 3] ; xs")) == "Vec(Int64)"
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

  describe "error-set composition (ADR-0040 §4)" do
    test "an error tag in the declared `T | E` set passes" do
      assert Check.check("def find(id Int64) User | NotFound := {:error, NotFound}") == :ok
    end

    test "constructing an error outside the declared set is rejected" do
      assert {:error, msg} =
               Check.check("def find(id Int64) User | NotFound := {:error, Timeout}")

      assert msg =~ "Timeout"
      assert msg =~ "declared set `NotFound`"
    end

    test "a named error set expands to its tags (subset is allowed)" do
      assert Check.check("""
             type LookupError := NotFound | Timeout
             def look(id Int64) User | LookupError := {:error, Timeout}
             """) == :ok
    end

    test "a tag outside a named error set is rejected" do
      assert {:error, msg} =
               Check.check("""
               type LookupError := NotFound | Timeout
               def look(id Int64) User | LookupError := {:error, Other}
               """)

      assert msg =~ "Other"
      assert msg =~ "`LookupError`"
    end

    test "the error-set gate fires through Decl.compile" do
      assert_raise Check.Error, ~r/not in its declared set/, fn ->
        Rian.Decl.compile("def f(n Int64) Int64 | NotFound := {:error, Nope}")
      end
    end

    test "a non-Result return type is unconstrained by the error-set check" do
      assert Check.check("def g(n Int64) Int64 := n + 1") == :ok
    end

    test "a propagated callee's error set is inferred into the caller's produced set" do
      # `outer` constructs no error itself; it `with`-propagates `inner`'s `A`,
      # which must therefore appear in `outer`'s declared set.
      assert Check.check("""
             type E := A | B
             def inner(n Int64) Int64 | E := {:error, A}
             def outer(n Int64) Int64 | E
               with {:ok, x} <- inner(n) do
                 {:ok, x}
               end
             end
             """) == :ok
    end

    test "an under-declared caller is rejected for a propagated callee error" do
      assert {:error, msg} =
               Check.check("""
               type E := A | B
               def inner(n Int64) Int64 | A := {:error, A}
               def outer(n Int64) Int64 | B
                 with {:ok, x} <- inner(n) do
                   {:ok, x}
                 end
               end
               """)

      assert msg =~ "outer"
      assert msg =~ "A"
      assert msg =~ "declared set `B`"
    end

    test "a with-else that handles the failure under-approximates (no propagation)" do
      # The `else` clause consumes `inner`'s `A` and re-emits only `B`, so
      # `outer` produces `{B}` ⊆ its declared `{B}`.
      assert Check.check("""
             type E := A | B
             def inner(n Int64) Int64 | A := {:error, A}
             def outer(n Int64) Int64 | B
               with {:ok, x} <- inner(n) do
                 {:ok, x}
               else
                 {:error, _} -> {:error, B}
               end
             end
             """) == :ok
    end
  end

  describe "parametric / generic inference (ADR-0042, BEAM-first)" do
    test "a list literal infers Vec(elem); a wrong declared list type is caught" do
      assert Check.check("def xs(n Int64) Vec(Int64) := [1, 2, 3]") == :ok
      assert {:error, msg} = Check.check("def xs(n Int64) Vec(Bool) := [1, 2, 3]")
      assert msg =~ "Vec(Int64)"
      assert msg =~ "Vec(Bool)"
    end

    test "a variant value infers its sum type" do
      assert Check.check("type Color := Red | Green\ndef pick(b Bool) Color := Red") == :ok

      assert {:error, msg} =
               Check.check("type Color := Red | Green\ndef pick(b Bool) Int64 := Red")

      assert msg =~ "Color"
    end

    test "a call infers the callee's declared return type" do
      assert {:error, msg} =
               Check.check("def one(n Int64) Int64 := 1\ndef g(n Int64) Bool := one(n)")

      assert msg =~ "Int64"
      assert msg =~ "Bool"
    end

    test "cons of a variant and a recursive call checks as Vec(T) — the lexer shape" do
      assert Check.check("""
             type Tok := A
             def lex(xs Vec(Int64)) Vec(Tok)
             def lex([]) := []
             def lex([_ | r]) := [A | lex(r)]
             """) == :ok
    end

    test "a `forall` binder makes the function generic (parsed; checked conservatively)" do
      %{funcs: [f]} = Rian.Decl.parse("def id(x T) T forall T := x")
      assert f.tvars == ["T"]
      assert Check.check("def id(x T) T forall T := x") == :ok
    end

    test "a `forall` bound parses the variable (bound dropped for now)" do
      %{funcs: [f]} = Rian.Decl.parse("def srt(xs Vec(T)) Vec(T) forall T: Comparable := xs")
      assert f.tvars == ["T"]
    end
  end

  describe "function types & higher-order inference (ADR-0042)" do
    test "a lambda infers an arrow type `Fn(args.., body)`; un-annotated args are `_`" do
      assert Check.infer(Pratt.parse("(x) -> x and false")) == "Fn(_,Bool)"
      assert Check.infer(Pratt.parse("(x) -> x + 1")) == "Fn(_,Int64)"
    end

    test "Fn types unify structurally — wildcard slots reconcile, real clashes don't" do
      assert Check.unify("Fn(_,Int64)", "Fn(Int64,Int64)") == "Fn(Int64,Int64)"
      assert Check.unify("Fn(_,Int64)", "Fn(Int64,Bool)") == :mismatch
      # differing arity never unifies
      assert Check.unify("Fn(Int64,Bool)", "Fn(Int64)") == :mismatch
    end

    test "applying a function-typed parameter infers the function's return type" do
      assert Check.check("def app(f Fn(Int64, Bool)) Bool := f(2)") == :ok

      assert {:error, msg} = Check.check("def app(f Fn(Int64, Bool)) Int64 := f(2)")
      assert msg =~ "type `Bool`"
      assert msg =~ "declared return type is `Int64`"
    end

    test "a returned lambda is checked against the declared Fn return type" do
      assert Check.check("def mk(n Int64) Fn(Int64, Int64) := (x) -> x + 1") == :ok

      assert {:error, msg} = Check.check("def mk(n Int64) Fn(Int64, Bool) := (x) -> x + 1")
      assert msg =~ "Fn(_,Int64)"
      assert msg =~ "Fn(Int64,Bool)"
    end

    test "`&name/arity` captures a known function as `Fn(_ × arity, return)`" do
      assert Check.infer(Pratt.parse("&dbl/1"), %{}, %{funs: %{"dbl" => "Int64"}}) ==
               "Fn(_,Int64)"
    end

    test "the ADR-0042 higher-order `map` signature parses and checks (Fn param + Vec)" do
      src = "def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U := []"
      assert Check.check(src) == :ok

      %{funcs: [f]} = Rian.Decl.parse(src)
      assert [%{name: "f", type: "Fn(T,U)"}, %{name: "xs", type: "Vec(T)"}] = f.params
    end

    test "calling a generic function yields `:unknown`, not its literal `Vec(U)`" do
      # `map` returns `Vec(U)`; we don't instantiate generics, so a concrete
      # caller must NOT be contradicted by the uninstantiated return.
      assert Check.check("""
             def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U := []
             def double(n Int64) Int64 := n * 2
             def doubled(xs val Vec(Int64)) Vec(Int64) := map(&double/1, xs)
             """) == :ok
    end

    test "a full higher-order recursive `map` over a Vec checks end to end" do
      assert Check.check("""
             def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U
             def map(_, []) := []
             def map(f, [h | t]) := [f(h) | map(f, t)]
             """) == :ok
    end
  end

  describe "annotate/3 — types on nodes (ADR-0050 §3)" do
    alias Rian.Core

    test "leaf and operator nodes carry their inferred type" do
      typed = Check.annotate(Pratt.parse("a + 1"), %{"a" => "Int64"})

      assert %Core.EBin{
               type: "Int64",
               left: %Core.EId{name: "a", type: "Int64"},
               right: %Core.ENum{text: "1", type: "Int64"}
             } = typed
    end

    test "a block threads its bindings and is typed by its final value" do
      typed = Check.annotate(Pratt.parse_body("n := 2; n * n"), %{})
      assert %Core.EBlock{type: "Int64"} = typed
    end

    test "a node inference cannot pin down is `:unknown`, not crashing" do
      assert %Core.ECall{type: :unknown} = Check.annotate(Pratt.parse("g(x)"))
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
