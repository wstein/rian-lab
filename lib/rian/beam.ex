defmodule Rian.Beam do
  @moduledoc """
  Erlang **abstract-forms** backend (ADR-0031 / ADR-0026) — the real-compilation
  path that replaces `Code.eval_string` of emitted source.

  Instead of producing Elixir text and `eval`-ing it, this lowers a parsed Rian
  function group directly to the **Erlang abstract format** and runs it through
  `:compile.forms/2`, yielding actual `.beam` bytecode that `:code.load_binary/3`
  loads as a real module. This is the bootstrap target: no Elixir-compiler
  dependency, a reproducible artifact, real error locations (line is tracked).

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
    beam_for(module, src |> Decl.parse() |> funcs_of())
  end

  @doc """
  Compile a **multi-module** program: every top-level `mod Name` in `src`
  becomes its own BEAM module named `Elixir.Name`, so a Rian cross-module call
  (`Name.fun(…)` — a Pascal-qualified call) resolves to it. Returns
  `[{module_atom, beam_binary}]`, one per `mod`, in source order.
  """
  def compile_program(src) do
    src
    |> Decl.parse()
    |> Map.get(:mods, [])
    |> Enum.map(fn m ->
      {:ok, atom, bin} = beam_for(:"Elixir.#{m.name}", m.funcs)
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

  # build one module's `.beam` from its function list
  defp beam_for(module, funcs) do
    forms =
      [
        {:attribute, @ln, :module, module},
        {:attribute, @ln, :export, Enum.map(funcs, &{String.to_atom(&1.name), arity(&1)})}
      ] ++ Enum.map(funcs, &function_form/1)

    case :compile.forms(forms, [:return_errors]) do
      {:ok, ^module, bin} -> {:ok, module, bin}
      {:ok, ^module, bin, _warnings} -> {:ok, module, bin}
      error -> raise Unsupported, "compile.forms failed: #{inspect(error)}"
    end
  end

  # the functions to compile: a single `mod`'s, else the top-level ones
  defp funcs_of(%{funcs: [], mods: [m]}), do: m.funcs
  defp funcs_of(%{funcs: funcs}), do: funcs

  defp arity(%{clauses: [c | _]}), do: length(c.pats)

  # ── function / clause forms ─────────────────────────────────────────────
  defp function_form(%{name: name, clauses: clauses}) do
    {:function, @ln, String.to_atom(name), length(hd(clauses).pats),
     Enum.map(clauses, &clause_form/1)}
  end

  defp clause_form(%{pats: pats, body: body, guard: guard}) do
    core_pats = Enum.map(pats, &Core.from_pat/1)
    # the names bound by the clause head are in scope for the body — so a call to
    # one of them is a *variable application* (a fun value), not a local call
    scope = Enum.reduce(core_pats, MapSet.new(), &pat_vars/2)

    {:clause, @ln, Enum.map(core_pats, &pat_form/1), guard_form(guard_core(guard), scope),
     body_forms(body, scope)}
  end

  # a clause guard is a source string (from `Rian.Decl`); normalize to core (or nil)
  defp guard_core(nil), do: nil
  defp guard_core(g) when is_binary(g), do: Core.from_expr(Pratt.parse(g))

  defp guard_form(nil, _scope), do: []
  defp guard_form(core, scope), do: [[expr_form(core, scope)]]

  # a clause body is a non-empty sequence of Erlang expressions
  defp body_forms(src, scope), do: block_forms(Core.from_expr(Pratt.parse_body(src)), scope)

  defp stmt_form({:bind, n, e}, scope), do: {:match, @ln, var_form(n), expr_form(e, scope)}
  defp stmt_form({:expr, e}, scope), do: expr_form(e, scope)

  # ── expression forms (consume the typed core IR, Rian.Core) ────────────
  # `scope` is the set of in-scope bound variable names (clause-head + `:=`
  # bindings + lambda/capture parameters), used to tell a fun-valued variable
  # application apart from a local function call.
  defp expr_form(%ENum{text: n}, _s), do: num_form(n)
  # a Rian `String` is a BEAM binary (Elixir string) — the literal's UTF-8 bytes
  defp expr_form(%EStr{value: s}, _s), do: str_form(s)
  defp expr_form(%EId{name: b}, _s) when b in ~w(true false), do: {:atom, @ln, String.to_atom(b)}
  # a bare PascalCase id is a nullary sum-variant value -> its snake atom tag
  defp expr_form(%EId{name: x}, _s),
    do: if(pascal?(x), do: {:atom, @ln, tag(x)}, else: var_form(x))

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
      MapSet.member?(s, f) -> {:call, @ln, var_form(f), arg_forms}
      true -> {:call, @ln, {:atom, @ln, String.to_atom(f)}, arg_forms}
    end
  end

  # a call to any other callee expression (e.g. an immediately-applied lambda)
  defp expr_form(%ECall{fun: fun, args: args}, s),
    do: {:call, @ln, expr_form(fun, s), Enum.map(args, &expr_form(&1, s))}

  # lambda `(a, b) -> body` -> an Erlang `fun` clause; its params extend the scope
  defp expr_form(%ELambda{params: params, body: body}, s) do
    names = Enum.map(params, fn {n, _} -> n end)
    inner = Enum.reduce(names, s, &MapSet.put(&2, &1))

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
    inner = Enum.reduce(names, s, &MapSet.put(&2, &1))

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
    {forms, _} =
      Enum.map_reduce(stmts, scope, fn stmt, s -> {stmt_form(stmt, s), grow_scope(s, stmt)} end)

    forms
  end

  defp grow_scope(s, {:bind, n, _}), do: MapSet.put(s, n)
  defp grow_scope(s, _), do: s

  # collect the variable names a core pattern binds (for scope tracking)
  defp pat_vars(%Core.PVar{name: n}, acc), do: MapSet.put(acc, n)
  defp pat_vars(%Core.PAs{name: n, pat: p}, acc), do: pat_vars(p, MapSet.put(acc, n))
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
  defp var_form("_"), do: {:var, @ln, :_}
  defp var_form("_" <> _ = u), do: {:var, @ln, String.to_atom(u)}
  defp var_form(x), do: {:var, @ln, String.to_atom(capitalize_first(x))}

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

  # a remote fun reference `&Mod.fun/arity` (the module/name/arity are literals)
  defp fun_ref(mod, fun, arity) do
    {:fun, @ln,
     {:function, {:atom, @ln, mod}, {:atom, @ln, String.to_atom(fun)}, {:integer, @ln, arity}}}
  end
end
