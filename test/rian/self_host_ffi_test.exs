defmodule Rian.SelfHostFfiTest do
  @moduledoc """
  Machine-enforced `@selfhost_ffi` ledger (ADR-0063 §4 — "permitted, but counted").

  Every host-FFI crutch in the self-host sources must be listed in
  `Rian.SelfHost.ffi_ledger/0`. The actual crutches are extracted by `Rian.Reach`
  (the same `:ffi`/`:concurrency` classification the reach gate uses), so:

    * an **unlisted** crutch (new FFI added to a self-host source) fails the build, and
    * a **stale** ledger line (a crutch a P5 portability swap removed) fails too.

  Each portability swap must therefore delete *both* the call and its ledger entry —
  the count only goes down, visibly.
  """
  use ExUnit.Case, async: true

  alias Rian.SelfHost

  test "every self-host source's host FFI exactly matches the ledger (no unlisted, no stale)" do
    ledger = SelfHost.ffi_ledger()

    drift =
      for path <- SelfHost.selfhost_files() do
        base = Path.basename(path)
        actual = SelfHost.ffi_in_file(path)
        declared = Map.get(ledger, base, [])

        cond do
          actual == declared -> nil
          true -> {base, unlisted: actual -- declared, stale: declared -- actual}
        end
      end
      |> Enum.reject(&is_nil/1)

    assert drift == [],
           "self-host FFI ledger out of sync (update Rian.SelfHost.@ffi_ledger):\n" <>
             Enum.map_join(drift, "\n", &inspect/1)
  end

  test "the ledger has no entry for a file that is FFI-free (no phantom crutches)" do
    bases = MapSet.new(SelfHost.selfhost_files(), &Path.basename/1)

    for {file, _} <- SelfHost.ffi_ledger() do
      assert file in bases, "ledger names #{file}, which is not a self-host source"

      assert SelfHost.ffi_in_file(Path.join(["examples", "rian", file])) != [],
             "ledger lists FFI for #{file}, but it has none — remove the stale entry"
    end
  end

  test "the extractor actually detects host FFI (teeth — not vacuously empty)" do
    # a program with a real host FFI call must be reported; a portable one must not.
    ffi_src = "def f(xs Vec(Int53)) Int53 := :lists.sum(xs)"
    pure_src = "def f(a Int53, b Int53) Int53 := a + b"

    assert ":lists.sum" in ffi_from(ffi_src)
    assert ffi_from(pure_src) == []

    # and the ledger is genuinely populated (at least one counted crutch), so the
    # match in the test above is not the trivial [] == [] for every file.
    assert SelfHost.ffi_ledger() |> Map.values() |> List.flatten() != []
  end

  defp ffi_from(src) do
    src
    |> Rian.Decl.parse()
    |> Rian.Reach.analyze()
    |> Map.values()
    |> Enum.flat_map(& &1.blockers)
    |> Enum.filter(&(&1.kind in [:ffi, :concurrency]))
    |> Enum.map(& &1.construct)
    |> Enum.uniq()
  end
end
