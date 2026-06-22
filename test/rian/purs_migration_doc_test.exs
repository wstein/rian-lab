defmodule Rian.PursMigrationDocTest do
  @moduledoc """
  Anti-drift guards for the PureScript-migration status docs (ADR-0084).

  The port is developed across parallel branches, and the hand-written status
  prose — `docs/purescript-migration.md`, the README ADR index, the ADR-0084
  header — kept drifting from the code it describes. Two recurring failures:

    * the **parity-record count** (a hand-transcribed snapshot, drifted 821 →
      896 across rounds), and
    * **"X is deferred / not wired" notes** that outlived the commit that landed
      X (`EStruct`, `check_binds`, `check_effects`, …).

  These tests pin the *machine-checkable* claims to the code, so a stale note
  fails `mix test` instead of rotting silently. They read source files only (no
  purerl / node), so they run in the default loop. Prose is not generated — only
  the facts a reader would trust are cross-checked.
  """
  use ExUnit.Case, async: true

  @migration "docs/purescript-migration.md"
  @fixtures "purs/test/fixtures/parity.fixtures"
  @core "purs/src/Rian/Core.purs"
  @check "purs/src/Rian/Check.purs"
  @ref_check "lib/rian/check.ex"
  @status_docs [@migration, "docs/README.md", "docs/adr/0084-purescript-port.md"]

  defp read(path), do: File.read!(Path.expand(path, File.cwd!()))

  # ── Guard A — the parity-record count must match the fixture file. ──────────
  # `parity.erl` reports its own `length(Results)` (the fixtures' non-blank line
  # count), so the prose figure is just a snapshot; pin it to the file.
  test "the migration doc's parity-record count matches the fixture file" do
    actual = @fixtures |> read() |> String.split("\n", trim: true) |> length()

    case Regex.run(~r/Total \*\*(\d+)\/(\d+)\*\* parity records/, read(@migration)) do
      [_, a, b] ->
        assert a == b,
               "#{@migration}: `Total **#{a}/#{b}**` is not N/N — both halves are one total."

        assert String.to_integer(a) == actual,
               "#{@migration} states #{a} parity records but #{@fixtures} has #{actual}. " <>
                 "Run `mix run purs/test/gen_fixtures.exs` and/or update the prose."

      _ ->
        flunk("no `Total **N/N** parity records` line found in #{@migration}")
    end
  end

  # ── Guard B — PS `check_program` wires every reference `check_func` check. ───
  # The count drifted (9 → 10 → 11 of 11) as checks landed without the doc
  # catching up. Pin the PS chain to the Elixir reference, and the doc to both.
  test "check_program wires every reference check_func check, and the doc says so" do
    ref_count = reference_chain() |> count(~r/check_\w+\(/)
    ps_count = read(@check) |> count(~r/\\_ -> check[A-Z]\w+/)

    assert ps_count == ref_count,
           "purs check_program wires #{ps_count} check_func checks but the reference runs #{ref_count}. " <>
             "Wire the missing check — or, if intentionally behind, the doc must say " <>
             "\"#{ps_count} of #{ref_count}\", not \"all\"."

    assert read(@migration) =~ ~r/all #{ref_count}\b/,
           "#{@migration} should state \"all #{ref_count}\" check_func checks (PS wires all #{ref_count})."
  end

  # ── Guard C — a deferral note must not outlive the port it described. ───────
  # The literal recurring failure: a "no `EStruct`" / "`check_binds` … not wired"
  # note survives the commit that landed it. A Core constructor PS Core defines
  # must not be called absent; a check `check_program` wires must not be called
  # deferred/not-wired.
  test "no status doc calls a Core constructor or wired check 'deferred' once it exists" do
    core = read(@core)

    core_ctors =
      ~r/(?:=|\|)\s*([EP][A-Z]\w+)/
      |> Regex.scan(core, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    wired_checks =
      ~r/\\_ -> (check[A-Z]\w+)/
      |> Regex.scan(read(@check), capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&snake/1)
      |> Enum.uniq()

    for path <- @status_docs do
      text = read(path)

      for ctor <- core_ctors do
        refute String.contains?(text, "no `#{ctor}`"),
               "#{path}: \"no `#{ctor}`\" is stale — PS Core defines `#{ctor}`. Drop the deferral note."
      end

      for chk <- wired_checks do
        stale? =
          text =~ ~r/`#{chk}`[^.\n]{0,90}(not wired|not yet|deferred|remains)/i or
            text =~ ~r/(not wired|not yet wired|deferred)[^.\n]{0,90}`#{chk}`/i

        refute stale?,
               "#{path}: `#{chk}` reads as deferred/not-wired, but check_program wires it. Update the note."
      end
    end
  end

  # the reference `check_func` chain: `with :ok <- check_unk … do: check_error_set`.
  defp reference_chain() do
    case Regex.run(~r/with :ok <- check_unk.*?do: check_error_set\([^\n]*\)/s, read(@ref_check)) do
      [chain] -> chain
      _ -> flunk("could not locate the check_func chain in #{@ref_check}")
    end
  end

  defp count(text, re), do: Regex.scan(re, text) |> length()

  defp snake(camel),
    do: camel |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2") |> String.downcase()
end
