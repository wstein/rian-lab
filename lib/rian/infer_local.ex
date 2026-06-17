defmodule Rian.InferLocal do
  @moduledoc """
  **Infer-local / declare-public** (ADR-0034): fill the types a *private* function
  leaves undeclared by local inference, so a `defp`-style helper needn't write a
  signature the compiler can recover. `pub` functions are untouched — they remain the
  explicit, declared boundary.

  This pass runs after parsing (`Rian.Decl.parse`) and before `Rian.Check`/the emitters,
  so everything downstream sees fully-typed functions exactly as if the human had written
  the sig.

  **Scope: parameters and return types.** A lone lowercase parameter token (`def f(x)`,
  ADR-0034 casing rule) parses with `type: :infer`; a private function with `ret: nil`
  omits its return. Each fixpoint round fills **params first, then the return** (a return
  needs its param types): `Check.infer_param_type/3` recovers a param's type
  bidirectionally — an operator, a string concat, a typed callee, or a clause-head
  pattern pushes its *expected* type onto the variable — and `Check.infer_return_type/2`
  joins the clause bodies. A **fixpoint** handles private→private chains (a callee's
  types fill first, then its callers see them). After the fixpoint, any param the body
  left *unconstrained* (a pass-through like `def id(x) := x`) is **generalized to a fresh
  `forall T`** type variable. A return that still cannot be inferred (self-recursion, an
  `@external` with no body, an unmodelled body) — or a param used at *conflicting* types —
  raises a clear *"annotate it"* error rather than reaching the checker unresolved: sound
  partiality, never a guess.

  `pub`/`@external` boundaries are untouched: a lone lowercase token there keeps its
  legacy permissive anonymous-typed reading (the token is the param's type) — the
  self-hosted dispatchers (`pub def lower_pat(p) Pat`) rely on it. The invariant: no
  `:infer` survives this pass.
  """

  alias Rian.{Check, IR, Pratt}

  @doc """
  Fill undeclared private-function return types by local inference (ADR-0034). A
  no-op (no inference context built) unless some private function omitted its return.
  A return that cannot be inferred — self-recursion, an `@external` with no body, a
  body touching something unmodelled — raises a clear "annotate it" error rather than
  letting a `nil` return reach the checker.
  """
  @spec fill_returns(map()) :: map()
  def fill_returns(prog) when is_map(prog) do
    if Enum.any?(all_funcs(prog), &(untyped_ret?(&1) or has_infer_param?(&1))) do
      # Parse every clause body to its AST ONCE up front. The fixpoint below re-reads
      # each body on every round (per `:infer` param, per round); since `Pratt.parse_body`
      # passes an already-parsed AST through unchanged and `IR.Clause` permits an AST
      # body, parsing once here turns those repeated tokenize+parse passes into O(1)
      # passthroughs — for the fixpoint and for every downstream consumer.
      prog = parse_bodies(prog)

      # 1. resolve params + returns with NO arithmetic default (`:unknown`), so a param
      #    is never frozen to `Int53` from a neighbour that may still resolve (a not-yet-
      #    typed callee); 2. re-run with the `Int53` default now that every neighbour has
      #    settled, pinning genuinely-unconstrained arithmetic params (`x + y` → `Int53`);
      #    3. generalize any param still unconstrained to `forall T`; 4. fix returns that
      #    depended on the above.
      prog =
        prog
        |> fixpoint(:unknown)
        |> fixpoint("Int53")
        |> generalize_params()
        |> fixpoint("Int53")

      case Enum.filter(all_funcs(prog), &untyped_ret?/1) do
        [] ->
          prog

        [%IR.Func{name: n} | _] ->
          raise Rian.Decl.Error,
                "cannot infer the return type of private `#{n}` — annotate it " <>
                  "(`def #{n}(…) <Type> := …`)"
      end
    else
      prog
    end
  end

  defp all_funcs(prog),
    do: Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

  # parse every clause body to its AST once (idempotent: `parse_body` passes an
  # already-parsed AST through), so the fixpoint and downstream emitters reuse it.
  defp parse_bodies(prog) do
    pb = fn f ->
      %{f | clauses: Enum.map(f.clauses, fn c -> %{c | body: Pratt.parse_body(c.body)} end)}
    end

    prog
    |> Map.update(:funcs, [], fn fs -> Enum.map(fs, pb) end)
    |> Map.update(:mods, [], fn ms ->
      Enum.map(ms, fn m -> %{m | funcs: Enum.map(m.funcs, pb)} end)
    end)
  end

  defp untyped_ret?(%IR.Func{pub?: false, ret: nil}), do: true
  defp untyped_ret?(_), do: false

  defp has_infer_param?(%IR.Func{pub?: false, params: ps}),
    do: Enum.any?(ps, &(&1.type == :infer))

  defp has_infer_param?(_), do: false

  # rebuild the inference context each round so a param/return filled this pass is
  # visible to its callers next pass; stop when a pass fills nothing new (bounded by
  # the number of undeclared params + returns).
  defp fixpoint(prog, num_default) do
    ic = Map.put(Check.program_ic(prog), :num_default, num_default)
    {prog, changed?} = pass(prog, ic)
    if changed?, do: fixpoint(prog, num_default), else: prog
  end

  defp pass(prog, ic) do
    {funcs, c1} = fill_step(Map.get(prog, :funcs, []), ic)

    {mods, c2} =
      Enum.map_reduce(Map.get(prog, :mods, []), false, fn m, any ->
        {mf, c} = fill_step(m.funcs, ic)
        {%{m | funcs: mf}, any or c}
      end)

    {%{prog | funcs: funcs, mods: mods}, c1 or c2}
  end

  # params first (a return needs its param types), then the return.
  defp fill_step(funcs, ic) do
    {funcs, cp} = fill_params(funcs, ic)
    {funcs, cr} = fill_funcs(funcs, ic)
    {funcs, cp or cr}
  end

  defp fill_params(funcs, ic) do
    Enum.map_reduce(funcs, false, fn f, changed ->
      if has_infer_param?(f) do
        {f2, c} = solve_concrete_params(f, ic)
        {f2, changed or c}
      else
        {f, changed}
      end
    end)
  end

  # fill only the params whose type is provable NOW (a concrete result). Leave an
  # unconstrained `:infer` param for a later round (a callee may not be typed yet) or
  # for generalization once the fixpoint settles. A provable conflict raises.
  defp solve_concrete_params(%IR.Func{params: ps} = f, ic) do
    {ps, changed} =
      ps
      |> Enum.with_index()
      |> Enum.map_reduce(false, fn {p, i}, ch ->
        case p.type == :infer && Check.infer_param_type(f, i, ic) do
          t when is_binary(t) ->
            {%{p | type: t}, true}

          :mismatch ->
            raise Rian.Decl.Error,
                  "parameter `#{p.name}` of private `#{f.name}` is used at conflicting " <>
                    "types — annotate it (`def #{f.name}(#{p.name} <Type>) …`)"

          _ ->
            {p, ch}
        end
      end)

    {%{f | params: ps}, changed}
  end

  # any param the body left unconstrained is parametric: generalize it to a fresh
  # `forall T` type variable (the user-chosen policy) so pass-through helpers like
  # `def id(x) := x` work across types without an annotation.
  defp generalize_params(prog) do
    prog
    |> Map.update(:funcs, [], fn fs -> Enum.map(fs, &generalize_func/1) end)
    |> Map.update(:mods, [], fn ms ->
      Enum.map(ms, fn m -> %{m | funcs: Enum.map(m.funcs, &generalize_func/1)} end)
    end)
  end

  defp generalize_func(%IR.Func{pub?: false, params: ps, tvars: tvs} = f) do
    if Enum.any?(ps, &(&1.type == :infer)) do
      {ps, tvs} =
        Enum.map_reduce(ps, tvs, fn p, used ->
          if p.type == :infer do
            tv = fresh_tvar(used)
            {%{p | type: tv}, used ++ [tv]}
          else
            {p, used}
          end
        end)

      %{f | params: ps, tvars: tvs}
    else
      f
    end
  end

  defp generalize_func(f), do: f

  # the first unused type-variable name. Single letters first (T, U, … Z, A … S),
  # then letter+digit (`A0` … `Z9`) — the whole space `Rian.Check`'s `tvar?` accepts
  # (`^[A-Z][0-9]?$`). Exhausting all 286 (286+ generalized params in one function)
  # raises rather than reusing a name: a duplicate tvar would collapse two parameters'
  # independent polymorphism into a spurious equality (sound partiality, never a guess).
  defp fresh_tvar(used) do
    letters = Enum.map(?T..?Z, &<<&1>>) ++ Enum.map(?A..?S, &<<&1>>)
    numbered = for l <- ?A..?Z, d <- ?0..?9, do: <<l, d>>

    case Enum.find(letters ++ numbered, &(&1 not in used)) do
      nil ->
        raise Rian.Decl.Error,
              "too many inferred type variables in one function (>#{length(letters ++ numbered)}) " <>
                "— annotate some parameter types"

      tv ->
        tv
    end
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
