defmodule Rian.BeamTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Beam

  describe "Erlang abstract-forms backend (ADR-0031) — real :compile.forms bytecode" do
    test "a one-liner compiles to loadable bytecode and runs" do
      {:ok, mod} = Beam.load("def double(n Int64) Int64 := n * 2", :rian_beam_double)
      assert mod.double(21) == 42
      assert {:file, _} = :code.is_loaded(:rian_beam_double)
    end

    test "underscore numeric literals lex AND compile, in expression and pattern position" do
      # Regression: the lexer accepts `1_000` but `String.to_integer/1` on the
      # lexeme would raise — the lexer/parser contradiction the verification pass
      # found. The `_` is now stripped at every value conversion.
      {:ok, mod} =
        Beam.load(
          "def k() Int64 := 1_000 + 2_500\n" <>
            "def cls(1_000) Int64\ndef cls(1_000) := 1\ndef cls(_) := 0",
          :rian_beam_underscore
        )

      assert mod.k() == 3500
      assert mod.cls(1000) == 1
      assert mod.cls(5) == 0
    end

    test "typed bindings (ADR-0034 §1) lower and run — the annotation is erased" do
      {:ok, mod} =
        Beam.load(
          "def f(n Int64) Int64 := x Int64 := n * 2 ; y Int64 := x + 1 ; y",
          :rian_beam_typed_bind
        )

      assert mod.f(10) == 21
    end

    test "the `Char` type (ADR-0036) drives patterns, ordinal guards, and codepoint conversion" do
      {:ok, mod} =
        Beam.load(
          """
          def kind(cs Vec(Char)) Symbol
          def kind(['+' | _]) := :plus
          def kind([d | _]) when d >= '0' and d <= '9' := :digit
          def kind(_) := :other

          def to_digit(c Char) Int64 := __prim_char_code(c) - __prim_char_code('0')
          """,
          :rian_beam_char_lit
        )

      # a `Char` is a codepoint integer on the BEAM, so a single-char string is `[codepoint]`
      assert mod.kind(~c"+") == :plus
      assert mod.kind(~c"7") == :digit
      assert mod.kind(~c"x") == :other
      # explicit Char -> Int64 conversion (no hidden widening)
      assert mod.to_digit(?9) == 9
    end

    test "implicit Char ordinal arithmetic widens to Int64 and runs (ADR-0036)" do
      # `c - '0'` needs no explicit conversion — a `Char` is a codepoint integer
      # on the BEAM; the checker types the result `Int64`
      {:ok, mod} =
        Beam.load("def dval(c Char) Int64 := c - '0'", :rian_beam_char_arith)

      assert mod.dval(?7) == 7
      assert mod.dval(?0) == 0
    end

    test "range construction `Name.of(n)` (ADR-0036) compiles to a checked Result" do
      {:ok, mod} =
        Beam.load(
          """
          range Digit := 0..9
          def of_digit(n Int64) Int64 | RangeError := Digit.of(n)
          """,
          :rian_beam_range_of
        )

      # in range -> {:ok, n}; out of range -> {:error, :range_error}; bounds inclusive
      assert mod.of_digit(7) == {:ok, 7}
      assert mod.of_digit(0) == {:ok, 0}
      assert mod.of_digit(9) == {:ok, 9}
      assert mod.of_digit(12) == {:error, :range_error}
      assert mod.of_digit(-1) == {:error, :range_error}
    end

    test "a `Char`-based range constructs over the codepoint (ADR-0036)" do
      {:ok, mod} =
        Beam.load(
          """
          range Up := 'A'..'Z'
          def of_up(c Char) Char | RangeError := Up.of(c)
          """,
          :rian_beam_range_of_char
        )

      assert mod.of_up(?M) == {:ok, ?M}
      assert mod.of_up(?5) == {:error, :range_error}
    end

    test "multi-clause with a `when` guard" do
      {:ok, mod} =
        Beam.load(
          """
          def max2(a Int64, b Int64) Int64
          def max2(a, b) when a >= b := a
          def max2(_, b) := b
          """,
          :rian_beam_max2
        )

      assert mod.max2(3, 7) == 7
      assert mod.max2(9, 2) == 9
    end

    test "cons-list recursion (the self-hosting shape) compiles to real bytecode" do
      {:ok, mod} =
        Beam.load(
          """
          def sum(xs Vec(Int64)) Int64
          def sum([]) := 0
          def sum([h | t]) := h + sum(t)
          """,
          :rian_beam_sum
        )

      assert mod.sum([1, 2, 3, 4]) == 10
      assert mod.sum([]) == 0
    end

    test "`case` over literals and an `if` expression compile and run" do
      {:ok, mod} =
        Beam.load(
          """
          def sign(n Int64) Int64
            case n do
              0 -> 0
              _ -> if n > 0 do 1 else 0 end
            end
          end
          """,
          :rian_beam_sign
        )

      assert mod.sign(0) == 0
      assert mod.sign(5) == 1
      assert mod.sign(-3) == 0
    end

    test "sum-variant construction + patterns compile to tagged tuples / atoms" do
      {:ok, mod} =
        Beam.load(
          """
          type V := Num(Int64) | Zero
          def eval(v V) Int64
          def eval(Num(n)) := n * 2
          def eval(Zero) := 0
          """,
          :rian_beam_variant
        )

      # Num(n) -> {:num, n}, Zero -> :zero (tag = snake(Ctor))
      assert mod.eval({:num, 21}) == 42
      assert mod.eval(:zero) == 0
    end

    test "the `pi` constant lowers on the canonical path (`:math.pi/0`)" do
      # `examples/area.rian` uses `pi`; it must run on real bytecode, not only
      # through the text emitter (`Rian.Lower`)
      {:ok, mod} = Beam.load(File.read!("examples/area.rian"), :rian_beam_area)
      assert_in_delta mod.area({:circle, 2.0}), :math.pi() * 4.0, 1.0e-9
      assert mod.area({:square, 3.0}) == 9.0
    end

    test "the full self-hosting lexer compiles to real bytecode (variants + recursion, FFI-free)" do
      {:ok, mod} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_lexer)

      assert mod.tokenize("1 + 2") == [{:t_num, 1}, :t_plus, {:t_num, 2}]
      assert {:file, _} = :code.is_loaded(:rian_beam_lexer)
    end

    test "the self-hosting parser (a Pratt slice in Rian) compiles and parses on bytecode" do
      {:ok, parser} =
        Beam.load(File.read!("examples/rian/selfhost_parser.rian"), :rian_beam_parser)

      {:ok, lexer} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_parser_lexer)

      # the full pipeline lexer -> parser, entirely Rian-compiled-to-.beam:
      # precedence (`*` over `+`) and parenthesisation come out right
      ast = parser.parse(lexer.tokenize("1 + 2 * (3 - 4)"))
      assert ast == {:add, {:num, 1}, {:mul, {:num, 2}, {:sub, {:num, 3}, {:num, 4}}}}

      # left-associativity of same-precedence operators
      assert parser.parse(lexer.tokenize("10 - 3 - 2")) ==
               {:sub, {:sub, {:num, 10}, {:num, 3}}, {:num, 2}}

      # the parser is TOTAL: malformed/empty input yields `EErr`, not a crash —
      # so every clause is exhaustive (and the parser clears the dual-target gate)
      assert parser.parse([]) == :e_err
      assert parser.parse(lexer.tokenize(")")) == :e_err
    end

    test "the total parser clears the exhaustiveness gate and lowers to both targets" do
      # (was rejected by `Lower.check!` as partial before `EErr` made it total)
      out = Rian.Decl.compile(File.read!("examples/rian/selfhost_parser.rian"))
      rust = Enum.map_join(out, "\n", fn {_, %{rust: r}} -> r end)
      assert rust =~ "enum Expr"
      # the parse-error fallback is present in the emitted Rust
      assert rust =~ "Expr::EErr"
    end

    test "the self-hosting evaluator folds the Expr sum with a map symbol table" do
      {:ok, ev} = Beam.load(File.read!("examples/rian/selfhost_eval.rian"), :rian_beam_eval)

      {:ok, parser} =
        Beam.load(File.read!("examples/rian/selfhost_parser.rian"), :rian_beam_eval_parser)

      {:ok, lexer} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_eval_lexer)

      # full pipeline, all Rian-compiled-to-.beam: lex -> parse -> evaluate
      assert ev.run(parser.parse(lexer.tokenize("2 + 3 * 4"))) == 14

      # the symbol table: `let x = 10 in let y = 4 in (x + y) * 2` (Expr built
      # directly — the parser layer has no `Var`/`Let` yet); `run` starts in `%{}`
      let_expr =
        {:let, "x", {:num, 10},
         {:let, "y", {:num, 4}, {:mul, {:add, {:var, "x"}, {:var, "y"}}, {:num, 2}}}}

      assert ev.run(let_expr) == 28
      # eval against a prebuilt (FFI-keyed) environment
      assert ev.eval({:mul, {:var, "x"}, {:var, "x"}}, %{"x" => 5}) == 25
    end

    test "the self-hosting type-checker reports structured errors via a struct record" do
      {:ok, chk} = Beam.load(File.read!("examples/rian/selfhost_check.rian"), :rian_beam_check)

      describe = fn e -> chk.describe(chk.check(e)) end

      # well-typed expressions infer a type
      assert describe.({:add, {:num, 1}, {:num, 2}}) == "Int"
      assert describe.({:lt, {:num, 1}, {:num, 2}}) == "Bool"
      assert describe.({:let, "x", {:num, 5}, {:add, {:var, "x"}, {:num, 1}}}) == "Int"

      # ill-typed expressions produce a `Mismatch` struct, read back by field
      # access (`m.op` / `m.expected` / `m.got`) — the struct round-trips
      assert describe.({:add, {:num, 1}, {:bln, true}}) ==
               "type error in add: expected Int, got Bool"

      assert describe.({:if, {:num, 1}, {:num, 0}, {:num, 1}}) ==
               "type error in if-cond: expected Bool, got Int"

      assert describe.({:if, {:lt, {:num, 1}, {:num, 2}}, {:num, 10}, {:bln, true}}) ==
               "type error in if-branch: expected Int, got Bool"
    end

    test "the full self-hosting pipeline: lex -> parse -> codegen -> stack VM, on bytecode" do
      {:ok, cg} = Beam.load(File.read!("examples/rian/selfhost_codegen.rian"), :rian_beam_cg)

      {:ok, parser} =
        Beam.load(File.read!("examples/rian/selfhost_parser.rian"), :rian_beam_cg_parser)

      {:ok, lexer} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_cg_lexer)

      compile_run = fn s -> cg.run(cg.gen(parser.parse(lexer.tokenize(s)))) end

      # five Rian modules, all compiled to .beam: source -> value
      assert compile_run.("2 + 3 * 4") == 14
      assert compile_run.("1 + 2 * (3 - 4)") == -1
      assert compile_run.("(1 + 2) * 3") == 9
      assert compile_run.("8 / 4 / 2") == 1

      # the generated post-order program is what runs
      assert cg.gen({:add, {:num, 1}, {:num, 2}}) == [{:push, 1}, {:push, 2}, :i_add]
    end

    test "the codegen handles variables and `let` via load/store slots" do
      {:ok, cg} = Beam.load(File.read!("examples/rian/selfhost_codegen.rian"), :rian_beam_cg_vars)

      run = fn e -> cg.run(cg.gen(e)) end

      # `let x = 5 in x + 1` -> a slot is stored then loaded
      let1 = {:let, "x", {:num, 5}, {:add, {:var, "x"}, {:num, 1}}}
      assert cg.gen(let1) == [{:push, 5}, {:store, 0}, {:load, 0}, {:push, 1}, :i_add]
      assert run.(let1) == 6

      # nested lets occupy distinct slots
      nested =
        {:let, "x", {:num, 10},
         {:let, "y", {:num, 4}, {:mul, {:add, {:var, "x"}, {:var, "y"}}, {:num, 2}}}}

      assert run.(nested) == 28

      # lexical shadowing: the inner `x` takes its own slot, the outer survives
      shadow =
        {:let, "x", {:num, 1}, {:add, {:let, "x", {:num, 2}, {:var, "x"}}, {:var, "x"}}}

      assert run.(shadow) == 3
    end

    test "the self-hosting optimizer constant-folds + simplifies, shrinking codegen output" do
      {:ok, opt} = Beam.load(File.read!("examples/rian/selfhost_opt.rian"), :rian_beam_opt)
      {:ok, cg} = Beam.load(File.read!("examples/rian/selfhost_codegen.rian"), :rian_beam_opt_cg)

      # constant folding collapses a constant tree to a single literal
      folded = opt.fold({:mul, {:add, {:num, 2}, {:num, 3}}, {:num, 4}})
      assert folded == {:num, 20}
      # and the optimized program is one instruction instead of five
      assert cg.gen(folded) == [{:push, 20}]
      assert length(cg.gen({:mul, {:add, {:num, 2}, {:num, 3}}, {:num, 4}})) == 5

      # algebraic identities over a variable (matched by shape: `Num(0)`/`Num(1)`)
      assert opt.fold({:add, {:mul, {:var, "x"}, {:num, 1}}, {:num, 0}}) == {:var, "x"}
      assert opt.fold({:mul, {:var, "x"}, {:num, 0}}) == {:num, 0}
      assert opt.fold({:add, {:sub, {:num, 10}, {:num, 10}}, {:var, "y"}}) == {:var, "y"}
    end

    test "a multi-module program: each `mod` is its own .beam, cross-module calls resolve" do
      mods = Beam.load_program(File.read!("examples/rian/selfhost_modules.rian"))

      # every `mod` became its own loaded module (named `Elixir.<Mod>`)
      assert CalcLex in mods
      assert Calc in mods

      # the driver `Calc.run` calls across CalcLex / CalcParse / CalcGen
      assert apply(Calc, :run, ["2 + 3 * 4"]) == 14
      assert apply(Calc, :run, ["1 + 2 * (3 - 4)"]) == -1
      assert apply(Calc, :run, ["(2 + 3) * 4"]) == 20

      # a module can be called directly too (e.g. just the lexer)
      assert apply(CalcLex, :lex, ["1+2"]) == [{:t_num, 1}, :t_plus, {:t_num, 2}]
    end

    test "the whole calc compiler in ONE Rian module: source string -> value on bytecode" do
      {:ok, calc} = Beam.load(File.read!("examples/rian/selfhost_calc.rian"), :rian_beam_calc)

      # one module, one .beam: lex -> parse -> fold -> codegen -> VM
      assert calc.run("2 + 3 * 4") == 14
      assert calc.run("1 + 2 * (3 - 4)") == -1
      assert calc.run("(2 + 3) * 4") == 20
      assert calc.run("10 - 3 - 2") == 5
      assert calc.run("8 / 4 / 2") == 1

      # the optimizer is in the pipeline: a constant program folds to one Push
      assert calc.emit("2 + 3 * 4") == [{:push, 14}]
      assert calc.emit("(2 + 3) * 4") == [{:push, 20}]
    end

    test "the calc parses `let`/variables from source (identifiers + keywords)" do
      {:ok, calc} = Beam.load(File.read!("examples/rian/selfhost_calc.rian"), :rian_beam_calc_let)

      # identifiers, the `let`/`in` keywords, and `=` are lexed; `let` parses
      assert calc.run("let x = 5 in x + 1") == 6
      assert calc.run("let x = 10 in let y = 4 in (x + y) * 2") == 28
      assert calc.run("let a = 2 in let b = 3 in a * b + a") == 8
      # lexical shadowing resolves through codegen's slots
      assert calc.run("let x = 1 in (let x = 2 in x) + x") == 3
    end

    test "the calc parses top-level `def` declarations (a program is decls + a result)" do
      {:ok, calc} = Beam.load(File.read!("examples/rian/selfhost_calc.rian"), :rian_beam_calc_def)

      # `def name = expr;` declarations desugar to nested lets, reusing the pipeline
      assert calc.run("def a = 2; def b = 3; a * b + a") == 8
      assert calc.run("def x = 10; def y = x + 5; y * 2") == 30
      # declarations and an inner `let` compose
      assert calc.run("def base = 100; let t = 1 in base + t") == 101
      # a bare expression (no declarations) still works
      assert calc.run("2 + 3 * 4") == 14
    end

    test "higher-order: a `&name/arity` capture applied through a fun-typed param (ADR-0042)" do
      {:ok, mod} =
        Beam.load(
          """
          def apply_twice(f Fn(Int64, Int64), x Int64) Int64 := f(f(x))
          def inc(n Int64) Int64 := n + 1
          def run(x Int64) Int64 := apply_twice(&inc/1, x)
          """,
          :rian_beam_hof_capture
        )

      # `f(...)` where `f` is a parameter compiles to a *variable* application,
      # not a local call — and `&inc/1` is a real Erlang fun reference
      assert mod.run(10) == 12
      # an externally-supplied fun works too (it is just a value)
      assert mod.apply_twice(fn x -> x * x end, 3) == 81
    end

    test "higher-order: a recursive `map` applying a fun-valued parameter runs on bytecode" do
      {:ok, mod} =
        Beam.load(
          """
          def map(f Fn(T, U), xs Vec(T)) Vec(U) forall T, U
          def map(_, []) := []
          def map(f, [h | t]) := [f(h) | map(f, t)]
          def dbl(n Int64) Int64 := n * 2
          def doubled(xs Vec(Int64)) Vec(Int64) := map(&dbl/1, xs)
          """,
          :rian_beam_hof_map
        )

      assert mod.doubled([1, 2, 3]) == [2, 4, 6]
      assert mod.map(fn x -> x + 100 end, [1, 2, 3]) == [101, 102, 103]
    end

    test "higher-order: a returned closure and an anonymous `&(&1 + …)` capture" do
      {:ok, mod} =
        Beam.load(
          """
          def adder(n Int64) Fn(Int64, Int64) := (x) -> x + n
          def twice(n Int64) Int64
            g := &(&1 + &1)
            g(n)
          end
          """,
          :rian_beam_hof_closure
        )

      # `adder` returns an Erlang fun that closes over `n`
      assert mod.adder(5).(37) == 42
      # an anonymous capture bound to a local var, then applied as `g(n)`
      assert mod.twice(21) == 42
    end

    test "strings: a literal is a binary, `<>` concatenates, unicode round-trips (ADR-0041)" do
      {:ok, mod} =
        Beam.load(
          ~s|def greet(name String) String := "hi, " <> name <> "!"\ndef u(n Int64) String := "café→λ"|,
          :rian_beam_str
        )

      assert mod.greet("Rian") == "hi, Rian!"
      assert is_binary(mod.greet("Rian"))
      assert mod.u(0) == "café→λ"
    end

    test "strings: a string-literal pattern dispatches clauses (keyword-matching shape)" do
      {:ok, mod} =
        Beam.load(
          """
          def kind(tok String) Int64
          def kind("def") := 1
          def kind("end") := 2
          def kind(_)     := 0
          """,
          :rian_beam_str_pat
        )

      assert mod.kind("def") == 1
      assert mod.kind("end") == 2
      assert mod.kind("other") == 0
    end

    test "`with` desugars to nested case: happy path, else-handled failures, passthrough (ADR-0039)" do
      {:ok, mod} =
        Beam.load(
          """
          def parse(n Int64) Int64 | E
          def parse(0) := {:error, Bad}
          def parse(n) := {:ok, n}

          def chain(a Int64, b Int64) Int64
            with {:ok, x} <- parse(a),
                 {:ok, y} <- parse(b) do
              {:ok, x + y}
            else
              {:error, e} -> {:error, e}
            end
          end

          def opt(a Int64) Int64
            with {:ok, x} <- parse(a) do
              {:ok, x}
            end
          end
          """,
          :rian_beam_with
        )

      assert mod.chain(2, 3) == {:ok, 5}
      # a failure in either clause position is routed to the `else`
      assert mod.chain(0, 3) == {:error, :bad}
      assert mod.chain(2, 0) == {:error, :bad}
      # no `else`: the happy path, and a non-matching value passes through
      assert mod.opt(7) == {:ok, 7}
      assert mod.opt(0) == {:error, :bad}
    end

    test "struct patterns destructure a struct value by named field (ADR-0043)" do
      {:ok, mod} =
        Beam.load(
          """
          struct Point(x Int64, y Int64)
          pub def mk(a Int64, b Int64) Point := Point(x: a, y: b)
          pub def fst(p val Point) Int64
          pub def fst(Point(x: v)) := v
          pub def swap(p val Point) Point
          pub def swap(Point(x: a, y: b)) := Point(x: b, y: a)
          """,
          :rian_beam_struct_pat
        )

      pt = mod.mk(3, 7)
      assert pt == %{__struct__: :point, x: 3, y: 7}
      # a struct pattern matches the tagged map and binds the named field
      assert mod.fst(pt) == 3
      assert mod.swap(pt) == %{__struct__: :point, x: 7, y: 3}
    end

    test "map patterns dispatch clauses on present keys (ADR-0043)" do
      {:ok, mod} =
        Beam.load(
          """
          pub def kindof(m val Int64) String
          pub def kindof(%{tag: :num}) := "number"
          pub def kindof(%{tag: :str}) := "string"
          pub def kindof(_) := "other"
          """,
          :rian_beam_map_pat
        )

      assert mod.kindof(%{tag: :num, val: 5}) == "number"
      assert mod.kindof(%{tag: :str}) == "string"
      assert mod.kindof(%{nope: 1}) == "other"
    end

    test "a portable `Str` over the `__prim_str_*` primitive layer (ADR-0047 §2)" do
      {:ok, m} = Beam.load(File.read!("examples/rian/prelude_str.rian"), :rian_beam_str_lib)

      assert m.chars("ab") == ~c"ab"
      assert m.from_chars([104, 105]) == "hi"
      assert m.concat("foo", "bar") == "foobar"
      # composite (Rian) — codepoint length, counting multibyte chars once
      assert m.length("héllo") == 5
    end

    test "`Prim.int_to_float` — the explicit Int→Float conversion runs on the BEAM" do
      {:ok, m} =
        Beam.load("def scale(a Int64) Float64 := 2.5 * Prim.int_to_float(a)", :rian_beam_itf)

      assert m.scale(4) == 10.0
      assert m.scale(0) == 0.0
    end

    test "a quoted atom literal `:\"+\"` lowers to the BEAM operator atom" do
      {:ok, m} = Beam.load(~s|def plus() Symbol := :"+"|, :rian_beam_qatom)
      assert m.plus() == :+
    end

    test "`Prim.str_to_atom` interns a runtime string to a BEAM atom" do
      {:ok, m} =
        Beam.load("def a(s String) Symbol := Prim.str_to_atom(s)", :rian_beam_str_to_atom)

      assert m.a("hello") == :hello
      assert m.a("Foo") == :Foo
    end

    test "the self-hosting lexer is FFI-free: `__prim_str_chars`, runs on BEAM" do
      {:ok, m} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_beam_lex_ffifree)

      # behaviour unchanged from the `String.to_charlist` version
      assert m.tokenize("1 + 2") == [{:t_num, 1}, :t_plus, {:t_num, 2}]
    end

    test "a portable `Dict` over the `__prim_map_*` primitive layer (ADR-0047 §2)" do
      {:ok, m} = Beam.load(File.read!("examples/rian/prelude_dict.rian"), :rian_beam_dict)

      d = m.put(m.empty(), "x", 10)
      # the primitives lower to native BEAM maps
      assert m.get(d, "x") == 10
      assert m.has(d, "y") == false
      # composite ops (written in Rian over the primitives) work
      assert m.get_or(d, "y", 99) == 99
      counts = m.empty() |> m.inc("a") |> m.inc("a") |> m.inc("b")
      assert m.get(counts, "a") == 2
      assert m.get(counts, "b") == 1
    end

    test "explicit overflow ops (ADR-0035 §3) project the bignum sum onto Int64" do
      {:ok, m} = Beam.load(File.read!("examples/rian/prelude_int.rian"), :rian_beam_int_ovf)

      max = 9_223_372_036_854_775_807
      min = -9_223_372_036_854_775_808

      # in-range arithmetic is unchanged across every op
      assert m.wrapping_add(2, 3) == 5
      assert m.saturating_add(2, 3) == 5
      assert m.checked_add(2, 3) == {:some, 5}

      # wrapping: two's-complement wrap (MAX + 1 == MIN), deterministic and total
      assert m.wrapping_add(max, 1) == min
      assert m.wrapping_add(min, -1) == max

      # saturating: clamp to the representable extreme
      assert m.saturating_add(max, 100) == max
      assert m.saturating_add(min, -5) == min

      # checked: overflow is surfaced in the type — `Option(Int64)` (`{:some,_}`/`:none`)
      assert m.checked_add(max, 1) == :none
      assert m.checked_add(min, -1) == :none
    end

    test "a portable `List` library written in Rian (cons recursion, no FFI; ADR-0047)" do
      {:ok, m} = Beam.load(File.read!("examples/rian/selfhost_listlib.rian"), :rian_beam_listlib)

      # collection ops written in Rian over cons — no `:lists`/host FFI
      assert m.reverse([1, 2, 3]) == [3, 2, 1]
      assert m.append([1, 2], [3, 4]) == [1, 2, 3, 4]
      assert m.length([1, 2, 3]) == 3
      assert m.sum([1, 2, 3, 4]) == 10
    end

    test "user-defined functions: a Rian interpreter with recursion + mutual recursion" do
      {:ok, m} = Beam.load(File.read!("examples/rian/selfhost_funcs.rian"), :rian_beam_funcs)

      fact =
        {:f, ["n"],
         {:if, {:lt, {:var, "n"}, {:num, 1}}, {:num, 1},
          {:mul, {:var, "n"}, {:app, "fact", [{:sub, {:var, "n"}, {:num, 1}}]}}}}

      even =
        {:f, ["n"],
         {:if, {:lt, {:var, "n"}, {:num, 1}}, {:num, 1},
          {:app, "odd", [{:sub, {:var, "n"}, {:num, 1}}]}}}

      odd =
        {:f, ["n"],
         {:if, {:lt, {:var, "n"}, {:num, 1}}, {:num, 0},
          {:app, "even", [{:sub, {:var, "n"}, {:num, 1}}]}}}

      add = {:f, ["a", "b"], {:add, {:var, "a"}, {:var, "b"}}}
      fs = %{"fact" => fact, "even" => even, "odd" => odd, "add" => add}
      ev = fn e -> m.evalx(e, %{}, fs) end

      # self-recursion
      assert ev.({:app, "fact", [{:num, 5}]}) == 120
      assert ev.({:app, "fact", [{:num, 10}]}) == 3_628_800
      # mutual recursion
      assert ev.({:app, "even", [{:num, 10}]}) == 1
      assert ev.({:app, "odd", [{:num, 7}]}) == 1
      # multi-argument call
      assert ev.({:app, "add", [{:num, 3}, {:num, 4}]}) == 7
    end

    test "a construct outside the core raises a clear Unsupported (never a miscompile)" do
      # the `in` membership operator has no simple Erlang operator form yet (it
      # needs `lists:member`); it raises rather than silently miscompiling
      assert_raise Beam.Unsupported, ~r/operator `in`/, fn ->
        Beam.compile("def g(x Int64, ys Vec(Int64)) Bool := x in ys", :rian_beam_bad)
      end
    end

    test "boolean literals and the `not`/`or`/`!=` operators lower and run" do
      {:ok, mod} =
        Beam.load(
          "def f(a Bool, b Bool) Bool := not a or (b != true)",
          :rian_beam_bool_ops
        )

      assert mod.f(false, false) == true
      assert mod.f(true, true) == false
    end

    test "unary minus, `rem`, and float `/` lower to the right Erlang ops" do
      {:ok, mod} =
        Beam.load(
          """
          def g(a Int64, b Int64) Int64 := -a + (a rem b)
          def d(a Float64, b Float64) Float64 := a / b
          """,
          :rian_beam_arith_ops
        )

      # -7 + (7 rem 5) = -7 + 2 = -5
      assert mod.g(7, 5) == -5
      assert mod.d(7.0, 2.0) == 3.5
    end

    test "a map literal in a body becomes a native BEAM map (atom keys)" do
      {:ok, mod} =
        Beam.load(
          """
          def mk(n Int64) Int64
          def mk(_) := __prim_map_get(%{tag: 5}, :tag)
          """,
          :rian_beam_map_lit
        )

      # the wildcard clause head (`_`) and the `%{tag: 5}` literal both exercise
      # uncovered paths; the map round-trips through `__prim_map_get`
      assert mod.mk(0) == 5
    end

    test "an immediately-applied lambda lowers to a call on a fun expression" do
      {:ok, mod} =
        Beam.load("def f(x Int64) Int64 := ((y) -> y + 1)(x)", :rian_beam_iife)

      assert mod.f(41) == 42
    end

    test "remote `&Mod.fun/arity` captures are Erlang fun references (Elixir module + Erlang atom)" do
      {:ok, mod} =
        Beam.load(
          """
          def elixir_cap() Fn(String, Int64) := &String.length/1
          def erlang_cap() Fn(Int64, Vec(Int64)) := &:lists.duplicate/1
          """,
          :rian_beam_mod_cap
        )

      # PascalCase head -> `Elixir.String`; an Erlang-atom head -> the bare atom
      assert mod.elixir_cap().("hello") == 5
      assert is_function(mod.erlang_cap(), 1)
    end

    test "`&(…)` anonymous captures count placeholders through tuple/list/dot/call bodies" do
      {:ok, mod} =
        Beam.load(
          """
          struct P(x Int64)
          def g(n Int64) Int64 := n + 1
          def as_tuple() Fn(Int64, Int64) := &({&1, &2})
          def as_list() Fn(Int64, Int64)  := &([&1, &2])
          def as_cons() Fn(Int64, Int64)  := &([&1 | &2])
          def via_dot() Fn(P, Int64)       := &(&1.x)
          def via_call() Fn(Int64, Int64)  := &(g(&1))
          """,
          :rian_beam_cap_arity
        )

      assert mod.as_tuple().(1, 2) == {1, 2}
      assert mod.as_list().(1, 2) == [1, 2]
      assert mod.as_cons().(1, [2]) == [1, 2]
      assert mod.via_dot().(%{__struct__: :p, x: 9}) == 9
      assert mod.via_call().(5) == 6
    end
  end

  describe "Stage 0.5 — Dialyzer-checkable `-spec`/`-type` attributes" do
    # pretty-print the `:type`/`:spec` attributes carried in the `.beam`'s
    # abstract-code chunk (retained via `:debug_info`), as their `-…` source lines
    defp attrs(src) do
      {:ok, _mod, bin} = Beam.compile(src, :"rian_spec_#{System.unique_integer([:positive])}")
      {:ok, {_, [{:abstract_code, {_, forms}}]}} = :beam_lib.chunks(bin, [:abstract_code])

      for {:attribute, _, kind, _} = f <- forms, kind in [:type, :spec] do
        f
        |> :erl_pp.attribute()
        |> IO.iodata_to_binary()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
      end
    end

    test "primitives, Vec, and Fn map to native Erlang type forms" do
      a =
        attrs("""
        def f(n Int64, ok Bool, name String, r Float64) Bool := ok
        def g(xs Vec(Int64)) Int64 := 0
        def h(fn1 Fn(Int64, Int64), n Int64) Int64 := fn1(n)
        """)

      assert "-spec f(integer(), boolean(), binary(), float()) -> boolean()." in a
      assert "-spec g([integer()]) -> integer()." in a
      assert "-spec h(fun((integer()) -> integer()), integer()) -> integer()." in a
    end

    test "a sum type gets a named `-type` (union of tags); specs reference it" do
      a =
        attrs("""
        type Shape := Circle(r Float64) | Square(s Float64) | Unit
        def area(sh Shape) Float64
        def area(Circle(r)) := r
        def area(Square(s)) := s
        def area(Unit) := 0.0
        """)

      assert "-type shape() :: {circle, float()} | {square, float()} | unit." in a
      assert "-spec area(shape()) -> float()." in a
    end

    test "a struct gets a named `-type` (the `__struct__` map | the positional tuple)" do
      a =
        attrs("""
        struct Point(x Int64, y Int64)
        def origin() Point := Point(x: 0, y: 0)
        """)

      assert Enum.any?(
               a,
               &(&1 =~ "-type point() ::" and &1 =~ "'__struct__' := point" and
                   &1 =~ "{point, integer(), integer()}")
             )

      assert "-spec origin() -> point()." in a
    end

    test "an un-pinnable type (a `forall` variable) becomes `any()` — every fn is specced" do
      a = attrs("def id(x T) T forall T := x")
      assert "-spec id(any()) -> any()." in a
    end
  end

  describe "`:=` shadowing in a block (ADR-0034 — Erlang is single-assignment)" do
    # Regression: a rebind `x := x * 10` must lower to a FRESH Erlang var, not a
    # second `X = …` match against the already-bound `X` (a runtime MatchError).
    test "the tour's shadow_demo pattern runs" do
      {:ok, m} =
        Beam.load(
          "def shadow_demo(n Int53) Int53\n  x := n + 1\n  x := x * 10\n  x\nend",
          :beam_shadow_demo
        )

      assert m.shadow_demo(1) == 20
    end

    test "a self-referential rebind reads the prior binding" do
      {:ok, m} =
        Beam.load(
          "def g(n Int53) Int53\n  a := n + n\n  a := a + 1\n  a\nend",
          :beam_shadow_selfref
        )

      assert m.g(8) == 17
    end

    test "a parameter can be shadowed by a later bind of the same name" do
      {:ok, m} = Beam.load("def f(n Int53) Int53\n  n := n + 100\n  n\nend", :beam_shadow_param)
      assert m.f(5) == 105
    end
  end
end
