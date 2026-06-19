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

  A `range` type (ADR-0036) registers its `{:lit, v}` members as a `{:finite, …}`
  signature via `add_range/4`, so a `case` covering the whole interval is
  exhaustive. Unregistered literals have no `type_of` entry and stay infinite —
  a bare `Int64`/`Char`/`String` still requires a `_` arm.
  """

  use Rian.Ann

  alias Rian.{Core, PatternLower, Pratt, Prelude}

  # ── Environment helpers ────────────────────────────────────────────────

  @rian_sig "pub def base_env() _Unk"
  @doc "Base env with built-in bool, list, and the infinite primitive types."
  @spec base_env() :: map()
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
  @rian_sig "pub def add_type(env _Unk, type_name Symbol, variants Vec(_Unk)) _Unk"
  @spec add_type(map(), term(), list()) :: map()
  def add_type(env, type_name, variants) do
    ids = Enum.map(variants, fn {c, _} -> c end)
    arity = Enum.reduce(variants, env.arity, fn {c, a}, acc -> Map.put(acc, c, a) end)
    typeof = Enum.reduce(ids, env.type_of, fn c, acc -> Map.put(acc, c, type_name) end)
    %{env | arity: arity, type_of: typeof, ctors: Map.put(env.ctors, type_name, {:finite, ids})}
  end

  @doc """
  Register a finite ordinal `range` type (ADR-0036): the inclusive interval
  `lo..hi` over an ordinal base (`Int64`/`Char` — pass `Char` bounds as
  codepoints). Its members are the `{:lit, v}` constructors, so a `case` that
  covers the whole interval is exhaustive — unlike a bare `Int64`, whose
  signature stays infinite and still demands a `_`.
  """
  @rian_sig "pub def add_range(env _Unk, type_name Symbol, lo Int53, hi Int53) _Unk"
  @spec add_range(map(), term(), integer(), integer()) :: map()
  def add_range(env, type_name, lo, hi) when lo <= hi do
    members = for v <- lo..hi, do: {:lit, v}
    typeof = Enum.reduce(members, env.type_of, fn m, acc -> Map.put(acc, m, type_name) end)
    %{env | type_of: typeof, ctors: Map.put(env.ctors, type_name, {:finite, members})}
  end

  defp arity(_env, {:tuple, n}), do: n
  defp arity(_env, {:lit, _}), do: 0
  defp arity(env, c), do: Map.get(env.arity, c, 0)

  # {:complete, all_ctors} when the head constructors cover the whole type,
  # otherwise :incomplete (also for empty / infinite signatures). A `{:lit, v}`
  # head is looked up like any other constructor: members of a registered
  # `range` type (ADR-0036) resolve to a finite signature; an unregistered
  # literal has no type, so it falls through to the infinite-primitive case.
  defp signature(_env, []), do: :incomplete
  defp signature(_env, [{:tuple, _} = t | _]), do: {:complete, [t]}

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

  @rian_sig "pub def useful?(rows Vec(_Unk), q Vec(_Unk), env _Unk) Bool"
  @doc "Is pattern vector `q` useful w.r.t. matrix `rows`?"
  @spec useful?(list(), list(), map()) :: boolean()
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

  @rian_sig "pub def analyze(arms Vec(_Unk), n Int53, env _Unk) _Unk"
  @doc """
  Analyze clauses. `arms` is `[%{pat: [pattern], guard: boolean}]`, `n` is the
  scrutinee arity (1 for `match`, the param count for a multi-clause `fn`).

  Returns `%{exhaustive?:, missing:, unreachable:}` where `missing` is a witness
  pattern vector (or nil) and `unreachable` is a list of 0-based clause indices.
  """
  @spec analyze(list(), integer(), map()) :: term()
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

  @rian_sig "pub def render(node _Unk) String"
  @spec render(term()) :: String.t()
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

  # ── `case`-expression exhaustiveness (the body gate) ─────────────────────
  # The clause-head gate (`Rian.Lower.check!`) only sees a function's argument
  # patterns; a non-exhaustive `case` INSIDE a body slips through and crashes at
  # runtime with `case_clause`. These walk a program's bodies and run the SAME
  # usefulness analysis on every `case` arm matrix, refusing to emit on a gap.

  @doc "The signature env for a whole program (types + ranges + structs)."
  @rian_sig "pub def program_env(types Vec(Type), structs Vec(Struct), ranges Vec(Range)) _Unk"
  @spec program_env(list(), list(), list()) :: map()
  def program_env(types, structs, ranges) do
    env =
      Enum.reduce(Prelude.with_prelude(types), base_env(), fn t, env ->
        variants =
          Enum.map(t.variants, fn v -> {PatternLower.to_snake(v.ctor), length(v.fields)} end)

        add_type(env, PatternLower.to_snake(t.name), variants)
      end)

    env = Enum.reduce(ranges, env, fn r, env -> add_range(env, r.name, r.lo, r.hi) end)

    Enum.reduce(structs, env, fn s, env ->
      PatternLower.add_struct(env, s.name, Enum.map(s.fields, &PatternLower.to_snake(&1.label)))
    end)
  end

  @doc "Refuse to emit any function whose body holds a non-exhaustive `case`."
  @rian_sig "pub def check_case_bodies!(funcs Vec(Func), env _Unk) Symbol"
  @spec check_case_bodies!(list(), map()) :: term()
  def check_case_bodies!(funcs, env) do
    for func <- funcs, not Map.get(func, :synthetic, false), clause <- func.clauses do
      clause.body |> body_core() |> check_match!(env, func.name)
    end

    :ok
  end

  defp body_core(body) when is_binary(body), do: Core.from_expr(Pratt.parse_body(body))
  defp body_core(ast), do: Core.from_expr(ast)

  @doc "Check every `case` reachable in a Core expression; raise on the first gap."
  @rian_sig "pub def check_match!(core Expr, env _Unk, where _Unk) _Unk"
  @spec check_match!(term(), map(), term()) :: term()
  def check_match!(core, env, where) do
    core |> collect_cases([]) |> Enum.each(&check_one_case!(&1, env, where))
  end

  defp check_one_case!(%Core.ECase{arms: arms}, env, where) do
    rows =
      Enum.map(arms, fn {pat, guard, _body} ->
        PatternLower.lower_clause(%{pats: [pat], guard: guard != nil}, env)
      end)

    r = analyze(rows, 1, env)

    unless r.exhaustive? do
      raise "non-exhaustive `case` in `#{where}`: pattern `#{render(r.missing)}` not covered"
    end
  end

  # generic Core walk — collect every `ECase` node (recursing into arm bodies too).
  defp collect_cases(%Core.ECase{} = n, acc), do: collect_children(n, [n | acc])
  defp collect_cases(node, acc) when is_struct(node), do: collect_children(node, acc)
  defp collect_cases(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_cases/2)

  defp collect_cases(tuple, acc) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.reduce(acc, &collect_cases/2)

  defp collect_cases(_, acc), do: acc

  defp collect_children(struct, acc),
    do: struct |> Map.from_struct() |> Map.values() |> Enum.reduce(acc, &collect_cases/2)
end
