defmodule Rian.ComposeDeclWholeFixpointTest do
  # async: false — loads the verified ports (by their natural atoms) + the driver,
  # and `build/2` loads the freshly-compiled decl parser at runtime.
  use ExUnit.Case, async: false

  alias Rian.Beam

  # THE LOOP CLOSES ON THE WHOLE DECLARATION PARSER (ADR-0063 Step 3 / §4). Like
  # `compose_lexer_fixpoint_test`, this feeds the composed `build` the ENTIRE
  # `compiler/decl.rian` — ~400 lines: the `mod` wrapper, sum/struct
  # types, generic signatures (`forall T`), multi-clause guarded functions, `if`,
  # `case` with guarded arms and next-line arm bodies, string/char literals and
  # patterns, `<>`, `Prim.*`, list construction, and the P1 newline-tolerant `:=`
  # bodies / trailing-operator line continuation the parser itself relies on — and
  # the composed build (verified lexer + decl parser + beam backend, cross-module)
  # compiles it into a real loadable module.
  #
  # That Rian-built decl parser then parses IDENTICALLY to the reference parser
  # (`Decl`, which `decl_fixpoint_test` already locks against `Rian.Decl`).
  # This is the second whole stage (after the lexer, `compose_lexer_fixpoint_test`)
  # to compile its **own whole source** — the v1==v2 shape, now on the declaration
  # parser. (`compose_decl_fixpoint_test` is the older, narrower single-`def`
  # composition over `compose_decl.rian`; this one is the whole file.)
  #
  # Honesty (mirrors Rian.SelfHost @composition): the loop is self-COMPILING, not
  # self-CHECKING — Rian.Check/Exhaustiveness/Capability are not in `build`.

  @decl_file "compiler/decl.rian"
  @decl_src File.read!(@decl_file)

  setup_all do
    {:ok, _} =
      Beam.load(File.read!("compiler/lexer_v2.rian"), :"Elixir.LexerV2")

    {:ok, _} = Beam.load(@decl_src, :"Elixir.Decl")
    {:ok, _} = Beam.load(File.read!("compiler/beam.rian"), :"Elixir.Beam")

    {:ok, _} =
      Beam.load(File.read!("compiler/exhaust.rian"), :"Elixir.Exhaust")

    {:ok, _} = Beam.load(File.read!("compiler/cap.rian"), :"Elixir.Cap")

    {:ok, _} = Beam.load(File.read!("compiler/checker.rian"), :"Elixir.Checker")

    {:ok, drv} =
      Beam.load(
        File.read!("compiler/compose_real_sum.rian"),
        :rian_compose_decl_whole
      )

    built = drv.build(@decl_src, :"RianBuiltDecl_#{System.unique_integer([:positive])}")
    {:ok, built: built, ref: :"Elixir.Decl", lexer: :"Elixir.LexerV2"}
  end

  # inputs that exercise the decl parser's full vocabulary — sum/struct types,
  # generic signatures, single-clause `:=` bodies, multi-clause guarded functions,
  # `if`/`case` (incl. guarded arms + next-line arm bodies), strings/chars/patterns,
  # `<>`, `Prim.*`, list construction, and the newline-tolerant `:=` / trailing-op
  # continuation the parser uses on its own source. If the self-hosted build
  # mis-compiled any clause, one of these diverges from the reference.
  @corpus [
    "def f(x) := x + 1",
    "type T := A | B(Int53) | C(String, Int53)",
    "struct P := P(x Int53, y Int53)",
    "pub def add(a Int64, b Int64) Int64 := a + b",
    "def length(xs Vec(T)) Int53 forall T\n  case xs do\n    [] -> 0\n    [_ | t] -> 1 + length(t)\n  end\nend",
    "def cls(c Int53) Bool := c >= 65 and c <= 90",
    "def g(n)\n  if n == 0 do\n    1\n  else\n    n\n  end\nend",
    "def pick(c) String\n  case c do\n    'x' -> \"ex\"\n    _ -> \"other\"\n  end\nend",
    "def cat(a String, b String) String := a <> b",
    "def pc(s String) String := Prim.str_concat(\"_\", s)",
    "def starts(c) Bool :=\n  c == 'a' or c == 'b' or\n  c == 'c' or c == 'd'",
    "def hd([x | _]) := x",
    "def cls2(c)\n  case c do\n    n when n >= 48 -> n\n    _ -> 0\n  end\nend",
    "mod M do\n  def one() := 1\n  def two() := 2\nend"
  ]

  describe "the loop closes on the decl parser — `build` self-compiles the whole file" do
    test "the Rian-built decl parser parses identically to the reference over the corpus",
         %{built: built, ref: ref, lexer: lexer} do
      for src <- @corpus do
        toks = lexer.tokenize(src)

        assert built.parse_program(toks) == ref.parse_program(toks),
               "the self-hosted-build decl parser diverged from the reference on #{inspect(src)}"
      end
    end

    test "it is the WHOLE real file (verbatim), not a slice", %{built: built} do
      # the source compiled is compiler/decl.rian unmodified, and the
      # built module exports the real entry point.
      assert @decl_src =~ "mod Decl do"
      assert @decl_src =~ "pub def parse_program("
      assert function_exported?(built, :parse_program, 1)
    end
  end
end
