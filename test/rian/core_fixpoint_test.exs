defmodule Rian.CoreFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Pratt}

  # Stage of the bootstrap ladder (ADR-0063) *after* the parser: a Rian-written
  # surface→Core lowering (examples/rian/selfhost_core.rian), compiled to real
  # `.beam`, diffed against the reference `Rian.Core.from_expr` over a corpus.
  #
  # The chain is real end-to-end: a source string is parsed by the reference
  # `Rian.Pratt.parse` into surface tuples, those are injected into the port's
  # `Surface` sum, and the port's `lower/1` output is compared term-for-term with
  # `Rian.Core.from_expr` of the same surface — canonicalised to the same tagged
  # form, so the comparison is exact (the Core analog of the parser fixpoint).
  #
  # Slice (the expression-parser slice's vocabulary): number/string/identifier/
  # atom literals, prefix unary, binary operators — recursively. The remaining
  # `from_expr` vocabulary (calls, lists, blocks, lambdas, …) is the `:partial`
  # tail (ADR-0063 / docs/self-host-status.md).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_core.rian"), :rian_core_fixpoint)
    {:ok, mod: mod}
  end

  # Inject a `Rian.Pratt` surface tuple into the port's `Surface` sum
  # (constructor `SNum` lowers to the `:s_num` tag, etc.).
  defp inj({:num, s}), do: {:s_num, s}
  defp inj({:str, s}), do: {:s_str, s}
  defp inj({:id, s}), do: {:s_id, s}
  defp inj({:atom, a}), do: {:s_atom, a}
  defp inj({:unary, op, x}), do: {:s_unary, op, inj(x)}
  defp inj({:bin, op, l, r}), do: {:s_bin, op, inj(l), inj(r)}

  # Canonicalise a reference `Rian.Core` struct into the port's tagged Core form
  # (`CNum` lowers to `:c_num`, etc.), so the two are compared term-for-term.
  defp canon(%Core.ENum{text: t}), do: {:c_num, t}
  defp canon(%Core.EStr{value: v}), do: {:c_str, v}
  defp canon(%Core.EId{name: n}), do: {:c_id, n}
  defp canon(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp canon(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, canon(a)}
  defp canon(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, canon(l), canon(r)}

  defp reference(src), do: src |> Pratt.parse() |> Core.from_expr() |> canon()
  defp ported(mod, src), do: mod.lower(inj(Pratt.parse(src)))

  @corpus [
    "1",
    "x",
    ~S|"hi"|,
    ":ok",
    "-x",
    "not a",
    "1 + 2",
    "1 + 2 * 3",
    "(1 + 2) * 3",
    "a - b - c",
    "a < b and c",
    "x * y + z * w",
    "-a + b",
    "a <> b <> c",
    "not a and b or c",
    "f - g * h rem k"
  ]

  describe "self-hosting Core fixpoint (ADR-0063) — Rian lowering vs Rian.Core.from_expr" do
    test "the compiled Rian lowering agrees with from_expr term-for-term", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == reference(src),
               "Core lowering diverged from Rian.Core.from_expr on #{inspect(src)}"
      end
    end

    test "structure is preserved: `1 + 2 * 3` nests `*` under `+`", %{mod: mod} do
      assert ported(mod, "1 + 2 * 3") ==
               {:c_bin, "+", {:c_num, "1"}, {:c_bin, "*", {:c_num, "2"}, {:c_num, "3"}}}
    end
  end

  describe "teeth — the fixpoint genuinely discriminates (not vacuous)" do
    test "operand order is preserved (a non-commutative op is not folded blindly)", %{mod: mod} do
      # if the lowering dropped/reordered operands, these would collapse to equal.
      refute ported(mod, "1 - 2") == ported(mod, "2 - 1")
      assert ported(mod, "1 - 2") == {:c_bin, "-", {:c_num, "1"}, {:c_num, "2"}}
    end

    test "the operator and node kind are preserved (not a constant projection)", %{mod: mod} do
      refute ported(mod, "1 + 2") == ported(mod, "1 * 2")
      refute ported(mod, "x") == ported(mod, ":x")
      refute ported(mod, "x") == ported(mod, ~S|"x"|)
    end

    test "a mutated reference must mismatch — the diff would catch a wrong lowering", %{mod: mod} do
      # the port's lowering of `1 + 2` must NOT equal from_expr of a *different*
      # program; a port that returned a constant would pass the main test but fail here.
      refute ported(mod, "1 + 2") == reference("1 + 3")
      assert ported(mod, "1 + 2") == reference("1 + 2")
    end
  end
end
