defmodule Rian.DeclTest do
  # async: false — the execution tests define modules via Code.eval_string.
  use ExUnit.Case, async: false

  alias Rian.Decl
  alias Rian.IR.{Clause, Field, Func, Param, Struct, Type, Variant}

  describe "parsing -> core IR (Rian.IR structs)" do
    test "a `type` sum with labeled fields" do
      %{types: [t]} = Decl.parse("type Shape := Circle(radius Float64) | Square(side Float64)")

      assert t == %Type{
               name: "Shape",
               variants: [
                 %Variant{ctor: "Circle", fields: [%Field{label: "radius", type: "Float64"}]},
                 %Variant{ctor: "Square", fields: [%Field{label: "side", type: "Float64"}]}
               ]
             }
    end

    test "nullary and unlabeled-field variants" do
      %{types: [t]} = Decl.parse("type Value := Num(Int64) | Zero")

      assert t.variants == [
               %Variant{ctor: "Num", fields: [%Field{type: "Int64"}]},
               %Variant{ctor: "Zero", fields: []}
             ]
    end

    test "a bodiless signature plus pattern clauses groups into one Func" do
      %{funcs: [f]} =
        Decl.parse("""
        def area(s val Shape) Float64
        def area(Circle(r)) := pi * r * r
        def area(Square(s)) := s * s
        """)

      assert f.name == "area"
      assert f.params == [%Param{name: "s", type: "Shape", cap: :val}]
      assert f.ret == "Float64"

      assert [%Clause{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"} | _] =
               f.clauses
    end

    test "a single typed clause binds its parameter as the pattern" do
      %{funcs: [f]} = Decl.parse("def double(n Int64) Int64 := n * 2")
      assert f.params == [%Param{name: "n", type: "Int64", cap: :val}]
      assert f.ret == "Int64"
      assert f.clauses == [%Clause{pats: [{:var, "n"}], body: "n * 2", guard: nil}]
    end

    test "multi-line declarations are joined by continuation" do
      %{types: [t]} =
        Decl.parse("""
        type Tree :=
            Leaf
          | Node(left Tree, value Int64, right Tree)
        """)

      assert t.name == "Tree"

      assert [%Variant{ctor: "Leaf", fields: []}, %Variant{ctor: "Node", fields: node_fields}] =
               t.variants

      assert node_fields == [
               %Field{label: "left", type: "Tree"},
               %Field{label: "value", type: "Int64"},
               %Field{label: "right", type: "Tree"}
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

    test "a `case` body lowers to both targets — Rust resolves constructor patterns via meta" do
      [{"area", out}] =
        Decl.compile("""
        type Shape := Circle(radius Float64) | Square(side Float64)

        def area(s val Shape) Float64
          case s do
            Circle(r) -> 3.14 * r * r
            Square(x) -> x * x
          end
        end
        """)

      assert out.elixir =~ "case s do {:circle, r} -> 3.14 * r * r; {:square, x} -> x * x end"
      # the ambient type meta lets the nested `case` emit Rust enum patterns
      assert out.rust =~ "Shape::Circle { radius: r } => 3.14 * r * r,"
      assert out.rust =~ "Shape::Square { side: x } => x * x,"

      Code.eval_string("defmodule AreaCaseFromSource do\n#{out.elixir}\nend")
      assert_in_delta AreaCaseFromSource.area({:circle, 2.0}), 3.14 * 4, 1.0e-9
      assert AreaCaseFromSource.area({:square, 3.0}) == 9.0
    end

    test "multiline block bodies lower and run (the token parser's headline)" do
      [{"step", out}] =
        Decl.compile("""
        def step(n Int64) Int64
          a := n * 2
          a + 1
        end
        """)

      assert out.elixir =~ "def step(n) do a = n * 2; a + 1 end"
      # a multi-statement block is braced inside the Rust match arm
      assert out.rust =~ "n => { let a = n * 2; a + 1 },"

      Code.eval_string("defmodule StepFromSource do\n#{out.elixir}\nend")
      assert StepFromSource.step(3) == 7
    end

    test "a block body containing an `if` expression lowers and runs" do
      [{"clamp", out}] =
        Decl.compile("""
        def clamp(n Int64) Int64
          if n < 0 do 0 else n end
        end
        """)

      Code.eval_string("defmodule ClampFromSource do\n#{out.elixir}\nend")
      assert ClampFromSource.clamp(-5) == 0
      assert ClampFromSource.clamp(7) == 7
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

  describe "alias declarations (transparent synonyms)" do
    test "an alias is substituted out of every type position (transitively)" do
      %{funcs: [f]} =
        Decl.parse("""
        alias Id := Int64
        alias Count := Id

        def add(x Id, y Count) Id := x + y
        """)

      assert f.params == [
               %Param{name: "x", type: "Int64", cap: :val},
               %Param{name: "y", type: "Int64", cap: :val}
             ]

      assert f.ret == "Int64"
    end

    test "an alias inside a compound type resolves and lowers" do
      [{"first", out}] =
        Decl.compile("""
        alias Id := Int64
        def first(xs val Vec(Id), d Id) Id := head(xs)
        """)

      # Vec(Id) -> Vec(Int64) -> &[i64], and the bare `Id` params/ret -> i64
      assert out.rust =~ "fn first(xs: &[i64], d: i64) -> i64"
    end
  end

  describe "with expressions (ADR-0040 propagation)" do
    @with_src """
    mod Wth do
      def parse(n Int64) R
        case n do
          0 -> {:error, 99}
          _ -> {:ok, n}
        end
      end

      pub def add(a Int64, b Int64) R
        with {:ok, x} <- parse(a),
             {:ok, y} <- parse(b) do
          {:ok, x + y}
        else
          {:error, e} -> {:error, e}
        end
      end
    end
    """

    test "with lowers to native Elixir `with`/`else` and a Rust match chain" do
      [{"Wth", out}] = Decl.compile(@with_src)

      assert out.elixir =~ "with {:ok, x} <- parse(a), {:ok, y} <- parse(b) do"
      assert out.elixir =~ "else {:error, e} -> {:error, e} end"
      # Rust: nested match short-circuiting to the else arm
      assert out.rust =~ "match parse(a) { Ok(x) =>"
      assert out.rust =~ "__w => match __w { Err(e) => Err(e), }"
    end

    test "with propagation runs on the BEAM (happy path and short-circuit)" do
      [{"Wth", out}] = Decl.compile(@with_src)
      Code.eval_string(out.elixir)
      assert Wth.add(2, 3) == {:ok, 5}
      assert Wth.add(0, 3) == {:error, 99}
      assert Wth.add(2, 0) == {:error, 99}
    end

    test "with no `else` propagates the non-matching value unchanged" do
      [{"prop", out}] =
        Decl.compile("""
        def prop(r R) R
          with {:ok, v} <- r do
            {:ok, v + 1}
          end
        end
        """)

      assert out.elixir =~ "with {:ok, v} <- r do {:ok, v + 1} end"
      refute out.elixir =~ "else"
      assert out.rust =~ "__w => __w,"

      Code.eval_string("defmodule PropT do\n#{out.elixir}\nend")
      assert PropT.prop({:ok, 41}) == {:ok, 42}
      assert PropT.prop({:error, :nope}) == {:error, :nope}
    end
  end

  describe "tuples and atoms (the Result surface, ADR-0040)" do
    test "tuple construction lowers to a BEAM tuple / Rust tuple and runs" do
      [{"pair", out}] = Decl.compile("def pair(a Int64, b Int64) Pair := {a, b}")
      assert out.elixir =~ "def pair(a, b) do {a, b} end"
      assert out.rust =~ "(a, b)"
      Code.eval_string("defmodule TupT do\n#{out.elixir}\nend")
      assert TupT.pair(1, 2) == {1, 2}
    end

    test "a tuple pattern in a clause head destructures and runs" do
      [{"fst", out}] =
        Decl.compile("""
        def fst(Pair) Int64
        def fst({a, b}) := a
        """)

      assert out.elixir =~ "def fst({a, b}) do a end"
      Code.eval_string("defmodule TupP do\n#{out.elixir}\nend")
      assert TupP.fst({3, 4}) == 3
    end

    test "`{:ok, v}` / `{:error, e}` are the Result surface — tagged tuple / Ok-Err on Rust" do
      [{"wrap", out}] = Decl.compile("def wrap(v Int64) R := {:ok, v}")
      assert out.elixir =~ "{:ok, v}"
      assert out.rust =~ "Ok(v)"

      [{"fail", out2}] = Decl.compile("def fail(e Int64) R := {:error, e}")
      assert out2.rust =~ "Err(e)"
    end
  end

  describe "sum-variant construction in bodies" do
    test "positional and nullary variant construction lower and run" do
      results =
        Decl.compile("""
        type Shape := Circle(radius Float64) | Square(side Float64)
        type Color := Red | Green | Blue

        def circ(r Float64) Shape := Circle(r)
        def pick(b Bool) Color := Red
        """)

      {"circ", c} = List.keyfind(results, "circ", 0)
      {"pick", p} = List.keyfind(results, "pick", 0)

      assert c.elixir =~ "def circ(r) do {:circle, r} end"
      assert c.rust =~ "Shape::Circle { radius: r }"
      assert p.elixir =~ "def pick(b) do :red end"
      assert p.rust =~ "Color::Red"

      Code.eval_string("defmodule Ctor1 do\n#{c.elixir}\nend")
      assert Ctor1.circ(2.0) == {:circle, 2.0}
    end

    test "named variant construction places fields by label" do
      [{"circ", c}] =
        Decl.compile("""
        type Shape := Circle(radius Float64) | Square(side Float64)
        def circ(r Float64) Shape := Circle(radius: r)
        """)

      assert c.elixir =~ "def circ(r) do {:circle, r} end"
      assert c.rust =~ "Shape::Circle { radius: r }"
    end

    test "an unlabeled-field variant constructs as a positional tuple / tuple variant" do
      [{"wrap", c}] =
        Decl.compile("""
        type Value := Num(Int64) | Zero
        def wrap(n Int64) Value := Num(n)
        """)

      assert c.elixir =~ "def wrap(n) do {:num, n} end"
      assert c.rust =~ "Value::Num(n)"

      Code.eval_string("defmodule Ctor2 do\n#{c.elixir}\nend")
      assert Ctor2.wrap(7) == {:num, 7}
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

  describe "struct declarations (product types)" do
    test "a struct parses into a %Struct{} with labeled fields" do
      %{structs: [s]} = Decl.parse("struct Point(x Float64, y Float64)")

      assert s == %Struct{
               name: "Point",
               fields: [%Field{label: "x", type: "Float64"}, %Field{label: "y", type: "Float64"}]
             }
    end

    test "a struct lowers to defstruct / Rust struct, and `Name(args)` builds it" do
      [{"origin", out}] =
        Decl.compile("""
        struct Point(x Float64, y Float64)

        def origin(d Float64) Point := Point(d, d)
        """)

      assert out.elixir =~ "defmodule Point do defstruct [:x, :y] end"
      assert out.elixir =~ "%Point{x: d, y: d}"
      assert out.rust =~ "struct Point { x: f64, y: f64 }"
      assert out.rust =~ "Point { x: d, y: d }"
    end

    test "a struct value built from source runs on the BEAM, with field access" do
      [{"shift", out}] =
        Decl.compile("""
        struct Point(x Int64, y Int64)

        def shift(p val Point, d Int64) Point := Point(p.x + d, p.y + d)
        """)

      Code.eval_string("defmodule ShiftFromSource do\n#{out.elixir}\nend")
      # build the struct dynamically — the module is defined at runtime, so a
      # `%Mod{}` literal cannot be compile-time expanded here.
      point = struct(ShiftFromSource.Point, x: 1, y: 2)
      assert ShiftFromSource.shift(point, 10) == struct(ShiftFromSource.Point, x: 11, y: 12)
    end

    test "named construction places fields by name (order-independent)" do
      [{"make", out}] =
        Decl.compile("""
        struct Point(x Int64, y Int64)

        def make(a Int64, b Int64) Point := Point(y: b, x: a)
        """)

      # written `y:` first, but emitted in the struct's declared field order
      assert out.elixir =~ "%Point{x: a, y: b}"
      assert out.rust =~ "Point { x: a, y: b }"

      Code.eval_string("defmodule MakeFromSource do\n#{out.elixir}\nend")
      assert MakeFromSource.make(1, 2) == struct(MakeFromSource.Point, x: 1, y: 2)
    end

    test "a missing named field is rejected at lowering" do
      assert_raise RuntimeError, ~r/missing field `y`/, fn ->
        Decl.compile("""
        struct Point(x Int64, y Int64)
        def bad(a Int64) Point := Point(x: a)
        """)
      end
    end

    test "an alias resolves inside struct fields" do
      %{structs: [s]} =
        Decl.parse("""
        alias Id := Int64
        struct Row(id Id, n Int64)
        """)

      assert s.fields == [%Field{label: "id", type: "Int64"}, %Field{label: "n", type: "Int64"}]
    end
  end

  describe "mod declarations (modules with pub visibility)" do
    @mod """
    mod Geometry do
      pub type Shape := Circle(radius Float64) | Square(side Float64)

      pub def area(Shape) Float64
      pub def area(Circle(r)) := 3.14159265 * r * r
      pub def area(Square(s)) := s * s

      def square(x Float64) Float64 := x * x
    end
    """

    test "a mod parses into a %Mod{} carrying its types and funcs, with pub flags" do
      %{mods: [m], funcs: []} = Decl.parse(@mod)

      assert m.name == "Geometry"
      assert [%Type{name: "Shape", pub?: true}] = m.types
      assert [%Func{name: "area", pub?: true}, %Func{name: "square", pub?: false}] = m.funcs
    end

    test "a mod lowers to defmodule / Rust mod, exporting pub items and hiding the rest" do
      [{"Geometry", out}] = Decl.compile(@mod)

      assert out.elixir =~ "defmodule Geometry do"
      assert out.elixir =~ "def area("
      # the private helper is `defp`
      assert out.elixir =~ "defp square(x) do x * x end"
      assert out.rust =~ "mod geometry {"
      assert out.rust =~ "pub fn area("
      assert out.rust =~ "fn square(x: f64) -> f64"
      refute out.rust =~ "pub fn square"
    end

    test "the emitted module runs on the BEAM" do
      [{"Geometry", out}] = Decl.compile(@mod)
      Code.eval_string(out.elixir)
      assert_in_delta Geometry.area({:circle, 2.0}), 3.14159265 * 4, 1.0e-6
      assert Geometry.area({:square, 3.0}) == 9.0
    end

    test "top-level functions and a module coexist in one compilation" do
      results =
        Decl.compile("""
        def double(n Int64) Int64 := n * 2

        mod M do
          pub def triple(n Int64) Int64 := n * 3
        end
        """)

      assert {"double", _} = List.keyfind(results, "double", 0)
      assert {"M", mout} = List.keyfind(results, "M", 0)
      assert mout.elixir =~ "defmodule M do"
      assert mout.elixir =~ "def triple(n) do n * 3 end"
    end
  end

  describe "const declarations (module constants)" do
    @consts """
    mod Scaling do
      pub const TAU Float64 := 6.28318530
      const SCALE Float64 := 2.0

      pub def scaled(r Float64) Float64 := TAU * r * SCALE
    end
    """

    test "consts lower to accessors / Rust const, and references resolve per target" do
      [{"Scaling", out}] = Decl.compile(@consts)

      assert out.elixir =~ "def tau() do 6.28318530 end"
      assert out.elixir =~ "defp scale() do 2.0 end"
      assert out.elixir =~ "def scaled(r) do tau() * r * scale() end"

      assert out.rust =~ "pub const TAU: f64 = 6.28318530;"
      assert out.rust =~ "const SCALE: f64 = 2.0;"
      assert out.rust =~ "TAU * r * SCALE"
    end

    test "a module with constants runs on the BEAM" do
      [{"Scaling", out}] = Decl.compile(@consts)
      Code.eval_string(out.elixir)
      assert_in_delta Scaling.scaled(3.0), 6.28318530 * 3.0 * 2.0, 1.0e-9
    end

    test "a top-level const (no enclosing module) is rejected" do
      assert_raise Decl.Error, ~r/`const` must appear inside a `mod`/, fn ->
        Decl.parse("const TAU Float64 := 6.28")
      end
    end
  end

  describe "use imports (module-scoped)" do
    test "qualified and selective imports lower to alias/import and Rust use" do
      [{"Geo", out}] =
        Decl.compile("""
        mod Geo do
          use Math
          use Std.(Vec, sqrt)

          pub def root(x Float64) Float64 := sqrt(x)
        end
        """)

      assert out.elixir =~ "alias Math"
      assert out.elixir =~ "import Std"
      assert out.rust =~ "use math;"
      assert out.rust =~ "use std::{Vec, sqrt};"
      # a name from a selective import is emitted bare; the import resolves it
      assert out.rust =~ "sqrt(x)"
    end

    test "an imported module's qualified call runs on the BEAM" do
      [{"Shout", out}] =
        Decl.compile("""
        mod Shout do
          use String
          pub def yell(s String) String := String.upcase(s)
        end
        """)

      assert out.elixir =~ "alias String"
      Code.eval_string(out.elixir)
      assert Shout.yell("hi") == "HI"
    end

    test "a top-level use (no enclosing module) is rejected" do
      assert_raise Decl.Error, ~r/`use` must appear inside a `mod`/, fn ->
        Decl.parse("use Math")
      end
    end
  end

  describe "honest limits raise Rian.Decl.Error" do
    test "unsupported declaration keywords are rejected" do
      assert_raise Decl.Error, ~r/unsupported declaration `macro`/, fn ->
        Decl.parse("macro m() := 1")
      end
    end
  end
end
