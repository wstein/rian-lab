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
  integer arithmetic stays in BigInt. **`Int53`** — the ECMAScript-safe integer
  (a native JS `number` is exact only to 2^53) — instead uses native numbers
  (`42`, no suffix). The mode is **per-function**: a function whose signature is
  typed `Int53` emits *all* its integer literals natively, so within one function
  body BigInt and number never mix (an `Int53` function is uniformly native, an
  `Int64` one uniformly BigInt).

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
  (ADR-0047) owns them. **Protocol dispatch** (ADR-0061 §3): a `protocol` lowers
  to a JS dispatcher generated from the protocol IR — it selects the impl by the
  first argument's runtime shape (`typeof` for primitives, the tagged-array head
  for sums), mirroring the BEAM strategy with JS-native guards; the `impl_*`
  methods lower as plain functions, and bounded generics are plain functions
  (the bound was checked statically and is erased). **Not yet** (raise
  `Rian.JS.Unsupported`): struct construction/patterns and struct protocol
  dispatch, atoms/`Symbol`, `with`, lambdas/captures, general FFI.
  """
  alias Rian.{Core, Decl, Pratt}

  alias Rian.Core.{
    EAtom,
    EBin,
    EBlock,
    ECall,
    ECase,
    EChar,
    EDot,
    EId,
    EIf,
    EList,
    EMap,
    ENum,
    EStr,
    ETuple,
    EUnary,
    PChar,
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
    # the BEAM `:dispatcher` is a guarded runtime type-test — not the JS shape.
    # JS keeps the `:impl` methods (they lower as plain functions) and regenerates
    # the dispatcher with JS-native guards (ADR-0061 §3).
    funcs = prog |> funcs_of() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    fn_js = Enum.map_join(funcs, "\n\n", &function_js/1)
    disp_js = protocol_dispatchers_js(prog)

    [fn_js, disp_js] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  # ── protocol dispatch (ADR-0061 §3): a JS dispatcher per protocol method ──
  # mirrors the BEAM strategy — select the impl by the first argument's runtime
  # shape — but with JS-native guards (`typeof`, tagged-array head).
  defp protocol_dispatchers_js(prog) do
    sum_ctors = sum_ctor_map(prog)
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    for p <- protocols, m <- p.methods, reduce: [] do
      acc ->
        impl_types = for i <- impl_decls, i.proto == p.name, do: i.type

        case impl_types do
          [] -> acc
          types -> [dispatcher_js(p.name, m, types, sum_ctors) | acc]
        end
    end
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp dispatcher_js(proto, method, impl_types, sum_ctors) do
    arity = method.params |> split_top_commas() |> length()
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    args = params

    clauses =
      Enum.map_join(impl_types, "\n", fn type ->
        "  if (#{js_guard!(type, proto, sum_ctors)}) return #{mangle(proto, type, method.name)}(#{args});"
      end)

    "export function #{method.name}(#{params}) {\n#{clauses}\n  throw new Error(\"#{method.name}: no protocol impl\");\n}"
  end

  defp mangle(proto, type, method),
    do: "impl_#{String.downcase(proto)}_#{String.downcase(type)}_#{method}"

  # JS guard selecting the impl for `type` by the first argument's runtime shape.
  defp js_guard!(type, proto, sum_ctors) do
    cond do
      type == "Bool" ->
        ~s(typeof a0 === "boolean")

      type == "String" ->
        ~s(typeof a0 === "string")

      type == "Char" ->
        ~s(typeof a0 === "bigint")

      String.match?(type, ~r/^U?Int\d*$/) ->
        ~s(typeof a0 === "bigint")

      String.match?(type, ~r/^Float\d*$/) ->
        ~s(typeof a0 === "number")

      ctors = sum_ctors[type] ->
        sum_guard_js(ctors)

      true ->
        raise(
          Unsupported,
          "JS protocol dispatch for `impl #{proto} for #{type}` (only primitive and sum types are supported on JS; restrict the module with `@targets`)"
        )
    end
  end

  # a sum value is a tagged array `["Ctor", …]` (this module's representation)
  defp sum_guard_js(ctors) do
    tags = Enum.map_join(ctors, " || ", &~s(a0[0] === "#{&1}"))
    "Array.isArray(a0) && (#{tags})"
  end

  # split a parameter string on top-level commas (respecting nested `(`/`)`), to
  # count a protocol method's arity (`a Self, b Vec(T)` -> 2)
  defp split_top_commas(""), do: []

  defp split_top_commas(s) do
    {parts, cur, _} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ",", {ps, cur, 0} -> {[cur | ps], "", 0}
        "(", {ps, cur, d} -> {ps, cur <> "(", d + 1}
        ")", {ps, cur, d} -> {ps, cur <> ")", d - 1}
        ch, {ps, cur, d} -> {ps, cur <> ch, d}
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp sum_ctor_map(prog) do
    types =
      Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)

    Map.new(types, fn t -> {t.name, Enum.map(t.variants, & &1.ctor)} end)
  end

  # ── function / clause dispatch ──────────────────────────────────────────
  defp function_js(%{name: name, clauses: clauses, pub?: pub?} = f) do
    arity = length(hd(clauses).pats)
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    # `Int64` lowers to BigInt (64-bit safe); a function typed `Int53` instead
    # uses native JS numbers (exact to 2^53). The mode is per-function, so a body
    # is uniformly native or BigInt and the two never mix. Carried via the process
    # dict (a single sequential emitter pass).
    Process.put(:rian_js_int53, int53_fn?(f))
    body = Enum.map_join(clauses, "\n", &clause_js/1)
    export = if pub?, do: "export ", else: ""

    "#{export}function #{name}(#{params}) {\n#{body}\n  throw new Error(\"#{name}: no clause matched\");\n}"
  end

  # a function is "Int53-mode" if its signature mentions `Int53` (param or return)
  defp int53_fn?(%{params: params, ret: ret}),
    do: ret == "Int53" or Enum.any?(params, &(&1.type == "Int53"))

  defp int53_fn?(_), do: false

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
  # a `Char` is its codepoint as a BigInt — `__prim_str_chars` yields BigInt codepoints
  defp pat_match(%PChar{value: cp}, acc), do: {["#{acc} === #{cp}n"], []}

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
  # the declared type is erased at lowering (ADR-0034 §1); the value is unchanged.
  defp stmt_js({:typed_bind, n, _t, e}), do: stmt_js({:bind, n, e})
  defp stmt_js({:expr, e}), do: "#{expr_js(e)};"
  defp stmt_return({:expr, e}), do: "return #{expr_js(e)};"
  defp stmt_return({:bind, _, e}), do: "return #{expr_js(e)};"
  defp stmt_return({:typed_bind, _, _, e}), do: "return #{expr_js(e)};"

  # ── expression emission ─────────────────────────────────────────────────
  defp expr_js(%ENum{text: n}), do: num_js(n)
  # a `Char` is its codepoint as a BigInt — matches `__prim_str_chars`'s codepoints
  defp expr_js(%EChar{value: cp}), do: "#{cp}n"
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

  # `String` primitives — codepoints are BigInt (Int64); concat is `+`
  defp expr_js(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}),
    do: "[...#{paren(s)}].map(c => BigInt(c.codePointAt(0)))"

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}),
    do: "#{paren(cs)}.map(c => String.fromCodePoint(Number(c))).join(\"\")"

  # a `Char`'s codepoint — identity in JS, where a `Char` is a BigInt codepoint
  defp expr_js(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}), do: expr_js(c)

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}),
    do: "(#{expr_js(a)} + #{expr_js(b)})"

  # explicit overflow ops (ADR-0035 §3) — Int64 is a BigInt in JS (arbitrary
  # precision, like the BEAM bignum), so each op projects the true sum onto the
  # signed 64-bit range: `BigInt.asIntN` wraps, an arrow clamps/checks once.
  defp expr_js(%ECall{fun: %EId{name: "__prim_wrapping_add"}, args: [a, b]}),
    do: "BigInt.asIntN(64, #{expr_js(a)} + #{expr_js(b)})"

  defp expr_js(%ECall{fun: %EId{name: "__prim_saturating_add"}, args: [a, b]}),
    do:
      "(s => s > 9223372036854775807n ? 9223372036854775807n : " <>
        "(s < -9223372036854775808n ? -9223372036854775808n : s))(#{expr_js(a)} + #{expr_js(b)})"

  # `checked_add` -> `Option(Int64)`, the JS tagged array `["Some", s]` / `["None"]`
  defp expr_js(%ECall{fun: %EId{name: "__prim_checked_add"}, args: [a, b]}),
    do:
      "(s => (s >= -9223372036854775808n && s <= 9223372036854775807n) ? " <>
        "[\"Some\", s] : [\"None\"])(#{expr_js(a)} + #{expr_js(b)})"

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
  # Int64 -> BigInt literal (`42n`); a Float64 literal is a plain JS number; in an
  # `Int53` function, an integer literal is a plain (native) JS number too
  defp num_js(n) do
    cond do
      float?(n) -> n
      Process.get(:rian_js_int53, false) -> n
      true -> "#{n}n"
    end
  end

  defp lit_js(v) when is_integer(v),
    do: if(Process.get(:rian_js_int53, false), do: "#{v}", else: "#{v}n")

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
