defmodule Rian.DeclTest do
  # async: false — the execution tests define modules via Code.eval_string.
  use ExUnit.Case, async: false

  alias Rian.Decl
  alias Rian.IR.{Clause, Const, Field, Func, Param, Struct, Type, Variant}

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

    test "a bare parameter defaults to `val`; only iso/ref/tag are spelled (ADR-0070)" do
      %{funcs: [f]} =
        Decl.parse(
          "def f(a Int64, b val Int64, c iso Vec(Int64), d ref Int64, e tag Bool) Int64 := a"
        )

      assert Enum.map(f.params, &{&1.name, &1.cap}) == [
               {"a", :val},
               {"b", :val},
               {"c", :iso},
               {"d", :ref},
               {"e", :tag}
             ]
    end

    test "a `:=` body is newline-tolerant (P1): trailing/leading op, brackets, next line" do
      bodies = fn src ->
        Decl.parse(src).funcs |> hd() |> Map.fetch!(:clauses) |> hd() |> Map.fetch!(:body)
      end

      # trailing binary operator continues onto the next line
      assert bodies.("def f(a Int64, b Int64) Int64 := a +\n  b") == "a + b"
      # leading binary operator continues the previous line
      assert bodies.("def g(a Int64, b Int64) Int64 := a\n  + b * 2") == "a + b * 2"
      # a newline inside unbalanced parens continues
      assert bodies.("def h(xs Vec(Int64)) Int64 := sum(\n  xs\n)") == "sum ( xs )"
      # the body may simply begin on the next line
      assert bodies.("def k(n Int64) Int64 :=\n  n * n + 1") == "n * n + 1"
      # a plain one-liner still ends at its newline (next decl is separate)
      %{funcs: [a, b]} = Decl.parse("def p() Int64 := 1\ndef q() Int64 := 2")
      assert a.name == "p" and b.name == "q"
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
      # the `&str` arm is coerced to the owned `String` the signature returns
      assert out.rust =~ "fn classify(n: i64) -> String"
      assert out.rust =~ "n if n > 0 => (\"positive\").to_string(),"

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

  describe "doc comments (ADR-0051)" do
    @docs """
    @moduledoc "A tiny module."
    mod M do
      @typedoc "A colour."
      pub type Color := Red | Green

      @doc "Double a number."
      pub def double(n Int64) Int64 := n * 2
    end
    """

    test "@moduledoc/@typedoc/@doc attach to the IR (heredoc + single-line)" do
      %{mods: [m]} =
        Decl.parse("""
        @moduledoc \"\"\"
        Multi-line
        module doc.
        \"\"\"
        mod M do
          @doc "one liner"
          pub def f(n Int64) Int64 := n
        end
        """)

      assert m.doc == "Multi-line\nmodule doc."
      assert hd(m.funcs).doc == "one liner"
    end

    test "docs lower to @moduledoc/@typedoc/@doc on the BEAM" do
      [{"M", out}] = Decl.compile(@docs)
      assert out.elixir =~ ~s(@moduledoc "A tiny module.")
      assert out.elixir =~ ~s(@typedoc "A colour.")
      assert out.elixir =~ ~s(@doc "Double a number.")
    end

    test "docs lower to rustdoc `//!` / `///`" do
      [{"M", out}] = Decl.compile(@docs)
      assert out.rust =~ "//! A tiny module."
      assert out.rust =~ "/// A colour."
      assert out.rust =~ "/// Double a number."
    end

    test "an unknown annotation is rejected" do
      assert_raise Decl.Error, ~r/unsupported annotation `@bogus`/, fn ->
        Decl.parse(~s|@bogus "x"\ndef f(n Int64) Int64 := n|)
      end
    end
  end

  describe "prelude: Option (ADR-0047 §3 — no nil)" do
    test "Some/None are built-in — usable with no `type Option` declaration" do
      [{"wrap", out}] = Decl.compile("def wrap(x Int64) Option := Some(x)")
      assert out.elixir =~ "def wrap(x) do {:some, x} end"
      # native Rust Option; the prelude type is NOT re-emitted as a user enum
      assert out.rust =~ "Option::Some(x)"
      refute out.rust =~ "enum Option"

      Code.eval_string("defmodule WrapO do\n#{out.elixir}\nend")
      assert WrapO.wrap(5) == {:some, 5}
    end

    test "case over Option is exhaustive with Some/None and no catch-all" do
      [{"uo", out}] =
        Decl.compile_beam("""
        def uo(o Option, d Int64) Int64
        def uo(Some(x), _) := x
        def uo(None, d) := d
        """)

      Code.eval_string("defmodule UoO do\n#{out.elixir}\nend")
      assert UoO.uo({:some, 7}, 0) == 7
      assert UoO.uo(:none, 0) == 0
    end

    test "a non-exhaustive Option match is refused (None missing) — prelude is known to the gate" do
      assert_raise RuntimeError, ~r/non-exhaustive/, fn ->
        Decl.compile_beam("def uo(o Option) Int64\ndef uo(Some(x)) := x")
      end
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

  describe "`T | E` return-type sugar (ADR-0040 §2)" do
    test "lowers to Rust Result<T, E>; the BEAM body carries the tagged tuple" do
      [{"find", out}] = Decl.compile("def find(id Int64) User | NotFound := {:ok, id}")
      assert out.rust =~ "fn find(id: i64) -> Result<User, NotFound>"
      assert out.elixir =~ "def find(id) do {:ok, id} end"
    end

    test "an alias resolves inside the result type" do
      [{"f", out}] =
        Decl.compile("""
        alias Id := Int64
        def f(x Id) Id | NotFound := {:ok, x}
        """)

      assert out.rust =~ "-> Result<i64, NotFound>"
    end

    test "an inline multi-tag error set is rejected (must be a named set)" do
      assert_raise RuntimeError, ~r/must be named/, fn ->
        Decl.compile("def f(x Int64) User | A | B := {:ok, x}")
      end
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

  describe "one parser (ADR-0050 §2) — clause heads reuse Pratt's pattern parser" do
    test "string-literal clause patterns now work (parity the old Decl parser lacked)" do
      [{"classify", out}] =
        Decl.compile_beam("""
        def classify(s String) Int64
        def classify("hi") := 1
        def classify(_) := 0
        """)

      assert out.elixir =~ "def classify(\"hi\") do 1 end"
      Code.eval_string("defmodule ClsT do\n#{out.elixir}\nend")
      assert ClsT.classify("hi") == 1
      assert ClsT.classify("x") == 0
    end

    test "negative-integer clause patterns work" do
      [{"f", out}] =
        Decl.compile_beam("""
        def f(n Int64) Int64
        def f(-1) := 0
        def f(n) := n
        """)

      assert out.elixir =~ "def f(-1) do 0 end"
      Code.eval_string("defmodule NegT do\n#{out.elixir}\nend")
      assert NegT.f(-1) == 0
      assert NegT.f(7) == 7
    end
  end

  describe "list patterns (B1 / self-hosting spike)" do
    test "cons recursion in clause heads runs on the BEAM" do
      [{"sum", out}] =
        Decl.compile_beam("""
        def sum(xs Vec(Int64)) Int64
        def sum([]) := 0
        def sum([h | t]) := h + sum(t)
        """)

      assert out.elixir =~ "def sum([]) do 0 end"
      assert out.elixir =~ "def sum([h | t]) do h + sum(t) end"
      Code.eval_string("defmodule SumT do\n#{out.elixir}\nend")
      assert SumT.sum([1, 2, 3, 4]) == 10
    end

    test "a fixed-length list pattern lowers to a Rust slice pattern" do
      [{"pair", out}] =
        Decl.compile("""
        def pair(xs Vec(Int64)) Int64
        def pair([a, b]) := a + b
        def pair(_) := 0
        """)

      assert out.elixir =~ "def pair([a, b]) do a + b end"
      assert out.rust =~ "[a, b] =>"
    end

    test "a `case` over a list lowers and runs" do
      [{"head0", out}] =
        Decl.compile_beam("""
        def head0(xs Vec(Int64)) Int64
          case xs do
            [] -> 0
            [h | _] -> h
          end
        end
        """)

      Code.eval_string("defmodule HeadT do\n#{out.elixir}\nend")
      assert HeadT.head0([7, 8]) == 7
      assert HeadT.head0([]) == 0
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
      assert_raise Decl.Error, ~r/unsupported declaration `case`/, fn ->
        Decl.parse("case x do end")
      end
    end

    test "`macro` is now a supported declaration (ADR-0030): emits no IR, expands at call sites" do
      # the macro itself produces no func; its call is expanded into the body
      prog = Decl.parse("macro sq(x) := x * x\ndef area(n Int64) Int64 := sq(n)")
      assert [%{name: "area"}] = prog.funcs
      assert [%{body: {:block, _}}] = hd(prog.funcs).clauses
    end
  end

  # ── Coverage: malformed declarations that the parser must reject ───────────
  describe "malformed alias declarations are rejected" do
    test "an `alias` with no `:=` is rejected" do
      assert_raise Decl.Error, ~r/alias needs `:=`/, fn ->
        Decl.parse("alias Id\ndef f(n Int64) Int64 := n")
      end
    end
  end

  describe "malformed declaration heads are rejected" do
    test "`mod` without `Name do` is rejected" do
      assert_raise Decl.Error, ~r/expected `mod Name do … end`/, fn ->
        Decl.parse("mod M")
      end
    end

    test "a token that is not a declaration head is rejected" do
      assert_raise Decl.Error, ~r/expected a declaration, got/, fn ->
        Decl.parse("42")
      end
    end

    test "an unclosed `mod` body is rejected" do
      assert_raise Decl.Error, ~r/`mod` body not closed by `end`/, fn ->
        Decl.parse("mod M do\n  type X := A")
      end
    end

    test "`pub` before something other than def/type/struct/const is rejected" do
      assert_raise Decl.Error,
                   ~r/`pub` may only precede `def` \/ `type` \/ `struct` \/ `const`/,
                   fn ->
                     Decl.parse("mod M do\n  pub use Math\nend")
                   end
    end
  end

  describe "malformed `def` heads / signatures are rejected" do
    test "`def` not followed by a function name is rejected" do
      assert_raise Decl.Error, ~r/expected a function name after `def`/, fn ->
        Decl.parse("def 42() Int64 := 1")
      end
    end

    test "a block body never closed by `end` is rejected" do
      assert_raise Decl.Error, ~r/block body not closed by `end`/, fn ->
        Decl.parse("def f(n Int64) Int64\n  n + 1")
      end
    end

    test "a `def` with no `(` after the name is rejected" do
      assert_raise Decl.Error, ~r/expected `\(` after the function name/, fn ->
        Decl.parse("def f n Int64 := n")
      end
    end

    test "an unbalanced `(` in the parameter list is rejected" do
      assert_raise Decl.Error, ~r/unbalanced `\(` in the parameter list/, fn ->
        Decl.parse("def f(n Int64 := n")
      end
    end

    test "a signature with no following clauses is rejected" do
      assert_raise Decl.Error, ~r/function `f` has a signature but no clauses/, fn ->
        Decl.parse("def f(n Int64) Int64")
      end
    end

    test "two bodied clauses that cannot be grouped are rejected" do
      assert_raise Decl.Error, ~r/cannot group clauses of `f`/, fn ->
        Decl.parse("def f(n Int64) Int64 := n\ndef f(n Int64) Int64 := n")
      end
    end

    test "a pattern clause with no body is rejected" do
      assert_raise Decl.Error, ~r/clause of `f` has no body/, fn ->
        Decl.parse("def f(n Int64) Int64\ndef f(n)\ndef f(x) := x")
      end
    end

    test "multiple capabilities on a parameter are rejected" do
      assert_raise Decl.Error, ~r/multiple capabilities on/, fn ->
        Decl.parse("def f(x val iso Int64) Int64 := x")
      end
    end

    test "a malformed parameter (more than name + type) is rejected" do
      assert_raise Decl.Error, ~r/bad parameter/, fn ->
        Decl.parse("def f(a b c Int64) Int64 := a")
      end
    end

    test "a function with a body but no return type is rejected" do
      assert_raise Decl.Error, ~r/function `f` needs a return type/, fn ->
        Decl.parse("def f(n Int64) := n")
      end
    end
  end

  describe "malformed type / struct / const / use / variant / field are rejected" do
    test "a `type` with no `:=` is rejected" do
      assert_raise Decl.Error, ~r/type declaration needs `:=`/, fn ->
        Decl.parse("type X")
      end
    end

    test "trailing tokens after a struct declaration are rejected" do
      assert_raise Decl.Error, ~r/trailing tokens after struct/, fn ->
        Decl.parse("struct P(x Int64) extra")
      end
    end

    test "a `const` whose declaration is not `NAME Type` is rejected" do
      assert_raise Decl.Error, ~r/const needs `NAME Type := value`/, fn ->
        Decl.parse("mod M do\n  const X := 1\nend")
      end
    end

    test "a `const` with no `:=` is rejected" do
      assert_raise Decl.Error, ~r/const needs `:=`/, fn ->
        Decl.parse("mod M do\n  const X Int64\nend")
      end
    end

    test "trailing tokens after a `use` selective import are rejected" do
      assert_raise Decl.Error, ~r/trailing tokens after use/, fn ->
        Decl.parse("mod M do\n  use Std.(a) extra\nend")
      end
    end

    test "trailing tokens after a variant are rejected" do
      assert_raise Decl.Error, ~r/trailing tokens after variant/, fn ->
        Decl.parse("type X := A(x Int64) junk")
      end
    end

    test "a field that is neither `Type` nor `label Type` is rejected" do
      assert_raise Decl.Error, ~r/bad field/, fn ->
        Decl.parse("struct P(a b c)")
      end
    end
  end

  describe "coverage: valid declarations exercising pub / doc / empty / guard branches" do
    test "`pub struct` sets the export flag" do
      %{structs: [s]} = Decl.parse("pub struct Point(x Int64)")
      assert %Struct{name: "Point", pub?: true} = s
    end

    test "a doc comment attaches to a struct / const" do
      %{structs: [s]} = Decl.parse(~s|@typedoc "str"\nstruct Point(x Int64)|)
      assert s.doc == "str"

      %{mods: [m]} = Decl.parse(~s|mod M do\n  @doc "c"\n  const X Int64 := 1\nend|)
      assert [%Const{name: "X", doc: "c"}] = m.consts
    end

    test "a bare `struct Name` and `struct Name()` parse to a zero-field record" do
      assert %{structs: [%Struct{name: "Empty", fields: []}]} = Decl.parse("struct Empty")
      assert %{structs: [%Struct{name: "Empty", fields: []}]} = Decl.parse("struct Empty()")
    end

    test "a signature head carrying ` when ` parses (split2 / guard branch)" do
      %{funcs: [f]} =
        Decl.parse("def f(n Int64) Int64 when n > 0\ndef f(n) := n")

      assert f.name == "f"
      assert f.ret == "Int64"
    end

    test "an unclosed `(` in a struct field list runs match_paren to the end" do
      # extract_parens opens on `(`, match_paren consumes to end with no close
      assert %{structs: [%Struct{name: "P", fields: [%Field{label: "x", type: "Int64"}]}]} =
               Decl.parse("struct P(x Int64")
    end
  end
end
