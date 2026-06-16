defmodule Rian.InferLocal do
  @moduledoc """
  **Infer-local / declare-public** (ADR-0034): fill the types a *private* function
  leaves undeclared by local inference, so a `defp`-style helper needn't write a
  signature the compiler can recover. `pub` functions are untouched — they remain the
  explicit, declared boundary.

  This pass runs after parsing and before `Rian.Check`/the emitters, so everything
  downstream sees fully-typed functions exactly as if the human had written the sig.

  **Phase 1 (here): return types.** For every private function with `ret: nil` (params
  still declared), infer the return from its clause bodies via `Check.infer_return_type/2`
  and write it back. A **fixpoint** handles private→private call chains: a callee's
  return fills first, then its callers see it on the next pass. A return that cannot be
  inferred (e.g. a self-recursive function, or a body touching something unmodelled) is
  left `nil` — honest partiality; the caller (Phase 3) turns that into an
  "annotate this" error rather than a guess.
  """

  alias Rian.{Check, IR}

  @doc "Fill undeclared private-function return types by local inference (ADR-0034)."
  @spec fill_returns(map()) :: map()
  def fill_returns(prog) when is_map(prog), do: fixpoint(prog)

  # rebuild the inference context each round so a return filled this pass is visible
  # to its callers next pass; stop when a pass fills nothing new (bounded by the
  # number of undeclared returns).
  defp fixpoint(prog) do
    ic = Check.program_ic(prog)
    {prog, changed?} = pass(prog, ic)
    if changed?, do: fixpoint(prog), else: prog
  end

  defp pass(prog, ic) do
    {funcs, c1} = fill_funcs(Map.get(prog, :funcs, []), ic)

    {mods, c2} =
      Enum.map_reduce(Map.get(prog, :mods, []), false, fn m, any ->
        {mf, c} = fill_funcs(m.funcs, ic)
        {%{m | funcs: mf}, any or c}
      end)

    {%{prog | funcs: funcs, mods: mods}, c1 or c2}
  end

  defp fill_funcs(funcs, ic) do
    Enum.map_reduce(funcs, false, fn f, changed ->
      with true <- inferable?(f),
           ret when is_binary(ret) <- Check.infer_return_type(f, ic) do
        {%{f | ret: ret}, true}
      else
        _ -> {f, changed}
      end
    end)
  end

  # only private functions with an undeclared return are filled — `pub` is the
  # declared boundary, and an already-typed return is left as the human wrote it.
  defp inferable?(%IR.Func{pub?: false, ret: nil}), do: true
  defp inferable?(_), do: false
end
