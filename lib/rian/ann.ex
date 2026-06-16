defmodule Rian.Ann do
  @moduledoc """
  **`@rian` annotations** — author a function/struct/type's exact Rian signature in the
  Elixir source, for the cases the Elixir→Rian transpiler's inference can't recover (the
  public-API boundary above all; ADR-0034 declare-public). A native Rian declaration,
  so there's no Elixir→Rian translation guesswork.

  Used as a registered, **persisted** module attribute so it (a) compiles cleanly under
  `--warnings-as-errors` — a bare `@rian` would warn "set but never used" — and (b) is
  stored in the `.beam`, so tooling can read it from a compiled module without the source:

      defmodule Rian.IR.Func do
        use Rian.Ann

        @rian \"\"\"
        struct Func(name String, params Vec(Param), ret String,
                    clauses Vec(Clause), pub? Bool, tvars Vec(String))
        \"\"\"
        defstruct [...]

        @rian "pub def arity(Func) Int53"
        def arity(f), do: length(f.params)
      end

  A heredoc handles the multi-line struct/type case natively. The value is any Rian
  `def` / `pub def` / `struct` / `type` declaration head. Read it with `from_source/1`
  (Elixir text) or `from_beam/1` (a loaded module or a `.beam` path).
  """

  @doc """
  Register `@rian` as an accumulating, **persisted** attribute — so it compiles
  warning-free (a bare `@rian` would warn "set but never used") and is stored in the
  `.beam`, readable by tooling without the source. `@rian` is a *native Rian* annotation:
  the source of truth for a function/struct/type's type, read by the Elixir→Rian
  transpiler. No Elixir `@spec`/`@type` is generated from it — Rian is the type system.
  """
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :rian, accumulate: true, persist: true)
    end
  end

  @doc "Extract every `@rian` annotation STRING from Elixir source (via its AST)."
  @spec from_source(String.t()) :: [String.t()]
  def from_source(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> collect(ast)
      _ -> []
    end
  end

  defp collect(ast) do
    {_, anns} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{:rian, _, [str]}]} = node, acc when is_binary(str) -> {node, [str | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(anns)
  end

  @doc """
  Extract every `@rian` annotation STRING from a compiled module's persisted attributes —
  a loaded module atom or a `.beam` file path. The roundtrip / no-source reader.
  """
  @spec from_beam(module() | String.t()) :: [String.t()]
  def from_beam(module) when is_atom(module) do
    module.__info__(:attributes) |> Keyword.get_values(:rian) |> List.flatten()
  rescue
    _ -> []
  end

  def from_beam(path) when is_binary(path) do
    case :beam_lib.chunks(String.to_charlist(path), [:attributes]) do
      {:ok, {_mod, [{:attributes, attrs}]}} ->
        attrs |> Keyword.get_values(:rian) |> List.flatten()

      _ ->
        []
    end
  rescue
    _ -> []
  end
end
