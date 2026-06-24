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
  """
  use Rian.Ann

  alias Rian.{Macro, Pratt}

  @rian_sig "pub def simplify(prog Prog) Prog"
  @spec simplify(map()) :: map()
  def simplify(prog) do
    each = fn funcs -> Enum.map(funcs, &simplify_func/1) end

    prog
    |> Map.put(:funcs, each.(Map.get(prog, :funcs, [])))
    |> Map.put(
      :mods,
      Enum.map(Map.get(prog, :mods, []), fn m -> %{m | funcs: each.(m.funcs)} end)
    )
  end

  defp simplify_func(%{clauses: cs} = func),
    do: %{func | clauses: Enum.map(cs, &simplify_clause/1)}

  defp simplify_clause(%{body: nil} = c), do: c

  defp simplify_clause(%{body: body} = c) do
    ast = Pratt.parse_body(body)
    out = simplify_expr(ast)
    if out == ast, do: c, else: %{c | body: out}
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

  def simplify_expr(node), do: Macro.map_node(node, &simplify_expr/1)
end
