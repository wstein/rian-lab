defmodule Rian.JsFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, JS, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **ECMAScript backend** (ADR-0049
  # Tier 1): a Rian-written JS emitter (examples/rian/selfhost_js.rian), compiled
  # to real `.beam`, diffed against the reference `Rian.JS` emitter.
  #
  # The reference emits a whole function; the expression it produces is the body's
  # `return <expr>;`. So for each corpus entry the test compiles a wrapper `def`
  # with `Rian.JS.compile`, extracts that return expression, and asserts the
  # port's `emit/1` of the SAME body (parsed → Core) equals it term-for-term.
  #
  # Slice: number/string/identifier/atom literals, prefix unary, binary operators
  # — the Core slice `selfhost_core.rian` produces. The remaining `Rian.JS`
  # vocabulary (calls, lists, `if`/`case`, structs, prims) is the `:partial` tail.

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_js.rian"), :rian_js_fixpoint)
    {:ok, mod: mod}
  end

  # Core struct -> the port's tagged Core form (CNum -> :c_num, etc.).
  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EAtom{name: a}), do: {:c_atom, a}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}

  defp ported(mod, body), do: mod.emit(inj(Core.from_expr(Pratt.parse(body))))

  # the reference's JS for the expression: the `return <expr>;` of the compiled
  # wrapper function.
  defp reference(wrapper) do
    [_, expr] = Regex.run(~r/return (.+);/, JS.compile(wrapper))
    expr
  end

  # {wrapper def (type-correct, so Check.gate! passes), the body expression}
  @corpus [
    {"def f() Int53 := 1", "1"},
    {"def f(a Int53) Int53 := -a", "-a"},
    {"def f() Int53 := 1 + 2 * 3", "1 + 2 * 3"},
    {"def f(a Int53, b Int53, c Int53) Int53 := a - b - c", "a - b - c"},
    {"def f(a Int53, b Int53) Bool := a < b", "a < b"},
    {"def f(a Int53, b Int53) Bool := a <= b and a >= b", "a <= b and a >= b"},
    {"def f(a Int53, b Int53, c Int53, d Int53) Bool := a == b and c != d", "a == b and c != d"},
    {"def f(a Bool, b Bool, c Bool) Bool := not a and b or c", "not a and b or c"},
    {~S|def f(w String) String := "hi" <> w|, ~S|"hi" <> w|},
    {"def f() Bool := :ok == :no", ":ok == :no"}
  ]

  describe "self-hosting JS-backend fixpoint — Rian emitter vs Rian.JS" do
    test "the Rian emitter's output equals Rian.JS term-for-term", %{mod: mod} do
      for {wrapper, body} <- @corpus do
        assert ported(mod, body) == reference(wrapper),
               "JS emission diverged on #{inspect(body)}"
      end
    end
  end

  describe "teeth — the emitter does real remapping (not passthrough/constant)" do
    test "operators are remapped to JS spellings", %{mod: mod} do
      assert ported(mod, "a and b") == "(a && b)"
      assert ported(mod, "a or b") == "(a || b)"
      assert ported(mod, "a == b") == "(a === b)"
      assert ported(mod, "a != b") == "(a !== b)"
      # the Rian operator name must NOT survive into the JS.
      refute ported(mod, "a and b") =~ "and"
    end

    test "an atom becomes a quoted JS string, not a bare identifier", %{mod: mod} do
      assert ported(mod, ":ok") == ~S|"ok"|
      refute ported(mod, ":ok") == "ok"
    end

    test "binary is parenthesised and precedence-nested", %{mod: mod} do
      assert ported(mod, "1 + 2 * 3") == "(1 + (2 * 3))"
    end

    test "the emission discriminates different operators/operands", %{mod: mod} do
      refute ported(mod, "a + b") == ported(mod, "a - b")
      refute ported(mod, "a + b") == ported(mod, "b + a")
    end
  end
end
