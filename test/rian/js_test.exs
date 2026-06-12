defmodule Rian.JSTest do
  use ExUnit.Case, async: true

  alias Rian.JS

  # Run emitted JS through node when available; nil when node is absent (CI may
  # lack it — the shape assertions still run unconditionally).
  defp node_eval(js, expr) do
    case System.find_executable("node") do
      nil ->
        :no_node

      node ->
        path = Path.join(System.tmp_dir!(), "rian_js_#{System.unique_integer([:positive])}.mjs")
        File.write!(path, js <> "\nconsole.log(String(#{expr}));\n")
        {out, 0} = System.cmd(node, [path])
        File.rm(path)
        String.trim(out)
    end
  end

  describe "ECMAScript emitter on the typed core IR (ADR-0049 / ADR-0050)" do
    test "a one-liner: Int64 -> BigInt, local function" do
      js = JS.compile("def double(n Int64) Int64 := n * 2")
      assert js =~ "function double(a0)"
      assert js =~ "n * 2n"

      case node_eval(js, "double(21n)") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end

    test "multi-clause with a guard lowers to a dispatcher (binds precede the guard)" do
      js =
        JS.compile("""
        def max2(a Int64, b Int64) Int64
        def max2(a, b) when a >= b := a
        def max2(_, b) := b
        """)

      assert js =~ "function max2(a0, a1)"
      assert js =~ "const a = a0;"
      assert js =~ "if ((a >= b))"
      assert js =~ ~s|throw new Error("max2: no clause matched")|

      case node_eval(js, "[max2(3n,7n), max2(9n,2n)].join(',')") do
        :no_node -> :ok
        out -> assert out == "7,9"
      end
    end

    test "literal clause patterns + recursion (factorial)" do
      js =
        JS.compile("""
        def fact(n Int64) Int64
        def fact(0) := 1
        def fact(n) := n * fact(n - 1)
        """)

      assert js =~ "if (a0 === 0n)"

      case node_eval(js, "fact(5n)") do
        :no_node -> :ok
        out -> assert out == "120"
      end
    end

    test "a `pub` function is exported" do
      assert JS.compile("def f(n Int64) Int64 := n") =~ "function f("
      # pub only meaningful inside a mod; emit `export` there
      js = JS.compile("mod M do\n  pub def g(n Int64) Int64 := n\nend")
      assert js =~ "export function g("
    end

    test "sum variants: construction + nested clause patterns (ADR-0049)" do
      js =
        JS.compile("""
        type Expr := Num(Int64) | Add(Expr, Expr)
        pub def evalexpr(e Expr) Int64
        pub def evalexpr(Num(n)) := n
        pub def evalexpr(Add(a, b)) := evalexpr(a) + evalexpr(b)
        """)

      # a constructor pattern checks the tag and binds positional fields
      assert js =~ ~s|a0[0] === "Num"|
      assert js =~ ~s|a0[0] === "Add"|
      assert js =~ "const a = a0[1];"
      assert js =~ "const b = a0[2];"

      # Add(Num(2), Add(Num(3), Num(4)))  ->  9 (tagged arrays = how a variant lowers)
      expr = ~s|["Add",["Num",2n],["Add",["Num",3n],["Num",4n]]]|

      case node_eval(js, "evalexpr(#{expr})") do
        :no_node -> :ok
        out -> assert out == "9"
      end
    end

    test "sum-variant construction emits a tagged array, round-tripping under node" do
      js =
        JS.compile("""
        type Color := Red | Green
        pub def flip(c Color) Color
        pub def flip(Red) := Green
        pub def flip(Green) := Red
        """)

      # nullary construction -> a one-element tagged array
      assert js =~ ~s|return ["Green"];|
      assert js =~ ~s|a0[0] === "Red"|

      case node_eval(js, "JSON.stringify(flip(['Red']))") do
        :no_node -> :ok
        out -> assert out == ~s|["Green"]|
      end
    end

    test "the self-hosting optimizer spike lowers to JS and folds under node (multi-target)" do
      js = JS.compile(File.read!("examples/rian/selfhost_opt.rian"))

      # (2 + 3) * 4  ->  Num(20);  a constant tree folds to one literal
      tree = ~s|["Mul",["Add",["Num",2n],["Num",3n]],["Num",4n]]|
      # x * 1 + 0  ->  Var("x");  algebraic identities, matched by shape
      ident = ~s|["Add",["Mul",["Var","x"],["Num",1n]],["Num",0n]]|

      case node_eval(
             js,
             "JSON.stringify(fold(#{tree}), (k,v)=>typeof v==='bigint'?v.toString():v)"
           ) do
        :no_node -> :ok
        out -> assert out == ~s|["Num","20"]|
      end

      case node_eval(js, "JSON.stringify(fold(#{ident}))") do
        :no_node -> :ok
        out -> assert out == ~s|["Var","x"]|
      end
    end

    test "constructs outside this increment raise a clear Unsupported" do
      # list construction has no JS lowering yet (variants now do)
      assert_raise JS.Unsupported, fn ->
        JS.compile("def xs(n Int64) Vec(Int64) := [1, 2, 3]")
      end
    end
  end
end
