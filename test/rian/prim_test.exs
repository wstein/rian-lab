defmodule Rian.PrimTest do
  use ExUnit.Case, async: true

  alias Rian.{Beam, Pratt, Prim}

  # `Reach.entry/2` resolves a bare name against the `"name/arity"`-keyed report
  # (and raises clearly on a miss) — these sources have no overloads.
  defp reach_entry(rep, name), do: Rian.Reach.entry(rep, name)

  describe "Prim.X(args) normalization (Rian.Prim)" do
    test "`Prim.str_chars(s)` rewrites to `__prim_str_chars(s)` at parse time" do
      ast = Pratt.parse("Prim.str_chars(s)")
      assert ast == {:call, {:id, "__prim_str_chars"}, [{:id, "s"}]}
    end

    test "`Prim.char_code(c)` rewrites at parse time" do
      ast = Pratt.parse("Prim.char_code('0')")
      assert ast == {:call, {:id, "__prim_char_code"}, [{:char, ?0}]}
    end

    test "rewrites recursively inside larger expressions" do
      # `acc * 10 + Prim.char_code(c) - Prim.char_code('0')`
      ast = Pratt.parse("acc * 10 + Prim.char_code(c) - Prim.char_code('0')")
      # both Prim.char_code calls normalize regardless of nesting depth
      s = inspect(ast)
      refute s =~ "{:dot, {:id, \"Prim\"}"
      assert s =~ "__prim_char_code"
    end

    test "rewrites inside a body block (the `:= … ;` form)" do
      block = Pratt.parse_body("Prim.str_chars(\"ab\")")

      assert block ==
               {:block,
                [
                  {:expr, {:call, {:id, "__prim_str_chars"}, [{:str, "ab"}]}}
                ]}
    end

    test "leaves a genuine user-module `Foo.bar(x)` alone" do
      ast = Pratt.parse("Foo.bar(x)")
      assert ast == {:call, {:dot, {:id, "Foo"}, "bar"}, [{:id, "x"}]}
    end

    test "is idempotent on the legacy `__prim_*` form" do
      ast = Pratt.parse("__prim_str_chars(s)")
      assert ast == {:call, {:id, "__prim_str_chars"}, [{:id, "s"}]}
      # second pass is identity
      assert Prim.normalize(ast) == ast
    end

    test "an unknown `Prim.x` is a hard error, not a bogus `__prim_x`" do
      # a typo (or a collision with a user module named `Prim`) must fail loudly
      err = assert_raise ArgumentError, fn -> Pratt.parse("Prim.str_charz(s)") end
      assert Exception.message(err) =~ "unknown primitive `Prim.str_charz`"
      assert Exception.message(err) =~ "reserved"
    end

    test "every registered intrinsic rewrites (the registry has no dead names)" do
      for name <- Prim.names() do
        assert Pratt.parse("Prim.#{name}(x)") == {:call, {:id, "__prim_#{name}"}, [{:id, "x"}]}
      end
    end

    test "a user `mod Prim` is rejected (the namespace is reserved)" do
      err =
        assert_raise Rian.Decl.Error, fn ->
          Rian.Decl.parse("mod Prim do\n  pub def f(x Int64) Int64 := x\nend")
        end

      assert Exception.message(err) =~ "reserved"
    end
  end

  describe "end-to-end on BEAM via the updated prelude files" do
    test "`Str` prelude uses `Prim.str_*` and still runs (ADR-0047 §2)" do
      {:ok, m} = Beam.load(File.read!("examples/rian/prelude_str.rian"), :rian_prim_str)

      assert m.chars("ab") == ~c"ab"
      assert m.from_chars([104, 105]) == "hi"
      assert m.concat("foo", "bar") == "foobar"
      assert m.length("héllo") == 5
    end

    test "`Dict` prelude uses `Prim.map_*` and still runs" do
      {:ok, m} = Beam.load(File.read!("examples/rian/prelude_dict.rian"), :rian_prim_dict)

      d = m.put(m.empty(), "x", 10)
      assert m.get(d, "x") == 10
      assert m.has(d, "y") == false
    end

    test "`List` prelude reducers run (with empty-list identities) and reach all four targets" do
      src = File.read!("examples/rian/prelude_list.rian")
      {:ok, m} = Beam.load(src, :rian_prim_list)

      # behaviour — including the empty-list identity, so each reducer is TOTAL
      # (no `Option`, no crash): 0/1/false/true/0.
      assert m.sum([1, 2, 3]) == 6
      assert m.sum([]) == 0
      assert m.product([2, 3, 4]) == 24
      assert m.product([]) == 1
      assert m.any([false, true]) == true
      assert m.any([]) == false
      assert m.all([true, true]) == true
      assert m.all([true, false]) == false
      assert m.all([]) == true
      assert m.length(["a", "b", "c"]) == 3
      assert m.length([]) == 0

      # the POINT of a portable prelude: pure-cons reducers reach every target.
      rep = Rian.Reach.analyze(Rian.Decl.parse(src))

      for fname <- ~w(sum product any all length) do
        assert Enum.sort(MapSet.to_list(reach_entry(rep, fname).reach)) == [:ex, :js, :jvm, :rs],
               "#{fname} must reach all four targets (it is pure cons)"
      end
    end

    test "`Foldable` — one ELEMENT-GENERIC reducer over two element types (ADR-0074)" do
      src = File.read!("examples/rian/foldable.rian")
      {:ok, m} = Beam.load(src, :rian_prim_foldable)

      # the SAME `fcount` reduces a Bag of Int53 AND a Words of String — the
      # associated type (`type Elem := Int53` / `:= String`) makes it element-generic.
      assert m.fcount({:bag, [1, 2, 3]}) == 3
      assert m.fcount({:words, ["a", "b"]}) == 2

      # reach is honest: a SUM-dispatching protocol consumer is `[:ex, :js]` (the
      # constructor-tag atom in the dispatcher pins off `:rs`/`:jvm`) — exactly the
      # reach of the shipped `Show`-over-`Expr`; associated types erase, no change.
      rep = Rian.Reach.analyze(Rian.Decl.parse(src))
      assert Enum.sort(MapSet.to_list(reach_entry(rep, "fcount").reach)) == [:ex, :js]
      # the underlying concrete fold IS all-target — only the dispatcher gates it.
      assert Enum.sort(MapSet.to_list(reach_entry(rep, "len_l").reach)) == [:ex, :js, :jvm, :rs]
    end

    test "selfhost lexer using `Prim.char_code`/`Prim.str_chars` round-trips" do
      {:ok, m} =
        Beam.load(File.read!("test/fixtures/rian/lexer.rian"), :rian_prim_selfhost_lex)

      assert m.tokenize("1 + 2") == [{:t_num, 1}, :t_plus, {:t_num, 2}]
    end
  end

  describe "the canonical 64-bit-overflow op list (single-sourced for Reach + JS)" do
    test "overflow_ops/0 are the `__prim_`-prefixed wrap/saturate/check ops" do
      assert Prim.overflow_ops() ==
               ~w(__prim_wrapping_add __prim_saturating_add __prim_checked_add)
    end

    test "every overflow op is a real intrinsic (a `__prim_` form of a `names/0` entry)" do
      for op <- Prim.overflow_ops() do
        assert "__prim_" <> bare = op
        assert bare in Prim.names()
      end
    end
  end
end
