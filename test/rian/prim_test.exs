defmodule Rian.PrimTest do
  use ExUnit.Case, async: true

  alias Rian.{Beam, Pratt, Prim}

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

    test "selfhost lexer using `Prim.char_code`/`Prim.str_chars` round-trips" do
      {:ok, m} =
        Beam.load(File.read!("examples/rian/selfhost_lexer.rian"), :rian_prim_selfhost_lex)

      assert m.tokenize("1 + 2") == [{:t_num, 1}, :t_plus, {:t_num, 2}]
    end
  end
end
