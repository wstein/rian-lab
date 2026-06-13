# ADR-0064 spike — BEAM masking overhead for a portable fixed-width contract.
#
# Measures the self-host lexer's hot path (`acc*10 + d` over a digit lexeme) two
# ways: native BEAM integer arithmetic vs. fixed-width wrap (mask to signed-64 each
# op). Tomás's objection, quantified: per-op masking is ~15x native on the BEAM,
# which is *why* arbitrary-precision `Int` is the default and fixed-width is opt-in.
#
#   mix run bench/numeric_masking.exs
import Bitwise

defmodule NumericMaskingBench do
  # fold a short digit list (bounded, like a real numeric lexeme)
  def fold([], acc), do: acc
  def fold([d | t], acc), do: fold(t, acc * 10 + d)

  def wrap64(x) do
    m = band(x, 0xFFFFFFFFFFFFFFFF)
    if m >= 0x8000000000000000, do: m - 0x10000000000000000, else: m
  end

  def foldm([], acc), do: acc
  def foldm([d | t], acc), do: foldm(t, wrap64(acc * 10 + d))

  def nloop(0, _d, last), do: last
  def nloop(n, d, _last), do: nloop(n - 1, d, fold(d, 0))
  def mloop(0, _d, last), do: last
  def mloop(n, d, _last), do: mloop(n - 1, d, foldm(d, 0))
end

alias NumericMaskingBench, as: B
digits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2]
iters = 5_000_000
B.nloop(1000, digits, 0)
B.mloop(1000, digits, 0)
{tn, _} = :timer.tc(fn -> B.nloop(iters, digits, 0) end)
{tm, _} = :timer.tc(fn -> B.mloop(iters, digits, 0) end)

IO.puts("ADR-0064 numeric-masking spike (#{iters} lexemes of #{length(digits)} digits)")
IO.puts("  native (Int / bignum):        #{Float.round(tn / 1000, 1)} ms  ·  #{Float.round(tn * 1000 / iters, 1)} ns/lexeme")
IO.puts("  fixed-width wrap (masked):    #{Float.round(tm / 1000, 1)} ms  ·  #{Float.round(tm * 1000 / iters, 1)} ns/lexeme")
IO.puts("  BEAM masking overhead:        #{Float.round(tm / tn, 1)}x")
