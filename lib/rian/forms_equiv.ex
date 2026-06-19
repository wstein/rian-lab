defmodule Rian.FormsEquiv do
  @moduledoc """
  **Normalized-forms equivalence** between a reference Elixir module and the same
  logic compiled through Rian (`Rian.Beam`) — the verification oracle for the
  Elixir→Rian transpile track (`Rian.Transpile`).

  Byte-identical `.beam` is *unreachable* between two different frontends: the
  Elixir compiler injects `__info__/1`, `ExCk`/`Docs`/`LitT` chunks, its own atom
  ordering and `Dbgi`/`CInf` encodings, and makes independent codegen choices. So
  the honest bar is one rung down: do the two backends emit the **same Erlang
  abstract function forms**, once we quotient out differences that provably don't
  change meaning?

  `normalize/1` quotients by three such differences:

    1. **Annotations** — line/column (`{2, 7}` in Elixir, a constant in Rian) are
       zeroed everywhere.
    2. **Variable names** — Elixir names a parameter `:_x@1`, Rian names it `:X`;
       both are alpha-renamed to `:V1`, `:V2`, … in order of first appearance,
       fresh per function.
    3. **Provably-safe lowering choices** — a *whitelist* of rewrites that are
       semantics-preserving. Current members:
         * a `case` whose clauses are exactly the two literal atoms `true`/`false`
           with no guards is reordered to a canonical `true`-first form. Elixir
           lowers `if` to such a `case` as `[false, true]`, Rian as `[true, false]`;
           the clauses are mutually exclusive and exhaustive, so order carries no
           meaning and reordering masks the encoding choice **without** masking a
           real difference.
         * a negated literal `{:op, :-, {:integer|:float, n}}` is folded to the
           literal `-n`. Elixir constant-folds `-1` to `{:integer, -1}`; Rian emits
           unary-minus-on-`1`. Negating a numeric literal is pure compile-time
           arithmetic (BEAM integers are bignums — no overflow; float negation is
           exact), so the two forms denote the identical constant.

  What it deliberately does **not** do: blindly sort `case` clauses (order is
  first-match-wins in general), drop guards, or otherwise hide a difference that
  could change behaviour. A construct where Elixir and Rian make different
  *equivalent* lowering choices for which no safe rewrite is whitelisted will
  honestly report as **not equivalent** — that is a TODO for a future rule, not a
  thing to paper over. Equivalence here means "equal modulo a justified quotient",
  never "close enough".
  """

  use Rian.Ann

  @rian_sig "pub def normalize(forms _Unk) _Unk"
  @doc """
  The normalized, sorted list of function forms for a module's abstract code —
  the canonical value two modules must share to be forms-equivalent. Accepts a
  `.beam` binary or an already-extracted abstract-code form list.
  """
  @spec normalize(binary() | list()) :: list()
  def normalize(beam) when is_binary(beam), do: beam |> abstract_code() |> normalize()

  def normalize(forms) when is_list(forms) do
    forms
    |> Enum.filter(&user_function?/1)
    |> Enum.map(&(&1 |> zero_anno() |> fold_neg_literal() |> canon_bool_case() |> alpha_rename()))
    |> Enum.sort_by(fn {:function, _, name, arity, _} -> {name, arity} end)
  end

  @rian_sig "pub def equivalent?(a _Unk, b _Unk) Bool"
  @doc """
  `true` iff the two inputs (each a `.beam` binary or abstract-code form list)
  share the same normalized function forms.
  """
  @spec equivalent?(binary() | list(), binary() | list()) :: boolean()
  def equivalent?(a, b), do: normalize(a) == normalize(b)

  @rian_sig "pub def diff(a _Unk, b _Unk) _Unk"
  @doc """
  Structured diff for debugging: `:equal`, or `{:diff, forms_only_in_a,
  forms_only_in_b}` over the normalized function forms (matched by name/arity).
  """
  @spec diff(binary() | list(), binary() | list()) :: term()
  def diff(a, b) do
    na = Map.new(normalize(a), &{key(&1), &1})
    nb = Map.new(normalize(b), &{key(&1), &1})
    keys = (Map.keys(na) ++ Map.keys(nb)) |> Enum.uniq()

    mismatches =
      for k <- keys, Map.get(na, k) != Map.get(nb, k) do
        {k, Map.get(na, k), Map.get(nb, k)}
      end

    if mismatches == [], do: :equal, else: {:diff, mismatches}
  end

  @doc """
  Per-function verification ledger between an Elixir oracle and a candidate Rian
  port — the accept/reject gate for the generate-and-verify porting loop. Returns
  `[{{name, arity}, status}]` sorted by name/arity, where status is:

    * `:equiv`       — normalized forms match (the port is faithful)
    * `:diverges`    — both define it but the forms differ (reject the candidate)
    * `:only_oracle` — Elixir has it, the Rian port doesn't yet (unported)
    * `:only_port`   — the Rian port has it, the oracle doesn't (extra/renamed)

  A port passes iff every entry is `:equiv` (see `verified?/2`).
  """
  @rian_sig "pub def verify(oracle _Unk, port _Unk) Vec(_Unk)"
  @spec verify(term(), term()) :: [{term(), atom()}]
  def verify(oracle, port) do
    na = Map.new(normalize(oracle), &{key(&1), &1})
    nb = Map.new(normalize(port), &{key(&1), &1})

    (Map.keys(na) ++ Map.keys(nb))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn k ->
      status =
        cond do
          not Map.has_key?(nb, k) -> :only_oracle
          not Map.has_key?(na, k) -> :only_port
          Map.fetch!(na, k) == Map.fetch!(nb, k) -> :equiv
          true -> :diverges
        end

      {k, status}
    end)
  end

  @rian_sig "pub def verified?(oracle _Unk, port _Unk) Bool"
  @doc "True iff every function in the oracle is matched `:equiv` by the port."
  @spec verified?(term(), term()) :: boolean()
  def verified?(oracle, port), do: Enum.all?(verify(oracle, port), &(elem(&1, 1) == :equiv))

  defp key({:function, _, name, arity, _}), do: {name, arity}

  @rian_sig "pub def abstract_code(beam _Unk) _Unk"
  @doc "Extract the Erlang abstract code from a `.beam` binary (raises if absent)."
  @spec abstract_code(binary()) :: list()
  def abstract_code(beam) when is_binary(beam) do
    case :beam_lib.chunks(beam, [:abstract_code]) do
      {:ok, {_mod, [{:abstract_code, {_vsn, ac}}]}} ->
        ac

      {:ok, {_mod, [{:abstract_code, :no_abstract_code}]}} ->
        raise "beam has no abstract_code (compile with :debug_info)"

      other ->
        raise "could not read abstract_code: #{inspect(other)}"
    end
  end

  # Elixir auto-injects `__info__/1` and `module_info/0,1`; they are frontend
  # boilerplate, never part of the ported logic.
  defp user_function?({:function, _, name, _, _}), do: name not in [:__info__, :module_info]
  defp user_function?(_), do: false

  # ── normalization passes ────────────────────────────────────────────────────

  # Zero the annotation (2nd element) of every abstract-form tuple — drops
  # line/column without touching payloads (atom/integer *values* live at elem 2+).
  defp zero_anno(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [tag, _anno | rest] when is_atom(tag) ->
        List.to_tuple([tag, 0 | Enum.map(rest, &zero_anno/1)])

      other ->
        other |> Enum.map(&zero_anno/1) |> List.to_tuple()
    end
  end

  defp zero_anno(list) when is_list(list), do: Enum.map(list, &zero_anno/1)
  defp zero_anno(leaf), do: leaf

  # Whitelisted safe rewrite: fold a negated numeric literal `-N` to the literal
  # `-N` value. Elixir constant-folds it; Rian emits unary minus on the literal.
  # Value-preserving (bignum integers don't overflow, float negation is exact).
  defp fold_neg_literal({:op, 0, :-, {:integer, 0, n}}), do: {:integer, 0, -n}
  defp fold_neg_literal({:op, 0, :-, {:float, 0, n}}), do: {:float, 0, -n}

  defp fold_neg_literal(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&fold_neg_literal/1) |> List.to_tuple()

  defp fold_neg_literal(list) when is_list(list), do: Enum.map(list, &fold_neg_literal/1)
  defp fold_neg_literal(leaf), do: leaf

  # Whitelisted safe rewrite: a boolean `case` (clauses are exactly the two
  # literal atoms true/false, no guards) → canonical true-first order. Applied
  # bottom-up so nested cases are canonicalized too. Annotations are already 0.
  defp canon_bool_case({:case, 0, scrut, clauses}) do
    scrut = canon_bool_case(scrut)
    clauses = Enum.map(clauses, &canon_bool_case/1)
    rebuilt = {:case, 0, scrut, clauses}

    case bool_clause_pair(clauses) do
      {t_clause, f_clause} -> {:case, 0, scrut, [t_clause, f_clause]}
      :no -> rebuilt
    end
  end

  defp canon_bool_case(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canon_bool_case/1) |> List.to_tuple()

  defp canon_bool_case(list) when is_list(list), do: Enum.map(list, &canon_bool_case/1)
  defp canon_bool_case(leaf), do: leaf

  # Recognize exactly `[true-clause, false-clause]` in either order, no guards;
  # return them in canonical `{true_clause, false_clause}` order, else `:no`.
  defp bool_clause_pair([a, b]) do
    case {bool_clause(a), bool_clause(b)} do
      {{:ok, true}, {:ok, false}} -> {a, b}
      {{:ok, false}, {:ok, true}} -> {b, a}
      _ -> :no
    end
  end

  defp bool_clause_pair(_), do: :no

  defp bool_clause({:clause, 0, [{:atom, 0, v}], [], _body}) when is_boolean(v), do: {:ok, v}
  defp bool_clause(_), do: :error

  # Alpha-rename variables to :V1, :V2, … in order of first appearance, fresh per
  # function form. `_` stays `_` (it binds nothing and never recurs).
  defp alpha_rename(form) do
    {renamed, _map} = walk_rename(form, %{})
    renamed
  end

  defp walk_rename({:var, 0, :_}, map), do: {{:var, 0, :_}, map}

  defp walk_rename({:var, 0, name}, map) do
    case Map.fetch(map, name) do
      {:ok, canon} ->
        {{:var, 0, canon}, map}

      :error ->
        canon = :"V#{map_size(map) + 1}"
        {{:var, 0, canon}, Map.put(map, name, canon)}
    end
  end

  defp walk_rename(tuple, map) when is_tuple(tuple) do
    {list, map} = walk_rename(Tuple.to_list(tuple), map)
    {List.to_tuple(list), map}
  end

  defp walk_rename(list, map) when is_list(list) do
    Enum.map_reduce(list, map, &walk_rename/2)
  end

  defp walk_rename(leaf, map), do: {leaf, map}
end
