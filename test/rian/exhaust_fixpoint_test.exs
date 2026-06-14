defmodule Rian.ExhaustFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Exhaustiveness}

  # Self-hosting fixpoint (ADR-0063) for the **exhaustiveness gate** (full): a
  # Rian-written Maranget usefulness check (examples/rian/selfhost_exhaust.rian),
  # compiled to real `.beam`, diffed against the reference
  # `Rian.Exhaustiveness.useful?/3` over the whole algorithm — single- and
  # multi-column matrices, constructors with arguments (arity-specialised),
  # wildcards, and signature completeness — so the port reproduces `useful?`,
  # not just a verdict.
  #
  # The same `useful?` formulation gives exhaustiveness: a `case` is exhaustive
  # iff a wildcard query is NOT useful w.r.t. the matrix. The witness/counterexample
  # pass (algorithm I) is the `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :rian_exhaust_fixpoint)

    {:ok, mod: mod}
  end

  # type definitions shared by both representations: type -> [{ctor, arity}].
  @tdefs [
    {"rgb", [{"red", 0}, {"green", 0}, {"blue", 0}]},
    {"shape", [{"circle", 1}, {"square", 1}, {"rect", 2}]},
    {"list", [{"nil", 0}, {"cons", 2}]},
    {"box", [{"box", 1}]}
  ]

  # ── the port's structured env (struct maps) ──
  defp port_env do
    cdefs =
      for {ty, vs} <- @tdefs, {c, a} <- vs, do: %{__struct__: :c_def, name: c, ar: a, ty: ty}

    tdefs =
      for {ty, vs} <- @tdefs, do: %{__struct__: :t_def, ty: ty, ctors: Enum.map(vs, &elem(&1, 0))}

    %{__struct__: :env, cdefs: cdefs, tdefs: tdefs}
  end

  # ── the reference env (base_env + add_type) ──
  defp ref_env do
    Enum.reduce(@tdefs, Exhaustiveness.base_env(), fn {ty, vs}, e ->
      Exhaustiveness.add_type(e, ty, Enum.map(vs, fn {c, a} -> {String.to_atom(c), a} end))
    end)
  end

  # a tiny neutral pattern DSL: `:w` | {ctor_name, [sub]}.  Translate to each side.
  defp to_port(:w), do: :p_wild
  defp to_port({c, args}), do: {:p_ctor, c, Enum.map(args, &to_port/1)}

  defp to_ref(:w), do: :wild
  defp to_ref({c, args}), do: {:ctor, String.to_atom(c), Enum.map(args, &to_ref/1)}

  defp port_useful(mod, rows, q) do
    pr = Enum.map(rows, fn row -> Enum.map(row, &to_port/1) end)
    mod.useful(port_env(), pr, Enum.map(q, &to_port/1))
  end

  defp ref_useful(rows, q) do
    rr = Enum.map(rows, fn row -> Enum.map(row, &to_ref/1) end)
    Exhaustiveness.useful?(rr, Enum.map(q, &to_ref/1), ref_env())
  end

  # {matrix, query} cases exercising the whole algorithm.
  @corpus [
    # nullary single-column: incomplete / complete / wildcard
    {[[{"red", []}], [{"green", []}]], [:w]},
    {[[{"red", []}], [{"green", []}], [{"blue", []}]], [:w]},
    {[[{"red", []}], [:w]], [:w]},
    {[], [:w]},
    {[[:w]], []},
    # constructors with arguments — specialised by arity
    {[[{"circle", [:w]}], [{"square", [:w]}]], [:w]},
    {[[{"circle", [:w]}], [{"square", [:w]}], [{"rect", [:w, :w]}]], [:w]},
    {[[{"rect", [{"red", []}, :w]}]], [:w]},
    # lists as nil/cons constructors
    {[[{"nil", []}], [{"cons", [:w, :w]}]], [:w]},
    {[[{"cons", [:w, :w]}]], [:w]},
    {[[{"cons", [:w, {"cons", [:w, {"nil", []}]}]}]], [:w]},
    # single-ctor type (box) — one ctor IS the whole signature
    {[[{"box", [{"red", []}]}]], [:w]},
    {[[{"box", [:w]}]], [:w]},
    # multi-column matrices
    {[[{"red", []}, {"circle", [:w]}]], [:w, :w]},
    {[[{"red", []}, {"circle", [:w]}], [{"green", []}, {"square", [:w]}]], [:w, :w]},
    {[[:w, {"nil", []}], [:w, {"cons", [:w, :w]}]], [:w, :w]}
  ]

  describe "self-hosting exhaustiveness fixpoint — Rian useful vs Maranget useful?/3" do
    test "the Rian usefulness check reproduces useful?/3 on every case", %{mod: mod} do
      for {rows, q} <- @corpus do
        assert port_useful(mod, rows, q) == ref_useful(rows, q),
               "useful diverged on matrix=#{inspect(rows)} q=#{inspect(q)}"
      end
    end
  end

  describe "teeth — the full algorithm (arity, multi-column, signatures) is real" do
    test "specialisation by arity: a missing multi-arg ctor leaves a gap", %{mod: mod} do
      # circle/square present, rect (arity 2) missing -> wildcard IS useful (gap).
      incomplete = [[{"circle", [:w]}], [{"square", [:w]}]]
      assert port_useful(mod, incomplete, [:w])
      # add rect -> the whole `shape` signature is covered -> NOT useful (exhaustive).
      complete = incomplete ++ [[{"rect", [:w, :w]}]]
      refute port_useful(mod, complete, [:w])
    end

    test "exhaustiveness = `not useful` agrees with the reference for lists", %{mod: mod} do
      cons_only = [[{"cons", [:w, :w]}]]
      full = [[{"nil", []}], [{"cons", [:w, :w]}]]
      # cons-only is non-exhaustive (nil missing); nil+cons is exhaustive.
      assert port_useful(mod, cons_only, [:w]) == ref_useful(cons_only, [:w])
      assert port_useful(mod, full, [:w]) == ref_useful(full, [:w])
      refute port_useful(mod, full, [:w])
    end

    test "multi-column: an uncovered column combination is useful", %{mod: mod} do
      # one row red+circle leaves the rest of the rgb × shape space uncovered.
      rows = [[{"red", []}, {"circle", [:w]}]]
      assert port_useful(mod, rows, [:w, :w])
      assert port_useful(mod, rows, [:w, :w]) == ref_useful(rows, [:w, :w])
    end
  end
end
