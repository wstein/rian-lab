defmodule Rian.ComposeCoreBridgeFixpointTest do
  # async: false — loads the verified ports + the driver into the VM.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Lexer, Pratt}

  # STEP 3 (verification bridge) — the driver's surface→Core lowering is
  # equivalence-locked to `Rian.Core` via the verified `selfhost_core` oracle.
  #
  # The composition driver (compose_real_sum.rian) lowers selfhost_decl's
  # surface to `selfhost_beam`'s Core with its own `lower_surface`/`lower_pat` — the
  # last sizeable chunk of driver-local code that reimplements a stage. It was
  # locked only BEHAVIORALLY (the build runs identically to Rian.Beam). This bridge
  # locks it STRUCTURALLY: for the same source, the driver's Core, rendered to the
  # canonical s-expression, equals what `Rian.Core.from_expr` produces AND what the
  # `selfhost_core` port emits (itself locked to `Rian.Core` in core_fixpoint_test).
  # So: driver lowering ≡ selfhost_core ≡ Rian.Core.
  #
  # Scope: the VALUE-expression core of the lowering (literals, unary/binary, calls,
  # field access, tuples, lists, and their nesting). The driver deliberately does
  # MORE than `from_expr` on three node families — `Prim.x`→`__prim_x`, `Mod.f`→a
  # remote call, and call-head→name resolution — so those are its own pass (locked
  # behaviorally, not here). `if`/`case` bodies differ only in block-wrapping and are
  # likewise behaviorally locked. This bridge covers what a pure surface→Core lowering
  # is responsible for.

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.SelfhostLexerV2")

    {:ok, _} = Beam.load(File.read!("compiler/decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("compiler/beam.rian"), :"Elixir.SelfhostBeam")
    {:ok, _} = Beam.load(File.read!("compiler/core.rian"), :"Elixir.SelfhostCore")

    {:ok, drv} =
      Beam.load(File.read!("compiler/compose_real_sum.rian"), :rian_core_bridge)

    {:ok, drv: drv}
  end

  # render the driver's `selfhost_beam` Core (tagged tuples) to the canonical
  # s-expression — the SAME format `Rian.Core` renders to in core_fixpoint's `canon`
  # and `selfhost_core` emits. A plain call's head is reconstructed as `(id f)` (the
  # driver collapses the head to a name; at Core level both are `(call (id f) …)`).
  defp r({:c_num, t}), do: "(num #{t})"
  defp r({:c_str, s}), do: "(str #{s})"
  defp r({:c_char, c}), do: "(char #{c})"
  defp r({:c_id, n}), do: "(id #{n})"
  defp r({:c_atom, a}), do: "(atom #{a})"
  defp r({:c_unary, op, x}), do: "(unary #{op} #{r(x)})"
  defp r({:c_bin, op, l, rr}), do: "(bin #{op} #{r(l)} #{r(rr)})"
  defp r({:c_call, f, args}), do: "(call (id #{f}) [#{Enum.map_join(args, " ", &r/1)}])"
  defp r({:c_dot, h, n}), do: "(dot #{r(h)} #{n})"
  defp r({:c_tuple, es}), do: "(tuple [#{Enum.map_join(es, " ", &r/1)}])"
  defp r({:c_list, es, tail}), do: "(list [#{Enum.map_join(es, " ", &r/1)}] #{rtail(tail)})"

  defp rtail(:t_close), do: "close"
  defp rtail({:t_tail, e}), do: "(tail #{r(e)})"

  # reference: `Rian.Core.from_expr` rendered to the same canonical s-expr (the value
  # subset — mirrors core_fixpoint_test's `canon`).
  defp canon(%Core.ENum{text: t}), do: "(num #{t})"
  defp canon(%Core.EStr{value: s}), do: "(str #{s})"
  defp canon(%Core.EChar{value: c}), do: "(char #{c})"
  defp canon(%Core.EId{name: n}), do: "(id #{n})"
  defp canon(%Core.EAtom{name: a}), do: "(atom #{a})"
  defp canon(%Core.EUnary{op: op, arg: x}), do: "(unary #{op} #{canon(x)})"
  defp canon(%Core.EBin{op: op, left: l, right: rr}), do: "(bin #{op} #{canon(l)} #{canon(rr)})"

  defp canon(%Core.ECall{fun: f, args: as}),
    do: "(call #{canon(f)} [#{Enum.map_join(as, " ", &canon/1)}])"

  defp canon(%Core.EDot{head: h, name: n}), do: "(dot #{canon(h)} #{n})"
  defp canon(%Core.ETuple{elems: es}), do: "(tuple [#{Enum.map_join(es, " ", &canon/1)}])"

  defp canon(%Core.EList{elems: es, tail: tl}),
    do: "(list [#{Enum.map_join(es, " ", &canon/1)}] #{canon_tail(tl)})"

  defp canon_tail(nil), do: "close"
  defp canon_tail(:close), do: "close"
  defp canon_tail(core), do: "(tail #{canon(core)})"

  # the selfhost_core oracle's surface injector (Rian.Pratt surface → SelfhostCore
  # Surface), value subset; mirrors core_fixpoint_test's `inj`.
  defp inj({:num, t}), do: {:s_num, t}
  defp inj({:str, s}), do: {:s_str, s}
  defp inj({:char, c}), do: {:s_char, c}
  defp inj({:id, n}), do: {:s_id, n}
  defp inj({:atom, a}), do: {:s_atom, a}
  defp inj({:unary, op, x}), do: {:s_unary, op, inj(x)}
  defp inj({:bin, op, l, rr}), do: {:s_bin, op, inj(l), inj(rr)}
  defp inj({:call, f, args}), do: {:s_call, inj(f), Enum.map(args, &inj/1)}
  defp inj({:dot, h, n}), do: {:s_dot, inj(h), n}
  defp inj({:tuple, es}), do: {:s_tuple, Enum.map(es, &inj/1)}
  defp inj({:list_lit, es, nil}), do: {:s_list, Enum.map(es, &inj/1), :t_close}
  defp inj({:list_lit, es, :close}), do: {:s_list, Enum.map(es, &inj/1), :t_close}
  defp inj({:list_lit, es, {:tail, t}}), do: {:s_list, Enum.map(es, &inj/1), {:t_tail, inj(t)}}

  # value-expression corpus (no `if`/`case`, no `Prim.`/`Mod.f` — see moduledoc).
  @corpus [
    "1 + 2 * 3",
    "(1 + 2) * 3",
    "a - b - c",
    "f(x, y)",
    "g(1) + h(2)",
    "foo(bar(1), baz)",
    "a.name",
    "obj.field.sub",
    "f(a + b, c.d)",
    ":ok",
    "-x",
    "not a",
    "\"hello\"",
    "'a'",
    "[1, 2, 3]",
    "[h | t]",
    "[]",
    "{1, 2}",
    "{a, b.c, f(3)}",
    "x == 0 and y > 1"
  ]

  describe "Step 3 bridge — driver lowering ≡ selfhost_core ≡ Rian.Core (value exprs)" do
    test "the driver's Core renders identically to the selfhost_core oracle AND Rian.Core",
         %{drv: drv} do
      for src <- @corpus do
        driver_core = drv.lower_surface(SelfhostDecl.parse_expr(SelfhostLexerV2.tokenize(src)))
        driver_text = r(driver_core)

        rian_surface = Pratt.parse(src)
        oracle_text = SelfhostCore.emit(inj(rian_surface))
        rian_core_text = canon(Core.from_expr(rian_surface))

        assert driver_text == oracle_text,
               "driver lowering diverged from the selfhost_core oracle on #{inspect(src)}:\n  driver: #{driver_text}\n  oracle: #{oracle_text}"

        assert driver_text == rian_core_text,
               "driver lowering diverged from Rian.Core on #{inspect(src)}:\n  driver: #{driver_text}\n  Rian.Core: #{rian_core_text}"
      end
    end

    test "the oracle is the verified port — selfhost_core agrees with Rian.Core too" do
      # belt-and-braces: the same equivalence core_fixpoint_test already locks, shown
      # here so the bridge's transitivity (driver ≡ selfhost_core ≡ Rian.Core) is local.
      for src <- @corpus do
        rian_surface = Pratt.parse(src)

        assert SelfhostCore.emit(inj(rian_surface)) == canon(Core.from_expr(rian_surface)),
               "selfhost_core diverged from Rian.Core on #{inspect(src)}"
      end
    end
  end
end
