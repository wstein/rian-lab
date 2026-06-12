defmodule Rian.Decl do
  @moduledoc """
  Stage 0.1 declaration parser (ADR-0031) — the gate from "verified components"
  to "a language that reads source files."

  Parses `.rian` declaration source into the IR the lowering pipeline already
  consumes (`Rian.Lower.compile/2`), then drives it. Surface follows ADR-0033:
  `def`, juxtaposed types, Crystal primitive names, `:=` bodies.

  ## Supported (MVP)

    * `type Name := Ctor(field Type, …) | Ctor2 | …` — sum declarations.
    * `def` functions, single- or multi-parameter:
      * single typed clause — `def add(x Int64, y Int64) Int64 := x + y`
      * bodiless signature + pattern clauses —
        `def max2(a Int64, b Int64) Int64` then `def max2(a, b) when a >= b := a`
    * `:=` bodies (single expressions parsed by `Rian.Pratt`), including string
      literals and `when` guards.

  Multi-line type/def declarations are joined (a line that does not start a
  declaration continues the previous one).

  ## Not yet supported

  `do … end` block and `case` expression bodies, and `mod`/`struct`/`alias`
  declarations. Each raises `Rian.Decl.Error`.
  """
  alias Rian.Lower

  defmodule Error do
    defexception [:message]
  end

  @caps ~w(val iso ref tag)

  # ── Public API ─────────────────────────────────────────────────────────
  @doc "Parse source into `%{types: [...], funcs: [...]}` (pipeline IR)."
  def parse(src) do
    decls = src |> logical_decls() |> Enum.map(&classify/1)
    %{types: for({:type, t} <- decls, do: parse_type(t)), funcs: build_funcs(decls)}
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

  # ── Lines -> logical declarations ──────────────────────────────────────
  defp logical_decls(src) do
    src
    |> String.split("\n")
    |> Enum.map(&(&1 |> strip_comment() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce([], fn line, acc ->
      cond do
        starts_decl?(line) -> [line | acc]
        acc == [] -> raise Error, "continuation before any declaration: #{line}"
        true -> [hd(acc) <> " " <> line | tl(acc)]
      end
    end)
    |> Enum.reverse()
  end

  defp strip_comment(line), do: line |> String.split("#", parts: 2) |> hd()

  # Every known declaration keyword starts a new declaration, so an unsupported
  # one (`struct`/`mod`/…) is classified and rejected with a clear message rather
  # than silently glued onto the previous declaration as a continuation line.
  @decl_kws ~w(type def struct alias mod const macro use import)
  defp starts_decl?(line), do: Enum.any?(@decl_kws, &String.starts_with?(line, &1 <> " "))

  defp classify(line) do
    case String.split(line, " ", parts: 2) do
      ["type", rest] -> {:type, rest}
      ["def", rest] -> {:def, rest}
      [kw | _] -> raise Error, "unsupported declaration `#{kw}` (MVP: `type` / `def`)"
    end
  end

  # ── `type` declarations ────────────────────────────────────────────────
  defp parse_type(rest) do
    case split_once(rest, ":=") do
      {left, right} ->
        %{
          name: strip_type_params(left),
          variants: right |> split_top("|") |> Enum.map(&variant/1)
        }

      :none ->
        raise Error, "type declaration needs `:=`: #{rest}"
    end
  end

  defp strip_type_params(name), do: name |> String.split("(", parts: 2) |> hd() |> String.trim()

  defp variant(v) do
    case extract_parens(v) do
      {ctor, inside, ""} -> %{ctor: String.trim(ctor), fields: fields(inside)}
      {_, _, rest} -> raise Error, "trailing tokens after variant `#{v}`: #{rest}"
      :none -> %{ctor: String.trim(v), fields: []}
    end
  end

  defp fields(inside) do
    case String.trim(inside) do
      "" -> []
      s -> s |> split_top(",") |> Enum.map(&field/1)
    end
  end

  defp field(f) do
    case f |> String.split(~r/\s+/, trim: true) |> Enum.reject(&(&1 in @caps)) do
      [type] -> %{type: type}
      [label, type] -> %{label: label, type: type}
      _ -> raise Error, "bad field `#{f}`"
    end
  end

  # ── `def` declarations -> grouped functions ────────────────────────────
  defp build_funcs(decls) do
    decls
    |> Enum.flat_map(fn
      {:def, d} -> [parse_def(d)]
      _ -> []
    end)
    |> Enum.chunk_by(& &1.name)
    |> Enum.map(&build_func/1)
  end

  defp parse_def(d) do
    {name, params, rest} =
      case extract_parens(d) do
        {n, inside, rest} -> {String.trim(n), String.trim(inside), rest}
        :none -> raise Error, "def needs a parameter list: #{d}"
      end

    {head, body} =
      case split_once(rest, ":=") do
        {h, b} -> {h, b}
        :none -> {String.trim(rest), nil}
      end

    {ret, guard} = parse_head(head)
    %{name: name, params: params, ret: ret, guard: guard, body: body}
  end

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

    %{
      name: sig.name,
      params: params,
      ret: req_ret(sig),
      clauses: Enum.map(clauses, &clause(&1, length(params)))
    }
  end

  # single typed clause — each parameter binds itself as the clause pattern
  defp build_func([%{body: body} = d]) when not is_nil(body) do
    params = parse_params(d.params)

    %{
      name: d.name,
      params: params,
      ret: req_ret(d),
      clauses: [%{pats: Enum.map(params, &{:var, &1.name}), body: body, guard: d.guard}]
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

    %{pats: pats, body: body, guard: guard}
  end

  defp parse_params(str) do
    str
    |> split_top(",")
    |> Enum.with_index()
    |> Enum.map(fn {p, i} ->
      {name, cap, type} = param(p)
      %{name: name || "arg#{i}", type: type, cap: cap}
    end)
  end

  defp param(p) do
    {caps, rest} = p |> String.split(~r/\s+/, trim: true) |> Enum.split_with(&(&1 in @caps))

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
