defmodule Rian.External do
  @moduledoc """
  Lowering and resolution for `@external` FFI specs (ADR-0068) — the neutral home
  shared by every emitter (`Rian.Beam`/`Rian.JS`/`Rian.JVM`/`Rian.Lower`), so the
  backends don't reach into `Rian.Decl` (the parser) for a rendering helper.

  `Rian.Decl` *parses* an `@external` spec to one of three shapes; this module owns
  what happens to each afterwards:

    * a raw **host-expression string** (`@external(:ex, "…")`) — rendered verbatim;
    * a **module reference** `{:ref, parts, erlang?}` (`@external(:ex, Mod.fun)`) —
      rendered as a positional host call; its arity is resolved by `Rian.Check`;
    * a **file-reference** `{:file, path, fun}` (`@external(:js, "./codec.ffi.mjs",
      "encode")`, ADR-0068 §1b / ADR-0080 §7) — authored foreign code beside the
      source. `resolve/2` verifies the file exists (and, for a `.ex`/`.exs` file, that
      it exports the named function at the right arity) at **build time**, failing
      closed (ADR-0080 §7 c, never a silent stub). Its **bundling/emission** — compiling
      a `.ffi.ex` into the app, emitting a JS `import`, etc. (ADR-0080 §7 b) — is the
      next build-system phase, so `render/2` refuses a file-reference rather than emit a
      call to a function the output does not yet carry.
  """

  @typedoc """
  An `@external` spec (ADR-0068): a raw host-expression string, a parsed function
  reference `{:ref, name_parts, erlang?}` (`:erlang.fun` → `erlang? = true`), or a
  file-reference `{:file, path, fun}` to authored foreign code beside the source
  (ADR-0068 §1b / ADR-0080 §7).
  """
  @type spec :: String.t() | {:ref, [String.t()], boolean()} | {:file, String.t(), String.t()}

  @doc """
  Render an `@external` spec to a host-call string for an emitter (ADR-0068): a raw
  string passes through; a reference `{:ref, parts, erlang?}` becomes a positional call
  `path(p1, p2, …)` over the function's params. So a reference lowers via the existing
  string-splicing path in every emitter — one helper, no per-backend reference logic.

  A **file-reference** `{:file, …}` has no rendering yet: its foreign code must first be
  bundled into the target output (ADR-0080 §7 b). Until that phase lands, rendering one
  raises rather than emit a call to an unbundled function (fail-closed, ADR-0041 §2).

  **Calling convention (the author's contract):** the referenced function must take the
  **same parameters in the same order** as the Rian `def` — the args are passed
  **positionally**. `Rian.Check`'s resolution verifies the *arity* matches, but **not**
  the order/types; a target that reorders or retypes its params will match arity yet be
  miswired silently. (Same trust boundary as any FFI — ADR-0068: this is FFI, not magic.)
  """
  @spec render(spec(), [map()]) :: String.t()
  def render(spec, _params) when is_binary(spec), do: spec

  def render({:ref, parts, erlang?}, params) do
    path = if erlang?, do: ":" <> Enum.join(parts, "."), else: Enum.join(parts, ".")
    "#{path}(#{Enum.map_join(params, ", ", & &1.name)})"
  end

  def render({:file, path, _fun}, _params) do
    raise ArgumentError,
          "foreign-file `@external(…, \"#{path}\", …)` cannot be emitted yet — file-reference " <>
            "bundling is the next build-system phase (ADR-0080 §7 b); the reference resolves " <>
            "(`Rian.External.resolve/2`) but the output does not yet carry its code"
  end

  @doc """
  Resolve every **file-reference** `@external` in a parsed program against `src_dir`
  (the directory of the source file), ADR-0080 §7 a/c. For each `{:file, path, fun}`:

    * the file must exist (resolved relative to `src_dir`), else fail closed;
    * a `.ex`/`.exs` file must define `fun` at the Rian function's arity — checked from
      its AST, so a typo or arity skew is a build error, not a runtime surprise;
    * other targets (`.mjs`/`.rs`/`.kt`) are existence-checked only — their export
      verification needs a target-aware parser and lands with each backend's bundler.

  Returns `:ok` or `{:error, message}` (errors-as-values, ADR-0035). A program with no
  file-references resolves trivially.
  """
  @spec resolve(map(), Path.t()) :: :ok | {:error, String.t()}
  def resolve(prog, src_dir) do
    refs =
      for f <- all_funcs(prog),
          {target, {:file, path, fun}} <- Map.get(f, :externals, %{}),
          do: {f.name, length(f.params), target, path, fun}

    Enum.reduce_while(refs, :ok, fn {name, arity, target, path, fun}, :ok ->
      case resolve_one(src_dir, path, fun, arity) do
        :ok -> {:cont, :ok}
        {:error, why} -> {:halt, {:error, "`#{name}`: `@external(:#{target}, …)` #{why}"}}
      end
    end)
  end

  defp all_funcs(prog) do
    Map.get(prog, :funcs, []) ++ for(m <- Map.get(prog, :mods, []), f <- m.funcs, do: f)
  end

  defp resolve_one(src_dir, path, fun, arity) do
    full = Path.expand(path, src_dir)

    cond do
      not File.exists?(full) ->
        {:error, "references foreign file `#{path}` which does not exist (looked in #{full})"}

      Path.extname(full) in [".ex", ".exs"] and not ex_defines?(full, fun, arity) ->
        {:error, "references `#{fun}/#{arity}` in `#{path}`, but that file defines no such `def`"}

      true ->
        :ok
    end
  end

  # Does an Elixir source file define `def fun(<arity args>)` (any clause)? Reads the
  # file's AST and scans for a public `def` head of the name and arity, unwrapping a
  # `when` guard. `defp` does not count — a foreign export must be public.
  defp ex_defines?(full, fun, arity) do
    name = String.to_atom(fun)

    case File.read(full) do
      {:ok, content} ->
        case Code.string_to_quoted(content) do
          {:ok, ast} -> ast_defines?(ast, name, arity)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp ast_defines?(ast, name, arity) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:def, _, [head | _]} = node, acc -> {node, acc or head_arity(head) == {name, arity}}
        node, acc -> {node, acc}
      end)

    found
  end

  # `{name, arity}` of a `def` head: `name(a, b)` → `{:name, 2}`, `name()`/`name` → 0,
  # `name(a) when g` → unwrap the guard first.
  defp head_arity({:when, _, [inner | _]}), do: head_arity(inner)
  defp head_arity({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp head_arity({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, 0}
  defp head_arity(_), do: :no
end
