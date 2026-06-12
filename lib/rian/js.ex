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
  unary/binary operators; `if`; local calls; tuples (→ JS arrays); `when`
  guards; **sum variants** — construction `Ctor(a, …)` → a tagged array
  `["Ctor", a, …]` (nullary → `["Ctor"]`), with **clause patterns** that check
  the tag and recurse into fields (nested + literal patterns supported);
  **lists** (→ JS arrays, cons `[h | t]` → `[h, ...t]`, with closed/cons clause
  patterns via `length`/`slice`); **`case`** (→ an IIFE if-chain over the arm
  patterns); **strings** (`<>` → `+`); **maps** (`%{k: v}` → a JS object); and a
  small set of **stdlib calls** the self-hosting spikes lean on, mapped to
  portable JS (`Map.get`/`Map.put` immutable, `String.to_charlist`,
  `List.to_string`, `:lists.reverse`) — a stopgap until the portable prelude
  (ADR-0047) owns them. **Not yet** (raise `Rian.JS.Unsupported`): struct
  construction/patterns, atoms/`Symbol`, `with`, lambdas/captures, general FFI.
  """
  alias Rian.{Core, Decl, Pratt}

  alias Rian.Core.{
    EAtom,
    EBin,
    EBlock,
    ECall,
    ECase,
    EDot,
    EId,
    EIf,
    EList,
    EMap,
    ENum,
    EStr,
    ETuple,
    EUnary,
    PCtor,
    PList,
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

  # `{ if (<structural tests>) { <binds> <guarded return> } }` — the binds live
  # *inside* the structural test so a nested field access (`a0[1][1]`) only runs
  # once the shape is known; a `when` guard, written in the bound names, follows.
  defp clause_js(%{pats: pats, body: body, guard: guard}) do
    {tests, binds} =
      pats
      |> Enum.map(&Core.from_pat/1)
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "a#{i}")
        {ts ++ t, bs ++ b}
      end)

    inner = bind_lines(binds) ++ [guarded_return(body, guard)]
    body_str = Enum.join(inner, " ")

    guarded =
      case tests do
        [] -> body_str
        _ -> "if (#{Enum.join(tests, " && ")}) { #{body_str} }"
      end

    "  { #{guarded} }"
  end

  defp guarded_return(body, nil), do: clause_return(body)

  defp guarded_return(body, g),
    do: "if (#{expr_js(Core.from_expr(Pratt.parse(g)))}) { #{clause_return(body)} }"

  # Match `pat` against the JS access path `acc` -> `{tests, binds}`. A sum
  # variant is a tagged array `["Ctor", arg0, …]` (ADR-0049), so a constructor
  # pattern checks the tag and recurses into each positional field.
  defp pat_match(%PWild{}, _acc), do: {[], []}
  defp pat_match(%PVar{name: n}, acc), do: {[], [{n, acc}]}
  defp pat_match(%PLit{value: v}, acc), do: {["#{acc} === #{lit_js(v)}"], []}

  defp pat_match(%PCtor{ctor: ctor, args: args}, acc) do
    {ts, bs} =
      args
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}[#{i + 1}]")
        {ts ++ t, bs ++ b}
      end)

    {["#{acc}[0] === #{inspect(ctor)}" | ts], bs}
  end

  # a list is a JS array; a closed pattern fixes the length, a cons pattern
  # `[h, … | tail]` requires at least the listed elements and binds the rest via
  # `slice`
  defp pat_match(%PList{elems: es, tail: :close}, acc) do
    {ts, bs} = match_elems(es, acc)
    {["#{acc}.length === #{length(es)}" | ts], bs}
  end

  defp pat_match(%PList{elems: es, tail: tail}, acc) do
    n = length(es)
    {ts, bs} = match_elems(es, acc)
    {tt, tb} = pat_match(tail, "#{acc}.slice(#{n})")
    {["#{acc}.length >= #{n}" | ts ++ tt], bs ++ tb}
  end

  defp pat_match(other, _acc),
    do: raise(Unsupported, "ecmascript: clause pattern #{inspect(other)}")

  defp match_elems(es, acc) do
    es
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
      {t, b} = pat_match(p, "#{acc}[#{i}]")
      {ts ++ t, bs ++ b}
    end)
  end

  defp bind_lines(binds), do: Enum.map(binds, fn {n, a} -> "const #{n} = #{a};" end)

  # one `case` arm against the bound scrutinee `_s`: `if (tests) { binds; return … }`
  defp case_arm_js({pat, guard, body}) do
    {tests, binds} = pat_match(pat, "_s")
    inner = Enum.join(bind_lines(binds) ++ [arm_return(body, guard)], " ")
    if tests == [], do: inner, else: "if (#{Enum.join(tests, " && ")}) { #{inner} }"
  end

  defp arm_return(body, nil), do: "return #{branch_js(body)};"
  defp arm_return(body, g), do: "if (#{expr_js(g)}) { return #{branch_js(body)}; }"

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
  # a Rian `String` is a JS string; `<>` concatenation is `+` (see js_op)
  defp expr_js(%EStr{value: s}), do: inspect(s)
  defp expr_js(%EId{name: b}) when b in ~w(true false), do: b

  # a bare PascalCase id is a nullary sum variant -> a one-element tagged array
  defp expr_js(%EId{name: x}) do
    if pascal?(x), do: "[#{inspect(x)}]", else: x
  end

  defp expr_js(%EUnary{op: "-", arg: x}), do: "-#{expr_js(x)}"
  defp expr_js(%EUnary{op: "not", arg: x}), do: "!#{expr_js(x)}"
  defp expr_js(%EBin{op: op, left: l, right: r}), do: "(#{expr_js(l)} #{js_op(op)} #{expr_js(r)})"
  defp expr_js(%ETuple{elems: es}), do: "[#{Enum.map_join(es, ", ", &expr_js/1)}]"

  # a list is a JS array; a cons tail spreads (`[h | t]` -> `[h, ...t]`)
  defp expr_js(%EList{elems: es, tail: :close}),
    do: "[#{Enum.map_join(es, ", ", &expr_js/1)}]"

  defp expr_js(%EList{elems: es, tail: tail}),
    do: "[#{Enum.join(Enum.map(es, &expr_js/1) ++ ["...#{expr_js(tail)}"], ", ")}]"

  # a map literal `%{k: v, …}` is a JS object (identifier keys -> string keys)
  defp expr_js(%EMap{pairs: pairs}),
    do: "{#{Enum.map_join(pairs, ", ", fn {k, v} -> "#{k}: #{expr_js(v)}" end)}}"

  # portable-prelude primitives (ADR-0047 §2): each backend lowers `__prim_*` to
  # its native collection op; the portable `Map`/`String` ops are written in Rian
  # over them. Here: JS objects.
  defp expr_js(%ECall{fun: %EId{name: "__prim_map_new"}, args: []}), do: "{}"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_get"}, args: [m, k]}),
    do: "#{paren(m)}[#{expr_js(k)}]"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_put"}, args: [m, k, v]}),
    do: "{...#{paren(m)}, [#{expr_js(k)}]: #{expr_js(v)}}"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_has"}, args: [m, k]}),
    do: "Object.hasOwn(#{paren(m)}, #{expr_js(k)})"

  # the handful of stdlib calls the self-hosting spikes use, mapped to portable
  # JS (a stopgap until the portable prelude, ADR-0047, owns these):
  #   Map.get/put (immutable), String.to_charlist, List.to_string, :lists.reverse
  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "get"}, args: [m, k]}),
    do: "#{paren(m)}[#{expr_js(k)}]"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "put"}, args: [m, k, v]}),
    do: "{...#{paren(m)}, [#{expr_js(k)}]: #{expr_js(v)}}"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "String"}, name: "to_charlist"}, args: [s]}),
    do: "[...#{paren(s)}].map(c => BigInt(c.codePointAt(0)))"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "List"}, name: "to_string"}, args: [xs]}),
    do: "#{paren(xs)}.map(c => String.fromCodePoint(Number(c))).join(\"\")"

  defp expr_js(%ECall{fun: %EDot{head: %EAtom{name: "lists"}, name: "reverse"}, args: [xs]}),
    do: "#{paren(xs)}.slice().reverse()"

  # `case scrut do pat -> body … end` -> an IIFE: bind the scrutinee, then an
  # if-chain of `pat_match` tests; the first matching arm `return`s its body
  defp expr_js(%ECase{scrut: scrut, arms: arms}) do
    arms_js = Enum.map_join(arms, " ", &case_arm_js/1)

    "(() => { const _s = #{expr_js(scrut)}; #{arms_js} throw new Error(\"case: no clause matched\"); })()"
  end

  # a PascalCase call is sum-variant construction -> a tagged array
  # `["Ctor", arg0, …]`; a lowercase call is a function call
  defp expr_js(%ECall{fun: %EId{name: f}, args: args}) do
    if pascal?(f) do
      "[#{Enum.join([inspect(f) | Enum.map(args, &expr_js/1)], ", ")}]"
    else
      "#{f}(#{Enum.map_join(args, ", ", &expr_js/1)})"
    end
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
  defp js_op("<>"), do: "+"
  defp js_op("div"), do: "/"
  defp js_op("rem"), do: "%"
  defp js_op(op), do: raise(Unsupported, "ecmascript: operator `#{op}`")

  # parenthesise an operand of a postfix `[…]` / `.method()` so precedence holds
  defp paren(e), do: "(#{expr_js(e)})"

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)
end
