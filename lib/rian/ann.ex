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
  Register `@rian` as an accumulating, persisted attribute (compiles warning-free) and
  install a `@before_compile` hook that emits a Dialyzer `@spec` for each `def`
  annotation — so a `@rian` carries the type **into the `.beam`** exactly like a hand
  written `@spec`, and a single native-Rian annotation replaces the Elixir typespec.
  """
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :rian, accumulate: true, persist: true)
      @before_compile Rian.Ann
    end
  end

  @doc false
  # generate `@spec` for every `def` annotation. NOTE: deliberately self-contained
  # (a tiny string parser + type map) — it must NOT call `Rian.Decl`, because the
  # parser-core modules (`Check`/`Decl`/`Lexer`/`Pratt`) themselves `use Rian.Ann`,
  # and `Rian.Decl` depends on them: using it here would be a compile cycle.
  defmacro __before_compile__(env) do
    specs =
      (Module.get_attribute(env.module, :rian) || [])
      |> Enum.flat_map(fn str ->
        case spec_parts(str) do
          nil -> []
          {name, params, ret} -> [quote(do: @spec(unquote(spec_ast(name, params, ret))))]
        end
      end)

    # a macro must return ONE AST — splice the generated `@spec`s into a block.
    {:__block__, [], specs}
  end

  @doc """
  Translate a Rian `def` annotation string into Elixir typespec parts
  `{name :: atom, param_type_asts, return_type_ast}`, or `nil` for a non-`def`
  (`struct`/`type`) annotation. The inverse of the Elixir→Rian spec map (ADR-0026).
  """
  @spec spec_parts(String.t()) :: {atom(), [Macro.t()], Macro.t()} | nil
  def spec_parts(str) do
    str =
      str |> String.replace(~r/\s+/, " ") |> String.trim() |> String.replace_prefix("pub ", "")

    with "def " <> rest <- str,
         [_, name, params, ret] <- Regex.run(~r/^(\w+)\((.*)\)\s*(.*)$/, rest) do
      {String.to_atom(name), params |> split_top() |> Enum.map(&rian_type_to_ast/1),
       rian_type_to_ast(ret)}
    else
      _ -> nil
    end
  end

  # `@spec name(p1, p2) :: ret` as a quoted `::` expression.
  defp spec_ast(name, params, ret), do: {:"::", [], [{name, [], params}, ret]}

  # Rian type string -> Elixir typespec AST. Unknown user types / tvars degrade to
  # `term()` (Dialyzer-safe: precise enough to be useful, never a false positive).
  defp rian_type_to_ast(t) do
    t = String.trim(t)

    cond do
      t == "" ->
        quote(do: term())

      Regex.match?(~r/^U?Int\d*$/, t) ->
        quote(do: integer())

      Regex.match?(~r/^Float\d*$/, t) ->
        quote(do: float())

      t == "Bool" ->
        quote(do: boolean())

      t == "String" ->
        quote(do: String.t())

      t == "Symbol" ->
        quote(do: atom())

      t == "Char" ->
        quote(do: char())

      String.contains?(t, " | ") ->
        union_ast(t)

      match = Regex.run(~r/^Vec\((.*)\)$/, t) ->
        [rian_type_to_ast(Enum.at(match, 1))]

      match = Regex.run(~r/^Option\((.*)\)$/, t) ->
        {:|, [], [rian_type_to_ast(Enum.at(match, 1)), nil]}

      Regex.match?(~r/^Map\(/, t) ->
        quote(do: map())

      true ->
        quote(do: term())
    end
  end

  defp union_ast(t) do
    t |> split_top("|") |> Enum.map(&rian_type_to_ast/1) |> Enum.reduce(&{:|, [], [&2, &1]})
  end

  # split on a separator at paren-depth 0 (so `Vec(Int53), Map(K, V)` → two parts).
  defp split_top(str, sep \\ ",") do
    {parts, last, _} =
      str
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn ch, {parts, cur, depth} ->
        cond do
          ch == sep and depth == 0 -> {[cur | parts], "", depth}
          ch in ["(", "[", "{"] -> {parts, cur <> ch, depth + 1}
          ch in [")", "]", "}"] -> {parts, cur <> ch, depth - 1}
          true -> {parts, cur <> ch, depth}
        end
      end)

    [last | parts] |> Enum.reverse() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
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
