defmodule Rian.Pratt do
  use Rian.Ann

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

  # already-parsed passthrough (symmetric with `parse_body/1`): a Rian-written
  # front-end (ADR-0063 Stage 2) may hand the checker/emitters an AST directly —
  # e.g. a clause guard parsed in Rian — so they can re-`parse` it idempotently.
  # Still run `Prim.normalize` (idempotent): a front-end-built AST may carry raw
  # `Prim.*` calls that must be rewritten to `__prim_*`, exactly as the string path.
  @spec parse(String.t() | tuple()) :: tuple()
  def parse(ast) when is_tuple(ast), do: Rian.Prim.normalize(ast)

  def parse(str) when is_binary(str) do
    {ast, rest} = parse_expr(Rian.Lexer.expr_tokens(str), 0)
    if rest != [], do: raise(ArgumentError, "trailing tokens: #{inspect(rest)}")
    Rian.Prim.normalize(ast)
  end

  @rian_sig "pub def parse_sexpr(str String) String"
  @spec parse_sexpr(String.t()) :: String.t()
  def parse_sexpr(str), do: sexpr(parse(str))

  @doc """
  Parse a comma-separated pattern list (a clause head's parameters) into surface
  patterns. The single pattern parser (`parse_pat`) — shared with `case` arms —
  is the one place patterns are parsed (ADR-0050 §2: one parser).
  """
  @spec parse_pats(String.t()) :: [tuple()]
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
  # Already-parsed body passthrough: macro expansion (`Rian.Decl`) runs before the
  # checker/emitters and stores the expanded `{:block, …}` AST back into a clause's
  # `body`, so every consumer that re-parses a body transparently sees expanded,
  # normalized code without threading a macro env (the body was normalized when it
  # was first parsed here).
  @spec parse_body(String.t() | tuple()) :: tuple()
  def parse_body(ast) when is_tuple(ast), do: ast

  def parse_body(str) when is_binary(str) do
    {block, rest} = parse_block(Rian.Lexer.expr_tokens(str))
    if rest != [], do: raise(ArgumentError, "trailing tokens in body: #{inspect(rest)}")
    Rian.Prim.normalize(block)
  end

  @doc """
  Errors-as-values entry point (ADR-0035/0040): parse a body, returning
  `{:ok, ast} | {:error, message}` instead of raising. The single boundary that
  converts the parser's internal raise into a value; callers that recover from a
  parse failure pattern-match this rather than `try/rescue`.
  """
  @spec parse_body_result(String.t() | tuple()) :: {:ok, tuple()} | {:error, String.t()}
  @rian_host "parser boundary: parse_body raises a malformed-input error into a value"
  def parse_body_result(src) do
    {:ok, parse_body(src)}
  rescue
    e -> {:error, Exception.message(e)}
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
    do: parse_postfix({:cap_arg, int_of(n)}, rest)

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
      [{:num, n} | r] -> {{:capture_named, path, int_of(n)}, r}
      other -> raise ArgumentError, "expected an integer arity after `/`: #{inspect(other)}"
    end
  end

  defp parse_path([{:op, ":"}, {:id, name} | rest]), do: collect_dots({:atom, name}, rest)
  defp parse_path([{:op, ":"}, {:str, s} | rest]), do: collect_dots({:atom, s}, rest)
  defp parse_path([{:id, name} | rest]), do: collect_dots({:id, name}, rest)
  defp parse_path(other), do: raise(ArgumentError, "bad capture path: #{inspect(other)}")

  defp collect_dots(node, [{:op, "."}, {:id, n} | rest]), do: collect_dots({:dot, node, n}, rest)
  defp collect_dots(node, rest), do: {node, rest}

  defp parse_primary([{:kw, "if"} | rest]), do: parse_if(rest)
  defp parse_primary([{:kw, "case"} | rest]), do: parse_case(rest)
  defp parse_primary([{:kw, "with"} | rest]), do: parse_with(rest)
  defp parse_primary([{:kw, "for"} | rest]), do: parse_for(rest)
  defp parse_primary([{:lbracket} | rest]), do: parse_list(rest, [])
  defp parse_primary([{:mapopen} | rest]), do: parse_map_start(rest)
  defp parse_primary([{:bitopen} | rest]), do: parse_bitstr(rest, [])
  defp parse_primary([{:lbrace} | rest]), do: parse_tuple(rest, [])

  defp parse_primary([{:lparen} | _] = tokens) do
    if lambda_ahead?(tokens) do
      parse_lambda(tokens)
    else
      [{:lparen} | rest] = tokens
      {e, rest} = parse_expr(rest, 0)

      case rest do
        [{:rparen} | r2] -> parse_postfix(e, r2)
        _ -> raise ArgumentError, "expected `)`, got #{here(rest)}"
      end
    end
  end

  defp parse_primary([{:op, ":"}, {:id, name} | rest]), do: parse_postfix({:atom, name}, rest)
  # a quoted atom `:"+"` / `:"hello world"` (Elixir-style): any atom whose name is
  # not a bare identifier — operators, mixed case, reserved words. The lexer emits
  # `:` + a plain string; an *interpolated* `:"${x}"` is not a literal and falls
  # through to an error.
  defp parse_primary([{:op, ":"}, {:str, s} | rest]), do: parse_postfix({:atom, s}, rest)
  defp parse_primary([{:str, s} | rest]), do: parse_postfix({:str, s}, rest)
  # an interpolated string `"… ${expr} …"` (ADR-0069): each hole's raw source is
  # re-parsed as an expression. The node is resolved to a `<>`/stringify chain by
  # `Rian.Interp` once types are known; an empty hole `${}` is a parse error.
  defp parse_primary([{:istr, parts} | rest]), do: parse_postfix(str_interp(parts), rest)
  defp parse_primary([{:num, n} | rest]), do: parse_postfix({:num, n}, rest)
  # a `Char` literal (ADR-0036) — a distinct node typed `Char` by the checker,
  # lowered to a codepoint integer on BEAM/JS and a native `char` on Rust
  defp parse_primary([{:char, cp} | rest]), do: parse_postfix({:char, cp}, rest)
  defp parse_primary([{:id, x} | rest]), do: parse_postfix({:id, x}, rest)
  defp parse_primary(other), do: raise(ArgumentError, "unexpected token: #{here(other)}")

  # build the `{:str_interp, parts}` node — literal segments pass through, each
  # hole's raw source is parsed as a full expression (ADR-0069). An empty hole is
  # a parse error (there is nothing to stringify).
  defp str_interp(parts) do
    resolved =
      Enum.map(parts, fn
        {:lit, s} ->
          {:lit, s}

        {:hole, src} ->
          case String.trim(src) do
            "" -> raise ArgumentError, "empty interpolation hole `${}` — nothing to interpolate"
            _ -> {:hole, parse(src)}
          end
      end)

    {:str_interp, resolved}
  end

  defp parse_postfix(node, [{:op, "."}, {:id, name} | rest]),
    do: parse_postfix({:dot, node, name}, rest)

  defp parse_postfix(node, [{:lparen} | rest]) do
    {args, rest} = parse_args(rest)
    parse_postfix({:call, node, args}, rest)
  end

  defp parse_postfix(node, tokens), do: {node, tokens}

  defp parse_args([{:rparen} | rest]), do: {[], rest}

  # `name: expr` — a labeled argument (named struct/variant construction). `id :`
  # is unambiguous here (an atom is `: id`, colon first), so it cannot collide. A
  # reserved keyword is a valid label too (`Field(type: t)`, like Elixir `%{type:
  # 1}`) — in label position the `word :` shape is unambiguous.
  defp parse_args([{tag, name}, {:op, ":"} | rest]) when tag in [:id, :kw] do
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

    # An `else`-less `if` parses to an empty else block: it is a unit-typed *effect*
    # statement (Rust's `if` typing). In **value** position (return / binding RHS /
    # argument / a branch feeding a used value) `else` is mandatory — that is an
    # expression that must yield a value — and is enforced by `Rian.Check`
    # (`check_if_else`, ADR-0035 §6), not here, since the parser lacks position context.
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

  # `for p <- src, filter, … do body end` (ADR-0079). A comma-separated clause is a
  # generator (`var <- src`, reusing the ADR-0039 `<-` arrow) or a boolean filter.
  # Parses to a surface `{:comprehension, clauses, body}` that `Core.from_expr`
  # desugars to nested `List.flat_map`/`if`/`[body]` over the portable prelude.
  defp parse_for(tokens) do
    {clauses, tokens} = parse_for_clauses(tokens, [])
    tokens = expect_kw(tokens, "do")
    {body, tokens} = parse_block(tokens)
    tokens = expect_kw(tokens, "end")
    {{:comprehension, clauses, body}, tokens}
  end

  defp parse_for_clauses(tokens, acc) do
    {clause, rest} = parse_for_clause(tokens)
    acc = [clause | acc]

    case rest do
      [{:comma} | r] -> parse_for_clauses(r, acc)
      _ -> {Enum.reverse(acc), rest}
    end
  end

  # a clause is a **generator** (`pat <- src`, ADR-0079) iff a top-level `<-` precedes
  # the clause boundary (a filter expression can never contain `<-`); the generator
  # binds a full pattern (a non-match *skips* the element, Elixir semantics). Otherwise
  # it is a boolean filter.
  defp parse_for_clause(tokens) do
    if for_generator?(tokens, 0) do
      {pat, rest} = parse_pat(tokens)
      rest = expect_op(rest, "<-")
      {src, rest} = parse_expr(rest, 0)
      {{:gen, pat, src}, rest}
    else
      {expr, rest} = parse_expr(tokens, 0)
      {{:filter, expr}, rest}
    end
  end

  # is there a top-level `<-` before the clause boundary (a `,` or `do` at bracket
  # depth 0)? `<-` appears only in a generator header, never inside a filter.
  defp for_generator?([{:op, "<-"} | _], 0), do: true
  defp for_generator?([{:comma} | _], 0), do: false
  defp for_generator?([{:kw, "do"} | _], 0), do: false
  defp for_generator?([], _depth), do: false
  defp for_generator?([t | rest], depth), do: for_generator?(rest, depth + for_depth(t))

  defp for_depth({o}) when o in [:lparen, :lbracket, :lbrace, :mapopen, :bitopen], do: 1
  defp for_depth({c}) when c in [:rparen, :rbracket, :rbrace, :bitclose], do: -1
  defp for_depth(_), do: 0

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

  # integer value of a numeric lexeme — strips `_` separators the lexer preserves
  # in the lexeme (`1_000` lexes as `{:num, "1_000"}`; `String.to_integer/1` would
  # otherwise raise on the underscore — the lexer/parser contradiction the review
  # flagged).
  defp int_of(n), do: n |> String.replace("_", "") |> String.to_integer()

  # token-level pattern parser (arm heads): wildcard, integer, atom, tuple, var, constructor
  defp parse_pat([{:id, "_"} | rest]), do: {:wild, rest}
  defp parse_pat([{:op, "-"}, {:num, n} | rest]), do: {{:lit, -int_of(n)}, rest}
  defp parse_pat([{:num, n} | rest]), do: {{:lit, int_of(n)}, rest}
  # a `Char` literal pattern (ADR-0036) — a distinct node so a clause head can
  # match a `Char` by value (codepoint on BEAM/JS, native `char` on Rust)
  defp parse_pat([{:char, cp} | rest]), do: {{:char_lit, cp}, rest}
  defp parse_pat([{:op, ":"}, {:id, name} | rest]), do: {{:atom, name}, rest}
  defp parse_pat([{:op, ":"}, {:str, s} | rest]), do: {{:atom, s}, rest}
  defp parse_pat([{:str, s} | rest]), do: {{:lit, s}, rest}
  defp parse_pat([{:lbrace} | rest]), do: parse_pat_tuple(rest, [])
  defp parse_pat([{:lbracket} | rest]), do: parse_pat_list(rest, [])
  # map pattern `%{k: p, …}` — matches any map carrying those keys (ADR-0043)
  defp parse_pat([{:mapopen} | rest]), do: parse_pat_map(rest, [])
  defp parse_pat([{:bitopen} | rest]), do: parse_bitstr_pat(rest, [])

  # a pin `^expr` (ADR-0036/0050): match the *value* of an already-bound expression
  # (refutable), not a new binder. The pinned expression parses as an expression.
  defp parse_pat([{:op, "^"} | rest]) do
    {e, rest} = parse_expr(rest, 0)
    {{:pin, e}, rest}
  end

  # as-pattern `name @ pat` — bind the whole value to `name` while also matching
  # `pat` (Core `PAs`). `@ ` must be spaced so it is not the `@name` annotation.
  defp parse_pat([{:id, name}, {:op, "@"} | rest]) do
    {p, rest} = parse_pat(rest)
    {{:as, name, p}, rest}
  end

  defp parse_pat([{:id, name} | rest]) do
    if pascal?(name) do
      case rest do
        # named fields -> a struct pattern `Name(field: p, …)` (symmetric with
        # construction); positional args -> a sum-variant pattern `Name(p, …)`
        [{:lparen}, {tag, _}, {:op, ":"} | _] when tag in [:id, :kw] ->
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

  # atom-key map pattern `%{k: p}` — `k` is the atom key, `p` the bound sub-pattern.
  defp parse_pat_map([{tag, k}, {:op, ":"} | rest], acc) when tag in [:id, :kw] do
    {p, rest} = parse_pat(rest)
    pat_map_after(rest, [{k, p} | acc])
  end

  # non-atom key map pattern `%{keyExpr => p}` (ADR-0033): the key is a *value*
  # (an expression, e.g. a string literal) looked up in the map, not a pattern;
  # `p` is the bound sub-pattern. Wrap the key `{:key, expr}` like the literal form.
  defp parse_pat_map(toks, acc) do
    {k, rest} = parse_expr(toks, 0)
    rest = expect_op(rest, "=>")
    {p, rest} = parse_pat(rest)
    pat_map_after(rest, [{{:key, k}, p} | acc])
  end

  defp pat_map_after(rest, acc) do
    case rest do
      [{:comma} | r] -> parse_pat_map(r, acc)
      [{:rbrace} | r] -> {{:map, Enum.reverse(acc)}, r}
      other -> raise ArgumentError, "bad map pattern: #{inspect(other)}"
    end
  end

  # struct pattern fields: `field: p` pairs until the closing `)`
  defp parse_pat_fields([{:rparen} | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_pat_fields([{tag, k}, {:op, ":"} | rest], acc) when tag in [:id, :kw] do
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
      other -> raise ArgumentError, "expected `,` or `)` in pattern, got #{here(other)}"
    end
  end

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  defp parse_block(tokens) do
    {stmts, tokens} = parse_stmts(tokens, [])
    {desugar_propagation(Enum.reverse(stmts)), tokens}
  end

  # ADR-0066 (P4): a bare `name <- expr` statement is **error propagation** —
  # desugar a block carrying one into a `case` over the `Result`: `{:ok, name}`
  # binds and continues; `{:error, e}` short-circuits, returning the error
  # unchanged (so the enclosing function's error set carries it — the pub-boundary
  # invariant is then the checker's job over the resulting `case`). Sugar over the
  # same Result match `with` desugars to; no new semantics.
  defp desugar_propagation(stmts) do
    if Enum.any?(stmts, &match?({:bind_arrow, _, _}, &1)),
      do: desugar_prop(stmts, 0),
      else: {:block, stmts}
  end

  # `depth` is a deterministic per-arrow counter naming each propagation's error
  # binder `__prop_e<depth>` — so nested `<-` chains get distinct names (no shadowing)
  # without a non-deterministic gensym, which would break bit-identical re-parse
  # (ADR-0063 §3 determinism). The `__`-prefix keeps it out of the user namespace.
  defp desugar_prop(stmts, depth) do
    {before, rest} = Enum.split_while(stmts, &(not match?({:bind_arrow, _, _}, &1)))

    case rest do
      [] ->
        {:block, before}

      [{:bind_arrow, name, _e}] ->
        # A bare `<-` "binds and continues" (ADR-0066): it must be followed by an
        # expression that uses the bound value. A *trailing* `<-` has nothing to
        # continue to — the ok branch would silently evaluate to `nil` while the
        # error branch returns `{:error, e}` — so it is a mistake, not sugar.
        raise ArgumentError,
              "a bare `<-` propagation bind (`#{name} <- …`) must be followed by an " <>
                "expression; nothing may follow it as the block's last statement " <>
                "(it binds and continues — use `:=` to just return the Result)"

      [{:bind_arrow, name, e} | after_arrow] ->
        ev = "__prop_e#{depth}"

        prop_case =
          {:case, e,
           [
             {{:tuple, [{:atom, "ok"}, {:var, name}]}, nil, desugar_prop(after_arrow, depth + 1)},
             {{:tuple, [{:atom, "error"}, {:var, ev}]}, nil,
              {:tuple, [{:atom, "error"}, {:id, ev}]}}
           ]}

        {:block, before ++ [{:expr, prop_case}]}
    end
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

  # `name <- expr` — failable bind / error propagation outside a `with` (ADR-0066,
  # P4). Desugared by `parse_block` into a `Result` `case` (Ok continues, Error
  # short-circuits). `<-` is otherwise only a `with`/`for` clause-header arrow.
  defp parse_stmt([{:id, name}, {:op, "<-"} | rest]) do
    {e, rest} = parse_expr(rest, 0)
    {{:bind_arrow, name, e}, rest}
  end

  # typed binding `x Int32 := 66` / `xs Vec(Int64) := [1, 2, 3]` — a declared type
  # sits between the name and `:=`. It is carried as a `{:typed_bind, name, type,
  # expr}` node so the checker can enforce it (ADR-0034 §1: a numeric literal
  # *adopts* the declared width; an already-typed RHS must be *assignable* — it may
  # widen losslessly but not narrow) and display the binding at the declared type.
  # Every backend erases the annotation —
  # `Int*` is representation intent, not a portable overflow contract (ADR-0034 §1).
  # The type may be parametric (`Vec(Int64)`, `Map(String, Int64)`, nested). A
  # `name type` sequence is otherwise not a valid statement, so when the type
  # phrase is *not* followed by `:=` we fall back to parsing an expression.
  defp parse_stmt([{:id, name}, {:id, _} | _] = tokens) do
    [{:id, ^name} | rest] = tokens

    case parse_type(rest) do
      {type, [{:op, ":="} | rest]} ->
        {e, rest} = parse_expr(rest, 0)
        {{:typed_bind, name, type, e}, rest}

      _ ->
        {e, rest} = parse_expr(tokens, 0)
        {{:expr, e}, rest}
    end
  end

  defp parse_stmt(tokens) do
    {e, rest} = parse_expr(tokens, 0)
    {{:expr, e}, rest}
  end

  # A type phrase in annotation position: `Name` with an optional parenthesized,
  # comma-separated list of nested type phrases — `Int32`, `Vec(Int64)`,
  # `Map(String, Int64)`, `Vec(Vec(Int64))`. Rendered with **no interior spaces**
  # to match the checker's canonical type strings (`Check.list_of`, `Decl`'s
  # `collapse_parens`), so an annotation unifies with an inferred parametric type.
  defp parse_type([{:id, name}, {:lparen} | rest]) do
    {args, rest} = parse_type_args(rest, [])
    {"#{name}(#{Enum.join(args, ",")})", rest}
  end

  defp parse_type([{:id, name} | rest]), do: {name, rest}

  defp parse_type_args(tokens, acc) do
    {t, rest} = parse_type(tokens)

    case rest do
      [{:rparen} | rest] -> {Enum.reverse([t | acc]), rest}
      [{:comma} | rest] -> parse_type_args(rest, [t | acc])
      other -> raise ArgumentError, "malformed type argument list: #{inspect(other)}"
    end
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

  # `%{}` and `%{k: v, …}` are map literals; `%{base | k: v, …}` is a map *update*
  # (ADR-0033) — replace the named keys on an existing map, every key required to be
  # present (the BEAM `:=` exact-assoc, Rust struct-update, JS spread). The first
  # form after `%{` disambiguates: a key (`id`/`kw`) immediately followed by `:` is a
  # literal; anything else is an update base expression, which parses up to the `|`
  # (`|` is not an infix expression operator, so it stops the base cleanly).
  defp parse_map_start([{:rbrace} | rest]), do: {{:map_lit, []}, rest}

  defp parse_map_start([{tag, _}, {:op, ":"} | _] = toks) when tag in [:id, :kw] do
    {pairs, rest} = parse_map_pairs(toks, [])
    {{:map_lit, pairs}, rest}
  end

  # the leading form is an arbitrary expression: either a map *update* base
  # (`%{base | …}`) or the first key of a non-atom-key literal (`%{key => v, …}`,
  # ADR-0033). Parse it, then the next token disambiguates (`|` vs `=>`).
  defp parse_map_start(toks) do
    {first, rest} = parse_expr(toks, 0)

    case rest do
      [{:op, "|"} | r] ->
        {pairs, rest} = parse_map_pairs(r, [])
        {{:map_update, first, pairs}, rest}

      [{:op, "=>"} | r] ->
        {v, r} = parse_expr(r, 0)
        {pairs, rest} = map_pairs_after(r, [{{:key, first}, v}])
        {{:map_lit, pairs}, rest}

      other ->
        raise ArgumentError, "bad map: #{inspect(other)}"
    end
  end

  defp parse_map_pairs([{:rbrace} | rest], acc), do: {Enum.reverse(acc), rest}

  # atom-key shorthand `k: v` (`k` a bare identifier/keyword key).
  defp parse_map_pairs([{tag, k}, {:op, ":"} | rest], acc) when tag in [:id, :kw] do
    {v, rest} = parse_expr(rest, 0)
    map_pairs_after(rest, [{k, v} | acc])
  end

  # non-atom key `keyExpr => v` (ADR-0033): the key is an arbitrary expression,
  # wrapped `{:key, expr}` so Core/emitters distinguish it from an atom key.
  defp parse_map_pairs(toks, acc) do
    {k, rest} = parse_expr(toks, 0)
    rest = expect_op(rest, "=>")
    {v, rest} = parse_expr(rest, 0)
    map_pairs_after(rest, [{{:key, k}, v} | acc])
  end

  # shared pair separator: `,` continues, `}` closes.
  defp map_pairs_after(rest, acc) do
    case rest do
      [{:comma} | r] -> parse_map_pairs(r, acc)
      [{:rbrace} | r] -> {Enum.reverse(acc), r}
      other -> raise ArgumentError, "bad map: #{inspect(other)}"
    end
  end

  # bitstring `<<seg, …>>` (ADR-0078): each segment is `value` or `value :: spec`,
  # spec a `-`-joined list of `{:type, name}` / `{:size, n}` / `{:unit, n}`. The value
  # stops at `::`/`,`/`>>` (none are infix), so `parse_expr` cleanly bounds it.
  defp parse_bitstr([{:bitclose} | rest], acc), do: {{:bitstr, Enum.reverse(acc)}, rest}

  defp parse_bitstr(tokens, acc) do
    {seg, rest} = parse_bitseg(tokens)

    case rest do
      [{:comma} | r] -> parse_bitstr(r, [seg | acc])
      [{:bitclose} | r] -> {{:bitstr, Enum.reverse([seg | acc])}, r}
      other -> raise ArgumentError, "expected `,` or `>>` in bitstring, got #{here(other)}"
    end
  end

  defp parse_bitseg(tokens) do
    {value, rest} = parse_expr(tokens, 0)

    case rest do
      [{:op, "::"} | r] ->
        {specs, r2} = parse_bitspec(r)
        {{:bitseg, value, specs}, r2}

      _ ->
        {{:bitseg, value, []}, rest}
    end
  end

  defp parse_bitspec(tokens) do
    {item, rest} = parse_bitspec_item(tokens)

    case rest do
      [{:op, "-"} | r] ->
        {more, r2} = parse_bitspec(r)
        {[item | more], r2}

      _ ->
        {[item], rest}
    end
  end

  defp parse_bitspec_item([{:num, n} | rest]), do: {{:size, int_of(n)}, rest}

  defp parse_bitspec_item([{:id, "size"}, {:lparen}, {:num, n}, {:rparen} | rest]),
    do: {{:size, int_of(n)}, rest}

  defp parse_bitspec_item([{:id, "unit"}, {:lparen}, {:num, n}, {:rparen} | rest]),
    do: {{:unit, int_of(n)}, rest}

  # a *dynamic* size `size(var)` is not supported yet (ADR-0078: literal sizes only) —
  # fail with a precise message instead of mis-parsing `size` as a type specifier.
  defp parse_bitspec_item([{:id, "size"}, {:lparen}, {:id, v}, {:rparen} | _]),
    do:
      raise(
        ArgumentError,
        "dynamic bitstring size `size(#{v})` is not supported yet (ADR-0078) — use a literal, e.g. `size(8)`"
      )

  defp parse_bitspec_item([{:id, name} | rest]), do: {{:type, name}, rest}

  defp parse_bitspec_item(other),
    do: raise(ArgumentError, "bad bitstring specifier: #{here(other)}")

  # a bitstring *pattern* `<<seg::spec, …>>` (ADR-0078) — each segment's value is a
  # simple sub-pattern (binder / literal / `_`); specs reuse `parse_bitspec`.
  defp parse_bitstr_pat([{:bitclose} | rest], acc), do: {{:bitstr_pat, Enum.reverse(acc)}, rest}

  defp parse_bitstr_pat(tokens, acc) do
    {seg, rest} = parse_bitpat_seg(tokens)

    case rest do
      [{:comma} | r] ->
        parse_bitstr_pat(r, [seg | acc])

      [{:bitclose} | r] ->
        {{:bitstr_pat, Enum.reverse([seg | acc])}, r}

      other ->
        raise ArgumentError, "expected `,` or `>>` in bitstring pattern, got #{here(other)}"
    end
  end

  defp parse_bitpat_seg(tokens) do
    {value, rest} = parse_bitpat_value(tokens)

    case rest do
      [{:op, "::"} | r] ->
        {specs, r2} = parse_bitspec(r)
        {{:bitseg, value, specs}, r2}

      _ ->
        {{:bitseg, value, []}, rest}
    end
  end

  defp parse_bitpat_value([{:id, "_"} | rest]), do: {:wild, rest}
  defp parse_bitpat_value([{:id, name} | rest]), do: {{:var, name}, rest}
  defp parse_bitpat_value([{:op, "-"}, {:num, n} | rest]), do: {{:lit, -int_of(n)}, rest}
  defp parse_bitpat_value([{:num, n} | rest]), do: {{:lit, int_of(n)}, rest}
  defp parse_bitpat_value([{:char, cp} | rest]), do: {{:char_lit, cp}, rest}
  defp parse_bitpat_value([{:str, s} | rest]), do: {{:lit, s}, rest}

  defp parse_bitpat_value(other),
    do: raise(ArgumentError, "bad bitstring-pattern segment: #{here(other)}")

  defp expect_kw([{:kw, k} | rest], k), do: rest
  defp expect_kw(toks, k), do: raise(ArgumentError, "expected `#{k}`, got #{here(toks)}")
  defp expect_op([{:op, o} | rest], o), do: rest
  defp expect_op(toks, o), do: raise(ArgumentError, "expected `#{o}`, got #{here(toks)}")
  defp expect_rbracket([{:rbracket} | rest]), do: rest
  defp expect_rbracket(toks), do: raise(ArgumentError, "expected `]`, got #{here(toks)}")
  defp expect_rparen([{:rparen} | rest]), do: rest
  defp expect_rparen(toks), do: raise(ArgumentError, "expected `)`, got #{here(toks)}")

  # Describe the offending position for a parse error: the *first* token's kind and
  # value (`number \`3\``, `keyword \`def\``, …), not a raw `inspect/1` dump of the
  # whole remaining token stream — which buried the actual error in noise.
  defp here([]), do: "end of input"
  defp here([t | _]), do: tok_desc(t)

  defp tok_desc({:id, x}), do: "identifier `#{x}`"
  defp tok_desc({:num, n}), do: "number `#{n}`"
  defp tok_desc({:str, s}), do: ~s(string "#{s}")
  defp tok_desc({:char, cp}), do: "char `?#{cp}`"
  defp tok_desc({:op, o}), do: "operator `#{o}`"
  defp tok_desc({:kw, k}), do: "keyword `#{k}`"
  # (no `{:atom, _}` token: the lexer emits `:` + `id`, and `{:atom, _}` is built at
  # parse time — so an atom never appears in a raw token stream here.)
  # any other token (brackets, `{:nl}`, `{:comment, _}`, …) — a token is always a
  # tuple, so this is the total fallback (`Rian.Lexer.token/0`).
  defp tok_desc(t), do: "`#{elem(t, 0)}`"

  defp sexpr({:num, n}), do: n
  defp sexpr({:str, s}), do: "\"#{s}\""

  defp sexpr({:str_interp, parts}) do
    inner =
      Enum.map_join(parts, " ", fn
        {:lit, s} -> "\"#{s}\""
        {:hole, e} -> "${#{sexpr(e)}}"
      end)

    "(str-interp #{inner})"
  end

  defp sexpr({:char, cp}), do: "?#{cp}"
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

  defp sexpr({:comprehension, clauses, body}) do
    cs =
      Enum.map_join(clauses, " ", fn
        {:gen, p, src} -> "(<- #{sexpr_pat(p)} #{sexpr(src)})"
        {:filter, c} -> "(? #{sexpr(c)})"
      end)

    "(for #{cs} #{sexpr(body)})"
  end

  defp sexpr({:block, stmts}),
    do: "(block#{Enum.map_join(stmts, "", fn s -> " " <> sexpr_stmt(s) end)})"

  defp sexpr({:tuple, es}), do: "{#{Enum.map_join(es, " ", &sexpr/1)}}"

  defp sexpr({:list_lit, elems, nil}), do: "[#{Enum.map_join(elems, " ", &sexpr/1)}]"

  defp sexpr({:list_lit, elems, {:tail, t}}),
    do: "[#{Enum.map_join(elems, " ", &sexpr/1)} | #{sexpr(t)}]"

  defp sexpr({:map_lit, pairs}),
    do: "%{#{Enum.map_join(pairs, " ", &sexpr_map_pair/1)}}"

  defp sexpr({:bitstr, segs}),
    do: "<<#{Enum.map_join(segs, ", ", fn {:bitseg, v, _specs} -> sexpr(v) end)}>>"

  # a map pair: atom-key shorthand `k: v` or a computed key `keyExpr => v`.
  defp sexpr_map_pair({{:key, k}, v}), do: "#{sexpr(k)} => #{sexpr(v)}"
  defp sexpr_map_pair({k, v}), do: "#{k}: #{sexpr(v)}"

  defp sexpr_map_pat_pair({{:key, k}, p}), do: "#{sexpr(k)} => #{sexpr_pat(p)}"
  defp sexpr_map_pat_pair({k, p}), do: "#{k}: #{sexpr_pat(p)}"

  defp sexpr_stmt({:bind, n, e}), do: "(:= #{n} #{sexpr(e)})"
  defp sexpr_stmt({:typed_bind, n, t, e}), do: "(:= #{n} #{t} #{sexpr(e)})"
  defp sexpr_stmt({:expr, e}), do: sexpr(e)

  defp sexpr_pat(:wild), do: "_"
  defp sexpr_pat({:lit, v}) when is_binary(v), do: "\"#{v}\""
  defp sexpr_pat({:lit, v}), do: to_string(v)
  defp sexpr_pat({:char_lit, cp}), do: "?#{cp}"
  defp sexpr_pat({:atom, a}), do: ":" <> a
  defp sexpr_pat({:tuple, ps}), do: "{#{Enum.map_join(ps, ", ", &sexpr_pat/1)}}"
  defp sexpr_pat({:list, ps, :close}), do: "[#{Enum.map_join(ps, ", ", &sexpr_pat/1)}]"

  defp sexpr_pat({:list, ps, {:tail, t}}),
    do: "[#{Enum.map_join(ps, ", ", &sexpr_pat/1)} | #{sexpr_pat(t)}]"

  defp sexpr_pat({:var, x}), do: x
  defp sexpr_pat({:as, n, p}), do: "(@ #{n} #{sexpr_pat(p)})"
  defp sexpr_pat({:ctor, n, []}), do: n
  defp sexpr_pat({:ctor, n, args}), do: "#{n}(#{Enum.map_join(args, ", ", &sexpr_pat/1)})"

  defp sexpr_pat({:map, fields}),
    do: "%{#{Enum.map_join(fields, ", ", &sexpr_map_pat_pair/1)}}"

  defp sexpr_pat({:struct, n, fields}),
    do: "#{n}(#{Enum.map_join(fields, ", ", fn {k, p} -> "#{k}: #{sexpr_pat(p)}" end)})"

  defp sexpr_pat({:pin, e}), do: "(^ #{sexpr(e)})"
end
