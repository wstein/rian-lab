defmodule Rian.Ann do
  @moduledoc """
  **`@rian_sig` annotations** — author a function/struct/type's exact Rian signature in the
  Elixir source, for the cases the Elixir→Rian transpiler's inference can't recover (the
  public-API boundary above all; ADR-0034 declare-public). A native Rian declaration,
  so there's no Elixir→Rian translation guesswork.

  Used as a registered, **persisted** module attribute so it (a) compiles cleanly under
  `--warnings-as-errors` — a bare `@rian_sig` would warn "set but never used" — and (b) is
  stored in the `.beam`, so tooling can read it from a compiled module without the source:

      defmodule Rian.IR.Func do
        use Rian.Ann

        @rian_sig \"\"\"
        struct Func(name String, params Vec(Param), ret String,
                    clauses Vec(Clause), pub? Bool, tvars Vec(String))
        \"\"\"
        defstruct [...]

        @rian_sig "pub def arity(Func) Int53"
        def arity(f), do: length(f.params)
      end

  A heredoc handles the multi-line struct/type case natively. The value is any Rian
  `def` / `pub def` / `struct` / `type` declaration head. Read it with `from_source/1`
  (Elixir text) or `from_beam/1` (a loaded module or a `.beam` path).

  ## Two annotation layers (ADR-0081)

  `@rian_sig` and `@rian_host` are **Elixir-bridge** annotations: they live only in
  `lib/rian/*.ex` and describe *crossing into* Rian from the host language — the `@rian_*`
  prefix is the namespace. They are distinct from the **Rian-surface** annotations that live
  in `.rian` source and describe Rian semantics (`@external` per-target FFI bodies, ADR-0068;
  `@effects(host)` the host effect, ADR-0048). The bridge marker `@rian_host` *transpiles to*
  the surface effect `@effects(host)`; they intentionally never share a file.
  """

  @doc """
  Register `@rian_sig` as an accumulating, **persisted** attribute — so it compiles
  warning-free (a bare `@rian_sig` would warn "set but never used") and is stored in the
  `.beam`, readable by tooling without the source. `@rian_sig` is a *native Rian* annotation:
  the source of truth for a function/struct/type's type, read by the Elixir→Rian
  transpiler. No Elixir `@spec`/`@type` is generated from it — Rian is the type system.
  """
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :rian_sig, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :rian_host, accumulate: true, persist: true)
    end
  end

  @doc """
  Names of the `def`s tagged `@rian_host` — a **sanctioned exception boundary**
  (ADR-0035/0040): a function whose `try/rescue` converts a host-runtime or parser
  raise into a value (e.g. `Code.format_string!`, ad-hoc compile, file I/O, the
  parser's `{:error,_}` boundary). The construct gate (`Rian.Transpile.incompatible/1`)
  excludes these — they are honest non-portability, not a Rian-concept clash. The
  attribute tags the **next** `def`/`defp` in its block (like `@doc`).
  """
  # NB: no `@rian_sig` here — this module *defines* the annotation, so it cannot register the
  # accumulating attribute on itself (bootstrapping); a `@rian_sig` would be "set but never used".
  @spec host_funcs(String.t()) :: [String.t()]
  def host_funcs(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> host_from_ast(ast)
      _ -> []
    end
  end

  defp host_from_ast(ast) do
    {_, {_pending, names}} =
      Macro.prewalk(ast, {false, []}, fn
        {:@, _, [{:rian_host, _, _}]} = n, {_pending, acc} ->
          {n, {true, acc}}

        {df, _, [head | _]} = n, {true, acc} when df in [:def, :defp] ->
          {n, {false, [def_name(head) | acc]}}

        {df, _, _} = n, {_pending, acc} when df in [:def, :defp] ->
          {n, {false, acc}}

        n, state ->
          {n, state}
      end)

    names |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  # the bare function name of a `def` head (`name(args)` or `name(args) when g`).
  defp def_name({:when, _, [call | _]}), do: def_name(call)
  defp def_name({name, _, _}) when is_atom(name), do: to_string(name)
  defp def_name(_), do: nil

  @doc "Extract every `@rian_sig` annotation STRING from Elixir source (via its AST)."
  @spec from_source(String.t()) :: [String.t()]
  def from_source(source) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> from_ast(ast)
      _ -> []
    end
  end

  @doc """
  Extract every `@rian_sig` annotation STRING from an ALREADY-PARSED Elixir AST — no
  re-parse. The live-source path: the transpiler already holds the module AST, so it
  reads annotations from it rather than parsing the text a second time.
  """
  @spec from_ast(Macro.t()) :: [String.t()]
  def from_ast(ast), do: collect(ast)

  defp collect(ast) do
    {_, anns} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{:rian_sig, _, [str]}]} = node, acc when is_binary(str) -> {node, [str | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(anns)
  end

  @doc """
  Extract every `@rian_sig` annotation STRING from a compiled module's persisted attributes —
  a loaded module atom or a `.beam` file path. The roundtrip / no-source reader.
  """
  @spec from_beam(module() | String.t()) :: [String.t()]
  def from_beam(module) when is_atom(module) do
    # guard the reflective `__info__/1` with an explicit load check instead of
    # rescuing UndefinedFunctionError (ADR-0035: no exception control flow).
    if Code.ensure_loaded?(module) do
      module.__info__(:attributes) |> Keyword.get_values(:rian_sig) |> List.flatten()
    else
      []
    end
  end

  def from_beam(path) when is_binary(path) do
    # `:beam_lib.chunks/2` already reports failure as `{:error, …}`, caught by the
    # catch-all arm — no `rescue` needed.
    case :beam_lib.chunks(String.to_charlist(path), [:attributes]) do
      {:ok, {_mod, [{:attributes, attrs}]}} ->
        attrs |> Keyword.get_values(:rian_sig) |> List.flatten()

      _ ->
        []
    end
  end
end
