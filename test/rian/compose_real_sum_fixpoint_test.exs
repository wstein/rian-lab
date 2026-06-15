defmodule Rian.ComposeRealSumFixpointTest do
  # async: false — loads verified ports (by their natural atoms) + the driver, and
  # the driver loads compiled modules at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # COMPOSITION fixpoint rung 11 (ADR-0063 Step 3): widens the composed build's
  # SURFACE to sum types + constructor-pattern dispatch, using selfhost_decl's
  # already-locked `type`/ctor capability (no verified-port changes). The driver
  # glue grows only by: erasing `type` declarations and inflating FCtorN/FCtor
  # (nullary ctor -> snake atom; applied ctor -> tagged tuple), via a `to_snake`
  # matching Rian.PatternLower.to_snake.
  #
  #   SelfhostLexerV2.tokenize → SelfhostDecl.parse_program → normalize (drops DType)
  #     → surface→Core lowering → SelfhostBeam.compile_forms → inflate → load
  #
  # The test loads all three verified ports under their :"Elixir.Selfhost*" atoms,
  # then calls only `build/2` and runs the result, identical to `Rian.Beam` — now
  # over sum-type programs (Color/Shape/Box) with constructor dispatch.

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("examples/rian/selfhost_lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, drv} =
      Beam.load(
        File.read!("examples/rian/selfhost_compose_real_sum.rian"),
        :rian_compose_real_sum
      )

    {:ok, drv: drv}
  end

  defp ref_module(src) do
    {:ok, m} = Beam.load(src, :"cmp_rs_ref_#{System.unique_integer([:positive])}")
    m
  end

  # {pipeline source (untyped), reference source (typed sigs), [{fn, args}] to run}.
  @corpus [
    # nullary variants → snake atoms; constructor-pattern dispatch
    {
      "type Color := Red | Green | Blue\ndef code(Red) := 0\ndef code(Green) := 1\ndef code(Blue) := 2",
      "type Color := Red | Green | Blue\ndef code(c Color) Int53\ndef code(Red) := 0\ndef code(Green) := 1\ndef code(Blue) := 2",
      [{:code, [:red]}, {:code, [:green]}, {:code, [:blue]}]
    },
    # applied variants → tagged tuples; payload destructuring in patterns
    {
      "type Shape := Circle(Int53) | Rect(Int53, Int53)\ndef area(Circle(r)) := r * r\ndef area(Rect(w, h)) := w * h",
      "type Shape := Circle(Int53) | Rect(Int53, Int53)\ndef area(s Shape) Int53\ndef area(Circle(r)) := r * r\ndef area(Rect(w, h)) := w * h",
      [{:area, [{:circle, 5}]}, {:area, [{:rect, 3, 4}]}, {:area, [{:circle, 10}]}]
    },
    # constructor VALUE in a body builds a tagged tuple
    {
      "type Box := B(Int53)\ndef wrap(n) := B(n)\ndef unwrap(B(n)) := n",
      "type Box := B(Int53)\ndef wrap(n Int53) Box := B(n)\ndef unwrap(b Box) Int53\ndef unwrap(B(n)) := n",
      [{:wrap, [7]}, {:wrap, [42]}, {:unwrap, [{:b, 9}]}]
    },
    # tuple EXPRESSIONS + atom literals (`{:ok, n}`) and tuple PATTERNS (`{:ok, v}`)
    # — the driver dispatches on `compile.forms`' `{:ok, m, bin}` and builds `{:var,
    # 0, n}` abstract-form tuples this way (CTuple/CAtom + PTuple/PAtom lowering).
    {
      "def mk(n Int53) Tuple := {:ok, n}\ndef unwrap(t Tuple) Int53\ndef unwrap({:ok, v}) := v",
      "def mk(n Int53) Tuple := {:ok, n}\ndef unwrap(t Tuple) Int53\ndef unwrap({:ok, v}) := v",
      [{:mk, [7]}, {:mk, [0]}, {:unwrap, [{:ok, 9}]}]
    },
    # `Prim.int_to_string` — integer → string (erlang:integer_to_binary), used by
    # selfhost_core.rian. Locks the prim lowering end to end.
    {
      "def show(n Int53) String := Prim.int_to_string(n)",
      "def show(n Int53) String := Prim.int_to_string(n)",
      [{:show, [0]}, {:show, [42]}, {:show, [-7]}]
    },
    # struct FIELD ACCESS `c.name` as a value — a Core field-read (`maps:get`); the
    # form selfhost_exhaust.rian uses (`cd.name`/`cd.ar`/`td.ctors`). A struct is a
    # tagged map, so a plain map carrying the field keys exercises the read path.
    {
      "struct CD(name String, ar Int53)\ndef gname(c CD) String := c.name\ndef gar(c CD) Int53 := c.ar",
      "struct CD(name String, ar Int53)\ndef gname(c CD) String := c.name\ndef gar(c CD) Int53 := c.ar",
      [{:gname, [%{name: "x", ar: 7}]}, {:gar, [%{name: "y", ar: 42}]}]
    },
    # `if` — now in selfhost_decl's surface (ADR-0063 widening); compiles end to end
    {
      "def max(a, b) := if a > b do a else b end\ndef min(a, b) := if a < b do a else b end",
      "def max(a Int53, b Int53) Int53 := if a > b do a else b end\ndef min(a Int53, b Int53) Int53 := if a < b do a else b end",
      [{:max, [3, 7]}, {:max, [9, 2]}, {:min, [3, 7]}]
    },
    # `if`-guarded recursion + sum-type constructor comparison in one program
    {
      "type Color := Red | Green\ndef code(c) := if c == Red do 0 else 1 end",
      "type Color := Red | Green\ndef code(c Color) Int53 := if c == Red do 0 else 1 end",
      [{:code, [:red]}, {:code, [:green]}]
    },
    # String literals — return body + string-literal clause head (toward the lexer)
    {
      "def tag() := \"ok\"\ndef sel(\"a\") := 1\ndef sel(_) := 0",
      "def tag() String := \"ok\"\ndef sel(s String) Int53\ndef sel(\"a\") := 1\ndef sel(_) := 0",
      [{:tag, []}, {:sel, ["a"]}, {:sel, ["z"]}]
    },
    # Char literals — in an expression (`c == '0'`) and as clause heads
    {
      "def isz(c) := c == '0'\ndef kind('+') := 1\ndef kind('-') := 2\ndef kind(_) := 0",
      "def isz(c Char) Bool := c == '0'\ndef kind(c Char) Int53\ndef kind('+') := 1\ndef kind('-') := 2\ndef kind(_) := 0",
      [{:isz, [?0]}, {:isz, [?1]}, {:kind, [?+]}, {:kind, [?-]}, {:kind, [?x]}]
    },
    # Prim.* — the string/char intrinsics the lexer leans on, normalized to
    # __prim_* by the driver and lowered to native Erlang forms by selfhost_beam
    {
      "def echo(s) := Prim.str_from_chars(Prim.str_chars(s))",
      "def echo(s String) String := Prim.str_from_chars(Prim.str_chars(s))",
      [{:echo, ["hi"]}, {:echo, ["ok"]}]
    },
    {
      "def d(c) := Prim.char_code(c) - Prim.char_code('0')",
      "def d(c Char) Int64 := Prim.char_code(c) - Prim.char_code('0')",
      [{:d, [?7]}, {:d, [?0]}, {:d, [?9]}]
    },
    # `<>` — binary concatenation (the lexer builds token strings this way)
    {
      "def wrap(s) := \"[\" <> s <> \"]\"\ndef cat(a, b) := a <> b",
      "def wrap(s String) String := \"[\" <> s <> \"]\"\ndef cat(a String, b String) String := a <> b",
      [{:wrap, ["hi"]}, {:cat, ["foo", "bar"]}]
    },
    # `case` — literal/guarded/wildcard arms (the last surface gate before the lexer)
    {
      "def classify(n) := case n do\n  0 -> 100\n  m when m > 0 -> m * 2\n  _ -> 0\nend",
      "def classify(n Int53) Int53 := case n do\n  0 -> 100\n  m when m > 0 -> m * 2\n  _ -> 0\nend",
      [{:classify, [0]}, {:classify, [5]}, {:classify, [-3]}]
    },
    # `case` over a sum value — constructor arms dispatch on the tagged tuple/atom
    {
      "type Sign := Pos | Neg | Zero\ndef code(s) := case s do\n  Pos -> 1\n  Neg -> -1\n  Zero -> 0\nend",
      "type Sign := Pos | Neg | Zero\ndef code(s Sign) Int53 := case s do\n  Pos -> 1\n  Neg -> -1\n  Zero -> 0\nend",
      [{:code, [:pos]}, {:code, [:neg]}, {:code, [:zero]}]
    },
    # the driver `normalize`-completeness fixes (toward building the lexer):
    # a `when`-guarded clause (was silently dropped — the guard discarded)
    {
      "def clamp(n) when n < 0 := 0\ndef clamp(n) := n",
      "def clamp(n Int53) Int53\ndef clamp(n) when n < 0 := 0\ndef clamp(n) := n",
      [{:clamp, [-5]}, {:clamp, [9]}, {:clamp, [0]}]
    },
    # a single TYPED clause (`DFunc`) — was skipped, leaving the function undefined
    {
      "def tag() Int53 := 7\ndef inc(n Int53) Int53 := n + 1",
      "def tag() Int53 := 7\ndef inc(n Int53) Int53 := n + 1",
      [{:tag, []}, {:inc, [41]}]
    },
    # list CONSTRUCTION in a body (`[x | acc]`, `[a, b]`) — lower_surface cons_e
    {
      "def one(x) := [x]\ndef pre(x, xs) := [x | xs]",
      "def one(x Int53) Vec(Int53) := [x]\ndef pre(x Int53, xs Vec(Int53)) Vec(Int53) := [x | xs]",
      [{:one, [9]}, {:pre, [1, [2, 3]]}]
    },
    # a `mod` wrapper — its inner defs flatten into the build's module
    {
      "mod M do\n  def double(n) := n * 2\n  pub def quad(n) := double(double(n))\nend",
      "mod M do\n  pub def double(n Int53) Int53 := n * 2\n  pub def quad(n Int53) Int53 := double(double(n))\nend",
      [{:double, [21]}, {:quad, [5]}]
    },
    # an untyped clause with a multi-statement BLOCK body (bind + expr), and a
    # `case` arm body on the next line — selfhost_decl's own idioms, end to end
    {
      "def step(n)\n  d := n * 2\n  d + 1\nend\ndef sgn(n)\n  case n do\n    0 ->\n      0\n    m -> m\n  end\nend",
      "def step(n Int53) Int53\n  d := n * 2\n  d + 1\nend\ndef sgn(n Int53) Int53\n  case n do\n    0 ->\n      0\n    m -> m\n  end\nend",
      [{:step, [10]}, {:sgn, [0]}, {:sgn, [7]}]
    }
  ]

  describe "sum-type fixpoint — constructor dispatch runs identically to Elixir" do
    test "build/2 compiles sum types + ctor patterns equal to Rian.Beam's", %{drv: drv} do
      for {rian_src, ref_src, calls} <- @corpus do
        modname = :"cmp_rs_#{System.unique_integer([:positive])}"
        loaded = drv.build(rian_src, modname)
        assert loaded == modname

        ref = ref_module(ref_src)

        for {fname, args} <- calls do
          assert apply(loaded, fname, args) == apply(ref, fname, args),
                 "driver(sum) `#{fname}` diverged from Elixir toolchain on #{inspect(args)}"
        end
      end
    end
  end

  describe "teeth — `type` is erased; ctors become atoms / tagged tuples" do
    test "nullary ctor patterns lower to snake atoms; type decl is dropped", %{drv: drv} do
      # the `type` line produces no form; the function pattern is the variant atom.
      [_m, {:attribute, 0, :export, exports} | funcs] =
        drv.compile_module(
          "type Color := Red | Green\ndef code(Red) := 0\ndef code(Green) := 1",
          :rs_color
        )

      assert exports == [{:code, 1}]
      assert [{:function, 0, :code, 1, [c0, c1]}] = funcs
      assert {:clause, 0, [{:atom, 0, :red}], [], [{:integer, 0, 0}]} = c0
      assert {:clause, 0, [{:atom, 0, :green}], [], [{:integer, 0, 1}]} = c1
    end

    test "to_snake matches Rian's convention (consecutive caps collapse)", %{drv: drv} do
      # SNum -> :s_num, SP -> :sp — multi-cap variant tags lower like Rian.PatternLower.
      [_m, _e, {:function, 0, :tag, 1, [a, b]}] =
        drv.compile_module(
          "type T := SNum(Int53) | SP\ndef tag(SNum(_)) := 1\ndef tag(SP) := 2",
          :rs_snake
        )

      assert {:clause, 0, [{:tuple, 0, [{:atom, 0, :s_num} | _]}], [], _} = a
      assert {:clause, 0, [{:atom, 0, :sp}], [], _} = b
    end

    test "an applied constructor value builds a tagged tuple", %{drv: drv} do
      m = drv.build("type Box := B(Int53)\ndef wrap(n) := B(n)", :rs_wrap)
      assert apply(m, :wrap, [99]) == {:b, 99}
    end
  end
end
