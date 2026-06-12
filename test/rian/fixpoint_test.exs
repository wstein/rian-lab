defmodule Rian.FixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.Fixpoint

  # The self-hosting lexer's `Token` sum lowers to these tagged tuples/atoms;
  # project each onto the reference `Rian.Lexer.expr_tokens/1` shape so the two
  # streams are comparable over the shared arithmetic domain.
  defp project({:t_num, n}), do: {:num, Integer.to_string(n)}
  defp project(:t_plus), do: {:op, "+"}
  defp project(:t_minus), do: {:op, "-"}
  defp project(:t_star), do: {:op, "*"}
  defp project(:t_slash), do: {:op, "/"}
  defp project(:tl_paren), do: {:lparen}
  defp project(:tr_paren), do: {:rparen}

  # Inputs within the toy lexer's domain (digits, `+ - * / ( )`, spaces) — the
  # subset where the Rian lexer and the reference must agree exactly.
  @corpus [
    "1",
    "42",
    "1 + 2",
    "12 + 34 * 5",
    "10 - 3 - 2",
    "1 + 2 * (3 - 4)",
    "(2 + 3) * 4",
    "12 + 3 * (4 - 5) / 6",
    "  7  *  8  "
  ]

  describe "self-hosting fixpoint (ADR-0027/0031) — Rian lexer vs reference" do
    setup do
      mod =
        Fixpoint.load_lexer(File.read!("examples/rian/selfhost_lexer.rian"), :rian_fixpoint_lexer)

      {:ok, mod: mod}
    end

    test "the compiled Rian lexer agrees with Rian.Lexer over the arithmetic corpus", %{mod: mod} do
      assert Fixpoint.check(mod, @corpus, &project/1) == :ok
    end

    test "the harness reports the first mismatch precisely (it has teeth)", %{mod: mod} do
      # a deliberately wrong projection (`+` → `-`) must be caught, proving the
      # diff is real and not vacuously passing
      wrong = fn
        :t_plus -> {:op, "-"}
        other -> project(other)
      end

      assert {:mismatch, "1 + 2", expected, got} = Fixpoint.check(mod, @corpus, wrong)
      assert {:op, "+"} in expected
      assert {:op, "-"} in got
    end
  end
end
