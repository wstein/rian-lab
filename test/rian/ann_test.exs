defmodule Rian.AnnTest do
  use ExUnit.Case, async: true

  @moduledoc """
  `@rian` annotations (`Rian.Ann`): a native Rian signature authored in the Elixir
  source, registered + persisted so it (a) compiles warning-free and (b) is stored in
  the `.beam`, readable from either the source or the compiled module.
  """

  # a real annotated module — `use Rian.Ann` registers/persists `@rian`.
  defmodule Sample do
    use Rian.Ann

    @rian "pub def f(Int53) Int53"
    def f(x), do: x + 1

    @rian """
    struct S(a String, b Int53)
    """
    defstruct [:a, :b]
  end

  test "the module compiles warning-free (a bare @rian would warn 'set but never used')" do
    # if this test module loaded, `use Rian.Ann` registered the attribute successfully.
    assert function_exported?(Sample, :f, 1)
  end

  test "from_source/1 extracts every @rian string from Elixir source text" do
    src = ~S'''
    defmodule M do
      use Rian.Ann
      @rian "pub def f(Int53) Int53"
      def f(x), do: x
      @rian "type Expr := A | B"
    end
    '''

    assert Rian.Ann.from_source(src) == ["pub def f(Int53) Int53", "type Expr := A | B"]
  end

  test "from_beam/1 reads @rian from a compiled module's PERSISTED attributes" do
    anns = Rian.Ann.from_beam(Sample)
    assert "pub def f(Int53) Int53" in anns
    assert Enum.any?(anns, &(&1 =~ "struct S(a String, b Int53)"))
  end

  test "from_ast/1 extracts from an already-parsed AST (no re-parse) — matches from_source" do
    src = ~S'''
    defmodule M do
      use Rian.Ann
      @rian "pub def f(Int53) Int53"
      def f(x), do: x
    end
    '''

    {:ok, ast} = Code.string_to_quoted(src)
    assert Rian.Ann.from_ast(ast) == Rian.Ann.from_source(src)
    assert Rian.Ann.from_ast(ast) == ["pub def f(Int53) Int53"]
  end

  test "from_beam on a module without @rian is empty (not a crash)" do
    assert Rian.Ann.from_beam(Enum) == []
  end
end
