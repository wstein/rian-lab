defmodule Rian.Pratt do
  @moduledoc """
  Precedence-climbing parser for Rian expressions, extended with the three
  self-hosting constructs: lambdas `(x) -> e`, `if c do .. else .. end`,
  blocks (`name := e; .. ; final`), and list/map literals.
  The operator-precedence core is unchanged (validated by rian_pratt_test.exs).

  Tokenization is delegated to `Rian.Lexer` (the shared tokenizer); this module
  consumes its newline-free `expr_tokens/1` stream.
  """

  defmodule NonAssocError do
    defexception [:message]
  end

  # `<~` is capability-gated mutation (ADR-0039). `<-` is NOT a general infix —
  # it is the failable-bind arrow, valid only in `with`/`for` clause headers.
  @infix ~w(+ - * / rem div <> in |> < <= > >= == != and or <~)

  def parse(str) do
    {ast, rest} = parse_expr(Rian.Lexer.expr_tokens(str), 0)
    if rest != [], do: raise(ArgumentError, "trailing tokens: #{inspect(rest)}")
    ast
  end

  def parse_sexpr(str), do: sexpr(parse(str))

  @doc """
  Parse a comma-separated pattern list (a clause head's parameters) into surface
  patterns. The single pattern parser (`parse_pat`) — shared with `case` arms —
  is the one place patterns are parsed (ADR-0050 §2: one parser).
  """
  def parse_pats(str) do
    case Rian.Lexer.expr_tokens(str) do
      [] -> []
      tokens -> parse_pats(tokens, [])
    end
  end

  defp parse_pats(tokens, acc) do
    {p, tokens} = parse_pat(tokens)

    case tokens do
      [] -> Enum.reverse([p | acc])
      [{:comma} | rest] -> parse_pats(rest, [p | acc])
      other -> raise ArgumentError, "trailing tokens in pattern list: #{inspect(other)}"
    end
  end

  @doc """
  Parse a function body — a block of `;`-separated statements with a final
  value expression (a single `:= expr` body is the one-statement case). Always
  returns a `{:block, stmts}` node; the emitter unwraps a single expression.
  """
  def parse_body(str) do
    {block, rest} = parse_block(Rian.Lexer.expr_tokens(str))
    if rest != [], do: raise(ArgumentError, "trailing tokens in body: #{inspect(rest)}")
    block
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
      op == "<~" -> {12, :right}
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

  # `&` — function capture (B'): `&(&1 + &2)` anonymous, or `&name/arity` named.
  defp parse_prefix([{:op, "&"} | rest]), do: parse_capture(rest)

  defp parse_prefix(tokens), do: parse_primary(tokens)

  # `&N` placeholder
  defp parse_capture([{:num, n} | rest]),
    do: parse_postfix({:cap_arg, String.to_integer(n)}, rest)

  # `&( expr )` — anonymous capture; placeholders inside set the arity
  defp parse_capture([{:lparen} | rest]) do
    {body, rest} = parse_expr(rest, 0)
    rest = expect_rparen(rest)
    {{:capture, body}, rest}
  end

  # `&name/arity` or `&Mod.fun/arity` or `&:erl.fun/arity`
  defp parse_capture(tokens) do
    {path, rest} = parse_path(tokens)
    rest = expect_op(rest, "/")

    case rest do
      [{:num, n} | r] -> {{:capture_named, path, String.to_integer(n)}, r}
      other -> raise ArgumentError, "expected an integer arity after `/`: #{inspect(other)}"
    end
  end

  defp parse_path([{:op, ":"}, {:id, name} | rest]), do: collect_dots({:atom, name}, rest)
  defp parse_path([{:id, name} | rest]), do: collect_dots({:id, name}, rest)
  defp parse_path(other), do: raise(ArgumentError, "bad capture path: #{inspect(other)}")

  defp collect_dots(node, [{:op, "."}, {:id, n} | rest]), do: collect_dots({:dot, node, n}, rest)
  defp collect_dots(node, rest), do: {node, rest}

  defp parse_primary([{:kw, "if"} | rest]), do: parse_if(rest)
  defp parse_primary([{:kw, "case"} | rest]), do: parse_case(rest)
  defp parse_primary([{:kw, "with"} | rest]), do: parse_with(rest)
  defp parse_primary([{:lbracket} | rest]), do: parse_list(rest, [])
  defp parse_primary([{:mapopen} | rest]), do: parse_map(rest, [])
  defp parse_primary([{:lbrace} | rest]), do: parse_tuple(rest, [])

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
  defp parse_primary([{:str, s} | rest]), do: parse_postfix({:str, s}, rest)
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

  # `name: expr` — a labeled argument (named struct/variant construction). `id :`
  # is unambiguous here (an atom is `: id`, colon first), so it cannot collide.
  defp parse_args([{:id, name}, {:op, ":"} | rest]) do
    {v, rest} = parse_expr(rest, 0)
    finish_arg({:label, name, v}, rest)
  end

  defp parse_args(tokens) do
    {a, tokens} = parse_expr(tokens, 0)
    finish_arg(a, tokens)
  end

  defp finish_arg(a, [{:comma} | rest]) do
    {more, rest} = parse_args(rest)
    {[a | more], rest}
  end

  defp finish_arg(a, [{:rparen} | rest]), do: {[a], rest}
  defp finish_arg(_a, _), do: raise(ArgumentError, "expected `,` or `)`")

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

  # `with pat <- expr, … do body [else arms] end` (ADR-0040). Each `pat <- expr`
  # is a failable bind (ADR-0039); a non-match short-circuits to `else` (or, with
  # no `else`, propagates the non-matching value).
  defp parse_with(tokens) do
    {clauses, tokens} = parse_with_clauses(tokens, [])
    tokens = expect_kw(tokens, "do")
    {body, tokens} = parse_block(tokens)

    {else_arms, tokens} =
      case tokens do
        [{:kw, "else"} | r] -> parse_arms(r, [])
        _ -> {[], tokens}
      end

    tokens = expect_kw(tokens, "end")
    {{:with, clauses, body, else_arms}, tokens}
  end

  defp parse_with_clauses(tokens, acc) do
    {pat, tokens} = parse_pat(tokens)
    tokens = expect_op(tokens, "<-")
    {expr, tokens} = parse_expr(tokens, 0)
    acc = [{pat, expr} | acc]

    case tokens do
      [{:comma} | rest] -> parse_with_clauses(rest, acc)
      _ -> {Enum.reverse(acc), tokens}
    end
  end

  # `case scrut do pattern [when guard] -> body … end` (Elixir form, ADR-0033).
  defp parse_case(tokens) do
    {scrut, tokens} = parse_expr(tokens, 0)
    tokens = expect_kw(tokens, "do")
    {arms, tokens} = parse_arms(tokens, [])
    tokens = expect_kw(tokens, "end")
    {{:case, scrut, arms}, tokens}
  end

  defp parse_arms([{:kw, "end"} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_arms(tokens, acc) do
    {pat, tokens} = parse_pat(tokens)

    {guard, tokens} =
      case tokens do
        [{:kw, "when"} | rest] -> parse_expr(rest, 0)
        _ -> {nil, tokens}
      end

    tokens = expect_op(tokens, "->")
    {body, tokens} = parse_expr(tokens, 0)
    parse_arms(tokens, [{pat, guard, body} | acc])
  end

  # token-level pattern parser (arm heads): wildcard, integer, atom, tuple, var, constructor
  defp parse_pat([{:id, "_"} | rest]), do: {:wild, rest}
  defp parse_pat([{:op, "-"}, {:num, n} | rest]), do: {{:lit, -String.to_integer(n)}, rest}
  defp parse_pat([{:num, n} | rest]), do: {{:lit, String.to_integer(n)}, rest}
  defp parse_pat([{:op, ":"}, {:id, name} | rest]), do: {{:atom, name}, rest}
  defp parse_pat([{:str, s} | rest]), do: {{:lit, s}, rest}
  defp parse_pat([{:lbrace} | rest]), do: parse_pat_tuple(rest, [])
  defp parse_pat([{:lbracket} | rest]), do: parse_pat_list(rest, [])
  # map pattern `%{k: p, …}` — matches any map carrying those keys (ADR-0043)
  defp parse_pat([{:mapopen} | rest]), do: parse_pat_map(rest, [])

  defp parse_pat([{:id, name} | rest]) do
    if pascal?(name) do
      case rest do
        # named fields -> a struct pattern `Name(field: p, …)` (symmetric with
        # construction); positional args -> a sum-variant pattern `Name(p, …)`
        [{:lparen}, {:id, _}, {:op, ":"} | _] ->
          [{:lparen} | r] = rest
          {fields, r} = parse_pat_fields(r, [])
          {{:struct, name, fields}, r}

        [{:lparen} | r] ->
          {args, r} = parse_pat_args(r, [])
          {{:ctor, name, args}, r}

        _ ->
          {{:ctor, name, []}, rest}
      end
    else
      {{:var, name}, rest}
    end
  end

  defp parse_pat(other), do: raise(ArgumentError, "unsupported pattern: #{inspect(other)}")

  # map pattern body: `k: p` pairs until the closing `}` (the `%{` opener is
  # already consumed); keys are identifiers (atom-style, like map literals)
  defp parse_pat_map([{:rbrace} | rest], acc), do: {{:map, Enum.reverse(acc)}, rest}

  defp parse_pat_map([{:id, k}, {:op, ":"} | rest], acc) do
    {p, rest} = parse_pat(rest)

    case rest do
      [{:comma} | r] -> parse_pat_map(r, [{k, p} | acc])
      [{:rbrace} | r] -> {{:map, Enum.reverse([{k, p} | acc])}, r}
      other -> raise ArgumentError, "bad map pattern: #{inspect(other)}"
    end
  end

  defp parse_pat_map(other, _acc), do: raise(ArgumentError, "bad map pattern: #{inspect(other)}")

  # struct pattern fields: `field: p` pairs until the closing `)`
  defp parse_pat_fields([{:rparen} | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_pat_fields([{:id, k}, {:op, ":"} | rest], acc) do
    {p, rest} = parse_pat(rest)

    case rest do
      [{:comma} | r] -> parse_pat_fields(r, [{k, p} | acc])
      [{:rparen} | r] -> {Enum.reverse([{k, p} | acc]), r}
      other -> raise ArgumentError, "bad struct pattern: #{inspect(other)}"
    end
  end

  defp parse_pat_fields(other, _acc),
    do: raise(ArgumentError, "bad struct pattern fields: #{inspect(other)}")

  defp parse_pat_tuple([{:rbrace} | rest], acc), do: {{:tuple, Enum.reverse(acc)}, rest}

  defp parse_pat_tuple(tokens, acc) do
    {p, tokens} = parse_pat(tokens)

    case tokens do
      [{:comma} | rest] -> parse_pat_tuple(rest, [p | acc])
      [{:rbrace} | rest] -> {{:tuple, Enum.reverse([p | acc])}, rest}
      other -> raise ArgumentError, "bad tuple pattern: #{inspect(other)}"
    end
  end

  # list pattern `[p1, …]` (closed) or `[p1, … | tail]` (cons tail)
  defp parse_pat_list([{:rbracket} | rest], acc), do: {{:list, Enum.reverse(acc), :close}, rest}

  defp parse_pat_list(tokens, acc) do
    {p, tokens} = parse_pat(tokens)

    case tokens do
      [{:comma} | rest] ->
        parse_pat_list(rest, [p | acc])

      [{:rbracket} | rest] ->
        {{:list, Enum.reverse([p | acc]), :close}, rest}

      [{:op, "|"} | rest] ->
        {tail, rest} = parse_pat(rest)
        rest = expect_rbracket(rest)
        {{:list, Enum.reverse([p | acc]), {:tail, tail}}, rest}

      other ->
        raise ArgumentError, "bad list pattern: #{inspect(other)}"
    end
  end

  defp parse_pat_args([{:rparen} | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_pat_args(tokens, acc) do
    {p, tokens} = parse_pat(tokens)

    case tokens do
      [{:comma} | rest] -> parse_pat_args(rest, [p | acc])
      [{:rparen} | rest] -> {Enum.reverse([p | acc]), rest}
      other -> raise ArgumentError, "expected `,` or `)` in pattern: #{inspect(other)}"
    end
  end

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

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

  # typed binding `x Int32 := 66` — the declared type sits between the name and
  # `:=`. The annotation is carried as a `{:typed_bind, name, type, expr}` node so
  # the checker can enforce it (ADR-0034 §1: a numeric literal *adopts* the
  # declared width; an already-typed RHS must *unify exactly*) and display the
  # binding at the declared type. Every backend erases the annotation — `Int*`
  # is representation intent, not a portable overflow contract (ADR-0034 §1).
  # (`name type` is otherwise not a valid statement, so this only newly accepts
  # the typed-binding form.) Parametric types (`Vec(Int64)`) are future.
  defp parse_stmt([{:id, name}, {:id, type}, {:op, ":="} | rest]) do
    {e, rest} = parse_expr(rest, 0)
    {{:typed_bind, name, type, e}, rest}
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

  # tuple literal `{e1, e2, …}` (a bare `{}` is the empty tuple)
  defp parse_tuple([{:rbrace} | rest], acc), do: {{:tuple, Enum.reverse(acc)}, rest}

  defp parse_tuple(tokens, acc) do
    {e, tokens} = parse_expr(tokens, 0)

    case tokens do
      [{:comma} | rest] -> parse_tuple(rest, [e | acc])
      [{:rbrace} | rest] -> {{:tuple, Enum.reverse([e | acc])}, rest}
      other -> raise ArgumentError, "bad tuple: #{inspect(other)}"
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
  defp expect_rparen([{:rparen} | rest]), do: rest
  defp expect_rparen(toks), do: raise(ArgumentError, "expected `)`, got #{inspect(toks)}")

  defp sexpr({:num, n}), do: n
  defp sexpr({:str, s}), do: "\"#{s}\""
  defp sexpr({:id, x}), do: x
  defp sexpr({:bin, op, l, r}), do: "(#{op} #{sexpr(l)} #{sexpr(r)})"
  defp sexpr({:unary, op, x}), do: "(#{op} #{sexpr(x)})"
  defp sexpr({:atom, a}), do: ":" <> a
  defp sexpr({:dot, o, n}), do: "(. #{sexpr(o)} #{n})"
  defp sexpr({:cap_arg, n}), do: "&#{n}"
  defp sexpr({:capture, b}), do: "(& #{sexpr(b)})"
  defp sexpr({:capture_named, p, a}), do: "(&/ #{sexpr(p)} #{a})"

  defp sexpr({:label, n, e}), do: "#{n}: #{sexpr(e)}"

  defp sexpr({:call, f, args}),
    do: "(call #{sexpr(f)}#{Enum.map_join(args, "", fn a -> " " <> sexpr(a) end)})"

  defp sexpr({:lambda, ps, b}),
    do: "(lambda (#{Enum.map_join(ps, " ", fn {n, _} -> n end)}) #{sexpr(b)})"

  defp sexpr({:if, c, t, e}), do: "(if #{sexpr(c)} #{sexpr(t)} #{sexpr(e)})"

  defp sexpr({:case, s, arms}),
    do:
      "(case #{sexpr(s)}#{Enum.map_join(arms, "", fn {p, _g, b} -> " (#{sexpr_pat(p)} -> #{sexpr(b)})" end)})"

  defp sexpr({:with, clauses, body, els}) do
    cs = Enum.map_join(clauses, " ", fn {p, e} -> "(<- #{sexpr_pat(p)} #{sexpr(e)})" end)

    e =
      if els == [],
        do: "",
        else:
          " (else#{Enum.map_join(els, "", fn {p, _g, b} -> " (#{sexpr_pat(p)} -> #{sexpr(b)})" end)})"

    "(with #{cs} #{sexpr(body)}#{e})"
  end

  defp sexpr({:block, stmts}),
    do: "(block#{Enum.map_join(stmts, "", fn s -> " " <> sexpr_stmt(s) end)})"

  defp sexpr({:tuple, es}), do: "{#{Enum.map_join(es, " ", &sexpr/1)}}"

  defp sexpr({:list_lit, elems, nil}), do: "[#{Enum.map_join(elems, " ", &sexpr/1)}]"

  defp sexpr({:list_lit, elems, {:tail, t}}),
    do: "[#{Enum.map_join(elems, " ", &sexpr/1)} | #{sexpr(t)}]"

  defp sexpr({:map_lit, pairs}),
    do: "%{#{Enum.map_join(pairs, " ", fn {k, v} -> "#{k}: #{sexpr(v)}" end)}}"

  defp sexpr_stmt({:bind, n, e}), do: "(:= #{n} #{sexpr(e)})"
  defp sexpr_stmt({:typed_bind, n, t, e}), do: "(:= #{n} #{t} #{sexpr(e)})"
  defp sexpr_stmt({:expr, e}), do: sexpr(e)

  defp sexpr_pat(:wild), do: "_"
  defp sexpr_pat({:lit, v}) when is_binary(v), do: "\"#{v}\""
  defp sexpr_pat({:lit, v}), do: to_string(v)
  defp sexpr_pat({:atom, a}), do: ":" <> a
  defp sexpr_pat({:tuple, ps}), do: "{#{Enum.map_join(ps, ", ", &sexpr_pat/1)}}"
  defp sexpr_pat({:list, ps, :close}), do: "[#{Enum.map_join(ps, ", ", &sexpr_pat/1)}]"

  defp sexpr_pat({:list, ps, {:tail, t}}),
    do: "[#{Enum.map_join(ps, ", ", &sexpr_pat/1)} | #{sexpr_pat(t)}]"

  defp sexpr_pat({:var, x}), do: x
  defp sexpr_pat({:ctor, n, []}), do: n
  defp sexpr_pat({:ctor, n, args}), do: "#{n}(#{Enum.map_join(args, ", ", &sexpr_pat/1)})"
end
