defmodule Rian.SigPolicyTest do
  use ExUnit.Case, async: true

  # Stability + safety rules (ADR-0081), enforced so they cannot rot:
  #
  #   1. COVERAGE — every public function defined in `lib/rian` carries a `@rian_sig`.
  #      Checked per distinct `def` HEAD (default-arg arities collapse — one head, one sig
  #      covering its `required..total` arity range), so it is strict (a wrong arity, like
  #      `status_markdown() ` for `status_markdown(stages)`, is caught) without forcing a
  #      noisy sig per auto-generated default arity.
  #
  #   2. SOUNDNESS — every `@rian_sig` must AGREE with the transpiler's own inference for the
  #      same function: a concrete declared type that provably conflicts with a concrete
  #      inferred type is a lying signature (a silent miscompile to Rust et al.). This is the
  #      Rust-like "signature checked against the implementation" property `rustc` enforces.
  #
  # Scope: modules whose SOURCE is under `lib/rian/` (not `dev/` tools, not Mix tasks).
  # Exclusions are structural: generated functions (`__struct__`, `defexception` callbacks,
  # `child_spec`, …) are not `def`s in source, so a source-based head scan never sees them;
  # `@behaviour` callbacks (OTP/Kino) are excluded via `behaviour_info/1`.

  defp lib_rian_modules do
    Application.spec(:rian_lab, :modules)
    |> Enum.filter(fn mod ->
      source = mod.module_info(:compile)[:source]

      String.starts_with?(Atom.to_string(mod), "Elixir.Rian.") and
        is_list(source) and String.contains?(to_string(source), "/lib/rian/")
    end)
  end

  defp source_of(mod), do: mod.module_info(:compile)[:source] |> to_string()

  # public `def` heads of THIS module (a file can hold several modules — e.g. `Rian.Repl`
  # and a nested `Rian.Repl.Session` — so defs are attributed to their enclosing module),
  # each `{name, required_arity, total_arity}`, deduped.
  defp def_heads(mod) do
    with {:ok, src} <- File.read(source_of(mod)),
         {:ok, ast} <- Code.string_to_quoted(src) do
      collect_module_defs(ast, [], %{})
      |> Map.get(Atom.to_string(mod), [])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp collect_module_defs({:defmodule, _, [aliases, [do: body]]}, prefix, acc) do
    collect_module_defs(body, prefix ++ alias_parts(aliases), acc)
  end

  defp collect_module_defs({:__block__, _, stmts}, prefix, acc),
    do: Enum.reduce(stmts, acc, &collect_module_defs(&1, prefix, &2))

  defp collect_module_defs({:def, _, [head | _]}, prefix, acc) when prefix != [] do
    key = "Elixir." <> Enum.join(prefix, ".")
    Map.update(acc, key, [head_arity(head)], &[head_arity(head) | &1])
  end

  defp collect_module_defs(_node, _prefix, acc), do: acc

  defp alias_parts({:__aliases__, _, parts}), do: Enum.map(parts, &to_string/1)
  defp alias_parts(_), do: []

  defp head_arity({:when, _, [call | _]}), do: head_arity(call)

  defp head_arity({name, _, args}) when is_atom(name) and is_list(args) do
    total = length(args)
    defaults = Enum.count(args, &match?({:\\, _, _}, &1))
    {to_string(name), total - defaults, total}
  end

  defp head_arity({name, _, _}) when is_atom(name), do: {to_string(name), 0, 0}
  defp head_arity(_), do: nil

  defp behaviour_callbacks(mod) do
    mod.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.flat_map(fn b ->
      if Code.ensure_loaded?(b) and function_exported?(b, :behaviour_info, 1),
        do: b.behaviour_info(:callbacks),
        else: []
    end)
    |> MapSet.new()
  end

  # {name, arity} declared by a module's `@rian_sig` def annotations (struct/type sigs add none).
  defp sig_arities(mod) do
    mod
    |> Rian.Ann.from_beam()
    |> Enum.map(fn s ->
      case Rian.Decl.parse_result(s <> " := nil") do
        {:ok, %{funcs: [f | _]}} -> {to_string(f.name), length(f.params)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  test "every public function in lib/rian declares a @rian_sig (coverage, per def head)" do
    missing =
      Enum.flat_map(lib_rian_modules(), fn mod ->
        sigs = sig_arities(mod)
        callbacks = behaviour_callbacks(mod)

        mod
        |> def_heads()
        |> Enum.reject(fn {name, _req, total} ->
          MapSet.member?(callbacks, {String.to_atom(name), total})
        end)
        |> Enum.reject(fn {name, req, total} ->
          Enum.any?(req..total, &MapSet.member?(sigs, {name, &1}))
        end)
        |> Enum.map(fn {name, _req, total} -> "#{inspect(mod)}.#{name}/#{total}" end)
      end)

    assert missing == [],
           "public functions in lib/rian missing a @rian_sig:\n  " <> Enum.join(missing, "\n  ")
  end

  # `_Unk` is a TRANSIENT placeholder ("type still to be defined"), not `any` (ADR-0034). This
  # ratchet enforces "drive it to zero": the count may only DROP. New `_Unk` fails the gate —
  # type it concretely, or write `Any` if the value is genuinely dynamic. When you reduce it,
  # lower @unk_baseline to lock the gain (same discipline as priv/transpile_check_baseline.txt).
  @unk_baseline 271

  defp unk_count do
    lib_rian_modules()
    |> Enum.flat_map(&Rian.Ann.from_beam/1)
    |> Enum.map(fn s -> length(String.split(s, "_Unk")) - 1 end)
    |> Enum.sum()
  end

  test "`_Unk` placeholders only ratchet DOWN (ADR-0034)" do
    count = unk_count()

    assert count <= @unk_baseline,
           "#{count - @unk_baseline} new `_Unk` placeholder(s) introduced (#{count} > " <>
             "#{@unk_baseline}). `_Unk` is transient — give it a concrete type, or `Any` if it " <>
             "genuinely accepts any value."

    assert count == @unk_baseline,
           "`_Unk` dropped to #{count} (good) — lower @unk_baseline to #{count} to lock the gain."
  end

  # ctor → sum-type map from every `@rian_sig "type X := A | B | …"` across lib/rian, so the
  # soundness check is subtype-aware (a variant inferred where its sum is declared is fine).
  defp ctor_to_sum do
    lib_rian_modules()
    |> Enum.flat_map(&Rian.Ann.from_beam/1)
    |> Enum.flat_map(fn s ->
      case Regex.run(~r/^\s*type\s+(\w+)\s*:=\s*(.+)$/s, s) do
        [_, sum, rhs] ->
          rhs
          |> String.split("|")
          |> Enum.map(&(&1 |> String.trim() |> String.split("(") |> hd() |> String.trim()))
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&{&1, sum})

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  test "every @rian_sig agrees with the transpiler's inference (soundness, no lying sigs)" do
    cts = ctor_to_sum()

    conflicts =
      lib_rian_modules()
      |> Enum.map(&source_of/1)
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, src} -> Rian.Transpile.verify_sigs(src, cts)
          _ -> []
        end
      end)

    assert conflicts == [],
           "@rian_sig annotations that provably conflict with inference:\n  " <>
             Enum.join(conflicts, "\n  ")
  end
end
