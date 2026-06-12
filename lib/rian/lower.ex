defmodule Rian.Lower do
  @moduledoc """
  End-to-end backend lowering for a single Rian function. Wires together:
    * type env             (Rian.Exhaustiveness)
    * pattern lowering     (Rian.PatternLower)
    * exhaustiveness gate  (Rian.Exhaustiveness.analyze)  -- refuses to emit if it fails
    * expression parsing   (Rian.Pratt)                    -- precedence-aware
  and emits idiomatic Elixir AND Rust.

  Inputs are the (would-be parser output) data:

      type = %{name: "Shape", variants: [
                 %{ctor: "Circle", fields: [%{label: "radius", type: "f64"}]},
                 %{ctor: "Square", fields: [%{label: "side",   type: "f64"}]}]}

      func = %{name: "area", params: [%{name: "shape", type: "Shape", cap: :val}], ret: "Float64",
               clauses: [%{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
                         %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}]}
  """
  alias Rian.Exhaustiveness, as: E
  alias Rian.PatternLower, as: PL
  alias Rian.Pratt

  # ── Pipeline ───────────────────────────────────────────────────────────
  def compile(types, func) do
    env = build_env(types)
    :ok = check!(func, env)
    meta = build_meta(types)
    %{elixir: to_elixir(func, types), rust: to_rust(func, types, meta)}
  end

  @doc "Compile to the BEAM target only (for functions using BEAM-only constructs)."
  def compile_beam(types, func) do
    env = build_env(types)
    :ok = check!(func, env)
    %{elixir: to_elixir(func, types)}
  end

  defp build_env(types) do
    Enum.reduce(types, E.base_env(), fn t, env ->
      variants = Enum.map(t.variants, fn v -> {PL.to_snake(v.ctor), length(v.fields)} end)
      E.add_type(env, PL.to_snake(t.name), variants)
    end)
  end

  # ctor_snake => %{enum: "Shape", labels: ["radius"], named: true}
  defp build_meta(types) do
    for t <- types, v <- t.variants, into: %{} do
      labels = Enum.map(v.fields, &Map.get(&1, :label))
      named = v.fields != [] and Enum.all?(v.fields, &Map.get(&1, :label))
      {PL.to_snake(v.ctor), %{enum: t.name, ctor: v.ctor, labels: labels, named: named}}
    end
  end

  # Exhaustiveness GATE — emission only proceeds if the match is total & has no dead clauses.
  defp check!(func, env) do
    arity = length(hd(func.clauses).pats)

    clauses =
      Enum.map(func.clauses, fn c ->
        PL.lower_clause(%{pats: c.pats, guard: Map.get(c, :guard) != nil}, env)
      end)

    r = E.analyze(clauses, arity, env)

    cond do
      not r.exhaustive? ->
        raise "non-exhaustive `#{func.name}`: pattern `#{E.render(r.missing)}` not covered"

      r.unreachable != [] ->
        raise "unreachable clauses in `#{func.name}`: #{inspect(r.unreachable)}"

      true ->
        :ok
    end
  end

  # ── Elixir backend ─────────────────────────────────────────────────────
  def to_elixir(func, types) do
    Enum.each(func.params, &Rian.Capability.beam_legal!(&1.cap))
    typespecs = Enum.map_join(types, "\n", &ex_typespec/1)

    clauses =
      Enum.map_join(func.clauses, "\n", fn c ->
        head = "def #{func.name}(#{Enum.map_join(c.pats, ", ", &pat_ex/1)})"
        body = emit(Pratt.parse_body(c.body), :elixir) |> elem(0)
        "#{head}#{guard_str(c, :elixir)} do #{body} end"
      end)

    typespecs <> "\n" <> clauses
  end

  # Optional clause guard: `nil` or a Rian guard-expression string. Lowers to
  # `when …` on Elixir and `if …` on Rust (clauses-guards §5).
  defp guard_str(c, target) do
    case Map.get(c, :guard) do
      g when is_binary(g) -> guard_kw(target) <> (emit(Pratt.parse(g), target) |> elem(0))
      _ -> ""
    end
  end

  defp guard_kw(:elixir), do: " when "
  defp guard_kw(:rust), do: " if "

  # A Rust match arm needs braces around a multi-statement block body; a single
  # expression (the `:= expr` case) is emitted bare.
  defp rust_arm_body({:block, [_, _ | _]}, s), do: "{ #{s} }"
  defp rust_arm_body(_, s), do: s

  defp case_guard(nil, _), do: ""
  defp case_guard(g, target), do: guard_kw(target) <> (emit(g, target) |> elem(0))

  # ── `&` capture support ────────────────────────────────────────────────
  # Highest placeholder index in an anonymous-capture body → the closure arity
  # the Rust target must spell out (`&(&1 + &2)` ⇒ 2 ⇒ `|a1, a2| …`).
  defp cap_arity({:cap_arg, n}), do: n
  defp cap_arity({:bin, _, l, r}), do: max(cap_arity(l), cap_arity(r))
  defp cap_arity({:unary, _, x}), do: cap_arity(x)
  defp cap_arity({:dot, o, _}), do: cap_arity(o)
  defp cap_arity({:if, c, t, e}), do: max(cap_arity(c), max(cap_arity(t), cap_arity(e)))

  defp cap_arity({:call, f, args}),
    do: Enum.reduce([f | args], 0, fn n, acc -> max(cap_arity(n), acc) end)

  defp cap_arity({:list_lit, es, tail}) do
    base = Enum.reduce(es, 0, fn e, acc -> max(cap_arity(e), acc) end)
    if match?({:tail, _}, tail), do: max(base, cap_arity(elem(tail, 1))), else: base
  end

  defp cap_arity({:map_lit, ps}),
    do: Enum.reduce(ps, 0, fn {_, v}, acc -> max(cap_arity(v), acc) end)

  defp cap_arity(_), do: 0

  # "aFrom, …, aTo" — empty when the range is empty (a nullary closure).
  defp closure_params(from, to) when to < from, do: ""
  defp closure_params(from, to), do: Enum.map_join(from..to, ", ", &"a#{&1}")

  defp ex_typespec(t) do
    body =
      Enum.map_join(t.variants, " | ", fn v ->
        tag = ":" <> Atom.to_string(PL.to_snake(v.ctor))

        case v.fields do
          [] -> tag
          fs -> "{#{tag}, #{Enum.map_join(fs, ", ", &prim_ex(&1.type))}}"
        end
      end)

    "@type #{PL.to_snake(t.name)} :: #{body}"
  end

  defp pat_ex(:wild), do: "_"
  defp pat_ex({:var, x}), do: x
  defp pat_ex({:lit, v}) when is_binary(v), do: inspect(v)
  defp pat_ex({:lit, v}), do: to_string(v)
  defp pat_ex({:tuple, ps}), do: "{#{Enum.map_join(ps, ", ", &pat_ex/1)}}"
  defp pat_ex({:ctor, name, []}), do: ":" <> Atom.to_string(PL.to_snake(name))

  defp pat_ex({:ctor, name, args}),
    do: "{:#{PL.to_snake(name)}, #{Enum.map_join(args, ", ", &pat_ex/1)}}"

  # ── Rust backend ───────────────────────────────────────────────────────
  def to_rust(func, types, meta) do
    # Ambient type meta for `case` constructor patterns nested in bodies, which
    # the recursive expression emitter would otherwise have no channel to reach
    # (a compiler-internal context, not language-level hidden control flow).
    Process.put({:rian, :meta}, meta)
    enums = Enum.map_join(types, "\n\n", &rust_enum/1)

    param_decls =
      Enum.map_join(func.params, ", ", fn p ->
        "#{p.name}: #{Rian.Capability.rust_param(p.cap, p.type)}"
      end)

    # One param matches the value directly; N>1 match the tuple of arguments
    # (clauses-guards §5.2).
    scrut = tuple_or_one(func.params, & &1.name)

    arms =
      Enum.map_join(func.clauses, "\n", fn c ->
        pat = tuple_or_one(c.pats, &pat_rs(&1, meta))
        body_ast = Pratt.parse_body(c.body)
        body = emit(body_ast, :rust) |> elem(0)
        "        #{pat}#{guard_str(c, :rust)} => #{rust_arm_body(body_ast, body)},"
      end)

    fn_str =
      "fn #{func.name}(#{param_decls}) -> #{prim_rust(func.ret)} {\n" <>
        "    match #{scrut} {\n#{arms}\n    }\n}"

    enums <> "\n\n" <> fn_str
  end

  defp tuple_or_one([one], f), do: f.(one)
  defp tuple_or_one(many, f), do: "(" <> Enum.map_join(many, ", ", f) <> ")"

  defp rust_enum(t) do
    variants =
      Enum.map_join(t.variants, "\n", fn v ->
        named = v.fields != [] and Enum.all?(v.fields, &Map.get(&1, :label))

        cond do
          v.fields == [] ->
            "    #{v.ctor},"

          named ->
            fs = Enum.map_join(v.fields, ", ", fn f -> "#{f.label}: #{prim_rust(f.type)}" end)
            "    #{v.ctor} { #{fs} },"

          true ->
            fs = Enum.map_join(v.fields, ", ", &prim_rust(&1.type))
            "    #{v.ctor}(#{fs}),"
        end
      end)

    "#[derive(Clone, Debug, PartialEq)]\nenum #{t.name} {\n#{variants}\n}"
  end

  defp pat_rs(:wild, _), do: "_"
  defp pat_rs({:var, x}, _), do: x
  defp pat_rs({:lit, v}, _) when is_binary(v), do: inspect(v)
  defp pat_rs({:lit, v}, _), do: to_string(v)

  defp pat_rs({:ctor, name, []}, meta) do
    info = Map.fetch!(meta, PL.to_snake(name))
    "#{info.enum}::#{info.ctor}"
  end

  defp pat_rs({:ctor, name, args}, meta) do
    info = Map.fetch!(meta, PL.to_snake(name))

    if info.named do
      fields =
        info.labels
        |> Enum.zip(args)
        |> Enum.map_join(", ", fn {lbl, p} -> "#{lbl}: #{pat_rs(p, meta)}" end)

      "#{info.enum}::#{info.ctor} { #{fields} }"
    else
      "#{info.enum}::#{info.ctor}(#{Enum.map_join(args, ", ", &pat_rs(&1, meta))})"
    end
  end

  # ── Expression emission (precedence-aware, target-specific) ────────────
  @doc "Emit a single Rian expression string to :elixir or :rust."
  def emit_expr(src, target), do: emit(Rian.Pratt.parse(src), target) |> elem(0)

  @doc "Emit an already-built AST (e.g. after macro expansion / comptime folding)."
  def emit_ast(ast, target), do: emit(ast, target) |> elem(0)

  # emit/2 -> {string, prec}; p/3 wraps in parens when prec < ctx.
  defp p(node, ctx, t) do
    {s, pr} = emit(node, t)
    if pr < ctx, do: "(" <> s <> ")", else: s
  end

  defp emit({:num, n}, _t), do: {n, 12}
  # string literal — same surface on both targets (Rust yields `&str`)
  defp emit({:str, s}, _t), do: {"\"#{s}\"", 12}
  defp emit({:id, "pi"}, :elixir), do: {":math.pi()", 12}
  defp emit({:id, "pi"}, :rust), do: {"std::f64::consts::PI", 12}
  defp emit({:id, x}, _t), do: {x, 12}
  # atom literal / Erlang FFI (BEAM-only on Rust)
  defp emit({:atom, a}, :elixir), do: {":" <> a, 12}
  defp emit({:atom, a}, :rust), do: raise("Erlang atom is BEAM-only: :#{a}")
  defp emit({:dot, {:atom, m}, n}, :elixir), do: {":#{m}.#{n}", 12}
  defp emit({:dot, {:atom, m}, _}, :rust), do: raise("Erlang FFI is BEAM-only: :#{m}")

  # dotted access: Elixir uses `.` for both module calls and field access
  defp emit({:dot, head, n}, :elixir), do: {p(head, 12, :elixir) <> ".#{n}", 12}

  # Rust: case of head/name selects field vs module-path vs type/variant-path
  defp emit({:dot, {:id, m}, n}, :rust) do
    cond do
      # value.field
      not pascal?(m) -> {"#{m}.#{n}", 12}
      # Type::Variant
      pascal?(n) -> {"#{m}::#{n}", 12}
      # module::fn
      true -> {"#{String.downcase(m)}::#{n}", 12}
    end
  end

  defp emit({:dot, head, n}, :rust), do: {p(head, 12, :rust) <> "::#{n}", 12}

  defp emit({:call, f, args}, t),
    do: {p(f, 12, t) <> "(" <> Enum.map_join(args, ", ", &p(&1, 0, t)) <> ")", 12}

  # `&` captures (B'). Placeholders: Elixir's native `&N`, Rust's closure args `aN`.
  defp emit({:cap_arg, n}, :elixir), do: {"&#{n}", 12}
  defp emit({:cap_arg, n}, :rust), do: {"a#{n}", 12}

  # `&(&1 + &2)` — Elixir's native capture; Rust an explicit closure `|a1, a2| …`.
  defp emit({:capture, body}, :elixir), do: {"&(#{p(body, 0, :elixir)})", 12}

  defp emit({:capture, body}, :rust) do
    {"|#{closure_params(1, cap_arity(body))}| #{p(body, 0, :rust)}", 12}
  end

  # `&name/arity` — Elixir's native capture; Rust a forwarding closure.
  defp emit({:capture_named, path, arity}, :elixir),
    do: {"&#{p(path, 12, :elixir)}/#{arity}", 12}

  defp emit({:capture_named, path, arity}, :rust) do
    ps = closure_params(0, arity - 1)
    {"|#{ps}| #{p(path, 12, :rust)}(#{ps})", 12}
  end

  defp emit({:unary, "-", x}, t), do: {"-" <> p(x, 11, t), 11}
  defp emit({:unary, "not", x}, :elixir), do: {"not " <> p(x, 11, :elixir), 11}
  defp emit({:unary, "not", x}, :rust), do: {"!" <> p(x, 11, :rust), 11}

  # lambdas — Elixir anonymous fn, Rust closure
  defp emit({:lambda, params, body}, :elixir) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"fn #{ps} -> #{p(body, 0, :elixir)} end", 12}
  end

  defp emit({:lambda, params, body}, :rust) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"|#{ps}| #{p(body, 0, :rust)}", 12}
  end

  # if-expression
  defp emit({:if, c, t, e}, :elixir),
    do:
      {"if #{p(c, 0, :elixir)} do #{emit_block(t, :elixir)} else #{emit_block(e, :elixir)} end",
       0}

  defp emit({:if, c, t, e}, :rust),
    do: {"if #{p(c, 0, :rust)} { #{emit_block(t, :rust)} } else { #{emit_block(e, :rust)} }", 0}

  defp emit({:block, _} = b, t), do: {emit_block(b, t), 0}

  # case expression — Elixir `case … do … -> … end`; Rust `match … { … => …, }`
  defp emit({:case, scrut, arms}, :elixir) do
    body =
      Enum.map_join(arms, "; ", fn {pt, g, b} ->
        "#{pat_ex(pt)}#{case_guard(g, :elixir)} -> #{p(b, 0, :elixir)}"
      end)

    {"case #{p(scrut, 0, :elixir)} do #{body} end", 0}
  end

  defp emit({:case, scrut, arms}, :rust) do
    meta = Process.get({:rian, :meta}, %{})

    body =
      Enum.map_join(arms, " ", fn {pt, g, b} ->
        "#{pat_rs(pt, meta)}#{case_guard(g, :rust)} => #{p(b, 0, :rust)},"
      end)

    {"match #{p(scrut, 0, :rust)} { #{body} }", 0}
  end

  # list / map literals
  defp emit({:list_lit, elems, nil}, :elixir),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir))}]", 12}

  defp emit({:list_lit, elems, {:tail, tl}}, :elixir),
    do: {"[#{Enum.map_join(elems, ", ", &p(&1, 0, :elixir))} | #{p(tl, 0, :elixir)}]", 12}

  defp emit({:list_lit, elems, nil}, :rust),
    do: {"vec![#{Enum.map_join(elems, ", ", &p(&1, 0, :rust))}]", 12}

  defp emit({:list_lit, _, {:tail, _}}, :rust),
    do: raise("cons-list construction is BEAM-only (no idiomatic Vec cons)")

  defp emit({:map_lit, pairs}, :elixir),
    do: {"%{#{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{p(v, 0, :elixir)}" end)}}", 12}

  defp emit({:map_lit, _}, :rust), do: raise("map literals are BEAM-only in PoC")

  # pipe: native on Elixir, structural call on Rust
  defp emit({:bin, "|>", l, r}, :elixir),
    do: {p(l, prec("|>"), :elixir) <> " |> " <> p(r, prec("|>") + 1, :elixir), prec("|>")}

  defp emit({:bin, "|>", l, r}, :rust), do: emit(pipe_to_call(l, r), :rust)

  # concat: native <> on Elixir, flattened format! on Rust
  defp emit({:bin, "<>", l, r}, :elixir),
    do: {p(l, prec("<>") + 1, :elixir) <> " <> " <> p(r, prec("<>"), :elixir), prec("<>")}

  defp emit({:bin, "<>", _, _} = node, :rust) do
    parts = flatten_concat(node)
    fmt = String.duplicate("{}", length(parts))
    {"format!(\"#{fmt}\", #{Enum.map_join(parts, ", ", &p(&1, 0, :rust))})", 12}
  end

  # integer div / rem
  defp emit({:bin, "div", l, r}, :elixir),
    do: {"div(#{p(l, 0, :elixir)}, #{p(r, 0, :elixir)})", 12}

  defp emit({:bin, "rem", l, r}, :elixir),
    do: {"rem(#{p(l, 0, :elixir)}, #{p(r, 0, :elixir)})", 12}

  defp emit({:bin, "div", l, r}, :rust),
    do: {p(l, prec("div"), :rust) <> " / " <> p(r, prec("div") + 1, :rust), prec("div")}

  defp emit({:bin, "rem", l, r}, :rust),
    do: {p(l, prec("rem"), :rust) <> " % " <> p(r, prec("rem") + 1, :rust), prec("rem")}

  # float division: native on Elixir, explicit f64 cast on Rust
  defp emit({:bin, "/", l, r}, :elixir),
    do: {p(l, prec("/"), :elixir) <> " / " <> p(r, prec("/") + 1, :elixir), prec("/")}

  defp emit({:bin, "/", l, r}, :rust),
    do: {"(#{p(l, 0, :rust)} as f64) / (#{p(r, 0, :rust)} as f64)", 10}

  # generic binary (arith, comparison, and/or) — MUST be last
  defp emit({:bin, op, l, r}, t) do
    pr = prec(op)

    {lc, rc} =
      case assoc(op) do
        :left -> {pr, pr + 1}
        :right -> {pr + 1, pr}
        :none -> {pr + 1, pr + 1}
      end

    {p(l, lc, t) <> " " <> disp(op, t) <> " " <> p(r, rc, t), pr}
  end

  defp emit_block({:block, []}, :elixir), do: "nil"
  defp emit_block({:block, []}, :rust), do: "()"

  defp emit_block({:block, stmts}, :elixir) do
    Enum.map_join(stmts, "; ", fn
      {:bind, n, e} -> "#{n} = #{p(e, 0, :elixir)}"
      {:expr, e} -> p(e, 0, :elixir)
    end)
  end

  defp emit_block({:block, stmts}, :rust) do
    Enum.map_join(stmts, " ", fn
      {:bind, n, e} -> "let #{n} = #{p(e, 0, :rust)};"
      {:expr, e} -> p(e, 0, :rust)
    end)
  end

  defp pipe_to_call(l, {:call, f, args}), do: {:call, f, [l | args]}
  defp pipe_to_call(l, f), do: {:call, f, [l]}

  defp flatten_concat({:bin, "<>", l, r}), do: flatten_concat(l) ++ flatten_concat(r)
  defp flatten_concat(x), do: [x]

  defp disp("and", :rust), do: "&&"
  defp disp("or", :rust), do: "||"
  defp disp(op, _), do: op

  defp prec(op) do
    cond do
      op in ~w(* / rem div) -> 10
      op in ~w(+ -) -> 9
      op == "<>" -> 8
      op == "in" -> 7
      op == "|>" -> 6
      op in ~w(< <= > >=) -> 5
      op in ~w(== !=) -> 4
      op == "and" -> 3
      op == "or" -> 2
      op == "<-" -> 1
    end
  end

  defp assoc(op) do
    cond do
      op == "<>" or op == "<-" -> :right
      op in ~w(< <= > >= == != in) -> :none
      true -> :left
    end
  end

  # ── primitive type mapping ─────────────────────────────────────────────
  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  # Crystal source name -> Rust (owned form) / Elixir typespec (ADR-0033).
  defp prim_rust(t), do: Rian.Capability.owned(t)

  defp prim_ex("Bool"), do: "boolean()"
  defp prim_ex("String"), do: "String.t()"
  defp prim_ex("Symbol"), do: "atom()"
  defp prim_ex("Char"), do: "char()"

  defp prim_ex(t) do
    cond do
      Regex.match?(~r/^(Int|UInt)(8|16|32|64|128)$/, t) -> "integer()"
      Regex.match?(~r/^Float(32|64)$/, t) -> "float()"
      true -> "term()"
    end
  end
end
