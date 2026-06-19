defmodule Rian.CheckTest do
  # async: false — exercises `Rian.Decl.compile`, which touches the global VM
  # (compiler/code server); concurrent module compilation races otherwise.
  use ExUnit.Case, async: false

  alias Rian.{Check, Core, Pratt}

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
      assert t("42") == "Int53"
      assert t("3.14") == "Float64"
      assert t("\"hi\"") == "String"
      assert t("true") == "Bool"
    end

    test "operators carry their result type" do
      assert t("a < b") == "Bool"
      assert t("a and b") == "Bool"
      assert t("a <> b") == "String"
      assert t("a / b") == "Float64"
      # `div`/`rem` infer from their operands like `+`/`-`/`*` (so an `Int53 div
      # Int53` stays `Int53`); with unknown operands the result is `:unknown`.
      assert Check.infer(Pratt.parse("a div b"), %{"a" => "Int53", "b" => "Int53"}) == "Int53"
      assert t("a div b") == :unknown
    end

    test "a `div`/`rem` constant of literals is width-flexible like `+`/`-`/`*`" do
      # `int_lit_expr?` accepts the same op set as `lit_expr_adopts?` (`+ - * div
      # rem`), so a literal `div`/`rem` sub-expression adopts a typed neighbour's
      # width instead of forcing the default `Int64` (ADR-0064).
      assert Check.infer(Pratt.parse("x * (4 div 2)"), %{"x" => "Int53"}) == "Int53"
      assert Check.infer(Pratt.parse("x + (10 rem 3)"), %{"x" => "Int53"}) == "Int53"
      # consistent with the already-flexible `+`/`-`/`*`
      assert Check.infer(Pratt.parse("x * (4 - 2)"), %{"x" => "Int53"}) == "Int53"
    end

    test "arithmetic unifies operands; mixed/unknown is conservative (not an error)" do
      assert Check.infer(Pratt.parse("x + 1"), %{"x" => "Int64"}) == "Int64"
      # mixing int and float does not crash the checker — it infers `:unknown`
      assert t("1 + 2.0") == :unknown
      # an unknown operand + a literal keeps the literal's default width (`Int53`)
      assert t("x + 1") == "Int53"
    end

    test "calls and unknown names infer :unknown (conservative)" do
      assert t("g(x)") == :unknown
      assert t("x") == :unknown
    end
  end

  describe "no implicit Int↔Float coercion (ADR-0035 / ADR-0034 §1)" do
    test "a float literal times an Int variable is rejected — convert explicitly" do
      assert {:error, msg} = Check.check("def f(a Int64) Float64 := 10.2 * a")
      assert msg =~ "no implicit Int↔Float conversion"
      assert msg =~ "Float64 * Int64"
      assert msg =~ "Prim.int_to_float"
    end

    test "a float literal times an int literal is rejected (write a float literal)" do
      assert {:error, _} = Check.check("def f() Float64 := 10.2 * 3")
    end

    test "an int literal added to a Float variable is rejected (strict, like the binding rule)" do
      assert {:error, _} = Check.check("def f(a Float64) Float64 := a + 1")
    end

    test "all-float and all-int arithmetic pass" do
      assert Check.check("def f(a Float64, b Float64) Float64 := a * b") == :ok
      assert Check.check("def f(a Int64, b Int64) Int64 := a * b") == :ok
      assert Check.check("def area(r Float64) Float64 := 3.14159 * r * r") == :ok
    end

    test "an :unknown operand stays conservative (no false rejection)" do
      # `g(a)` is :unknown, so `10.2 * g(a)` is not provably mixed
      assert Check.check("def f(a Int64) Float64 := 10.2 * g(a)") == :ok
    end

    test "the explicit `Prim.int_to_float(n)` conversion makes mixed math well-typed" do
      assert Check.check("def f(a Int64) Float64 := 10.2 * Prim.int_to_float(a)") == :ok
      assert Check.infer(Pratt.parse("__prim_int_to_float(n)"), %{"n" => "Int64"}) == "Float64"
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

    test "a bare inferred sum head is assignable to the same head parameterized (conservative)" do
      # `Some(rest)` infers the bare head `Option` (the payload type is not tracked); it
      # is under-specified, NOT a provable mismatch against `Option(Vec(Char))`, so the
      # conservative checker accepts it (the self-host `strip_prefix` shape, ADR-0034).
      assert Check.check("def strip(rest Vec(Char)) Option(Vec(Char)) := Some(rest)") == :ok

      # but a DIFFERENT head still mismatches — the relaxation pins the head exactly
      assert {:error, msg} = Check.check("def g() Vec(Int64) := Some(1)")
      assert msg =~ "declared return type is `Vec(Int64)`"
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
      assert msg =~ "type `Int53`"
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
      assert msg =~ "type `Vec(Int53)`"
    end

    test "a parametric binding displays at its declared type" do
      assert Check.infer(Pratt.parse_body("xs Vec(Int64) := [1, 2, 3] ; xs")) == "Vec(Int64)"
    end

    test "an in-range literal checks against each fixed-width integer type's bounds" do
      # exercises the two's-complement width_bounds/1 table across all widths.
      for ty <- ~w(Int8 Int16 Int32 Int53 Int64 Int128 UInt8 UInt16 UInt32 UInt64 UInt128) do
        assert Check.check("def f() #{ty} := 100") == :ok, "#{ty} should accept 100"
      end
    end

    test "an out-of-range literal for a narrow width is a proven error" do
      assert {:error, _} = Check.check("def f() Int8 := 999")
      assert {:error, _} = Check.check("def f() UInt8 := -1")
    end
  end

  describe "Char type (ADR-0036)" do
    test "a char literal is the `Char` primitive, distinct from `Int53`" do
      assert Check.infer(Pratt.parse_body("'A'")) == "Char"
      assert Check.infer(Pratt.parse_body("65")) == "Int53"
    end

    test "`__prim_char_code` converts a Char to its Int53 codepoint (portable, incl. JS)" do
      assert Check.infer(Pratt.parse_body("__prim_char_code('0')")) == "Int53"
    end

    test "ordinal arithmetic widens Char to its Int53 base (ADR-0036/0064)" do
      # `'9' - '0' = 9` is an Int53 (the portable codepoint width), not a Char
      assert Check.infer(Pratt.parse_body("'9' - '0'")) == "Int53"
      assert Check.infer(Pratt.parse_body("'a' + 1")) == "Int53"
      # a Char-typed param flows through: `c - '0' : Int64`
      assert Check.check("def dval(c Char) Int64 := c - '0'") == :ok
    end

    test "a typed binding may declare `Char`" do
      assert Check.check("def f(n Int64) Int64 := c Char := 'A' ; n") == :ok
      assert Check.infer(Pratt.parse_body("c Char := 'A' ; c")) == "Char"
    end

    test "a `Char`-returning function with a char-literal body checks" do
      assert Check.check("def first() Char := 'A'") == :ok
      assert {:error, _} = Check.check("def first() Char := 65")
    end
  end

  describe "range types (ADR-0036) — literal in-bounds binding checks" do
    test "an in-bounds integer literal binds, and the range unifies as its base" do
      # 7 ∈ 0..9, and `Digit` resolves to its `Int64` base so the block returns Int64
      assert Check.check("""
             range Digit := 0..9
             def f() Int64 := d Digit := 7 ; d
             """) == :ok

      # inclusive boundaries
      assert Check.check("range Digit := 0..9\ndef f() Int64 := d Digit := 0 ; d") == :ok
      assert Check.check("range Digit := 0..9\ndef f() Int64 := d Digit := 9 ; d") == :ok
    end

    test "an out-of-bounds literal is a proven compile error naming the interval" do
      assert {:error, msg} =
               Check.check("range Digit := 0..9\ndef f() Int64 := d Digit := 12 ; d")

      assert msg =~ "literal 12 is outside range `Digit` (0..9)"
    end

    test "a `Char`-based range checks the codepoint of a char literal" do
      assert Check.check("range Up := 'A'..'Z'\ndef f() Int64 := c Up := 'M' ; 0") == :ok

      assert {:error, msg} =
               Check.check("range Dig := '0'..'9'\ndef f() Int64 := c Dig := 'x' ; 0")

      assert msg =~ "outside range `Dig`"
    end

    test "the literal's ordinal kind must match the range base" do
      assert {:error, msg} =
               Check.check("range Up := 'A'..'Z'\ndef f() Int64 := c Up := 7 ; 0")

      assert msg =~ "range `Up` is over `Char`"
    end

    test "negative intervals are supported" do
      assert Check.check("range S := -5..5\ndef f() Int64 := d S := -3 ; d") == :ok
      assert {:error, _} = Check.check("range S := -5..5\ndef f() Int64 := d S := -9 ; d")
    end

    test "a non-literal base-compatible value is allowed (representation-transparent)" do
      # the bound is not statically provable for a runtime value; it is transparent
      # to its base (use `Name.of(n)` when a runtime bound check is wanted)
      assert Check.check("range Digit := 0..9\ndef f(n Int64) Int64 := d Digit := n ; d") == :ok
    end

    test "the `Name.of(n)` checked constructor returns `base | RangeError`" do
      # the function's declared `Int64 | RangeError` matches the constructor's type
      assert Check.check("""
             range Digit := 0..9
             def of_d(n Int64) Int64 | RangeError := Digit.of(n)
             """) == :ok

      # a `Char`-based range constructs `Char | RangeError`
      assert Check.check("""
             range Up := 'A'..'Z'
             def of_u(c Char) Char | RangeError := Up.of(c)
             """) == :ok
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

    test "under-declaration through a module-qualified call `M.f()` is also rejected" do
      # Regression: the call-graph fixpoint followed only bare-name calls
      # (`inner(n)`); a qualified `M.inner(n)` returned no callee, so its error set
      # silently escaped `outer`'s declared set — a pub function could under-declare
      # by routing the propagation through a module-qualified call (ADR-0040 §4
      # soundness hole). `call_name` now extracts the method name from a dot-call.
      assert {:error, msg} =
               Check.check("""
               type E := A | B
               mod M do
                 pub def inner(n Int64) Int64 | A := {:error, A}
               end
               def outer(n Int64) Int64 | B
                 with {:ok, x} <- M.inner(n) do
                   {:ok, x}
                 end
               end
               """)

      assert msg =~ "outer"
      assert msg =~ "A"
      assert msg =~ "declared set `B`"
    end

    test "an external dot-call to a name with no local function does not over-propagate" do
      # `String.upcase` names no local function, so the `table` lookup is empty and
      # nothing is propagated — `caller` produces ∅ ⊆ its declared `{Oops}`. Guards
      # the dot-call fix against spurious "returns error not in declared set".
      assert Check.check("""
             type Oops := Oops
             def caller(s Str) Str | Oops
               with {:ok, x} <- String.upcase(s) do
                 {:ok, x}
               end
             end
             """) == :ok
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
      assert msg =~ "Vec(Int53)"
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
      assert Check.infer(Pratt.parse("(x) -> x + 1")) == "Fn(_,Int53)"
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
      assert msg =~ "Fn(_,Int53)"
      assert msg =~ "Fn(Int64,Bool)"
    end

    test "`&name/arity` captures a known function as `Fn(_ × arity, return)`" do
      assert Check.infer(Pratt.parse("&dbl/1"), %{}, %{funs: %{{"dbl", 1} => "Int64"}}) ==
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
               right: %Core.ENum{text: "1", type: "Int53"}
             } = typed
    end

    test "a block threads its bindings and is typed by its final value" do
      typed = Check.annotate(Pratt.parse_body("n := 2; n * n"), %{})
      assert %Core.EBlock{type: "Int53"} = typed
    end

    test "a node inference cannot pin down is `:unknown`, not crashing" do
      assert %Core.ECall{type: :unknown} = Check.annotate(Pratt.parse("g(x)"))
    end

    # Locks the composition every emitter now performs (ADR-0050 §3): build the
    # program inference context, derive a clause's typing env from its head
    # patterns + declared params, and annotate the clause body under it. If an
    # emitter were reverted to the bare untyped `Core.from_expr`, this contract
    # — a declared param type reaching the body's Core nodes — is what it loses.
    test "program_ic + clause_env + annotate type a clause body the way emitters call it" do
      prog = Rian.Decl.parse("def dbl(n Int64) Int64 := n + n")
      ic = Check.program_ic(prog)
      func = hd(prog.funcs)
      clause = hd(func.clauses)

      tenv = Check.clause_env(clause.pats, func.params, ic)
      assert tenv["n"] == "Int64"

      # the emitters annotate `parse_body`, which wraps the expr in an EBlock
      typed = Check.annotate(Pratt.parse_body(clause.body), tenv, ic)

      assert %Core.EBlock{
               type: "Int64",
               stmts: [
                 expr: %Core.EBin{
                   type: "Int64",
                   left: %Core.EId{name: "n", type: "Int64"},
                   right: %Core.EId{name: "n", type: "Int64"}
                 }
               ]
             } = typed
    end
  end

  describe "the type gate fires at compile time" do
    test "Decl.compile refuses a proven return-type mismatch" do
      assert_raise Check.Error, ~r/declared return type is `Bool`/, fn ->
        Rian.Decl.compile("def f(n Int64) Bool := n + 1")
      end
    end

    test "a well-typed program compiles through the gate" do
      assert [{_, _}] = Rian.Decl.compile("def double(n Int64) Int64 := n * 2")
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

  describe "a unit-yielding expression is rejected in value position (ADR-0035 §6)" do
    test "an else-less `if` as the returned value is rejected" do
      assert_raise Check.Error, ~r/value position must have an `else`/, fn ->
        Rian.Decl.compile("def f(n Int64) Int64 := if n > 0 do 1 end")
      end
    end

    test "an else-less `if` on a binding's right-hand side is rejected" do
      assert_raise Check.Error, ~r/value position must have an `else`/, fn ->
        Rian.Decl.compile("""
        def f(n Int64) Int64
        def f(n)
          x := if n > 0 do 1 end
          x
        end
        """)
      end
    end

    test "an else-less `if` as a function argument is rejected" do
      assert_raise Check.Error, ~r/value position must have an `else`/, fn ->
        Rian.Decl.compile("""
        def g(x Int64) Int64 := x
        def f(n Int64) Int64 := g(if n > 0 do 1 end)
        """)
      end
    end

    test "an else-less `if` as a non-final effect statement is allowed" do
      assert [{_, _}] =
               Rian.Decl.compile("""
               def f(n Int64) Int64
               def f(n)
                 if n > 0 do dbg(n) end
                 n
               end
               """)
    end

    test "a value-position `if` with both branches compiles" do
      assert [{_, _}] = Rian.Decl.compile("def f(n Int64) Int64 := if n > 0 do 1 else 0 end")
    end

    test "a `<~` mutation as the returned value is rejected — it yields unit" do
      assert {:error, msg} =
               Check.check("""
               def f(n Int64) Int64
               def f(n)
                 total := 0
                 total <~ total + n
               end
               """)

      assert msg =~ "mutation yields unit"
    end

    test "a `<~` mutation as a non-final effect statement is allowed" do
      assert Check.check("""
             def f(n Int64) Int64
             def f(n)
               total := 0
               total <~ total + n
               total
             end
             """) == :ok
    end

    test "an else-less `if` inside an effect-position lambda body is allowed" do
      # the lambda is a non-final statement (its value is discarded; the block
      # returns 5), and a lambda body is not *provably* value position — so the gate
      # must not reject the else-less `if` in it.
      assert Check.check("""
             def g() Int64
             def g()
               (x) -> if x > 0 do 1 end
               5
             end
             """) == :ok
    end
  end

  describe "join lattice — least-upper-bound (ADR-0059)" do
    test "numeric LUB: same kind widens; differing widths climb" do
      assert Check.join("Int32", "Int64") == "Int64"
      assert Check.join("Int64", "Int32") == "Int64"
      assert Check.join("Float32", "Float64") == "Float64"
      assert Check.join("Int64", "Int64") == "Int64"
    end

    test "unsigned ⊔ signed climbs to the least Int wide enough for both" do
      assert Check.join("UInt8", "Int8") == "Int16"
      assert Check.join("UInt32", "Int32") == "Int64"
      assert Check.join("UInt64", "Int64") == "Int128"
    end

    test "integer ⊔ float picks the least float that holds the integer exactly" do
      assert Check.join("Int16", "Float32") == "Float32"
      assert Check.join("Int32", "Float32") == "Float64"
    end

    test "gaps with no representable upper bound resolve to :unknown" do
      assert Check.join("UInt128", "Int64") == :unknown
      # 2^63 is not exact in any float (mantissa maxes at 53)
      assert Check.join("Int64", "Float64") == :unknown
      assert Check.join("Int128", "Float64") == :unknown
    end

    test ":unknown is absorbing (an uninferable arm poisons the join); :bottom is identity" do
      assert Check.join("Int64", :unknown) == :unknown
      assert Check.join(:unknown, "Int64") == :unknown
      assert Check.join(:bottom, "Int64") == "Int64"
      assert Check.join("Int64", :bottom) == "Int64"
      assert Check.join(:bottom, :bottom) == :bottom
    end

    test "same-constructor covariant join recurses; cross-constructor is :unknown" do
      assert Check.join("Vec(Int32)", "Vec(Int64)") == "Vec(Int64)"
      assert Check.join("Option(Int32)", "Option(Int64)") == "Option(Int64)"
      # different nominal sums never promote (ADR-0035 / ADR-0059 §4)
      assert Check.join("Shape", "Color") == :unknown
      # a covariant arg that itself has no LUB poisons the whole
      assert Check.join("Vec(Int64)", "Vec(Float64)") == :unknown
    end

    test "function types are not covariantly joined (args are contravariant)" do
      # widening the arg would be unsound — a caller could pass an Int64 to the
      # Int32 arm; differing `Fn`s join to :unknown, equal ones pass through
      assert Check.join("Fn(Int32,Bool)", "Fn(Int64,Bool)") == :unknown
      assert Check.join("Fn(Int64,Bool)", "Fn(Int64,Bool)") == "Fn(Int64,Bool)"
    end

    test "if-arm join is precise where a binding would widen (the closed asymmetry)" do
      # both arms numeric, differing width -> the if infers the LUB, not :unknown
      assert Check.infer(Pratt.parse_body("if c do x else y end"), %{
               "x" => "Int32",
               "y" => "Int64"
             }) ==
               "Int64"
    end

    test "list literal elements join to the LUB element type" do
      assert Check.infer(Pratt.parse_body("[a, b]"), %{"a" => "Int32", "b" => "Int64"}) ==
               "Vec(Int64)"
    end
  end

  describe "inference — unary, fallthroughs & nested callables" do
    test "a unary negation of a literal infers the literal's type" do
      assert Check.infer(Pratt.parse("-5")) == "Int53"
      assert Check.infer(Pratt.parse("-3.5")) == "Float64"
    end

    test "`not e` infers Bool regardless of its argument" do
      assert Check.infer(Pratt.parse("not x")) == "Bool"
    end

    test "an unhandled binary operator infers :unknown (conservative fallthrough)" do
      # `|>` and `<~` parse as infix but are neither arithmetic, comparison,
      # concat, nor division — they fall through `infer(%EBin{})` to `:unknown`.
      assert Check.infer(Pratt.parse("a |> b")) == :unknown
      assert Check.infer(Pratt.parse("a <~ b")) == :unknown
    end

    test "capturing an unknown function infers :unknown" do
      assert Check.infer(Pratt.parse("&nope/1"), %{}, %{funs: %{}}) == :unknown
    end

    test "an if expression unifies its two arm types" do
      assert Check.infer(Pratt.parse("if c do 1 else 2 end")) == "Int53"
      # differing concrete arms are conservative, not an error
      assert Check.infer(Pratt.parse("if c do 1 else true end")) == :unknown
    end

    test "a cons-tail list whose head and tail element types disagree is :unknown" do
      # head infers Int64, tail is Vec(Bool) -> element Bool -> no agreement
      assert Check.infer(Pratt.parse_body("[a | rest]"), %{
               "a" => "Int64",
               "rest" => "Vec(Bool)"
             }) == :unknown

      # a matching head/tail does infer Vec(T)
      assert Check.infer(Pratt.parse_body("[a | rest]"), %{
               "a" => "Int64",
               "rest" => "Vec(Int64)"
             }) == "Vec(Int64)"
    end

    test "applying a function-typed param whose return slot is `_` infers :unknown (passes)" do
      # `f Fn(Int64, _)` applied as `f(2)` -> the `_` return reads back as
      # `:unknown`, which never contradicts the declared `Int64`.
      assert Check.check("def app(f Fn(Int64, _)) Int64 := f(2)") == :ok
    end
  end

  describe "structural Fn unification with nested parens" do
    test "a nested `Fn(...)` argument is one component under the paren-aware splitter" do
      assert Check.unify("Fn(Fn(Int64,Int64),Bool)", "Fn(Fn(Int64,Int64),Bool)") ==
               "Fn(Fn(Int64,Int64),Bool)"

      # a wildcard in the nested position reconciles with a concrete nested Fn
      assert Check.unify("Fn(_,Bool)", "Fn(Fn(Int64,Int64),Bool)") ==
               "Fn(Fn(Int64,Int64),Bool)"
    end
  end

  describe "generic-return instantiation (ADR-0042)" do
    test "a fully-pinned generic return is substituted to the concrete arg type" do
      ic = %{
        funs: %{{"id", 1} => "T"},
        fsigs: %{{"id", 1} => %{params: ["T"], ret: "T", tvars: ["T"]}}
      }

      assert Check.infer(Pratt.parse("id(5)"), %{}, ic) == "Int53"
      # an un-pinnable tvar (no informative argument) stays :unknown
      assert Check.infer(Pratt.parse("id(x)"), %{}, ic) == :unknown
    end

    test "a `Vec(T)` parameter pins T from a list argument's element type" do
      ic = %{
        funs: %{{"head", 1} => "T"},
        fsigs: %{{"head", 1} => %{params: ["Vec(T)"], ret: "T", tvars: ["T"]}}
      }

      assert Check.infer(Pratt.parse("head([1, 2, 3])"), %{}, ic) == "Int53"
    end
  end

  describe "annotate/3 — additional nodes (ADR-0050 §3)" do
    test "a string leaf carries its inferred type" do
      assert %Core.EStr{type: "String"} = Check.annotate(Pratt.parse(~s|"hi"|))
    end

    test "a unary node annotates its argument and carries its type" do
      typed = Check.annotate(Pratt.parse("-5"))
      assert %Core.EUnary{type: "Int53", arg: %Core.ENum{type: "Int53"}} = typed
    end

    test "a tuple annotates each element; the tuple itself is :unknown" do
      typed = Check.annotate(Pratt.parse("{1, 2}"))

      assert %Core.ETuple{
               type: :unknown,
               elems: [%Core.ENum{type: "Int53"}, %Core.ENum{type: "Int53"}]
             } = typed
    end

    test "a cons-tail list annotates head and tail and is typed Vec(T)" do
      typed = Check.annotate(Pratt.parse("[a | rest]"), %{"a" => "Int64", "rest" => "Vec(Int64)"})

      assert %Core.EList{
               type: "Vec(Int64)",
               elems: [%Core.EId{name: "a", type: "Int64"}],
               tail: %Core.EId{name: "rest", type: "Vec(Int64)"}
             } = typed
    end

    test "an if expression annotates cond/then/else and is typed by its arm unification" do
      typed = Check.annotate(Pratt.parse("if c do 1 else 2 end"))

      assert %Core.EIf{
               type: "Int53",
               then: %Core.EBlock{type: "Int53"},
               else: %Core.EBlock{type: "Int53"}
             } = typed
    end

    test "a case expression narrows each arm, annotates its guard and body, and unifies" do
      prog = Rian.Decl.parse("type Shape := Circle(radius Float64) | Square(side Float64)")
      ic = Check.program_ic(prog)
      src = "case s do\n Circle(r) when r > 0.0 -> r\n Square(x) -> x\n end"

      typed = Check.annotate(Pratt.parse(src), %{"s" => "Shape"}, ic)

      assert %Core.ECase{type: "Float64"} = typed
      # the first arm's guard is annotated under the narrowed env (`r` is Float64)
      [{_pat, guard, body} | _] = typed.arms
      assert %Core.EBin{type: "Bool"} = guard
      assert %Core.EId{name: "r", type: "Float64"} = body
    end

    test "a `with` expression annotates its body and is typed by it" do
      typed = Check.annotate(Pratt.parse("with {:ok, x} <- f(n) do 1 end"))
      assert %Core.EWith{type: "Int53"} = typed
    end

    test "a node annotate has no rule for is returned unchanged" do
      # a bare atom node has no annotate clause -> falls to the default passthrough
      node = Rian.Core.from_expr(Pratt.parse(":sym"))
      assert Check.annotate(node) == node
    end
  end

  describe "check_func/1,2 and a non-Result eset (entry points)" do
    test "check_func/2 (default eset) checks a return-type mismatch directly" do
      %{funcs: [f]} = Rian.Decl.parse("def f(n Int64) Bool := n + 1")
      ic = Check.program_ic(Rian.Decl.parse("def f(n Int64) Bool := n + 1"))
      assert {:error, msg} = Check.check_func(f, ic)
      assert msg =~ "declared return type is `Bool`"
    end

    test "check_func/1 (all defaults) passes a well-typed function" do
      %{funcs: [f]} = Rian.Decl.parse("def double(n Int64) Int64 := n * 2")
      assert Check.check_func(f) == :ok
    end
  end

  describe "error-set composition — transitive & constructor tags (ADR-0040 §4)" do
    test "an error set propagates transitively through a chain of with-callees" do
      # inner produces A; mid propagates inner; outer propagates mid — the union
      # over callees in the call-graph fixpoint must carry A all the way to outer.
      assert Check.check("""
             type E := A | B
             def inner(n Int64) Int64 | E := {:error, A}
             def mid(n Int64) Int64 | E
               with {:ok, x} <- inner(n) do
                 {:ok, x}
               end
             end
             def outer(n Int64) Int64 | E
               with {:ok, x} <- mid(n) do
                 {:ok, x}
               end
             end
             """) == :ok
    end

    test "a constructor-call error tag (`DivByZero(x)`) is named for the set check" do
      assert Check.check("def f(n Int64) Int64 | DivByZero := {:error, DivByZero(n)}") == :ok

      assert {:error, msg} =
               Check.check("def f(n Int64) Int64 | NotFound := {:error, DivByZero(n)}")

      assert msg =~ "DivByZero"
      assert msg =~ "declared set `NotFound`"
    end

    test "a with-clause source that is not a call propagates no callee set" do
      # the `<-` source `n` is a bare variable, not a `f(...)` call, so `call_name`
      # contributes nothing and the function produces an empty error set.
      assert Check.check("""
             def f(n Int64) Int64 | NotFound
               with {:ok, x} <- n do
                 {:ok, x}
               end
             end
             """) == :ok
    end

    test "an unannotated intermediary's set is the union of its propagated callees" do
      # `helper` has a non-Result return, so the fixpoint must INFER its set as the
      # union over its callees (`inner`'s `A`) rather than reading a declared one.
      assert Check.check("""
             type E := A | B
             def inner(n Int64) Int64 | E := {:error, A}
             def helper(n Int64) Int64
               with {:ok, x} <- inner(n) do
                 {:ok, x}
               end
             end
             def outer(n Int64) Int64 | E
               with {:ok, x} <- helper(n) do
                 {:ok, x}
               end
             end
             """) == :ok
    end

    test "check_func/3 with a non-`%{tsets,table}` eset skips the error-set check" do
      # the default `check_error_set/2` clause: an eset that is not the expected
      # context map leaves the error-set check a no-op (return type still checked).
      %{funcs: [f]} = Rian.Decl.parse("def f(n Int64) Int64 | NotFound := {:error, Anything}")
      ic = Check.program_ic(Rian.Decl.parse("def f(n Int64) Int64 | NotFound := {:error, X}"))
      assert Check.check_func(f, ic, %{}) == :ok
    end
  end

  describe "flow narrowing against an unknown scrutinee" do
    test "a bare-variable case arm over an unknown scrutinee narrows to :unknown" do
      # the scrutinee `s` is :unknown, so narrowing the arm's `PVar` runs
      # `concretize(:unknown)` (the non-binary passthrough) and the body is :unknown.
      assert Check.infer(Pratt.parse_body("case s do\n x -> x\n end"), %{}) == :unknown
    end
  end

  describe "a `.of` call on a non-range dot head" do
    test "infers :unknown when the head is not a known range and not function-typed" do
      # `Foo.of(3)` — `Foo` is not in `ic.ranges`, and `Foo.of` infers to a
      # non-`Fn` type, so the fallthrough yields `:unknown` (lines 219-220).
      assert Check.infer(Pratt.parse("Foo.of(3)")) == :unknown
    end
  end

  describe "negative numeric literals against annotations" do
    test "a negative integer literal adopts a signed-integer annotation" do
      # `x Int32 := -5` — the unary-minus literal adopts the declared `Int32`.
      assert Check.check("def f(n Int64) Int64 := x Int32 := -5 ; n") == :ok
    end
  end

  describe "constant-of-literals return bodies adopt the declared width (ADR-0064)" do
    test "a bare-literal base case adopts `Int53`/`Int32` (not the default `Int64`)" do
      assert Check.check("def g() Int53 := 0") == :ok
      assert Check.check("def g() Int32 := 7") == :ok
    end

    test "an arithmetic expression of literals adopts the declared width" do
      assert Check.check("def f() Int53 := 2 * 3 + 1") == :ok
      assert Check.check("def f() Int32 := 0 - 1") == :ok
    end

    test "an `if`/`case` whose branches are all literals adopts the width" do
      assert Check.check(
               "def sign(n Int53) Int53 := if n > 0 do 1 else if n < 0 do 0 - 1 else 0 end end"
             ) == :ok
    end

    test "a recursive fn with a literal base + literal-augmented step adopts `Int53`" do
      assert Check.check("""
             def len(xs Vec(Int53)) Int53
             def len([]) := 0
             def len([_ | t]) := 1 + len(t)
             """) == :ok
    end

    test "a REAL `Int64` value is still rejected against `Int53` — adoption is literals-only" do
      # soundness: only a constant of literals adopts; a typed value keeps the
      # narrowing check, even inside an `if` branch alongside a literal.
      assert {:error, m1} = Check.check("def bad(n Int64) Int53 := n")
      assert m1 =~ "declared return type is `Int53`"

      assert {:error, _} =
               Check.check("def bad(n Int64) Int53 := if true do n else 0 end")
    end
  end

  describe "a fixed-width literal must fit the declared width (ADR-0064 soundness)" do
    test "a return-body literal out of the width's range is rejected" do
      assert {:error, m} = Check.check("def f() Int8 := 9999")
      assert m =~ "literal 9999 is out of range for `Int8` (-128..127)"

      assert {:error, _} = Check.check("def f() UInt8 := 300")
      assert {:error, _} = Check.check("def f(b Bool) Int8 := if b do 1 else 9999 end")
    end

    test "a typed binding (incl. negated) and a list element are range-checked" do
      assert {:error, m} = Check.check("def f(n Int64) Int64 := x Int8 := -200 ; n")
      assert m =~ "out of range for `Int8`"

      assert {:error, _} = Check.check("def f() Vec(Int8) := [1, 9999]")
    end

    test "in-range literals pass; arbitrary-precision `Int` has no bound" do
      assert Check.check("def f() Int8 := 100") == :ok
      assert Check.check("def f() Int53 := 1000") == :ok
      assert Check.check("def f() Int := 999999999999999999999999") == :ok
    end
  end

  describe "integer literals are width-flexible in arithmetic & branches (ADR-0064)" do
    test "a literal operand takes the typed operand's width, even nested" do
      # `13 - lvl` over an `Int53` var is `Int53` (13 adopts lvl); `(13 - lvl) * 10`
      # then stays `Int53` instead of the literal's default `Int64`.
      assert Check.check("def bp(lvl Int53) Int53 := (13 - lvl) * 10") == :ok
      assert Check.check("def f(n Int32) Int32 := n * 2 + 1") == :ok
    end

    test "an `if` with an Int53 branch + a literal branch stays Int53" do
      assert Check.check("def step(n Int53) Int53 := if n > 0 do a := n * 2; a + 1 else 0 end") ==
               :ok
    end

    test "flexibility is integer-only — no int→float, no int→bool coercion" do
      # `1 + 2.0` stays mixed/`:unknown` (ADR-0035, no implicit coercion), and an
      # `if` with an int-literal and a Bool branch stays `:unknown` (not Bool).
      assert Check.infer(Pratt.parse("1 + 2.0")) == :unknown
      assert Check.infer(Pratt.parse("if c do 1 else true end")) == :unknown
    end

    test "an unknown operand + a literal keeps the literal's default Int53" do
      # only a *concrete* integer neighbour is adopted; an `:unknown` one is not, so
      # `x + 1` (x unknown) stays `Int53` and `(x) -> x + 1` is `Fn(_,Int53)`.
      assert Check.infer(Pratt.parse("x + 1"), %{}) == "Int53"
      assert Check.infer(Pratt.parse("(x) -> x + 1")) == "Fn(_,Int53)"
    end

    test "a list literal of constant elements adopts `Vec(Int53)`" do
      assert Check.check("def small_primes() Vec(Int53) := [2, 3, 5, 7]") == :ok
      # soundness: a list of REAL Int64 values is still rejected against Vec(Int53)
      assert {:error, m} = Check.check("def f(n Int64) Vec(Int53) := [n, n]")
      assert m =~ "Vec(Int53)"
    end

    test "a generic fn whose return ignores its tvar infers concretely through recursion" do
      # `length(xs Vec(T)) Int53 forall T` returns `Int53` regardless of `T`, so the
      # recursive `length(t)` over an unknown tail stays `Int53` (not `:unknown`).
      assert Check.check("""
             mod L do
               pub def length(xs Vec(T)) Int53 forall T
               pub def length([]) := 0
               pub def length([_ | t]) := 1 + length(t)
             end
             """) == :ok
    end
  end

  describe "range bindings — non-integer ordinal kinds & runtime values" do
    test "a Char literal against an Int64-based range is a kind mismatch naming `Char`" do
      assert {:error, msg} =
               Check.check("range S := 0..9\ndef f() Int64 := d S := 'A' ; 0")

      assert msg =~ "range `S` is over `Int64`, but the literal is a `Char`"
    end

    test "a negative float literal against an Int64-based range is not assignable" do
      # `-3.5` is a `EUnary{-, ENum{float}}`; its inner ordinal is `:not_literal`
      # (a float for an `Int64` base), so the unary branch propagates `:not_literal`
      # and the `Float64` value is reported as not assignable to the base.
      assert {:error, msg} =
               Check.check("range S := 0..9\ndef f() Int64 := d S := -3.5 ; 0")

      assert msg =~ "value of type `Float64` is not assignable to range `S`"
      assert msg =~ "base `Int64`"
      assert msg =~ "use `S.of(n)`"
    end

    test "a String-typed runtime value is not assignable to an Int64-based range" do
      assert {:error, msg} =
               Check.check(~s|range Digit := 0..9\ndef f(s String) Int64 := d Digit := s ; 0|)

      assert msg =~ "value of type `String` is not assignable to range `Digit`"
      assert msg =~ "(base `Int64`); use `Digit.of(n)`"
    end
  end

  describe "numeric widening across more kinds (assignable?)" do
    test "unsigned widens to a wider unsigned" do
      assert Check.check("def f(n UInt16) UInt32 := x UInt32 := n ; x") == :ok
    end

    test "unsigned widens losslessly into a float whose mantissa holds it" do
      assert Check.check("def f(n UInt16) Float32 := x Float32 := n ; x") == :ok
    end

    test "a float widens into a wider float" do
      assert Check.check("def f(n Float32) Float64 := x Float64 := n ; x") == :ok
    end

    test "a malformed numeric-prefixed width is treated as non-numeric (no widening)" do
      # `Int` with a non-integer width parses to `nil` from `num_bits`, so the
      # join falls back to non-numeric handling and yields `:unknown`.
      assert Check.join("IntX", "Int64") == :unknown
    end
  end

  describe "join lattice — remaining numeric & parametric branches (ADR-0059)" do
    test "signed ⊔ unsigned is symmetric (either operand order)" do
      assert Check.join("Int8", "UInt8") == "Int16"
    end

    test "float ⊔ integer is symmetric (either operand order)" do
      assert Check.join("Float32", "Int16") == "Float32"
    end

    test "unsigned ⊔ float and float ⊔ unsigned both climb to the holding float" do
      assert Check.join("UInt16", "Float32") == "Float32"
      assert Check.join("Float32", "UInt16") == "Float32"
    end

    test "same-kind unsigned ⊔ unsigned widens (UInt prefix)" do
      assert Check.join("UInt8", "UInt16") == "UInt16"
    end

    test "a parametric type joined with an `Fn(...)` is :unknown (either order)" do
      assert Check.join("Vec(Int64)", "Fn(Int64,Bool)") == :unknown
      assert Check.join("Fn(Int64,Bool)", "Vec(Int64)") == :unknown
    end
  end

  describe "protocol-bound checking at call sites (ADR-0042 §2)" do
    @eq_protocol """
    protocol Eq do
      def eq(a Self, b Self) Bool
    end
    impl Eq for Int64 do
      def eq(a, b) := a == b
    end
    def equal3(a T, b T, c T) Bool forall T: Eq := eq(a, b) and eq(b, c)
    """

    test "calling a bounded generic with a concrete type lacking the impl is rejected" do
      assert {:error, msg} =
               Check.check(@eq_protocol <> "def caller(a Bool) Bool := equal3(a, a, a)")

      assert msg =~ "`equal3` requires `T: Eq`"
      assert msg =~ "`Bool` has no `impl Eq for Bool`"
    end

    test "calling a bounded generic with a type that has the impl passes" do
      assert Check.check(@eq_protocol <> "def caller(a Int64) Bool := equal3(a, a, a)") == :ok
    end
  end

  describe "labeled arguments are construction-only (ADR-0065 freeze)" do
    test "a labeled struct construction (PascalCase callee) is allowed" do
      src = "struct Point(x Int64, y Int64)\ndef f() Point := Point(x: 1, y: 2)"
      assert Check.check(src) == :ok
    end

    test "a labeled argument on a plain (lowercase) function call is rejected" do
      assert {:error, msg} =
               Check.check("def g(a Int64) Int64 := a\ndef f() Int64 := g(a: 1)")

      assert msg =~ "labeled arguments"
      assert msg =~ "ADR-0065"
    end

    test "a nested labeled plain call (inside an arithmetic expr) is also caught" do
      assert {:error, msg} =
               Check.check("def g(a Int64) Int64 := a\ndef f() Int64 := 1 + g(a: 1)")

      assert msg =~ "labeled arguments"
    end

    test "a labeled argument on a qualified (dotted) call is rejected" do
      assert {:error, msg} = Check.check("def f() Int64 := String.foo(a: 1)")

      assert msg =~ "labeled arguments"
      assert msg =~ "String.foo"
      assert msg =~ "ADR-0065"
    end

    test "a labeled argument on a piped-into plain call is rejected" do
      assert {:error, msg} =
               Check.check("def g(a Int64) Int64 := a\ndef f() Int64 := 1 |> g(a: 1)")

      assert msg =~ "labeled arguments"
    end
  end
end
