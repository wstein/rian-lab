defmodule Rian.Exhaustiveness do
  @moduledoc """
  Pattern-match analysis for Rian, based on Maranget's usefulness algorithm
  ("Warnings for pattern matching", JFP 2007) — the same basis as OCaml/Rust.

  One algorithm yields three diagnostics:

    * exhaustiveness — `(_, …, _)` is NOT useful against the clause matrix
    * unreachable clause — its pattern is NOT useful against preceding clauses
    * counterexample — Maranget's witness variant (algorithm I)

  ## Pattern representation
      :wild                          # wildcard / variable / (lowered) pin
      {:ctor, ctor_id, [pattern]}    # constructor with sub-patterns

  ctor_id is:
      :leaf | :node | ...            # sum-type variants (atoms)
      true | false                   # bool
      :nil | :cons                   # list (nil / cons)
      {:tuple, n}                    # n-tuple / multi-arg
      {:lit, value}                  # literal (i64/f64/str) — 0-arity

  ## Signature environment
      %{arity: %{ctor_id => arity},
        type_of: %{ctor_id => type_name},
        ctors:  %{type_name => {:finite, [ctor_id]} | :infinite}}
  """

  # ── Environment helpers ────────────────────────────────────────────────

  @doc "Base env with built-in bool, list, and the infinite primitive types."
  def base_env do
    %{
      arity: %{nil: 0, cons: 2, true: 0, false: 0},
      type_of: %{nil: :list, cons: :list, true: :bool, false: :bool},
      ctors: %{
        list: {:finite, [nil, :cons]},
        bool: {:finite, [true, false]},
        int: :infinite,
        float: :infinite,
        str: :infinite,
        map: :infinite
      }
    }
  end

  @doc "Register a sum type: variants is [{ctor_id, arity}, ...]."
  def add_type(env, type_name, variants) do
    ids = Enum.map(variants, fn {c, _} -> c end)
    arity = Enum.reduce(variants, env.arity, fn {c, a}, acc -> Map.put(acc, c, a) end)
    typeof = Enum.reduce(ids, env.type_of, fn c, acc -> Map.put(acc, c, type_name) end)
    %{env | arity: arity, type_of: typeof, ctors: Map.put(env.ctors, type_name, {:finite, ids})}
  end

  defp arity(_env, {:tuple, n}), do: n
  defp arity(_env, {:lit, _}), do: 0
  defp arity(env, c), do: Map.get(env.arity, c, 0)

  # {:complete, all_ctors} when the head constructors cover the whole type,
  # otherwise :incomplete (also for empty / infinite signatures).
  defp signature(_env, []), do: :incomplete
  defp signature(_env, [{:tuple, _} = t | _]), do: {:complete, [t]}
  defp signature(_env, [{:lit, _} | _]), do: :incomplete

  defp signature(env, [c | _] = present) do
    case env.ctors[env.type_of[c]] do
      {:finite, all} ->
        if MapSet.subset?(MapSet.new(all), MapSet.new(present)),
          do: {:complete, all},
          else: :incomplete

      _ ->
        :incomplete
    end
  end

  defp head_ctors(rows) do
    rows
    |> Enum.flat_map(fn
      [{:ctor, c, _} | _] -> [c]
      _ -> []
    end)
    |> Enum.uniq()
  end

  # ── Matrix operations ──────────────────────────────────────────────────

  # Specialize by constructor c: keep rows that can match c, expanding sub-patterns.
  defp specialize(rows, c, env) do
    a = arity(env, c)

    Enum.flat_map(rows, fn
      [{:ctor, ^c, args} | rest] -> [args ++ rest]
      [{:ctor, _other, _} | _] -> []
      [:wild | rest] -> [List.duplicate(:wild, a) ++ rest]
    end)
  end

  # Default matrix: rows whose head is a wildcard, with the head column dropped.
  defp default(rows) do
    Enum.flat_map(rows, fn
      [{:ctor, _, _} | _] -> []
      [:wild | rest] -> [rest]
    end)
  end

  # ── Usefulness U(P, q) ─────────────────────────────────────────────────

  @doc "Is pattern vector `q` useful w.r.t. matrix `rows`?"
  def useful?(rows, [], _env), do: rows == []

  def useful?(rows, [{:ctor, c, args} | qrest], env) do
    useful?(specialize(rows, c, env), args ++ qrest, env)
  end

  def useful?(rows, [:wild | qrest], env) do
    case signature(env, head_ctors(rows)) do
      {:complete, ctors} ->
        Enum.any?(ctors, fn c ->
          useful?(specialize(rows, c, env), List.duplicate(:wild, arity(env, c)) ++ qrest, env)
        end)

      :incomplete ->
        useful?(default(rows), qrest, env)
    end
  end

  # ── Witness / counterexample (algorithm I) ─────────────────────────────

  defp witness(rows, 0, _env), do: if(rows == [], do: {:missing, []}, else: :none)

  defp witness(rows, n, env) when n > 0 do
    present = head_ctors(rows)

    case signature(env, present) do
      {:complete, ctors} ->
        Enum.find_value(ctors, :none, fn c ->
          a = arity(env, c)

          case witness(specialize(rows, c, env), a + n - 1, env) do
            {:missing, ws} ->
              {head_ws, rest} = Enum.split(ws, a)
              {:missing, [{:ctor, c, head_ws} | rest]}

            :none ->
              false
          end
        end)

      :incomplete ->
        case witness(default(rows), n - 1, env) do
          {:missing, ws} -> {:missing, [missing_head(env, present) | ws]}
          :none -> :none
        end
    end
  end

  defp missing_head(_env, []), do: :wild
  defp missing_head(_env, [{:lit, _} | _]), do: :wild

  defp missing_head(env, [c | _] = present) do
    case env.ctors[env.type_of[c]] do
      # NOTE: use list subtraction, not Enum.find — the list nil-constructor IS the
      # atom `nil`, which Enum.find cannot distinguish from its "not found" sentinel.
      {:finite, all} ->
        case all -- present do
          [] -> :wild
          [m | _] -> {:ctor, m, List.duplicate(:wild, arity(env, m))}
        end

      _ ->
        :wild
    end
  end

  # ── Top-level analysis ─────────────────────────────────────────────────

  @doc """
  Analyze clauses. `arms` is `[%{pat: [pattern], guard: boolean}]`, `n` is the
  scrutinee arity (1 for `match`, the param count for a multi-clause `fn`).

  Returns `%{exhaustive?:, missing:, unreachable:}` where `missing` is a witness
  pattern vector (or nil) and `unreachable` is a list of 0-based clause indices.
  """
  def analyze(arms, n, env) do
    unguarded = arms |> Enum.reject(& &1.guard) |> Enum.map(& &1.pat)
    exhaustive = not useful?(unguarded, List.duplicate(:wild, n), env)

    missing =
      if exhaustive do
        nil
      else
        case witness(unguarded, n, env) do
          {:missing, w} -> w
          :none -> nil
        end
      end

    {unreachable, _} =
      arms
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {arm, idx}, {unreach, prior} ->
        unreach = if useful?(prior, arm.pat, env), do: unreach, else: [idx | unreach]
        prior = if arm.guard, do: prior, else: prior ++ [arm.pat]
        {unreach, prior}
      end)

    %{exhaustive?: exhaustive, missing: missing, unreachable: Enum.reverse(unreachable)}
  end

  # ── Rendering (for diagnostics) ────────────────────────────────────────

  def render(:wild), do: "_"
  def render({:ctor, {:lit, v}, []}), do: inspect(v)
  def render({:ctor, {:tuple, _}, args}), do: "{" <> Enum.map_join(args, ", ", &render/1) <> "}"
  def render({:ctor, nil, []}), do: "[]"
  def render({:ctor, :cons, [h, t]}), do: "[" <> render(h) <> " | " <> render(t) <> "]"
  def render({:ctor, c, []}), do: pascal(c)

  def render({:ctor, c, args}),
    do: pascal(c) <> "(" <> Enum.map_join(args, ", ", &render/1) <> ")"

  def render(vec) when is_list(vec), do: Enum.map_join(vec, ", ", &render/1)

  defp pascal(c) when c in [true, false], do: to_string(c)

  defp pascal(c) when is_atom(c) do
    c |> Atom.to_string() |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end
end
