defmodule Rian.JS do
  @moduledoc """
  ECMAScript emitter (ADR-0049 Tier 1) — a **direct** JS source emitter built on
  the **typed core IR** (`Rian.Core`, ADR-0050): it consumes `Core.from_expr` /
  `Core.from_pat`, never the surface tuples. Being a fresh emitter on the core is
  the ADR-0050 thesis in practice — a third backend without a fourth fork.

  JS has no native multi-clause pattern matching, so a multi-clause function
  lowers to a **dispatcher**: positional params `a0, a1, …`, one guarded block
  per clause that binds the clause's variables and `return`s its body, falling
  through to the next clause, ending in a `throw` (no clause matched).

  `Int64` lowers to **`BigInt`** (ADR-0049 §3): integer literals are `42n` and
  integer arithmetic stays in BigInt.

  ## Scope (this increment)

  Functions (single/multi-clause) over `Int64`/`Float64`/`Bool`; variables;
  unary/binary operators; `if`; literal/var/wildcard clause patterns; `when`
  guards; local calls; tuples (→ JS arrays). **Not yet** (raise
  `Rian.JS.Unsupported`): sum-variant / struct construction + their patterns,
  atoms/`Symbol`, lists, `case`/`with`, lambdas/captures, strings, FFI.
  """
  alias Rian.{Core, Decl, Pratt}

  alias Rian.Core.{
    EBin,
    EBlock,
    ECall,
    EId,
    EIf,
    ENum,
    ETuple,
    EUnary,
    PLit,
    PVar,
    PWild
  }

  defmodule Unsupported do
    defexception [:message]
  end

  @doc "Compile `src`'s functions to a single ECMAScript module (a string)."
  def compile(src) do
    prog = Decl.parse(src)
    funcs = funcs_of(prog)
    Enum.map_join(funcs, "\n\n", &function_js/1)
  end

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  # ── function / clause dispatch ──────────────────────────────────────────
  defp function_js(%{name: name, clauses: clauses, pub?: pub?}) do
    arity = length(hd(clauses).pats)
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    body = Enum.map_join(clauses, "\n", &clause_js/1)
    export = if pub?, do: "export ", else: ""

    "#{export}function #{name}(#{params}) {\n#{body}\n  throw new Error(\"#{name}: no clause matched\");\n}"
  end

  # `{ <binds>  <guarded return> }` — bindings precede the test so a `when` guard
  # (written in the pattern's variable names) can reference them
  defp clause_js(%{pats: pats, body: body, guard: guard}) do
    core_pats = Enum.map(pats, &Core.from_pat/1)
    binds = bind_lines(pats_binds(core_pats))
    tests = pats_tests(core_pats) ++ guard_tests(guard)
    ret = clause_return(body)

    guarded =
      case tests do
        [] -> ret
        _ -> "if (#{Enum.join(tests, " && ")}) { #{ret} }"
      end

    "  { #{Enum.join(binds ++ [guarded], " ")} }"
  end

  # var pattern at arg i -> {name, "ai"}; literal/wild contribute no binding
  defp pats_binds(core_pats) do
    core_pats
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%PVar{name: n}, i} -> [{n, "a#{i}"}]
      {_, _} -> []
    end)
  end

  defp bind_lines(binds), do: Enum.map(binds, fn {n, a} -> "const #{n} = #{a};" end)

  defp pats_tests(core_pats) do
    core_pats
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%PLit{value: v}, i} -> ["a#{i} === #{lit_js(v)}"]
      {%PWild{}, _} -> []
      {%PVar{}, _} -> []
      {other, _} -> raise(Unsupported, "ecmascript: clause pattern #{inspect(other)}")
    end)
  end

  defp guard_tests(nil), do: []
  defp guard_tests(g), do: ["(#{expr_js(Core.from_expr(Pratt.parse(g)))})"]

  # a clause body parses to a block: emit `let`s then `return` the final value
  defp clause_return(src) do
    %EBlock{stmts: stmts} = Core.from_expr(Pratt.parse_body(src))
    block_return(stmts)
  end

  defp block_return([{:expr, e}]), do: "return #{expr_js(e)};"

  defp block_return(stmts) do
    {init, [last]} = Enum.split(stmts, -1)
    lets = Enum.map_join(init, " ", &stmt_js/1)
    "#{lets} #{stmt_return(last)}"
  end

  defp stmt_js({:bind, n, e}), do: "let #{n} = #{expr_js(e)};"
  defp stmt_js({:expr, e}), do: "#{expr_js(e)};"
  defp stmt_return({:expr, e}), do: "return #{expr_js(e)};"
  defp stmt_return({:bind, _, e}), do: "return #{expr_js(e)};"

  # ── expression emission ─────────────────────────────────────────────────
  defp expr_js(%ENum{text: n}), do: num_js(n)
  defp expr_js(%EId{name: b}) when b in ~w(true false), do: b

  defp expr_js(%EId{name: x}) do
    if pascal?(x),
      do: raise(Unsupported, "ecmascript: variant/struct construction `#{x}`"),
      else: x
  end

  defp expr_js(%EUnary{op: "-", arg: x}), do: "-#{expr_js(x)}"
  defp expr_js(%EUnary{op: "not", arg: x}), do: "!#{expr_js(x)}"
  defp expr_js(%EBin{op: op, left: l, right: r}), do: "(#{expr_js(l)} #{js_op(op)} #{expr_js(r)})"
  defp expr_js(%ETuple{elems: es}), do: "[#{Enum.map_join(es, ", ", &expr_js/1)}]"

  defp expr_js(%ECall{fun: %EId{name: f}, args: args}) do
    if pascal?(f), do: raise(Unsupported, "ecmascript: variant/struct construction `#{f}`")
    "#{f}(#{Enum.map_join(args, ", ", &expr_js/1)})"
  end

  defp expr_js(%EIf{cond: c, then: t, else: e}),
    do: "(#{expr_js(c)} ? #{branch_js(t)} : #{branch_js(e)})"

  defp expr_js(other), do: raise(Unsupported, "ecmascript: expression #{inspect(other)}")

  # an `if` branch is a block; a single-expression block is an expression, a
  # multi-statement block an IIFE
  defp branch_js(%EBlock{stmts: [{:expr, e}]}), do: expr_js(e)
  defp branch_js(%EBlock{stmts: []}), do: "undefined"
  defp branch_js(%EBlock{stmts: stmts}), do: "(() => { #{block_return(stmts)} })()"
  defp branch_js(expr), do: expr_js(expr)

  # ── helpers ─────────────────────────────────────────────────────────────
  # Int64 -> BigInt literal (`42n`); a Float64 literal is a plain JS number
  defp num_js(n), do: if(float?(n), do: n, else: "#{n}n")
  defp lit_js(v) when is_integer(v), do: "#{v}n"
  defp lit_js(v) when is_binary(v), do: inspect(v)

  defp float?(n), do: String.contains?(n, ".") or String.match?(n, ~r/[eE]/)

  defp js_op("=="), do: "==="
  defp js_op("!="), do: "!=="
  defp js_op("and"), do: "&&"
  defp js_op("or"), do: "||"
  defp js_op(op) when op in ~w(+ - * < <= > >= %), do: op
  defp js_op("div"), do: "/"
  defp js_op("rem"), do: "%"
  defp js_op(op), do: raise(Unsupported, "ecmascript: operator `#{op}`")

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)
end
