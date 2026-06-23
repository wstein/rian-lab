defmodule Rian.JS do
  use Rian.Ann

  @moduledoc """
  ECMAScript emitter (ADR-0049 Tier 1) — a **direct** JS source emitter built on
  the **typed core IR** (`Rian.Core`, ADR-0050): it consumes `Core.from_expr` /
  `Core.from_pat`, never the surface tuples. Being a fresh emitter on the core is
  the ADR-0050 thesis in practice — a third backend without a fourth fork.

  The backend has **two print modes** over one lowering (ADR-0086 §5):
  `compile/1` emits the runtime ECMAScript module, and `compile_types/1` emits a
  TypeScript declaration sidecar (`.d.mts`) describing the same module's exported
  surface — the typed *view* a TS consumer checks across the FFI boundary.

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
  catches it first. The number/BigInt mode is **whole-program**: the whole module is
  uniformly native (`Int53`/`Int32`) or uniformly BigInt (`Int`), the two never mix
  (`reject_mixed_int_mode!`). `compile/1` computes the mode once and threads it
  through the emitter as the boolean `i53` (`true` = native `number`).

  ## Scope (this increment)

  Functions (single/multi-clause) over `Int64`/`Float64`/`Bool`; variables;
  unary/binary operators; `if`; local calls; tuples (→ JS arrays); `when`
  guards; **sum variants** — construction `Ctor(a, …)` → a tagged object
  `{ $: "Ctor", _0: a, … }` (nullary → `{ $: "Ctor" }`; positional `_n` field keys),
  with **clause patterns** that check the `$` tag and recurse into fields
  (nested + literal patterns supported). A tagged object (not the old array)
  distinguishes a variant from a list/tuple and is consistent with structs;
  **lists** (→ JS arrays, cons `[h | t]` → `[h, ...t]`, with closed/cons clause
  patterns via `length`/`slice`); **`case`** (→ an IIFE if-chain over the arm
  patterns); **strings** (`<>` → `+`); **maps** (`%{k: v}` → a JS object); and a
  small set of **stdlib calls** — a stopgap until the portable prelude (ADR-0047) —
  mapped to portable JS (`Map.get`/`Map.put` immutable, `String.to_charlist`,
  `List.to_string`, `:lists.reverse`) — a stopgap until the portable prelude
  (ADR-0047) owns them. **Protocol dispatch** (ADR-0061 §3): a `protocol` lowers
  to a JS dispatcher generated from the protocol IR — it selects the impl by the
  first argument's runtime shape (`typeof` for primitives, the variant `$` tag
  for sums), mirroring the BEAM strategy with JS-native guards; the `impl_*`
  methods lower as plain functions, and bounded generics are plain functions
  (the bound was checked statically and is erased). **Structs**: named
  construction `Name(f: v, …)` → a `__struct__`-tagged object `{__struct__:
  "Name", f: v}`, with field access `p.f` and struct clause patterns; struct
  protocol dispatch tests `a0.__struct__ === "Name"`. Atoms/`Symbol` (→ JS
  strings) and `Result` (`{:ok,v}`/`{:error,e}` → tagged arrays — a tuple, *not* a
  sum, so it stays an array — matched in a `case`) lower too. A **value union**
  `A | B` (ADR-0083) is narrowed by a type-pattern `n Int53 ->`: a primitive tests
  `typeof`, a sum the variant `$` tag, a struct `__struct__` — the discriminator is
  *baked into the pattern*
  (`bake_union_disc`) before emit, as the `expr_js` recursion threads no type
  registry. A **lambda** `(a) -> body` lowers to a JS arrow function `(a) => body`,
  capturing its environment natively (no `Box`/`move` ceremony as Rust needs —
  ADR-0061). A **capture** `&(&1 + 1)` lowers to an arrow over generated args
  (`(_1) => …`) and `&name/arity` to the bare function reference. A **`with`**
  expression desugars to a nest of `case`s (ADR-0040, via `Core.desugar_with`).
  **Not yet** (raise `Rian.JS.Unsupported`): bitstrings (BEAM-only, ADR-0078),
  general FFI.

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
    EConstRef,
    EDot,
    EId,
    EIf,
    ECapArg,
    ECapture,
    ECaptureNamed,
    ELambda,
    EList,
    EMap,
    EMapUpdate,
    ENum,
    EStr,
    EStruct,
    EVariant,
    ELabel,
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

  # Fast-fail diagnostic: before emitting, scan each function body for a construct
  # the JS emitter does not yet implement and raise ONE clear error naming the
  # function and construct — instead of a deep `inspect`-dump surfacing mid-emission.
  # Reach stays *architectural* (atoms/Result are portable per ADR-0041); this is an
  # *implementation-status* check, so it covers only constructs the emitter handles
  # in NO context (a bare atom is left to the emitter's own `Unsupported`, since an
  # atom inside an FFI call like `:lists.reverse` IS lowered). `Core.reject_unsupported!`
  # runs the shared walk; this map is the JS-specific construct→label set.
  @js_unsupported %{
    Core.EBitstr => "a bitstring (BEAM-only, ADR-0078)"
  }

  # The portable-prelude namespaces (ADR-0047) plus the built-in interop heads. A
  # qualified call into one of these is portable-by-design — either specially
  # lowered here (`Map.get`, `String.to_charlist`, `List.to_string`) or resolved
  # when the prelude is linked (`List.map`, `Dict.get`, `Str.chars`, `Show.float`) —
  # so it is NOT host FFI. Every OTHER qualified call (`Enum.map`, `Integer.to_string`,
  # `IO.puts`) must resolve to a program function; see `reject_unknown_module_calls!/2`.
  @js_portable_modules ~w(Map String Char List Dict Str Int Show)

  @doc "Compile `src`'s functions to a single ECMAScript module (a string)."
  @rian_sig "pub def compile(src String) String"
  @spec compile(String.t()) :: String.t()
  def compile(src), do: compile_prog(Decl.parse(src))

  @doc """
  Lower an already-parsed program (the `Decl.parse/1` shape) to a JS module — the post-parse
  half of `compile/1`. A multi-target driver (the by-example tour) parses once and lowers each
  target off the shared program (parse-once, lower-many), instead of re-parsing per target.
  """
  @rian_sig "pub def compile_prog(prog Prog) String"
  @spec compile_prog(map()) :: String.t()
  def compile_prog(prog) do
    # Run the full type gate first — parity with the BEAM path (`Decl.compile`),
    # which gates before emitting. Without this a real `Rian.Check` error stayed
    # latent on the JS path (commit 80f6929). A type error is now caught here, not
    # discovered as malformed JS downstream.
    :ok = Check.gate!(prog)
    # Erase abstract types to their base after the gate (ADR-0067): `opaque Token
    # := String` emits as the underlying `String`, and `Token.of(x)` -> `x`.
    prog = Rian.Opaque.erase(prog)
    # Integer mode is a WHOLE-PROGRAM decision, not per-function: integer values
    # (a depth counter, a codepoint) flow across function boundaries, and BigInt
    # and number cannot be combined in JS. A "neutral" function with no integer in
    # its own signature would otherwise default to BigInt and pass `0n` into a
    # number-mode callee. So if the program uses a JS-number width (`Int53`/`Int32`)
    # anywhere, the entire module emits in number-mode (ADR-0064).
    reject_mixed_int_mode!(prog)
    # `i53` (true = native `number`, false = `BigInt`) is a whole-program constant;
    # computed once and threaded through the emitter so the leaf literal/guard
    # emitters pick the right integer form without an ambient flag.
    i53 = program_number_mode?(prog)
    # the BEAM `:dispatcher` is a guarded runtime type-test — not the JS shape.
    # JS keeps the `:impl` methods (they lower as plain functions) and regenerates
    # the dispatcher with JS-native guards (ADR-0061 §3).
    funcs = prog |> all_funcs() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    Core.reject_unsupported!(funcs, @js_unsupported, :js, Unsupported)
    # A `Mod.fun(args)` call lowers to a bare `fun(args)` (modules flatten into one
    # file), which is correct only when `fun` is a program function. A host-module
    # call (`Enum.map`) or a wrong-arity stdlib call (`List.foo`) would otherwise
    # emit a dangling reference silently — so reject it here, before emit.
    known_fns = prog |> all_funcs() |> MapSet.new(& &1.name)
    reject_unknown_module_calls!(funcs, known_fns)
    # `const NAME := value` (ADR-0033) lowers to a top-level `const`, and a reference
    # resolves to it — threaded through `ic[:consts]` so every clause body sees the
    # const set (parity with `Rian.Beam`/`Rian.Lower`; without this a const reference
    # emitted as a bare, undefined identifier — a silent miscompile).
    consts = all_consts(prog)
    # the program inference context lets each clause body emit from the TYPED core
    # IR (`Check.annotate` fills every node's type, ADR-0050 §3).
    # the sum/struct registry, carried so a value-union type-pattern over a user type
    # (`s Box ->`, ADR-0083) can bake its JS discriminator (tag / `__struct__`) in
    # `clause_return` — the `expr_js` recursion threads no registry, so it is resolved
    # before emit (`bake_union_disc`), not at the deep `pat_match` site.
    reg = %{sums: sum_ctor_map(prog), structs: struct_name_set(prog)}

    ic =
      Check.program_ic(prog)
      |> Map.put(:consts, MapSet.new(consts, & &1.name))
      |> Map.put(:js_reg, reg)
      # ctor → {enum, named, labels} for `bake_variants`: a sum construction becomes an
      # `EVariant`, and the labels order a *named* construction (`Circle(radius: r)`) into
      # declared field order before it is keyed positionally (`_0`); JS does not name keys.
      |> Map.put(:js_vmeta, Rian.VariantLabels.meta(prog))

    const_js = Enum.map_join(consts, "\n", &const_js(&1, i53, ic))
    fn_js = Enum.map_join(funcs, "\n\n", &function_js(&1, i53, ic))
    disp_js = protocol_dispatchers_js(prog, i53)
    import_js = imports_js(funcs)

    [import_js, const_js, fn_js, disp_js] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  # ── native TypeScript `.ts` (ADR-0086 §5, third print mode) ──────────────────
  @doc """
  Emit a self-contained native TypeScript module (`.ts`) for `src`: the same runtime
  as `compile/1`, with the value types declared up front (the `.d.mts` unions/
  interfaces) and a type annotation woven into every function/const signature. So
  `compile` is the `.mjs` runtime, `compile_types` the `.d.mts` sidecar, and
  `compile_ts` the typed `.ts` source — one Core lowering, three print modes. The
  bodies are byte-identical to `compile/1`; only the headers gain `: T`.
  """
  @rian_sig "pub def compile_ts(src String) String"
  @spec compile_ts(String.t()) :: String.t()
  def compile_ts(src) do
    prog = Decl.parse(src)
    :ok = Check.gate!(prog)
    prog = Rian.Opaque.erase(prog)
    reject_mixed_int_mode!(prog)
    i53 = program_number_mode?(prog)
    known = known_type_names(prog)

    funcs = prog |> all_funcs() |> Enum.reject(&(Map.get(&1, :dispatch) == :dispatcher))
    Core.reject_unsupported!(funcs, @js_unsupported, :js, Unsupported)
    reject_unknown_module_calls!(funcs, prog |> all_funcs() |> MapSet.new(& &1.name))
    consts = all_consts(prog)
    reg = %{sums: sum_ctor_map(prog), structs: struct_name_set(prog)}

    ic =
      Check.program_ic(prog)
      |> Map.put(:consts, MapSet.new(consts, & &1.name))
      |> Map.put(:js_reg, reg)
      |> Map.put(:js_vmeta, Rian.VariantLabels.meta(prog))

    range_ts = Enum.map_join(all_ranges(prog), "\n", &dts_range/1)
    type_ts = Enum.map_join(all_types(prog), "\n", &dts_sum(&1, known))
    struct_ts = Enum.map_join(all_structs(prog), "\n", &dts_struct(&1, known))
    import_ts = imports_js(funcs)
    const_ts = Enum.map_join(consts, "\n", &const_ts(&1, i53, ic, known))
    fn_ts = Enum.map_join(funcs, "\n\n", &function_ts(&1, i53, ic, known))
    disp_ts = protocol_dispatchers_js(prog, i53)

    [range_ts, type_ts, struct_ts, import_ts, const_ts, fn_ts, disp_ts]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # the i-th declared parameter's type (`nil` → `unknown` via `ts_type`).
  defp param_ty(f, i) do
    case Enum.at(f.params, i) do
      nil -> nil
      p -> p.type
    end
  end

  # typed twin of `const_js` — `export const NAME: T = value;` (same value emission).
  defp const_ts(c, i53, ic, known) do
    %EBlock{stmts: stmts} =
      c.value
      |> Pratt.parse_body()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Check.annotate(%{}, ic)
      |> bake_variants(Map.get(ic, :js_vmeta, %{}))

    val =
      case Rian.Shadow.dedup(stmts, [], &js_fresh/2) do
        [{:expr, e}] -> expr_js(e, i53)
        deduped -> "(() => { #{block_return(deduped, i53)} })()"
      end

    export = if c.pub?, do: "export ", else: ""
    "#{export}const #{c.name}: #{ts_type(c.type, known, MapSet.new())} = #{val};"
  end

  # typed twin of `function_js` — typed signature over the byte-identical runtime body.
  defp function_ts(%{externals: ext} = f, _i53, _ic, known) when map_size(ext) > 0 do
    case Map.get(ext, :js) do
      nil ->
        raise Unsupported, "`#{f.name}`: no `@external(:js, …)` body — not reachable on :js"

      {:file, _path, fun} ->
        js_external_fn_ts(f, "#{fun}(#{Enum.map_join(f.params, ", ", & &1.name)})", known)

      spec ->
        js_external_fn_ts(f, Rian.External.render(spec, f.params), known)
    end
  end

  defp function_ts(%{name: name, clauses: clauses, pub?: pub?} = f, i53, ic, known) do
    reject_wide_int!(name, f)
    export = if pub?, do: "export ", else: ""
    tset = MapSet.new(f.tvars)
    ret = ts_type(f.ret, known, tset)

    case simple_clause(clauses) do
      {:simple, vars} ->
        [c] = clauses
        tenv = Check.clause_env(c.pats, f.params, ic)
        body = clause_return(c.body, vars, i53, tenv, ic)

        tps =
          vars
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {v, i} -> "#{v}: #{ts_type(param_ty(f, i), known, tset)}" end)

        "#{export}function #{name}#{generics(f.tvars)}(#{tps}): #{ret} { #{body} }"

      :dispatch ->
        arity = length(hd(clauses).pats)

        tps =
          Enum.map_join(0..(arity - 1)//1, ", ", fn i ->
            "a#{i}: #{ts_type(param_ty(f, i), known, tset)}"
          end)

        body = Enum.map_join(clauses, "\n", &clause_js(&1, i53, f.params, ic))

        tail =
          if total_clauses?(clauses, i53),
            do: "",
            else: "\n  throw new Error(\"#{name}: no clause matched\");"

        "#{export}function #{name}#{generics(f.tvars)}(#{tps}): #{ret} {\n#{body}#{tail}\n}"
    end
  end

  # typed twin of `js_external_fn`.
  defp js_external_fn_ts(f, host, known) do
    tset = MapSet.new(f.tvars)

    args =
      f.params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {p, i} -> "a#{i}: #{ts_type(p.type, known, tset)}" end)

    binds =
      f.params
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {p, i} -> "const #{p.name} = a#{i};" end)

    export = if f.pub?, do: "export ", else: ""

    "#{export}function #{f.name}#{generics(f.tvars)}(#{args}): #{ts_type(f.ret, known, tset)} { #{binds} return (#{host}); }"
  end

  # ── TypeScript `.d.mts` sidecar (ADR-0086 §5) ────────────────────────────────
  @doc """
  Emit a TypeScript declaration sidecar (`.d.mts`) for `src` — the **typed view**
  of the JS backend (ADR-0086 §5).

  The runtime `.mjs` (`compile/1`) erases every type at the boundary, so a
  TypeScript consumer importing it sees `any`. This second print mode describes the
  module's **exported runtime surface** — `export function`/`export const` for every
  `pub` declaration, plus `type`/`interface`/range aliases for the user types they
  reference — so the consumer is type-checked across the FFI boundary by their own
  `tsc`. TypeScript resolves an ESM module's declarations from the sibling `<name>.d.mts`
  beside `<name>.mjs` (a `.d.ts` does *not* resolve for a `.mjs`, ADR-0086 §5).

  **The declarations describe the values the `.mjs` actually produces** (a sum is a
  tagged object `{ $: "Ctor", _0: … }`, a struct a `{__struct__: "Name", …}` object,
  a `Result` an `["ok", v]` / `["error", e]` tuple) — never an aspirational shape.

  **Honest scope limits** (ADR-0086 §5 — types are *documentation, not a gate*; the
  reach gate stays `Rian.Reach`):

    * **Capabilities are fully erased.** `val`/`iso`/`tag`/`ref` shape Rust/BEAM
      only (ADR-0055) and have no JS runtime meaning, so they leave no TS trace.
    * **Mapped subset:** the JS-valid primitives (`Int`→`bigint`,
      `Int53`/`Int32`/smaller + `Float64`/`Char`→`number`, `Bool`→`boolean`,
      `String`/`Symbol`→`string`), `Any`→`unknown`, `Vec(T)`→`Array<T>`, tuples,
      `Fn(…)`, `Option`/`Result`, value-unions (ADR-0083), user sums/structs/ranges,
      `Map`/`Dict` with a `string`/`number` key, and `forall T` generics.
    * Anything else maps to **`unknown`** — an honest "cannot be faithfully
      described" rather than a misleading `any`.
  """
  @rian_sig "pub def compile_types(src String) String"
  @spec compile_types(String.t()) :: String.t()
  def compile_types(src) do
    prog = Decl.parse(src)
    # Same gate prologue as `compile/1`: a type error is caught here, and opaque
    # types are erased to their base before they reach the type mapper (ADR-0067).
    :ok = Check.gate!(prog)
    prog = Rian.Opaque.erase(prog)

    known = known_type_names(prog)

    range_dts = Enum.map_join(all_ranges(prog), "\n", &dts_range/1)
    type_dts = Enum.map_join(all_types(prog), "\n", &dts_sum(&1, known))
    struct_dts = Enum.map_join(all_structs(prog), "\n", &dts_struct(&1, known))

    const_dts =
      all_consts(prog) |> Enum.filter(& &1.pub?) |> Enum.map_join("\n", &dts_const(&1, known))

    # Only `pub` functions with a portable body are part of the module's export
    # surface: a private `def` is not emitted, a dispatcher is regenerated, and an
    # `@external` (`clauses: []`) function is imported, never re-exported.
    fn_dts =
      all_funcs(prog)
      |> Enum.filter(&(&1.pub? and &1.clauses != [] and Map.get(&1, :dispatch) != :dispatcher))
      |> Enum.map_join("\n", &dts_func(&1, known))

    body =
      [range_dts, type_dts, struct_dts, const_dts, fn_dts]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if body == "", do: "", else: body <> "\n"
  end

  # the JS-valid Rian primitives and their faithful TypeScript carriers (ADR-0064).
  # Wide fixed-width ints (`Int64`+) are absent on purpose — they have no JS rep and
  # map to `unknown` (they never appear in a JS-valid program; `reject_wide_int!`).
  @ts_prims %{
    "Int" => "bigint",
    "Int8" => "number",
    "Int16" => "number",
    "Int32" => "number",
    "Int53" => "number",
    "UInt8" => "number",
    "UInt16" => "number",
    "UInt32" => "number",
    "Float32" => "number",
    "Float64" => "number",
    "Bool" => "boolean",
    "String" => "string",
    "Char" => "number",
    "Symbol" => "string",
    "Unit" => "void",
    "Any" => "unknown"
  }

  # the structural type heads handled by name (so they are never mistaken for a type
  # variable) plus the wide ints that map to `unknown`.
  @ts_reserved ~w(Int64 Int128 UInt64 UInt128 Vec Fn Map Dict Result Option Union)

  defp all_types(prog),
    do:
      Map.get(prog, :types, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :types, []))

  defp all_structs(prog),
    do:
      Map.get(prog, :structs, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :structs, []))

  defp all_ranges(prog),
    do:
      Map.get(prog, :ranges, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :ranges, []))

  # every user type-name in scope, so a reference resolves to its declaration
  # instead of being misclassified as a type variable.
  defp known_type_names(prog) do
    names =
      Enum.map(all_types(prog), & &1.name) ++
        Enum.map(all_structs(prog), & &1.name) ++
        Enum.map(all_ranges(prog), & &1.name)

    MapSet.new(names)
  end

  # a finite ordinal subrange (ADR-0036) is its base ordinal at runtime — an integer,
  # i.e. a JS `number`.
  defp dts_range(r), do: "export type #{r.name} = number;"

  # a sum type lowers to a discriminated union of fixed-length tagged tuples, exactly
  # the `{ $: "Ctor", … }` objects the runtime emits.
  defp dts_sum(t, known) do
    tvars = t.variants |> Enum.flat_map(& &1.fields) |> collect_tvars(known)
    tset = MapSet.new(tvars)

    variants =
      case Enum.map_join(t.variants, " | ", &dts_variant(&1, known, tset)) do
        "" -> "never"
        vs -> vs
      end

    "export type #{t.name}#{generics(tvars)} = #{variants};"
  end

  defp dts_variant(v, known, tvars) do
    tag = inspect(to_string(v.ctor))

    case v.fields do
      [] ->
        "{ $: #{tag} }"

      fs ->
        body =
          fs
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {f, i} -> "_#{i}: #{ts_type(f.type, known, tvars)}" end)

        "{ $: #{tag}, #{body} }"
    end
  end

  # a struct lowers to a `{__struct__: "Name", …}` object — a TS interface with a
  # discriminant literal so a consumer can narrow on it.
  defp dts_struct(s, known) do
    tvars = collect_tvars(s.fields, known)
    tset = MapSet.new(tvars)

    fields =
      s.fields
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {f, i} ->
        # a positional (label-less) field is named `f<i>` (no truthy `||`, ADR-0035).
        label =
          case f.label do
            nil -> "f#{i}"
            l -> l
          end

        "#{label}: #{ts_type(f.type, known, tset)};"
      end)

    "export interface #{s.name}#{generics(tvars)} { __struct__: #{inspect(s.name)}; #{fields} }"
  end

  defp dts_const(c, known),
    do: "export const #{c.name}: #{ts_type(c.type, known, MapSet.new())};"

  defp dts_func(f, known) do
    tset = MapSet.new(f.tvars)
    params = Enum.map_join(f.params, ", ", &"#{&1.name}: #{ts_type(&1.type, known, tset)}")
    "export function #{f.name}#{generics(f.tvars)}(#{params}): #{ts_type(f.ret, known, tset)};"
  end

  defp generics([]), do: ""
  defp generics(tvars), do: "<#{Enum.join(tvars, ", ")}>"

  # the type variables a declaration introduces: every tvar-shaped identifier in its
  # field types (recursing into `Vec(T)`/`Pair(K, V)`/…), in first-appearance order.
  defp collect_tvars(fields, known) do
    fields |> Enum.flat_map(&scan_tvars(&1.type, known)) |> Enum.uniq()
  end

  defp scan_tvars(type, known) when is_binary(type) do
    ~r/[A-Za-z_][A-Za-z0-9_]*/
    |> Regex.scan(type)
    |> Enum.map(&hd/1)
    |> Enum.filter(&tvar?(&1, known))
  end

  defp scan_tvars(_type, _known), do: []

  defp tvar?(name, known) do
    Regex.match?(~r/^[A-Z][A-Za-z0-9_]*$/, name) and
      not Map.has_key?(@ts_prims, name) and
      name not in @ts_reserved and
      not MapSet.member?(known, name)
  end

  # map a Rian type-string to its faithful TypeScript carrier (the runtime values
  # `compile/1` emits). `known` are declared type-names, `tvars` the in-scope
  # generics; anything outside the mapped subset becomes `unknown` (honest).
  defp ts_type(nil, _known, _tvars), do: "unknown"

  defp ts_type(t, known, tvars) when is_binary(t),
    do: t |> String.trim() |> Rian.TypeStr.normalize() |> ts_app(known, tvars)

  defp ts_app("", _known, _tvars), do: "unknown"

  defp ts_app(t, known, tvars) do
    cond do
      prim = Map.get(@ts_prims, t) ->
        prim

      MapSet.member?(tvars, t) ->
        t

      String.starts_with?(t, "(") and String.ends_with?(t, ")") ->
        ts_tuple(t, known, tvars)

      true ->
        case parse_app(t) do
          {head, args} -> ts_application(head, args, known, tvars)
          :none -> if MapSet.member?(known, t), do: t, else: "unknown"
        end
    end
  end

  # `Head(arg, …)` → `{"Head", [arg, …]}`, else `:none` (a bare name / tuple).
  defp parse_app(t) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$/s, t) do
      [_, head, inner] -> {head, split_top_commas(inner)}
      _ -> :none
    end
  end

  defp ts_tuple(t, known, tvars) do
    elems =
      t
      |> binary_part(1, byte_size(t) - 2)
      |> split_top_commas()
      |> Enum.map_join(", ", &ts_type(&1, known, tvars))

    "[#{elems}]"
  end

  defp ts_application("Vec", [a], known, tvars),
    do: "Array<#{ts_type(a, known, tvars)}>"

  defp ts_application("Option", [a], known, tvars),
    do: ~s({ $: "Some", _0: #{ts_type(a, known, tvars)} } | { $: "None" })

  defp ts_application("Result", [a, b], known, tvars),
    do: ~s(["ok", #{ts_type(a, known, tvars)}] | ["error", #{ts_type(b, known, tvars)}])

  defp ts_application("Union", args, known, tvars) when args != [],
    do: Enum.map_join(args, " | ", &ts_type(&1, known, tvars))

  defp ts_application("Fn", args, known, tvars) when args != [] do
    {params, [ret]} = Enum.split(args, -1)

    sig =
      params
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {a, i} -> "a#{i}: #{ts_type(a, known, tvars)}" end)

    "(#{sig}) => #{ts_type(ret, known, tvars)}"
  end

  defp ts_application(head, [k, v], known, tvars) when head in ["Map", "Dict"] do
    kts = ts_type(k, known, tvars)

    if kts in ["string", "number"],
      do: "Record<#{kts}, #{ts_type(v, known, tvars)}>",
      else: "unknown"
  end

  defp ts_application(head, args, known, tvars) do
    if MapSet.member?(known, head),
      do: "#{head}<#{Enum.map_join(args, ", ", &ts_type(&1, known, tvars))}>",
      else: "unknown"
  end

  # `@external(:js, "./ffi.mjs", "fun")` file-references (ADR-0080 §7 b): one ESM
  # `import { … } from "path"` per referenced file, grouping the functions imported
  # from the same file. The build copies the `.ffi.mjs` beside the output.
  defp imports_js(funcs) do
    funcs
    |> Enum.flat_map(fn f ->
      case Map.get(Map.get(f, :externals, %{}), :js) do
        {:file, path, fun} -> [{path, fun}]
        _ -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map_join("\n", fn {path, funs} ->
      "import { #{funs |> Enum.uniq() |> Enum.sort() |> Enum.join(", ")} } from #{inspect(path)};"
    end)
  end

  defp all_consts(prog),
    do:
      Map.get(prog, :consts, []) ++
        Enum.flat_map(Map.get(prog, :mods, []), &Map.get(&1, :consts, []))

  # `const NAME := value` -> a top-level JS `const` (exported when `pub`). The value
  # parses, resolves sibling const references, and emits in the program integer mode.
  # A single-expression value emits inline; a multi-statement block value wraps in an
  # IIFE so the `const` still binds a single expression.
  defp const_js(c, i53, ic) do
    %EBlock{stmts: stmts} =
      c.value
      |> Pratt.parse_body()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Check.annotate(%{}, ic)
      |> bake_variants(Map.get(ic, :js_vmeta, %{}))

    val =
      case Rian.Shadow.dedup(stmts, [], &js_fresh/2) do
        [{:expr, e}] -> expr_js(e, i53)
        deduped -> "(() => { #{block_return(deduped, i53)} })()"
      end

    export = if c.pub?, do: "export ", else: ""
    "#{export}const #{c.name} = #{val};"
  end

  # every function the JS file emits: the top-level ones plus every `mod`'s,
  # flattened into one namespace — JS erases module boundaries, so a cross-module
  # call `Mod.fun(…)` lowers to a bare `fun(…)` (see the `EDot`-call clause). This
  # is how the injected `Show` module (ADR-0069 `${float}`) reaches the output.
  defp all_funcs(prog),
    do: Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

  # ── protocol dispatch (ADR-0061 §3): a JS dispatcher per protocol method ──
  # mirrors the BEAM strategy — select the impl by the first argument's runtime
  # shape — but with JS-native guards (`typeof`, the variant `$` tag).
  defp protocol_dispatchers_js(prog, i53) do
    reg = %{sums: sum_ctor_map(prog), structs: struct_name_set(prog)}
    protocols = Map.get(prog, :protocols, [])
    impl_decls = Map.get(prog, :impl_decls, [])

    for p <- protocols, m <- p.methods, reduce: [] do
      acc ->
        impl_types = for i <- impl_decls, i.proto == p.name, do: i.type

        case impl_types do
          [] -> acc
          types -> [dispatcher_js(p.name, m, types, reg, i53) | acc]
        end
    end
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp dispatcher_js(proto, method, impl_types, reg, i53) do
    arity = method.params |> split_top_commas() |> length()
    params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
    args = params

    clauses =
      Enum.map_join(impl_types, "\n", fn type ->
        "  if (#{js_guard!(type, proto, reg, i53)}) return #{mangle(proto, type, method.name)}(#{args});"
      end)

    "export function #{method.name}(#{params}) {\n#{clauses}\n  throw new Error(\"#{method.name}: no protocol impl\");\n}"
  end

  defp mangle(proto, type, method),
    do: "impl_#{String.downcase(proto)}_#{String.downcase(type)}_#{method}"

  # JS guard selecting the impl for `type` by the first argument's runtime shape.
  # the `typeof` an integer/`Char` value carries in this program's whole-program
  # int mode: `number` in number-mode (`Int53`/`Int32`), else `bigint` (`Int`).
  defp int_typeof(i53), do: if(i53, do: "number", else: "bigint")

  defp js_guard!(type, proto, reg, i53) do
    cond do
      type == "Bool" ->
        ~s(typeof a0 === "boolean")

      type == "String" ->
        ~s(typeof a0 === "string")

      # a `Char` is its codepoint and an `Int*` is an integer — both lower to a JS
      # `number` in whole-program number-mode (`Int53`/`Int32`) or a `BigInt` in
      # BigInt-mode (`Int`). The dispatch guard must match the mode the values carry,
      # or `lt(3, 1)` (a `number`) misses a `typeof === "bigint"` guard (ADR-0064 §2a).
      type == "Char" ->
        ~s(typeof a0 === "#{int_typeof(i53)}")

      String.match?(type, ~r/^U?Int\d*$/) ->
        ~s(typeof a0 === "#{int_typeof(i53)}")

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

  # the JS runtime type-test for a value-union type-pattern (ADR-0083), over an
  # arbitrary scrutinee expression `acc` (the dispatcher's `js_guard!` is the same
  # mapping fixed to `a0`). Primitive discriminators only — a sum/struct member is
  # deferred (Reach pins such a union off `:js` until it lands).
  defp type_test_js(t, acc, i53) do
    cond do
      t == "Bool" -> ~s(typeof #{acc} === "boolean")
      t == "String" -> ~s(typeof #{acc} === "string")
      t == "Char" -> ~s(typeof #{acc} === "#{int_typeof(i53)}")
      String.match?(t, ~r/^U?Int\d*$/) -> ~s(typeof #{acc} === "#{int_typeof(i53)}")
      String.match?(t, ~r/^Float\d*$/) -> ~s(typeof #{acc} === "number")
      true -> raise(Unsupported, "JS type-pattern over non-primitive `#{t}`")
    end
  end

  # the JS test for a value-union type-pattern over a SUM member (ADR-0083): a sum
  # value is a tagged array `["Ctor", …]`, so "is a `T`" tests the head against `T`'s
  # ctor tags (mirrors `sum_guard_js`).
  defp sum_disc_js(ctors, acc) do
    tags = Enum.map_join(ctors, " || ", &~s(#{acc}.$ === "#{&1}"))
    "#{acc} != null && (#{tags})"
  end

  # the JS test for a STRUCT member: a struct is `{__struct__: "Name", …}` (mirrors
  # the struct case of `js_guard!`).
  defp struct_disc_js(sname, acc),
    do: ~s(typeof #{acc} === "object" && #{acc} !== null && #{acc}.__struct__ === "#{sname}")

  defp struct_name_set(prog) do
    structs =
      Map.get(prog, :structs, []) ++ for(m <- Map.get(prog, :mods, []), s <- m.structs, do: s)

    MapSet.new(structs, & &1.name)
  end

  # a sum value is a tagged array `["Ctor", …]` (this module's representation)
  defp sum_guard_js(ctors) do
    tags = Enum.map_join(ctors, " || ", &~s(a0.$ === "#{&1}"))
    "a0 != null && (#{tags})"
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
  # an `@external` function (ADR-0068): emit the `:js` host body verbatim, binding
  # each Rian param to its positional argument by name so the spec can reference it.
  # No `:js` body -> the function is off `:js` (Reach pins it); reaching here means an
  # off-target compile, a clear error (ADR-0041 §2 — never a silent stub).
  defp function_js(%{externals: ext} = f, _i53, _ic) when map_size(ext) > 0 do
    case Map.get(ext, :js) do
      nil ->
        raise Unsupported, "`#{f.name}`: no `@external(:js, …)` body — not reachable on :js"

      # a file-reference calls the imported function (its `import` is at the module
      # top, `imports_js/1`); the call binds params positionally like any host body.
      {:file, _path, fun} ->
        js_external_fn(f, "#{fun}(#{Enum.map_join(f.params, ", ", & &1.name)})")

      spec ->
        js_external_fn(f, Rian.External.render(spec, f.params))
    end
  end

  defp function_js(%{name: name, clauses: clauses, pub?: pub?} = f, i53, ic) do
    reject_wide_int!(name, f)
    export = if pub?, do: "export ", else: ""
    # integer mode (`i53`) is computed once, program-wide, in `compile/1`.
    # Wide fixed-width (`Int64`+) is rejected above, never silently elevated.
    case simple_clause(clauses) do
      {:simple, vars} ->
        # A single clause whose every parameter is a plain variable, no guard: the
        # trivial total function. Name the JS params directly (no `a0` rebind), with
        # neither a per-clause block nor a `no clause matched` throw (it is total) —
        # so `def twice(n) := n * 2` lowers to `function twice(n) { return … }`,
        # matching the Elixir/Rust panes. The body still runs through `clause_return`,
        # so const-resolution, union-disc baking, typing, and the `:=` shadow-rename
        # (seeded with the param names) are unchanged.
        [c] = clauses
        tenv = Check.clause_env(c.pats, f.params, ic)
        ret = clause_return(c.body, vars, i53, tenv, ic)
        "#{export}function #{name}(#{Enum.join(vars, ", ")}) { #{ret} }"

      :dispatch ->
        arity = length(hd(clauses).pats)
        params = Enum.map_join(0..(arity - 1)//1, ", ", &"a#{&1}")
        body = Enum.map_join(clauses, "\n", &clause_js(&1, i53, f.params, ic))
        # The fallthrough `throw` is the runtime "no clause matched" (ADR-0035 §4),
        # needed only when the clause set is non-total. A clause with no structural
        # tests and no guard always matches, so it makes the function total — drop
        # the dead throw then (parity with the JVM emitter).
        tail =
          if total_clauses?(clauses, i53),
            do: "",
            else: "\n  throw new Error(\"#{name}: no clause matched\");"

        "#{export}function #{name}(#{params}) {\n#{body}#{tail}\n}"
    end
  end

  # A single, guardless clause whose every parameter is a plain variable pattern —
  # the trivial total function. Returns `{:simple, var_names}` or `:dispatch`.
  defp simple_clause([%{pats: pats, guard: nil}]) do
    cores = Enum.map(pats, &Core.from_pat/1)

    if Enum.all?(cores, &match?(%PVar{}, &1)),
      do: {:simple, Enum.map(cores, & &1.name)},
      else: :dispatch
  end

  defp simple_clause(_), do: :dispatch

  # The clause set is total iff some clause has no structural tests and no guard —
  # it always matches, so the dispatcher can never fall through.
  defp total_clauses?(clauses, i53), do: Enum.any?(clauses, &unconditional?(&1, i53))

  defp unconditional?(%{guard: g}, _i53) when g != nil, do: false

  defp unconditional?(%{pats: pats}, i53) do
    Enum.all?(pats, fn p ->
      {tests, _binds} = pat_match(Core.from_pat(p), "a0", i53)
      tests == []
    end)
  end

  # wrap a `:js` host expression as the function body, binding each Rian param to its
  # positional argument by name so the expression can reference it.
  defp js_external_fn(f, host) do
    args = Enum.map_join(0..(length(f.params) - 1)//1, ", ", &"a#{&1}")

    binds =
      f.params
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {p, i} -> "const #{p.name} = a#{i};" end)

    export = if f.pub?, do: "export ", else: ""
    "#{export}function #{f.name}(#{args}) { #{binds} return (#{host}); }"
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

  # A qualified call `Mod.fun(args)` (`%EDot{head: %EId{}}`) lowers to a bare
  # `fun(args)` because JS erases module boundaries (every `mod`'s funcs flatten
  # into one file). That is only sound when `fun` names a program function; a
  # host-module call (`Enum.map`) or a wrong-arity stdlib call (`List.foo`) would
  # otherwise emit an undefined reference. Reach pins such functions off `:js`, but
  # the emitter must not silently produce broken JS if called directly — reject it
  # with a clear message pointing at the sanctioned escape (`@external`).
  defp reject_unknown_module_calls!(funcs, known) do
    Enum.each(funcs, fn f ->
      Enum.each(f.clauses, fn c ->
        body = c.body |> Pratt.parse_body() |> Core.from_expr()

        case unknown_module_call(body, known) do
          nil ->
            :ok

          {mod, fun} ->
            raise Unsupported,
                  "`#{f.name}`: `#{mod}.#{fun}(…)` is neither a program function nor a " <>
                    "supported interop call — host FFI is not reachable on :js (use " <>
                    "`@external(:js, …)`, ADR-0068)."
        end
      end)
    end)
  end

  defp unknown_module_call(%ECall{fun: %EDot{head: %EId{name: mod}, name: fun}} = node, known)
       when mod not in @js_portable_modules do
    if fun in known,
      do: descend_unknown_call(node, known),
      else: {mod, fun}
  end

  defp unknown_module_call(node, known) when is_struct(node),
    do: descend_unknown_call(node, known)

  defp unknown_module_call(l, known) when is_list(l),
    do: Enum.find_value(l, &unknown_module_call(&1, known))

  defp unknown_module_call(t, known) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.find_value(&unknown_module_call(&1, known))

  defp unknown_module_call(_node, _known), do: nil

  defp descend_unknown_call(node, known),
    do:
      node
      |> Map.from_struct()
      |> Map.values()
      |> Enum.find_value(&unknown_module_call(&1, known))

  # `{ if (<structural tests>) { <binds> <guarded return> } }` — the binds live
  # *inside* the structural test so a nested field access (`a0[1][1]`) only runs
  # once the shape is known; a `when` guard, written in the bound names, follows.
  defp clause_js(%{pats: pats, body: body, guard: guard}, i53, params, ic) do
    {tests, binds} =
      pats
      |> Enum.map(&Core.from_pat/1)
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "a#{i}", i53)
        {ts ++ t, bs ++ b}
      end)

    # the per-clause typing env (params narrowed by the head patterns) types the
    # body's core IR (ADR-0050 §3).
    tenv = Check.clause_env(pats, params, ic)
    # the clause's parameters are `const`-bound in this same JS scope, so a `:=`
    # that rebinds a parameter name shadows them — seed the rename with the params
    param_names = Enum.map(binds, fn {n, _} -> n end)
    inner = bind_lines(binds) ++ [guarded_return(body, guard, param_names, i53, tenv, ic)]
    body_str = Enum.join(inner, " ")

    guarded =
      case tests do
        [] -> body_str
        _ -> "if (#{Enum.join(tests, " && ")}) { #{body_str} }"
      end

    "  { #{guarded} }"
  end

  defp guarded_return(body, nil, params, i53, tenv, ic),
    do: clause_return(body, params, i53, tenv, ic)

  defp guarded_return(body, g, params, i53, tenv, ic) do
    guard =
      g
      |> Pratt.parse()
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Check.annotate(tenv, ic)
      |> expr_js(i53)

    "if (#{guard}) { #{clause_return(body, params, i53, tenv, ic)} }"
  end

  # Match `pat` against the JS access path `acc` -> `{tests, binds}`. A sum
  # variant is a tagged array `["Ctor", arg0, …]` (ADR-0049), so a constructor
  # pattern checks the tag and recurses into each positional field.
  defp pat_match(%PWild{}, _acc, _i53), do: {[], []}
  defp pat_match(%PVar{name: n}, acc, _i53), do: {[], [{n, acc}]}

  # an as-pattern `name @ pat` (ADR-0050): bind `name` to the whole scrutinee AND
  # match the inner pattern against it.
  defp pat_match(%PAs{name: n, pat: p}, acc, i53) do
    {ts, bs} = pat_match(p, acc, i53)
    {ts, [{n, acc} | bs]}
  end

  # a pin `^x` (ADR-0050): match when the scrutinee equals the pinned value — an
  # `===` test, no bind. Only `^var` is supported (as on the BEAM).
  defp pat_match(%PPin{expr: {:id, name}}, acc, _i53), do: {["#{acc} === #{name}"], []}

  defp pat_match(%PPin{expr: e}, _acc, _i53),
    do: raise(Unsupported, "ecmascript: pin `^#{inspect(e)}` (only `^var` is supported)")

  # a type-pattern `n Type` (ADR-0083): bind `n` and test the scrutinee's runtime
  # type with the same JS-native discriminator the dispatcher uses. A primitive
  # (`disc: nil`) tests `typeof`; a sum/struct member's discriminator was baked into
  # `disc` by `bake_union_disc` (the tag array / `__struct__`).
  defp pat_match(%PTyped{name: n, disc: {:sum, ctors}}, acc, _i53),
    do: {[sum_disc_js(ctors, acc)], [{n, acc}]}

  defp pat_match(%PTyped{name: n, disc: {:struct, sname}}, acc, _i53),
    do: {[struct_disc_js(sname, acc)], [{n, acc}]}

  defp pat_match(%PTyped{name: n, tname: t, disc: nil}, acc, i53),
    do: {[type_test_js(t, acc, i53)], [{n, acc}]}

  defp pat_match(%PLit{value: v}, acc, i53), do: {["#{acc} === #{lit_js(v, i53)}"], []}
  # a `Char` is its codepoint integer, in the program's integer mode (number or
  # BigInt) so it never mixes with the surrounding codepoints
  defp pat_match(%PChar{value: cp}, acc, i53), do: {["#{acc} === #{cp_lit(cp, i53)}"], []}
  defp pat_match(%PAtom{name: a}, acc, _i53), do: {["#{acc} === #{js_atom(a)}"], []}

  # a tuple is a JS array (a Result `{:ok, x}` is `["ok", x]`); fix the length and
  # match each element positionally (`acc[i]`)
  defp pat_match(%PTuple{elems: es}, acc, i53) do
    {ts, bs} = match_elems(es, acc, i53)
    {["#{acc}.length === #{length(es)}" | ts], bs}
  end

  defp pat_match(%PCtor{ctor: ctor, args: args}, acc, i53) do
    {ts, bs} =
      args
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}._#{i}", i53)
        {ts ++ t, bs ++ b}
      end)

    {["#{acc}.$ === #{inspect(ctor)}" | ts], bs}
  end

  # a list is a JS array; a closed pattern fixes the length, a cons pattern
  # `[h, … | tail]` requires at least the listed elements and binds the rest via
  # `slice`
  defp pat_match(%PList{elems: es, tail: :close}, acc, i53) do
    {ts, bs} = match_elems(es, acc, i53)
    {["#{acc}.length === #{length(es)}" | ts], bs}
  end

  defp pat_match(%PList{elems: es, tail: tail}, acc, i53) do
    n = length(es)
    {ts, bs} = match_elems(es, acc, i53)
    {tt, tb} = pat_match(tail, "#{acc}.slice(#{n})", i53)
    {["#{acc}.length >= #{n}" | ts ++ tt], bs ++ tb}
  end

  # a struct is a JS object `{__struct__: "Name", field: …}`; the pattern checks
  # the tag and binds each named field by property access.
  defp pat_match(%PStruct{name: name, fields: fields}, acc, i53) do
    {ts, bs} =
      Enum.reduce(fields, {[], []}, fn {f, p}, {ts, bs} ->
        {t, b} = pat_match(p, "#{acc}.#{f}", i53)
        {ts ++ t, bs ++ b}
      end)

    {["#{acc}.__struct__ === #{inspect(to_string(name))}" | ts], bs}
  end

  # a map pattern `%{k: p, …}` over a JS object: each atom key tests presence and
  # matches its value (`acc["k"]`); an empty `%{}` matches any map (no test). A
  # non-atom (computed) key has no JS-object lowering (ADR-0033), so it raises.
  defp pat_match(%PMap{pairs: pairs}, acc, i53) do
    Enum.reduce(pairs, {[], []}, fn
      {{:key, _k}, _p}, _acc ->
        raise(Unsupported, "a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)")

      {key, p}, {ts, bs} ->
        ks = inspect(to_string(key))
        {t, b} = pat_match(p, "#{acc}[#{ks}]", i53)
        {ts ++ ["Object.hasOwn(#{acc}, #{ks})" | t], bs ++ b}
    end)
  end

  defp pat_match(other, _acc, _i53),
    do: raise(Unsupported, "ecmascript: clause pattern #{inspect(other)}")

  defp match_elems(es, acc, i53) do
    es
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {p, i}, {ts, bs} ->
      {t, b} = pat_match(p, "#{acc}[#{i}]", i53)
      {ts ++ t, bs ++ b}
    end)
  end

  defp bind_lines(binds), do: Enum.map(binds, fn {n, a} -> "const #{n} = #{a};" end)

  # one `case` arm against the bound scrutinee `_s`: `if (tests) { binds; return … }`
  defp case_arm_js({pat, guard, body}, i53) do
    {tests, binds} = pat_match(pat, "_s", i53)
    inner = Enum.join(bind_lines(binds) ++ [arm_return(body, guard, i53)], " ")
    if tests == [], do: inner, else: "if (#{Enum.join(tests, " && ")}) { #{inner} }"
  end

  defp arm_return(body, nil, i53), do: "return #{branch_js(body, i53)};"
  defp arm_return(body, g, i53), do: "if (#{expr_js(g, i53)}) { return #{branch_js(body, i53)}; }"

  # a clause body parses to a block: emit `let`s then `return` the final value.
  # `:=` shadowing is resolved on the Core IR by `Rian.Shadow` first (JS `let`/
  # `const` forbid same-scope re-declaration); `$` is JS-valid and never appears
  # in a Rian identifier, so a `$`-suffixed fresh name cannot collide.
  defp clause_return(src, params, i53, tenv, ic) do
    %EBlock{stmts: stmts} =
      src
      |> Pratt.parse_body()
      |> bake_union_disc(Map.get(ic, :js_reg, %{sums: %{}, structs: MapSet.new()}))
      |> resolve_consts(Map.get(ic, :consts, MapSet.new()))
      |> Check.annotate(tenv, ic)
      # resolve sum constructions to `EVariant` (labeled fields) + label ctor
      # patterns in `case` arms, on the typed Core (ADR-0049 §3b).
      |> bake_variants(Map.get(ic, :js_vmeta, %{}))

    block_return(Rian.Shadow.dedup(stmts, params, &js_fresh/2), i53)
  end

  # Reflective Core walk: a sum construction `Ctor(args)` becomes an `EVariant` carrying
  # `{label | nil, value}` pairs in declared field order — so a *named* construction
  # (`Circle(radius: r)`) is reordered before `expr_js` keys it positionally (`_0`). JS
  # keeps positional keys (the JVM `data class` is the named-field backend, ADR-0049 §3b);
  # the labels only drive the ordering here. Non-variant nodes recurse generically; a
  # non-sum `Ctor(...)` (a struct/function call) is left untouched.
  defp bake_variants(%EVariant{} = n, _vm), do: n

  defp bake_variants(%ECall{fun: %EId{name: c}, args: args} = n, vm) do
    case Map.get(vm, c) do
      nil ->
        bake_struct(n, vm)

      info ->
        %EVariant{
          enum: info.enum,
          ctor: info.ctor,
          named: info.named,
          pairs: variant_pairs(info, args, vm)
        }
    end
  end

  defp bake_variants(%_struct{} = n, vm), do: bake_struct(n, vm)
  defp bake_variants(l, vm) when is_list(l), do: Enum.map(l, &bake_variants(&1, vm))

  defp bake_variants(t, vm) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.map(&bake_variants(&1, vm)) |> List.to_tuple()

  defp bake_variants(x, _vm), do: x

  defp bake_struct(%mod{} = n, vm) do
    struct(mod, n |> Map.from_struct() |> Map.new(fn {k, v} -> {k, bake_variants(v, vm)} end))
  end

  # `{label | nil, value}` pairs in declared field order — positional args zip onto
  # the labels; all-named args (`Circle(radius: 1.0)`) are placed by name (mirrors
  # `Rian.Lower.variant_pairs`).
  defp variant_pairs(info, args, vm) do
    if args != [] and Enum.all?(args, &match?(%ELabel{}, &1)) do
      given = Map.new(args, fn %ELabel{name: l, expr: e} -> {l, bake_variants(e, vm)} end)
      Enum.map(info.labels, fn l -> {l, Map.fetch!(given, l)} end)
    else
      Enum.zip(info.labels, Enum.map(args, &bake_variants(&1, vm)))
    end
  end

  # Bake a value-union type-pattern's discriminator (ADR-0083) into the surface so
  # `pat_match` (which threads no type registry) can emit a sum's tag / a struct's
  # `__struct__` JS test. `map_node` deliberately skips arm PATTERNS, so a `case`
  # arm's pattern is baked explicitly here; everything else recurses.
  defp bake_union_disc({:case, s, arms}, reg) do
    {:case, bake_union_disc(s, reg),
     Enum.map(arms, fn {p, g, b} ->
       {bake_pat(p, reg), bake_guard(g, reg), bake_union_disc(b, reg)}
     end)}
  end

  defp bake_union_disc(node, reg), do: Rian.Macro.map_node(node, &bake_union_disc(&1, reg))

  defp bake_guard(nil, _reg), do: nil
  defp bake_guard(g, reg), do: bake_union_disc(g, reg)

  # `{:typed, n, T}` -> `{:typed, n, T, {:sum, ctors}|{:struct, T}}` for a user type;
  # a primitive `T` is left as the 3-tuple for `pat_match` to discriminate.
  defp bake_pat({:typed, name, tname}, reg) do
    cond do
      ctors = Map.get(reg.sums, tname) -> {:typed, name, tname, {:sum, ctors}}
      MapSet.member?(reg.structs, tname) -> {:typed, name, tname, {:struct, tname}}
      true -> {:typed, name, tname}
    end
  end

  defp bake_pat(p, _reg), do: p

  # Rewrite a reference to a declared `const` (`{:id, NAME}`, NAME in the set) into a
  # `{:const_ref, NAME}` surface node, which `Core.from_expr` lifts to `EConstRef` and
  # this emitter spells as the const's name (parity with `Rian.Beam`/`Rian.Lower`).
  defp resolve_consts(node, cset) do
    if MapSet.size(cset) == 0, do: node, else: walk_consts(node, cset)
  end

  defp walk_consts({:id, name} = node, cset),
    do: if(MapSet.member?(cset, name), do: {:const_ref, name}, else: node)

  defp walk_consts(node, cset), do: Rian.Macro.map_node(node, &walk_consts(&1, cset))

  defp js_fresh(base, count), do: base <> "$" <> Integer.to_string(count)

  defp block_return([{:expr, e}], i53), do: "return #{expr_js(e, i53)};"

  defp block_return(stmts, i53) do
    {init, [last]} = Enum.split(stmts, -1)
    lets = Enum.map_join(init, " ", &stmt_js(&1, i53))
    "#{lets} #{stmt_return(last, i53)}"
  end

  defp stmt_js({:bind, n, e}, i53), do: "let #{n} = #{expr_js(e, i53)};"
  # the declared type is erased at lowering (ADR-0034 §1); the value is unchanged.
  defp stmt_js({:typed_bind, n, _t, e}, i53), do: stmt_js({:bind, n, e}, i53)
  defp stmt_js({:expr, e}, i53), do: "#{expr_js(e, i53)};"
  # The returned statement is always an expression — a trailing binding is
  # rejected at `Rian.Core` (ADR-0035), so `stmt_return` only sees `:expr`.
  defp stmt_return({:expr, e}, i53), do: "return #{expr_js(e, i53)};"

  # ── expression emission ─────────────────────────────────────────────────
  defp expr_js(%ENum{text: n}, i53), do: num_js(n, i53)
  # a reference to a declared `const` -> the top-level `const`'s name (emitted by `const_js`).
  defp expr_js(%EConstRef{name: name}, _i53), do: name
  # a `Char` is its codepoint integer, in the program's integer mode
  defp expr_js(%EChar{value: cp}, i53), do: cp_lit(cp, i53)
  # a Rian `String` is a JS string; `<>` concatenation is `+` (see js_op)
  defp expr_js(%EStr{value: s}, _i53), do: js_str(s)
  defp expr_js(%EId{name: b}, _i53) when b in ~w(true false), do: b
  # an atom (`Symbol`, incl. the `:ok`/`:error` Result tags) lowers to a JS string —
  # equality holds, ordering is rejected by `symbol_lint!` (ADR-0041 §2). A Result
  # `{:ok, v}` is then `["ok", v]`, exactly parallel to a sum variant `["Ctor", …]`.
  defp expr_js(%EAtom{name: a}, _i53), do: js_atom(a)

  # a bare PascalCase id is a nullary sum variant -> a tagged object `{ $: "Red" }`
  defp expr_js(%EId{name: x}, _i53) do
    if pascal?(x), do: "{ $: #{inspect(x)} }", else: x
  end

  defp expr_js(%EUnary{op: "-", arg: x}, i53), do: "-#{expr_js(x, i53)}"
  defp expr_js(%EUnary{op: "not", arg: x}, i53), do: "!#{expr_js(x, i53)}"

  # ECMAScript has no integer-division operator: `/` is IEEE-754 float division
  # (a `Number`). So a Rian `div` (integer division, truncate-toward-zero) cannot
  # lower to a bare `/` in number-mode — `5 div 2` would be `2.5`, not `2`. Truncate
  # explicitly. In BigInt-mode `/` is already integer division (truncates toward
  # zero, matching `div`), so it stands as-is (ADR-0049 §JS-numerics).
  defp expr_js(%EBin{op: "div", left: l, right: r}, i53) do
    if i53,
      do: "Math.trunc(#{expr_js(l, i53)} / #{expr_js(r, i53)})",
      else: "(#{expr_js(l, i53)} / #{expr_js(r, i53)})"
  end

  # membership `x in xs` -> `xs.includes(x)` (JS arrays + strings)
  defp expr_js(%EBin{op: "in", left: l, right: r}, i53),
    do: "#{expr_js(r, i53)}.includes(#{expr_js(l, i53)})"

  defp expr_js(%EBin{op: op, left: l, right: r}, i53),
    do: "(#{expr_js(l, i53)} #{js_op(op)} #{expr_js(r, i53)})"

  defp expr_js(%ETuple{elems: es}, i53), do: "[#{Enum.map_join(es, ", ", &expr_js(&1, i53))}]"

  # a list is a JS array; a cons tail spreads (`[h | t]` -> `[h, ...t]`)
  defp expr_js(%EList{elems: es, tail: :close}, i53),
    do: "[#{Enum.map_join(es, ", ", &expr_js(&1, i53))}]"

  defp expr_js(%EList{elems: es, tail: tail}, i53),
    do: "[#{Enum.join(Enum.map(es, &expr_js(&1, i53)) ++ ["...#{expr_js(tail, i53)}"], ", ")}]"

  # a map literal `%{k: v, …}` is a JS object (identifier keys -> string keys).
  # A non-atom (computed) key `%{expr => v}` (ADR-0033) has no faithful JS-object
  # lowering — object keys coerce to strings, so a module/tuple key would silently
  # collide — so it raises; `Rian.Reach` pins such a function off `:js` (BEAM-only).
  defp expr_js(%EMap{pairs: pairs}, i53),
    do: "{#{Enum.map_join(pairs, ", ", &js_map_pair(&1, i53))}}"

  # a map update `%{base | k: v, …}` is a spread over the base object — the later
  # keys override (`{...base, k: v}`), matching the BEAM exact-assoc replacement
  defp expr_js(%EMapUpdate{base: base, pairs: pairs}, i53) do
    fields = Enum.map_join(pairs, ", ", &js_map_pair(&1, i53))
    "{...#{expr_js(base, i53)}, #{fields}}"
  end

  # portable-prelude primitives (ADR-0047 §2): each backend lowers `__prim_*` to
  # its native collection op; the portable `Map`/`String` ops are written in Rian
  # over them. Here: JS objects.
  defp expr_js(%ECall{fun: %EId{name: "__prim_map_new"}, args: []}, _i53), do: "{}"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_get"}, args: [m, k]}, i53),
    do: "#{paren(m, i53)}[#{expr_js(k, i53)}]"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_put"}, args: [m, k, v]}, i53),
    do: "{...#{paren(m, i53)}, [#{expr_js(k, i53)}]: #{expr_js(v, i53)}}"

  defp expr_js(%ECall{fun: %EId{name: "__prim_map_has"}, args: [m, k]}, i53),
    do: "Object.hasOwn(#{paren(m, i53)}, #{expr_js(k, i53)})"

  # `String` primitives — codepoints are BigInt (Int64); concat is `+`
  defp expr_js(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s]}, i53),
    do: "[...#{paren(s, i53)}].map(c => #{cp_expr("c.codePointAt(0)", i53)})"

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}, i53),
    do: "#{paren(cs, i53)}.map(c => String.fromCodePoint(Number(c))).join(\"\")"

  # a `Char`'s codepoint — identity in JS, where a `Char` is a BigInt codepoint
  defp expr_js(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, i53), do: expr_js(c, i53)

  # integer → string (ADR-0069 interpolation): `String(n)` stringifies a `number`
  # or a `BigInt` (`String(5n)` === "5") — no suffix either way
  defp expr_js(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, i53),
    do: "String(#{expr_js(n, i53)})"

  # runtime `Show` fallthrough for an `:unknown`-typed hole (ADR-0069 §2): `String(x)` is
  # JS's universal runtime stringifier.
  defp expr_js(%ECall{fun: %EId{name: "__prim_to_string"}, args: [x]}, i53),
    do: "String(#{expr_js(x, i53)})"

  # float → its shortest-round-trip scientific form (ADR-0069 Float64 unlock): the
  # *digits* are unique across targets; `Rian.Show.float` (portable Rian) normalizes
  # this to the ECMAScript canonical. `toExponential()` (no arg) gives the shortest
  # mantissa with an explicit signed exponent, e.g. `0.1 -> "1e-1"`.
  defp expr_js(%ECall{fun: %EId{name: "__prim_float_repr"}, args: [n]}, i53),
    do: "(#{expr_js(n, i53)}).toExponential()"

  # integer → float (ADR-0035 explicit conversion): `Number(n)` widens a `number`
  # or a `BigInt` (`Number(5n)` === 5) to a JS number (Float64)
  defp expr_js(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [n]}, i53),
    do: "Number(#{expr_js(n, i53)})"

  defp expr_js(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}, i53),
    do: "(#{expr_js(a, i53)} + #{expr_js(b, i53)})"

  # variadic single-shot join (ADR-0069 §6): a flat `+` chain — every part is
  # already a string, and V8 builds it as one rope (no per-pair intermediate).
  defp expr_js(%ECall{fun: %EId{name: "__prim_str_concat_all"}, args: args}, i53),
    do: "(" <> Enum.map_join(args, " + ", &expr_js(&1, i53)) <> ")"

  # a `Char`'s single-character string (ADR-0069 §6): a `Char` is its codepoint in
  # the program's integer mode, so `String.fromCodePoint(Number(c))`.
  defp expr_js(%ECall{fun: %EId{name: "__prim_char_to_string"}, args: [c]}, i53),
    do: "String.fromCodePoint(Number(#{expr_js(c, i53)}))"

  # diverging abort (ADR-0035/0040): `throw` is a JS statement, so wrap it in an
  # immediately-invoked arrow to keep `panic` an expression (it never returns).
  defp expr_js(%ECall{fun: %EId{name: "__prim_panic"}, args: [msg]}, i53),
    do: "(() => { throw new Error(#{expr_js(msg, i53)}); })()"

  # explicit 64-bit overflow ops (ADR-0035 §3) operate on `Int64`, which is NOT
  # supported on JS (ADR-0064): their two's-complement-at-64 contract has no JS
  # representation without per-op `BigInt.asIntN` masking — the silent BigInt
  # elevation we refuse. So they raise here (and `Rian.Reach` pins any `Int64`
  # function off `:js`, so the gate catches it first). A function reaching this is
  # one that bypassed the signature gate via an untyped call site.
  defp expr_js(%ECall{fun: %EId{name: prim}, args: [_, _]}, _i53)
       when prim in @overflow_prims,
       do:
         raise(
           Unsupported,
           "`#{prim}` operates on `Int64`, which is not supported on JS (ADR-0064) — " <>
             "64-bit two's-complement wrap has no JS representation; use `Int` or `Int53`."
         )

  # the handful of stdlib calls mapped to portable JS (a stopgap until the
  # portable prelude, ADR-0047, owns these):
  #   Map.get/put (immutable), String.to_charlist, List.to_string, :lists.reverse
  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "get"}, args: [m, k]}, i53),
    do: "#{paren(m, i53)}[#{expr_js(k, i53)}]"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "Map"}, name: "put"}, args: [m, k, v]}, i53),
    do: "{...#{paren(m, i53)}, [#{expr_js(k, i53)}]: #{expr_js(v, i53)}}"

  defp expr_js(
         %ECall{fun: %EDot{head: %EId{name: "String"}, name: "to_charlist"}, args: [s]},
         i53
       ),
       do: "[...#{paren(s, i53)}].map(c => #{cp_expr("c.codePointAt(0)", i53)})"

  defp expr_js(%ECall{fun: %EDot{head: %EId{name: "List"}, name: "to_string"}, args: [xs]}, i53),
    do: "#{paren(xs, i53)}.map(c => String.fromCodePoint(Number(c))).join(\"\")"

  defp expr_js(%ECall{fun: %EDot{head: %EAtom{name: "lists"}, name: "reverse"}, args: [xs]}, i53),
    do: "#{paren(xs, i53)}.slice().reverse()"

  # a user cross-module call `Mod.fun(args)` (Pascal-qualified): JS erases module
  # boundaries — every `mod`'s funcs flatten into this one file (see `all_funcs/1`)
  # — so the qualifier drops and it lowers to a bare call. (ADR-0069: the `Show`
  # module injected for `${float}` interpolation resolves through here.) The three
  # built-in interop namespaces above keep their special lowering and are excluded.
  defp expr_js(%ECall{fun: %EDot{head: %EId{name: mod}, name: fun}, args: args}, i53)
       when mod not in ~w(Map String),
       do: "#{fun}(#{Enum.map_join(args, ", ", &expr_js(&1, i53))})"

  # `case scrut do pat -> body … end` -> an IIFE: bind the scrutinee, then an
  # if-chain of `pat_match` tests; the first matching arm `return`s its body
  defp expr_js(%ECase{scrut: scrut, arms: arms}, i53) do
    arms_js = Enum.map_join(arms, " ", &case_arm_js(&1, i53))

    "(() => { const _s = #{expr_js(scrut, i53)}; #{arms_js} throw new Error(\"case: no clause matched\"); })()"
  end

  # named construction `Name(field: v, …)` (labeled args) -> a `__struct__`-tagged
  # object; a positional PascalCase call -> a sum-variant tagged array
  # `["Ctor", arg0, …]`; a lowercase call -> a function call
  defp expr_js(%ECall{fun: %EId{name: f}, args: [%ELabel{} | _] = args}, i53) do
    fields =
      Enum.map_join(args, ", ", fn %ELabel{name: l, expr: e} -> "#{l}: #{expr_js(e, i53)}" end)

    "{ __struct__: #{inspect(f)}, #{fields} }"
  end

  defp expr_js(%ECall{fun: %EId{name: f}, args: args}, i53) do
    if pascal?(f) do
      # a sum variant -> a tagged object `{ $: "Ctor", _0: a, _1: b }` (positional
      # field keys; distinguishes a variant from a list/tuple, unlike the old array)
      fields =
        args
        |> Enum.with_index()
        |> Enum.map_join(", ", fn {a, i} -> "_#{i}: #{expr_js(a, i53)}" end)

      sep = if args == [], do: "", else: ", "
      "{ $: #{inspect(f)}#{sep}#{fields} }"
    else
      "#{f}(#{Enum.map_join(args, ", ", &expr_js(&1, i53))})"
    end
  end

  defp expr_js(%EIf{cond: c, then: t, else: e}, i53),
    do: "(#{expr_js(c, i53)} ? #{branch_js(t, i53)} : #{branch_js(e, i53)})"

  # struct construction `Name(field: v, …)` -> a JS object tagged with
  # `__struct__` (so field access and protocol dispatch work uniformly)
  defp expr_js(%EStruct{name: name, pairs: pairs}, i53) do
    fields = Enum.map_join(pairs, ", ", fn {label, v} -> "#{label}: #{expr_js(v, i53)}" end)
    "{ __struct__: #{inspect(to_string(name))}#{if fields == "", do: "", else: ", " <> fields} }"
  end

  # a resolved sum-variant construction -> a tagged object with positional field keys
  # `{ $: "Ctor", _0: a, _1: b }` (ADR-0049 §3b: JS keeps positional `_n`, unlike the
  # JVM `data class`). `bake_variants` produces this from a `Ctor(args)` call, placing
  # named args (`Circle(radius: r)`) in declared field order first.
  defp expr_js(%EVariant{ctor: ctor, pairs: pairs}, i53) do
    fields =
      pairs
      |> Enum.with_index()
      |> Enum.map_join("", fn {{_label, v}, i} -> ", _#{i}: #{expr_js(v, i53)}" end)

    "{ $: #{inspect(ctor)}#{fields} }"
  end

  # bare field access `value.field` (a remote call `Mod.fun(…)` is handled above
  # as an `ECall` over an `EDot`, so a standalone `EDot` here is field access)
  defp expr_js(%EDot{head: head, name: field}, i53), do: "#{expr_js(head, i53)}.#{field}"

  # a `with` expression desugars to a nest of `case`s (ADR-0040) — emit that.
  defp expr_js(%EWith{clauses: clauses, body: body, els: els}, i53),
    do: expr_js(Core.desugar_with(clauses, body, els), i53)

  # a lambda `(a, b) -> body` -> a JS arrow function. JS closures capture their
  # environment natively, so a lambda value (passed to a HOF, returned, or bound)
  # needs no `Box`/`move` ceremony as Rust does (ADR-0061). The body is a single
  # expression or a `do…end` block (an `EBlock`); `branch_js` renders both as one
  # JS expression (an IIFE for a multi-statement block).
  defp expr_js(%ELambda{params: params, body: body}, i53) do
    ps = Enum.map_join(params, ", ", fn {n, _} -> n end)
    "(#{ps}) => #{branch_js(body, i53)}"
  end

  # an anonymous capture `&(&1 + &2)` -> an arrow over generated args `_1.._N`
  defp expr_js(%ECapture{body: body}, i53) do
    ps = Enum.map_join(1..Core.cap_arity(body)//1, ", ", &"_#{&1}")
    "(#{ps}) => #{expr_js(body, i53)}"
  end

  defp expr_js(%ECapArg{n: n}, _i53), do: "_#{n}"

  # `&name/arity` -> the bare function reference (JS functions are first-class);
  # `&Mod.fun/arity` -> a forwarding arrow (a remote name has no bare JS binding).
  defp expr_js(%ECaptureNamed{path: %EId{name: n}}, _i53), do: n

  defp expr_js(%ECaptureNamed{path: path, arity: a}, i53) do
    ps = Enum.map_join(0..(a - 1)//1, ", ", &"_a#{&1}")
    "(#{ps}) => #{expr_js(path, i53)}(#{ps})"
  end

  # a block in expression position (a `do…end` as an arg/arm value) -> an IIFE,
  # the same form `branch_js` produces for `if`/`case` branches.
  defp expr_js(%EBlock{} = b, i53), do: branch_js(b, i53)

  defp expr_js(other, _i53), do: raise(Unsupported, "ecmascript: expression #{inspect(other)}")

  # one JS map pair. An atom-key shorthand → a JS object field; a non-atom (computed)
  # key has no faithful JS-object lowering (object keys coerce to strings), so raise —
  # `Rian.Reach` pins such a function off `:js`, BEAM-only (ADR-0033).
  defp js_map_pair({{:key, _k}, _v}, _i53),
    do: raise(Unsupported, "a non-atom map key (`%{expr => v}`) is BEAM-only (ADR-0033)")

  defp js_map_pair({k, v}, i53), do: "#{k}: #{expr_js(v, i53)}"

  # an `if` branch is a block; a single-expression block is an expression, a
  # multi-statement block an IIFE
  defp branch_js(%EBlock{stmts: [{:expr, e}]}, i53), do: expr_js(e, i53)
  defp branch_js(%EBlock{stmts: []}, _i53), do: "undefined"
  defp branch_js(%EBlock{stmts: stmts}, i53), do: "(() => { #{block_return(stmts, i53)} })()"
  defp branch_js(expr, i53), do: expr_js(expr, i53)

  # ── helpers ─────────────────────────────────────────────────────────────
  # `Int` -> BigInt literal (`42n`); a Float64 literal is a plain JS number; in
  # number-mode (`Int53`/`Int32`), an integer literal is a plain (native) JS number too
  defp num_js(n, i53) do
    cond do
      float?(n) -> n
      i53 -> n
      true -> "#{n}n"
    end
  end

  defp lit_js(v, i53) when is_integer(v), do: if(i53, do: "#{v}", else: "#{v}n")
  defp lit_js(v, _i53) when is_binary(v), do: js_str(v)

  # render a decoded `String` value as a JS double-quoted literal, escaping the
  # quote/backslash, the common control chars by name, and any other control
  # codepoint as `\uHHHH` (printable codepoints, incl. non-ASCII, pass through).
  defp js_str(s),
    do: ~s(") <> for(cp <- String.to_charlist(s), into: "", do: js_str_cp(cp)) <> ~s(")

  # an atom lowers to its name as a JS string literal (ADR-0041 §3: open symbols are
  # strings on JS); the same escaping as a `String` literal so a quirky tag is safe
  defp js_atom(name), do: js_str(name)

  defp js_str_cp(?\\), do: "\\\\"
  defp js_str_cp(?"), do: "\\\""
  defp js_str_cp(?\n), do: "\\n"
  defp js_str_cp(?\r), do: "\\r"
  defp js_str_cp(?\t), do: "\\t"
  defp js_str_cp(cp) when cp < 0x20 or cp == 0x7F, do: "\\u" <> hex4(cp)
  defp js_str_cp(cp), do: <<cp::utf8>>

  defp hex4(cp), do: String.pad_leading(Integer.to_string(cp, 16), 4, "0")

  # A `Char`/codepoint integer follows the program's integer mode: a plain JS
  # number in number-mode (`Int53`/`Int32`), a `BigInt` otherwise — so codepoints
  # never mix with the surrounding integers (JS forbids combining BigInt + number).
  defp cp_lit(cp, i53), do: if(i53, do: "#{cp}", else: "#{cp}n")
  defp cp_expr(js, i53), do: if(i53, do: js, else: "BigInt(#{js})")

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
  defp paren(e, i53), do: "(#{expr_js(e, i53)})"

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)
end
