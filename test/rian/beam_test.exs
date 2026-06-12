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

    test "the full self-hosting lexer compiles to real bytecode (variants + FFI + recursion)" do
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

    test "a construct outside the core raises a clear Unsupported (never a miscompile)" do
      # the `in` membership operator has no simple Erlang operator form yet (it
      # needs `lists:member`); it raises rather than silently miscompiling
      assert_raise Beam.Unsupported, ~r/operator `in`/, fn ->
        Beam.compile("def g(x Int64, ys Vec(Int64)) Bool := x in ys", :rian_beam_bad)
      end
    end
  end
end
