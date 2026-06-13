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

  # ── lexer port, slices 1-4 (selfhost_lexer_v2.rian) ──────────────────────
  # v2 keeps its own `Tok` sum; its parens are `TLP`/`TRP` (`:tlp`/`:trp`), distinct
  # from the toy lexer's `:tl_paren`/`:tr_paren`, so project them here. Slice 2
  # adds `TOp(String)` (`:t_op`) for comparison + word-operators. Slice 4 makes
  # `TNum` carry the number *lexeme* (`:t_num` with a string, not a folded int),
  # matching the reference's `{:num, lexeme}` — floats, `_` separators, exponents.
  defp project_v2({:t_num, s}), do: {:num, s}
  defp project_v2({:t_id, s}), do: {:id, s}
  defp project_v2({:t_kw, s}), do: {:kw, s}
  defp project_v2({:t_op, s}), do: {:op, s}
  defp project_v2({:t_str, s}), do: {:str, s}
  defp project_v2({:t_char, cp}), do: {:char, cp}
  defp project_v2(:tlp), do: {:lparen}
  defp project_v2(:trp), do: {:rparen}
  defp project_v2(other), do: project(other)

  # within slices 1-4: integers, identifiers, all 16 keywords, the comparison
  # operators (`< > <= >= == !=`), the word-operators (`and or not in rem div`),
  # `+ - * /`, parens, spaces, **string** (`"…"`) and **char** (`'X'`) literals,
  # and **numbers** — `_` separators, decimals, and exponents (incl. the
  # `norm_num` rule: a bare `1e9` normalizes to `1.0e9`).
  # (Out of slice: escapes in literals, brackets, significant newlines.)
  @corpus_v2 [
    "foo",
    "x_1",
    "if x do y end",
    "12 * (x_1 + foo)",
    "a + b - c",
    "def f",
    "x1 * y2 / z3",
    "  spaced  out  ",
    "ifx else end",
    # slice 2 — comparisons (two-char longest match) + word-operators
    "a <= b and c == d",
    "x != y or not z",
    "if a >= 2 do c end",
    "p rem q div r in s",
    "12 < 34",
    "i > 0 and i < 10",
    # slice 3 — string + char literals
    "\"hi\"",
    "'A'",
    "foo \"bar\" + 'z'",
    "if c == 'x' do \"yes\" else \"no\" end",
    # slice 4 — number lexemes: `_` separators, decimals, exponents (norm_num)
    "1_000",
    "3.14",
    "1.0",
    "1e9",
    "1E9",
    "1.0e9",
    "1.0E9",
    "1e+9",
    "2_500.50e-3",
    "1 + 2_000 * 3.5",
    "(1.5e2)",
    # every keyword at least once, so the full @keywords slice is exercised
    "type range case when struct alias mod pub const macro use with def if do else end"
  ]

  describe "lexer port slices 1-4 — ids, keywords, comparisons, word-ops, literals, numbers" do
    setup do
      mod =
        Fixpoint.load_lexer(
          File.read!("examples/rian/selfhost_lexer_v2.rian"),
          :rian_fixpoint_lexer_v2
        )

      {:ok, mod: mod}
    end

    test "the v2 Rian lexer agrees with Rian.Lexer over the slices 1-4 corpus", %{mod: mod} do
      assert Fixpoint.check(mod, @corpus_v2, &project_v2/1) == :ok
    end

    # CI lock: a deliberate divergence in the v2 slice (a wrong comparison-op
    # projection) MUST be caught, so drift in either lexer fails the build.
    test "divergence in the slice-2 vocabulary is caught (the diff has teeth)", %{mod: mod} do
      wrong = fn
        {:t_op, "<="} -> {:op, "<"}
        other -> project_v2(other)
      end

      assert {:mismatch, "a <= b and c == d", expected, got} =
               Fixpoint.check(mod, @corpus_v2, wrong)

      assert {:op, "<="} in expected
      assert {:op, "<"} in got
    end

    # slice-4 teeth: a number-lexeme divergence (dropping the `norm_num` `.0`
    # insertion) MUST be caught — the lexeme must match the reference exactly.
    test "divergence in a number lexeme is caught (the diff has teeth)", %{mod: mod} do
      wrong = fn
        {:t_num, "1.0e9"} -> {:num, "1e9"}
        other -> project_v2(other)
      end

      assert {:mismatch, "1e9", expected, got} = Fixpoint.check(mod, @corpus_v2, wrong)
      assert {:num, "1.0e9"} in expected
      assert {:num, "1e9"} in got
    end
  end
end
