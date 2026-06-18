defmodule Rian.AnnTest do
  use ExUnit.Case, async: true

  @moduledoc """
  `@rian_sig` annotations (`Rian.Ann`): a native Rian signature authored in the Elixir
  source, registered + persisted so it (a) compiles warning-free and (b) is stored in
  the `.beam`, readable from either the source or the compiled module.
  """

  # a real annotated module — `use Rian.Ann` registers/persists `@rian_sig`.
  defmodule Sample do
    use Rian.Ann

    @rian_sig "pub def f(Int53) Int53"
    def f(x), do: x + 1

    @rian_sig """
    struct S(a String, b Int53)
    """
    defstruct [:a, :b]
  end

  test "the module compiles warning-free (a bare @rian_sig would warn 'set but never used')" do
    # if this test module loaded, `use Rian.Ann` registered the attribute successfully.
    assert function_exported?(Sample, :f, 1)
  end

  test "from_source/1 extracts every @rian_sig string from Elixir source text" do
    src = ~S'''
    defmodule M do
      use Rian.Ann
      @rian_sig "pub def f(Int53) Int53"
      def f(x), do: x
      @rian_sig "type Expr := A | B"
    end
    '''

    assert Rian.Ann.from_source(src) == ["pub def f(Int53) Int53", "type Expr := A | B"]
  end

  test "from_beam/1 reads @rian_sig from a compiled module's PERSISTED attributes" do
    anns = Rian.Ann.from_beam(Sample)
    assert "pub def f(Int53) Int53" in anns
    assert Enum.any?(anns, &(&1 =~ "struct S(a String, b Int53)"))
  end

  test "from_ast/1 extracts from an already-parsed AST (no re-parse) — matches from_source" do
    src = ~S'''
    defmodule M do
      use Rian.Ann
      @rian_sig "pub def f(Int53) Int53"
      def f(x), do: x
    end
    '''

    {:ok, ast} = Code.string_to_quoted(src)
    assert Rian.Ann.from_ast(ast) == Rian.Ann.from_source(src)
    assert Rian.Ann.from_ast(ast) == ["pub def f(Int53) Int53"]
  end

  test "from_beam on a module without @rian_sig is empty (not a crash)" do
    assert Rian.Ann.from_beam(Enum) == []
  end

  test "from_beam on a module that is not loaded is empty (no rescue)" do
    refute Code.ensure_loaded?(:no_such_module_at_all)
    assert Rian.Ann.from_beam(:no_such_module_at_all) == []
  end

  describe "from_beam/1 from a .beam PATH (the no-source reader)" do
    test "reads @rian_sig from a real compiled module's .beam file" do
      path = Path.join(Application.app_dir(:rian_lab, "ebin"), "Elixir.Rian.Prim.beam")
      anns = Rian.Ann.from_beam(path)
      assert "pub def names() Vec(String)" in anns
    end

    test "a missing / unreadable .beam path is empty (not a crash)" do
      assert Rian.Ann.from_beam("/no/such/file.beam") == []
    end
  end

  describe "from_source/1 robustness" do
    test "unparseable source yields no annotations (not a raise)" do
      assert Rian.Ann.from_source("defmodule M do  @rian (((") == []
    end
  end

  describe "host_funcs/1 — @rian_host exception-boundary tagging" do
    test "names the def/defp following each @rian_host, skipping untagged defs" do
      src = ~S'''
      defmodule M do
        use Rian.Ann

        @rian_host "reads a file"
        def load(p), do: File.read!(p)

        def plain(x), do: x + 1

        @rian_host "guarded host call"
        defp parse(s) when is_binary(s), do: Code.string_to_quoted!(s)
      end
      '''

      hosts = Rian.Ann.host_funcs(src)
      assert "load" in hosts
      assert "parse" in hosts
      refute "plain" in hosts
    end

    test "unparseable source yields no host names (not a raise)" do
      assert Rian.Ann.host_funcs("defmodule M do @rian_host (((") == []
    end
  end
end
