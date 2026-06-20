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
    test "a one-liner: Int -> BigInt, local function" do
      js = JS.compile("def double(n Int) Int := n * 2")
      assert js =~ "function double(a0)"
      assert js =~ "n * 2n"

      case node_eval(js, "double(21n)") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end

    test "a value-union type-pattern narrows by `typeof` and runs (ADR-0083)" do
      js =
        JS.compile("""
        def describe(x Int53 | String) Int53 := case x do
          n Int53 -> n + 1
          s String -> 0
        end
        """)

      assert js =~ ~s(typeof _s === "number")
      assert js =~ ~s(typeof _s === "string")

      case node_eval(js, "[describe(41), describe('hi')].join(',')") do
        :no_node -> :ok
        out -> assert out == "42,0"
      end
    end

    test "a value union of SUM members narrows by the tagged-array head and runs (ADR-0083)" do
      js =
        JS.compile("""
        type Box := BoxV(Int53)
        type Bag := BagV(Int53)
        def kind(x Box | Bag) Int53 := case x do
          a Box -> 1
          b Bag -> 2
        end
        """)

      # a sum value is `["Ctor", …]`, so "is a Box" tests the head against Box's tags
      assert js =~ ~s|Array.isArray(_s) && (_s[0] === "BoxV")|
      assert js =~ ~s|Array.isArray(_s) && (_s[0] === "BagV")|

      case node_eval(js, "[kind(['BoxV',5]), kind(['BagV',9])].join(',')") do
        :no_node -> :ok
        out -> assert out == "1,2"
      end
    end

    test "a value union of STRUCT members narrows by `__struct__` and runs (ADR-0083)" do
      js =
        JS.compile("""
        struct Box(v Int53)
        struct Widget(n Int53)
        def pick(x Box | Widget) Int53 := case x do
          b Box -> b.v
          w Widget -> w.n
        end
        """)

      # a struct value is `{ __struct__: "Box", … }`, so "is a Box" tests that tag
      assert js =~ ~s|__struct__ === "Box"|

      case node_eval(
             js,
             "[pick({__struct__:'Box',v:7}), pick({__struct__:'Widget',n:9})].join(',')"
           ) do
        :no_node -> :ok
        out -> assert out == "7,9"
      end
    end

    test "a `const` reference resolves to the emitted top-level const, not a bare identifier" do
      js = JS.compile("mod M do\n  const Answer := 42\n  pub def get() Int53 := Answer\nend")
      assert js =~ "const Answer = 42;"
      assert js =~ "return Answer;"

      # before the const-resolution pass this emitted bare `Answer` with no
      # declaration, so Node threw `ReferenceError`; now it runs.
      case node_eval(js, "get()") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end

    test "a multi-statement `const` value wraps in an IIFE (still a single binding)" do
      js = JS.compile("mod M do\n  const X := a := 40; a + 2\n  pub def g() Int53 := X\nend")
      assert js =~ "const X = (() => { let a = 40; return (a + 2); })();"

      case node_eval(js, "g()") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end

    test "Int53 uses native JS numbers (not BigInt) — exact to 2^53 (ADR-0049)" do
      js53 = JS.compile("def inc(n Int53) Int53 := n + 1")
      # native number literal — no `n` suffix
      assert js53 =~ "(n + 1)"
      refute js53 =~ "1n"

      # Int is unchanged (BigInt)
      assert JS.compile("def inc(n Int) Int := n + 1") =~ "(n + 1n)"

      case node_eval(js53, "[inc(41), typeof inc(41)].join(',')") do
        :no_node -> :ok
        out -> assert out == "42,number"
      end
    end

    test "float `/` lowers to native JS division (ADR-0049 gap closed)" do
      js = JS.compile("def half(x Float64) Float64 := x / 2.0")
      assert js =~ "(x / 2.0)"

      case node_eval(js, "half(7.0)") do
        :no_node -> :ok
        out -> assert out == "3.5"
      end
    end

    test "multi-clause with a guard lowers to a dispatcher (binds precede the guard)" do
      js =
        JS.compile("""
        def max2(a Int, b Int) Int
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
        def fact(n Int) Int
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
      assert JS.compile("def f(n Int) Int := n") =~ "function f("
      # pub only meaningful inside a mod; emit `export` there
      js = JS.compile("mod M do\n  pub def g(n Int) Int := n\nend")
      assert js =~ "export function g("
    end

    test "sum variants: construction + nested clause patterns (ADR-0049)" do
      js =
        JS.compile("""
        type Expr := Num(Int) | Add(Expr, Expr)
        pub def evalexpr(e Expr) Int
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

    test "the explicit 64-bit overflow ops (ADR-0035 §3) are rejected on JS (ADR-0064)" do
      # `Int.wrapping_add`/`saturating_add`/`checked_add` operate on `Int64`, whose
      # two's-complement-at-64 contract has no JS representation. We refuse to
      # silently elevate to `BigInt` (the old `asIntN` lowering), so compiling the
      # 64-bit wrap prelude to JS raises — naming the offending fixed-width type.
      err =
        assert_raise JS.Unsupported, fn ->
          JS.compile(File.read!("examples/rian/prelude_int.rian"))
        end

      assert Exception.message(err) =~ "Int64"
      assert Exception.message(err) =~ "not supported on JS"
    end

    test "the self-hosting optimizer spike lowers to JS and folds under node (multi-target)" do
      js = JS.compile(File.read!("test/fixtures/rian/opt.rian"))

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

    test "the self-hosting parser lowers to JS and parses under node (cons-recursive)" do
      js = JS.compile(File.read!("test/fixtures/rian/parser.rian"))

      # token arrays use the variant convention: TNum(5) -> ["TNum", 5n], TPlus -> ["TPlus"]
      toks =
        ~s|[["TNum",1n],["TPlus"],["TNum",2n],["TStar"],["TLParen"],["TNum",3n],["TMinus"],["TNum",4n],["TRParen"]]|

      # 1 + 2 * (3 - 4)  ->  Add(Num 1, Mul(Num 2, Sub(Num 3, Num 4)))
      expected = ~s|["Add",["Num","1"],["Mul",["Num","2"],["Sub",["Num","3"],["Num","4"]]]]|

      case node_eval(
             js,
             "JSON.stringify(parse(#{toks}), (k,v)=>typeof v==='bigint'?v.toString():v)"
           ) do
        :no_node -> :ok
        out -> assert out == expected
      end
    end

    test "the WHOLE calc compiler lowers to JS and runs end-to-end under node" do
      js = JS.compile(File.read!("test/fixtures/rian/calc.rian"))

      # lexer (FFI) + parser + optimizer + codegen (maps) + VM, all in JS
      assert node_eval(js, "run(\"2 + 3 * 4\").toString()") in [:no_node, "14"]
      assert node_eval(js, "run(\"1 + 2 * (3 - 4)\").toString()") in [:no_node, "-1"]
      # `let`/variables from source survive the round-trip too
      assert node_eval(js, "run(\"let x = 5 in x + 1\").toString()") in [:no_node, "6"]

      assert node_eval(js, "run(\"let x = 1 in (let x = 2 in x) + x\").toString()") in [
               :no_node,
               "3"
             ]
    end

    test "constructs outside this increment raise a clear Unsupported" do
      # general host FFI has no JS lowering (atoms/Result now do; only specific
      # bridges like `:lists.reverse` are wired)
      assert_raise JS.Unsupported, fn ->
        JS.compile("def q() Int := :queue.new()")
      end
    end

    test "a type error is caught by the gate, not emitted as malformed JS (parity)" do
      # JS.compile now runs `Check.gate!` before emitting (parity with the BEAM
      # `Decl.compile` path) — a proven type mismatch raises here, not downstream.
      assert_raise Rian.Check.Error, fn -> JS.compile("def f() Int := true") end
    end

    test "a not-yet-implemented construct fails early with a clear message (naming the fn)" do
      # the emitter-capability pre-check raises ONE clear error up front (Reach stays
      # architectural per ADR-0041 — this is an implementation-status check).
      err =
        assert_raise JS.Unsupported, fn ->
          JS.compile("def f(x Int) Int := with {:ok, v} <- g(x) do v end")
        end

      assert Exception.message(err) =~ "`f`: a `with` expression is not yet supported on :js"
    end

    test "a `ref` param is lowered to value semantics (sound: return-based surface)" do
      # `ref` (&mut) has no JS analog; it only ever changed the Rust signature, so
      # JS emits an ordinary positional binding and the result is correct. Reach
      # reports `ref` as reaching :js, so this MUST compile (not raise) — and the
      # cap must not leak into the emitted parameter. Locks the documented decision:
      # if in-place mutation is ever added, this assertion forces JS to handle it.
      js = JS.compile("def bump(x ref Int) Int := x + 1")
      assert js =~ "function bump(a0)"
      assert js =~ "const x = a0"

      case node_eval(js, "bump(41n)") do
        :no_node -> :ok
        out -> assert out == "42"
      end
    end
  end

  describe "protocol dispatch on JS (ADR-0061 §3)" do
    @show """
    type Expr := Num(n Int) | Zero

    protocol Show do
      def show(self Self) String
    end

    impl Show for Int do
      def show(n) := "int"
    end

    impl Show for Bool do
      def show(b) := "bool"
    end

    impl Show for Expr do
      def show(e)
        case e do
          Num(n) -> "num"
          Zero -> "zero"
        end
      end
    end
    """

    test "the dispatcher uses JS-native guards (typeof + tagged-array head)" do
      js = JS.compile(@show)
      assert js =~ "export function show(a0)"
      assert js =~ ~s(typeof a0 === "bigint")
      assert js =~ ~s(typeof a0 === "boolean")
      assert js =~ "Array.isArray(a0)"
      assert js =~ ~s(a0[0] === "Num")
      assert js =~ ~s(a0[0] === "Zero")
      # no BEAM guard leaked through
      refute js =~ "is_integer"
      refute js =~ "element("
    end

    test "dispatch runs in node over primitives and a sum type" do
      js = JS.compile(@show)
      assert node_eval(js, "show(42n)") in [:no_node, "int"]
      assert node_eval(js, "show(true)") in [:no_node, "bool"]
      assert node_eval(js, ~s/show(["Num", 5n])/) in [:no_node, "num"]
      assert node_eval(js, ~s/show(["Zero"])/) in [:no_node, "zero"]
    end

    test "the integer Eq/Ord stdlib is JS-portable (literals are Int53) and runs in node" do
      # `contains([1, 2, 3], 2)` derives `T = Int53` from the integer literals (the
      # portable default, ADR-0064), so `impl Eq/Ord for Int53` matches and the whole
      # stdlib compiles to JS — number-mode, with the dispatcher guarding on `number`.
      js = JS.compile(File.read!("examples/rian/17_stdlib_eq_ord.rian"))
      refute js =~ "Int64"

      assert node_eval(js, "JSON.stringify(sort([3, 1, 2]))") in [:no_node, "[1,2,3]"]
      assert node_eval(js, "contains([1, 2, 3], 2)") in [:no_node, "true"]
      assert node_eval(js, "contains([1, 2, 3], 9)") in [:no_node, "false"]
    end

    test "struct construction, field access, patterns, and dispatch run in node" do
      js =
        JS.compile("""
        struct Point(x Int, y Int)

        def mk(a Int, b Int) Point := Point(x: a, y: b)
        def getx(p Point) Int := p.x

        def sumxy(p Point) Int
        def sumxy(Point(x: a, y: b)) := a + b

        protocol Kind do
          def kind(self Self) String
        end

        impl Kind for Point do
          def kind(p) := "point"
        end

        impl Kind for Int do
          def kind(n) := "int"
        end
        """)

      # a struct is a `__struct__`-tagged object
      assert js =~ ~s({ __struct__: "Point", x: a, y: b })
      assert js =~ ~s(a0.__struct__ === "Point")

      assert node_eval(js, "getx(mk(7n,8n))") in [:no_node, "7"]
      assert node_eval(js, "sumxy(mk(3n,4n))") in [:no_node, "7"]
      assert node_eval(js, "kind(mk(1n,2n))") in [:no_node, "point"]
      assert node_eval(js, "kind(99n)") in [:no_node, "int"]
    end
  end

  describe "patterns: empty list, cons, tuples (ADR-0049/0050)" do
    test "the empty-list clause and a cons clause lower to length tests + slice" do
      js =
        JS.compile("""
        def sum(xs Vec(Int)) Int
        def sum([]) := 0
        def sum([h | t]) := h + sum(t)
        """)

      # closed [] -> exact length; cons [h | t] -> length >= 1, head index, slice tail
      assert js =~ "if (a0.length === 0)"
      assert js =~ "if (a0.length >= 1)"
      assert js =~ "const h = a0[0];"
      assert js =~ "const t = a0.slice(1);"

      assert node_eval(js, "sum([1n,2n,3n,4n])") in [:no_node, "10"]
      assert node_eval(js, "sum([])") in [:no_node, "0"]
    end

    test "a tuple literal lowers to a JS array; unary minus negates in place" do
      js = JS.compile("def pair(n Int) Tup := {-n, n}")
      assert js =~ "return [-n, n];"

      assert node_eval(js, "JSON.stringify(pair(5n).map(String))") in [
               :no_node,
               ~s|["-5","5"]|
             ]
    end

    test "a map literal lowers to a JS object (identifier keys -> object keys)" do
      js = JS.compile("def m() Map := %{a: 1, b: 2}")
      assert js =~ "return {a: 1n, b: 2n};"

      assert node_eval(js, "JSON.stringify(m(), (k,v)=>typeof v==='bigint'?v.toString():v)") in [
               :no_node,
               ~s|{"a":"1","b":"2"}|
             ]
    end
  end

  describe "atoms and Result lower to JS (ADR-0040/0041)" do
    test "a bare atom lowers to a JS string; equality holds" do
      js = JS.compile("def is_ok(s Symbol) Bool := s == :ok")
      assert js =~ ~s|(s === "ok")|
      assert node_eval(js, ~s|is_ok("ok")|) in [:no_node, "true"]
      assert node_eval(js, ~s|is_ok("no")|) in [:no_node, "false"]
    end

    test "a Result `{:ok,v}`/`{:error,e}` round-trips through a `case` (`[\"ok\", v]`)" do
      js =
        JS.compile("""
        type DivErr := Bad
        def half(n Int53) Result(Int53, DivErr)
        def half(0) := {:error, Bad}
        def half(n) := {:ok, n}

        def unwrap(n Int53) Int53
          case half(n) do
            {:ok, x} -> x
            {:error, _} -> 0 - 1
          end
        end
        """)

      # construction: a Result is a tagged array, parallel to a sum variant
      assert js =~ ~s|["ok", n]|
      assert js =~ ~s|["error", ["Bad"]]|
      # matching: positional length + tag-string test
      assert js =~ ~s|_s[0] === "ok"|

      assert node_eval(js, "unwrap(5)") in [:no_node, "5"]
      assert node_eval(js, "unwrap(0)") in [:no_node, "-1"]
    end
  end

  describe "block bodies, guards, and branches (ADR-0050)" do
    test "a multi-statement body emits lets and expr-statements then returns a value" do
      # `;`-separated statements: a bind (`let`), an expr statement, a returned value
      js = JS.compile("def f(n Int) Int := x := n + 1; g(x); x * 2")
      assert js =~ "let x = (n + 1n);"
      assert js =~ "g(x);"
      assert js =~ "return (x * 2n);"
    end

    test "a block whose last statement is a bind is rejected (ADR-0035)" do
      # A block's value is its final *expression*; a trailing binding has no
      # portable value (BEAM returns the rhs, Rust lowers to `()`), so it is a
      # compile error — Core refuses it before any emitter runs.
      err =
        assert_raise ArgumentError, fn ->
          JS.compile("def f(n Int) Int := y := n - 1; x := n + 1")
        end

      assert err.message =~ "must end in an expression"
      assert err.message =~ "ADR-0035"
    end

    test "a guarded `case` arm wraps the return in an `if`" do
      js =
        JS.compile("""
        def classify(n Int) String
        def classify(n) do
          case n do
            x when x > 0 -> "pos"
            _ -> "other"
          end
        end
        """)

      # arm_return with a guard -> `if (g) { return …; }`; the unguarded arm falls through
      assert js =~ ~s|if ((x > 0n)) { return "pos"; }|
      assert js =~ ~s|return "other";|

      assert node_eval(js, "classify(5n)") in [:no_node, "pos"]
      assert node_eval(js, "classify(-1n)") in [:no_node, "other"]
    end

    test "a multi-statement `if` branch lowers to an IIFE; an empty branch is `undefined`" do
      iife = JS.compile("def f(n Int) Int := if n > 0 do y := n + 1; y else 0 end")
      assert iife =~ "(() => { let y = (n + 1n); return y; })()"
      assert node_eval(iife, "f(4n)") in [:no_node, "5"]

      empty = JS.compile("def g(b Bool) Int := if b do else 2 end")
      assert empty =~ "(b ? undefined : 2n)"
      assert node_eval(empty, "String(g(false))") in [:no_node, "2"]
    end

    test "a Float64 literal passes through as a native JS number (no BigInt suffix)" do
      js = JS.compile("def f(x Float64) Float64 := x + 1.5")
      assert js =~ "(x + 1.5)"
      refute js =~ "1.5n"
      assert node_eval(js, "f(2.5)") in [:no_node, "4"]
    end
  end

  describe "operators map to their JS equivalents (js_op)" do
    test "!=, or, <>, rem lower to their JS operators" do
      assert JS.compile("def f(a Int, b Int) Bool := a != b") =~ "(a !== b)"
      assert JS.compile("def f(a Bool, b Bool) Bool := a or b") =~ "(a || b)"
      assert JS.compile("def f(a String, b String) String := a <> b") =~ "(a + b)"
      assert JS.compile("def f(a Int, b Int) Int := a rem b") =~ "(a % b)"
    end

    test "a bare boolean literal and `not` lower to JS booleans/negation" do
      bool = JS.compile("def t() Bool := true")
      assert bool =~ "return true;"
      assert node_eval(bool, "t()") in [:no_node, "true"]

      neg = JS.compile("def f(b Bool) Bool := not b")
      assert neg =~ "return !b;"
      assert node_eval(neg, "f(false)") in [:no_node, "true"]
    end

    test "an operator with no JS equivalent raises Unsupported (js_op default)" do
      # `in` (membership) has no js_op clause yet — it must raise rather than emit
      # garbage. (Float `/` now *does* lower — see the float-division test above.)
      assert_raise JS.Unsupported, ~r/operator `in`/, fn ->
        JS.compile("def f(a Int, xs Vec(Int)) Bool := a in xs")
      end
    end
  end

  describe "char literals and prelude primitives (ADR-0036 / ADR-0047)" do
    test "a Char literal pattern matches its codepoint as a BigInt" do
      # pat_match(%PChar{}) -> `a0 === <cp>n`; expr_js(%EChar{}) -> `<cp>n`
      js =
        JS.compile("""
        def name(c Char) String
        def name('a') := "ay"
        def name(_) := "other"
        """)

      assert js =~ "if (a0 === 97n)"

      assert node_eval(js, "name(97n)") in [:no_node, "ay"]
      assert node_eval(js, "name(98n)") in [:no_node, "other"]
    end

    test "a Char literal expression lowers to its codepoint BigInt" do
      js = JS.compile("def z() Char := 'z'")
      assert js =~ "return 122n;"
      assert node_eval(js, "String(z())") in [:no_node, "122"]
    end

    test "`Prim.char_code` is identity in JS (a Char is its codepoint number; Int53)" do
      js = JS.compile("def code(c Char) Int53 := Prim.char_code(c)")
      assert js =~ "const c = a0;"
      assert js =~ "return c;"
      assert node_eval(js, "String(code(65))") in [:no_node, "65"]
    end

    test "the Dict prelude lowers `__prim_map_*` to JS object ops" do
      js = JS.compile(File.read!("examples/rian/prelude_dict.rian"))

      # map_new -> {}; map_get -> m[k]; map_put -> spread; map_has -> Object.hasOwn
      assert js =~ "return {};"
      assert js =~ "return (m)[k];"
      assert js =~ "return {...(m), [k]: v};"
      assert js =~ "return Object.hasOwn((m), k);"

      # round-trip: inc(empty(), "x") then get_or for "x" is 1, missing is 0
      assert node_eval(js, "String(get_or(inc(empty(), 'x'), 'x', 0n))") in [:no_node, "1"]
      assert node_eval(js, "String(get_or(empty(), 'x', 0n))") in [:no_node, "0"]
    end

    test "the Str prelude lowers `__prim_str_*` to JS string/codepoint ops" do
      js = JS.compile(File.read!("examples/rian/prelude_str.rian"))

      # str_chars -> codePointAt+BigInt; str_from_chars -> fromCodePoint; concat -> `+`
      assert js =~ "codePointAt(0)"
      assert js =~ "String.fromCodePoint(Number(c))"
      assert js =~ "(a + b)"

      assert node_eval(js, "String(length('héllo'))") in [:no_node, "5"]
      assert node_eval(js, "concat('ab', 'cd')") in [:no_node, "abcd"]
    end
  end

  describe "block typed binds and unsupported clause patterns (ADR-0034 / ADR-0050)" do
    test "a typed bind in a block erases its type (stmt_js typed_bind)" do
      # `x Int := …;` mid-block -> a plain `let`; the type is erased at lowering
      js = JS.compile("def f(n Int) Int := x Int := n + 1; x * 2")
      assert js =~ "let x = (n + 1n);"
      assert js =~ "return (x * 2n);"
      assert node_eval(js, "String(f(4n))") in [:no_node, "10"]
    end

    test "a block whose last statement is a typed bind is rejected (ADR-0035)" do
      # Same rule for a typed trailing binding (`y Int := …`): rejected at Core.
      err =
        assert_raise ArgumentError, fn ->
          JS.compile("def g(n Int) Int := y Int := n + 1")
        end

      assert err.message =~ "must end in an expression"
      assert err.message =~ "ADR-0035"
    end

    test "a tuple clause pattern lowers to positional array matching and runs" do
      js = JS.compile("def f(p Tup) Int\ndef f({a, b}) := a + b")
      # a tuple pattern fixes the length and binds positionally (`a0[0]`/`a0[1]`)
      assert js =~ "a0.length === 2"
      assert js =~ "const a = a0[0];"
      assert js =~ "const b = a0[1];"
      assert node_eval(js, "f([2n, 3n])") in [:no_node, "5"]
    end
  end

  describe "protocol dispatcher arity and empty-impl edge cases (ADR-0061 §3)" do
    test "a zero-arg method and a parenthesised parametric param resolve arity" do
      # split_top_commas("") -> [] (zero params); a `Vec(T)` param exercises the
      # paren-depth counting so the comma inside `Vec(T)` is not a separator.
      js =
        JS.compile("""
        type T := A | B

        protocol P do
          def zero() String
          def two(a Self, b Vec(T)) String
        end

        impl P for T do
          def zero() := "z"
          def two(a, b) := "t"
        end
        """)

      # zero-arg dispatcher takes no params; two-arg dispatcher takes a0, a1
      assert js =~ "export function zero() {"
      assert js =~ "export function two(a0, a1) {"
      assert js =~ "return impl_p_t_two(a0, a1);"
    end

    test "a protocol with no impls emits no dispatcher (empty impl_types)" do
      # the reduce's `[] -> acc` branch: a declared protocol method with zero
      # matching impls contributes nothing to the dispatcher output.
      js =
        JS.compile("""
        protocol Q do
          def n(self Self) String
        end

        def f(x Int) Int := x
        """)

      refute js =~ "function n("
      assert js =~ "function f(a0)"
    end
  end

  describe "integer `div` lowers to truncating division (ECMAScript has no `div`)" do
    # Regression: ECMAScript `/` is IEEE-754 float division, so a Rian `div`
    # (integer division, truncate-toward-zero) must NOT lower to bare `/` in
    # number-mode — `5 div 2` would be `2.5`. Truncate explicitly. In BigInt-mode
    # `/` already truncates toward zero, so it stands (ADR-0049 §JS numerics).
    test "number-mode (Int53): `div` emits `Math.trunc(l / r)` and stays integral" do
      js = JS.compile("def g(a Int53) Int53 := a div 2")
      assert js =~ "Math.trunc(a / 2)"
      # node agrees with the BEAM (`div(5,2)=2`, `div(-5,2)=-2`) — not 2.5
      assert node_eval(js, "g(5)") in [:no_node, "2"]
      assert node_eval(js, "g(-5)") in [:no_node, "-2"]
    end

    test "BigInt-mode (Int): `div` stays `l / r` (BigInt `/` truncates toward zero)" do
      js = JS.compile("def h(a Int) Int := a div 2")
      assert js =~ "(a / 2n)"
      refute js =~ "Math.trunc"
      assert node_eval(js, "h(5n)") in [:no_node, "2"]
      assert node_eval(js, "h(-5n)") in [:no_node, "-2"]
    end
  end

  describe "string-literal escaping (full Elixir/Gleam set)" do
    test "quotes, control chars and `$` emit a valid, runnable JS literal" do
      js = JS.compile(~S|def s() String := "\t\"$\a"|)
      assert js =~ ~S|"\t\"$\u0007"|

      case node_eval(js, ~S|[...s()].map(c => c.charCodeAt(0)).join(",")|) do
        :no_node -> :ok
        out -> assert out == "9,34,36,7"
      end
    end

    test "backslash, newline and CR escape to `\\\\` / `\\n` / `\\r` (js_str_cp)" do
      # the remaining `js_str_cp` arms: `\\` -> `\\\\`, LF -> `\\n`, CR -> `\\r`
      # (the quote/`$`/control arms are exercised by the test above).
      js = JS.compile(~S|def s() String := "a\\b\nc\rd"|)
      assert js =~ ~S|"a\\b\nc\rd"|

      case node_eval(js, ~S|[...s()].map(c => c.charCodeAt(0)).join(",")|) do
        :no_node -> :ok
        # a=97 \=92 b=98 LF=10 c=99 CR=13 d=100
        out -> assert out == "97,92,98,10,99,13,100"
      end
    end
  end

  describe "further protocol-dispatch, prim, and pattern edge cases" do
    test "a `Char` impl dispatches on `typeof === number` in whole-program number-mode (ADR-0064)" do
      # `int_typeof()` -> "number" when the program is number-mode: a `Char` value is
      # its codepoint `number`, so `impl Show for Char` guards on `typeof === "number"`
      # (not "bigint"). An `Int53` function elsewhere pins the whole program to
      # number-mode without colliding with `Char` on the integer discriminator.
      js =
        JS.compile("""
        protocol Show do
          def show(self Self) String
        end

        impl Show for Char do
          def show(c) := "char"
        end

        impl Show for Bool do
          def show(b) := "bool"
        end

        def force(n Int53) Int53 := n + 1
        """)

      assert js =~ ~s|if (typeof a0 === "number") return impl_show_char_show(a0);|
      refute js =~ ~s|typeof a0 === "bigint"|

      assert node_eval(js, "show(65)") in [:no_node, "char"]
      assert node_eval(js, "show(true)") in [:no_node, "bool"]
    end

    test "an explicit 64-bit overflow prim raises in expression position (Int64-only, ADR-0064)" do
      # `Prim.wrapping_add` operates on `Int64`, which has no JS representation. A
      # non-wide signature (`Int`) slips past `reject_wide_int!`, so the refusal must
      # also fire at the call site in `expr_js` — naming the prim and `Int64`.
      err =
        assert_raise JS.Unsupported, fn ->
          JS.compile("def f(a Int, b Int) Int := Prim.wrapping_add(a, b)")
        end

      assert Exception.message(err) =~ "__prim_wrapping_add"
      assert Exception.message(err) =~ "Int64"
    end

    test "a clause pattern the emitter cannot lower raises a clear Unsupported (pat_match default)" do
      # a map pattern `%{a: x}` in a clause head has no `pat_match` clause yet, so it
      # must raise rather than emit garbage (mirrors the expression/operator defaults).
      assert_raise JS.Unsupported, ~r/clause pattern/, fn ->
        JS.compile("def f(m Map) Int\ndef f(%{a: x}) := x")
      end
    end

    test "`:=` shadowing threads a rename through a struct-pattern `case` arm (pat_var_names/PStruct)" do
      # a rebind `k := k + 1` renames the second `k` to `k$1`; descending into the
      # `case` arm, `pat_var_names(%PStruct{})` collects the arm's bound names so the
      # rename map is correctly restricted before the arm body is rewritten.
      js =
        JS.compile("""
        struct Pt(x Int53, y Int53)
        def f(p Pt) Int53
        def f(p) do
          k := 1
          k := k + 1
          case p do
            Pt(x: a, y: b) -> a + b + k
          end
        end
        """)

      assert js =~ "let k$1 = (k + 1);"
      assert js =~ ~s(_s.__struct__ === "Pt")
      assert js =~ "(a + b) + k$1"

      assert node_eval(js, "f({__struct__:'Pt',x:3,y:4})") in [:no_node, "9"]
    end
  end

  describe "`@external` FFI, mixed-int-mode, and interpolation lowering (ADR-0068 / ADR-0064 / ADR-0069)" do
    test "an `@external(:js, …)` function emits its host body, binding params by name" do
      # the `:js` spec is emitted verbatim; each Rian param is bound to its positional
      # argument by name (`const a = a0;`) so the spec can reference it.
      js =
        JS.compile(~S|@external(:js, "a + b")
        def add(a Int53, b Int53) Int53|)

      assert js =~ "function add(a0, a1) {"
      assert js =~ "const a = a0;"
      assert js =~ "const b = a1;"
      assert js =~ "return (a + b);"

      assert node_eval(js, "add(2, 3)") in [:no_node, "5"]
    end

    test "a `pub` `@external` inside a `mod` is exported" do
      js =
        JS.compile(~S|mod M do
          @external(:js, "a * 2")
          pub def dbl(a Int53) Int53
        end|)

      assert js =~ "export function dbl(a0) {"
      assert js =~ "return (a * 2);"
    end

    test "an `@external` function with no `:js` body raises (off `:js`, never a silent stub)" do
      # a `:rs`-only external has no JS host body, so reaching the JS emitter is an
      # off-target compile — a clear error naming the function (ADR-0068 / ADR-0041 §2).
      err =
        assert_raise JS.Unsupported, fn ->
          JS.compile(~S|@external(:rs, "a + b")
          def onlyrs(a Int53, b Int53) Int53|)
        end

      assert Exception.message(err) =~ "onlyrs"
      assert Exception.message(err) =~ "not reachable on :js"
    end

    test "mixing `Int` (BigInt) and a JS-number width in one module is rejected (ADR-0064 §2a)" do
      # BigInt and `number` are incompatible in a JS expression and number-mode would
      # silently truncate `Int`, so a module mixing the two integer representations
      # must raise rather than miscompile (`reject_mixed_int_mode!`).
      err =
        assert_raise JS.Unsupported, fn ->
          JS.compile("def a(n Int53) Int53 := n\ndef b(n Int) Int := n")
        end

      assert Exception.message(err) =~ "cannot mix `Int`"
    end

    test "string interpolation `${n}` lowers an `Int53` hole via `String(n)` (ADR-0069)" do
      # `__prim_int_to_string` lowers to `String(n)` — stringifies a `number` or BigInt
      # with no suffix, so an interpolated integer hole reaches JS.
      js = JS.compile(~S|def shw(n Int53) String := "n=${n}"|)
      assert js =~ "String(n)"

      assert node_eval(js, "shw(7)") in [:no_node, "n=7"]
    end
  end

  describe "`:=` shadowing renames (no JS re-declaration SyntaxError)" do
    test "rebinding a clause parameter renames it (the param is `const`-bound)" do
      # regression: `const n = a0; let n = …` is a re-declaration SyntaxError, so a
      # `:=` rebinding the parameter must take a fresh `n$1` (RHS reads the param).
      js = JS.compile("def f(n Int53) Int53\n  n := n + 1\n  n * 2\nend")
      assert js =~ "const n = a0;"
      assert js =~ "let n$1 = (n + 1);"
      assert js =~ "return (n$1 * 2);"
      assert node_eval(js, "f(5)") in [:no_node, "12"]
    end

    test "rebinding a local binding renames the shadow" do
      js = JS.compile("def g(n Int53) Int53\n  x := n\n  x := x * 10\n  x\nend")
      assert js =~ "let x = n;"
      assert js =~ "let x$1 = (x * 10);"
      assert node_eval(js, "g(2)") in [:no_node, "20"]
    end
  end
end
