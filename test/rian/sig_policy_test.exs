defmodule Rian.SigPolicyTest do
  use ExUnit.Case, async: true

  # Stability rule (ADR-0081): **every public function defined in `lib/rian` carries a
  # `@rian_sig`** — the authoritative native-Rian signature. `@spec` is not a substitute
  # (it is documentary and Elixir-shaped); `@rian_sig` is the stable contract the
  # Elixir→Rian transpiler reads, so a public function without one would regenerate with
  # `_Unk` holes. This gate makes the rule self-enforcing instead of a convention that rots.
  #
  # Scope + exclusions are deliberate:
  #   * scoped to modules whose SOURCE is under `lib/rian/` (not `dev/` tools, not Mix tasks);
  #   * generated/reflection functions (`__struct__`, `__info__`, `module_info`, `child_spec`,
  #     `__*__`) and `defexception` callbacks (`exception/1`, `message/1`) are not Rian functions;
  #   * `@behaviour` callbacks (OTP `Application`, Kino `SmartCell`, …) are host-framework
  #     integration, exempt from the Rian-signature rule.

  @generated [:__struct__, :__info__, :child_spec, :module_info, :exception, :message]

  defp lib_rian?(mod) do
    source = mod.module_info(:compile)[:source]
    is_list(source) and String.contains?(to_string(source), "/lib/rian/")
  end

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

  # the `def` names declared by a module's `@rian_sig` annotations (struct/type sigs have no
  # `def`, so they contribute nothing — exactly right).
  defp sig_def_names(mod) do
    mod
    |> Rian.Ann.from_beam()
    |> Enum.flat_map(fn s ->
      Regex.scan(~r/\bdef\s+([a-z_][a-zA-Z0-9_?!]*)/, s) |> Enum.map(fn [_, n] -> n end)
    end)
    |> MapSet.new()
  end

  defp lib_rian_modules do
    Application.spec(:rian_lab, :modules)
    |> Enum.filter(&(String.starts_with?(Atom.to_string(&1), "Elixir.Rian.") and lib_rian?(&1)))
  end

  test "every public function in lib/rian declares a @rian_sig (ADR-0081 stability rule)" do
    missing =
      Enum.flat_map(lib_rian_modules(), fn mod ->
        callbacks = behaviour_callbacks(mod)
        sigs = sig_def_names(mod)

        mod.__info__(:functions)
        |> Enum.reject(fn {name, _ar} ->
          name in @generated or String.starts_with?(Atom.to_string(name), "__")
        end)
        |> Enum.reject(fn {name, ar} -> MapSet.member?(callbacks, {name, ar}) end)
        |> Enum.reject(fn {name, _ar} -> MapSet.member?(sigs, Atom.to_string(name)) end)
        |> Enum.map(fn {name, ar} -> "#{inspect(mod)}.#{name}/#{ar}" end)
      end)

    assert missing == [],
           "public functions in lib/rian missing a @rian_sig (add one, or `_Infer`/`_Unk` " <>
             "params + the return type):\n  " <> Enum.join(missing, "\n  ")
  end
end
