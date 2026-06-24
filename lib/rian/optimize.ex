defmodule Rian.Optimize do
  @moduledoc """
  Post-CHECK semantic simplification (ADR-0046 §3, "dead-arm elimination").

  Distinct from `Rian.Comptime.fold_constants`, which is a *pre*-check, variable-neutral pass.
  These simplifications **eliminate a branch or an operator over a variable**, which removes code
  the checker/`InferLocal`/`Reach` would otherwise read — so they must run **after** the type
  checker has validated the whole program (else they would mask a branch-type-mismatch error or
  change an inferred parameter type). The consumer pipeline is therefore: parse → **check the
  original** → `simplify` → **`Reach` on the simplified program** (so the portability matrix is
  honest about the code actually emitted) → emit.

  A pure surface AST → AST pass over each clause body (the same body representation
  `Rian.Comptime.fold_constants` rewrites), composed by the emit front-ends, never by `Decl.parse`
  (so the bare `parse → emit` parity path is untouched). Idempotent; a body it does not change keeps
  its source-string form.

  - **#2 dead-`if`** — a constant condition selects its branch (`if false do A else B end` → `B`).
  - **#3 constant-`case`** — a literal (int/string) scrutinee selects the matching arm
    (`case 2 do 1 -> a; 2 -> b; _ -> c end` → `b`); conservative (a `var`/ctor pattern or a guard
    stops the selection, no binding/guard semantics guessed).
  - **#4 boolean identities** — the evaluation-preserving ones (`true and x` → `x`, `x and true` →
    `x`, `false or x` → `x`, `x or false` → `x`); the value-dropping pair is left to the backend.
  """
  use Rian.Ann

  alias Rian.{Comptime, Interp, Macro, Pratt}

  @rian_sig "pub def simplify(prog Prog) Prog"
  @spec simplify(map()) :: map()
  def simplify(prog) do
    ctx = %{funcs: inlinable_registry(prog), inlining: MapSet.new()}
    each = fn funcs -> Enum.map(funcs, &simplify_func(&1, ctx)) end

    prog
    |> Map.put(:funcs, each.(Map.get(prog, :funcs, [])))
    |> Map.put(
      :mods,
      Enum.map(Map.get(prog, :mods, []), fn m -> %{m | funcs: each.(m.funcs)} end)
    )
  end

  defp simplify_func(%{clauses: cs} = func, ctx),
    do: %{func | clauses: Enum.map(cs, &simplify_clause(&1, ctx))}

  defp simplify_clause(%{body: nil} = c, _ctx), do: c

  defp simplify_clause(%{body: body} = c, ctx) do
    ast = Pratt.parse_body(body)

    # the expression simplifications (#2/#3/#4), then constant call inlining (the registry-driven
    # one), then the interpolation re-bake — so a hole inlining just made constant (`${sq(2, 3)}` →
    # `__prim_int_to_string(25)`) bakes into the surrounding text (ADR-0046 §5). One pass, no fixpoint.
    out = ast |> simplify_expr() |> inline_const_calls(ctx) |> Interp.rebake()
    if out == ast, do: c, else: %{c | body: out}
  end

  # name → `{param_names, body}` for functions a constant call can evaluate at COMPILE time
  # (ADR-0046/0030): single-clause, every param a plain `var`, no guard, binder-free body. Built from
  # the whole program. An ill-typed / effectful body never folds to a constant → never inlined; the
  # checker has already run (this is a post-check pass), so the inlined call cannot mask an arg-type
  # error the way pre-check folding would.
  defp inlinable_registry(prog) do
    all = Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)

    for %{name: n, clauses: [%{pats: pats, body: body, guard: nil}], synthetic: false} <- all,
        body != nil,
        Enum.all?(pats, &match?({:var, _}, &1)),
        ast = Pratt.parse_body(body),
        Comptime.inlinable_body?(ast),
        into: %{} do
      {n, {Enum.map(pats, fn {:var, p} -> p end), ast}}
    end
  end

  # #5 constant function-call inlining: `sq(2, 3)` over `def sq(a, b) := (a + b) * (a + b)` → `25`.
  # On a call to an inlinable function with all-literal args (and not already inlining it), substitute
  # the args, then INLINE NESTED constant calls, then `fold_constants` the operators — and use the
  # result ONLY if it reduced to a literal (so a body with FFI/an un-foldable shape is left a call).
  defp inline_const_calls({:call, {:id, f}, args}, ctx),
    do: inline_call(f, Enum.map(args, &inline_const_calls(&1, ctx)), ctx)

  defp inline_const_calls(node, ctx), do: Macro.map_node(node, &inline_const_calls(&1, ctx))

  defp inline_call(f, args, ctx) do
    with {params, body} <- Map.get(ctx.funcs, f),
         true <- length(params) == length(args),
         true <- Enum.all?(args, &Comptime.literal?/1),
         false <- MapSet.member?(ctx.inlining, f),
         subst = Map.new(Enum.zip(params, args)),
         inner = %{ctx | inlining: MapSet.put(ctx.inlining, f)},
         folded =
           body
           |> Comptime.substitute(subst)
           |> inline_const_calls(inner)
           |> Comptime.fold_constants()
           |> Comptime.unwrap_block(),
         true <- Comptime.literal?(folded) do
      folded
    else
      _ -> {:call, {:id, f}, args}
    end
  end

  @doc "Simplify one surface expression (exposed for the `opt` parity stream / tests)."
  @rian_sig "pub def simplify_expr(node Expr) Expr"
  @spec simplify_expr(term()) :: term()
  # #2 dead-`if`: a now-constant condition (folded by `fold_constants` earlier) selects its branch;
  # the other branch — and any type error or Reach pin it carried — is dropped (sound here: the
  # checker already validated BOTH branches; Reach runs after this pass).
  def simplify_expr({:if, cond, then_b, else_b}) do
    case simplify_expr(cond) do
      {:id, "true"} -> simplify_expr(then_b)
      {:id, "false"} -> simplify_expr(else_b)
      cond2 -> {:if, cond2, simplify_expr(then_b), simplify_expr(else_b)}
    end
  end

  # #4 boolean identities — only the evaluation-PRESERVING ones (`true and x` → `x`, `x and true` →
  # `x`, `false or x` → `x`, `x or false` → `x`). No operand is dropped, so the emitted code keeps
  # every value `Reach` analysed (the dropping pair `false and x` → `false` is left to the backend's
  # short-circuit). Sound post-check: the checker already pinned `x : Bool` from this `and`/`or`.
  def simplify_expr({:bin, "and", l, r}) do
    case {simplify_expr(l), simplify_expr(r)} do
      {{:id, "true"}, r2} -> r2
      {l2, {:id, "true"}} -> l2
      {l2, r2} -> {:bin, "and", l2, r2}
    end
  end

  def simplify_expr({:bin, "or", l, r}) do
    case {simplify_expr(l), simplify_expr(r)} do
      {{:id, "false"}, r2} -> r2
      {l2, {:id, "false"}} -> l2
      {l2, r2} -> {:bin, "or", l2, r2}
    end
  end

  # #3 constant-`case` arm selection: a constant scrutinee picks the matching arm at compile time
  # (`case 2 do 1 -> a; 2 -> b; _ -> c end` → `b`). CONSERVATIVE — fires only when the scrutinee is a
  # literal (num/string/bool) and every arm up to the match is a literal pattern (so its match/no-match
  # is decidable) or a final wildcard, with NO guard. A `var`/ctor/tuple pattern or a guard stops the
  # selection (the case is kept, its scrutinee + arm bodies simplified), so no binding/guard semantics
  # is ever guessed. Sound post-check: the checker validated every arm before this runs.
  def simplify_expr({:case, scrut, arms}) do
    scrut2 = simplify_expr(scrut)

    case select_const_arm(scrut2, arms) do
      {:ok, body} -> simplify_expr(body)
      :no -> {:case, scrut2, Enum.map(arms, fn {p, g, b} -> {p, g, simplify_expr(b)} end)}
    end
  end

  def simplify_expr(node), do: Macro.map_node(node, &simplify_expr/1)

  defp select_const_arm(scrut, arms) do
    case scrut_value(scrut) do
      {:ok, val} -> match_arm(arms, val)
      :no -> :no
    end
  end

  defp match_arm([], _val), do: :no
  defp match_arm([{_pat, guard, _body} | _], _val) when guard != nil, do: :no

  defp match_arm([{{:lit, v}, nil, body} | rest], val),
    do: if(v == val, do: {:ok, body}, else: match_arm(rest, val))

  defp match_arm([{:wild, nil, body} | _], _val), do: {:ok, body}

  # a `var`/ctor/tuple/… pattern: matching it would need binding or a kind we don't decide — stop.
  defp match_arm([_arm | _], _val), do: :no

  # the compile-time value of a constant scrutinee. INTEGER and STRING only — a `{:lit, _}` pattern is
  # an int (`PLitInt`) or string (`PLitStr`); a float scrutinee has no matching literal-pattern kind,
  # so it is not selected (matches the PureScript twin and dodges float-pattern ambiguity).
  defp scrut_value({:num, n}) do
    clean = String.replace(n, "_", "")

    if String.contains?(clean, ".") or String.match?(clean, ~r/[eE]/),
      do: :no,
      else: {:ok, String.to_integer(clean)}
  end

  defp scrut_value({:str, s}), do: {:ok, s}

  # num/string only — a `Bool`/`Char`/atom pattern is a `var`/atom node (no `{:lit, _}`), so a `case`
  # over one is never selected (both this and the PureScript twin keep it). Keeps the two in parity.
  defp scrut_value(_), do: :no
end
