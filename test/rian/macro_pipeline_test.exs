defmodule Rian.MacroPipelineTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl}

  describe "macros are threaded through the compile pipeline (ADR-0030)" do
    test "a top-level macro expands at its call sites and runs on the BEAM" do
      {:ok, mod} =
        Beam.load(
          """
          macro dbl(x) := x + x
          def quad(n Int64) Int64 := dbl(n) + dbl(n)
          """,
          :rian_macro_pipe_quad
        )

      # dbl(n) -> n + n, twice: quad(5) = (5+5) + (5+5) = 20
      assert mod.quad(5) == 20
    end

    test "hygiene survives the pipeline: a template-local binder cannot capture the caller's" do
      {:ok, mod} =
        Beam.load(
          """
          macro with_tmp(x) := if true do tmp Int64 := 100 ; x + tmp else 0 end
          def f(tmp Int64) Int64 := with_tmp(tmp)
          """,
          :rian_macro_pipe_hyg
        )

      # the macro-local `tmp` (=100) must not capture the caller's `tmp` (=5): 5 + 100
      assert mod.f(5) == 105
    end

    test "a macro inside a `mod` is scope-local and runs on the BEAM" do
      [{atom, bin}] =
        Beam.compile_program("""
        mod MacMod do
          macro inc(x) := x + 1
          pub def f(n Int64) Int64 := inc(inc(n))
        end
        """)

      {:module, ^atom} = :code.load_binary(atom, ~c"macmod.beam", bin)
      assert atom.f(10) == 12
    end

    test "expansion happens before every emitter — the Rust output shows expanded code" do
      out = Decl.compile("macro sq(x) := x * x\ndef area(n Int64) Int64 := sq(n)")
      {_, unit} = Enum.find(out, fn {n, _} -> n == "area" end)
      # sq(n) lowered to `n * n`, not a call to a `sq` function (macros emit no IR)
      assert Map.get(unit, :rust) =~ "n * n"
      refute Map.get(unit, :rust) =~ "sq("
    end
  end

  describe "portable-core macro discipline at the @targets boundary (ADR-0035/0058)" do
    @failable """
    macro unwrap(e) := with {:ok, v} <- e do v end
    pub def g(r Result) Int64 := unwrap(r)
    """

    test "a @targets module rejects a macro that introduces a failable bind" do
      assert_raise RuntimeError, ~r/introduces a failable bind/, fn ->
        Decl.parse("@targets(ex, rs, js) mod P do\n#{@failable}end")
      end
    end

    test "the same macro is allowed in a module with no @targets contract" do
      prog = Decl.parse("mod Q do\n#{@failable}end")
      assert length(prog.mods) == 1
    end
  end
end
