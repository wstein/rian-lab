defmodule Rian.SelfhostFixedpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Lexer}

  # Stage 1 of the bootstrap ladder (ADR-0063): **self-application**. Beyond
  # matching the reference on a hand-written corpus (Stage 0, the fixpoint tests),
  # the Rian-written lexer here tokenizes **real toolchain source** — the
  # self-hosting pipeline (including the Rian *parser's* own source), the portable
  # preludes, and tour examples — and must agree with `Rian.Lexer.tokenize/1`
  # token-for-token. This is the strongest fixed-point-flavored proof available
  # before the compiler itself is written in Rian (the genuine vN==vN+1 bootstrap
  # fixed point is Stage 3, future). It is *self-application*, not yet a bootstrap
  # fixed point — the honesty rule of ADR-0063 §3.

  setup_all do
    {:ok, lx} =
      Beam.load(File.read!("compiler/lexer_v2.rian"), :rian_selfhost_fp_lexer)

    {:ok, lexer: lx}
  end

  # the v2 lexer's `Tok` sum projected onto the reference `Rian.Lexer` tokens.
  defp project({:t_num, s}), do: {:num, s}
  defp project({:t_id, s}), do: {:id, s}
  defp project({:t_kw, s}), do: {:kw, s}
  defp project({:t_op, s}), do: {:op, s}
  defp project({:t_str, s}), do: {:str, s}
  defp project({:t_char, cp}), do: {:char, cp}
  defp project({:t_annot, s}), do: {:annot, s}
  defp project(:tlp), do: {:lparen}
  defp project(:trp), do: {:rparen}
  defp project(:tl_bracket), do: {:lbracket}
  defp project(:tr_bracket), do: {:rbracket}
  defp project(:tl_brace), do: {:lbrace}
  defp project(:tr_brace), do: {:rbrace}
  defp project(:t_map_open), do: {:mapopen}
  defp project(:t_comma), do: {:comma}
  defp project(:t_semi), do: {:semi}
  defp project(:tnl), do: {:nl}

  defp tokens_of(lx, path) do
    src = File.read!(path)
    {src, lx.tokenize(src) |> Enum.map(&project/1)}
  end

  # Real Rian source within the lexer's slice (no char escapes / heredocs). Includes
  # the Rian PARSER's own source and the self-hosting compiler pipeline, the portable
  # preludes, and two tour modules. (Verified set: the lexer matches the reference on
  # 27 of the 33 `.rian` sources; the divergent ones use heredoc doc-comments, and
  # the lexer cannot yet lex *its own* source — char escapes `'\n'` — the frontier.)
  @sources ~w(
    compiler/parse.rian compiler/opt.rian compiler/modules.rian
    compiler/calc.rian compiler/eval.rian compiler/codegen.rian compiler/listlib.rian
    examples/rian/prelude_dict.rian examples/rian/prelude_int.rian examples/rian/prelude_str.rian
    examples/rian/01_basics.rian examples/rian/05_modules.rian
  )

  describe "self-application fixed point (ADR-0063 Stage 1) — Rian lexer over real Rian source" do
    test "the Rian lexer tokenizes real toolchain source identically to Rian.Lexer", %{lexer: lx} do
      for f <- @sources do
        {_src, got} = tokens_of(lx, f)

        assert got == Lexer.tokenize(File.read!(f)),
               "the Rian-written lexer diverged from Rian.Lexer on #{f}"
      end
    end

    test "headline: the Rian lexer lexes the Rian PARSER's own source", %{lexer: lx} do
      {src, got} = tokens_of(lx, "compiler/parse.rian")
      assert got == Lexer.tokenize(src)
      # a non-trivial real module — proves this is not a toy-input result
      assert length(got) > 500
    end
  end

  # Stage 3 prerequisite (ADR-0063 §"Open items"): a bit-identical bootstrap fixed
  # point (compile the compiler with itself, twice, and get the same bytes) is only
  # possible if emission is **deterministic**. Verify `Rian.Beam` already is — the
  # same source compiles to byte-identical bytecode on every run.
  describe "Stage 3 prerequisite — deterministic emission (ADR-0063)" do
    test "Rian.Beam emits byte-identical bytecode on recompilation" do
      for f <- ~w(opt.rian modules.rian parse.rian) do
        src = File.read!(Path.join(["compiler", f]))

        assert Beam.compile_program(src) == Beam.compile_program(src),
               "Rian.Beam emission is nondeterministic for #{f} — blocks a bit-identical bootstrap"
      end
    end
  end
end
