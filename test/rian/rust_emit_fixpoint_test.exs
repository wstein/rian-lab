defmodule Rian.RustEmitFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Core, Lower, Pratt}

  # Self-hosting fixpoint (ADR-0063) for the **Rust text backend** (ADR-0049): a
  # Rian-written Rust emitter (examples/rian/selfhost_rust.rian), compiled to real
  # `.beam`, diffed against the reference `Rian.Lower.emit_expr(_, :rust)`.
  #
  # Unlike JS (blanket parens), the Rust emitter is precedence-aware — a paren is
  # added only when a child binds looser than its context — so the corpus
  # includes mixed-precedence and associativity cases that exercise exactly that.
  #
  # Slice: number/string/identifier literals, prefix unary, binary operators with
  # the full precedence/associativity table. Atoms (BEAM-only on Rust) and
  # calls/lists/structs are the `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} = Beam.load(File.read!("examples/rian/selfhost_rust.rian"), :rian_rust_fixpoint)
    {:ok, mod: mod}
  end

  defp inj(%Core.ENum{text: t}), do: {:c_num, t}
  defp inj(%Core.EStr{value: v}), do: {:c_str, v}
  defp inj(%Core.EId{name: n}), do: {:c_id, n}
  defp inj(%Core.EUnary{op: op, arg: a}), do: {:c_unary, op, inj(a)}
  defp inj(%Core.EBin{op: op, left: l, right: r}), do: {:c_bin, op, inj(l), inj(r)}

  defp ported(mod, src), do: mod.render(inj(Core.from_expr(Pratt.parse(src))))

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
    ~S|"hi"|
  ]

  describe "self-hosting Rust-backend fixpoint — Rian emitter vs Rian.Lower" do
    test "the Rian emitter equals Rian.Lower.emit_expr(_, :rust) term-for-term", %{mod: mod} do
      for src <- @corpus do
        assert ported(mod, src) == Lower.emit_expr(src, :rust),
               "Rust emission diverged on #{inspect(src)}"
      end
    end
  end

  describe "teeth — precedence-aware parenthesisation, not blanket or none" do
    test "a paren is added only when a child binds looser than its context", %{mod: mod} do
      # mixed precedence: no paren needed (`*` binds tighter than `+`).
      assert ported(mod, "1 + 2 * 3") == "1 + 2 * 3"
      # but a looser child on the tight side IS parenthesised.
      assert ported(mod, "(1 + 2) * 3") == "(1 + 2) * 3"
      # left-assoc `-`: the right operand needs parens, the left does not.
      assert ported(mod, "a - b - c") == "a - b - c"
      assert ported(mod, "a - (b - c)") == "a - (b - c)"
    end

    test "operators are remapped to Rust (and→&&, or→||, not→!)", %{mod: mod} do
      assert ported(mod, "not a and b or c") == "!a && b || c"
      refute ported(mod, "a and b") =~ "and"
    end

    test "the emission discriminates structure", %{mod: mod} do
      refute ported(mod, "1 + 2 * 3") == ported(mod, "(1 + 2) * 3")
      refute ported(mod, "a - b") == ported(mod, "b - a")
    end
  end
end
