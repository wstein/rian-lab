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
  defp inj(%Core.EChar{value: c}), do: {:c_char, c}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}
  defp inj(%Core.ECall{fun: %Core.EId{name: f}, args: as}), do: {:c_call, f, Enum.map(as, &inj/1)}
  defp inj(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, inj(c), inj(t), inj(e)}
  defp inj(%Core.EBlock{stmts: stmts}), do: {:c_block, Enum.map(stmts, &inj_stmt/1)}

  defp inj_stmt({:expr, e}), do: {:s_expr, inj(e)}
  defp inj_stmt({:bind, n, e}), do: {:s_bind, n, inj(e)}

  defp ported(mod, src), do: mod.infer(inj(Core.from_expr(Pratt.parse(src))))

  defp reference(src) do
    case Check.infer(Pratt.parse(src)) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  defp ported_env(mod, src, env), do: mod.infer_env(inj(Core.from_expr(Pratt.parse(src))), env)

  defp reference_env(src, env) do
    case Check.infer(Pratt.parse(src), env) do
      :unknown -> "unknown"
      ty -> ty
    end
  end

  @corpus [
    "1",
    "3.14",
    "2.5e3",
    "1.0",
    "'a'",
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
    "not (1 < 2)",
    # operand-directed arithmetic (arith_type): float arithmetic is Float64 (NOT the
    # old hardcoded Int53), char ordinals widen to Int53, and Int53+Float64 is a
    # mismatch (no implicit int→float) → unknown.
    "1.0 + 2.0",
    "3.14 * 2.0",
    "'a' + 1",
    "'z' - 'a'",
    "1.0 + 2",
    # primitive intrinsics with determinate result types
    "Prim.char_code('a')",
    "Prim.int_to_float(5)",
    ~S|Prim.str_to_atom("x")|,
    "Prim.char_to_string('a')",
    # a general call with no env is conservatively unknown
    "foo(1)",
    # `if` — LUB-join of branches (each a single-expr block). Same-type branches join
    # to that type; an int literal opposite a non-int branch can't adopt it → unknown.
    "if c do 1 else 2 end",
    "if c do true else false end",
    ~S|if c do "a" else "b" end|,
    "if c do 1 else true end"
  ]

  describe "self-hosting checker fixpoint — Rian infer vs Rian.Check.infer" do
    test "the Rian inference agrees with Rian.Check.infer over the slice", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == reference(src),
               "inference diverged on #{inspect(src)}"
      end
    end
  end

  # a typing env binding variables to types — the headline gap the port now closes.
  # (operand-directed arithmetic widths are a later rung, so bound vars appear in
  # env-lookup / comparison / unary / same-type-Int arithmetic positions.)
  @env %{
    "x" => "Int53",
    "y" => "Int53",
    "s" => "String",
    "b" => "Bool",
    "f" => "Float64",
    "w" => "Int8"
  }
  @env_corpus [
    "x",
    "y",
    "s",
    "b",
    "f",
    "z",
    "-x",
    "-f",
    "not b",
    "x < y",
    "x == y",
    "s <> s",
    "x + y",
    "x - y * x",
    "x + 1",
    # operand-directed widths under the env: an int literal adopts the typed
    # neighbour's width; Float64 arithmetic stays Float64; a mix is unknown.
    "w + 1",
    "w + w",
    "f + f",
    "x + f",
    "f * 2.0",
    # `if` under the env: a literal branch adopts the typed branch's integer type;
    # same-typed branches join to that type.
    "if c do x else 1 end",
    "if c do x else y end",
    ~S|if c do s else "z" end|
  ]

  describe "self-hosting checker fixpoint — inference under a typing env" do
    test "the Rian inference agrees with Rian.Check.infer over bound variables", %{mod: mod} do
      for src <- @env_corpus do
        assert ported_env(mod, src, @env) == reference_env(src, @env),
               "env inference diverged on #{inspect(src)}"
      end
    end

    test "a bound variable resolves to its env type; an unbound one stays unknown",
         %{mod: mod} do
      assert ported_env(mod, "x", @env) == "Int53"
      assert ported_env(mod, "s", @env) == "String"
      assert ported_env(mod, "z", @env) == "unknown"
      assert reference_env("x", @env) == "Int53"
      assert reference_env("z", @env) == "unknown"
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
