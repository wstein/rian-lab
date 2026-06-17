defmodule Rian.JVM do
  use Rian.Ann

  @moduledoc """
  JVM emitter (ADR-0049 Tier 2) — a **direct Kotlin source emitter** built on the
  **typed core IR** (`Rian.Core`, ADR-0050): it consumes `Core.from_expr` /
  `Core.from_pat`, never the surface tuples. A fourth backend on the same core,
  no new fork (the ADR-0050 thesis), and the second proof after `Rian.JS`.

  **Kotlin, not Java** (the 2026-06 design review): Rian is sum-and-match
  oriented, and Kotlin's `sealed interface` + `data class` + smart-cast `is`
  patterns + expression-`if` map almost 1:1 — far less boilerplate than Java's
  pre-Valhalla boxing, and the idiomatic-per-target ethos (BEAM/Rust/JS each get
  their native shape). A Rian sum lowers to a sealed hierarchy:

      type Expr := Num(Int64) | Add(Expr, Expr)
      =>  sealed interface Expr
          data class Num(val f0: Long): Expr
          data class Add(val f0: Expr, val f1: Expr): Expr

  Kotlin has no native multi-clause functions, so a multi-clause `def` lowers to a
  **dispatcher**: positional params `a0, a1, …`, one `if (<structural tests>) { …
  return … }` per clause (binds via Kotlin smart-cast after an `is` test), ending
  in a `throw` (no clause matched — dropped when a clause is unconditional). A
  clause whose only condition is a `when` guard (no structural test) lowers to a
  scoped `run { … }` carrying the guard as its inner `if`.

  `Int64` lowers to `Long` (JVM has 64-bit ints natively, no boxing dance);
  `Float64` → `Double`, `Bool` → `Boolean`, `String` → `String`, `Char` → `Long`
  codepoint (the portable-prelude convention, ADR-0047), `Vec(T)` → `List<T>`.

  ## Scope (this increment)

  Functions (single/multi-clause) over `Int64`/`Float64`/`Bool`/`String`;
  variables; unary/binary operators; `if`-expressions; local calls; `when`
  guards; and **sum variants** — a `type` lowers to a sealed hierarchy, a
  construction `Ctor(a, …)` to a data-class constructor (nullary → an `object`),
  with clause patterns that smart-cast (`a0 is Ctor`) and recurse into positional
  fields (`a0.f0`, nested + literal patterns supported). A `case` expression lowers
  to a labelled `run rcase@{ … }` whose arms reuse the clause dispatcher's
  smart-cast/literal tests, binds, and guard handling. **Lists / `Vec(T)`** lower to
  Kotlin `List<T>`: a literal `[a, b]` → `listOf(a, b)`, a cons `[h, … | t]` →
  `listOf(h, …) + t`; clause/`case` patterns test `size` (exact for a closed list,
  `>=` for a cons), match fixed elements by index (`acc[i]`), and bind the rest with
  `acc.drop(n)`. The `Str`/`Char` prims over codepoint lists are lowered
  (`str_chars`/`str_from_chars`/`str_concat`/`char_code`). **Not yet** (raise
  `Rian.JVM.Unsupported`): tuples, maps, structs, atoms/`Symbol`, `with`, lambdas,
  protocols, general FFI.

  ## Capabilities

  The portable core is `val`/`iso`/`tag`; `ref` (`&mut`) has no Kotlin analog. It is
  **intentionally lowered to value semantics** — a `ref` param emits an ordinary
  `val` binding, which is *sound today* because the Rian surface is return-based (no
  in-place mutation operator), so `ref` only ever changed the Rust signature. If a
  future in-place-mutation primitive is added, this assumption breaks and `ref`
  would need real handling here — `test/rian/jvm_test.exs` locks the current
  value-lowering so that change can't pass silently.
  """
  alias Rian.{Check, Core, Decl, Pratt}

  alias Rian.Core.{
    EBin,
    EBlock,
    ECall,
    ECase,
    EChar,
    EConstRef,
    EDot,
    EId,
    EIf,
    EList,
    ENum,
    EStr,
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

  # Fast-fail diagnostic (parity with `Rian.JS`): before emitting, scan each
  # function body for a construct the Tier-2 JVM emitter does not yet implement and
  # raise ONE clear error naming the function and construct, rather than a deep
  # `inspect`-dump mid-emission. Reach stays *architectural* (ADR-0041); this is an
  # *implementation-status* check over the constructs the emitter handles in NO
  # context. (Type-level gaps — `Vec`/`Map` params, etc. — are left to `kt_type`.)
  # `Core.reject_unsupported!` runs the shared walk; this map is the JVM-specific set.
  @jvm_unsupported %{
    Core.EWith => "a `with` expression",
    Core.ELambda => "a lambda",
    Core.ECapture => "a function capture (`&(…)`)",
    Core.ECaptureNamed => "a function capture (`&name/arity`)",
    Core.ETuple => "a tuple",
    Core.EMap => "a map",
    Core.EMapUpdate => "a map update",
    Core.EBitstr => "a bitstring (BEAM-only, ADR-0078)",
    Core.EStruct => "a struct construction"
  }

  @doc "Compile `src`'s types + functions to a single Kotlin source module (a string)."
  @rian "pub def compile(src String) String"
  @spec compile(String.t()) :: String.t()
  def compile(src) do
    prog = Decl.parse(src)
    # Run the full type gate first — parity with the BEAM path (`Decl.compile`); a
    # `Rian.Check` error is caught here rather than emitted as malformed Kotlin.
    :ok = Check.gate!(prog)
    # Erase abstract types to their base after the gate (ADR-0067): `opaque Token
    # := String` emits as the underlying `String`, and `Token.of(x)` -> `x`.
    prog = Rian.Opaque.erase(prog)
    # the BEAM `:dispatcher` is a guarded runtime type-test, not the Kotlin shape;
    # protocol lowering for the JVM is a later increment.
    funcs = prog |> all_funcs() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    Core.reject_unsupported!(funcs, @jvm_unsupported, :jvm, Unsupported)
    type_decls = Enum.map_join(all_types(prog), "\n\n", &sum_decl/1)
    # `const NAME := value` (ADR-0033) lowers to a top-level `val`, and a reference
    # resolves to it — threaded through `ic[:consts]` (parity with `Rian.Beam`/
    # `Rian.Lower`); without this a const reference emitted as an unresolved Kotlin
    # identifier (a silent miscompile).
    consts = all_consts(prog)
    # the program inference context types each clause body's core IR (ADR-0050 §3).
    ic = Rian.Check.program_ic(prog) |> Map.put(:consts, MapSet.new(consts, & &1.name))
    const_decls = Enum.map_join(consts, "\n", &const_kt(&1, ic))
    fn_decls = Enum.map_join(funcs, "\n\n", &function_kt(&1, ic))
    # inject the float-repr helper only when the program lowers `__prim_float_repr`.
    runtime =
      if String.contains?(fn_decls, "__rian_float_repr("), do: float_repr_helper(), else: ""

    [runtime, type_decls, const_decls, fn_decls]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp all_consts(prog),
    do:
      Map.get(prog, :consts, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :consts, []))

  # `const NAME := value` -> a top-level Kotlin `val`. The value parses and resolves
  # sibling const references; `block_value` emits a single expression inline and a
  # multi-statement block value as a scoped `run { … }`.
  defp const_kt(c, ic) do
    %EBlock{stmts: stmts} =
      c.value
      |> Pratt.parse_body()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Rian.Check.annotate(%{}, ic)

    "val #{c.name} = #{block_value(Rian.Shadow.dedup(stmts, [], &kt_fresh/2))}"
  end

  # Rewrite a reference to a declared `const` (`{:id, NAME}`, NAME in the set) into a
  # `{:const_ref, NAME}` surface node (lifted to `EConstRef` by `Core.from_expr`),
  # which this emitter spells as the const's name (parity with `Rian.Beam`/`Rian.Lower`).
  defp resolve_consts(node, cset) do
    if MapSet.size(cset) == 0, do: node, else: walk_consts(node, cset)
  end

  defp walk_consts({:id, name} = node, cset),
    do: if(MapSet.member?(cset, name), do: {:const_ref, name}, else: node)

  defp walk_consts(node, cset), do: Rian.Macro.map_node(node, &walk_consts(&1, cset))

  # The `__prim_float_repr` lowering (ADR-0069). Returns the **shortest** decimal
  # string that round-trips to `x` — the contract `Show.float` relies on. Java's
  # `Double.toString` is shortest for all normal doubles but JLS-pinned to a
  # non-shortest form for the tiniest denormals, so we search instead: the smallest
  # significant-digit count whose `%e` rounding parses back to `x` exactly. Verified
  # byte-identical to ECMAScript `String(x)` across a 120k-double fuzz + the whole
  # denormal tail. `Locale.ROOT` keeps the decimal separator a `.` regardless of host
  # locale; ±0/NaN/Inf fall through to `toString` (`Show.float` handles the sign/zero).
  defp float_repr_helper do
    """
    private fun __rian_float_repr(x: Double): String {
      if (x.isNaN() || x.isInfinite() || x == 0.0) return x.toString()
      val a = Math.abs(x)
      var rep = a.toString()
      for (p in 0..16) {
        val c = String.format(java.util.Locale.ROOT, "%." + p + "e", a)
        if (c.toDouble() == a) { rep = c; break }
      }
      return if (x < 0) "-" + rep else rep
    }\
    """
  end

  @doc """
  Assemble `src` into a JVM `.jar` at `jar_path` by emitting Kotlin (`compile/1`)
  and invoking `kotlinc -include-runtime`. This is the **rung-B** path (ADR-0062):
  a real, runnable artifact, but via the host Kotlin compiler — a transpile step,
  not yet direct bytecode (the rung-C analog of `Rian.Beam`'s abstract forms).

  `opts[:main]` names a **zero-arg** function to wrap in a generated
  `fun main()` (it prints the result), so the jar is runnable with `java -jar`;
  without it, a library jar whose top-level functions are callable from the JVM
  as `<File>Kt.fn(…)`. Returns `{:ok, jar_path}`. Raises `RuntimeError` if
  `kotlinc` is absent or the emitted Kotlin does not compile (and the emitter
  itself raises `Rian.JVM.Unsupported` for a not-yet-lowered construct).
  """
  @spec to_jar(String.t(), String.t(), keyword()) :: {:ok, String.t()}
  def to_jar(src, jar_path, opts \\ []) do
    kotlinc =
      System.find_executable("kotlinc") ||
        raise(
          RuntimeError,
          "`kotlinc` not found on PATH — needed to assemble a JVM .jar (ADR-0049 Tier 2)"
        )

    ktfile = Path.join(System.tmp_dir!(), "rian_jar_#{System.unique_integer([:positive])}.kt")
    File.write!(ktfile, kotlin_module(src, opts[:main]))

    try do
      case System.cmd(kotlinc, [ktfile, "-include-runtime", "-d", jar_path],
             stderr_to_stdout: true
           ) do
        {_, 0} -> {:ok, jar_path}
        {out, code} -> raise(RuntimeError, "kotlinc failed (exit #{code}):\n#{out}")
      end
    after
      File.rm(ktfile)
    end
  end

  # the Kotlin compilation unit, optionally with a generated `main` entry point
  # (kotlinc derives `Main-Class` from a top-level `fun main`, so `-include-runtime`
  # yields a `java -jar`-runnable fat jar).
  defp kotlin_module(src, nil), do: compile(src)

  defp kotlin_module(src, main) when is_binary(main),
    do: compile(src) <> "\n\nfun main() {\n  println(#{main}())\n}\n"

  # every function/type the Kotlin file emits: the top-level ones plus every `mod`'s,
  # flattened into one namespace — the JVM unit erases module boundaries, so a
  # cross-module call `Mod.fun(…)` lowers to a bare `fun(…)` (see the `EDot`-call
  # clause). This is how the injected `Show` module (ADR-0069 `${float}`) is emitted.
  defp all_funcs(prog),
    do: Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

  defp all_types(prog),
    do: Map.get(prog, :types, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.types)

  # ── sum type -> a Kotlin sealed hierarchy ───────────────────────────────
  defp sum_decl(t) do
    variants = Enum.map_join(t.variants, "\n", &variant_decl(&1, t.name))
    "sealed interface #{t.name}\n#{variants}"
  end

  # a nullary variant is a singleton `object`; an arg-carrying one a `data class`
  # with positional fields `f0, f1, …` (Rian variants are positional).
  defp variant_decl(%{ctor: ctor, fields: []}, tname), do: "object #{ctor} : #{tname}"

  defp variant_decl(%{ctor: ctor, fields: fields}, tname) do
    params =
      fields
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {f, i} -> "val f#{i}: #{kt_type(f.type)}" end)

    "data class #{ctor}(#{params}) : #{tname}"
  end

  # ── function / clause dispatch ──────────────────────────────────────────
  # an `@external` function (ADR-0068): emit the `:jvm` host body verbatim, binding
  # each param to its positional argument by name. No `:jvm` body -> off `:jvm`.
  defp function_kt(%{externals: ext} = f, _ic) when map_size(ext) > 0 do
    case Map.get(ext, :jvm) do
      nil ->
        raise Unsupported, "`#{f.name}`: no `@external(:jvm, …)` body — not reachable on :jvm"

      spec ->
        sig =
          f.params
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {p, i} -> "a#{i}: #{kt_type(p.type)}" end)

        binds =
          f.params
          |> Enum.with_index()
          |> Enum.map_join(" ", fn {p, i} -> "val #{p.name} = a#{i};" end)

        vis = if f.pub?, do: "", else: "private "
        "#{vis}fun #{f.name}(#{sig}): #{kt_type(f.ret)} { #{binds} return #{spec} }"
    end
  end

  defp function_kt(%{name: name, clauses: clauses, ret: ret, params: params, pub?: pub?}, ic) do
    sig_params =
      params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {p, i} -> "a#{i}: #{kt_type(p.type)}" end)

    {lines, closed?} = clause_lines(clauses, params, ic)

    tail =
      if closed?,
        do: "",
        else: "  throw RuntimeException(#{inspect("#{name}: no clause matched")})\n"

    vis = if pub?, do: "", else: "private "

    "#{vis}fun #{name}(#{sig_params}): #{kt_type(ret)} {\n#{lines}#{tail}}"
  end

  # Emit clauses top-to-bottom; an unconditional clause (no tests, no guard)
  # always matches, so it closes the function — return without emitting the rest
  # (or the trailing throw, which Kotlin would flag as unreachable). Dispatching
  # on the guard and recursing — rather than threading a `{acc, closed?}` tuple
  # through `reduce_while` — lets "closes" be "don't recurse" instead of `:halt`.
  defp clause_lines([], _params, _ic), do: {"", false}

  defp clause_lines([c | rest], params, ic) do
    {tests, binds} = clause_match(c.pats)
    param_names = Enum.map(binds, fn {n, _} -> n end)
    # the per-clause typing env types the body's core IR (ADR-0050 §3).
    tenv = Rian.Check.clause_env(c.pats, params, ic)
    line = bind_str(binds) <> guarded_return(c.body, c.guard, param_names, tenv, ic)

    case c.guard do
      nil -> closed_or_cond(tests, line, rest, params, ic)
      _ -> run_or_cond(tests, line, rest, params, ic)
    end
  end

  # no guard: empty tests -> unconditional (closes the function); else an `if`.
  defp closed_or_cond([], line, _rest, _params, _ic), do: {"  #{line}\n", true}

  defp closed_or_cond(tests, line, rest, params, ic),
    do: prepend_if(tests, line, rest, params, ic)

  # guarded: a guard with no structural tests carries its condition in the inner
  # `if` that `guarded_return/3` emits; wrap it in a scoped `run { … }` (an empty
  # `if () { … }` is not valid Kotlin) so the binds stay local and a matched guard
  # returns non-locally from the function. With tests, it's a plain conditional `if`.
  defp run_or_cond([], line, rest, params, ic),
    do: prepend("  run { #{line} }\n", clause_lines(rest, params, ic))

  defp run_or_cond(tests, line, rest, params, ic), do: prepend_if(tests, line, rest, params, ic)

  defp prepend_if(tests, line, rest, params, ic),
    do:
      prepend("  if (#{Enum.join(tests, " && ")}) { #{line} }\n", clause_lines(rest, params, ic))

  defp prepend(s, {lines, closed?}), do: {s <> lines, closed?}

  defp clause_match(pats) do
    pats
    |> Enum.map(&Core.from_pat/1)
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
      {t, b} = pat_match(p, "a#{i}")
      {ts ++ t, bs ++ b}
    end)
  end

  defp guarded_return(body, nil, params, tenv, ic),
    do: "return #{clause_value(body, params, tenv, ic)}"

  defp guarded_return(body, g, params, tenv, ic) do
    guard =
      g
      |> Pratt.parse()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Rian.Check.annotate(tenv, ic)
      |> expr_kt()

    "if (#{guard}) { return #{clause_value(body, params, tenv, ic)} }"
  end

  # Match `pat` against the Kotlin access path `acc` -> `{tests, binds}`. A sum
  # value is a `data class`, so a ctor pattern smart-casts (`acc is Ctor`) and
  # recurses into positional fields `acc.f0`, `acc.f1`, ….
  defp pat_match(%PWild{}, _acc), do: {[], []}
  defp pat_match(%PVar{name: n}, acc), do: {[], [{n, acc}]}
  defp pat_match(%PLit{value: v}, acc), do: {["#{acc} == #{lit_kt(v)}"], []}
  defp pat_match(%PChar{value: cp}, acc), do: {["#{acc} == #{cp}L"], []}

  defp pat_match(%PCtor{ctor: ctor, args: args}, acc) do
    {ts, bs} =
      args
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}.f#{i}")
        {ts ++ t, bs ++ b}
      end)

    {["#{acc} is #{ctor}" | ts], bs}
  end

  # a list pattern over a `List<_>` access path. A closed `[a, b]` tests the exact
  # `size`; a cons `[a, … | t]` tests `size >=` the fixed-element count and binds the
  # rest pattern to `acc.drop(n)`. Each fixed element `i` matches `acc[i]` (a literal
  # tests, a var binds, recursively). The `&&` chain is short-circuit, so an element
  # test never indexes past a failed size guard.
  defp pat_match(%PList{elems: elems, tail: tail}, acc) do
    n = length(elems)

    size_test =
      case {n, tail} do
        {0, :close} -> ["(#{acc}).isEmpty()"]
        {_, :close} -> ["(#{acc}).size == #{n}"]
        _ -> ["(#{acc}).size >= #{n}"]
      end

    {elem_tests, elem_binds} =
      elems
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "(#{acc})[#{i}]")
        {ts ++ t, bs ++ b}
      end)

    {tail_tests, tail_binds} =
      case tail do
        :close -> {[], []}
        t -> pat_match(t, "(#{acc}).drop(#{n})")
      end

    {size_test ++ elem_tests ++ tail_tests, elem_binds ++ tail_binds}
  end

  defp pat_match(other, _acc), do: raise(Unsupported, "jvm: clause pattern #{inspect(other)}")

  defp bind_str([]), do: ""
  defp bind_str(binds), do: Enum.map_join(binds, "", fn {n, a} -> "val #{n} = #{a}; " end)

  # a clause body parses to a block: `val`s then the final value expression.
  # `:=` shadowing is resolved on the Core IR by `Rian.Shadow` first — a Kotlin
  # `val`/`var` cannot be re-declared in a scope. Kotlin forbids `$`/`@` in a
  # plain identifier, so the fresh name is backtick-quoted (`` `x$1` ``): a valid
  # Kotlin identifier that a Rian source name can never collide with.
  defp clause_value(src, params, tenv, ic) do
    %EBlock{stmts: stmts} =
      src
      |> Pratt.parse_body()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Rian.Check.annotate(tenv, ic)

    block_value(Rian.Shadow.dedup(stmts, params, &kt_fresh/2))
  end

  defp kt_fresh(base, count), do: "`" <> base <> "$" <> Integer.to_string(count) <> "`"

  defp block_value([{:expr, e}]), do: expr_kt(e)

  defp block_value(stmts) do
    {init, [last]} = Enum.split(stmts, -1)
    lets = Enum.map_join(init, " ", &stmt_kt/1)
    "run { #{lets} #{stmt_value(last)} }"
  end

  defp stmt_kt({:bind, n, e}), do: "val #{n} = #{expr_kt(e)};"
  defp stmt_kt({:typed_bind, n, _t, e}), do: "val #{n} = #{expr_kt(e)};"
  defp stmt_kt({:expr, e}), do: "#{expr_kt(e)};"
  # A block's value is its final statement, always an expression — a trailing
  # binding is rejected at `Rian.Core` (ADR-0035), so `stmt_value` only sees `:expr`.
  defp stmt_value({:expr, e}), do: expr_kt(e)

  # ── expression emission ─────────────────────────────────────────────────
  defp expr_kt(%ENum{text: n}), do: num_kt(n)
  # a reference to a declared `const` -> the top-level `val`'s name (emitted by `const_kt`).
  defp expr_kt(%EConstRef{name: name}), do: name
  defp expr_kt(%EChar{value: cp}), do: "#{cp}L"
  defp expr_kt(%EStr{value: s}), do: kt_str(s)
  defp expr_kt(%EId{name: b}) when b in ~w(true false), do: b
  # a bare PascalCase id is a nullary sum variant -> its singleton `object`
  defp expr_kt(%EId{name: x}), do: x
  defp expr_kt(%EUnary{op: "-", arg: x}), do: "-#{expr_kt(x)}"
  defp expr_kt(%EUnary{op: "not", arg: x}), do: "!#{expr_kt(x)}"
  defp expr_kt(%EBin{op: op, left: l, right: r}), do: "(#{expr_kt(l)} #{kt_op(op)} #{expr_kt(r)})"

  # integer → string (ADR-0069 interpolation): Kotlin `Long.toString()`
  defp expr_kt(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}),
    do: "(#{expr_kt(n)}).toString()"

  # float → shortest-round-trip string (ADR-0069 Float64 unlock); `Rian.Show.float`
  # normalizes it to the ECMAScript canonical. Lowers to the injected
  # `__rian_float_repr` helper (below) rather than `Double.toString` directly: the
  # JLS pins `toString` to a *non-shortest* form for the tiniest denormals (`4.9E-324`
  # vs ECMA's `5e-324`), which would break byte-identity, so the helper finds the true
  # shortest by trial — making `:jvm` byte-identical to ECMAScript for *every* double.
  defp expr_kt(%ECall{fun: %EId{name: "__prim_float_repr"}, args: [n]}),
    do: "__rian_float_repr(#{expr_kt(n)})"

  # variadic single-shot join (ADR-0069 §6): a flat `+` chain — every part is
  # already a String; the Kotlin compiler lowers it to a single StringBuilder.
  defp expr_kt(%ECall{fun: %EId{name: "__prim_str_concat_all"}, args: args}),
    do: "(" <> Enum.map_join(args, " + ", &expr_kt/1) <> ")"

  # a `Char`'s single-character string (ADR-0069 §6): a `Char` is a codepoint `Long`,
  # so `String(Character.toChars(cp))` (handles supplementary codepoints / surrogates).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_char_to_string"}, args: [c]}),
    do: "String(Character.toChars((#{expr_kt(c)}).toInt()))"

  # ── `Str`/`Char` primitives over `Vec(Char)` = `List<Long>` codepoints ────
  # a String → its codepoints as `List<Long>` (the portable-prelude `Vec(Char)`).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}),
    do: "(#{expr_kt(s)}).codePoints().toArray().map { it.toLong() }"

  # a `Vec(Char)` → the String of those codepoints (supplementary-safe).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}),
    do: ~s|(#{expr_kt(cs)}).joinToString("") { String(Character.toChars(it.toInt())) }|

  # a `Char`'s codepoint — identity, since a `Char` *is* a codepoint `Long`.
  defp expr_kt(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}), do: expr_kt(c)

  # binary String concat (`Prim.str_concat`): Kotlin `+`.
  defp expr_kt(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}),
    do: "(#{expr_kt(a)} + #{expr_kt(b)})"

  # integer → float (ADR-0035 explicit conversion): Kotlin `Long.toDouble()`
  defp expr_kt(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [n]}),
    do: "(#{expr_kt(n)}).toDouble()"

  # a user cross-module call `Mod.fun(args)` (Pascal-qualified): the JVM unit erases
  # module boundaries — every `mod`'s funcs flatten into the one file (`all_funcs/1`)
  # — so the qualifier drops and it lowers to a bare call. (ADR-0069: the `Show`
  # module injected for `${float}` interpolation resolves through here.) The built-in
  # interop namespaces have no JVM lowering, so they are excluded and raise via the
  # `Unsupported` fallback (FFI is off `:jvm`).
  defp expr_kt(%ECall{fun: %EDot{head: %EId{name: mod}, name: fun}, args: args})
       when mod not in ~w(Map String List),
       do: "#{fun}(#{Enum.map_join(args, ", ", &expr_kt/1)})"

  # a PascalCase call is sum-variant construction `Ctor(args)`; a lowercase call
  # is a local function call
  defp expr_kt(%ECall{fun: %EId{name: f}, args: args}) do
    "#{f}(#{Enum.map_join(args, ", ", &expr_kt/1)})"
  end

  # a list literal `[a, b]` → `listOf(a, b)` (the empty `[]` → `listOf()`, whose
  # `List<Nothing>` unifies with any `List<T>` by covariance); a cons `[h, … | t]`
  # → `listOf(h, …) + t` (Kotlin `List + List` concatenation). `Vec(Char)` elements
  # are codepoint `Long`s, so this is a `List<Long>`.
  defp expr_kt(%EList{elems: elems, tail: :close}),
    do: "listOf(#{Enum.map_join(elems, ", ", &expr_kt/1)})"

  defp expr_kt(%EList{elems: elems, tail: tail}),
    do: "(listOf(#{Enum.map_join(elems, ", ", &expr_kt/1)}) + #{expr_kt(tail)})"

  # Kotlin `if` is an expression
  defp expr_kt(%EIf{cond: c, then: t, else: e}),
    do: "if (#{expr_kt(c)}) #{branch_kt(t)} else #{branch_kt(e)}"

  # `case` is an expression: a labelled `run` whose arms test the scrutinee like
  # the clause dispatcher and `return@rcase` the matching body. Reuses `pat_match`
  # for the smart-cast/literal tests + binds; a `when` guard rides an inner `if`.
  # The scrutinee is bound once (skipped when it is already a bare variable).
  defp expr_kt(%ECase{scrut: scrut, arms: arms}) do
    {decl, acc} =
      case scrut do
        %EId{name: n} -> {[], n}
        other -> {["val __s = #{expr_kt(other)}"], "__s"}
      end

    {arm_lines, closed?} = case_arms(arms, acc)
    tail = if closed?, do: [], else: ["throw RuntimeException(\"case: no clause matched\")"]
    # statements are newline-separated (Kotlin does not accept space-separated ones)
    "run rcase@{\n" <> Enum.join(decl ++ arm_lines ++ tail, "\n") <> "\n}"
  end

  defp expr_kt(other), do: raise(Unsupported, "jvm: expression #{inspect(other)}")

  defp branch_kt(%EBlock{stmts: [{:expr, e}]}), do: expr_kt(e)
  defp branch_kt(%EBlock{stmts: stmts}), do: block_value(stmts)
  defp branch_kt(expr), do: expr_kt(expr)

  # Emit `case` arms top-to-bottom, mirroring `clause_lines`: a structural test is
  # an `if`, a guard-only arm a scoped `run { … }`, and an unconditional arm closes
  # the `run` (drop the rest + the trailing throw). `branch_kt` yields the arm body.
  defp case_arms(arms, acc) do
    {lines, closed?} =
      Enum.reduce_while(arms, {[], false}, fn {pat, guard, body}, {ls, _} ->
        {tests, binds} = pat_match(pat, acc)
        stmt = bind_str(binds) <> guarded_arm(branch_kt(body), guard)

        case {tests, guard} do
          {[], nil} -> {:halt, {["#{stmt}" | ls], true}}
          {[], _g} -> {:cont, {["run { #{stmt} }" | ls], false}}
          _ -> {:cont, {["if (#{Enum.join(tests, " && ")}) { #{stmt} }" | ls], false}}
        end
      end)

    {Enum.reverse(lines), closed?}
  end

  defp guarded_arm(body_kt, nil), do: "return@rcase #{body_kt}"
  defp guarded_arm(body_kt, g), do: "if (#{expr_kt(g)}) { return@rcase #{body_kt} }"

  # ── helpers ─────────────────────────────────────────────────────────────
  # Int64 -> a Kotlin `Long` literal (`42L`); a Float64 literal is a Kotlin Double
  defp num_kt(n), do: if(float?(n), do: n, else: "#{n}L")

  defp lit_kt(v) when is_integer(v), do: "#{v}L"
  defp lit_kt(v) when is_binary(v), do: kt_str(v)

  # render a decoded `String` value as a Kotlin double-quoted literal. Beyond the
  # quote/backslash and common control chars, Kotlin needs `$` escaped (string
  # templates) and uses fixed four-digit `\uHHHH` for other control codepoints.
  defp kt_str(s), do: ~s(") <> for(<<cp::utf8 <- s>>, into: "", do: kt_str_cp(cp)) <> ~s(")

  defp kt_str_cp(?\\), do: "\\\\"
  defp kt_str_cp(?"), do: "\\\""
  defp kt_str_cp(?$), do: "\\$"
  defp kt_str_cp(?\n), do: "\\n"
  defp kt_str_cp(?\r), do: "\\r"
  defp kt_str_cp(?\t), do: "\\t"
  defp kt_str_cp(cp) when cp < 0x20 or cp == 0x7F, do: "\\u" <> kt_hex4(cp)
  defp kt_str_cp(cp), do: <<cp::utf8>>

  defp kt_hex4(cp), do: String.pad_leading(Integer.to_string(cp, 16), 4, "0")

  defp float?(n), do: String.contains?(n, ".") or String.match?(n, ~r/[eE]/)

  defp kt_op("=="), do: "=="
  defp kt_op("!="), do: "!="
  defp kt_op("and"), do: "&&"
  defp kt_op("or"), do: "||"
  defp kt_op("<>"), do: "+"
  # Long `/` is integer division in Kotlin (matches Rian `div`); `%` is `rem`
  defp kt_op("div"), do: "/"
  defp kt_op("rem"), do: "%"
  # float division: Rian `/` is always `Float64` (ADR-0049) -> a Kotlin `Double`, on
  # which `/` is IEEE-754 float division. (Kotlin disambiguates by operand type:
  # `Long / Long` from `div` is integer division, `Double / Double` here is float.)
  defp kt_op("/"), do: "/"
  defp kt_op(op) when op in ~w(+ - * < <= > >=), do: op
  defp kt_op(op), do: raise(Unsupported, "jvm: operator `#{op}`")

  defp kt_type(nil), do: raise(Unsupported, "jvm: missing type annotation")

  defp kt_type(t) do
    cond do
      # `Int` is arbitrary precision (ADR-0064) — a JVM `Long` would wrap, so it
      # needs `BigInteger` (not implemented); fail loudly rather than mis-map.
      t == "Int" ->
        raise(
          Unsupported,
          "jvm: `Int` (arbitrary precision, ADR-0064) needs BigInteger; use `Int64`"
        )

      t in ~w(Int64 Int53) ->
        "Long"

      String.match?(t, ~r/^U?Int\d*$/) ->
        "Long"

      String.match?(t, ~r/^Float\d*$/) ->
        "Double"

      t == "Bool" ->
        "Boolean"

      t == "String" ->
        "String"

      t == "Char" ->
        "Long"

      m = Regex.run(~r/^Vec\((.+)\)$/, t) ->
        "List<#{kt_type(Enum.at(m, 1))}>"

      String.match?(t, ~r/^[A-Z]/) ->
        t

      true ->
        raise(Unsupported, "jvm: type `#{t}`")
    end
  end
end
