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

      func = %{name: "area", param_name: "shape", param_type: "Shape", ret: "f64",
               clauses: [%{pats: [{:ctor, "Circle", [{:var, "r"}]}], body: "pi * r * r"},
                         %{pats: [{:ctor, "Square", [{:var, "s"}]}], body: "s * s"}]}
  """
  alias Rian.Exhaustiveness, as: E
  alias Rian.PatternLower, as: PL
  alias Rian.Pratt

  # Tag thrown by the `?` propagation desugar on the BEAM, caught by the
  # enclosing function/lambda wrapper. Unique — Rian expressions have no string
  # literals, so this cannot collide with user data.
  @propagate_tag "__rian_q__"

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
        PL.lower_clause(%{pats: c.pats, guard: Map.get(c, :guard, false)}, env)
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
    Rian.Capability.beam_legal!(Map.get(func, :param_cap, :val))
    typespecs = Enum.map_join(types, "\n", &ex_typespec/1)

    clauses =
      Enum.map_join(func.clauses, "\n", fn c ->
        head = "def #{func.name}(#{Enum.map_join(c.pats, ", ", &pat_ex/1)})"
        ast = Pratt.parse(c.body)
        "#{head} do #{maybe_wrap(emit(ast, :elixir) |> elem(0), ast)} end"
      end)

    typespecs <> "\n" <> clauses
  end

  # `?`-propagation wrapping (Elixir only): if a function/lambda body uses `?`,
  # wrap its emitted body in a `try` that catches the propagation throw and
  # returns the short-circuit value. `has_try?` treats a lambda as a scope
  # boundary, so each function/closure catches its own `?` — mirroring Rust,
  # where `?` propagates from the nearest enclosing `fn`/closure.
  defp maybe_wrap(str, ast), do: if(has_try?(ast), do: wrap_propagate(str), else: str)

  defp wrap_propagate(body), do: "try do #{body} catch {:#{@propagate_tag}, rian_v} -> rian_v end"

  defp has_try?({:try, _}), do: true
  defp has_try?({:bin, _, l, r}), do: has_try?(l) or has_try?(r)
  defp has_try?({:unary, _, x}), do: has_try?(x)
  defp has_try?({:call, f, args}), do: has_try?(f) or Enum.any?(args, &has_try?/1)
  defp has_try?({:dot, o, _}), do: has_try?(o)
  defp has_try?({:if, c, t, e}), do: has_try?(c) or has_try?(t) or has_try?(e)

  defp has_try?({:block, stmts}) do
    Enum.any?(stmts, fn
      {:bind, _, e} -> has_try?(e)
      {:expr, e} -> has_try?(e)
    end)
  end

  defp has_try?({:list_lit, es, tail}),
    do: Enum.any?(es, &has_try?/1) or (match?({:tail, _}, tail) and has_try?(elem(tail, 1)))

  defp has_try?({:map_lit, ps}), do: Enum.any?(ps, fn {_, v} -> has_try?(v) end)
  # a lambda is a propagation boundary — it wraps its own `?` when emitted
  defp has_try?({:lambda, _, _}), do: false
  defp has_try?(_), do: false

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
    enums = Enum.map_join(types, "\n\n", &rust_enum/1)
    scrut = func.param_name
    cap = Map.get(func, :param_cap, :val)
    scrut_type = Rian.Capability.rust_param(cap, func.param_type)

    arms =
      Enum.map_join(func.clauses, "\n", fn c ->
        pat = c.pats |> hd() |> pat_rs(meta)
        "        #{pat} => #{emit(Pratt.parse(c.body), :rust) |> elem(0)},"
      end)

    fn_str =
      "fn #{func.name}(#{scrut}: #{scrut_type}) -> #{prim_rust(func.ret)} {\n" <>
        "    match #{scrut} {\n#{arms}\n    }\n}"

    enums <> "\n\n" <> fn_str
  end

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

  # `?` — error/Option propagation. Rust: idiomatic postfix `e?`. Elixir:
  # `Rian.Q.unwrap/1` (unwrap-or-throw), caught by the enclosing function/lambda
  # `try` wrapper (added by `maybe_wrap/2`), so propagation targets the nearest
  # enclosing function-or-closure on BOTH targets.
  defp emit({:try, x}, :rust), do: {p(x, 12, :rust) <> "?", 12}
  defp emit({:try, x}, :elixir), do: {"Rian.Q.unwrap(#{p(x, 0, :elixir)})", 12}

  defp emit({:unary, "-", x}, t), do: {"-" <> p(x, 11, t), 11}
  defp emit({:unary, "not", x}, :elixir), do: {"not " <> p(x, 11, :elixir), 11}
  defp emit({:unary, "not", x}, :rust), do: {"!" <> p(x, 11, :rust), 11}

  # lambdas — Elixir anonymous fn, Rust closure
  defp emit({:lambda, params, body}, :elixir) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    {"fn #{ps} -> #{maybe_wrap(p(body, 0, :elixir), body)} end", 12}
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

  defp prim_rust(t), do: t
  defp prim_ex("f64"), do: "float()"
  defp prim_ex("f32"), do: "float()"
  defp prim_ex("bool"), do: "boolean()"
  defp prim_ex("str"), do: "String.t()"
  defp prim_ex(t), do: if(String.starts_with?(t, ["i", "u"]), do: "integer()", else: "term()")
end
