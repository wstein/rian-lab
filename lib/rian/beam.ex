defmodule Rian.Beam do
  @moduledoc """
  Erlang **abstract-forms** backend (ADR-0031 / ADR-0026) — the real-compilation
  path that replaces `Code.eval_string` of emitted source.

  Instead of producing Elixir text and `eval`-ing it, this lowers a parsed Rian
  function group directly to the **Erlang abstract format** and runs it through
  `:compile.forms/2`, yielding actual `.beam` bytecode that `:code.load_binary/3`
  loads as a real module. This is the bootstrap target: no Elixir-compiler
  dependency, a reproducible artifact, real error locations (line is tracked).

  **Dialyzer contracts (Stage 0.5).** Rian's declared types are not erased into
  the void: every function emits a `-spec`, and every sum/struct emits a named
  `-type`, into the module's abstract code (kept in the `.beam` via `:debug_info`)
  — so the output is **Dialyzer-checkable**. The Rian → Erlang type-form mapping
  is `Int*`/`UInt*`/`Char` → `integer()`, `Float*` → `float()`, `Bool` →
  `boolean()`, `String` → `binary()`, `Vec(T)` → `[t()]`, `Fn(A, R)` →
  `fun((a()) -> r())`, a sum → a named union of tag atoms / tagged tuples, a
  struct → a named `\#{'__struct__' := tag, …} | {tag, …}`, and a `forall`
  type-variable or any un-pinnable type → `any()` (sound — never a false
  contract). So `def area(s Shape) Float64` compiles with
  `-spec area(shape()) -> float()` and `-type shape() :: …` alongside.

  ## Scope (this increment)

  The function core plus **sum-variant** construction and patterns, enough to
  compile a real lexer: multi-clause `def`s (top-level *or* a single `mod`);
  `Int64`/`Float64`/`Bool` literals; variables; binary operators; tuples; cons
  lists (literals + patterns); atoms; sum-variant construction (`TPlus`,
  `TNum(x)`) and patterns → tagged tuples / atoms (`{:t_num, X}` / `:t_plus`,
  the tag = `snake(Ctor)`); `when` guards; local calls; `case`; `if`.

  **Higher-order functions (ADR-0042):** lambdas `(x) -> e` lower to Erlang
  `fun`s, `&name/arity` / `&Mod.fun/arity` to `fun` references, and `&(&1 + …)`
  to a `fun` over generated args. Applying a function-valued *variable* (a
  parameter or a binding) emits a variable application `Var(Args)` — distinct
  from a local function call `name(Args)` — so map/fold-shaped code runs.

  **Strings (ADR-0041):** a `String` literal lowers to the BEAM binary of its
  UTF-8 bytes (an Elixir string is a binary), `<>` to binary concatenation
  (`<<L::binary, R::binary>>`), and a string-literal *pattern* to the matching
  binary — enough for a parser/compiler to carry identifiers, keywords, and
  error text (the lexer spike had to dodge this with integer codepoints).

  **Error handling (ADR-0039):** `with p <- e … do body else arms end` desugars
  to a right-nested `case` — each clause matches its pattern, a catch-all
  dispatches the `else` arms (or passes the non-matching value through when there
  is no `else`).

  **Maps (ADR-0041):** a map literal `%{k: v, …}` lowers to a BEAM map (an
  identifier key `k` is the atom `:k`, the Elixir convention); access/insert ride
  the `Map` FFI (free remote calls). Enough for a symbol-table / environment.

  **Structs (ADR-0043):** a `struct` declaration is erased; a struct *value* is a
  tagged map. Named construction `Name(field: v, …)` builds a map keyed by
  field-name atoms plus `__struct__ => :name`; field access `value.field` reads
  it via `maps:get/2` — no field schema is threaded. A struct *pattern*
  `Name(field: p, …)` matches that tagged map (requiring `__struct__ := :name`
  plus the named fields), and a map *pattern* `%{k: p, …}` matches any map
  carrying those keys.

  **Not yet** (raise a clear error, never a silent miscompile): *positional*
  struct construction (named `Name(f: v)` works) and map *update* (`%{m | k: v}`).
  """
  alias Rian.{Core, Decl, PatternLower, Pratt}

  alias Rian.Core.{
    EAtom,
    EBin,
    EBlock,
    ECall,
    ECapArg,
    ECapture,
    ECaptureNamed,
    ECase,
    EChar,
    EDot,
    EId,
    EIf,
    ELabel,
    ELambda,
    EList,
    EMap,
    ENum,
    EStr,
    ETuple,
    EUnary,
    EWith
  }

  @ln 1

  # signed 64-bit domain — the explicit overflow ops (ADR-0035 §3) project the
  # true (bignum) sum back onto this range
  @i64_max 9_223_372_036_854_775_807
  @i64_min -9_223_372_036_854_775_808

  defmodule Unsupported do
    defexception [:message]
  end

  @doc """
  Compile every top-level function in `src` into one Erlang module named `module`
  and load it. Returns `{:ok, module}` (the loaded module atom) or raises
  `Rian.Beam.Unsupported` for a construct outside this increment's core.
  """
  def load(src, module) when is_atom(module) do
    {:ok, ^module, bin} = compile(src, module)
    {:module, ^module} = :code.load_binary(module, ~c"#{module}.beam", bin)
    {:ok, module}
  end

  @doc "Compile `src`'s functions to `{:ok, module, beam_binary}` via `:compile.forms`."
  def compile(src, module) when is_atom(module) do
    # `struct` declarations contribute no forms — a struct value is a tagged map
    # (built by named construction `Name(f: v)`, read by field access), so the
    # declaration itself is erased; only its constructions/accesses emit.
    prog = Decl.parse(src)
    :ok = Rian.Reach.gate!(prog)
    prog = Rian.Opaque.erase(prog)
    beam_for(module, funcs_of(prog), ranges_of(prog), types_of(prog), structs_of(prog))
  end

  @doc """
  Compile a **multi-module** program: every top-level `mod Name` in `src`
  becomes its own BEAM module named `Elixir.Name`, so a Rian cross-module call
  (`Name.fun(…)` — a Pascal-qualified call) resolves to it. Returns
  `[{module_atom, beam_binary}]`, one per `mod`, in source order.
  """
  def compile_program(src) do
    prog = Decl.parse(src)
    :ok = Rian.Reach.gate!(prog)
    prog = Rian.Opaque.erase(prog)
    top = Map.get(prog, :ranges, [])

    prog
    |> Map.get(:mods, [])
    |> Enum.map(fn m ->
      {:ok, atom, bin} =
        beam_for(
          :"Elixir.#{m.name}",
          m.funcs,
          top ++ Map.get(m, :ranges, []),
          Map.get(m, :types, []),
          Map.get(m, :structs, [])
        )

      {atom, bin}
    end)
  end

  @doc """
  Compile **and load** every `mod` in `src` (see `compile_program/1`). Returns
  the loaded module atoms; cross-`mod` calls between them resolve because each is
  named `Elixir.<Mod>` — the same atom a Pascal-qualified call lowers to.
  """
  def load_program(src) do
    src
    |> compile_program()
    |> Enum.map(fn {atom, bin} ->
      {:module, ^atom} = :code.load_binary(atom, ~c"#{atom}.beam", bin)
      atom
    end)
  end

  @doc """
  Compile a **pre-built program IR** (the `Rian.Decl.parse/1` shape —
  `%{funcs, types, structs, ranges, mods}`) directly, skipping the Elixir parser.

  This is the **Stage-2 self-hosting seam** (ADR-0063): a Rian-written front-end
  produces this IR and the real backend compiles it, with no Elixir parse in the
  loop. Clause bodies may be source strings *or* already-parsed `{:block,…}` ASTs
  — `Pratt.parse_body/1` accepts either (the macro-pipeline passthrough).
  """
  def compile_ir(prog, module) when is_atom(module) do
    :ok = Rian.Reach.gate!(prog)
    prog = Rian.Opaque.erase(prog)
    beam_for(module, funcs_of(prog), ranges_of(prog), types_of(prog), structs_of(prog))
  end

  @doc "Compile and load a pre-built program IR (see `compile_ir/2`)."
  def load_ir(prog, module) when is_atom(module) do
    {:ok, ^module, bin} = compile_ir(prog, module)
    {:module, ^module} = :code.load_binary(module, ~c"#{module}.beam", bin)
    {:ok, module}
  end

  @doc """
  Compile a pre-built **multi-module** program IR (each `%IR.Mod{}` -> its own
  `Elixir.<Mod>` BEAM module) — the Stage-2 seam for a Rian front-end that parses
  `mod` declarations (see `compile_program/1`, IR form).
  """
  def compile_program_ir(prog) do
    prog = Rian.Opaque.erase(prog)
    top = Map.get(prog, :ranges, [])

    prog
    |> Map.get(:mods, [])
    |> Enum.map(fn m ->
      {:ok, atom, bin} =
        beam_for(
          :"Elixir.#{m.name}",
          m.funcs,
          top ++ Map.get(m, :ranges, []),
          Map.get(m, :types, []),
          Map.get(m, :structs, [])
        )

      {atom, bin}
    end)
  end

  @doc "Compile and load a multi-module program IR (see `compile_program_ir/1`)."
  def load_program_ir(prog) do
    prog
    |> compile_program_ir()
    |> Enum.map(fn {atom, bin} ->
      {:module, ^atom} = :code.load_binary(atom, ~c"#{atom}.beam", bin)
      atom
    end)
  end

  # build one module's `.beam` from its function list. `ranges` (a list of
  # `%IR.Range{}`) lets `Name.of(n)` construction desugar (ADR-0036). `types` and
  # `structs` let `-spec` attributes expand sum/struct types (Stage 0.5).
  defp beam_for(module, funcs, ranges, types, structs) do
    funcs = Enum.flat_map(funcs, &beam_func/1)
    rtable = Rian.Range.table(ranges)
    tctx = type_ctx(types, ranges, structs)

    forms =
      [
        {:attribute, @ln, :module, module},
        {:attribute, @ln, :export, Enum.map(funcs, &{String.to_atom(&1.name), arity(&1)})}
      ] ++
        type_attrs(types, structs, tctx) ++
        Enum.map(funcs, &spec_form(&1, tctx)) ++
        Enum.map(funcs, &function_form(&1, rtable))

    # `:debug_info` retains the abstract code (incl. the `-spec` attributes) in
    # the `.beam`, so Dialyzer can read the contracts (Stage 0.5).
    case :compile.forms(forms, [:return_errors, :debug_info]) do
      {:ok, ^module, bin} -> {:ok, module, bin}
      {:ok, ^module, bin, _warnings} -> {:ok, module, bin}
      error -> raise Unsupported, "compile.forms failed: #{inspect(error)}"
    end
  end

  # the functions to compile: a single `mod`'s, else the top-level ones
  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  # an `@external` function (ADR-0068): on the BEAM the `:ex` spec is a Rian-surface
  # host expression, so splice it as the function body — a synthetic clause whose
  # head binds the params — and reuse the normal Core -> abstract-forms FFI lowering.
  # An `@external` with no `:ex` body is honestly off `:ex` and emits nothing.
  defp beam_func(%{externals: ext} = f) when map_size(ext) > 0 do
    case Map.get(ext, :ex) do
      nil ->
        []

      spec ->
        clause = %{pats: Enum.map(f.params, &{:var, &1.name}), body: spec, guard: nil}
        [%{f | clauses: [clause], externals: %{}}]
    end
  end

  defp beam_func(f), do: [f]

  # the type/struct declarations in the same scope as `funcs_of/1`
  defp types_of(%{funcs: [], mods: [m]}), do: Map.get(m, :types, [])
  defp types_of(prog), do: Map.get(prog, :types, [])

  defp structs_of(%{funcs: [], mods: [m]}), do: Map.get(m, :structs, [])
  defp structs_of(prog), do: Map.get(prog, :structs, [])

  # every `range` in scope (top-level + any module's) — for `Name.of` desugaring
  defp ranges_of(prog),
    do:
      Map.get(prog, :ranges, []) ++
        for(m <- Map.get(prog, :mods, []), r <- Map.get(m, :ranges, []), do: r)

  defp arity(%{clauses: [c | _]}), do: length(c.pats)

  # ── `-spec` attributes (Stage 0.5): Dialyzer-checkable contracts ─────────
  # The type context for expanding Rian types into Erlang abstract type forms:
  # sum types (name -> variants), range bases (name -> "Int64"/"Char"), and the
  # set of struct names (a struct value is a tagged map).
  defp type_ctx(types, ranges, structs) do
    %{
      sums: Map.new(types, &{&1.name, &1.variants}),
      ranges: Map.new(ranges, &{&1.name, &1.base}),
      structs: MapSet.new(structs, & &1.name)
    }
  end

  # `-type name() :: …` declarations for the scope's sum and struct types, so a
  # `-spec` can reference `shape()` rather than inline the structure (idiomatic,
  # Dialyzer-friendly). A type name is its snake-cased tag (`Shape` -> `shape`).
  defp type_attrs(types, structs, tctx) do
    Enum.map(types, fn t ->
      {:attribute, @ln, :type, {tag(t.name), sum_form(t.variants, tctx), []}}
    end) ++
      Enum.map(structs, fn s ->
        {:attribute, @ln, :type, {tag(s.name), struct_form(s, tctx), []}}
      end)
  end

  # `-spec name(Arg…) :: Ret` from the declared parameter types and return type.
  # A function whose declared types we cannot pin down still gets a valid spec
  # (`any()` per unknown position), so every function is Dialyzer-analyzable.
  defp spec_form(%{name: name, params: params, ret: ret} = f, tctx) do
    args = Enum.map(params, &type_form(&1.type, tctx))
    fun_t = {:type, @ln, :fun, [{:type, @ln, :product, args}, type_form(ret, tctx)]}
    {:attribute, @ln, :spec, {{String.to_atom(name), arity(f)}, [fun_t]}}
  end

  # a Rian type string -> an Erlang abstract **type form** (for `-spec`/`-type`).
  defp type_form(nil, _tctx), do: any_t()

  defp type_form(t, tctx) when is_binary(t) do
    cond do
      t == "Bool" -> {:type, @ln, :boolean, []}
      t == "String" -> {:type, @ln, :binary, []}
      # `Char` is a codepoint integer on the BEAM (ADR-0036)
      t == "Char" -> int_t()
      t == "Int53" or String.match?(t, ~r/^U?Int\d*$/) -> int_t()
      String.match?(t, ~r/^Float\d*$/) -> {:type, @ln, :float, []}
      String.starts_with?(t, "Vec(") -> {:type, @ln, :list, [type_form(inner_of(t), tctx)]}
      String.starts_with?(t, "Fn(") -> fn_form(t, tctx)
      # `T | E` (error-set sugar / a union) — union of the parts
      top_level_union?(t) -> union_t(Enum.map(split_top(t, "|"), &type_form(&1, tctx)))
      Map.has_key?(tctx.ranges, t) -> type_form(tctx.ranges[t], tctx)
      # a sum / struct value -> a reference to its named `-type` (defined above)
      Map.has_key?(tctx.sums, t) -> {:user_type, @ln, tag(t), []}
      MapSet.member?(tctx.structs, t) -> {:user_type, @ln, tag(t), []}
      # a type variable (`forall T`) or an unknown type -> `any()` (sound)
      true -> any_t()
    end
  end

  # a sum type -> a union of its variants: a nullary variant is its tag atom, a
  # field-carrying variant a tagged tuple `{tag, Field…}` (mirrors construction).
  defp sum_form(variants, tctx) do
    variants
    |> Enum.map(fn
      %{ctor: c, fields: []} ->
        {:atom, @ln, tag(c)}

      %{ctor: c, fields: fs} ->
        {:type, @ln, :tuple, [{:atom, @ln, tag(c)} | Enum.map(fs, &type_form(&1.type, tctx))]}
    end)
    |> union_t()
  end

  # a struct value is either a `__struct__`-tagged map (named construction
  # `Name(f: v)`) or a tagged tuple (positional `Name(v1, v2)`); the `-type` is
  # the union of both representations.
  defp struct_form(%{name: name, fields: fs}, tctx) do
    field_assocs =
      [
        {:type, @ln, :map_field_exact, [{:atom, @ln, :__struct__}, {:atom, @ln, tag(name)}]}
        | Enum.map(fs, fn f ->
            {:type, @ln, :map_field_exact,
             [{:atom, @ln, String.to_atom(f.label)}, type_form(f.type, tctx)]}
          end)
      ]

    map_t = {:type, @ln, :map, field_assocs}

    tuple_t =
      {:type, @ln, :tuple, [{:atom, @ln, tag(name)} | Enum.map(fs, &type_form(&1.type, tctx))]}

    union_t([map_t, tuple_t])
  end

  # `Fn(A1, …, An, R)` -> `fun((a1(), …) -> r())`; `Fn(R)` -> `fun(() -> r())`.
  defp fn_form(t, tctx) do
    parts = t |> String.trim_leading("Fn(") |> String.trim_trailing(")") |> split_top(",")
    {args, [ret]} = Enum.split(parts, length(parts) - 1)

    {:type, @ln, :fun,
     [{:type, @ln, :product, Enum.map(args, &type_form(&1, tctx))}, type_form(ret, tctx)]}
  end

  defp union_t([one]), do: one
  defp union_t(forms), do: {:type, @ln, :union, forms}

  defp int_t, do: {:type, @ln, :integer, []}
  defp any_t, do: {:type, @ln, :any, []}

  defp inner_of("Vec(" <> rest), do: String.trim_trailing(rest, ")")

  defp top_level_union?(t), do: length(split_top(t, "|")) > 1

  # split on a separator at bracket depth 0 (so `Vec(A | B)` / `Fn(A, B)` are atomic)
  defp split_top(s, sep) do
    {parts, cur, _} =
      s
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ch, {ps, cur, 0} when ch == sep -> {[cur | ps], "", 0}
        "(", {ps, cur, d} -> {ps, cur <> "(", d + 1}
        ")", {ps, cur, d} -> {ps, cur <> ")", d - 1}
        ch, {ps, cur, d} -> {ps, cur <> ch, d}
      end)

    [cur | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # ── function / clause forms ─────────────────────────────────────────────
  defp function_form(%{name: name, clauses: clauses}, rtable) do
    {:function, @ln, String.to_atom(name), length(hd(clauses).pats),
     Enum.map(clauses, &clause_form(&1, rtable))}
  end

  defp clause_form(%{pats: pats, body: body, guard: guard}, rtable) do
    core_pats = Enum.map(pats, &Core.from_pat/1)
    # the names bound by the clause head are in scope for the body — so a call to
    # one of them is a *variable application* (a fun value), not a local call
    scope = Enum.reduce(core_pats, %{}, &pat_vars/2)

    {:clause, @ln, Enum.map(core_pats, &pat_form/1), guard_form(guard_core(guard), scope),
     body_forms(body, scope, rtable)}
  end

  # a clause guard is a source string (from `Rian.Decl`) or an already-parsed AST
  # (from a Rian-written front-end, ADR-0063); `Pratt.parse/1` accepts either.
  defp guard_core(nil), do: nil
  defp guard_core(g), do: Core.from_expr(Pratt.parse(g))

  defp guard_form(nil, _scope), do: []
  defp guard_form(core, scope), do: [[expr_form(core, scope)]]

  # a clause body is a non-empty sequence of Erlang expressions; `Name.of(n)`
  # range construction (ADR-0036) is desugared here before lowering
  defp body_forms(src, scope, rtable),
    do: block_forms(Rian.Range.expand_of(Core.from_expr(Pratt.parse_body(src)), rtable), scope)

  # A block statement lowers to one Erlang form *and* threads the block scope
  # (the `map_reduce` reducer in `block_forms`). A `:=` bind emits `Var = Expr`;
  # if the name is already bound it **shadows** (ADR-0034) — and since Erlang is
  # single-assignment, the rebind takes a FRESH Erlang var (`X` -> `X@1` -> `X@2`)
  # and later references to the name resolve to it. The RHS is lowered against the
  # OLD scope, so `a := 8 + a` reads the prior `a` (not the var being bound).
  defp stmt_form({:bind, n, e}, s) do
    rhs = expr_form(e, s)
    {var, s2} = bind_var(n, s)
    {{:match, @ln, {:var, @ln, var}, rhs}, s2}
  end

  # the declared type is erased at lowering — `Int*` is representation intent,
  # not a portable overflow contract (ADR-0034 §1); the value lowers unchanged.
  defp stmt_form({:typed_bind, n, _t, e}, s), do: stmt_form({:bind, n, e}, s)
  defp stmt_form({:expr, e}, s), do: {expr_form(e, s), s}

  # the Erlang var to bind `n` to: its canonical var on the first bind in scope,
  # else a shadow var derived by bumping the current var's version (`X` -> `X@1`).
  # The version lives in the var name, so it is deterministic and unique per name
  # across nested blocks without a counter (user names can't contain `@`).
  defp bind_var(n, s) do
    case Map.get(s, n) do
      nil ->
        base = var_atom(n)
        {base, Map.put(s, n, base)}

      cur ->
        fresh = bump_var(cur)
        {fresh, Map.put(s, n, fresh)}
    end
  end

  defp bump_var(cur) do
    case String.split(Atom.to_string(cur), "@") do
      [base] -> String.to_atom(base <> "@1")
      [base, k] -> String.to_atom(base <> "@" <> Integer.to_string(String.to_integer(k) + 1))
    end
  end

  # ── expression forms (consume the typed core IR, Rian.Core) ────────────
  # `scope` is the set of in-scope bound variable names (clause-head + `:=`
  # bindings + lambda/capture parameters), used to tell a fun-valued variable
  # application apart from a local function call.
  defp expr_form(%ENum{text: n}, _s), do: num_form(n)
  # a Rian `String` is a BEAM binary (Elixir string) — the literal's UTF-8 bytes
  defp expr_form(%EStr{value: s}, _s), do: str_form(s)
  # a `Char` is its codepoint integer on the BEAM (charlists are integer lists)
  defp expr_form(%EChar{value: cp}, _s), do: {:integer, @ln, cp}
  defp expr_form(%EId{name: b}, _s) when b in ~w(true false), do: {:atom, @ln, String.to_atom(b)}
  # `pi` is the math constant — `:math.pi()`, matching the text emitter (`Rian.Lower`)
  defp expr_form(%EId{name: "pi"}, s), do: remote_call(:math, "pi", [], s)
  # a bare PascalCase id is a nullary sum-variant value -> its snake atom tag; a
  # lowercase id is a variable — resolved through the scope to its *current*
  # Erlang var (a `:=` shadow rebinds the name to a fresh var; unshadowed names
  # map to their canonical var, so this is identical to the old behaviour)
  defp expr_form(%EId{name: x}, s),
    do: if(pascal?(x), do: {:atom, @ln, tag(x)}, else: {:var, @ln, Map.get(s, x, var_atom(x))})

  defp expr_form(%EAtom{name: a}, _s), do: {:atom, @ln, String.to_atom(a)}
  defp expr_form(%EUnary{op: "-", arg: x}, s), do: {:op, @ln, :-, expr_form(x, s)}
  defp expr_form(%EUnary{op: "not", arg: x}, s), do: {:op, @ln, :not, expr_form(x, s)}

  # `<>` is binary (String) concatenation, not an arithmetic operator: build a
  # binary that appends both operands as whole binaries (`<<L::binary, R::binary>>`)
  defp expr_form(%EBin{op: "<>", left: l, right: r}, s),
    do: {:bin, @ln, [bin_seg(expr_form(l, s)), bin_seg(expr_form(r, s))]}

  defp expr_form(%EBin{op: op, left: l, right: r}, s),
    do: {:op, @ln, erl_op(op), expr_form(l, s), expr_form(r, s)}

  defp expr_form(%ETuple{elems: es}, s), do: {:tuple, @ln, Enum.map(es, &expr_form(&1, s))}

  # a map literal `%{k: v, …}` -> a BEAM map; an identifier key `k` is the atom
  # `:k` (the Elixir convention `%{x: 1}`), matching the text/JS emitters
  defp expr_form(%EMap{pairs: pairs}, s) do
    {:map, @ln,
     Enum.map(pairs, fn {k, v} ->
       {:map_field_assoc, @ln, {:atom, @ln, String.to_atom(k)}, expr_form(v, s)}
     end)}
  end

  defp expr_form(%EList{elems: es, tail: tail}, s),
    do: cons(es, core_list_tail(tail), &expr_form(&1, s))

  # a remote call `Mod.fun(…)` — free BEAM FFI (ADR-0041): a Pascal head is an
  # Elixir module (`String` -> `'Elixir.String'`), an atom head is an Erlang one
  defp expr_form(%ECall{fun: %EDot{head: %EId{name: m}, name: fun}, args: args}, s),
    do: remote_call(if(pascal?(m), do: :"Elixir.#{m}", else: String.to_atom(m)), fun, args, s)

  defp expr_form(%ECall{fun: %EDot{head: %EAtom{name: m}, name: fun}, args: args}, s),
    do: remote_call(String.to_atom(m), fun, args, s)

  # portable-prelude primitives (ADR-0047 §2): each backend lowers `__prim_*`
  # to its native collection op, and the portable `Map`/`String` ops are written
  # in Rian over them. Here: a BEAM map and `:maps` calls.
  defp expr_form(%ECall{fun: %EId{name: "__prim_map_new"}, args: []}, _s), do: {:map, @ln, []}

  defp expr_form(%ECall{fun: %EId{name: "__prim_map_get"}, args: [m, k]}, s),
    do: remote_call(:maps, "get", [k, m], s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_map_put"}, args: [m, k, v]}, s),
    do: remote_call(:maps, "put", [k, v, m], s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_map_has"}, args: [m, k]}, s),
    do: remote_call(:maps, "is_key", [k, m], s)

  # `String` primitives — a BEAM string is a UTF-8 binary; codepoints round-trip
  # through `String.to_charlist`/`List.to_string`, concat is binary append
  defp expr_form(%ECall{fun: %EId{name: "__prim_str_chars"}, args: [s_]}, s),
    do: remote_call(:"Elixir.String", "to_charlist", [s_], s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_str_from_chars"}, args: [cs]}, s),
    do: remote_call(:"Elixir.List", "to_string", [cs], s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_str_concat"}, args: [a, b]}, s),
    do: {:bin, @ln, [bin_seg(expr_form(a, s)), bin_seg(expr_form(b, s))]}

  # a `Char`'s codepoint — identity on the BEAM, where a `Char` *is* its integer
  defp expr_form(%ECall{fun: %EId{name: "__prim_char_code"}, args: [c]}, s),
    do: expr_form(c, s)

  # integer → string (ADR-0069 interpolation): native `erlang:integer_to_binary/1`
  defp expr_form(%ECall{fun: %EId{name: "__prim_int_to_string"}, args: [n]}, s),
    do: remote_call(:erlang, "integer_to_binary", [n], s)

  # integer → float (ADR-0035 explicit conversion): native `erlang:float/1`
  defp expr_form(%ECall{fun: %EId{name: "__prim_int_to_float"}, args: [n]}, s),
    do: remote_call(:erlang, "float", [n], s)

  # explicit overflow ops (ADR-0035 §3) — BEAM integers are bignums, so each op
  # computes the true sum (once, via an immediately-applied `fun`) and projects it
  # onto the signed 64-bit domain: wrap (two's complement), saturate (clamp), or
  # check (`Option(Int64)` — the sum if in range, else `None`).
  defp expr_form(%ECall{fun: %EId{name: "__prim_wrapping_add"}, args: [a, b]}, s),
    do: i64_overflow(:wrapping, a, b, s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_saturating_add"}, args: [a, b]}, s),
    do: i64_overflow(:saturating, a, b, s)

  defp expr_form(%ECall{fun: %EId{name: "__prim_checked_add"}, args: [a, b]}, s),
    do: i64_overflow(:checked, a, b, s)

  # named construction `Name(field: v, …)` builds a **struct**: a map keyed by
  # field-name atoms plus a `__struct__` tag (the snake-cased name). Field access
  # reads it by name, so no field schema is threaded (ADR-0041 / ADR-0043).
  defp expr_form(%ECall{fun: %EId{name: f}, args: [%ELabel{} | _] = labels}, s) do
    fields =
      Enum.map(labels, fn %ELabel{name: k, expr: v} ->
        {:map_field_assoc, @ln, {:atom, @ln, String.to_atom(k)}, expr_form(v, s)}
      end)

    {:map, @ln,
     [{:map_field_assoc, @ln, {:atom, @ln, :__struct__}, {:atom, @ln, tag(f)}} | fields]}
  end

  # a PascalCase call is sum-variant construction -> a tagged tuple `{tag, args…}`
  # (labels erased, positional); a lowercase call is either a *variable*
  # application (the name is a fun-valued binding) or a local function call
  defp expr_form(%ECall{fun: %EId{name: f}, args: args}, s) do
    arg_forms = Enum.map(args, &expr_form(&1, s))

    cond do
      pascal?(f) -> {:tuple, @ln, [{:atom, @ln, tag(f)} | arg_forms]}
      Map.has_key?(s, f) -> {:call, @ln, {:var, @ln, Map.fetch!(s, f)}, arg_forms}
      true -> {:call, @ln, {:atom, @ln, String.to_atom(f)}, arg_forms}
    end
  end

  # a call to any other callee expression (e.g. an immediately-applied lambda)
  defp expr_form(%ECall{fun: fun, args: args}, s),
    do: {:call, @ln, expr_form(fun, s), Enum.map(args, &expr_form(&1, s))}

  # lambda `(a, b) -> body` -> an Erlang `fun` clause; its params extend the scope
  defp expr_form(%ELambda{params: params, body: body}, s) do
    names = Enum.map(params, fn {n, _} -> n end)
    inner = Enum.reduce(names, s, &Map.put(&2, &1, var_atom(&1)))

    {:fun, @ln,
     {:clauses, [{:clause, @ln, Enum.map(names, &var_form/1), [], body_seq(body, inner)}]}}
  end

  # `&name/arity` — a local fun reference; `&Mod.fun/arity` — a remote one
  defp expr_form(%ECaptureNamed{path: %EId{name: n}, arity: a}, _s),
    do: {:fun, @ln, {:function, String.to_atom(n), a}}

  defp expr_form(%ECaptureNamed{path: %EDot{head: %EId{name: m}, name: fun}, arity: a}, _s),
    do: fun_ref(:"Elixir.#{m}", fun, a)

  defp expr_form(%ECaptureNamed{path: %EDot{head: %EAtom{name: m}, name: fun}, arity: a}, _s),
    do: fun_ref(String.to_atom(m), fun, a)

  # `&(&1 + &2)` — an anonymous fun over generated args `Caparg_1..N`
  defp expr_form(%ECapture{body: body}, s) do
    n = cap_arity(body)
    names = for i <- 1..n//1, do: "caparg_#{i}"
    inner = Enum.reduce(names, s, &Map.put(&2, &1, var_atom(&1)))

    {:fun, @ln,
     {:clauses, [{:clause, @ln, Enum.map(names, &var_form/1), [], body_seq(body, inner)}]}}
  end

  defp expr_form(%ECapArg{n: n}, _s), do: var_form("caparg_#{n}")

  defp expr_form(%EIf{cond: c, then: t, else: e}, s) do
    {:case, @ln, expr_form(c, s),
     [
       {:clause, @ln, [{:atom, @ln, true}], [], body_seq(t, s)},
       {:clause, @ln, [{:atom, @ln, false}], [], body_seq(e, s)}
     ]}
  end

  defp expr_form(%ECase{scrut: scrut, arms: arms}, s) do
    {:case, @ln, expr_form(scrut, s),
     Enum.map(arms, fn {pat, g, body} ->
       # arm-pattern bindings extend the scope for the arm guard and body
       arm = pat_vars(pat, s)
       {:clause, @ln, [pat_form(pat)], guard_form(g, arm), body_seq(body, arm)}
     end)}
  end

  # a block in expression position becomes an Erlang `begin … end`
  defp expr_form(%EBlock{} = b, s), do: {:block, @ln, block_forms(b, s)}

  # `with p1 <- e1; …; pn <- en do body else arms end` (ADR-0039) desugars to a
  # right-nested `case`: each clause matches its pattern, and a catch-all binds
  # the non-matching value to dispatch the `else` arms (or, with no `else`, the
  # value passes through as the `with`'s result)
  defp expr_form(%EWith{clauses: clauses, body: body, els: els}, s),
    do: with_form(clauses, body, els, s, 0)

  # struct field access `value.field` -> `maps:get(field, value)` (a struct is a
  # map keyed by field-name atoms); the ECall/EDot remote-call clauses above
  # already claimed module-qualified calls, so a bare `EDot` here is field access
  defp expr_form(%EDot{head: head, name: field}, s),
    do: remote_call(:maps, "get", [%EAtom{name: field}, head], s)

  defp expr_form(other, _s),
    do: raise(Unsupported, "abstract-forms: expression #{inspect(other)}")

  # the happy path: no clauses left, evaluate the `with` body
  defp with_form([], body, _els, s, _d), do: {:block, @ln, body_seq(body, s)}

  defp with_form([{pat, expr} | rest], body, els, s, d) do
    inner = pat_vars(pat, s)
    catch_var = "_with#{d}"

    {:case, @ln, expr_form(expr, s),
     [
       {:clause, @ln, [pat_form(pat)], [], [with_form(rest, body, els, inner, d + 1)]},
       {:clause, @ln, [var_form(catch_var)], [], [else_dispatch(els, catch_var, s)]}
     ]}
  end

  # with no `else`, a non-matching clause value is the `with`'s result; otherwise
  # it is matched against the `else` arms (case-style)
  defp else_dispatch([], catch_var, _s), do: var_form(catch_var)

  defp else_dispatch(els, catch_var, s) do
    {:case, @ln, var_form(catch_var),
     Enum.map(els, fn {pat, g, body} ->
       arm = pat_vars(pat, s)
       {:clause, @ln, [pat_form(pat)], guard_form(g, arm), body_seq(body, arm)}
     end)}
  end

  # a fun body that may be a single expression or a block
  defp body_seq(%EBlock{} = b, s), do: block_forms(b, s)
  defp body_seq(e, s), do: [expr_form(e, s)]

  # the Erlang body of a clause/block: a non-empty expression sequence, threading
  # each `:=` binding's name into scope for the statements that follow it
  defp block_forms(%EBlock{stmts: []}, _s), do: [{:atom, @ln, nil}]

  defp block_forms(%EBlock{stmts: stmts}, scope) do
    {forms, _} = Enum.map_reduce(stmts, scope, &stmt_form/2)
    forms
  end

  # collect the variable names a core pattern binds (for scope tracking)
  defp pat_vars(%Core.PVar{name: n}, acc), do: Map.put(acc, n, var_atom(n))
  defp pat_vars(%Core.PAs{name: n, pat: p}, acc), do: pat_vars(p, Map.put(acc, n, var_atom(n)))
  defp pat_vars(%Core.PTuple{elems: ps}, acc), do: Enum.reduce(ps, acc, &pat_vars/2)

  defp pat_vars(%Core.PList{elems: ps, tail: t}, acc),
    do: pat_vars(t, Enum.reduce(ps, acc, &pat_vars/2))

  defp pat_vars(%Core.PCtor{args: ps}, acc), do: Enum.reduce(ps, acc, &pat_vars/2)

  defp pat_vars(%Core.PStruct{fields: fs}, acc),
    do: Enum.reduce(fs, acc, fn {_l, p}, a -> pat_vars(p, a) end)

  defp pat_vars(%Core.PMap{pairs: ps}, acc),
    do: Enum.reduce(ps, acc, fn {_k, p}, a -> pat_vars(p, a) end)

  defp pat_vars(_other, acc), do: acc

  # maximum capture placeholder `&N` in an anonymous-capture body -> its arity
  defp cap_arity(%ECapArg{n: n}), do: n
  defp cap_arity(%EBin{left: l, right: r}), do: max(cap_arity(l), cap_arity(r))
  defp cap_arity(%EUnary{arg: x}), do: cap_arity(x)
  defp cap_arity(%EDot{head: h}), do: cap_arity(h)
  defp cap_arity(%ETuple{elems: es}), do: cap_arity_list(es)
  defp cap_arity(%EList{elems: es, tail: :close}), do: cap_arity_list(es)
  defp cap_arity(%EList{elems: es, tail: t}), do: max(cap_arity_list(es), cap_arity(t))
  defp cap_arity(%ECall{fun: f, args: as}), do: cap_arity_list([f | as])
  defp cap_arity(_), do: 0
  defp cap_arity_list(es), do: Enum.reduce(es, 0, &max(cap_arity(&1), &2))

  # ── pattern forms (consume the typed core IR, Rian.Core) ───────────────
  defp pat_form(%Core.PWild{}), do: {:var, @ln, :_}
  defp pat_form(%Core.PVar{name: x}), do: var_form(x)
  defp pat_form(%Core.PChar{value: cp}), do: {:integer, @ln, cp}
  defp pat_form(%Core.PLit{value: v}) when is_integer(v), do: {:integer, @ln, v}
  # a string-literal pattern matches the same binary the literal constructs
  defp pat_form(%Core.PLit{value: v}) when is_binary(v), do: str_form(v)
  defp pat_form(%Core.PAtom{name: a}), do: {:atom, @ln, String.to_atom(a)}
  defp pat_form(%Core.PTuple{elems: ps}), do: {:tuple, @ln, Enum.map(ps, &pat_form/1)}

  defp pat_form(%Core.PList{elems: ps, tail: tail}),
    do: cons(ps, core_list_tail(tail), &pat_form/1)

  # sum-variant patterns mirror construction: nullary -> tag atom, else tagged tuple
  defp pat_form(%Core.PCtor{ctor: name, args: []}), do: {:atom, @ln, tag(name)}

  defp pat_form(%Core.PCtor{ctor: name, args: args}),
    do: {:tuple, @ln, [{:atom, @ln, tag(name)} | Enum.map(args, &pat_form/1)]}

  # a struct pattern `Name(field: p, …)` matches the tagged map a struct value is:
  # it requires `__struct__ := :name` plus each named field (other fields ignored)
  defp pat_form(%Core.PStruct{name: name, fields: fields}) do
    head = {:map_field_exact, @ln, {:atom, @ln, :__struct__}, {:atom, @ln, tag(name)}}
    {:map, @ln, [head | Enum.map(fields, &map_field_pat/1)]}
  end

  # a map pattern `%{k: p, …}` matches any map carrying those keys
  defp pat_form(%Core.PMap{pairs: pairs}),
    do: {:map, @ln, Enum.map(pairs, &map_field_pat/1)}

  defp pat_form(other), do: raise(Unsupported, "abstract-forms: pattern #{inspect(other)}")

  # one `key := pattern` field of a map/struct pattern (the key is an atom)
  defp map_field_pat({k, p}),
    do: {:map_field_exact, @ln, {:atom, @ln, String.to_atom(k)}, pat_form(p)}

  defp core_list_tail(:close), do: {nil, @ln}
  defp core_list_tail(tail), do: tail

  # ── helpers ───────────────────────────────────────────────────────────
  # build a cons chain `[e1, e2 | tail]` with `f` translating each element
  defp cons([], tail, _f) when is_tuple(tail) and elem(tail, 0) == nil, do: tail
  defp cons([], tail, f), do: f.(tail)
  defp cons([h | t], tail, f), do: {:cons, @ln, f.(h), cons(t, tail, f)}

  defp num_form(n) do
    # strip the `_` separators the lexer keeps in a numeric lexeme (`1_000` /
    # `1_000.5`) — `String.to_integer/float` would otherwise raise (the lexer
    # accepts the underscore, so the emitter must too).
    n = String.replace(n, "_", "")

    if String.contains?(n, ".") or String.match?(n, ~r/[eE]/),
      do: {:float, @ln, String.to_float(n)},
      else: {:integer, @ln, String.to_integer(n)}
  end

  # a Rian `String` literal -> the BEAM binary of its UTF-8 bytes (an Elixir
  # string is a UTF-8 binary); `:erlang.binary_to_list/1` yields those raw bytes
  defp str_form(s),
    do:
      {:bin, @ln,
       [{:bin_element, @ln, {:string, @ln, :erlang.binary_to_list(s)}, :default, :default}]}

  # a whole-binary segment for `<>` concatenation (`X::binary`)
  defp bin_seg(form), do: {:bin_element, @ln, form, :default, [:binary]}

  # Rian's snake_case binding -> a legal Erlang variable (leading-cap, `_` kept).
  defp var_form(x), do: {:var, @ln, var_atom(x)}

  # the canonical Erlang variable atom for a Rian name (`n` -> `:N`); `_`/`_x`
  # discards pass through unchanged
  defp var_atom("_"), do: :_
  defp var_atom("_" <> _ = u), do: String.to_atom(u)
  defp var_atom(x), do: String.to_atom(capitalize_first(x))

  defp capitalize_first(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest

  defp erl_op("=="), do: :==
  defp erl_op("!="), do: :"/="
  defp erl_op("<="), do: :"=<"
  defp erl_op(">="), do: :>=
  defp erl_op("<"), do: :<
  defp erl_op(">"), do: :>
  defp erl_op("and"), do: :andalso
  defp erl_op("or"), do: :orelse
  defp erl_op("+"), do: :+
  defp erl_op("-"), do: :-
  defp erl_op("*"), do: :*
  defp erl_op("/"), do: :/
  defp erl_op("div"), do: :div
  defp erl_op("rem"), do: :rem
  defp erl_op(op), do: raise(Unsupported, "abstract-forms: operator `#{op}`")

  defp pascal?(s), do: String.match?(s, ~r/^[A-Z]/)

  # a sum-variant's BEAM tag atom — `snake(Ctor)` (`TNum` -> `:t_num`)
  defp tag(ctor), do: PatternLower.to_snake(ctor)

  defp remote_call(mod, fun, args, scope) do
    {:call, @ln, {:remote, @ln, {:atom, @ln, mod}, {:atom, @ln, String.to_atom(fun)}},
     Enum.map(args, &expr_form(&1, scope))}
  end

  # `(fun (S) -> project(S) end)(A + B)` — bind the bignum sum once, then project
  defp i64_overflow(kind, a, b, s) do
    sum = {:op, @ln, :+, expr_form(a, s), expr_form(b, s)}
    sv = {:var, @ln, :OvfSum}

    {:call, @ln, {:fun, @ln, {:clauses, [{:clause, @ln, [sv], [], [i64_project(kind, sv)]}]}},
     [sum]}
  end

  # two's-complement low 64 bits, then sign-correct (>= 2^63 -> subtract 2^64)
  defp i64_project(:wrapping, sv) do
    low = {:op, @ln, :band, sv, {:integer, @ln, 0xFFFFFFFFFFFFFFFF}}

    {:case, @ln, {:op, @ln, :>=, low, {:integer, @ln, 0x8000000000000000}},
     [
       {:clause, @ln, [{:atom, @ln, true}], [],
        [{:op, @ln, :-, low, {:integer, @ln, 0x10000000000000000}}]},
       {:clause, @ln, [{:atom, @ln, false}], [], [low]}
     ]}
  end

  # clamp into [min, max] via `erlang:max(erlang:min(S, MAX), MIN)`
  defp i64_project(:saturating, sv) do
    capped =
      {:call, @ln, {:remote, @ln, {:atom, @ln, :erlang}, {:atom, @ln, :min}},
       [sv, {:integer, @ln, @i64_max}]}

    {:call, @ln, {:remote, @ln, {:atom, @ln, :erlang}, {:atom, @ln, :max}},
     [capped, {:integer, @ln, @i64_min}]}
  end

  # the sum if it fits the signed 64-bit range, else the `Option` `None` — so
  # `__prim_checked_add` has Rian type `Option(Int64)` (`{:some, S}` / `:none`)
  defp i64_project(:checked, sv) do
    in_range =
      {:op, @ln, :andalso, {:op, @ln, :>=, sv, {:integer, @ln, @i64_min}},
       {:op, @ln, :"=<", sv, {:integer, @ln, @i64_max}}}

    {:case, @ln, in_range,
     [
       {:clause, @ln, [{:atom, @ln, true}], [], [{:tuple, @ln, [{:atom, @ln, :some}, sv]}]},
       {:clause, @ln, [{:atom, @ln, false}], [], [{:atom, @ln, :none}]}
     ]}
  end

  # a remote fun reference `&Mod.fun/arity` (the module/name/arity are literals)
  defp fun_ref(mod, fun, arity) do
    {:fun, @ln,
     {:function, {:atom, @ln, mod}, {:atom, @ln, String.to_atom(fun)}, {:integer, @ln, arity}}}
  end
end
