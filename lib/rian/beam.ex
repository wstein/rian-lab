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

  The **primitive function core**, enough to compile real recursive functions to
  bytecode: multi-clause `def`s; `Int64`/`Float64`/`Bool` literals; variables;
  binary arithmetic/comparison/boolean operators; tuples; cons-list literals and
  patterns; atoms; `when` guards; local calls; `case`; `if`.

  **Not yet** (raise a clear error, never a silent miscompile): user sum/struct
  *construction* and patterns (need the variant→tagged-tuple meta — the next
  increment), `String` literals/`<>`, remote/FFI calls, `with`. Functions using
  those still go through the interim Elixir-source path (`Rian.Lower`).
  """
  alias Rian.{Decl, Pratt}

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

  @doc "Compile top-level functions of `src` to `{:ok, module, beam_binary}` via `:compile.forms`."
  def compile(src, module) when is_atom(module) do
    %{funcs: funcs} = Decl.parse(src)

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

  defp arity(%{clauses: [c | _]}), do: length(c.pats)

  # ── function / clause forms ─────────────────────────────────────────────
  defp function_form(%{name: name, clauses: clauses}) do
    {:function, @ln, String.to_atom(name), length(hd(clauses).pats),
     Enum.map(clauses, &clause_form/1)}
  end

  defp clause_form(%{pats: pats, body: body, guard: guard}) do
    {:clause, @ln, Enum.map(pats, &pat_form/1), guard_form(guard), body_forms(body)}
  end

  # a clause guard is a source string (from `Rian.Decl`); a case-arm guard is AST
  defp guard_form(nil), do: []
  defp guard_form(g) when is_binary(g), do: [[expr_form(Pratt.parse(g))]]
  defp guard_form(g), do: [[expr_form(g)]]

  # a clause body is a non-empty sequence of Erlang expressions
  defp body_forms(src), do: block_forms(Pratt.parse_body(src))

  defp stmt_form({:bind, n, e}), do: {:match, @ln, var_form(n), expr_form(e)}
  defp stmt_form({:expr, e}), do: expr_form(e)

  # ── expression forms ──────────────────────────────────────────────────
  defp expr_form({:num, n}), do: num_form(n)
  defp expr_form({:id, b}) when b in ~w(true false), do: {:atom, @ln, String.to_atom(b)}
  defp expr_form({:id, x}), do: if(pascal?(x), do: ctor_todo(x), else: var_form(x))
  defp expr_form({:atom, a}), do: {:atom, @ln, String.to_atom(a)}
  defp expr_form({:unary, "-", x}), do: {:op, @ln, :-, expr_form(x)}
  defp expr_form({:unary, "not", x}), do: {:op, @ln, :not, expr_form(x)}
  defp expr_form({:bin, op, l, r}), do: {:op, @ln, erl_op(op), expr_form(l), expr_form(r)}
  defp expr_form({:tuple, es}), do: {:tuple, @ln, Enum.map(es, &expr_form/1)}
  defp expr_form({:list_lit, es, tail}), do: cons(es, list_tail(tail), &expr_form/1)

  defp expr_form({:call, {:id, f}, args}) do
    if pascal?(f), do: ctor_todo(f)
    {:call, @ln, {:atom, @ln, String.to_atom(f)}, Enum.map(args, &expr_form/1)}
  end

  defp expr_form({:if, c, t, e}) do
    {:case, @ln, expr_form(c),
     [
       {:clause, @ln, [{:atom, @ln, true}], [], block_forms(t)},
       {:clause, @ln, [{:atom, @ln, false}], [], block_forms(e)}
     ]}
  end

  defp expr_form({:case, scrut, arms}) do
    {:case, @ln, expr_form(scrut),
     Enum.map(arms, fn {pat, g, body} ->
       {:clause, @ln, [pat_form(pat)], guard_form(g), [expr_form(body)]}
     end)}
  end

  # a block in expression position becomes an Erlang `begin … end`
  defp expr_form({:block, stmts}), do: {:block, @ln, block_forms({:block, stmts})}
  defp expr_form(other), do: raise(Unsupported, "abstract-forms: expression #{inspect(other)}")

  # the Erlang body of a clause/block: a non-empty expression sequence
  defp block_forms({:block, []}), do: [{:atom, @ln, nil}]
  defp block_forms({:block, stmts}), do: Enum.map(stmts, &stmt_form/1)

  # ── pattern forms ─────────────────────────────────────────────────────
  defp pat_form(:wild), do: {:var, @ln, :_}
  defp pat_form({:var, x}), do: var_form(x)
  defp pat_form({:lit, v}) when is_integer(v), do: {:integer, @ln, v}
  defp pat_form({:atom, a}), do: {:atom, @ln, String.to_atom(a)}
  defp pat_form({:tuple, ps}), do: {:tuple, @ln, Enum.map(ps, &pat_form/1)}
  defp pat_form({:list, ps, tail}), do: cons(ps, list_tail(tail), &pat_form/1)
  defp pat_form(other), do: raise(Unsupported, "abstract-forms: pattern #{inspect(other)}")

  # ── helpers ───────────────────────────────────────────────────────────
  defp list_tail(:close), do: {nil, @ln}
  defp list_tail(nil), do: {nil, @ln}
  defp list_tail({:tail, t}), do: t

  # build a cons chain `[e1, e2 | tail]` with `f` translating each element
  defp cons([], tail, _f) when is_tuple(tail) and elem(tail, 0) == nil, do: tail
  defp cons([], tail, f), do: f.(tail)
  defp cons([h | t], tail, f), do: {:cons, @ln, f.(h), cons(t, tail, f)}

  defp num_form(n) do
    if String.contains?(n, ".") or String.match?(n, ~r/[eE]/),
      do: {:float, @ln, String.to_float(n)},
      else: {:integer, @ln, String.to_integer(n)}
  end

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

  defp ctor_todo(name),
    do:
      raise(
        Unsupported,
        "abstract-forms: constructor/type `#{name}` needs variant meta (next increment)"
      )
end
