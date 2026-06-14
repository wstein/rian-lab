defmodule Rian.CheckerInferFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Check, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **type-checker** stage: a Rian-written
  # type inference (examples/rian/selfhost_checker.rian) — a slice of the REAL
  # `Rian.Check.infer/3`, not the toy-language `selfhost_check` checker —
  # compiled to real `.beam`, diffed against `Rian.Check.infer` over a corpus.
  #
  # The reference returns a type string or the atom `:unknown`; the port returns
  # the string `"unknown"` (Rian has no bare atom result here), so the test maps
  # `:unknown -> "unknown"` before comparing.
  #
  # Slice: closed integer expressions (no env, no float literals). Variables,
  # float widths, calls, lambdas, `case`, and abstract operators are the
  # `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_checker.rian"), :rian_checker_infer_fixpoint)

    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}

  defp ported(mod, src), do: mod.infer(inj(Core.from_expr(Pratt.parse(src))))

  defp reference(src) do
    case Check.infer(Pratt.parse(src)) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  @corpus [
    "1",
    "true",
    "false",
    "x",
    "-5",
    "not 1",
    "1 + 2",
    "1 - 2 * 3",
    "1 div 2",
    "1 rem 2",
    "1 / 2",
    "1 < 2",
    "1 <= 2",
    "1 == 2",
    "1 != 2",
    "1 == 2 and 3 < 4",
    "1 < 2 or 3 > 4",
    ~S|"a" <> "b"|,
    "-(1 + 2)",
    "not (1 < 2)"
  ]

  describe "self-hosting checker fixpoint — Rian infer vs Rian.Check.infer" do
    test "the Rian inference agrees with Rian.Check.infer over the slice", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == reference(src),
               "inference diverged on #{inspect(src)}"
      end
    end
  end

  describe "teeth — the inference is real and conservative" do
    test "an unbound identifier is `unknown` — the checker does not guess", %{mod: mod} do
      assert ported(mod, "x") == "unknown"
      assert reference("x") == "unknown"
    end

    test "a comparison is Bool, not the operands' Int53", %{mod: mod} do
      assert ported(mod, "1 < 2") == "Bool"
      refute ported(mod, "1 < 2") == ported(mod, "1 + 2")
    end

    test "`/` is Float64 even over integer operands (special rule)", %{mod: mod} do
      assert ported(mod, "1 / 2") == "Float64"
      refute ported(mod, "1 / 2") == ported(mod, "1 div 2")
    end

    test "`<>` is String and arithmetic is Int53", %{mod: mod} do
      assert ported(mod, ~S|"a" <> "b"|) == "String"
      assert ported(mod, "1 + 2") == "Int53"
    end
  end
end
