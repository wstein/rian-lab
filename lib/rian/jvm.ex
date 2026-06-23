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
  **generic functions** (`forall T` → a `<T>` declaration on the `fun`, so a `T` in
  the signature resolves); variables; unary/binary operators; `if`-expressions;
  local calls; `when` guards; and **sum variants** — a `type` lowers to a sealed hierarchy, a
  construction `Ctor(a, …)` to a data-class constructor (nullary → an `object`),
  with clause patterns that smart-cast (`a0 is Ctor`) and recurse into positional
  fields (`a0.f0`, nested + literal patterns supported). A `case` expression lowers
  to a labelled `run rcase@{ … }` whose arms reuse the clause dispatcher's
  smart-cast/literal tests, binds, and guard handling. **Lists / `Vec(T)`** lower to
  Kotlin `List<T>`: a literal `[a, b]` → `listOf(a, b)`, a cons `[h, … | t]` →
  `listOf(h, …) + t`; clause/`case` patterns test `size` (exact for a closed list,
  `>=` for a cons), match fixed elements by index (`acc[i]`), and bind the rest with
  `acc.drop(n)`. The `Str`/`Char` prims over codepoint lists are lowered
  (`str_chars`/`str_from_chars`/`str_concat`/`char_code`). A `Symbol`/atom (`:foo`)
  lowers to a Kotlin `String` — its interned name (ADR-0041) — as a value, a pattern
  test (`a0 == "ok"`), and a param/return type. **Protocols** (ADR-0042) lower: a
  `dispatch: :dispatcher` becomes a `when (a0)` over the receiver's runtime type
  (`is Long`/`is Bag` → the matching `impl_…`, the other `Self` args `as`-cast), and a
  bounded-generic consumer (`forall T: Eq`) calls it — the bound erases (dispatch is
  dynamic). An **associated type** (ADR-0074) in a covariant `Vec(...)` return erases to
  `List<Any>` (`Foldable.to_list() Vec(Elem)`), and a type-directed coercion pass
  (`coerce_casts`) inserts `as List<T>` where that `List<Any>` flows into a concrete
  `List<T>` callee param (an element-*typed* consumer). A **lambda** `(a) -> body`
  lowers to a Kotlin lambda `{ a -> body }` and a `Fn(arg…, ret)` type to a Kotlin
  function type `(arg…) -> ret`, capturing the environment natively (ADR-0061).
  A **capture** `&(&1 * 2)` lowers to a Kotlin lambda over generated args
  (`{ _1 -> … }`) and `&name/arity` to a Kotlin function reference `::name`. A
  **tuple** `{a, b}` / `{a, b, c}` lowers to a Kotlin `Pair`/`Triple` (type
  `(A, B)` → `Pair<A, B>`), destructured in a pattern via `componentN()`. A
  **struct** `struct Name(f T, …)` lowers to a Kotlin `data class` (named-arg
  construction `Name(f = v)`, field access `p.f`, and `is Name` patterns). A
  **map** `%{k: v}` (atom keys → `String`) lowers to a Kotlin `Map` (`mapOf("k" to
  v)`, type `Dict(K, V)` → `Map<K, V>`), with `Map.get`→`getValue`, `Map.put`→`+
  (k to v)`, `Map.has`→`containsKey`. A **`with`** expression desugars to nested
  `case`s (ADR-0040, via `Core.desugar_with`). **Not yet** (raise
  `Rian.JVM.Unsupported`): arity-≥4 tuples (use a struct), tagged tuples
  (`{:ok, v}` — a Result, BEAM-only), non-atom map keys (BEAM-only), map update
  (`%{m | …}`), bitstrings, general FFI; and an associated type in a
  *non*-covariant position (a bare `Elem` return / an `Elem` parameter), which
  stays off `:jvm`. A **value union** `A | B` (ADR-0083) erases to
  `Any` — a member value *is-a* `Any`, so construction needs no wrapping — and a
  type-pattern `n Int53 ->` narrows it back with `is Long`/`is String` (Kotlin
  smart-cast), the same discriminator the dispatcher uses.

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
    EAtom,
    EBin,
    EBlock,
    ECall,
    ECase,
    EChar,
    EConstRef,
    EDot,
    EId,
    ECapArg,
    ECapture,
    ECaptureNamed,
    EIf,
    ELabel,
    ELambda,
    EList,
    EMap,
    ENum,
    EStr,
    EStruct,
    ETuple,
    EUnary,
    EWith,
    PAs,
    PAtom,
    PChar,
    PCtor,
    PList,
    PLit,
    PMap,
    PPin,
    PStruct,
    PTuple,
    PTyped,
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
    Core.EMapUpdate => "a map update",
    Core.EBitstr => "a bitstring (BEAM-only, ADR-0078)"
  }

  @doc "Compile `src`'s types + functions to a single Kotlin source module (a string)."
  @rian_sig "pub def compile(src String) String"
  @spec compile(String.t()) :: String.t()
  def compile(src) do
    prog = Decl.parse(src)
    # Run the full type gate first — parity with the BEAM path (`Decl.compile`); a
    # `Rian.Check` error is caught here rather than emitted as malformed Kotlin.
    :ok = Check.gate!(prog)
    # Erase abstract types to their base after the gate (ADR-0067): `opaque Token
    # := String` emits as the underlying `String`, and `Token.of(x)` -> `x`.
    prog = Rian.Opaque.erase(prog)
    # A protocol **dispatcher** (`dispatch: :dispatcher`, ADR-0042) lowers to a Kotlin
    # `when (a0)` over the receiver's runtime type (`is Long`/`is Bag` → the matching
    # `impl_…`). An **associated type** (ADR-0074) in a covariant `Vec(...)` return erases
    # to `List<Any>` (`Foldable.to_list() Vec(Elem)` reaches `:jvm`); only an assoc in a
    # *non*-covariant position (a bare `Elem` return / an `Elem` parameter) has no Kotlin
    # shape, so that dispatcher is dropped and `Rian.Reach` keeps it + its consumers off
    # `:jvm` (`assoc_blocks_jvm?`, mirrored in `Rian.Reach`).
    all = all_funcs(prog)

    impl_first_type =
      for f <- all, f.dispatch == :impl, into: %{}, do: {f.name, hd(f.params).type}

    assoc_names = jvm_assoc_names(prog)
    {dispatchers, funcs} = Enum.split_with(all, &(&1.dispatch == :dispatcher))
    dispatchers = Enum.reject(dispatchers, &assoc_blocks_jvm?(&1, assoc_names))
    Core.reject_unsupported!(funcs, @jvm_unsupported, :jvm, Unsupported)
    # the type-directed coercion pass (ADR-0074) needs: which lowered dispatchers were
    # erased to `List<Any>` (an associated type in a covariant `Vec(...)` return), and
    # each callee's parameter types — so a `List<Any>` flowing into a concrete `List<T>`
    # param gets an `as List<T>` cast. Threaded via `ic` (already passed everywhere).
    erased =
      for(
        d <- dispatchers,
        type_mentions_assoc?(d.ret, assoc_names),
        into: MapSet.new(),
        do: d.name
      )

    sigs = Map.new(all, fn f -> {{f.name, length(f.params)}, Enum.map(f.params, & &1.type)} end)
    type_decls = Enum.map_join(all_types(prog), "\n\n", &sum_decl/1)
    # a `struct Name(f Type, …)` (ADR-0043) → a standalone Kotlin `data class` with
    # named fields (a product type, no sealed supertype).
    struct_decls = Enum.map_join(all_structs(prog), "\n\n", &struct_decl/1)
    # `const NAME := value` (ADR-0033) lowers to a top-level `val`, and a reference
    # resolves to it — threaded through `ic[:consts]` (parity with `Rian.Beam`/
    # `Rian.Lower`); without this a const reference emitted as an unresolved Kotlin
    # identifier (a silent miscompile).
    consts = all_consts(prog)
    # the program inference context types each clause body's core IR (ADR-0050 §3).
    ic =
      Rian.Check.program_ic(prog)
      |> Map.put(:consts, MapSet.new(consts, & &1.name))
      |> Map.put(:jvm_sigs, sigs)
      |> Map.put(:jvm_erased, erased)
      # ctor → field-label info (ADR-0049 §3b): a labeled variant lowers to a `data class`
      # with named fields, and its patterns bind `acc.radius` not `acc.f0`.
      |> Map.put(:vmeta, Rian.VariantLabels.meta(prog))

    const_decls = Enum.map_join(consts, "\n", &const_kt(&1, ic))
    fn_decls = Enum.map_join(funcs, "\n\n", &function_kt(&1, ic))

    disp_decls =
      Enum.map_join(dispatchers, "\n\n", &dispatcher_kt(&1, impl_first_type, assoc_names))

    # inject the float-repr helper only when the program lowers `__prim_float_repr`.
    runtime =
      if String.contains?(fn_decls, "__rian_float_repr("), do: float_repr_helper(), else: ""

    [runtime, type_decls, struct_decls, const_decls, fn_decls, disp_decls]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # the associated-type names declared across the program's protocols (ADR-0074).
  defp jvm_assoc_names(prog),
    do: prog |> Map.get(:protocols, []) |> Enum.flat_map(&Map.get(&1, :assoc, [])) |> MapSet.new()

  # Can the JVM NOT lower a dispatcher because of an associated type? Only when the
  # associated type appears somewhere it can't be erased to `Any`: a **parameter**
  # (contravariant) or a **bare / non-`Vec` return**. Inside a covariant `Vec(...)`
  # return it erases fine — `Vec(Elem)` → `List<Any>` (Kotlin `List` is covariant), so a
  # `Foldable.to_list() Vec(Elem)` dispatcher lowers and reaches `:jvm` (ADR-0074;
  # element-AGNOSTIC consumers only — an element-typed use needs a use-site cast). The
  # `Vec(...)` wrapper is stripped before the check so its assoc occurrences don't count.
  defp assoc_blocks_jvm?(func, assoc) do
    param_types = func |> Map.get(:params, []) |> Enum.map(& &1.type)
    ret_bare = func.ret |> to_string() |> String.replace(~r/Vec\([^()]*\)/, "")
    Enum.any?([ret_bare | param_types], &type_mentions_assoc?(&1, assoc))
  end

  defp type_mentions_assoc?(nil, _assoc), do: false

  defp type_mentions_assoc?(t, assoc),
    do: Enum.any?(assoc, &Regex.match?(~r/\b#{Regex.escape(&1)}\b/, t))

  # substitute each associated-type name with `Any` (the erased Kotlin type) — turns a
  # dispatcher's `Vec(Elem)` return into `Vec(Any)` → `List<Any>` via `kt_type`.
  defp subst_assoc_any(type, assoc),
    do: Enum.reduce(assoc, type, &Regex.replace(~r/\b#{Regex.escape(&1)}\b/, &2, "Any"))

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
  @rian_sig "pub def to_jar(src String, jar_path String) _Unk"
  @rian_sig "pub def to_jar(src String, jar_path String, opts _Unk) _Unk"
  @rian_host "host boundary: invokes `kotlinc` and cleans up a temp `.kt` file (try/after) — :ex-only host I/O, no Rian image"
  @spec to_jar(String.t(), String.t(), keyword()) :: {:ok, String.t()}
  def to_jar(src, jar_path, opts \\ []) do
    kotlinc =
      case System.find_executable("kotlinc") do
        nil ->
          raise(
            RuntimeError,
            "`kotlinc` not found on PATH — needed to assemble a JVM .jar (ADR-0049 Tier 2)"
          )

        v ->
          v
      end

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

  defp all_structs(prog),
    do: Map.get(prog, :structs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.structs)

  # a `struct Name(f Type, …)` → `data class Name(val f: T, …)` (named fields, no
  # sealed supertype). Construction is by named args; a field access `p.f` and a
  # struct pattern read the data-class properties.
  defp struct_decl(s) do
    params = Enum.map_join(s.fields, ", ", fn f -> "val #{f.label}: #{kt_type(f.type)}" end)
    "data class #{s.name}(#{params})"
  end

  # ── sum type -> a Kotlin sealed hierarchy ───────────────────────────────
  # a single-variant sum whose ctor name **is** the type name (`type Bag := Bag(items …)`,
  # the common newtype/wrapper shape) — emit just the standalone data class. A
  # `sealed interface Bag` + `data class Bag : Bag` would be a Kotlin redeclaration (and
  # a self-supertype); with one variant the interface is unnecessary anyway, and `is Bag`
  # / construction / field access all resolve to the one `Bag`.
  defp sum_decl(%{name: name, variants: [%{ctor: name} = v]}), do: variant_body(v)

  defp sum_decl(t) do
    variants = Enum.map_join(t.variants, "\n", &variant_decl(&1, t.name))
    "sealed interface #{t.name}\n#{variants}"
  end

  # a nullary variant is a singleton `object`; an arg-carrying one a `data class`
  # with its declared field names (`radius`), falling back to positional `f0, f1, …`
  # for an anonymous field (ADR-0049 §3b).
  defp variant_decl(v, tname), do: "#{variant_body(v)} : #{tname}"

  # the data class / object for a variant, without the `: SealedInterface` supertype.
  defp variant_body(%{ctor: ctor, fields: []}), do: "object #{ctor}"

  defp variant_body(%{ctor: ctor, fields: fields}) do
    params =
      fields
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {f, i} ->
        "val #{field_key(Map.get(f, :label), i)}: #{kt_type(f.type)}"
      end)

    "data class #{ctor}(#{params})"
  end

  # the Kotlin field name for a variant's i-th field: its declared label, else `f<i>`.
  defp field_key(nil, i), do: "f#{i}"
  defp field_key(label, _i), do: label

  # the i-th declared label, or `nil` when the variant has no labels (anonymous
  # fields) — pattern-matched off the nilable list rather than a truthy `&&`.
  defp label_at(nil, _i), do: nil
  defp label_at(labels, i), do: Enum.at(labels, i)

  # ── function / clause dispatch ──────────────────────────────────────────
  # an `@external` function (ADR-0068): emit the `:jvm` host body verbatim, binding
  # each param to its positional argument by name. No `:jvm` body -> off `:jvm`.
  defp function_kt(%{externals: ext} = f, _ic) when map_size(ext) > 0 do
    host =
      case Map.get(ext, :jvm) do
        nil ->
          raise Unsupported, "`#{f.name}`: no `@external(:jvm, …)` body — not reachable on :jvm"

        # a file-reference calls the foreign top-level function (the build copies the
        # `.ffi.kt` into the same package, compiled together); params passed by name.
        {:file, _path, fun} ->
          "#{fun}(#{Enum.map_join(f.params, ", ", & &1.name)})"

        spec ->
          Rian.External.render(spec, f.params)
      end

    sig =
      f.params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {p, i} -> "a#{i}: #{kt_type(p.type)}" end)

    binds =
      f.params
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {p, i} -> "val #{p.name} = a#{i};" end)

    vis = if f.pub?, do: "", else: "private "
    "#{vis}fun #{f.name}(#{sig}): #{kt_type(f.ret)} { #{binds} return #{host} }"
  end

  defp function_kt(%{name: name, clauses: clauses, ret: ret, params: params, pub?: pub?} = f, ic) do
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

    "#{vis}fun #{generics_kt(f)}#{name}(#{sig_params}): #{kt_type(ret)} {\n#{lines}#{tail}}"
  end

  # A runtime protocol dispatcher (`dispatch: :dispatcher`, ADR-0042) lowers to a
  # `when (a0)` over the receiver's runtime type: one `is <KotlinType> -> impl_…(…)`
  # arm per impl, ending in an `else -> throw`. The dispatch parameter(s) are typed
  # `Any` (the dispatch is dynamic); the `is` test smart-casts the receiver `a0`, and a
  # further `Self`-typed argument is `as`-cast to the matched type (every `Self` arg has
  # the same runtime type as the receiver). The `is`-test type is `impl_…`'s first
  # parameter type rendered through `kt_type` (`Int53` → `Long`, a sum/struct → its
  # class), recovered from the clause's `impl_…(…)` call.
  defp dispatcher_kt(disp, impl_first_type, assoc) do
    params =
      disp.params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {p, i} ->
        "a#{i}: #{if p.type == "Self", do: "Any", else: kt_type(p.type)}"
      end)

    arms =
      Enum.map_join(disp.clauses, "\n", fn c ->
        impl = dispatch_impl_name(c.body)
        kt_dtype = kt_type(impl_first_type[impl])
        args = dispatch_args(disp.params, kt_dtype)
        "    is #{kt_dtype} -> #{impl}(#{args})"
      end)

    vis = if Map.get(disp, :pub?, true), do: "", else: "private "
    miss = inspect("#{disp.name}: no matching impl")
    # an associated type in a covariant `Vec(...)` return erases to `List<Any>` (the
    # `impl_…` arms return `List<Long>`/`List<String>`, covariantly `List<Any>`).
    ret = kt_type(subst_assoc_any(disp.ret, assoc))

    "#{vis}fun #{disp.name}(#{params}): #{ret} = when (a0) {\n#{arms}\n" <>
      "    else -> throw RuntimeException(#{miss})\n}"
  end

  # the impl call's arguments: the receiver `a0` is smart-cast by the `is` test; any
  # other `Self`-typed argument is `as`-cast to the matched type; non-`Self` args pass
  # through. (`Rian` dispatches on the first argument — ADR-0042 — so `a0` is the receiver.)
  defp dispatch_args(params, kt_dtype) do
    params
    |> Enum.with_index()
    |> Enum.map_join(", ", fn
      {_p, 0} -> "a0"
      {%{type: "Self"}, i} -> "a#{i} as #{kt_dtype}"
      {_p, i} -> "a#{i}"
    end)
  end

  # recover the impl function name from a dispatcher clause body (`impl_eq_int53_eq(v0,
  # v1)`); the arguments are reconstructed from the dispatcher's own params (`a0`, `a1`).
  defp dispatch_impl_name(body) do
    [_, name] = Regex.run(~r/^\s*([a-z_][\w]*)\s*\(/, body)
    name
  end

  # a generic function (`forall T`, ADR-0042) declares its type variables as Kotlin
  # generics: `def len_l(Vec(T)) … forall T` -> `fun <T> len_l(a0: List<T>): Long`.
  # Without the `<T>` declaration a `T` in the signature is an unresolved reference
  # (kotlinc error) — so an un-declared generic was a `:jvm` reach lie. Bounds are not
  # rendered: a Rian `T: Eq` bound is satisfied by the runtime protocol dispatcher (a
  # `when (v0)` over the value's type), not a Kotlin `where` clause.
  defp generics_kt(f) do
    case Map.get(f, :tvars, []) do
      [] ->
        ""

      tvars ->
        # bound each tvar `: Any` (non-null): Rian values are never null, and an
        # unbounded Kotlin `<T>` is `T : Any?`, which would not fit a protocol
        # dispatcher's non-null `Any` parameter (`eq(a0: Any, …)`).
        "<#{Enum.map_join(tvars, ", ", &"#{&1} : Any")}> "
    end
  end

  # Emit clauses top-to-bottom; an unconditional clause (no tests, no guard)
  # always matches, so it closes the function — return without emitting the rest
  # (or the trailing throw, which Kotlin would flag as unreachable). Dispatching
  # on the guard and recursing — rather than threading a `{acc, closed?}` tuple
  # through `reduce_while` — lets "closes" be "don't recurse" instead of `:halt`.
  defp clause_lines([], _params, _ic), do: {"", false}

  defp clause_lines([c | rest], params, ic) do
    {tests, binds} = clause_match(c.pats, ic)
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

  defp clause_match(pats, ic) do
    vmeta = Map.get(ic, :vmeta, %{})

    pats
    |> Enum.map(&(&1 |> Core.from_pat() |> Rian.VariantLabels.bake_pats(vmeta)))
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

  # an as-pattern `name @ pat` (ADR-0050): bind `name` to the whole scrutinee AND
  # match the inner pattern against it.
  defp pat_match(%PAs{name: n, pat: p}, acc) do
    {ts, bs} = pat_match(p, acc)
    {ts, [{n, acc} | bs]}
  end

  # a pin `^x` (ADR-0050): match when the scrutinee equals the pinned value — an
  # `==` test, no bind. Only `^var` is supported (as on the BEAM).
  defp pat_match(%PPin{expr: {:id, name}}, acc), do: {["#{acc} == #{name}"], []}

  defp pat_match(%PPin{expr: e}, _acc),
    do: raise(Unsupported, "jvm: pin `^#{inspect(e)}` (only `^var` is supported)")

  # a type-pattern `n Type` (ADR-0083): test the runtime type (`is Long`/`is String`,
  # the dispatcher discriminator) and bind the scrutinee — Kotlin smart-casts it to
  # the tested type inside the `is` block (the dispatcher relies on the same).
  defp pat_match(%PTyped{name: n, tname: t}, acc),
    do: {["#{acc} is #{kt_type(t)}"], [{n, acc}]}

  defp pat_match(%PLit{value: v}, acc), do: {["#{acc} == #{lit_kt(v)}"], []}
  # a `Symbol` pattern (`:ok`) tests the interned name as a Kotlin `String` (ADR-0041).
  defp pat_match(%PAtom{name: a}, acc), do: {["#{acc} == #{kt_str(a)}"], []}
  defp pat_match(%PChar{value: cp}, acc), do: {["#{acc} == #{cp}L"], []}

  defp pat_match(%PCtor{ctor: ctor, args: args, labels: labels}, acc) do
    {ts, bs} =
      args
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}.#{field_key(label_at(labels, i), i)}")
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

  # a tuple pattern destructures a `Pair`/`Triple` via `componentN()` — no shape
  # test (the static type guarantees arity). Tagged/≥4 tuples are unsupported, as in
  # construction.
  defp pat_match(%PTuple{elems: [%PAtom{} | _]}, _acc),
    do: raise(Unsupported, "jvm: a tagged tuple pattern (`{:tag, …}`) is BEAM-only")

  defp pat_match(%PTuple{elems: ps}, acc) when length(ps) in [2, 3] do
    ps
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
      {t, b} = pat_match(p, "(#{acc}).component#{i}()")
      {ts ++ t, bs ++ b}
    end)
  end

  defp pat_match(%PTuple{elems: ps}, _acc),
    do: raise(Unsupported, "jvm: a #{length(ps)}-tuple pattern (Pair/Triple cover 2/3)")

  # a struct pattern `Name(f: pat, …)` (ADR-0043): test `is Name` (Kotlin then
  # smart-casts the scrutinee), then match each named field via its data-class
  # property `acc.f` (recursing for nested patterns).
  defp pat_match(%PStruct{name: name, fields: fields}, acc) do
    {ts, bs} =
      Enum.reduce(fields, {[], []}, fn {f, p}, {ts, bs} ->
        {t, b} = pat_match(p, "(#{acc} as #{name}).#{f}")
        {ts ++ t, bs ++ b}
      end)

    {["#{acc} is #{name}" | ts], bs}
  end

  # a map pattern `%{k: p, …}` over a Kotlin `Map`: each atom key tests `containsKey`
  # and matches its value (`getValue`); an empty `%{}` matches any map. A non-atom
  # (computed) key is BEAM-only (ADR-0033).
  defp pat_match(%PMap{pairs: pairs}, acc) do
    Enum.reduce(pairs, {[], []}, fn
      {{:key, _k}, _p}, _a ->
        raise(Unsupported, "jvm: a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)")

      {key, p}, {ts, bs} ->
        ks = kt_str(to_string(key))
        {t, b} = pat_match(p, "(#{acc}).getValue(#{ks})")
        {ts ++ ["(#{acc}).containsKey(#{ks})" | t], bs ++ b}
    end)
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
      # fill `case`-arm ctor patterns' field labels (ADR-0049 §3b) so they bind `.radius`.
      |> Rian.VariantLabels.bake_pats(Map.get(ic, :vmeta, %{}))

    stmts
    |> Rian.Shadow.dedup(params, &kt_fresh/2)
    |> coerce_stmts(ic)
    |> block_value()
  end

  defp kt_fresh(base, count), do: "`" <> base <> "$" <> Integer.to_string(count) <> "`"

  # ── JVM type-directed coercion pass (the seed of a general pass, ADR-0074) ──────────
  # An erased associated-type dispatcher returns `List<Any>`, but a concrete-typed callee
  # param expects `List<T>` — `sum_l(to_list(b))` where `to_list` is erased and `sum_l`
  # takes `Vec(Int53)`; Kotlin `List<Any>` is not a `List<Long>`, so insert `as List<T>`.
  # The cast target is read from the CALLEE's parameter type (the conservative checker
  # leaves the erased call `:unknown`). Runs over the annotated body before `expr_kt`;
  # today it carries the one rule the associated-type story needs, structured so further
  # rules slot in. (`ic` carries `:jvm_sigs` / `:jvm_erased`, set in `compile/1`.)
  defp coerce_stmts(stmts, ic), do: coerce_stmts(stmts, ic, MapSet.new())

  # thread `env` — the set of locals bound to an (uncast) erased dispatcher result
  # (`List<Any>`) — across the statement sequence, so a later concrete-typed consumer of
  # one (`xs := to_list(b) ; sum_l(xs)`) gets the same `as List<T>` cast a direct
  # dispatcher-call argument would. Without it the bound `List<Any>` flows into a
  # `List<Long>` param uncast and kotlinc rejects it — yet Reach claims `:jvm`, an
  # honesty gap; the cast keeps the claim true for the bound form too.
  defp coerce_stmts(stmts, ic, env) do
    {rev, _env} =
      Enum.reduce(stmts, {[], env}, fn s, {acc, env} ->
        {s2, env2} = coerce_stmt(s, ic, env)
        {[s2 | acc], env2}
      end)

    Enum.reverse(rev)
  end

  defp coerce_stmt({:bind, n, e}, ic, env),
    do: {{:bind, n, coerce_casts(e, ic, env)}, bind_env(n, e, ic, env)}

  defp coerce_stmt({:typed_bind, n, t, e}, ic, env),
    do: {{:typed_bind, n, t, coerce_casts(e, ic, env)}, bind_env(n, e, ic, env)}

  defp coerce_stmt({:expr, e}, ic, env), do: {{:expr, coerce_casts(e, ic, env)}, env}

  # a binding whose RHS is a bare erased-dispatcher call holds a `List<Any>` — track the
  # name; any other RHS clears a prior tracking (`:=` rebind, shadow-deduped already).
  defp bind_env(n, %ECall{fun: %EId{name: g}}, ic, env) do
    if MapSet.member?(Map.get(ic, :jvm_erased, MapSet.new()), g),
      do: MapSet.put(env, n),
      else: MapSet.delete(env, n)
  end

  defp bind_env(n, _e, _ic, env), do: MapSet.delete(env, n)

  defp coerce_casts(%ECall{args: args} = call, ic, env) do
    args = Enum.map(args, &coerce_casts(&1, ic, env))
    args = if match?(%EId{}, call.fun), do: cast_args(call.fun.name, args, ic, env), else: args
    %{call | args: args}
  end

  defp coerce_casts(%EBin{left: l, right: r} = n, ic, env),
    do: %{n | left: coerce_casts(l, ic, env), right: coerce_casts(r, ic, env)}

  defp coerce_casts(%EUnary{arg: a} = n, ic, env), do: %{n | arg: coerce_casts(a, ic, env)}

  defp coerce_casts(%EIf{cond: c, then: t, else: e} = n, ic, env),
    do: %{
      n
      | cond: coerce_casts(c, ic, env),
        then: coerce_casts(t, ic, env),
        else: coerce_casts(e, ic, env)
    }

  defp coerce_casts(%EList{elems: elems, tail: tail} = n, ic, env),
    do: %{
      n
      | elems: Enum.map(elems, &coerce_casts(&1, ic, env)),
        tail: if(tail == :close, do: :close, else: coerce_casts(tail, ic, env))
    }

  defp coerce_casts(%ECase{scrut: s, arms: arms} = n, ic, env),
    do: %{
      n
      | scrut: coerce_casts(s, ic, env),
        arms: Enum.map(arms, fn {p, g, b} -> {p, g, coerce_casts(b, ic, env)} end)
    }

  defp coerce_casts(%EDot{head: h} = n, ic, env), do: %{n | head: coerce_casts(h, ic, env)}

  defp coerce_casts(%EBlock{stmts: stmts} = n, ic, env),
    do: %{n | stmts: coerce_stmts(stmts, ic, env)}

  defp coerce_casts(leaf, _ic, _env), do: leaf

  # cast each erased value (a direct dispatcher call, or a local bound to one) flowing
  # into a concrete `Vec(...)` param of callee `f`.
  defp cast_args(f, args, ic, env) do
    erased = Map.get(ic, :jvm_erased, MapSet.new())

    case Map.get(ic, :jvm_sigs, %{})[{f, length(args)}] do
      nil ->
        args

      ptypes ->
        Enum.zip(args, ptypes) |> Enum.map(fn {a, pt} -> maybe_cast(a, pt, erased, env) end)
    end
  end

  # a direct erased-dispatcher call flowing into a concrete `Vec(...)` param.
  defp maybe_cast(%ECall{fun: %EId{name: g}} = arg, "Vec(" <> _ = pt, erased, _env),
    do: cast_if_concrete(arg, pt, MapSet.member?(erased, g))

  # a local bound to an erased dispatcher result (`xs := to_list(b)`) used the same way.
  defp maybe_cast(%EId{name: v} = arg, "Vec(" <> _ = pt, _erased, env),
    do: cast_if_concrete(arg, pt, MapSet.member?(env, v))

  defp maybe_cast(arg, _pt, _erased, _env), do: arg

  # cast to `List<elem>` only when the param's element type is CONCRETE: a `Vec(T)` param
  # with a tvar `T` already accepts the erased `List<Any>` (Kotlin infers `T = Any`), and
  # `as List<T>` would reference an undeclared `T` at the call site.
  defp cast_if_concrete(arg, pt, erased?) do
    inner = vec_inner(pt)

    if erased? and not tvar_kt?(inner),
      do: {:jvm_cast, arg, "List<#{kt_type(inner)}>"},
      else: arg
  end

  # the element type of a `Vec(T)` type string (`Vec(Int53)` -> `Int53`).
  defp vec_inner("Vec(" <> rest), do: String.replace_suffix(rest, ")", "")

  # a bare type variable (`T`, `C`, `U2`) — single uppercase letter + optional digits.
  defp tvar_kt?(t), do: String.match?(t, ~r/^[A-Z][0-9]*$/)

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
  # a `Symbol` value (`:foo`) lowers to its interned name as a Kotlin `String` (ADR-0041).
  defp expr_kt(%EAtom{name: a}), do: kt_str(a)
  defp expr_kt(%EId{name: b}) when b in ~w(true false), do: b
  # a bare PascalCase id is a nullary sum variant -> its singleton `object`
  defp expr_kt(%EId{name: x}), do: x
  defp expr_kt(%EUnary{op: "-", arg: x}), do: "-#{expr_kt(x)}"
  defp expr_kt(%EUnary{op: "not", arg: x}), do: "!#{expr_kt(x)}"
  defp expr_kt(%EBin{op: op, left: l, right: r}), do: "(#{expr_kt(l)} #{kt_op(op)} #{expr_kt(r)})"

  # diverging abort (ADR-0035/0040): Kotlin `throw` is an expression of type
  # `Nothing`, so `panic` lowers directly (no IIFE wrapper needed, unlike JS).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_panic"}, args: [msg]}),
    do: "throw RuntimeException(#{expr_kt(msg)})"

  # integer → string (ADR-0069 interpolation): Kotlin `Long.toString()`
  defp expr_kt(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}),
    do: "(#{expr_kt(n)}).toString()"

  # runtime `Show` fallthrough for an `:unknown`-typed hole (ADR-0069 §2): Kotlin
  # `.toString()` is universal (every value has it).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_to_string"}, args: [x]}),
    do: "(#{expr_kt(x)}).toString()"

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

  # ── `Dict`/`Map` ops (ADR-0047) — Kotlin immutable `Map` ─────────────────
  # `Map.get` returns `V` (the prelude contract, not `V?`), so use `getValue`
  # (throws on a missing key, matching the BEAM/JS "assume present" semantics — a
  # caller guards with `has`/`get_or`). `put` returns a NEW map (`m + (k to v)`).
  defp expr_kt(%ECall{fun: %EId{name: "__prim_map_new"}, args: []}), do: "mapOf()"

  defp expr_kt(%ECall{fun: %EId{name: "__prim_map_get"}, args: [m, k]}),
    do: "(#{expr_kt(m)}).getValue(#{expr_kt(k)})"

  defp expr_kt(%ECall{fun: %EId{name: "__prim_map_put"}, args: [m, k, v]}),
    do: "((#{expr_kt(m)}) + (#{expr_kt(k)} to #{expr_kt(v)}))"

  defp expr_kt(%ECall{fun: %EId{name: "__prim_map_has"}, args: [m, k]}),
    do: "(#{expr_kt(m)}).containsKey(#{expr_kt(k)})"

  # direct `Map.get`/`Map.put`/`Map.has` calls (the prelude `Dict` wrappers route
  # through the prims above; user code may call `Map.*` directly — ADR-0047).
  defp expr_kt(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "get"}, args: [m, k]}),
    do: "(#{expr_kt(m)}).getValue(#{expr_kt(k)})"

  defp expr_kt(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "put"}, args: [m, k, v]}),
    do: "((#{expr_kt(m)}) + (#{expr_kt(k)} to #{expr_kt(v)}))"

  defp expr_kt(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "has"}, args: [m, k]}),
    do: "(#{expr_kt(m)}).containsKey(#{expr_kt(k)})"

  # a map literal `%{k: v, …}` (atom keys → `String` keys, ADR-0033/0041) → `mapOf`.
  defp expr_kt(%EMap{pairs: pairs}),
    do: "mapOf(#{Enum.map_join(pairs, ", ", &kt_map_pair/1)})"

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
       when mod not in ~w(Map String),
       do: "#{fun}(#{Enum.map_join(args, ", ", &expr_kt/1)})"

  # struct construction `Name(f: v, …)` (ADR-0043): labelled call args → a Kotlin
  # data-class constructor with named arguments (`Name(f = v, …)`).
  defp expr_kt(%ECall{fun: %EId{name: f}, args: [%ELabel{} | _] = args}) do
    fields = Enum.map_join(args, ", ", fn %ELabel{name: l, expr: e} -> "#{l} = #{expr_kt(e)}" end)
    "#{f}(#{fields})"
  end

  # a resolved struct literal (the `Rian.Lower` resolve passes produce `EStruct`).
  defp expr_kt(%EStruct{name: name, pairs: pairs}) do
    fields = Enum.map_join(pairs, ", ", fn {l, v} -> "#{l} = #{expr_kt(v)}" end)
    "#{name}(#{fields})"
  end

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

  # a tuple `{a, b}` / `{a, b, c}` → a Kotlin `Pair`/`Triple` (the idiomatic 2-/3-
  # tuple, destructured via `componentN`). A tagged tuple `{:ok, v}` is a Result/AST
  # node (BEAM-only on :jvm, ADR-0040); arity ≥4 has no Kotlin form yet.
  defp expr_kt(%ETuple{elems: [%EAtom{} | _]}),
    do:
      raise(Unsupported, "a tagged tuple (`{:tag, …}` — a Result/AST node) is BEAM-only on :jvm")

  defp expr_kt(%ETuple{elems: [a, b]}), do: "Pair(#{expr_kt(a)}, #{expr_kt(b)})"

  defp expr_kt(%ETuple{elems: [a, b, c]}),
    do: "Triple(#{expr_kt(a)}, #{expr_kt(b)}, #{expr_kt(c)})"

  defp expr_kt(%ETuple{elems: es}),
    do:
      raise(
        Unsupported,
        "a #{length(es)}-tuple has no Kotlin form (Pair/Triple cover 2/3; use a struct)"
      )

  # a type-directed cast inserted by `coerce_casts` (ADR-0074): bridge an erased
  # dispatcher's `List<Any>` to the concrete `List<T>` a callee expects.
  defp expr_kt({:jvm_cast, inner, t}), do: "(#{expr_kt(inner)} as #{t})"

  # a lambda `(a, b) -> body` → a Kotlin lambda `{ a, b -> body }` (a zero-arg
  # lambda is `{ body }`). The parameter types are inferred from the expected
  # function type at the use site (a `Fn(...)` param/return → `(T) -> U`), so they
  # stay implicit — idiomatic Kotlin. Closures capture their environment natively.
  defp expr_kt(%ELambda{params: [], body: body}), do: "{ #{branch_kt(body)} }"

  defp expr_kt(%ELambda{params: params, body: body}),
    do: "{ #{Enum.map_join(params, ", ", fn {n, _} -> n end)} -> #{branch_kt(body)} }"

  # a `with` expression desugars to a nest of `case`s (ADR-0040) — emit that.
  defp expr_kt(%EWith{clauses: clauses, body: body, els: els}),
    do: expr_kt(Core.desugar_with(clauses, body, els))

  # an anonymous capture `&(&1 * 2)` -> a Kotlin lambda over generated args `_1.._N`
  defp expr_kt(%ECapture{body: body}),
    do: "{ #{Enum.map_join(1..Core.cap_arity(body)//1, ", ", &"_#{&1}")} -> #{branch_kt(body)} }"

  defp expr_kt(%ECapArg{n: n}), do: "_#{n}"

  # `&name/arity` -> a Kotlin function reference `::name` (idiomatic); `&Mod.fun/arity`
  # -> a forwarding lambda (a remote name has no bare `::` reference here).
  defp expr_kt(%ECaptureNamed{path: %EId{name: n}}), do: "::#{n}"

  defp expr_kt(%ECaptureNamed{path: path, arity: a}) do
    ps = Enum.map_join(0..(a - 1)//1, ", ", &"_a#{&1}")
    "{ #{ps} -> #{expr_kt(path)}(#{ps}) }"
  end

  # bare struct field access `value.field` (a remote call `Mod.fun(…)` is an `ECall`
  # over an `EDot`, handled above; a standalone `EDot` here is data-class field access).
  defp expr_kt(%EDot{head: head, name: field}), do: "#{expr_kt(head)}.#{field}"

  # a block in expression position (a `do…end` as an arg/arm value) -> a `run { … }`,
  # the same form `branch_kt` produces for `if`/`case` branches.
  defp expr_kt(%EBlock{} = b), do: branch_kt(b)

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

  # one `mapOf` pair. An atom-key shorthand `k: v` → `"k" to v` (the key is the
  # interned atom name as a `String`, ADR-0041); a non-atom key has no faithful
  # Kotlin-map lowering and is BEAM-only (ADR-0033).
  defp kt_map_pair({{:key, _k}, _v}),
    do: raise(Unsupported, "a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)")

  defp kt_map_pair({k, v}), do: "#{kt_str(to_string(k))} to #{expr_kt(v)}"

  # ── helpers ─────────────────────────────────────────────────────────────
  # Int64 -> a Kotlin `Long` literal (`42L`); a Float64 literal is a Kotlin Double
  defp num_kt(n), do: if(float?(n), do: n, else: "#{n}L")

  defp lit_kt(v) when is_integer(v), do: "#{v}L"
  defp lit_kt(v) when is_binary(v), do: kt_str(v)

  # render a decoded `String` value as a Kotlin double-quoted literal. Beyond the
  # quote/backslash and common control chars, Kotlin needs `$` escaped (string
  # templates) and uses fixed four-digit `\uHHHH` for other control codepoints.
  defp kt_str(s),
    do: ~s(") <> for(cp <- String.to_charlist(s), into: "", do: kt_str_cp(cp)) <> ~s(")

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
  # Kotlin has a native `in` operator (membership): `x in list` calls `contains`.
  defp kt_op("in"), do: "in"
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

      # a `Symbol` (`:foo`) is an interned-name `String` off the BEAM (ADR-0041).
      t == "Symbol" ->
        "String"

      t == "Char" ->
        "Long"

      m = Regex.run(~r/^Vec\((.+)\)$/, t) ->
        "List<#{kt_type(Enum.at(m, 1))}>"

      # a `Dict(K, V)` (ADR-0047 map type) → a Kotlin `Map<K, V>`. Atom keys lower to
      # `String` (ADR-0041), so a `Dict(Symbol, V)` is a `Map<String, V>`.
      m = Regex.run(~r/^Dict\((.+)\)$/, t) ->
        [k, v] = Rian.TypeStr.split_top_commas(Enum.at(m, 1))
        "Map<#{kt_type(k)}, #{kt_type(v)}>"

      # a function type `Fn(arg…, ret)` (ADR-0061) → a Kotlin function type
      # `(arg…) -> ret`; the LAST top-level component is the return, the rest are
      # parameters (`Fn(Int53, Int53)` → `(Long) -> Long`, `Fn(Int53)` → `() -> Long`).
      m = Regex.run(~r/^Fn\((.+)\)$/, t) ->
        {params, [ret]} = Rian.TypeStr.split_top_commas(Enum.at(m, 1)) |> Enum.split(-1)
        "(#{Enum.map_join(params, ", ", &kt_type/1)}) -> #{kt_type(ret)}"

      # a tuple type `(A, B)` / `(A, B, C)` → a Kotlin `Pair`/`Triple` (the idiomatic
      # 2-/3-tuple). A tuple type starts with `(` — distinct from `Fn(`/`Vec(`/a
      # nominal type. Arity ≥4 has no Kotlin form yet (use a struct).
      m = Regex.run(~r/^\((.+)\)$/, t) ->
        case Rian.TypeStr.split_top_commas(Enum.at(m, 1)) do
          [a, b] ->
            "Pair<#{kt_type(a)}, #{kt_type(b)}>"

          [a, b, c] ->
            "Triple<#{kt_type(a)}, #{kt_type(b)}, #{kt_type(c)}>"

          parts ->
            raise(
              Unsupported,
              "jvm: a #{length(parts)}-tuple type `#{t}` (Pair/Triple cover 2/3)"
            )
        end

      # a value union `Union(A, B)` (ADR-0083) erases to `Any` — a member value
      # *is-a* `Any` (no wrapping needed, unlike Rust); a type-pattern narrows it back.
      String.starts_with?(t, "Union(") ->
        "Any"

      String.match?(t, ~r/^[A-Z]/) ->
        t

      true ->
        raise(Unsupported, "jvm: type `#{t}`")
    end
  end
end
