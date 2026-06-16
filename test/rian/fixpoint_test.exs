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
        Fixpoint.load_lexer(File.read!("test/fixtures/rian/lexer.rian"), :rian_fixpoint_lexer)

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

  # ── lexer port, slices 1-4 (lexer_v2.rian) ──────────────────────
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
  # slice 5 — the full `tokenize/1` vocabulary: annotations, brackets, punctuation,
  # and the significant newline (`{:nl}`).
  defp project_v2({:t_annot, s}), do: {:annot, s}
  defp project_v2(:tlp), do: {:lparen}
  defp project_v2(:trp), do: {:rparen}
  defp project_v2(:tl_bracket), do: {:lbracket}
  defp project_v2(:tr_bracket), do: {:rbracket}
  defp project_v2(:tl_brace), do: {:lbrace}
  defp project_v2(:tr_brace), do: {:rbrace}
  defp project_v2(:t_map_open), do: {:mapopen}
  defp project_v2(:t_comma), do: {:comma}
  defp project_v2(:t_semi), do: {:semi}
  defp project_v2(:tnl), do: {:nl}
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
    # escaped char literals (\n \t \r \\ \') — toward tokenizing the lexer's OWN
    # source (`lex(['\n' | rest])`, `c == '\t'`, …), which `scan_char` choked on
    ~S|'\n'|,
    ~S|'\t'|,
    ~S|'\r'|,
    ~S|'\\'|,
    ~S|'\''|,
    ~S|c == '\n' or c == '\t'|,
    ~S/lex(['\n' | rest])/,
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
          File.read!("compiler/lexer_v2.rian"),
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

  # Slice 5 corpus — the FULL declaration stream `Rian.Decl` consumes: significant
  # newlines (runs collapsed, leading/trailing dropped), `;` `,`, `@annot`,
  # brackets `[] {} %{`, line comments, and the extra operators (`-> .. := |> <>
  # <~ <- . | : &`). Checked against `Rian.Lexer.tokenize/1` (not `expr_tokens/1`).
  @corpus_tok [
    # significant newlines: collapsed runs, leading/trailing dropped
    "a\nb",
    "\n\nx\n\n",
    "a\n\n\nb\nc",
    # punctuation + brackets + map-open
    "[1, 2, 3]",
    "%{k: v, j: w}",
    "f(a, b) ; g(c)",
    # the new operators
    "x := y",
    "p |> q.r",
    "ok <- e",
    "total <~ total + n",
    "lo .. hi",
    "a <> b",
    "&f | x",
    # line comment is skipped; the newline after it survives as {:nl}
    "a # trailing comment\nb",
    # a realistic multi-line declaration (newlines, @annot, keywords, do/end, `:=`)
    "@doc\nmod M do\n  pub def f(n Int64) Int64 := n + 1\nend"
  ]

  describe "lexer port slice 5 — tokenize/1 parity (newlines, punctuation, @annot, full ops)" do
    setup do
      mod =
        Fixpoint.load_lexer(
          File.read!("compiler/lexer_v2.rian"),
          :rian_fixpoint_lexer_tok
        )

      {:ok, mod: mod}
    end

    test "the v2 Rian lexer agrees with Rian.Lexer.tokenize/1 (full declaration stream)",
         %{mod: mod} do
      assert Fixpoint.check(mod, @corpus_tok, &project_v2/1, &Rian.Lexer.tokenize/1) == :ok
    end

    # slice-5 teeth: a wrong newline projection (dropping `{:nl}`) MUST be caught —
    # significant newlines are real tokens in the declaration stream.
    test "divergence in the significant newline is caught (the diff has teeth)", %{mod: mod} do
      wrong = fn
        :tnl -> {:semi}
        other -> project_v2(other)
      end

      assert {:mismatch, "a\nb", expected, got} =
               Fixpoint.check(mod, @corpus_tok, wrong, &Rian.Lexer.tokenize/1)

      assert {:nl} in expected
      assert {:semi} in got
    end
  end

  # === reference-completeness ledger (selfhost_lexer_v2 vs Rian.Lexer) ==========
  # Does the port tokenize each lexical construct exactly like `Rian.Lexer`? A
  # `ported?` flag per construct, checked against reality, with teeth — so a
  # frontier gap (heredocs, string-body escapes, `\u{…}` char escapes, `${}`
  # interpolation, the 4 unported keywords) can't masquerade as covered.
  defp lex_covers?(mod, input) do
    Fixpoint.check(mod, [input], &project_v2/1, &Rian.Lexer.tokenize/1) == :ok
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  @lex_constructs [
    {"integer", "42", true},
    {"underscore separator", "1_000", true},
    {"float / decimal", "3.14", true},
    {"exponent (normalized)", "1e9", true},
    {"string literal", ~S|"hi"|, true},
    {"char literal", ~S|'A'|, true},
    {"char named escape", ~S|'\n'|, true},
    {"multi-char operators", "a -> b := c <> d", true},
    {"word operators", "a and b or not c", true},
    {"keywords (core)", "if do else end def type case when with", true},
    {"brackets / braces / map-open", "[1, 2] %{k: v}", true},
    {"comma / semicolon", "f(a, b) ; g(c)", true},
    {"line comment", "a # note\nb", true},
    {"significant newline", "a\nb", true},
    {"annotation @x", "@doc", true},
    # string-body escapes now decode like the reference (`\n`/`\"`/`\\` via char_esc).
    {"string-body escape", ~S|"a\nb"|, true},
    # --- the documented frontier: not yet lexed like the reference ---
    {"string interpolation ${}", ~S|"x=${n}"|, false},
    {"char unicode escape", ~S|'\u{1F600}'|, false},
    {"heredoc", "\"\"\"\ndoc\n\"\"\"", false},
    {"keywords protocol/impl/opaque/abstract", "protocol impl opaque abstract", true}
  ]

  describe "lexer completeness ledger (selfhost_lexer_v2 vs Rian.Lexer)" do
    setup do
      mod =
        Fixpoint.load_lexer(
          File.read!("compiler/lexer_v2.rian"),
          :rian_lex_completeness
        )

      {:ok, mod: mod}
    end

    test "every construct's ported? flag matches reality", %{mod: mod} do
      drift =
        for {name, input, ported?} <- @lex_constructs,
            actual = lex_covers?(mod, input),
            actual != ported? do
          "#{name}: ledger says ported?=#{ported?} but selfhost_lexer_v2 " <>
            "#{if actual, do: "MATCHES", else: "does NOT match"} Rian.Lexer"
        end

      assert drift == [], "lexer completeness ledger drifted:\n" <> Enum.join(drift, "\n")
    end

    test "lexical-construct coverage is measured and must not regress" do
      ported = Enum.count(@lex_constructs, fn {_, _, p} -> p end)
      total = length(@lex_constructs)
      IO.puts("\n  selfhost_lexer_v2 completeness: #{ported}/#{total} Rian.Lexer constructs")
      assert ported >= 13
    end
  end
end
