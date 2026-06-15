defmodule Rian.ParseFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Lexer, Pratt}

  # Self-hosting fixpoint for the **expression/pattern parser** (ADR-0063): a
  # Rian-written port of `Rian.Pratt` (compiler/parse.rian), compiled
  # to real `.beam`, its output **diffed against the reference `Rian.Pratt.parse`**
  # over a corpus with NO projection — the port builds Pratt's exact surface tuples
  # (`{:num,s}`, `{:bin,op,l,r}`, `:wild`, `{:lit,v}`, `{:if,c,t,e}`, …) as raw
  # Rian tuples/atoms threaded through a parametric `R(node, rest)`.
  #
  # Coverage: the FULL grammar — prefix `-`/`not`/`&`-capture; primaries if/case/
  # with/list/map/tuple/paren-or-lambda/atom/str/char/num/id; postfix dot/call;
  # labelled args; precedence climbing; AND the full pattern grammar (wild/var/lit/
  # char/atom/tuple/list+tail/map/ctor/struct), plus blocks. Surface SUGAR resolved
  # by later passes — string interpolation (ADR-0069) and the `<-` propagation bind
  # (ADR-0066) — is out of scope.

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("compiler/parse.rian"), :rian_parse_fixpoint)

    {:ok, mod: mod}
  end

  # Inject the reference `Rian.Lexer` tokens into the parser's `Tok` sum (the same
  # token stream `Rian.Pratt.parse` consumes, since it also uses `expr_tokens/1`).
  defp inject({:num, s}), do: {:t_num, s}
  defp inject({:str, s}), do: {:t_str, s}
  defp inject({:char, c}), do: {:t_char, c}
  defp inject({:id, s}), do: {:t_id, s}
  defp inject({:kw, k}), do: {:t_kw, k}
  defp inject({:op, o}), do: {:t_op, o}
  defp inject({:lparen}), do: :tlp
  defp inject({:rparen}), do: :trp
  defp inject({:lbracket}), do: :tl_bracket
  defp inject({:rbracket}), do: :tr_bracket
  defp inject({:lbrace}), do: :tl_brace
  defp inject({:rbrace}), do: :tr_brace
  defp inject({:mapopen}), do: :t_map_open
  defp inject({:comma}), do: :t_comma
  defp inject({:semi}), do: :t_semi

  defp toks(src), do: src |> Lexer.expr_tokens() |> Enum.map(&inject/1)

  @corpus [
    # literals / identifiers / atoms
    "1",
    "x",
    "12",
    "'A'",
    ":ok",
    ~S|"hi"|,
    "true",
    # operators / precedence / associativity
    "1 + 2 * 3",
    "1 * 2 + 3",
    "1 - 2 - 3",
    "(1 + 2) * 3",
    "a + b * c - d",
    "a * (b + c) / d",
    "(((7)))",
    "a < b",
    "x and y or z",
    "a == b and c != d",
    "a <> b <> c",
    "x rem y div z",
    "a <= b and c >= d or e",
    # prefix
    "-x",
    "not a",
    "-a + b",
    "a + -b * c",
    # calls / labelled args / dot
    "f(x)",
    "f(x, y)",
    "g()",
    "h(a + b, c * d)",
    "f(g(x), y)",
    "Point(x: 1, y: 2)",
    "obj.field",
    "obj.f(1, 2)",
    "a.b.c(1).d",
    # captures
    "&(_1 + _2)",
    "&foo/2",
    "&:erlang.length/1",
    # collections
    "[1, 2, 3]",
    "[1, 2 | rest]",
    "[]",
    "{1, 2}",
    "{:ok, x}",
    "{}",
    "%{a: 1, b: x}",
    "%{}",
    # lambdas
    "(p) -> p + 1",
    "(a, b) -> a * b",
    "() -> 0",
    # if / case / with (blocks + patterns)
    "if c do 1 else 2 end",
    "if c do 1 end",
    "case n do\n  0 -> \"z\"\n  m -> \"nz\"\nend",
    "case v do\n  Some(a) -> a\n  None -> 0\n  [h | t] -> h\n  {a, b} -> a\n  %{k: w} -> w\n  'A' -> 1\n  :ok -> 2\n  _ -> 3\nend",
    "case p do\n  Point(x: a, y: b) -> a\n  n when n > 0 -> n\nend",
    "with y <- f(x) do y else z -> 0 end",
    "with a <- p(), b <- q(a) do a + b end"
  ]

  describe "self-hosting parser fixpoint (ADR-0063) — Rian parser vs Rian.Pratt (full)" do
    test "the compiled Rian parser agrees with Rian.Pratt.parse term-for-term", %{mod: mod} do
      for s <- @corpus do
        assert mod.parse(toks(s)) == Pratt.parse(s),
               "parser diverged from Rian.Pratt on #{inspect(s)}"
      end
    end
  end

  describe "teeth — structure (precedence, nesting, node kind) is preserved" do
    test "precedence: `1 + 2 * 3` nests `*` under `+`", %{mod: mod} do
      assert mod.parse(toks("1 + 2 * 3")) ==
               {:bin, "+", {:num, "1"}, {:bin, "*", {:num, "2"}, {:num, "3"}}}
    end

    test "left-assoc `-` and right-assoc `<>`", %{mod: mod} do
      assert mod.parse(toks("1 - 2 - 3")) ==
               {:bin, "-", {:bin, "-", {:num, "1"}, {:num, "2"}}, {:num, "3"}}

      assert mod.parse(toks("a <> b <> c")) ==
               {:bin, "<>", {:id, "a"}, {:bin, "<>", {:id, "b"}, {:id, "c"}}}
    end

    test "a `case` arm pattern + guard + body matches Pratt exactly", %{mod: mod} do
      assert mod.parse(toks("case x do\n  Some(v) when v > 0 -> v\n  _ -> 0\nend")) ==
               {:case, {:id, "x"},
                [
                  {{:ctor, "Some", [{:var, "v"}]}, {:bin, ">", {:id, "v"}, {:num, "0"}},
                   {:id, "v"}},
                  {:wild, nil, {:num, "0"}}
                ]}
    end

    test "different node kinds give different trees", %{mod: mod} do
      refute mod.parse(toks("{1, 2}")) == mod.parse(toks("[1, 2]"))
      refute mod.parse(toks("f(x)")) == mod.parse(toks("f(y)"))
    end
  end

  # Stage 2 of the bootstrap ladder (ADR-0063): the Rian-written front-end's output
  # is consumed by the **real Elixir backend** (`Rian.Lower`) and actually runs.
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
