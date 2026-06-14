defmodule Rian.ExhaustFixpointTest do
  # async: false — loads a real module into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Exhaustiveness}

  # Self-hosting fixpoint (ADR-0063) for the **exhaustiveness gate**: a
  # Rian-written exhaustiveness verdict (examples/rian/selfhost_exhaust.rian),
  # compiled to real `.beam`, diffed against the reference `Rian.Exhaustiveness`.
  #
  # The diff is against the real Maranget usefulness check: a single-column match
  # over signature `sig` is exhaustive iff a wildcard query is NOT useful w.r.t.
  # the pattern matrix — `not Exhaustiveness.useful?(rows, [:wild], env)`. The
  # Rian port must agree with that on every corpus case.
  #
  # Slice: single-column matches over a finite sum of nullary constructors. The
  # remaining vocabulary (ctors with args, multi-column, list/literal/range
  # patterns, redundancy) is the `:partial` tail (ADR-0063).

  setup_all do
    {:ok, mod} =
      Beam.load(File.read!("examples/rian/selfhost_exhaust.rian"), :rian_exhaust_fixpoint)

    {:ok, mod: mod}
  end

  # ctor name string -> the reference's ctor id (an atom).
  defp cid(name), do: name |> String.downcase() |> String.to_atom()

  # the reference verdict via the real Maranget useful?/3.
  defp ref_exhaustive(sig, items) do
    env = Exhaustiveness.add_type(Exhaustiveness.base_env(), "T", Enum.map(sig, &{cid(&1), 0}))

    rows =
      Enum.map(items, fn
        :wild -> [:wild]
        {:ctor, name} -> [{:ctor, cid(name), []}]
      end)

    not Exhaustiveness.useful?(rows, [:wild], env)
  end

  # the port verdict: inject items into the Pat sum (PWild / PCtor(name)).
  defp port_exhaustive(mod, sig, items) do
    pats =
      Enum.map(items, fn
        :wild -> :p_wild
        {:ctor, name} -> {:p_ctor, name}
      end)

    mod.exhaustive(pats, sig)
  end

  @sig ["Red", "Green", "Blue"]

  # {signature, column items}
  @corpus [
    {@sig, [{:ctor, "Red"}, {:ctor, "Green"}, {:ctor, "Blue"}]},
    {@sig, [{:ctor, "Red"}, {:ctor, "Green"}]},
    {@sig, [{:ctor, "Red"}]},
    {@sig, []},
    {@sig, [:wild]},
    {@sig, [{:ctor, "Red"}, :wild]},
    {@sig, [{:ctor, "Red"}, {:ctor, "Green"}, {:ctor, "Blue"}, {:ctor, "Red"}]},
    {["On", "Off"], [{:ctor, "On"}, {:ctor, "Off"}]},
    {["On", "Off"], [{:ctor, "On"}]},
    {["Only"], [{:ctor, "Only"}]},
    {["Only"], []}
  ]

  describe "self-hosting exhaustiveness fixpoint — Rian verdict vs Maranget useful?/3" do
    test "the Rian verdict agrees with Rian.Exhaustiveness on every case", %{mod: mod} do
      for {sig, items} <- @corpus do
        assert port_exhaustive(mod, sig, items) == ref_exhaustive(sig, items),
               "diverged on sig=#{inspect(sig)} items=#{inspect(items)}"
      end
    end
  end

  describe "teeth — the verdict genuinely detects gaps (not vacuously true)" do
    test "a missing constructor is reported non-exhaustive", %{mod: mod} do
      refute port_exhaustive(mod, @sig, [{:ctor, "Red"}, {:ctor, "Green"}])
      # ...and the reference agrees this is the real gap.
      refute ref_exhaustive(@sig, [{:ctor, "Red"}, {:ctor, "Green"}])
    end

    test "a wildcard makes any column exhaustive", %{mod: mod} do
      assert port_exhaustive(mod, @sig, [:wild])
      assert port_exhaustive(mod, @sig, [{:ctor, "Red"}, :wild])
    end

    test "covering all constructors is exhaustive without a wildcard", %{mod: mod} do
      assert port_exhaustive(mod, @sig, [{:ctor, "Red"}, {:ctor, "Green"}, {:ctor, "Blue"}])
    end

    test "the verdict discriminates complete from incomplete columns", %{mod: mod} do
      refute port_exhaustive(mod, @sig, [{:ctor, "Red"}]) ==
               port_exhaustive(mod, @sig, [{:ctor, "Red"}, {:ctor, "Green"}, {:ctor, "Blue"}])
    end
  end
end
