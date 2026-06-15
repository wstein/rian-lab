defmodule Rian.ComposeBenchTest do
  # async: false — builds the Rian compiler twice (gen1, gen2) and times it.
  use ExUnit.Case, async: false

  # PERFORMANCE TRACKING (not a correctness gate) — excluded from the default loop
  # AND `mix test.all` (see test/test_helper.exs). Run on demand:
  #
  #   mix test --include bench test/rian/compose_bench_test.exs
  #
  # Prints compile-time for the Rian-written compiler in two generations (v1 =
  # Elixir-host-compiled, v2 = self-built) against the Elixir reference `Rian.Beam`.
  # Since gen1 and gen2 emit bit-identical `.beam` (selfhost_v1_v2_fixpoint_test),
  # v1 and v2 are the SAME bytecode — so their timings must match (a performance
  # fixed point). No timing ASSERTIONS (wall-clock is noisy); the only assertion is
  # that v1 and v2 produce identical output.

  @moduletag :bench

  alias Rian.Beam

  @lexer File.read!("compiler/lexer_v2.rian")
  @decl File.read!("compiler/decl.rian")
  @beam File.read!("compiler/beam.rian")
  @driver File.read!("compiler/compose_real_sum.rian")
  @cap File.read!("compiler/cap.rian")

  @iters 15

  defp load_forms(name, forms) do
    {:ok, m, bin} = :compile.forms(forms, [:deterministic, :return_errors])
    {:module, ^m} = :code.load_binary(name, ~c"nofile", bin)
    m
  end

  defp ms(fun, iters) do
    {us, _} = :timer.tc(fn -> for _ <- 1..iters, do: fun.() end)
    Float.round(us / 1000 / iters, 2)
  end

  setup_all do
    # gen0 — the compiler compiled by the Elixir host.
    {:ok, _} = Beam.load(@lexer, :"Elixir.LexerV2")
    {:ok, _} = Beam.load(@decl, :"Elixir.Decl")
    {:ok, _} = Beam.load(@beam, :"Elixir.Beam")

    {:ok, _} =
      Beam.load(File.read!("compiler/exhaust.rian"), :"Elixir.Exhaust")

    {:ok, _} = Beam.load(File.read!("compiler/cap.rian"), :"Elixir.Cap")
    {:ok, gen0} = Beam.load(@driver, :rian_bench_gen0)

    # gen1 — gen0 compiles the compiler's own sources; load them as the live compiler.
    load_forms(:"Elixir.LexerV2", gen0.compile_module(@lexer, :"Elixir.LexerV2"))
    load_forms(:"Elixir.Decl", gen0.compile_module(@decl, :"Elixir.Decl"))
    load_forms(:"Elixir.Beam", gen0.compile_module(@beam, :"Elixir.Beam"))
    g1 = load_forms(:RianBenchV1, gen0.compile_module(@driver, :RianBenchV1))

    # gen2 — the self-built compiler.
    g2 = load_forms(:RianBenchV2, g1.compile_module(@driver, :RianBenchV2))

    {:ok, g1: g1, g2: g2}
  end

  test "v1 vs v2 vs Rian.Beam compile-time (printed for tracking)", %{g1: g1, g2: g2} do
    workloads = [{"selfhost_decl (~700 loc)", @decl}, {"selfhost_cap (~110 loc)", @cap}]

    IO.puts("\n=== Rian compiler compile-time — v1 (host-built) vs v2 (self-built) ===")

    IO.puts(
      "    (#{@iters} iters each; gen1/gen2 emit bit-identical .beam → v1≡v2 by construction)\n"
    )

    IO.puts(
      String.pad_trailing("workload", 26) <>
        String.pad_trailing("v1 compile_module", 19) <>
        String.pad_trailing("v2 compile_module", 19) <>
        String.pad_trailing("v1 build/2 (+load)", 20) <>
        "Rian.Beam.load (+check)"
    )

    for {label, src} <- workloads do
      t_v1 = ms(fn -> g1.compile_module(src, :Bench) end, @iters)
      t_v2 = ms(fn -> g2.compile_module(src, :Bench) end, @iters)
      t_build = ms(fn -> g1.build(src, :"BB_#{System.unique_integer([:positive])}") end, @iters)
      t_ref = ms(fn -> Beam.load(src, :"RB_#{System.unique_integer([:positive])}") end, @iters)

      IO.puts(
        String.pad_trailing(label, 26) <>
          String.pad_trailing("#{t_v1} ms", 19) <>
          String.pad_trailing("#{t_v2} ms", 19) <>
          String.pad_trailing("#{t_build} ms", 20) <>
          "#{t_ref} ms"
      )

      # the only hard assertion: v1 and v2 are the SAME compiler (bit-identical output).
      assert g1.compile_module(src, :Bench) == g2.compile_module(src, :Bench),
             "v1 and v2 diverged on #{label} — not a fixed point"
    end

    IO.puts("")
  end
end
