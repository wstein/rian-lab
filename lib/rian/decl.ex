defmodule Rian.Decl do
  @moduledoc """
  Stage 0.1 declaration parser (ADR-0031) — the gate from "verified components"
  to "a language that reads source files."

  Parses `.rian` declaration source into the IR the lowering pipeline already
  consumes (`Rian.Lower.compile/2`), then drives it. Surface follows ADR-0033:
  `def`, juxtaposed types, Crystal primitive names, `:=` bodies.

  ## Implementation

  Token-driven recursive descent over `Rian.Lexer.tokenize/1`: `do`/`end`/`;`
  and significant `{:nl}` tokens drive declaration boundaries and block bodies,
  so block bodies — which the earlier line-joining MVP could not parse — work.
  Token *ranges* (params, patterns, bodies) are detokenized and handed to the
  string content helpers below; bodies are re-parsed by `Rian.Pratt.parse_body/1`.

  ## Supported

    * `type Name := Ctor(field Type, …) | Ctor2 | …` — sum declarations.
    * `def` functions, single- or multi-parameter:
      * single typed clause — `def add(x Int64, y Int64) Int64 := x + y`
      * bodiless signature + pattern clauses —
        `def max2(a Int64, b Int64) Int64` then `def max2(a, b) when a >= b := a`
    * `:=` one-liner bodies **and** multiline `… end` **block bodies**, including
      `case … do … end` expressions, string literals, and `when` guards.
    * `alias Name := Type` — transparent synonyms, resolved by substituting the
      name out of every type position (introduces no runtime form).

  ## Not yet supported

  `mod`/`struct` declarations. Each raises `Rian.Decl.Error`.
  """
  alias Rian.{Lexer, Lower}
  alias Rian.IR.{Clause, Field, Func, Param, Type, Variant}

  defmodule Error do
    defexception [:message]
  end

  @caps ~w(val iso ref tag)

  # ── Public API ─────────────────────────────────────────────────────────
  @doc "Parse source into `%{types: [...], funcs: [...]}` (pipeline IR)."
  def parse(src) do
    decls = src |> Lexer.tokenize() |> split_decls()

    # `alias Name := Type` is a transparent synonym: resolve it by substituting
    # the name out of every type position in the IR, so it never reaches the
    # emitter (ADR-0033 / types-match: aliases introduce no runtime form).
    aliases = Map.new(for {:alias, t} <- decls, do: parse_alias(t))

    funcs =
      decls
      |> Enum.flat_map(fn
        {:def, raw} -> [raw]
        _ -> []
      end)
      |> Enum.chunk_by(& &1.name)
      |> Enum.map(&build_func/1)
      |> Enum.map(&subst_func(&1, aliases))

    types = for({:type, t} <- decls, do: parse_type(t)) |> Enum.map(&subst_type(&1, aliases))
    %{types: types, funcs: funcs}
  end

  defp parse_alias(text) do
    case split_once(text, ":=") do
      {name, type} -> {strip_type_params(name), type}
      :none -> raise Error, "alias needs `:=`: #{text}"
    end
  end

  # whole-word substitution of every alias name in a type string (transitive)
  defp subst_type_str(type, aliases) do
    resolved =
      Enum.reduce(aliases, type, fn {name, val}, acc ->
        Regex.replace(~r/\b#{Regex.escape(name)}\b/, acc, val)
      end)

    if resolved == type, do: resolved, else: subst_type_str(resolved, aliases)
  end

  defp subst_func(%Func{params: ps, ret: ret} = f, aliases) do
    params =
      Enum.map(ps, fn %Param{} = p -> %Param{p | type: subst_type_str(p.type, aliases)} end)

    %Func{f | params: params, ret: subst_type_str(ret, aliases)}
  end

  defp subst_type(%Type{variants: vs} = t, aliases) do
    %Type{t | variants: Enum.map(vs, &subst_variant(&1, aliases))}
  end

  defp subst_variant(%Variant{fields: fs} = v, aliases) do
    %Variant{
      v
      | fields:
          Enum.map(fs, fn %Field{} = fl -> %Field{fl | type: subst_type_str(fl.type, aliases)} end)
    }
  end

  @doc "Parse and lower every function to both targets: `[{name, %{elixir, rust}}]`."
  def compile(src) do
    %{types: types, funcs: funcs} = parse(src)
    Enum.map(funcs, fn f -> {f.name, Lower.compile(types, f)} end)
  end

  @doc "Parse and lower to the BEAM target only (FFI / BEAM-only bodies)."
  def compile_beam(src) do
    %{types: types, funcs: funcs} = parse(src)
    Enum.map(funcs, fn f -> {f.name, Lower.compile_beam(types, f)} end)
  end

  # ── Tokens -> declarations (recursive descent) ─────────────────────────
  defp split_decls([]), do: []
  defp split_decls([{:nl} | rest]), do: split_decls(rest)

  defp split_decls([{:kw, "type"} | rest]) do
    {toks, rest} = take_type(rest, [])
    [{:type, Lexer.detokenize(toks)} | split_decls(rest)]
  end

  defp split_decls([{:kw, "def"} | rest]) do
    {raw, rest} = take_def(rest)
    [{:def, raw} | split_decls(rest)]
  end

  defp split_decls([{:kw, "alias"} | rest]) do
    {toks, rest} = take_type(rest, [])
    [{:alias, Lexer.detokenize(toks)} | split_decls(rest)]
  end

  defp split_decls([{:kw, kw} | _]),
    do: raise(Error, "unsupported declaration `#{kw}` (supported: `type` / `def` / `alias`)")

  defp split_decls([tok | _]), do: raise(Error, "expected a declaration, got #{inspect(tok)}")

  # A `type` runs to the newline that begins the next declaration (variant lines
  # beginning with `|` are continuations).
  defp take_type([], acc), do: {Enum.reverse(acc), []}

  defp take_type([{:nl} | rest], acc) do
    if rest == [] or decl_kw?(rest), do: {Enum.reverse(acc), rest}, else: take_type(rest, acc)
  end

  defp take_type([t | rest], acc), do: take_type(rest, [t | acc])

  defp decl_kw?([{:kw, k} | _]), do: k in ~w(type def struct alias mod pub const macro use import)
  defp decl_kw?(_), do: false

  # `def name(params) <head>` then a body: `:= expr` (to newline), a block
  # (`<nl> stmts end`), or nothing (a bodiless signature).
  defp take_def([{:id, name} | rest]) do
    {param_toks, rest} = balanced_parens(rest)
    take_head(name, Lexer.detokenize(param_toks), rest, [])
  end

  defp take_def(other),
    do: raise(Error, "expected a function name after `def`: #{inspect(other)}")

  defp take_head(name, params, [{:op, ":="} | rest], head) do
    {body_toks, rest} = take_line(rest, [])
    {def_raw(name, params, head, Lexer.detokenize(body_toks)), rest}
  end

  defp take_head(name, params, [{:nl} | rest], head) do
    if rest == [] or decl_kw?(rest) do
      {def_raw(name, params, head, nil), rest}
    else
      {block_toks, rest} = take_block(rest, 1, [])
      {def_raw(name, params, head, detok_block(block_toks)), rest}
    end
  end

  defp take_head(name, params, [], head), do: {def_raw(name, params, head, nil), []}
  defp take_head(name, params, [t | rest], head), do: take_head(name, params, rest, [t | head])

  defp def_raw(name, params, head_rev, body) do
    {ret, guard} = parse_head(Lexer.detokenize(Enum.reverse(head_rev)))
    %{name: name, params: params, ret: ret, guard: guard, body: body}
  end

  defp take_line([], acc), do: {Enum.reverse(acc), []}
  defp take_line([{:nl} | rest], acc), do: {Enum.reverse(acc), rest}
  defp take_line([t | rest], acc), do: take_line(rest, [t | acc])

  # Collect a block body up to the `end` that closes it; `do` (from nested
  # `if`/`case`) deepens, `end` un-deepens, depth 1's `end` closes the body.
  defp take_block([{:kw, "do"} = t | rest], depth, acc),
    do: take_block(rest, depth + 1, [t | acc])

  defp take_block([{:kw, "end"} | rest], 1, acc), do: {Enum.reverse(acc), rest}

  defp take_block([{:kw, "end"} = t | rest], depth, acc),
    do: take_block(rest, depth - 1, [t | acc])

  defp take_block([t | rest], depth, acc), do: take_block(rest, depth, [t | acc])
  defp take_block([], _depth, _acc), do: raise(Error, "block body not closed by `end`")

  defp balanced_parens([{:lparen} | rest]), do: take_parens(rest, 0, [])

  defp balanced_parens(other),
    do: raise(Error, "expected `(` after the function name: #{inspect(other)}")

  defp take_parens([{:rparen} | rest], 0, acc), do: {Enum.reverse(acc), rest}
  defp take_parens([{:lparen} = t | rest], d, acc), do: take_parens(rest, d + 1, [t | acc])
  defp take_parens([{:rparen} = t | rest], d, acc), do: take_parens(rest, d - 1, [t | acc])
  defp take_parens([t | rest], d, acc), do: take_parens(rest, d, [t | acc])
  defp take_parens([], _, _), do: raise(Error, "unbalanced `(` in the parameter list")

  # Detokenize a block body: a newline at block level (depth 0) separates
  # statements (`;`); a newline inside a nested `do … end` (a `case`/`if`) is
  # insignificant (those arms self-delimit), so it becomes whitespace.
  defp detok_block(tokens), do: tokens |> block_seps(0, []) |> Lexer.detokenize()

  defp block_seps([], _d, acc), do: Enum.reverse(acc)
  defp block_seps([{:kw, "do"} = t | r], d, acc), do: block_seps(r, d + 1, [t | acc])
  defp block_seps([{:kw, "end"} = t | r], d, acc), do: block_seps(r, d - 1, [t | acc])
  defp block_seps([{:nl} | r], 0, acc), do: block_seps(r, 0, [{:semi} | acc])
  defp block_seps([{:nl} | r], d, acc), do: block_seps(r, d, acc)
  defp block_seps([t | r], d, acc), do: block_seps(r, d, [t | acc])

  # ── `type` declarations ────────────────────────────────────────────────
  defp parse_type(rest) do
    case split_once(rest, ":=") do
      {left, right} ->
        %Type{
          name: strip_type_params(left),
          variants: right |> split_top("|") |> Enum.map(&variant/1)
        }

      :none ->
        raise Error, "type declaration needs `:=`: #{rest}"
    end
  end

  defp strip_type_params(name), do: name |> String.split("(", parts: 2) |> hd() |> String.trim()

  # Detokenized type strings space their parens/commas (`Vec ( Int64 )`); collapse
  # them back so a parenthesized type is one whitespace-split token (`Vec(Int64)`).
  defp collapse_parens(s), do: Regex.replace(~r/\s*([(),])\s*/, s, "\\1")

  defp variant(v) do
    case extract_parens(v) do
      {ctor, inside, ""} -> %Variant{ctor: String.trim(ctor), fields: fields(inside)}
      {_, _, rest} -> raise Error, "trailing tokens after variant `#{v}`: #{rest}"
      :none -> %Variant{ctor: String.trim(v), fields: []}
    end
  end

  defp fields(inside) do
    case String.trim(inside) do
      "" -> []
      s -> s |> split_top(",") |> Enum.map(&field/1)
    end
  end

  defp field(f) do
    case f
         |> collapse_parens()
         |> String.split(~r/\s+/, trim: true)
         |> Enum.reject(&(&1 in @caps)) do
      [type] -> %Field{type: type}
      [label, type] -> %Field{label: label, type: type}
      _ -> raise Error, "bad field `#{f}`"
    end
  end

  # ── `def` raw maps -> grouped functions ────────────────────────────────
  defp parse_head(head) do
    cond do
      head == "" ->
        {nil, nil}

      String.starts_with?(head, "when ") ->
        {nil, String.trim_leading(head, "when ")}

      String.contains?(head, " when ") ->
        head |> split2(" when ") |> then(fn {r, g} -> {nz(r), g} end)

      true ->
        {nz(head), nil}
    end
  end

  # multi-clause: bodiless signature followed by >=1 pattern clauses
  defp build_func([%{body: nil} = sig | [_ | _] = clauses]) do
    params = parse_params(sig.params)

    %Func{
      name: sig.name,
      params: params,
      ret: req_ret(sig),
      clauses: Enum.map(clauses, &clause(&1, length(params)))
    }
  end

  # single typed clause — each parameter binds itself as the clause pattern
  defp build_func([%{body: body} = d]) when not is_nil(body) do
    params = parse_params(d.params)

    %Func{
      name: d.name,
      params: params,
      ret: req_ret(d),
      clauses: [%Clause{pats: Enum.map(params, &{:var, &1.name}), body: body, guard: d.guard}]
    }
  end

  defp build_func([%{body: nil, name: n}]),
    do: raise(Error, "function `#{n}` has a signature but no clauses")

  defp build_func(group),
    do: raise(Error, "cannot group clauses of `#{hd(group).name}`")

  defp clause(%{body: nil, name: n}, _arity), do: raise(Error, "clause of `#{n}` has no body")

  defp clause(%{params: pstr, body: body, guard: guard}, arity) do
    pats = pstr |> split_top(",") |> Enum.map(&pattern/1)

    if length(pats) != arity do
      raise Error, "clause has #{length(pats)} patterns but the signature has arity #{arity}"
    end

    %Clause{pats: pats, body: body, guard: guard}
  end

  defp parse_params(str) do
    str
    |> split_top(",")
    |> Enum.with_index()
    |> Enum.map(fn {p, i} ->
      {name, cap, type} = param(p)
      %Param{name: name || "arg#{i}", type: type, cap: cap}
    end)
  end

  defp param(p) do
    {caps, rest} =
      p
      |> collapse_parens()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.split_with(&(&1 in @caps))

    cap =
      case caps do
        [] -> :val
        [c] -> String.to_atom(c)
        _ -> raise Error, "multiple capabilities on `#{p}`"
      end

    case rest do
      [type] -> {nil, cap, type}
      [name, type] -> {name, cap, type}
      _ -> raise Error, "bad parameter `#{p}`"
    end
  end

  # ── patterns (clause heads) ────────────────────────────────────────────
  defp pattern(str) do
    s = String.trim(str)

    cond do
      s == "_" -> :wild
      Regex.match?(~r/^-?\d+$/, s) -> {:lit, String.to_integer(s)}
      match?({_, _, _}, extract_parens(s)) -> ctor_pattern(s)
      Regex.match?(~r/^[A-Z]/, s) -> {:ctor, s, []}
      Regex.match?(~r/^[a-z_]\w*$/, s) -> {:var, s}
      true -> raise Error, "unsupported pattern `#{s}`"
    end
  end

  defp ctor_pattern(s) do
    {ctor, inside, ""} = extract_parens(s)

    args =
      case String.trim(inside) do
        "" -> []
        i -> i |> split_top(",") |> Enum.map(&pattern/1)
      end

    {:ctor, String.trim(ctor), args}
  end

  defp req_ret(%{ret: nil, name: n}), do: raise(Error, "function `#{n}` needs a return type")
  defp req_ret(%{ret: ret}), do: ret

  # ── string helpers ─────────────────────────────────────────────────────
  defp nz(s), do: if(String.trim(s) == "", do: nil, else: String.trim(s))

  defp split_once(str, sep) do
    case :binary.split(str, sep) do
      [l, r] -> {String.trim(l), String.trim(r)}
      [_] -> :none
    end
  end

  defp split2(str, sep) do
    [l, r] = String.split(str, sep, parts: 2)
    {l, String.trim(r)}
  end

  # split on a single-char separator at paren-depth 0; trims, drops empties
  defp split_top(str, sep) do
    {parts, {cur, _}} =
      str
      |> String.graphemes()
      |> Enum.reduce({[], {"", 0}}, fn ch, {parts, {cur, depth}} ->
        cond do
          ch == sep and depth == 0 -> {[cur | parts], {"", 0}}
          ch == "(" -> {parts, {cur <> ch, depth + 1}}
          ch == ")" -> {parts, {cur <> ch, depth - 1}}
          true -> {parts, {cur <> ch, depth}}
        end
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # "name(inside)rest" -> {name, inside, rest}; :none if no parens
  defp extract_parens(str) do
    case String.split(str, "(", parts: 2) do
      [_no_paren] ->
        :none

      [name, after_open] ->
        {inside, rest} = match_paren(after_open, 0, "")
        {name, inside, String.trim(rest)}
    end
  end

  defp match_paren("(" <> t, depth, acc), do: match_paren(t, depth + 1, acc <> "(")
  defp match_paren(")" <> t, 0, acc), do: {acc, t}
  defp match_paren(")" <> t, depth, acc), do: match_paren(t, depth - 1, acc <> ")")

  defp match_paren(<<c::utf8, t::binary>>, depth, acc),
    do: match_paren(t, depth, acc <> <<c::utf8>>)

  defp match_paren("", _depth, acc), do: {acc, ""}
end
