defmodule Rian.DeclTest do
  # async: false — the execution tests define modules via Code.eval_string.
  use ExUnit.Case, async: false

  alias Rian.Decl

  describe "parsing -> pipeline IR" do
    test "a `type` sum with labeled fields" do
      %{types: [t]} = Decl.parse("type Shape := Circle(radius Float64) | Square(side Float64)")

      assert t == %{
               name: "Shape",
               variants: [
                 %{ctor: "Circle", fields: [%{label: "radius", type: "Float64"}]},
                 %{ctor: "Square", fields: [%{label: "side", type: "Float64"}]}
               ]
             }
    end

    test "nullary and unlabeled-field variants" do
      %{types: [t]} = Decl.parse("type Value := Num(Int64) | Zero")

      assert t.variants == [
               %{ctor: "Num", fields: [%{type: "Int64"}]},
               %{ctor: "Zero", fields: []}
             ]
    end

    test "a bodiless signature plus pattern clauses groups into one function" do
      %{funcs: [f]} =
        Decl.parse("""
        def area(s val Shape) Float64
        def area(Circle(r)) := pi * r * r
        def area(Square(s)) := s * s
        """)

      assert f.name == "area"
      assert f.params == [%{name: "s", type: "Shape", cap: :val}]
      assert f.ret == "Float64"
      assert [%{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"} | _] = f.clauses
    end

    test "a single typed clause binds its parameter as the pattern" do
      %{funcs: [f]} = Decl.parse("def double(n Int64) Int64 := n * 2")
      assert f.params == [%{name: "n", type: "Int64", cap: :val}]
      assert f.ret == "Int64"
      assert f.clauses == [%{pats: [{:var, "n"}], body: "n * 2", guard: nil}]
    end

    test "multi-line declarations are joined by continuation" do
      %{types: [t]} =
        Decl.parse("""
        type Tree :=
            Leaf
          | Node(left Tree, value Int64, right Tree)
        """)

      assert t.name == "Tree"
      assert [%{ctor: "Leaf", fields: []}, %{ctor: "Node", fields: node_fields}] = t.variants

      assert node_fields == [
               %{label: "left", type: "Tree"},
               %{label: "value", type: "Int64"},
               %{label: "right", type: "Tree"}
             ]
    end
  end

  describe "end-to-end lowering and execution" do
    @area """
    type Shape := Circle(radius Float64) | Square(side Float64)

    def area(s val Shape) Float64
    def area(Circle(r)) := pi * r * r
    def area(Square(s)) := s * s
    """

    test "area lowers to idiomatic Elixir and Rust" do
      [{"area", out}] = Decl.compile(@area)

      assert out.elixir =~ "def area({:circle, r}) do :math.pi() * r * r end"
      assert out.rust =~ "fn area(s: &Shape) -> f64"
      assert out.rust =~ "Shape::Circle { radius: r } => std::f64::consts::PI * r * r,"
    end

    test "the emitted Elixir runs on the BEAM" do
      [{"area", out}] = Decl.compile(@area)
      Code.eval_string("defmodule AreaFromSource do\n#{out.elixir}\nend")

      assert_in_delta AreaFromSource.area({:circle, 2.0}), :math.pi() * 4, 1.0e-9
      assert AreaFromSource.area({:square, 3.0}) == 9.0
    end

    test "an iso sum (Value) lowers and runs" do
      [{"eval", out}] =
        Decl.compile("""
        type Value := Num(Int64) | Zero

        def eval(v iso Value) Int64
        def eval(Num(n)) := n * 2
        def eval(Zero) := 0
        """)

      assert out.rust =~ "fn eval(v: Value) -> i64"
      Code.eval_string("defmodule EvalFromSource do\n#{out.elixir}\nend")
      assert EvalFromSource.eval({:num, 21}) == 42
      assert EvalFromSource.eval(:zero) == 0
    end

    test "string bodies and guards lower and run (classify-style)" do
      [{"classify", out}] =
        Decl.compile("""
        def classify(n Int64) String
        def classify(0) := "zero"
        def classify(n) when n > 0 := "positive"
        def classify(_) := "negative"
        """)

      assert out.elixir =~ "def classify(n) when n > 0 do \"positive\" end"
      assert out.rust =~ "n if n > 0 => \"positive\","

      Code.eval_string("defmodule ClassifyFromSource do\n#{out.elixir}\nend")
      assert ClassifyFromSource.classify(0) == "zero"
      assert ClassifyFromSource.classify(7) == "positive"
      assert ClassifyFromSource.classify(-3) == "negative"
    end
  end

  describe "the exhaustiveness gate fires on parsed source" do
    test "a missing variant clause is refused at lowering" do
      src = """
      type Shape := Circle(radius Float64) | Square(side Float64)

      def area(s val Shape) Float64
      def area(Circle(r)) := pi * r * r
      """

      assert_raise RuntimeError, ~r/non-exhaustive/, fn -> Decl.compile(src) end
    end
  end

  describe "multi-parameter functions (clauses-guards §5.2)" do
    test "single-clause: Elixir multi-arg def; Rust matches the argument tuple" do
      [{"add", out}] = Decl.compile("def add(x Int64, y Int64) Int64 := x + y")

      assert out.elixir =~ "def add(x, y) do x + y end"
      assert out.rust =~ "fn add(x: i64, y: i64) -> i64"
      assert out.rust =~ "match (x, y) {"
      assert out.rust =~ "(x, y) => x + y,"

      Code.eval_string("defmodule AddFromSource do\n#{out.elixir}\nend")
      assert AddFromSource.add(2, 3) == 5
    end

    test "multi-clause with guards lowers and runs (max2)" do
      [{"max2", out}] =
        Decl.compile("""
        def max2(a Int64, b Int64) Int64
        def max2(a, b) when a >= b := a
        def max2(_, b) := b
        """)

      assert out.elixir =~ "def max2(a, b) when a >= b do a end"
      assert out.rust =~ "(a, b) if a >= b => a,"

      Code.eval_string("defmodule Max2FromSource do\n#{out.elixir}\nend")
      assert Max2FromSource.max2(3, 7) == 7
      assert Max2FromSource.max2(9, 2) == 9
    end

    test "a clause whose arity differs from the signature is rejected" do
      assert_raise Decl.Error, ~r/arity/, fn ->
        Decl.parse("""
        def f(a Int64, b Int64) Int64
        def f(a) := a
        """)
      end
    end
  end

  describe "honest limits raise Rian.Decl.Error" do
    test "unsupported declaration keywords are rejected" do
      assert_raise Decl.Error, ~r/unsupported declaration/, fn ->
        Decl.parse("struct Point(x Float64, y Float64)")
      end
    end
  end
end
