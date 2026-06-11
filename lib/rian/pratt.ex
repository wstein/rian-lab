defmodule Rian.Pratt do
  @moduledoc """
  Precedence-climbing parser for Rian expressions, extended with the three
  self-hosting constructs: lambdas `(x) -> e`, `if c do .. else .. end`,
  blocks (`name := e; .. ; final`), and list/map literals.
  The operator-precedence core is unchanged (validated by rian_pratt_test.exs).
  """

  defmodule NonAssocError do
    defexception [:message]
  end

  @multi ["->", ":=", "|>", "<>", "<-", "<=", ">=", "==", "!="]
  @single ["+", "-", "*", "/", "<", ">", ".", "|", ":"]
  @words ~w(and or not in rem div)
  @ctrl ~w(if do else end)
  @infix ~w(+ - * / rem div <> in |> < <= > >= == != and or <-)

  def parse(str) do
    {ast, rest} = parse_expr(tokenize(str), 0)
    if rest != [], do: raise(ArgumentError, "trailing tokens: #{inspect(rest)}")
    ast
  end

  def parse_sexpr(str), do: sexpr(parse(str))

  defp advance(s, n), do: elem(String.split_at(s, n), 1)
  defp tokenize(str), do: do_tok(str, [])

  # Normalize a numeric lexeme so it is a valid literal on BOTH targets: an
  # exponent with no decimal point (`1e9`) is invalid Elixir, so inject `.0`
  # before the exponent marker (`1.0e9`). Plain ints/floats and `_` separators
  # pass through unchanged (already valid in Elixir and Rust alike).
  defp norm_num(lexeme) do
    if String.match?(lexeme, ~r/[eE]/) and not String.contains?(lexeme, ".") do
      String.replace(lexeme, ~r/[eE]/, ".0e", global: false)
    else
      lexeme
    end
  end

  defp do_tok(str, acc) do
    s = String.trim_leading(str)

    cond do
      s == "" ->
        Enum.reverse(acc)

      String.starts_with?(s, "%{") ->
        do_tok(advance(s, 2), [{:mapopen} | acc])

      String.starts_with?(s, "(") ->
        do_tok(advance(s, 1), [{:lparen} | acc])

      String.starts_with?(s, ")") ->
        do_tok(advance(s, 1), [{:rparen} | acc])

      String.starts_with?(s, "[") ->
        do_tok(advance(s, 1), [{:lbracket} | acc])

      String.starts_with?(s, "]") ->
        do_tok(advance(s, 1), [{:rbracket} | acc])

      String.starts_with?(s, "}") ->
        do_tok(advance(s, 1), [{:rbrace} | acc])

      String.starts_with?(s, ",") ->
        do_tok(advance(s, 1), [{:comma} | acc])

      String.starts_with?(s, ";") ->
        do_tok(advance(s, 1), [{:semi} | acc])

      op = Enum.find(@multi, &String.starts_with?(s, &1)) ->
        do_tok(advance(s, String.length(op)), [{:op, op} | acc])

      op = Enum.find(@single, &String.starts_with?(s, &1)) ->
        do_tok(advance(s, 1), [{:op, op} | acc])

      m = Regex.run(~r/^\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?/, s) ->
        lexeme = hd(m)
        do_tok(advance(s, String.length(lexeme)), [{:num, norm_num(lexeme)} | acc])

      m = Regex.run(~r/^[A-Za-z_]\w*/, s) ->
        w = hd(m)

        tok =
          cond do
            w in @words -> {:op, w}
            w in @ctrl -> {:kw, w}
            true -> {:id, w}
          end

        do_tok(advance(s, String.length(w)), [tok | acc])

      true ->
        raise ArgumentError, "cannot scan: #{inspect(s)}"
    end
  end

  defp opinfo(op) do
    cond do
      op in ~w(* / rem div) -> {3, :left}
      op in ~w(+ -) -> {4, :left}
      op == "<>" -> {5, :right}
      op == "in" -> {6, :none}
      op == "|>" -> {7, :left}
      op in ~w(< <= > >=) -> {8, :none}
      op in ~w(== !=) -> {9, :none}
      op == "and" -> {10, :left}
      op == "or" -> {11, :left}
      op == "<-" -> {12, :right}
    end
  end

  defp level(op), do: elem(opinfo(op), 0)
  defp assoc(op), do: elem(opinfo(op), 1)

  defp bp(op) do
    {lvl, a} = opinfo(op)
    base = (13 - lvl) * 10

    case a do
      :left -> {base, base + 1}
      :right -> {base + 1, base}
      :none -> {base, base + 1}
    end
  end

  defp parse_expr(tokens, min_bp) do
    {lhs, tokens} = parse_prefix(tokens)
    climb(lhs, tokens, min_bp)
  end

  defp climb(lhs, tokens, min_bp) do
    case peek_infix(tokens) do
      nil ->
        {lhs, tokens}

      op ->
        {lbp, rbp} = bp(op)

        if lbp < min_bp do
          {lhs, tokens}
        else
          if assoc(op) == :none and same_level_root?(lhs, op) do
            raise NonAssocError, message: "`#{op}` is non-associative; parenthesize"
          end

          [_ | rest] = tokens
          {rhs, rest} = parse_expr(rest, rbp)
          climb({:bin, op, lhs, rhs}, rest, min_bp)
        end
    end
  end

  defp same_level_root?({:bin, op2, _, _}, op), do: level(op2) == level(op)
  defp same_level_root?(_, _), do: false

  defp peek_infix([{:op, op} | _]) when op in @infix, do: op
  defp peek_infix(_), do: nil

  defp parse_prefix([{:op, op} | rest]) when op in ~w(- not) do
    {operand, rest} = parse_expr(rest, 110)
    {{:unary, op, operand}, rest}
  end

  defp parse_prefix(tokens), do: parse_primary(tokens)

  defp parse_primary([{:kw, "if"} | rest]), do: parse_if(rest)
  defp parse_primary([{:lbracket} | rest]), do: parse_list(rest, [])
  defp parse_primary([{:mapopen} | rest]), do: parse_map(rest, [])

  defp parse_primary([{:lparen} | _] = tokens) do
    if lambda_ahead?(tokens) do
      parse_lambda(tokens)
    else
      [{:lparen} | rest] = tokens
      {e, rest} = parse_expr(rest, 0)

      case rest do
        [{:rparen} | r2] -> parse_postfix(e, r2)
        _ -> raise ArgumentError, "expected `)`"
      end
    end
  end

  defp parse_primary([{:op, ":"}, {:id, name} | rest]), do: parse_postfix({:atom, name}, rest)
  defp parse_primary([{:num, n} | rest]), do: parse_postfix({:num, n}, rest)
  defp parse_primary([{:id, x} | rest]), do: parse_postfix({:id, x}, rest)
  defp parse_primary(other), do: raise(ArgumentError, "unexpected token: #{inspect(other)}")

  defp parse_postfix(node, [{:op, "."}, {:id, name} | rest]),
    do: parse_postfix({:dot, node, name}, rest)

  defp parse_postfix(node, [{:lparen} | rest]) do
    {args, rest} = parse_args(rest)
    parse_postfix({:call, node, args}, rest)
  end

  defp parse_postfix(node, tokens), do: {node, tokens}

  defp parse_args([{:rparen} | rest]), do: {[], rest}

  defp parse_args(tokens) do
    {a, tokens} = parse_expr(tokens, 0)

    case tokens do
      [{:comma} | rest] ->
        {more, rest} = parse_args(rest)
        {[a | more], rest}

      [{:rparen} | rest] ->
        {[a], rest}

      _ ->
        raise ArgumentError, "expected `,` or `)`"
    end
  end

  defp lambda_ahead?([{:lparen} | rest]), do: match?([{:op, "->"} | _], after_paren(rest, 1))

  defp after_paren(tokens, 0), do: tokens
  defp after_paren([{:lparen} | t], d), do: after_paren(t, d + 1)
  defp after_paren([{:rparen} | t], 1), do: t
  defp after_paren([{:rparen} | t], d), do: after_paren(t, d - 1)
  defp after_paren([_ | t], d), do: after_paren(t, d)
  defp after_paren([], _), do: []

  defp parse_lambda([{:lparen} | rest]) do
    {params, rest} = parse_params(rest)
    rest = expect_op(rest, "->")
    {body, rest} = parse_expr(rest, 0)
    {{:lambda, params, body}, rest}
  end

  defp parse_params([{:rparen} | rest]), do: {[], rest}

  defp parse_params(tokens) do
    {param, tokens} = parse_param(tokens)

    case tokens do
      [{:comma} | rest] ->
        {ps, rest} = parse_params(rest)
        {[param | ps], rest}

      [{:rparen} | rest] ->
        {[param], rest}

      other ->
        raise ArgumentError, "bad lambda params: #{inspect(other)}"
    end
  end

  defp parse_param([{:id, name}, {:id, ty} | rest]), do: {{name, ty}, rest}
  defp parse_param([{:id, name} | rest]), do: {{name, nil}, rest}

  defp parse_if(tokens) do
    {cnd, tokens} = parse_expr(tokens, 0)
    tokens = expect_kw(tokens, "do")
    {then_b, tokens} = parse_block(tokens)

    {else_b, tokens} =
      case tokens do
        [{:kw, "else"} | r] -> parse_block(r)
        _ -> {{:block, []}, tokens}
      end

    tokens = expect_kw(tokens, "end")
    {{:if, cnd, then_b, else_b}, tokens}
  end

  defp parse_block(tokens) do
    {stmts, tokens} = parse_stmts(tokens, [])
    {{:block, Enum.reverse(stmts)}, tokens}
  end

  defp parse_stmts([{:kw, k} | _] = tokens, acc) when k in ["else", "end"], do: {acc, tokens}
  defp parse_stmts([] = tokens, acc), do: {acc, tokens}

  defp parse_stmts(tokens, acc) do
    {stmt, tokens} = parse_stmt(tokens)

    case tokens do
      [{:semi} | rest] -> parse_stmts(rest, [stmt | acc])
      _ -> {[stmt | acc], tokens}
    end
  end

  defp parse_stmt([{:id, name}, {:op, ":="} | rest]) do
    {e, rest} = parse_expr(rest, 0)
    {{:bind, name, e}, rest}
  end

  defp parse_stmt(tokens) do
    {e, rest} = parse_expr(tokens, 0)
    {{:expr, e}, rest}
  end

  defp parse_list([{:rbracket} | rest], acc), do: {{:list_lit, Enum.reverse(acc), nil}, rest}

  defp parse_list(tokens, acc) do
    {e, tokens} = parse_expr(tokens, 0)

    case tokens do
      [{:comma} | rest] ->
        parse_list(rest, [e | acc])

      [{:rbracket} | rest] ->
        {{:list_lit, Enum.reverse([e | acc]), nil}, rest}

      [{:op, "|"} | rest] ->
        {tail, rest} = parse_expr(rest, 0)
        rest = expect_rbracket(rest)
        {{:list_lit, Enum.reverse([e | acc]), {:tail, tail}}, rest}

      other ->
        raise ArgumentError, "bad list: #{inspect(other)}"
    end
  end

  defp parse_map([{:rbrace} | rest], acc), do: {{:map_lit, Enum.reverse(acc)}, rest}

  defp parse_map([{:id, k}, {:op, ":"} | rest], acc) do
    {v, rest} = parse_expr(rest, 0)
    acc = [{k, v} | acc]

    case rest do
      [{:comma} | r] -> parse_map(r, acc)
      [{:rbrace} | r] -> {{:map_lit, Enum.reverse(acc)}, r}
      other -> raise ArgumentError, "bad map: #{inspect(other)}"
    end
  end

  defp expect_kw([{:kw, k} | rest], k), do: rest
  defp expect_kw(toks, k), do: raise(ArgumentError, "expected `#{k}`, got #{inspect(toks)}")
  defp expect_op([{:op, o} | rest], o), do: rest
  defp expect_op(toks, o), do: raise(ArgumentError, "expected `#{o}`, got #{inspect(toks)}")
  defp expect_rbracket([{:rbracket} | rest]), do: rest
  defp expect_rbracket(toks), do: raise(ArgumentError, "expected `]`, got #{inspect(toks)}")

  defp sexpr({:num, n}), do: n
  defp sexpr({:id, x}), do: x
  defp sexpr({:bin, op, l, r}), do: "(#{op} #{sexpr(l)} #{sexpr(r)})"
  defp sexpr({:unary, op, x}), do: "(#{op} #{sexpr(x)})"
  defp sexpr({:atom, a}), do: ":" <> a
  defp sexpr({:dot, o, n}), do: "(. #{sexpr(o)} #{n})"

  defp sexpr({:call, f, args}),
    do: "(call #{sexpr(f)}#{Enum.map_join(args, "", fn a -> " " <> sexpr(a) end)})"

  defp sexpr({:lambda, ps, b}),
    do: "(lambda (#{Enum.map_join(ps, " ", fn {n, _} -> n end)}) #{sexpr(b)})"

  defp sexpr({:if, c, t, e}), do: "(if #{sexpr(c)} #{sexpr(t)} #{sexpr(e)})"

  defp sexpr({:block, stmts}),
    do: "(block#{Enum.map_join(stmts, "", fn s -> " " <> sexpr_stmt(s) end)})"

  defp sexpr({:list_lit, elems, nil}), do: "[#{Enum.map_join(elems, " ", &sexpr/1)}]"

  defp sexpr({:list_lit, elems, {:tail, t}}),
    do: "[#{Enum.map_join(elems, " ", &sexpr/1)} | #{sexpr(t)}]"

  defp sexpr({:map_lit, pairs}),
    do: "%{#{Enum.map_join(pairs, " ", fn {k, v} -> "#{k}: #{sexpr(v)}" end)}}"

  defp sexpr_stmt({:bind, n, e}), do: "(:= #{n} #{sexpr(e)})"
  defp sexpr_stmt({:expr, e}), do: sexpr(e)
end
