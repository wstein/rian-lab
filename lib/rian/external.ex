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
      closed (ADR-0080 §7 c, never a silent stub). For the **BEAM** target,
      `lower_beam/2` then **bundles** it (ADR-0080 §7 b): it compiles the `.ffi.ex` and
      rewrites the `@external` to a module-reference, so the foreign module ships as a
      `.beam` beside the app and the call lowers via the existing reference path. The
      other targets' bundling (a JS `import`, a Rust `mod`, a JVM compile) is not yet
      built, so `render/2` still refuses a non-BEAM file-reference.
  """

  use Rian.Ann

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
  @rian_sig "pub def render(spec _Unk, params Vec(_Unk)) String"
  @spec render(spec(), [map()]) :: String.t()
  def render(spec, _params) when is_binary(spec), do: spec

  def render({:ref, parts, erlang?}, params) do
    path = if erlang?, do: ":" <> Enum.join(parts, "."), else: Enum.join(parts, ".")
    "#{path}(#{Enum.map_join(params, ", ", & &1.name)})"
  end

  def render({:file, path, _fun}, _params) do
    raise ArgumentError,
          "foreign-file `@external(…, \"#{path}\", …)` cannot be rendered directly — a `:ex` " <>
            "file-reference is bundled by `rian build` (`lower_beam/2`, which rewrites it to a " <>
            "module-reference, ADR-0080 §7 b); other targets' bundling is not yet implemented"
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
  @rian_sig "pub def resolve(prog Prog, src_dir String) _Unk"
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
    case File.read(full) do
      {:ok, content} ->
        case Code.string_to_quoted(content) do
          {:ok, ast} -> ast_defines?(ast, fun, arity)
          _ -> false
        end

      _ ->
        false
    end
  end

  # `fun` is the (string) name from the foreign `@external`; comparing head names as
  # strings avoids interning an arbitrary user-supplied name into the atom table.
  defp ast_defines?(ast, fun, arity) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:def, _, [head | _]} = node, acc -> {node, acc or head_arity(head) == {fun, arity}}
        node, acc -> {node, acc}
      end)

    found
  end

  # `{name, arity}` of a `def` head with the name as a **string** (to match `fun`):
  # `name(a, b)` → `{"name", 2}`, `name()`/`name` → 0, `name(a) when g` → unwrap first.
  defp head_arity({:when, _, [inner | _]}), do: head_arity(inner)

  defp head_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {to_string(name), length(args)}

  defp head_arity({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {to_string(name), 0}
  defp head_arity(_), do: :no

  @doc """
  True if any function in `prog` carries a BEAM (`:ex`) file-reference `@external` —
  i.e. the BEAM build must bundle a foreign `.ffi.ex` (see `lower_beam/2`). A program
  with only string/module-reference externals (or none) needs no bundling.
  """
  @rian_sig "pub def has_beam_file_ref?(prog Prog) Bool"
  @spec has_beam_file_ref?(map()) :: boolean()
  def has_beam_file_ref?(prog) do
    Enum.any?(all_funcs(prog), &match?({:file, _, _}, Map.get(externals(&1), :ex)))
  end

  @doc """
  Bundle every BEAM (`:ex`) file-reference in `prog` for the build (ADR-0080 §7 b):
  compile each referenced `.ffi.ex` and rewrite its `@external` to a module-reference
  `{:ref, parts, false}` that calls the foreign module's exported function — so the
  existing reference path emits `Mod.fun(args)` and the BEAM backend needs no new case.

  Returns `{:ok, lowered_prog, [{module, beam_binary}]}` — the binaries to write beside
  the app — or `{:error, message}` if a `.ffi.ex` will not compile or exports no module
  with the named function at the right arity (fail-closed, ADR-0041 §2). Non-`:ex`
  references are left untouched. The foreign modules are compiled (and thus loaded) here.
  """
  @rian_sig "pub def lower_beam(prog Prog, src_dir String) _Unk"
  @spec lower_beam(map(), Path.t()) :: {:ok, map(), [{module(), binary()}]} | {:error, String.t()}
  def lower_beam(prog, src_dir) do
    paths =
      for f <- all_funcs(prog),
          {:ex, {:file, path, _fun}} <- externals(f),
          uniq: true,
          do: path

    with {:ok, cache} <- compile_ffi(paths, src_dir) do
      rewrite_beam(prog, cache)
    end
  end

  defp externals(f), do: Map.get(f, :externals, %{})

  # each distinct `.ffi.ex` → its `[{module, binary}]`, compiled once.
  defp compile_ffi(paths, src_dir) do
    Enum.reduce_while(paths, {:ok, %{}}, fn path, {:ok, cache} ->
      case compile_ffi_file(Path.expand(path, src_dir), path) do
        {:ok, mods} -> {:cont, {:ok, Map.put(cache, path, mods)}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  # compiling authored foreign Elixir is a genuine FFI boundary — a malformed file
  # raises a `CompileError`, converted to an errors-as-value here (ADR-0035).
  @rian_host "FFI compile boundary: a foreign `.ffi.ex` CompileError becomes a Result"
  defp compile_ffi_file(full, path) do
    case File.read(full) do
      {:ok, content} ->
        {:ok, Code.compile_string(content, full)}

      {:error, reason} ->
        {:error, "foreign file `#{path}` could not be read: #{:file.format_error(reason)}"}
    end
  rescue
    e -> {:error, "foreign file `#{path}` failed to compile: #{Exception.message(e)}"}
  end

  defp rewrite_beam(prog, cache) do
    beams = cache |> Map.values() |> List.flatten() |> Enum.uniq_by(&elem(&1, 0))

    with {:ok, funcs} <- rewrite_funcs(Map.get(prog, :funcs, []), cache),
         {:ok, mods} <- rewrite_mods(Map.get(prog, :mods, []), cache) do
      {:ok, %{prog | funcs: funcs, mods: mods}, beams}
    end
  end

  defp rewrite_mods(mods, cache) do
    map_ok(mods, fn m ->
      with {:ok, fs} <- rewrite_funcs(m.funcs, cache), do: {:ok, %{m | funcs: fs}}
    end)
  end

  defp rewrite_funcs(funcs, cache), do: map_ok(funcs, &rewrite_func(&1, cache))

  defp rewrite_func(f, cache) do
    case Map.get(externals(f), :ex) do
      {:file, path, fun} ->
        case find_module(Map.get(cache, path), fun, length(f.params)) do
          {:ok, mod} ->
            ref = {:ref, Module.split(mod) ++ [fun], false}
            {:ok, %{f | externals: Map.put(f.externals, :ex, ref)}}

          :error ->
            {:error, "`#{f.name}`: no module in `#{path}` exports `#{fun}/#{length(f.params)}`"}
        end

      _ ->
        {:ok, f}
    end
  end

  defp find_module(nil, _fun, _arity), do: :error

  defp find_module(mods, fun, arity) do
    case Enum.find(mods, fn {m, _bin} -> exports?(m, fun, arity) end) do
      {m, _bin} -> {:ok, m}
      nil -> :error
    end
  end

  # does `mod` export `fun/arity`? Compares the function's *string* name against each
  # export — avoids interning unbounded input (`String.to_atom`) and the raise from
  # `String.to_existing_atom` (errors-as-values over exception flow, ADR-0035).
  defp exports?(mod, fun, arity) do
    Enum.any?(mod.__info__(:functions), fn {n, a} -> a == arity and Atom.to_string(n) == fun end)
  end

  # map a fallible transform over a list, short-circuiting on the first `{:error, _}`.
  defp map_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      e -> e
    end
  end
end
