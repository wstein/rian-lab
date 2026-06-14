defmodule Rian.RustEmitFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Lower, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **Rust/Elixir text backend** (ADR-0049):
  # a Rian-written emitter (examples/rian/selfhost_rust.rian), compiled to real
  # `.beam`, diffed against the reference `Rian.Lower.emit_expr(_, :rust)` AND
  # `(_, :elixir)` — both text targets `Rian.Lower` serves.
  #
  # The emitter is precedence-aware (a paren only when a child binds looser than
  # its context); the corpus exercises mixed-precedence/associativity, calls, `if`,
  # tuples, and closed lists. Only operator spelling (`and`/`or`, unary `not`) and
  # the `if`/tuple/list shapes differ by target — so the same corpus is asserted
  # against both. Dot, cons-lists, structs, `case`, maps, and atoms are the
  # `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_rust.rian"), :rian_rust_fixpoint)
    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}
  defp inj(%Core.ECall{fun: %Core.EId{name: f}, args: as}), do: {:c_call, f, Enum.map(as, &inj/1)}
  # an `if`'s branches are single-expression blocks in the slice — unwrap them.
  defp inj(%Core.EIf{cond: c, then: t, else: e}), do: {:c_if, inj(c), inj(t), inj(e)}
  defp inj(%Core.EBlock{stmts: [{:expr, e}]}), do: inj(e)
  defp inj(%Core.ETuple{elems: es}), do: {:c_tuple, Enum.map(es, &inj/1)}
  defp inj(%Core.EList{elems: es, tail: :close}), do: {:c_list, Enum.map(es, &inj/1)}

  # the port's target sum lowers to atoms (`TRust` -> `:t_rust`).
  defp tag(:rust), do: :t_rust
  defp tag(:elixir), do: :t_elixir

  defp ported(mod, src, target),
    do: mod.render(inj(Core.from_expr(Pratt.parse(src))), tag(target))

  @corpus [
    "1",
    "a",
    "-a",
    "not a",
    "1 + 2 * 3",
    "1 * 2 + 3",
    "(1 + 2) * 3",
    "a - b - c",
    "a - (b - c)",
    "a * (b + c)",
    "-a + b",
    "not a and b or c",
    "a == b and c != d",
    "a <= b and a >= b",
    "a < b or c > d",
    "a + b * c - d",
    ~S|"hi"|,
    # calls: prec 12 (tightest), args at context 0 (a binary arg keeps no parens),
    # nested calls recurse, and a call as an operand binds tighter
    "f()",
    "f(a, b)",
    "f(a + 1, b)",
    "f(g(a), b)",
    "f(a) + b",
    "g(a - b)",
    # `if` (Rust braces / Elixir do…end), cond rendered at context 0
    "if a do 1 else 2 end",
    "if a > b do a else b end",
    # tuples (Rust `(…)` / Elixir `{…}`) and closed lists (Rust `vec![…]` / Elixir `[…]`)
    "{1, 2}",
    "{a, f(b)}",
    "[1, 2, 3]",
    "[a, b]",
    "[f(a), b + 1]"
  ]

  describe "self-hosting text-backend fixpoint — Rian emitter vs Rian.Lower (both targets)" do
    test "equals Rian.Lower.emit_expr term-for-term on :rust AND :elixir", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src, :rust) == Lower.emit_expr(src, :rust),
               "Rust emission diverged on #{inspect(src)}"

        assert ported(mod, src, :elixir) == Lower.emit_expr(src, :elixir),
               "Elixir emission diverged on #{inspect(src)}"
      end
    end
  end

  describe "teeth — precedence-aware parenthesisation, not blanket or none" do
    test "a paren is added only when a child binds looser than its context", %{mod: mod} do
      # mixed precedence: no paren needed (`*` binds tighter than `+`).
      assert ported(mod, "1 + 2 * 3", :rust) == "1 + 2 * 3"
      # but a looser child on the tight side IS parenthesised.
      assert ported(mod, "(1 + 2) * 3", :rust) == "(1 + 2) * 3"
      # left-assoc `-`: the right operand needs parens, the left does not.
      assert ported(mod, "a - b - c", :rust) == "a - b - c"
      assert ported(mod, "a - (b - c)", :rust) == "a - (b - c)"
    end

    test "the two targets spell the SAME tree differently", %{mod: mod} do
      # operator words: Rust remaps `and`/`or`/`not`, Elixir keeps them
      assert ported(mod, "not a and b or c", :rust) == "!a && b || c"
      assert ported(mod, "not a and b or c", :elixir) == "not a and b or c"
      # `if`: Rust braces vs Elixir `do … end`
      assert ported(mod, "if a do 1 else 2 end", :rust) == "if a { 1 } else { 2 }"
      assert ported(mod, "if a do 1 else 2 end", :elixir) == "if a do 1 else 2 end"
      # tuple: Rust `(…)` vs Elixir `{…}`
      assert ported(mod, "{1, 2}", :rust) == "(1, 2)"
      assert ported(mod, "{1, 2}", :elixir) == "{1, 2}"
      # list: Rust `vec![…]` vs Elixir `[…]`
      assert ported(mod, "[1, 2, 3]", :rust) == "vec![1, 2, 3]"
      assert ported(mod, "[1, 2, 3]", :elixir) == "[1, 2, 3]"
    end

    test "the emission discriminates structure", %{mod: mod} do
      refute ported(mod, "1 + 2 * 3", :rust) == ported(mod, "(1 + 2) * 3", :rust)
      refute ported(mod, "a - b", :rust) == ported(mod, "b - a", :rust)
      refute ported(mod, "{1, 2}", :rust) == ported(mod, "[1, 2]", :rust)
    end

    test "a call binds tightest and its args take no parens", %{mod: mod} do
      assert ported(mod, "f(a) + b", :rust) == "f(a) + b"
      assert ported(mod, "f(a + 1, b)", :rust) == "f(a + 1, b)"
      assert ported(mod, "f(g(a), b)", :rust) == "f(g(a), b)"
    end
  end
end
