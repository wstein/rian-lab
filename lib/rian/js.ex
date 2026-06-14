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

  ## Integer types on JS (ADR-0064)

  JS has exactly two integer carriers, so only three Rian integer types are
  JS-valid:

    * **`Int`** (arbitrary precision, the default) → **`BigInt`**: literals `42n`,
      arithmetic stays in BigInt.
    * **`Int53`** (the portable fixed-width ceiling) and **`Int32`/smaller** →
      native JS **`number`** (`42`, no suffix), exact within 2^53.

  **`Int64`/`Int128`/`UInt64`/`UInt128` are *not* supported on JS** — a `number`
  can't hold them and we refuse to silently elevate them to `BigInt` (which would
  widen a bounded type to arbitrary precision). A function whose signature names one
  is **rejected** (`reject_wide_int!`); `Rian.Reach` pins it off `:js` so the gate
  catches it first. The number/BigInt mode is **per-function**: a body is uniformly
  native (`Int53`/`Int32`) or uniformly BigInt (`Int`), the two never mix.

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
  (the bound was checked statically and is erased). **Structs**: named
  construction `Name(f: v, …)` → a `__struct__`-tagged object `{__struct__:
  "Name", f: v}`, with field access `p.f` and struct clause patterns; struct
  protocol dispatch tests `a0.__struct__ === "Name"`. **Not yet** (raise
  `Rian.JS.Unsupported`): atoms/`Symbol`, `with`, lambdas/captures, general FFI.

  ## Capabilities

  The portable core is `val`/`iso`/`tag`; `ref` (`&mut`) has no JS analog. It is
  **intentionally lowered to value semantics** — a `ref` param emits an ordinary
  positional binding, which is *sound today* because the Rian surface is
  return-based (no in-place mutation operator), so `ref` only ever changed the Rust
  signature. If a future in-place-mutation primitive is added, this assumption
  breaks and `ref` would need real handling here — `test/rian/js_test.exs` locks the
  current value-lowering so that change can't pass silently.
  """
  alias Rian.{Check, Core, Decl, Pratt}

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
    EStruct,
    ELabel,
    ETuple,
    EUnary,
    PChar,
    PCtor,
    PList,
    PLit,
    PStruct,
    PVar,
    PWild
  }

  defmodule Unsupported do
    defexception [:message]
  end

  @doc "Compile `src`'s functions to a single ECMAScript module (a string)."
  def compile(src) do
    prog = Decl.parse(src)
    # Run the full type gate first — parity with the BEAM path (`Decl.compile`),
    # which gates before emitting. Without this a real `Rian.Check` error stayed
    # latent on the JS path (commit 80f6929). A type error is now caught here, not
    # discovered as malformed JS downstream.
    :ok = Check.gate!(prog)
    # Integer mode is a WHOLE-PROGRAM decision, not per-function: integer values
    # (a depth counter, a codepoint) flow across function boundaries, and BigInt
    # and number cannot be combined in JS. A "neutral" function with no integer in
    # its own signature would otherwise default to BigInt and pass `0n` into a
    # number-mode callee. So if the program uses a JS-number width (`Int53`/`Int32`)
    # anywhere, the entire module emits in number-mode (ADR-0064).
    reject_mixed_int_mode!(prog)
    Process.put(:rian_js_int53, program_number_mode?(prog))
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
    reg = %{sums: sum_ctor_map(prog), structs: struct_name_set(prog)}
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    for p <- protocols, m <- p.methods, reduce: [] do
      acc ->
        impl_types = for i <- impl_decls, i.proto == p.name, do: i.type

        case impl_types do
          [] -> acc
          types -> [dispatcher_js(p.name, m, types, reg) | acc]
        end
    end
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp dispatcher_js(proto, method, impl_types, reg) do
    arity = method.params |> split_top_commas() |> length()
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    args = params

    clauses =
      Enum.map_join(impl_types, "\n", fn type ->
        "  if (#{js_guard!(type, proto, reg)}) return #{mangle(proto, type, method.name)}(#{args});"
      end)

    "export function #{method.name}(#{params}) {\n#{clauses}\n  throw new Error(\"#{method.name}: no protocol impl\");\n}"
  end

  defp mangle(proto, type, method),
    do: "impl_#{String.downcase(proto)}_#{String.downcase(type)}_#{method}"

  # JS guard selecting the impl for `type` by the first argument's runtime shape.
  defp js_guard!(type, proto, reg) do
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

      ctors = reg.sums[type] ->
        sum_guard_js(ctors)

      MapSet.member?(reg.structs, type) ->
        ~s(typeof a0 === "object" && a0 !== null && a0.__struct__ === #{inspect(type)})

      true ->
        raise(
          Unsupported,
          "JS protocol dispatch for `impl #{proto} for #{type}` (no runtime discriminator for `#{type}`; restrict the module with `@targets`)"
        )
    end
  end

  defp struct_name_set(prog) do
    structs =
      Map.get(prog, :structs, []) ++ for(m <- Map.get(prog, :mods, []), s <- m.structs, do: s)

    MapSet.new(structs, & &1.name)
  end

  # a sum value is a tagged array `["Ctor", …]` (this module's representation)
  defp sum_guard_js(ctors) do
    tags = Enum.map_join(ctors, " || ", &~s(a0[0] === "#{&1}"))
    "Array.isArray(a0) && (#{tags})"
  end

  # split a parameter string on top-level commas (respecting nested `(`/`)`), to
  # count a protocol method's arity (`a Self, b Vec(T)` -> 2)
  defp split_top_commas(s), do: Rian.TypeStr.split_top_commas(s)

  defp sum_ctor_map(prog) do
    types =
      Map.get(prog, :types, []) ++ for(m <- Map.get(prog, :mods, []), t <- m.types, do: t)

    Map.new(types, fn t -> {t.name, Enum.map(t.variants, & &1.ctor)} end)
  end

  # ── function / clause dispatch ──────────────────────────────────────────
  defp function_js(%{name: name, clauses: clauses, pub?: pub?} = f) do
    reject_wide_int!(name, f)
    arity = length(hd(clauses).pats)
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    # integer mode (`:rian_js_int53`) is set once, program-wide, in `compile/1`.
    # Wide fixed-width (`Int64`+) is rejected above, never silently elevated.
    body = Enum.map_join(clauses, "\n", &clause_js/1)
    export = if pub?, do: "export ", else: ""

    "#{export}function #{name}(#{params}) {\n#{body}\n  throw new Error(\"#{name}: no clause matched\");\n}"
  end

  # The program is in number-mode if any function signature mentions a JS-native
  # integer width — `Int53` or `Int32`/smaller — anywhere, *including nested* in
  # `Vec(Int53)`/`Map(Int53,…)`. (`Int`, arbitrary precision, never matches, so
  # BigInt stays the default; the two are not mixed within one program, ADR-0064.)
  @js_number_int ~r/\b(Int53|(Int|UInt)(8|16|32))\b/

  # the 64-bit-overflow prims this emitter refuses (ADR-0064 §2a); canonical in
  # `Rian.Prim` so the list here and `Rian.Reach`'s `:js` blocker never drift.
  @overflow_prims Rian.Prim.overflow_ops()

  defp program_number_mode?(prog) do
    funcs = Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

    Enum.any?(funcs, fn f ->
      Enum.any?([f.ret | Enum.map(f.params, & &1.type)], &js_number_int?/1)
    end)
  end

  defp js_number_int?(t), do: is_binary(t) and Regex.match?(@js_number_int, t)

  # `Int` (arbitrary precision -> BigInt) and a fixed-width JS-number type
  # (`Int53`/`Int32`/smaller) cannot coexist in one JS module: BigInt and number
  # never mix in a JS expression, and the whole-program number-mode would silently
  # demote `Int` to a bounded `number` — exactly the precision change ADR-0064
  # forbids. Refuse the mix loudly rather than miscompile. (`\bInt\b` matches bare
  # `Int` only — not `Int53`/`Int64`/`UInt8`.)
  @js_bigint_int ~r/\bInt\b/
  defp reject_mixed_int_mode!(prog) do
    sig_types =
      (Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs))
      |> Enum.flat_map(fn f -> [f.ret | Enum.map(f.params, & &1.type)] end)
      |> Enum.filter(&is_binary/1)

    if Enum.any?(sig_types, &Regex.match?(@js_number_int, &1)) and
         Enum.any?(sig_types, &Regex.match?(@js_bigint_int, &1)) do
      raise(
        Unsupported,
        "ecmascript: a module cannot mix `Int` (arbitrary precision -> BigInt) with a " <>
          "fixed-width JS-number type (`Int53`/`Int32`) — BigInt and `number` are incompatible " <>
          "in JS, and number-mode would silently truncate `Int` (ADR-0064 §2a). " <>
          "Split them into separate modules or pick one integer representation."
      )
    end
  end

  # Wide fixed-width integers (`Int64/128`, `UInt64/128`) exceed the JS safe-integer
  # range and have no faithful `number` representation; we refuse to silently
  # elevate them to `BigInt` (which would widen a bounded type to arbitrary
  # precision, the opposite of its contract). Use `Int` (arbitrary precision) or
  # `Int53` (portable fixed-width) for JS-reachable code (ADR-0064; `Rian.Reach`
  # pins these off `:js`).
  @js_wide_int ~r/^(Int|UInt)(64|128)$/
  defp reject_wide_int!(name, %{params: params, ret: ret}) do
    types = Enum.map(params, & &1.type) ++ [ret]

    case Enum.find(types, &(is_binary(&1) and Regex.match?(@js_wide_int, &1))) do
      nil ->
        :ok

      t ->
        raise Unsupported,
              "`#{name}`: fixed-width integer `#{t}` is not supported on JS — it " <>
                "exceeds the 2^53 safe-integer range and is never elevated to BigInt. " <>
                "Use `Int` (arbitrary precision) or `Int53` (portable fixed-width, ADR-0064)."
    end
  end

  defp reject_wide_int!(_name, _f), do: :ok

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
  # a `Char` is its codepoint integer, in the function's integer mode (number or
  # BigInt) so it never mixes with the surrounding codepoints
  defp pat_match(%PChar{value: cp}, acc), do: {["#{acc} === #{cp_lit(cp)}"], []}

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

  # a struct is a JS object `{__struct__: "Name", field: …}`; the pattern checks
  # the tag and binds each named field by property access.
  defp pat_match(%PStruct{name: name, fields: fields}, acc) do
    {ts, bs} =
      Enum.reduce(fields, {[], []}, fn {f, p}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}.#{f}")
        {ts ++ t, bs ++ b}
      end)

    {["#{acc}.__struct__ === #{inspect(to_string(name))}" | ts], bs}
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
  # a `Char` is its codepoint integer, in the function's integer mode
  defp expr_js(%EChar{value: cp}), do: cp_lit(cp)
  # a Rian `String` is a JS string; `<>` concatenation is `+` (see js_op)
  defp expr_js(%EStr{value: s}), do: inspect(s)
  defp expr_js(%EId{name: b}) when b in ~w(true false), do: b

  # a bare PascalCase id is a nullary sum variant -> a one-element tagged array
  defp expr_js(%EId{name: x}) do
    if pascal?(x), do: "[#{inspect(x)}]", else: x
  end

  defp expr_js(%EUnary{op: "-", arg: x}), do: "-#{expr_js(x)}"
  defp expr_js(%EUnary{op: "not", arg: x}), do: "!#{expr_js(x)}"

  # ECMAScript has no integer-division operator: `/` is IEEE-754 float division
  # (a `Number`). So a Rian `div` (integer division, truncate-toward-zero) cannot
  # lower to a bare `/` in number-mode — `5 div 2` would be `2.5`, not `2`. Truncate
  # explicitly. In BigInt-mode `/` is already integer division (truncates toward
  # zero, matching `div`), so it stands as-is (ADR-0049 §JS-numerics).
  defp expr_js(%EBin{op: "div", left: l, right: r}) do
    if number_mode?(),
      do: "Math.trunc(#{expr_js(l)} / #{expr_js(r)})",
      else: "(#{expr_js(l)} / #{expr_js(r)})"
  end

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
    do: "[...#{paren(s)}].map(c => #{cp_expr("c.codePointAt(0)")})"

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}),
    do: "#{paren(cs)}.map(c => String.fromCodePoint(Number(c))).join(\"\")"

  # a `Char`'s codepoint — identity in JS, where a `Char` is a BigInt codepoint
  defp expr_js(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}), do: expr_js(c)

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}),
    do: "(#{expr_js(a)} + #{expr_js(b)})"

  # explicit 64-bit overflow ops (ADR-0035 §3) operate on `Int64`, which is NOT
  # supported on JS (ADR-0064): their two's-complement-at-64 contract has no JS
  # representation without per-op `BigInt.asIntN` masking — the silent BigInt
  # elevation we refuse. So they raise here (and `Rian.Reach` pins any `Int64`
  # function off `:js`, so the gate catches it first). A function reaching this is
  # one that bypassed the signature gate via an untyped call site.
  defp expr_js(%ECall{fun: %EId{name: prim}, args: [_, _]})
       when prim in @overflow_prims,
       do:
         raise(
           Unsupported,
           "`#{prim}` operates on `Int64`, which is not supported on JS (ADR-0064) — " <>
             "64-bit two's-complement wrap has no JS representation; use `Int` or `Int53`."
         )

  # the handful of stdlib calls the self-hosting spikes use, mapped to portable
  # JS (a stopgap until the portable prelude, ADR-0047, owns these):
  #   Map.get/put (immutable), String.to_charlist, List.to_string, :lists.reverse
  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "get"}, args: [m, k]}),
    do: "#{paren(m)}[#{expr_js(k)}]"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "put"}, args: [m, k, v]}),
    do: "{...#{paren(m)}, [#{expr_js(k)}]: #{expr_js(v)}}"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "String"}, name: "to_charlist"}, args: [s]}),
    do: "[...#{paren(s)}].map(c => #{cp_expr("c.codePointAt(0)")})"

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

  # named construction `Name(field: v, …)` (labeled args) -> a `__struct__`-tagged
  # object; a positional PascalCase call -> a sum-variant tagged array
  # `["Ctor", arg0, …]`; a lowercase call -> a function call
  defp expr_js(%ECall{fun: %EId{name: f}, args: [%ELabel{} | _] = args}) do
    fields = Enum.map_join(args, ", ", fn %ELabel{name: l, expr: e} -> "#{l}: #{expr_js(e)}" end)
    "{ __struct__: #{inspect(f)}, #{fields} }"
  end

  defp expr_js(%ECall{fun: %EId{name: f}, args: args}) do
    if pascal?(f) do
      "[#{Enum.join([inspect(f) | Enum.map(args, &expr_js/1)], ", ")}]"
    else
      "#{f}(#{Enum.map_join(args, ", ", &expr_js/1)})"
    end
  end

  defp expr_js(%EIf{cond: c, then: t, else: e}),
    do: "(#{expr_js(c)} ? #{branch_js(t)} : #{branch_js(e)})"

  # struct construction `Name(field: v, …)` -> a JS object tagged with
  # `__struct__` (so field access and protocol dispatch work uniformly)
  defp expr_js(%EStruct{name: name, pairs: pairs}) do
    fields = Enum.map_join(pairs, ", ", fn {label, v} -> "#{label}: #{expr_js(v)}" end)
    "{ __struct__: #{inspect(to_string(name))}#{if fields == "", do: "", else: ", " <> fields} }"
  end

  # bare field access `value.field` (a remote call `Mod.fun(…)` is handled above
  # as an `ECall` over an `EDot`, so a standalone `EDot` here is field access)
  defp expr_js(%EDot{head: head, name: field}), do: "#{expr_js(head)}.#{field}"

  defp expr_js(other), do: raise(Unsupported, "ecmascript: expression #{inspect(other)}")

  # an `if` branch is a block; a single-expression block is an expression, a
  # multi-statement block an IIFE
  defp branch_js(%EBlock{stmts: [{:expr, e}]}), do: expr_js(e)
  defp branch_js(%EBlock{stmts: []}), do: "undefined"
  defp branch_js(%EBlock{stmts: stmts}), do: "(() => { #{block_return(stmts)} })()"
  defp branch_js(expr), do: expr_js(expr)

  # ── helpers ─────────────────────────────────────────────────────────────
  # `Int` -> BigInt literal (`42n`); a Float64 literal is a plain JS number; in a
  # number-mode function (`Int53`/`Int32`), an integer literal is a plain (native)
  # JS number too
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

  # A `Char`/codepoint integer follows the function's integer mode: a plain JS
  # number in number-mode (`Int53`/`Int32`), a `BigInt` otherwise — so codepoints
  # never mix with the surrounding integers (JS forbids combining BigInt + number).
  defp number_mode?, do: Process.get(:rian_js_int53, false)
  defp cp_lit(cp), do: if(number_mode?(), do: "#{cp}", else: "#{cp}n")
  defp cp_expr(js), do: if(number_mode?(), do: js, else: "BigInt(#{js})")

  defp float?(n), do: String.contains?(n, ".") or String.match?(n, ~r/[eE]/)

  defp js_op("=="), do: "==="
  defp js_op("!="), do: "!=="
  defp js_op("and"), do: "&&"
  defp js_op("or"), do: "||"
  defp js_op(op) when op in ~w(+ - * < <= > >= %), do: op
  defp js_op("<>"), do: "+"
  # float division: ECMAScript `/` *is* IEEE-754 float division, which is exactly
  # what Rian `/` means (the checker types it `Float64`, ADR-0049). `Float64` is a
  # native JS `number`, so this is portable. (Integer `div` is the dedicated
  # `expr_js(%EBin{op: "div"})` clause above — `Math.trunc(l / r)`.)
  defp js_op("/"), do: "/"
  defp js_op("rem"), do: "%"
  defp js_op(op), do: raise(Unsupported, "ecmascript: operator `#{op}`")

  # parenthesise an operand of a postfix `[…]` / `.method()` so precedence holds
  defp paren(e), do: "(#{expr_js(e)})"

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)
end
