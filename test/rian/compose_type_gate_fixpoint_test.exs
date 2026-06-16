defmodule Rian.ComposeTypeGateFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # P3 — the SELF-CHECKING gate is WIRED into `build`. The composed compiler already
  # refused non-exhaustive (`{:non_exhaustive, _}`) and BEAM-illegal (`{:not_beam_legal,
  # _}`) programs; this adds the third gate — TYPE checking via the equivalence-locked
  # `Checker.num_mix` (checker.rian, ADR-0035). The self-built compiler now REFUSES an
  # int↔float program (`{:type_error, name}`) instead of silently emitting it — the step
  # that turns the bootstrap loop from self-COMPILING into (partially) self-CHECKING.
  #
  # Scope (honest): the gate runs on `d_func` bodies (the inline `def f(p T) R := body`
  # form). Separate-clause functions carry their param types in a sibling `d_sig` and are
  # conservatively skipped — a documented tail, asserted below — so the gate never
  # false-rejects them and the v1==v2 fixed point is unaffected.

  setup_all do
    {:ok, _} = Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.LexerV2")
    {:ok, _} = Beam.load(File.read!("compiler/decl.rian"), :"Elixir.Decl")
    {:ok, _} = Beam.load(File.read!("compiler/beam.rian"), :"Elixir.Beam")
    {:ok, _} = Beam.load(File.read!("compiler/exhaust.rian"), :"Elixir.Exhaust")
    {:ok, _} = Beam.load(File.read!("compiler/cap.rian"), :"Elixir.Cap")
    {:ok, _} = Beam.load(File.read!("compiler/checker.rian"), :"Elixir.Checker")
    {:ok, drv} = Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_type_gate)
    {:ok, drv: drv}
  end

  defp uniq(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  describe "the type gate is WIRED into build — an int↔float program is REJECTED" do
    @mixes [
      "def f(a Int64) Float64 := a + 1.5",
      "def f(a Int64, b Float64) Float64 := a * b",
      "def f(c Char) Float64 := c + 1.5",
      "def f(x Float64) Float64 := 1 + x"
    ]

    test "compile_module and build REFUSE every numeric-mix d_func (raise {:type_error, name})",
         %{drv: drv} do
      for src <- @mixes do
        assert catch_error(drv.compile_module(src, uniq(:TypeBad))) == {:type_error, "f"},
               "the type gate did not refuse: #{inspect(src)}"

        assert catch_error(drv.build(src, uniq(:TypeBad))) == {:type_error, "f"},
               "build did not refuse: #{inspect(src)}"
      end
    end

    test "a well-typed d_func still compiles + runs", %{drv: drv} do
      m = drv.build("def f(a Int64) Int64 := a + 1", uniq(:TypeOk))
      assert m.f(41) == 42
    end

    test "same-kind float arithmetic is NOT a mix — compiles", %{drv: drv} do
      m = drv.build("def f(a Float64) Float64 := a - 1.0", uniq(:FloatOk))
      assert m.f(3.5) == 2.5
    end

    test "untyped params infer `unknown` — conservatively NOT rejected", %{drv: drv} do
      # `a`/`b` have no declared type, so the operands are `unknown`; the gate is
      # conservative and never rejects on an unprovable mix.
      m = drv.build("def f(a, b) Int64 := a + b", uniq(:Conservative))
      assert m.f(2, 3) == 5
    end

    test "div/rem are not mix operators — an Int÷Int compiles", %{drv: drv} do
      m = drv.build("def f(a Int64) Int64 := a div 2", uniq(:DivOk))
      assert m.f(9) == 4
    end
  end

  describe "the return-type gate is WIRED into build — a return mismatch is REJECTED" do
    @mismatches [
      "def f(a Int64) Float64 := a",
      ~S|def f() Int64 := "hi"|,
      "def f(a Int16) Int8 := a",
      "def f() Int8 := 9999"
    ]

    test "compile_module and build REFUSE every return-type-mismatch d_func", %{drv: drv} do
      for src <- @mismatches do
        assert catch_error(drv.compile_module(src, uniq(:RetBad))) == {:type_error, "f"},
               "the return gate did not refuse: #{inspect(src)}"

        assert catch_error(drv.build(src, uniq(:RetBad))) == {:type_error, "f"},
               "build did not refuse: #{inspect(src)}"
      end
    end

    test "an identity / integer-widening return compiles + runs", %{drv: drv} do
      m = drv.build("def f(a Int64) Int64 := a", uniq(:RetId))
      assert m.f(5) == 5
      w = drv.build("def f(a Int8) Int64 := a", uniq(:RetWiden))
      assert w.f(9) == 9
    end

    test "an in-range literal adopting the declared width compiles + runs", %{drv: drv} do
      m = drv.build("def f() Int8 := 5", uniq(:RetAdopt))
      assert m.f() == 5
    end

    test "an int literal widening to a float return compiles + runs", %{drv: drv} do
      m = drv.build("def f() Float64 := 66", uniq(:RetIntFloat))
      assert m.f() == 66
    end
  end

  describe "d_clause widening — both gates also cover separate-clause functions (P3)" do
    # `def f(a Int64) Float64` (a d_sig) + `def f(a) := a + 1.5` (a d_clause): the clause's
    # param types come from its sibling sig (sig_index/clause_env), so the gates now bite on
    # the common multi-clause form, not just inline `d_func`.
    test "a separate-clause numeric mix is REFUSED", %{drv: drv} do
      src = "def f(a Int64) Float64\ndef f(a) := a + 1.5"
      assert catch_error(drv.compile_module(src, uniq(:ClauseMix))) == {:type_error, "f"}
    end

    test "a separate-clause return mismatch is REFUSED", %{drv: drv} do
      src = "def g(a Int64) Float64\ndef g(a) := a"
      assert catch_error(drv.compile_module(src, uniq(:ClauseRet))) == {:type_error, "g"}
    end

    test "a well-typed separate-clause function compiles + runs", %{drv: drv} do
      m = drv.build("def h(a Int64) Int64\ndef h(a) := a + 1", uniq(:ClauseOk))
      assert m.h(41) == 42
    end

    test "a clause with NO sibling sig is conservatively skipped (untyped → unknown)",
         %{drv: drv} do
      # no `d_sig` → the clause's `a` has no declared type → the gates can't prove anything,
      # so it compiles even though `a + 1.5` would mix were `a` an Int.
      m = drv.build("def k(a) := a + 1.5", uniq(:NoSig))
      assert m.k(2) == 3.5
    end
  end
end
