defmodule Rian.JVM do
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
  in a `throw` (no clause matched — dropped when a clause is unconditional).

  `Int64` lowers to `Long` (JVM has 64-bit ints natively, no boxing dance);
  `Float64` → `Double`, `Bool` → `Boolean`, `String` → `String`, `Char` → `Long`
  codepoint (the portable-prelude convention, ADR-0047), `Vec(T)` → `List<T>`.

  ## Scope (this increment)

  Functions (single/multi-clause) over `Int64`/`Float64`/`Bool`/`String`;
  variables; unary/binary operators; `if`-expressions; local calls; `when`
  guards; and **sum variants** — a `type` lowers to a sealed hierarchy, a
  construction `Ctor(a, …)` to a data-class constructor (nullary → an `object`),
  with clause patterns that smart-cast (`a0 is Ctor`) and recurse into positional
  fields (`a0.f0`, nested + literal patterns supported). **Not yet** (raise
  `Rian.JVM.Unsupported`): tuples, lists/`Vec`, maps, structs, `case`,
  atoms/`Symbol`, `with`, lambdas, protocols, general FFI.
  """
  alias Rian.{Core, Decl, Pratt}

  alias Rian.Core.{
    EBin,
    EBlock,
    ECall,
    EChar,
    EId,
    EIf,
    ENum,
    EStr,
    EUnary,
    PChar,
    PCtor,
    PLit,
    PVar,
    PWild
  }

  defmodule Unsupported do
    defexception [:message]
  end

  @doc "Compile `src`'s types + functions to a single Kotlin source module (a string)."
  def compile(src) do
    prog = Decl.parse(src)
    # the BEAM `:dispatcher` is a guarded runtime type-test, not the Kotlin shape;
    # protocol lowering for the JVM is a later increment.
    funcs = prog |> funcs_of() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    type_decls = Enum.map_join(types_of(prog), "\n\n", &sum_decl/1)
    fn_decls = Enum.map_join(funcs, "\n\n", &function_kt/1)

    [type_decls, fn_decls] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
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

  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  defp types_of(%{types: [], mods: [m]}), do: m.types
  defp types_of(%{types: types}), do: types

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
  defp function_kt(%{name: name, clauses: clauses, ret: ret, params: params, pub?: pub?}) do
    sig_params =
      params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {p, i} -> "a#{i}: #{kt_type(p.type)}" end)

    {lines, closed?} = clause_lines(clauses)

    tail =
      if closed?,
        do: "",
        else: "  throw RuntimeException(#{inspect("#{name}: no clause matched")})\n"

    vis = if pub?, do: "", else: "private "

    "#{vis}fun #{name}(#{sig_params}): #{kt_type(ret)} {\n#{lines}#{tail}}"
  end

  # Emit clauses top-to-bottom; an unconditional clause (no structural tests)
  # always matches, so it closes the function — drop the rest and the trailing
  # throw (Kotlin flags unreachable code).
  defp clause_lines(clauses) do
    {acc, closed?} =
      Enum.reduce_while(clauses, {[], false}, fn c, {acc, _} ->
        {tests, binds} = clause_match(c.pats)
        body = bind_str(binds) <> guarded_return(c.body, c.guard)

        case {tests, c.guard} do
          {[], nil} -> {:halt, {["  #{body}\n" | acc], true}}
          _ -> {:cont, {["  if (#{Enum.join(tests, " && ")}) { #{body} }\n" | acc], false}}
        end
      end)

    {acc |> Enum.reverse() |> Enum.join(""), closed?}
  end

  defp clause_match(pats) do
    pats
    |> Enum.map(&Core.from_pat/1)
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
      {t, b} = pat_match(p, "a#{i}")
      {ts ++ t, bs ++ b}
    end)
  end

  defp guarded_return(body, nil), do: "return #{clause_value(body)}"

  defp guarded_return(body, g),
    do: "if (#{expr_kt(Core.from_expr(Pratt.parse(g)))}) { return #{clause_value(body)} }"

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

  defp pat_match(other, _acc), do: raise(Unsupported, "jvm: clause pattern #{inspect(other)}")

  defp bind_str([]), do: ""
  defp bind_str(binds), do: Enum.map_join(binds, "", fn {n, a} -> "val #{n} = #{a}; " end)

  # a clause body parses to a block: `val`s then the final value expression
  defp clause_value(src) do
    %EBlock{stmts: stmts} = Core.from_expr(Pratt.parse_body(src))
    block_value(stmts)
  end

  defp block_value([{:expr, e}]), do: expr_kt(e)

  defp block_value(stmts) do
    {init, [last]} = Enum.split(stmts, -1)
    lets = Enum.map_join(init, " ", &stmt_kt/1)
    "run { #{lets} #{stmt_value(last)} }"
  end

  defp stmt_kt({:bind, n, e}), do: "val #{n} = #{expr_kt(e)};"
  defp stmt_kt({:typed_bind, n, _t, e}), do: "val #{n} = #{expr_kt(e)};"
  defp stmt_kt({:expr, e}), do: "#{expr_kt(e)};"
  defp stmt_value({:expr, e}), do: expr_kt(e)
  defp stmt_value({:bind, _, e}), do: expr_kt(e)
  defp stmt_value({:typed_bind, _, _, e}), do: expr_kt(e)

  # ── expression emission ─────────────────────────────────────────────────
  defp expr_kt(%ENum{text: n}), do: num_kt(n)
  defp expr_kt(%EChar{value: cp}), do: "#{cp}L"
  defp expr_kt(%EStr{value: s}), do: inspect(s)
  defp expr_kt(%EId{name: b}) when b in ~w(true false), do: b
  # a bare PascalCase id is a nullary sum variant -> its singleton `object`
  defp expr_kt(%EId{name: x}), do: x
  defp expr_kt(%EUnary{op: "-", arg: x}), do: "-#{expr_kt(x)}"
  defp expr_kt(%EUnary{op: "not", arg: x}), do: "!#{expr_kt(x)}"
  defp expr_kt(%EBin{op: op, left: l, right: r}), do: "(#{expr_kt(l)} #{kt_op(op)} #{expr_kt(r)})"

  # a PascalCase call is sum-variant construction `Ctor(args)`; a lowercase call
  # is a local function call
  defp expr_kt(%ECall{fun: %EId{name: f}, args: args}) do
    "#{f}(#{Enum.map_join(args, ", ", &expr_kt/1)})"
  end

  # Kotlin `if` is an expression
  defp expr_kt(%EIf{cond: c, then: t, else: e}),
    do: "if (#{expr_kt(c)}) #{branch_kt(t)} else #{branch_kt(e)}"

  defp expr_kt(other), do: raise(Unsupported, "jvm: expression #{inspect(other)}")

  defp branch_kt(%EBlock{stmts: [{:expr, e}]}), do: expr_kt(e)
  defp branch_kt(%EBlock{stmts: stmts}), do: block_value(stmts)
  defp branch_kt(expr), do: expr_kt(expr)

  # ── helpers ─────────────────────────────────────────────────────────────
  # Int64 -> a Kotlin `Long` literal (`42L`); a Float64 literal is a Kotlin Double
  defp num_kt(n), do: if(float?(n), do: n, else: "#{n}L")

  defp lit_kt(v) when is_integer(v), do: "#{v}L"
  defp lit_kt(v) when is_binary(v), do: inspect(v)

  defp float?(n), do: String.contains?(n, ".") or String.match?(n, ~r/[eE]/)

  defp kt_op("=="), do: "=="
  defp kt_op("!="), do: "!="
  defp kt_op("and"), do: "&&"
  defp kt_op("or"), do: "||"
  defp kt_op("<>"), do: "+"
  # Long `/` is integer division in Kotlin (matches Rian `div`); `%` is `rem`
  defp kt_op("div"), do: "/"
  defp kt_op("rem"), do: "%"
  defp kt_op(op) when op in ~w(+ - * < <= > >=), do: op
  defp kt_op(op), do: raise(Unsupported, "jvm: operator `#{op}`")

  defp kt_type(nil), do: raise(Unsupported, "jvm: missing type annotation")

  defp kt_type(t) do
    cond do
      t in ~w(Int64 Int Int53) -> "Long"
      String.match?(t, ~r/^U?Int\d*$/) -> "Long"
      String.match?(t, ~r/^Float\d*$/) -> "Double"
      t == "Bool" -> "Boolean"
      t == "String" -> "String"
      t == "Char" -> "Long"
      m = Regex.run(~r/^Vec\((.+)\)$/, t) -> "List<#{kt_type(Enum.at(m, 1))}>"
      String.match?(t, ~r/^[A-Z]/) -> t
      true -> raise(Unsupported, "jvm: type `#{t}`")
    end
  end
end
