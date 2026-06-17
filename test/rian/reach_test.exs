defmodule Rian.ReachTest do
  # async: false — the build-default tests mutate the global `:rian_lab` app env
  # (`:rian_targets`), which `Rian.Reach.gate!/1` reads on *every* compile; running
  # concurrently would leak a transient value into other tests' `Beam.compile`.
  use ExUnit.Case, async: false

  alias Rian.Reach

  defp reach(src), do: src |> Rian.Decl.parse() |> Reach.analyze()

  # `Reach.entry/2` resolves a bare name against the `"name/arity"`-keyed report
  # (and raises clearly on a miss) — these sources have no overloads.
  defp entry(rep, fn_name), do: Reach.entry(rep, fn_name)

  defp targets(rep, fn_name), do: entry(rep, fn_name).reach |> MapSet.to_list() |> Enum.sort()

  describe "portable code reaches every target" do
    test "pure arithmetic / cons recursion / variants are portable" do
      rep =
        reach("""
        mod P do
          pub def add(a Int53, b Int53) Int53 := a + b
          pub def sum(xs Vec(Int53)) Int53
          pub def sum([]) := 0
          pub def sum([h | t]) := h + sum(t)
        end
        """)

      assert targets(rep, "add") == [:ex, :js, :jvm, :rs]
      assert targets(rep, "sum") == [:ex, :js, :jvm, :rs]
      assert entry(rep, "add").blockers == []
    end

    test "a portable-prelude call (`List.map`) reaches every target; a stdlib FFI does not" do
      rep =
        reach("""
        mod P do
          pub def dbl(xs Vec(Int53)) Vec(Int53) := List.map(xs, (x) -> x * 2)
          pub def srt(xs Vec(Int53)) Vec(Int53) := Enum.sort(xs)
        end
        """)

      # `List.map` is the portable prelude (ADR-0047) — reaches all four targets
      assert targets(rep, "dbl") == [:ex, :js, :jvm, :rs]
      # `Enum.sort` has no prelude image — host FFI, pinned to the BEAM
      assert targets(rep, "srt") == [:ex]
    end

    test "an inferred private helper reaches every target (inference widens portability)" do
      # `inc`'s parameter has no written type; private parameter inference recovers
      # `x : Int53` (ADR-0034 Phase 2), so Reach sees a concrete signature and the
      # helper is portable to :rs/:jvm — inference removes the annotation tax without
      # pinning the function off the typed targets.
      rep =
        reach("""
        mod M do
          pub def main(n Int53) Int53 := inc(n)
          def inc(x) := x + 1
        end
        """)

      assert targets(rep, "inc") == [:ex, :js, :jvm, :rs]
      assert entry(rep, "inc").blockers == []
    end

    test "the 64-bit wrap prelude reaches every target EXCEPT :js (ADR-0064)" do
      # `Int.wrapping_add` & friends carry the fixed-width-64 two's-complement
      # contract — native on Rust/JVM, masked on the BEAM, and *not representable*
      # on JS (Int64 is off :js; we refuse the silent BigInt elevation). So the
      # 64-bit wrap layer is portable across BEAM/Rust/JVM but not JS; portable
      # all-target integer code uses `Int53`/`Int32` instead.
      rep = reach(File.read!("examples/rian/prelude_int.rian"))

      for f <- ~w(wrapping_add saturating_add checked_add) do
        assert targets(rep, f) == [:ex, :jvm, :rs]
        assert Enum.any?(entry(rep, f).blockers, &(&1.kind == :numeric and &1.kills == [:js]))
      end
    end

    test "a JS-valid signature whose BODY calls a 64-bit prim is still off :js (no gate lie)" do
      # An `Int53` wrapper around `Prim.wrapping_add` has a JS-valid signature, but
      # its body calls a 64-bit overflow prim the JS emitter refuses (ADR-0064 §2a).
      # The body-call must pin it off `:js` — otherwise the gate reports
      # `:js`-reachable and the emitter then raises, the gate lying.
      rep = reach("def w(a Int53, b Int53) Int53 := Prim.wrapping_add(a, b)")

      assert targets(rep, "w") == [:ex, :jvm, :rs]
      assert Enum.any?(entry(rep, "w").blockers, &(&1.kind == :numeric and &1.kills == [:js]))
    end

    test "a body that calls `Prim.str_to_atom` is BEAM-only (atoms have no Rust/JS/JVM value)" do
      # string→atom interning is lowered only by the BEAM emitter (ADR-0047). The
      # body-call must pin the function to `:ex` alone — otherwise the gate reports
      # a non-BEAM target reachable and that emitter then raises, the gate lying.
      rep = reach("def s(x String) Symbol := Prim.str_to_atom(x)")

      assert targets(rep, "s") == [:ex]

      assert Enum.any?(
               entry(rep, "s").blockers,
               &(&1.kind == :atom and &1.kills == [:rs, :js, :jvm])
             )
    end

    test "a Rian cross-module call is portable (not host FFI)" do
      rep =
        reach("""
        mod Lex do
          pub def lex(n Int53) Int53 := n
        end
        mod Driver do
          pub def run(n Int53) Int53 := Lex.lex(n)
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
          pub def total(xs Vec(Int53)) Int53 := :lists.sum(xs)
        end
        """)

      assert targets(rep, "total") == [:ex]
      assert [%{construct: ":lists.sum", kind: :ffi, kills: kills}] = entry(rep, "total").blockers
      assert Enum.sort(kills) == [:js, :jvm, :rs]
    end

    test "a `ref` capability pins a function OFF :ex (P5 — ref is not in the portable core)" do
      rep = reach("def bump(x ref Int53) Int53 := x + 1")

      # ref (&mut) is BEAM-rejected, so the function reaches everything BUT :ex —
      # the reachability report no longer oversells `ref` as portable (ADR-0055/P5).
      assert targets(rep, "bump") == [:js, :jvm, :rs]
      assert [%{kind: :capability, kills: [:ex]}] = entry(rep, "bump").blockers
    end

    test "ordering a Symbol/atom is a compile error — equality-only boundary (P9, ADR-0041 §2)" do
      # atom term-order diverges across targets (BEAM atom-table vs &str vs enum),
      # so `:a < :b` is rejected; `==`/`!=` on atoms is fine.
      assert_raise Rian.Reach.Error, ~r/equality-only/, fn ->
        Reach.gate!(Rian.Decl.parse("def bad(s Symbol) Bool := s < :foo"))
      end

      assert Reach.symbol_lint!(Rian.Decl.parse("def ok(s Symbol) Bool := s == :foo")) == :ok
      # ordering on non-Symbols is unaffected
      assert Reach.symbol_lint!(Rian.Decl.parse("def n(a Int53) Bool := a < 5")) == :ok
    end

    test "an Elixir-module call (non-Rian) is ex-only" do
      rep =
        reach("""
        mod M do
          pub def up(s String) String := String.upcase(s)
        end
        """)

      assert targets(rep, "up") == [:ex]
      assert [%{construct: "String.upcase"}] = entry(rep, "up").blockers
    end
  end

  describe "concurrency/process/state FFI is ex-only by design (ADR-0057)" do
    test "spawn, ETS, and GenServer are flagged as concurrency, not generic FFI" do
      rep =
        reach("""
        mod C do
          pub def s() Int53 := :erlang.spawn(:m, :f, [])
          pub def t(k String) Int53 := :ets.lookup(:tab, k)
          pub def g(pid Int53) Int53 := GenServer.call(pid, :v)
        end
        """)

      for f <- ~w(s t g) do
        assert targets(rep, f) == [:ex]
        # a concurrency blocker is present (the load-bearing one); these bodies also
        # pass bare atoms (`:m`/`:tab`/`:v`), which now carry honest `:atom` blockers
        # too — both pin to `:ex`, so the function is ex-only either way.
        assert Enum.any?(entry(rep, f).blockers, &(&1.kind == :concurrency))
      end
    end

    test "a pure `:erlang` function is plain FFI, not concurrency" do
      rep =
        reach("""
        mod M do
          pub def a(x Int53) Int53 := :erlang.abs(x)
        end
        """)

      assert [%{kind: :ffi}] = entry(rep, "a").blockers
    end
  end

  describe "atoms/Result are honest against the emitters (ADR-0041 vs emitter)" do
    test "a bare value atom reaches `:ex`+`:js` but is off `:rs`/`:jvm`" do
      rep = reach("def f(s Symbol) Bool := s == :foo")
      # JS lowers an atom to a string; Rust raises BEAM-only, JVM has no atom lowering
      assert targets(rep, "f") == [:ex, :js]
      assert [%{kind: :atom, kills: [:rs, :jvm]}] = entry(rep, "f").blockers
    end

    test "a constructed Result reaches `:ex`+`:rs`+`:js` but is off `:jvm`" do
      rep =
        reach("""
        type DivErr := Bad
        def half(n Int53) Int53 | DivErr
        def half(0) := {:error, Bad}
        def half(n) := {:ok, n}
        """)

      assert targets(rep, "half") == [:ex, :js, :rs]
      assert Enum.any?(entry(rep, "half").blockers, &(&1.kind == :result and &1.kills == [:jvm]))
      # the `:ok`/`:error` tag is NOT re-flagged as a bare value atom (that would
      # wrongly also kill `:rs`/`:js`, where the emitters lower the Result)
      refute Enum.any?(entry(rep, "half").blockers, &(&1.kind == :atom))
    end

    test "a map literal reaches `:ex`+`:js` but is off `:rs`/`:jvm` (the emitters raise)" do
      rep = reach("mod M do\n  pub def build() Map := %{a: 1}\nend")

      # BEAM/JS lower a map (native map / JS object); Rust raises "map literals are
      # BEAM-only" and JVM lists `EMap` unsupported.
      assert targets(rep, "build") == [:ex, :js]

      assert Enum.any?(
               entry(rep, "build").blockers,
               &(&1.kind == :map and &1.kills == [:rs, :jvm])
             )
    end

    test "a map update `%{base | k: v}` reaches `:ex`+`:js` but is off `:rs`/`:jvm`" do
      rep = reach("mod M do\n  pub def bump(m Map) Map := %{m | k: 9}\nend")

      # the update form has the same target story as the literal — BEAM/JS lower it,
      # Rust/JVM raise BEAM-only — so the matrix pins it off `:rs`/`:jvm` (no gate lie).
      assert targets(rep, "bump") == [:ex, :js]

      assert Enum.any?(
               entry(rep, "bump").blockers,
               &(&1.kind == :map and &1.kills == [:rs, :jvm])
             )
    end

    test "a non-atom-key map `%{expr => v}` is BEAM-only — also off `:js` (ADR-0033)" do
      rep = reach(~s|mod M do\n  pub def build() Map := %{"a" => 1}\nend|)

      # a computed key has no faithful JS-object lowering (`Rian.JS` raises), so unlike
      # an atom-key map it pins off `:js` too — the matrix matches the emitters.
      assert targets(rep, "build") == [:ex]

      assert Enum.any?(
               entry(rep, "build").blockers,
               &(&1.kind == :map and &1.kills == [:rs, :js, :jvm])
             )
    end

    test "the `into: %{}` comprehension desugar inherits the map blocker (ADR-0079/ADR-0000)" do
      # `for …, into: %{}` lowers (transpiler-side) to `List.reduce(…, %{}, … Dict.put …)`.
      # Reach sees the `%{}` map literal and pins the function off `:rs`/`:jvm` automatically
      # — the honesty guarantee: the blocker comes from the real insert op, not the `for`.
      rep =
        reach(~S'''
        mod M do
          pub def build(ps Vec(Map)) Map :=
            List.reduce(ps, %{}, (__e, __acc) -> case __e do {__k, __v} -> Dict.put(__acc, __k, __v) end)
        end
        ''')

      assert Enum.any?(
               entry(rep, "build").blockers,
               &(&1.kind == :map and &1.kills == [:rs, :jvm])
             )

      refute :rs in targets(rep, "build")
    end

    test "a bitstring is BEAM-only — off `:rs`/`:js`/`:jvm` (ADR-0078; the emitters raise)" do
      rep = reach("mod M do\n  pub def enc(cp Int53) String := <<cp::utf8>>\nend")

      # `Rian.Beam` lowers Erlang bitstring forms natively; Rust/JS/JVM have no
      # faithful bit-level lowering yet and raise `Unsupported`.
      assert targets(rep, "enc") == [:ex]

      assert Enum.any?(
               entry(rep, "enc").blockers,
               &(&1.kind == :bitstring and &1.kills == [:rs, :js, :jvm])
             )
    end

    test "a bitstring PATTERN in a clause head is BEAM-only (ADR-0078; head is inspected)" do
      # the construction blocker scans bodies; a pattern-only bitstring function has no
      # `EBitstr` in its body, so Reach must inspect the clause head (as for as-patterns).
      rep =
        reach("""
        mod M do
          pub def first(s String) Int53
          pub def first(<<c::utf8, _r::binary>>) := c
          pub def first(_) := 0
        end
        """)

      assert targets(rep, "first") == [:ex]
      assert Enum.any?(entry(rep, "first").blockers, &(&1.kind == :bitstring))
    end

    test "a pin `^x` in a clause head is BEAM-only (ADR-0050; head is inspected)" do
      # the BEAM lowers a pin to repeated-var equality; the non-BEAM emitters have no
      # guard-transform yet, so Reach inspects the clause head and pins it BEAM-only.
      rep =
        reach("""
        def eq(a Int53, b Int53) Bool
        def eq(x, ^x) := true
        def eq(_, _) := false
        """)

      assert targets(rep, "eq") == [:ex]

      assert Enum.any?(
               entry(rep, "eq").blockers,
               &(&1.kind == :pin and &1.kills == [:rs, :js, :jvm])
             )
    end

    test "an as-pattern reaches `:ex`+`:rs` but is off `:js`/`:jvm` (the emitters raise)" do
      rep =
        reach("""
        type T := C(x Int53)
        def f(p T) Int53
        def f(n @ C(x)) := x
        """)

      # BEAM/Rust lower `name @ pat` via PatternLower; JS/JVM raise Unsupported.
      assert targets(rep, "f") == [:ex, :rs]

      assert Enum.any?(
               entry(rep, "f").blockers,
               &(&1.kind == :pattern and &1.kills == [:js, :jvm])
             )
    end

    test "an FFI module-head atom is not double-flagged as a bare atom" do
      rep =
        reach("""
        mod M do
          pub def total(xs Vec(Int53)) Int53 := :lists.sum(xs)
        end
        """)

      assert [%{kind: :ffi}] = entry(rep, "total").blockers
    end
  end

  describe "reachability propagates along the local call graph" do
    test "a portable-looking caller inherits a callee's ex-only pin" do
      rep =
        reach("""
        mod P do
          pub def leaf(n Int53) Int53 := :lists.sum([n])
          pub def mid(n Int53) Int53 := leaf(n) + 1
          pub def caller(n Int53) Int53 := mid(n) * 2
        end
        """)

      # leaf is directly ex-only; mid and caller have no FFI of their own but
      # cannot reach further than the function they (transitively) call
      assert targets(rep, "leaf") == [:ex]
      assert targets(rep, "mid") == [:ex]
      assert targets(rep, "caller") == [:ex]
      # the pin is propagated, so mid/caller carry no *local* blocker
      assert entry(rep, "mid").blockers == []
      assert entry(rep, "caller").blockers == []
    end

    test "a portable function calling only portable functions stays all-target" do
      rep =
        reach("""
        mod P do
          pub def inc(n Int53) Int53 := n + 1
          pub def twice(n Int53) Int53 := inc(inc(n))
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
      pub def total(xs val Vec(Int53)) Int53 := :lists.sum(xs)
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
