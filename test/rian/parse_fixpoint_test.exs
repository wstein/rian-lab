defmodule Rian.ParseFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Lexer, Pratt}

  # Rung 2 of self-hosting (ADR-0027/0031): a Rian-written expression parser
  # (examples/rian/selfhost_parse.rian) compiled to real `.beam`, its output
  # **diffed against the reference `Rian.Pratt.parse`** over a corpus. Because the
  # parser's AST constructors lower to Pratt's exact surface tuples
  # (`Num(s)`->`{:num,s}`, `Id`->`{:id,s}`, `Bin`->`{:bin,op,l,r}`), the streams
  # are compared term-for-term with **no projection** — the parser analog of the
  # lexer fixpoint.

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_parse.rian"), :rian_parse_fixpoint)

    {:ok, mod: mod}
  end

  # Inject the reference `Rian.Lexer` tokens into the parser's `Tok` sum (the same
  # token stream `Rian.Pratt.parse` consumes, since it also uses `expr_tokens/1`).
  defp inject({:num, s}), do: {:t_num, s}
  defp inject({:id, s}), do: {:t_id, s}
  defp inject({:op, o}), do: {:t_op, o}
  defp inject({:lparen}), do: :tlp
  defp inject({:rparen}), do: :trp
  defp inject({:comma}), do: :t_comma

  defp toks(src), do: src |> Lexer.expr_tokens() |> Enum.map(&inject/1)

  # Within the slice: identifiers, integer literals, parens, and the full binary
  # operator precedence table (`* / rem div`, `+ -`, `<>` right-assoc, `< <= > >=`,
  # `== !=`, `and`, `or`) via precedence climbing — Rian.Pratt's exact levels.
  @corpus [
    "1",
    "x",
    "12",
    "1 + 2",
    "1 + 2 * 3",
    "1 * 2 + 3",
    "1 - 2 - 3",
    "1 + 2 + 3 + 4",
    "(1 + 2) * 3",
    "a + b * c - d",
    "a * (b + c) / d",
    "(((7)))",
    "a / b / c",
    "x * y + z * w",
    # widened: comparison / boolean / concat / rem / div
    "a < b",
    "a + b == c",
    "x and y or z",
    "a or b and c",
    "a == b and c != d",
    "a <> b <> c",
    "x rem y div z",
    "n * n + 1 < limit and ok",
    "a <= b and c >= d or e",
    # prefix operators and function calls
    "-x",
    "not a",
    "-a + b",
    "a + -b * c",
    "not a and b",
    "f(x)",
    "f(x, y)",
    "g()",
    "f(x, y) + 1",
    "h(a + b, c * d)",
    "f(g(x), y)",
    "-f(x)",
    "1 + f(2, 3) * g(4)"
  ]

  describe "self-hosting parser fixpoint (ADR-0027/0031) — Rian parser vs Rian.Pratt" do
    test "the compiled Rian parser agrees with Rian.Pratt.parse term-for-term", %{mod: mod} do
      for s <- @corpus do
        assert mod.parse(toks(s)) == Pratt.parse(s),
               "parser diverged from Rian.Pratt on #{inspect(s)}"
      end
    end

    test "precedence is respected: `1 + 2 * 3` nests `*` under `+` (not left-to-right)",
         %{mod: mod} do
      # the teeth: a precedence-blind fold would give {:bin,"+",{:bin,"*",..},..} wrong;
      # the parser must match Pratt's {:bin,"+",1,{:bin,"*",2,3}}.
      assert mod.parse(toks("1 + 2 * 3")) ==
               {:bin, "+", {:num, "1"}, {:bin, "*", {:num, "2"}, {:num, "3"}}}

      # and the corpus is non-vacuous: precedence actually changes the tree
      assert Pratt.parse("1 + 2 * 3") != Pratt.parse("(1 + 2) * 3")
    end

    test "left-associativity: `1 - 2 - 3` groups as `(1 - 2) - 3`", %{mod: mod} do
      assert mod.parse(toks("1 - 2 - 3")) ==
               {:bin, "-", {:bin, "-", {:num, "1"}, {:num, "2"}}, {:num, "3"}}
    end

    test "the full precedence ladder matches Pratt: `*` > `+` > comparison > `and` > `or`",
         %{mod: mod} do
      # `and` binds tighter than `or`: a or (b and c)
      assert mod.parse(toks("a or b and c")) ==
               {:bin, "or", {:id, "a"}, {:bin, "and", {:id, "b"}, {:id, "c"}}}

      # comparison looser than arithmetic: (a + b) == (c * d)
      assert mod.parse(toks("a + b == c * d")) ==
               {:bin, "==", {:bin, "+", {:id, "a"}, {:id, "b"}},
                {:bin, "*", {:id, "c"}, {:id, "d"}}}
    end

    test "`<>` is right-associative (Pratt level 5): `a <> b <> c` ⇒ `a <> (b <> c)`",
         %{mod: mod} do
      assert mod.parse(toks("a <> b <> c")) ==
               {:bin, "<>", {:id, "a"}, {:bin, "<>", {:id, "b"}, {:id, "c"}}}
    end

    test "prefix `-` binds tighter than `+`: `-a + b` ⇒ `(-a) + b`", %{mod: mod} do
      assert mod.parse(toks("-a + b")) ==
               {:bin, "+", {:unary, "-", {:id, "a"}}, {:id, "b"}}
    end

    test "a call's arguments are full expressions: `f(a + b, c)`", %{mod: mod} do
      assert mod.parse(toks("f(a + b, c)")) ==
               {:call, {:id, "f"}, [{:bin, "+", {:id, "a"}, {:id, "b"}}, {:id, "c"}]}
    end
  end

  # Stage 2 of the bootstrap ladder (ADR-0063): the Rian-written front-end's output
  # is consumed by the **real Elixir backend** (`Rian.Lower`) and actually runs —
  # "Rian front-end + reused backend = working program." (Calls to bound functions
  # are exercised by the fixpoint above; here we run arithmetic/unary so emission is
  # unambiguous.)
  describe "Stage 2 — the Rian front-end feeds the real backend and runs" do
    test "a Rian-parsed expression compiles through Rian.Lower and executes", %{mod: mod} do
      run = fn src, binds ->
        ast = mod.parse(toks(src))
        {value, _} = Code.eval_string(Rian.Lower.emit_ast(ast, :elixir), binds)
        value
      end

      assert run.("(2 + 3) * 4", []) == 20
      assert run.("a + b * c", a: 2, b: 3, c: 4) == 14
      assert run.("-a + b", a: 5, b: 1) == -4
      assert run.("a * b - c * d", a: 2, b: 3, c: 4, d: 5) == -14
    end
  end
end
