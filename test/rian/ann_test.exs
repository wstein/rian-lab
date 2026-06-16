defmodule Rian.AnnTest do
  # async: false — the spec-generation test compiles a module to disk and toggles the
  # global `:debug_info` compiler option, which must not race other concurrent tests.
  use ExUnit.Case, async: false

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

  test "from_beam on a module without @rian is empty (not a crash)" do
    assert Rian.Ann.from_beam(Enum) == []
  end

  describe "@rian → Dialyzer @spec generation (replaces the Elixir typespec)" do
    test "spec_parts/1 maps Rian types to Elixir typespec ASTs (ADR-0026 inverse)" do
      {:add, [p1, p2], ret} = Rian.Ann.spec_parts("pub def add(Int53, Int53) Int53")
      assert Macro.to_string(p1) == "integer()"
      assert Macro.to_string(p2) == "integer()"
      assert Macro.to_string(ret) == "integer()"
    end

    test "richer types: Vec/Option/String/Symbol/union" do
      {_, [vec], _} = Rian.Ann.spec_parts("def f(Vec(String)) Bool")
      assert Macro.to_string(vec) == "[String.t()]"

      {_, [opt], r} = Rian.Ann.spec_parts("def g(Option(Symbol)) Bool | Errors")
      assert Macro.to_string(opt) == "atom() | nil"
      assert Macro.to_string(r) == "boolean() | term()"
    end

    test "a non-def annotation (struct/type) yields no spec" do
      assert Rian.Ann.spec_parts("struct S(a String)") == nil
      assert Rian.Ann.spec_parts("type Expr := A | B") == nil
    end

    test "the @spec actually lands in the compiled .beam (single source of truth)" do
      mod = "RianSpecGen#{:erlang.unique_integer([:positive])}"
      dir = Path.join(System.tmp_dir!(), "rian_spec_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      file = Path.join(dir, "m.ex")

      File.write!(file, """
      defmodule #{mod} do
        use Rian.Ann
        @rian "pub def add(Int53, Int53) Int53"
        def add(a, b), do: a + b
      end
      """)

      prev = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)

      try do
        Kernel.ParallelCompiler.compile_to_path([file], dir)
        beam = Path.join(dir, "Elixir.#{mod}.beam") |> String.to_charlist()
        {:ok, {_, [{:abstract_code, {_, ac}}]}} = :beam_lib.chunks(beam, [:abstract_code])

        # the generated `-spec add(integer(), integer()) -> integer()` is in the bytecode
        spec = Enum.find(ac, &match?({:attribute, _, :spec, {{:add, 2}, _}}, &1))
        assert spec != nil
        # all three slots are `integer()` — the spec form mentions it three times
        assert spec |> inspect() |> then(&(length(String.split(&1, "integer")) - 1)) == 3
      after
        Code.put_compiler_option(:debug_info, prev)
        File.rm_rf!(dir)
      end
    end
  end
end
