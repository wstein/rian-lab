defmodule Rian.KotlinEmitFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, JVM, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **Kotlin/JVM backend** (ADR-0049
  # Tier 2): a Rian-written Kotlin emitter (examples/rian/selfhost_kotlin.rian),
  # compiled to real `.beam`, diffed against the reference `Rian.JVM` emitter.
  #
  # `Rian.JVM` emits a whole function; the expression is its body's
  # `return <expr>`. For each corpus entry the test compiles a wrapper def with
  # `Rian.JVM.compile`, extracts that return expression, and asserts the port's
  # `emit/1` of the same body equals it term-for-term. (No `kotlinc` needed —
  # this checks the emitter text, which `Rian.JVM`'s own `:jvm` tests then run.)
  #
  # Slice: integer literals, strings, identifiers, prefix unary, binary operators.
  # Floats, atoms, calls/lists/structs are the `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_kotlin.rian"), :rian_kotlin_fixpoint)

    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}

  defp ported(mod, body), do: mod.emit(inj(Core.from_expr(Pratt.parse(body))))

  defp reference(wrapper) do
    [_, expr] = Regex.run(~r/return (.+)/, JVM.compile(wrapper))
    String.trim(expr)
  end

  @corpus [
    {"def f() Int53 := 1", "1"},
    {"def f(a Int53) Int53 := -a", "-a"},
    {"def f(a Int53, b Int53, c Int53) Int53 := a + b * c", "a + b * c"},
    {"def f(a Int53, b Int53, c Int53) Int53 := a rem b div c", "a rem b div c"},
    {"def f(a Int53, b Int53) Bool := a < b", "a < b"},
    {"def f(a Int53, b Int53, c Int53, d Int53) Bool := a == b and c != d", "a == b and c != d"},
    {"def f(a Bool, b Bool, c Bool) Bool := not a and b or c", "not a and b or c"},
    {~S|def f(w String) String := "hi" <> w|, ~S|"hi" <> w|}
  ]

  describe "self-hosting Kotlin-backend fixpoint — Rian emitter vs Rian.JVM" do
    test "the Rian emitter equals Rian.JVM term-for-term", %{mod: mod} do
      for {wrapper, body} <- @corpus do
        assert ported(mod, body) == reference(wrapper),
               "Kotlin emission diverged on #{inspect(body)}"
      end
    end
  end

  describe "teeth — Kotlin spellings differ from JS, and structure is preserved" do
    test "== stays structural == (not JS's ===), and operators remap", %{mod: mod} do
      assert ported(mod, "a == b") == "(a == b)"
      assert ported(mod, "a != b") == "(a != b)"
      assert ported(mod, "a and b") == "(a && b)"
      assert ported(mod, "a div b") == "(a / b)"
      assert ported(mod, "a rem b") == "(a % b)"
    end

    test "integer literals carry the L (Long) suffix", %{mod: mod} do
      assert ported(mod, "1") == "1L"
      assert ported(mod, "1 + 2") == "(1L + 2L)"
    end

    test "binary is parenthesised and the emission discriminates", %{mod: mod} do
      assert ported(mod, "a + b * c") == "(a + (b * c))"
      refute ported(mod, "a + b") == ported(mod, "a - b")
    end
  end
end
