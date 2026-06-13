defmodule Rian.ReachTest do
  # async: false — the build-default tests mutate the global `:rian_lab` app env
  # (`:rian_targets`), which `Rian.Reach.gate!/1` reads on *every* compile; running
  # concurrently would leak a transient value into other tests' `Beam.compile`.
  use ExUnit.Case, async: false

  alias Rian.Reach

  defp reach(src), do: src |> Rian.Decl.parse() |> Reach.analyze()
  defp targets(rep, fn_name), do: rep[fn_name].reach |> MapSet.to_list() |> Enum.sort()

  describe "portable code reaches every target" do
    test "pure arithmetic / cons recursion / variants are portable" do
      rep =
        reach("""
        mod P do
          pub def add(a Int64, b Int64) Int64 := a + b
          pub def sum(xs Vec(Int64)) Int64
          pub def sum([]) := 0
          pub def sum([h | t]) := h + sum(t)
        end
        """)

      assert targets(rep, "add") == [:ex, :js, :jvm, :rs]
      assert targets(rep, "sum") == [:ex, :js, :jvm, :rs]
      assert rep["add"].blockers == []
    end

    test "the portable prelude `__prim_*` layer stays all-target" do
      rep = reach(File.read!("examples/rian/prelude_int.rian"))

      for f <- ~w(wrapping_add saturating_add checked_add),
          do: assert(targets(rep, f) == [:ex, :js, :jvm, :rs])
    end

    test "a Rian cross-module call is portable (not host FFI)" do
      rep =
        reach("""
        mod Lex do
          pub def lex(n Int64) Int64 := n
        end
        mod Driver do
          pub def run(n Int64) Int64 := Lex.lex(n)
        end
        """)

      assert targets(rep, "run") == [:ex, :js, :jvm, :rs]
    end
  end

  describe "host FFI pins a function to :ex" do
    test "an Erlang remote call is ex-only and names the blocker" do
      rep =
        reach("""
        mod M do
          pub def total(xs Vec(Int64)) Int64 := :lists.sum(xs)
        end
        """)

      assert targets(rep, "total") == [:ex]
      assert [%{construct: ":lists.sum", kind: :ffi, kills: kills}] = rep["total"].blockers
      assert Enum.sort(kills) == [:js, :jvm, :rs]
    end

    test "a `ref` capability pins a function OFF :ex (P5 — ref is not in the portable core)" do
      rep = reach("def bump(x ref Int64) Int64 := x + 1")

      # ref (&mut) is BEAM-rejected, so the function reaches everything BUT :ex —
      # the reachability report no longer oversells `ref` as portable (ADR-0055/P5).
      assert targets(rep, "bump") == [:js, :jvm, :rs]
      assert [%{kind: :capability, kills: [:ex]}] = rep["bump"].blockers
    end

    test "an Elixir-module call (non-Rian) is ex-only" do
      rep =
        reach("""
        mod M do
          pub def up(s String) String := String.upcase(s)
        end
        """)

      assert targets(rep, "up") == [:ex]
      assert [%{construct: "String.upcase"}] = rep["up"].blockers
    end
  end

  describe "concurrency/process/state FFI is ex-only by design (ADR-0057)" do
    test "spawn, ETS, and GenServer are flagged as concurrency, not generic FFI" do
      rep =
        reach("""
        mod C do
          pub def s() Int64 := :erlang.spawn(:m, :f, [])
          pub def t(k String) Int64 := :ets.lookup(:tab, k)
          pub def g(pid Int64) Int64 := GenServer.call(pid, :v)
        end
        """)

      for f <- ~w(s t g) do
        assert targets(rep, f) == [:ex]
        assert [%{kind: :concurrency}] = rep[f].blockers
      end
    end

    test "a pure `:erlang` function is plain FFI, not concurrency" do
      rep =
        reach("""
        mod M do
          pub def a(x Int64) Int64 := :erlang.abs(x)
        end
        """)

      assert [%{kind: :ffi}] = rep["a"].blockers
    end
  end

  describe "reachability propagates along the local call graph" do
    test "a portable-looking caller inherits a callee's ex-only pin" do
      rep =
        reach("""
        mod P do
          pub def leaf(n Int64) Int64 := :lists.sum([n])
          pub def mid(n Int64) Int64 := leaf(n) + 1
          pub def caller(n Int64) Int64 := mid(n) * 2
        end
        """)

      # leaf is directly ex-only; mid and caller have no FFI of their own but
      # cannot reach further than the function they (transitively) call
      assert targets(rep, "leaf") == [:ex]
      assert targets(rep, "mid") == [:ex]
      assert targets(rep, "caller") == [:ex]
      # the pin is propagated, so mid/caller carry no *local* blocker
      assert rep["mid"].blockers == []
      assert rep["caller"].blockers == []
    end

    test "a portable function calling only portable functions stays all-target" do
      rep =
        reach("""
        mod P do
          pub def inc(n Int64) Int64 := n + 1
          pub def twice(n Int64) Int64 := inc(inc(n))
        end
        """)

      assert targets(rep, "twice") == [:ex, :js, :jvm, :rs]
    end
  end

  test "the closed target vocabulary is ex/rs/js" do
    assert Enum.sort(Reach.targets()) == [:ex, :js, :jvm, :rs]
  end

  describe "build-default target set (ADR-0058 §2)" do
    @ffi """
    mod M do
      pub def total(xs val Vec(Int64)) Int64 := :lists.sum(xs)
    end
    """

    test "a nil-`@targets` module is not gated without a build default" do
      assert Reach.check_contracts(Rian.Decl.parse(@ffi), nil) == :ok
    end

    test "the build default gates a nil-`@targets` module that can't reach it" do
      assert {:error, msg} = Reach.check_contracts(Rian.Decl.parse(@ffi), [:ex, :rs, :js])
      assert msg =~ "M.total cannot reach [:js, :rs]"
    end

    test "an `:ex` build default passes (the FFI reaches the BEAM)" do
      assert Reach.check_contracts(Rian.Decl.parse(@ffi), [:ex]) == :ok
    end

    test "an explicit `@targets` overrides the build default" do
      # the module declares `@targets(ex)`, so a stricter build default is ignored
      src = "@targets(ex)\n" <> @ffi
      assert Reach.check_contracts(Rian.Decl.parse(src), [:ex, :rs, :js]) == :ok
    end

    test "build_default/0 reads the :rian_lab app env" do
      Application.put_env(:rian_lab, :rian_targets, [:ex, :rs])

      try do
        assert Reach.build_default() == [:ex, :rs]
      after
        Application.delete_env(:rian_lab, :rian_targets)
      end
    end

    test "build_default/0 validates the configured set against the target vocabulary" do
      # a typo or wrong type must fail clearly, not silently mis-gate every module
      Application.put_env(:rian_lab, :rian_targets, [:ex, :foo])

      try do
        assert_raise Reach.Error, ~r/invalid build-default target\(s\) \[:foo\]/, fn ->
          Reach.build_default()
        end
      after
        Application.delete_env(:rian_lab, :rian_targets)
      end

      # a list of the wrong element type is still a vocabulary error
      Application.put_env(:rian_lab, :rian_targets, ["ex"])

      try do
        assert_raise Reach.Error, ~r/invalid build-default target/, fn ->
          Reach.build_default()
        end
      after
        Application.delete_env(:rian_lab, :rian_targets)
      end

      # a non-list value is rejected with the type message
      Application.put_env(:rian_lab, :rian_targets, :ex)

      try do
        assert_raise Reach.Error, ~r/must be a list of/, fn -> Reach.build_default() end
      after
        Application.delete_env(:rian_lab, :rian_targets)
      end
    end
  end
end
