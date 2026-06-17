defmodule Rian.FormatTest do
  use ExUnit.Case, async: true

  alias Rian.Decl
  alias Rian.Format
  alias Rian.Lexer

  @width 98

  # ── semantic-preservation oracle ──────────────────────────────────────────
  # The "significant" token stream: what the parser actually cares about. We drop
  # the changes the formatter is *allowed* to make — comments, newlines **inside
  # brackets** (where Rian is newline-tolerant), blank-line runs, and a trailing
  # comma before a closer (parse-insignificant) — and assert the rest is identical.
  # Equal significant streams ⇒ same program. This supersedes the MVP's raw re-lex
  # equivalence, which a reflowing formatter cannot satisfy (it moves newlines).
  @open [{:lparen}, {:lbracket}, {:lbrace}, {:mapopen}]
  @close [{:rparen}, {:rbracket}, {:rbrace}]
  # the parser's `Rian.Decl` @cont_ops: a depth-0 newline in a `:=` body adjacent
  # to one of these is a *continuation* (insignificant), so the oracle drops it.
  @cont_ops ~w(+ - * / < > <= >= == != <> |> and or in rem div)

  defp sig(src) do
    src
    |> Lexer.tokenize_trivia()
    |> Enum.reject(&match?({:comment, _}, &1))
    |> Enum.map(fn
      {:heredoc, c} -> {:str, String.trim(c)}
      t -> t
    end)
    |> drop_bracket_nl(0, [])
    |> drop_cont_nl(nil, [])
    |> collapse_nl([])
    |> strip_tc()
  end

  # drop a (depth-0) newline that sits next to a continuation operator
  defp drop_cont_nl([], _prev, acc), do: Enum.reverse(acc)

  defp drop_cont_nl([{:nl} | rest], prev, acc) do
    if cont_op?(prev) or cont_op?(List.first(rest)),
      do: drop_cont_nl(rest, prev, acc),
      else: drop_cont_nl(rest, prev, [{:nl} | acc])
  end

  defp drop_cont_nl([t | rest], _prev, acc), do: drop_cont_nl(rest, t, [t | acc])

  defp cont_op?({:op, o}), do: o in @cont_ops
  defp cont_op?(_), do: false

  defp drop_bracket_nl([], _d, acc), do: Enum.reverse(acc)
  defp drop_bracket_nl([t | r], d, acc) when t in @open, do: drop_bracket_nl(r, d + 1, [t | acc])

  defp drop_bracket_nl([t | r], d, acc) when t in @close,
    do: drop_bracket_nl(r, max(0, d - 1), [t | acc])

  defp drop_bracket_nl([{:nl} | r], d, acc) when d > 0, do: drop_bracket_nl(r, d, acc)
  defp drop_bracket_nl([t | r], d, acc), do: drop_bracket_nl(r, d, [t | acc])

  defp collapse_nl([], acc), do: Enum.reverse(acc)
  defp collapse_nl([{:nl}, {:nl} | r], acc), do: collapse_nl([{:nl} | r], acc)
  defp collapse_nl([t | r], acc), do: collapse_nl(r, [t | acc])

  defp strip_tc([{:comma}, c | r]) when c in @close, do: [c | strip_tc(r)]
  defp strip_tc([t | r]), do: [t | strip_tc(r)]
  defp strip_tc([]), do: []

  defp comments(src), do: Enum.filter(Lexer.tokenize_trivia(src), &match?({:comment, _}, &1))

  defp longest_line(src),
    do: src |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()

  describe "intra-line spacing" do
    test "function application and indexing bind tightly" do
      assert Format.format("def f() := g(x)\n") == "def f() := g(x)\n"
      assert Format.format("def f(xs) := xs[0]\n") == "def f(xs) := xs[0]\n"
    end

    test "normalizes ragged operator spacing to a single space" do
      assert Format.format("def f(x) := x+1\n") == "def f(x) := x + 1\n"
      assert Format.format("def f(x) := x   +   1\n") == "def f(x) := x + 1\n"
    end

    test "member access dot, unary minus, colons" do
      assert Format.format("def f() := Enum.map(xs, g)\n") == "def f() := Enum.map(xs, g)\n"
      assert Format.format("def f() := -1\n") == "def f() := -1\n"
      assert Format.format("def f(a, b) := a - b\n") == "def f(a, b) := a - b\n"
      assert Format.format("def f() := %{x: 0, y: 0}\n") == "def f() := %{x: 0, y: 0}\n"
      assert Format.format("def f() := g(:ok)\n") == "def f() := g(:ok)\n"
    end

    test "a reserved keyword used as a field label spaces like any label (ADR-0033)" do
      # `type:`/`def:` are keyword labels, not `: atom` openers — `type: v`, not `type :v`.
      assert Format.format("def f() := Field(type: \"T\")\n") == "def f() := Field(type: \"T\")\n"
      assert Format.format("def f() := %{case: 1}\n") == "def f() := %{case: 1}\n"
    end
  end

  describe "indentation" do
    test "do/end blocks indent two spaces per level" do
      src = "def sign(n)\nif n >= 0 do\n1\nelse\n-1\nend\nend\n"

      assert Format.format(src) == """
             def sign(n)
               if n >= 0 do
                 1
               else
                 -1
               end
             end
             """
    end

    test "a multi-line case arm body nests under the arm" do
      src = "def f(x)\ncase x do\nP(a) ->\ng(a)\nend\nend\n"

      assert Format.format(src) == """
             def f(x)
               case x do
                 P(a) ->
                   g(a)
               end
             end
             """
    end

    test "module body indents one level" do
      assert Format.format("mod M do\ndef f() := 1\nend\n") == "mod M do\n  def f() := 1\nend\n"
    end
  end

  describe "comments and blank lines" do
    test "trailing comments stay on their line (two spaces off)" do
      assert Format.format("def f() := 1  # one\n") == "def f() := 1  # one\n"
    end

    test "own-line comments keep their place and context indent" do
      assert Format.format("mod M do\n# note\ndef f() := 1\nend\n") ==
               "mod M do\n  # note\n  def f() := 1\nend\n"
    end

    test "collapses blank-line runs to one and trims edges" do
      assert Format.format("\n\ndef f() := 1\n\n\n\ndef g() := 2\n\n") ==
               "def f() := 1\n\ndef g() := 2\n"
    end

    test "heredocs are reproduced verbatim, not flattened" do
      triple = "\"\"\""
      src = "@doc #{triple}\nline one\nline two\n#{triple}\ndef f() := 1\n"
      out = Format.format(src)
      assert out =~ triple
      assert out =~ "line one\nline two"
    end
  end

  describe "Tier 2 — line wrapping (reflow inside brackets)" do
    test "a call that fits the budget stays on one line" do
      assert Format.format("def f() := g(a, b, c)\n") == "def f() := g(a, b, c)\n"
    end

    test "a call that overflows breaks one argument per line with a trailing comma" do
      args = Enum.map_join(1..7, ", ", &"argument_number_#{&1}")
      out = Format.format("def f() := call(#{args})\n")

      assert out == """
             def f() := call(
               argument_number_1,
               argument_number_2,
               argument_number_3,
               argument_number_4,
               argument_number_5,
               argument_number_6,
               argument_number_7,
             )
             """
    end

    test "an already-multiline literal that now fits is collapsed (no trailing comma)" do
      assert Format.format("def xs() := [\n  1,\n  2,\n  3\n]\n") == "def xs() := [1, 2, 3]\n"
    end

    test "magic trailing comma: an author's trailing comma keeps the group expanded" do
      assert Format.format("def xs() := [1, 2, 3,]\n") == """
             def xs() := [
               1,
               2,
               3,
             ]
             """
    end

    test "magic trailing comma is idempotent" do
      out = Format.format("def xs() := [1, 2, 3,]\n")
      assert Format.format(out) == out
    end

    test "no magic comma without a trailing comma — a fitting list stays inline" do
      assert Format.format("def xs() := [1, 2, 3]\n") == "def xs() := [1, 2, 3]\n"
    end

    test "no formatted line exceeds the column budget when the body is breakable" do
      long = "def f() := compute(#{Enum.map_join(1..12, ", ", &"arg_number_#{&1}")})\n"
      assert longest_line(Format.format(long)) <= @width
    end

    test "declaration heads are never reflowed (only the body wraps)" do
      src =
        "def process(first Int53, second Int53, third Int53) Int53 := compute(first_value, second_value, third_value, fourth_value)\n"

      out = Format.format(src)
      # the (long) head stays intact on its line; only the body call wraps
      assert out =~ "def process(first Int53, second Int53, third Int53) Int53 := compute(\n"
    end

    test "a trailing comment does not force a fitting list to break" do
      assert Format.format("def xs() := [a, b]  # tail\n") == "def xs() := [a, b]  # tail\n"
    end

    test "a cons list that overflows breaks WITHOUT a trailing comma (parser rejects one)" do
      heads = Enum.map_join(1..6, ", ", &"element_number_#{&1}")
      out = Format.format("def xs(rest Vec(Int53)) Vec(Int53) := [#{heads} | rest]\n")
      # one item per line, the cons tail kept with the last head, no trailing comma
      assert out =~ "element_number_6 | rest\n"
      refute out =~ "rest,\n"
      # and the result still parses — the whole point of suppressing the comma
      assert Decl.parse(out)
    end
  end

  describe "Tier 2 — depth-0 operator-chain wrapping (|> and or <>)" do
    test "a chain that fits stays on one line" do
      assert Format.format("def f() := a |> b |> c\n") == "def f() := a |> b |> c\n"
    end

    test "a pipe chain that overflows breaks leading-operator with a hanging indent" do
      src =
        "def run() := input_data |> transform(options) |> validate_everything(strict_mode) |> persist(store)\n"

      assert Format.format(src) == """
             def run() := input_data
               |> transform(options)
               |> validate_everything(strict_mode)
               |> persist(store)
             """
    end

    test "a source-multiline chain that now fits is collapsed (idempotence basis)" do
      assert Format.format("def f() := a\n  |> b\n  |> c\n") == "def f() := a |> b |> c\n"
    end

    test "wrapping is idempotent on an overflowing chain" do
      src =
        "def run() := step_one(x) |> step_two(y) |> step_three(z) |> step_four(w) |> step_five(v)\n"

      once = Format.format(src)
      assert Format.format(once) == once
    end

    test "an arithmetic chain breaks at the loosest operator (+), keeping * terms together" do
      src =
        "def total() Int53 := base_amount * quantity_count + shipping_cost * weight_kg + handling_fee + insurance\n"

      out = Format.format(src)
      assert out =~ "\n  + "
      # the tighter `*` is not a break point — its operands stay on one line
      refute out =~ "\n  * "
      assert out =~ "base_amount * quantity_count"
      assert Rian.Decl.parse(out)
    end

    test "a mixed and/or chain breaks only at the loosest operator (or)" do
      src =
        "def ok() Bool := check_one(value) and check_two(value) or fallback(value) and final_check(value, scope)\n"

      out = Format.format(src)
      assert out =~ "\n  or "
      refute out =~ "\n  and "
      assert Rian.Decl.parse(out)
    end

    test "a short arithmetic body stays inline" do
      assert Format.format("def f() := a + b * c\n") == "def f() := a + b * c\n"
    end

    test "a long boolean chain wraps and still parses" do
      src =
        "def ok() Bool := is_valid(value) and within_range(value) and not blocked(value) and allowed(value, scope)\n"

      out = Format.format(src)
      assert out =~ "\n  and "
      assert Rian.Decl.parse(out)
    end

    test "a block-internal bind chain is NOT chain-wrapped (its newline would become a `;`)" do
      src =
        "def f(x Int53) Int53\nresult := source_data |> alpha_mapper(p) |> beta_validator(q) |> gamma_filter(r) |> sink_storage(x)\nresult\nend\n"

      out = Format.format(src)
      # no leading-`|>` continuation line — the chain is not broken across lines
      refute out =~ ~r/\n\s*\|>/
      assert Rian.Decl.parse(out)
    end
  end

  describe "correctness bars over the real corpus" do
    @corpus Path.wildcard("examples/rian/*.rian") ++ Path.wildcard("compiler/*.rian")

    test "the corpus is non-empty (guards against a bad glob)" do
      assert length(@corpus) > 20
    end

    for file <- @corpus do
      @path file

      test "significant-token equivalence (meaning preserved): #{file}" do
        src = File.read!(@path)
        assert sig(Format.format(src)) == sig(src)
      end

      test "idempotence: #{file}" do
        once = Format.format(File.read!(@path))
        assert Format.format(once) == once
      end

      test "comment fidelity: #{file}" do
        src = File.read!(@path)
        assert comments(Format.format(src)) == comments(src)
      end
    end
  end

  describe "formatted output stays parseable (no corruption)" do
    # `sig/1` proves the *significant tokens* are preserved, but it strips the
    # trailing comma a reflow may add — so it cannot see a reflow that emits
    # *non-parsing* source (e.g. a comma after a cons tail, `[a | xs,]`). This bar
    # closes that gap: format a real file and assert the result still parses. It
    # covers only files the core parser fully models — a few examples exercise
    # constructs it does not (FFI `extern`, custom `@`-annotations) and do not parse
    # at all, so they are excluded; `sig/1` above still covers them.
    @parseable Enum.filter(@corpus, fn f ->
                 try do
                   Decl.parse(File.read!(f))
                   true
                 rescue
                   _ -> false
                 end
               end)

    test "a healthy majority of the corpus parses (guards a parser regression)" do
      assert length(@parseable) >= 30
    end

    for file <- @parseable do
      @path file

      test "format/1 output parses: #{file}" do
        assert @path |> File.read!() |> Format.format() |> Decl.parse()
      end
    end
  end
end
