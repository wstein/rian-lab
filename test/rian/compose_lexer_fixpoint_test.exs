defmodule Rian.ComposeLexerFixpointTest do
  # async: false — loads the verified ports (by their natural atoms) + the driver,
  # and `build/2` loads the freshly-compiled lexer module at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE LOOP CLOSES ON A WHOLE STAGE (ADR-0063 Step 3 / §4). Every other composition
  # fixpoint feeds `build` a hand-written corpus or a verbatim *slice*. This one feeds
  # it the ENTIRE `examples/rian/selfhost_lexer_v2.rian` — `mod` wrapper, multi-clause
  # guarded functions, single typed clauses (`pub def tokenize(…) := …`), char/string
  # and escape literals (`'\n'`), `Prim.*`, `<>`, and list construction — and the
  # composed build (verified lexer + decl parser + beam backend, cross-module)
  # compiles it into a real loadable module.
  #
  # That Rian-built lexer then tokenizes IDENTICALLY to the reference lexer
  # (`SelfhostLexerV2`, which the per-stage fixpoint already locks against
  # `Rian.Lexer`). This is the first time a stage compiles its **own whole source**,
  # not a toy or a slice — the v1==v2 shape, on the lexer.
  #
  # Honesty (mirrors Rian.SelfHost @composition): the loop is self-COMPILING, not
  # self-CHECKING — Rian.Check/Exhaustiveness/Capability are not in `build`.

  @lexer_file "examples/rian/selfhost_lexer_v2.rian"
  @lexer_src File.read!(@lexer_file)

  setup_all do
    {:ok, _} = Beam.load(@lexer_src, :"Elixir.SelfhostLexerV2")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :"Elixir.SelfhostDecl")
    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_beam.rian"), :"Elixir.SelfhostBeam")

    {:ok, _} = Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :"Elixir.SelfhostExhaust")

    {:ok, drv} =
      Beam.load(File.read!("examples/rian/selfhost_compose_real_sum.rian"), :rian_compose_lexer)

    built = drv.build(@lexer_src, :"RianBuiltLexer_#{System.unique_integer([:positive])}")
    {:ok, built: built, ref: :"Elixir.SelfhostLexerV2"}
  end

  # inputs that exercise the lexer's full token vocabulary — ids/keywords, two-char
  # operators, word-ops, strings/chars + escapes, numbers, lists, comments, atoms,
  # punctuation. If the self-hosted build mis-compiled any clause, one of these
  # diverges from the reference.
  @corpus [
    "1 + 2 * 3",
    "def f(x) := x_1 + foo",
    "a <= b and c == d or not e",
    "p rem q div r in s",
    "if c == 'x' do \"yes\" else \"no\" end",
    "type Tok := TNum(String) | TPlus",
    "[h | t] ++ rest",
    "x <> \"!\"",
    "1_000 + 3.14 + 2_500.50e-3",
    "Prim.str_chars(s)",
    "# a comment\nlex(rest)",
    "case n do\n  0 -> 1\n  _ -> 2\nend",
    ~S|'\n'|,
    ~S|'\t'|,
    ~S/lex(['\n' | rest]) := more/,
    "@external x.y",
    "%{k: v}",
    "type range case when struct alias mod pub const macro use with def if do else end"
  ]

  describe "the loop closes on the lexer — `build` self-compiles the whole file" do
    test "the Rian-built lexer tokenizes identically to the reference over the corpus", %{
      built: built,
      ref: ref
    } do
      for src <- @corpus do
        assert built.tokenize(src) == ref.tokenize(src),
               "the self-hosted-build lexer diverged from the reference on #{inspect(src)}"
      end
    end

    test "it is the WHOLE real file (verbatim), not a slice", %{built: built} do
      # the source compiled is examples/rian/selfhost_lexer_v2.rian unmodified, and
      # the built module exports the real entry point.
      assert @lexer_src =~ "mod SelfhostLexerV2 do"
      assert @lexer_src =~ "pub def tokenize(src String) Vec(Tok)"
      assert function_exported?(built, :tokenize, 1)
    end
  end
end
