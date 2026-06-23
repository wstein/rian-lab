# Drift-tax measurement (debate follow-up #3) — quantify the per-feature emitter cost.
#
# Premise (Samir, the multi-target debate): every feature is lowered once per emitter, so adding
# a target multiplies maintenance. The `__prim_*` intrinsic set is the cleanest case to measure
# because it is *already* a near-declarative table — one intrinsic, each emitter lowers it natively.
#
# This script counts, for the `__prim_*` feature:
#   • DISTINCT intrinsics,
#   • LOWERING SITES = (intrinsic, emitter) pairs actually hand-written across all emitters,
#   • TOUCH COUNT = emitter files a *new* intrinsic must edit,
# and contrasts that with a single declarative table (one row per intrinsic × target columns).
#
#   mix run scripts/measure_drift_tax.exs

emitters = [
  {"BEAM (Elixir)", "lib/rian/beam.ex"},
  {"Rust (Elixir)", "lib/rian/lower.ex"},
  {"JVM  (Elixir)", "lib/rian/jvm.ex"},
  {"JS   (Elixir)", "lib/rian/js.ex"},
  {"Rust (PureScript)", "purs/src/Rian/Lower/Rust.purs"},
  {"JVM  (PureScript)", "purs/src/Rian/JVM.purs"},
  {"JS   (PureScript)", "purs/src/Rian/JS.purs"}
]

prim_re = ~r/__prim_[a-z0-9_]+/

read = fn path ->
  case File.read(path) do
    {:ok, s} -> s
    _ -> ""
  end
end

# the set of intrinsics each emitter LOWERS (mentions in a non-comment line), per file.
per_emitter =
  for {label, path} <- emitters do
    prims =
      read.(path)
      |> String.split("\n")
      |> Enum.reject(&String.match?(&1, ~r/^\s*(#|--)/))
      |> Enum.flat_map(&Regex.scan(prim_re, &1))
      |> List.flatten()
      |> Enum.reject(&String.ends_with?(&1, "_"))
      |> Enum.uniq()
      |> MapSet.new()

    {label, prims}
  end

all_prims =
  per_emitter |> Enum.flat_map(fn {_, s} -> MapSet.to_list(s) end) |> Enum.uniq() |> Enum.sort()

n_prims = length(all_prims)
sites = per_emitter |> Enum.map(fn {_, s} -> MapSet.size(s) end) |> Enum.sum()
n_emitters = length(emitters)

IO.puts("\n══ drift-tax measurement — the `__prim_*` intrinsic feature ══\n")
IO.puts("  distinct intrinsics ......... #{n_prims}")
IO.puts("  emitters .................... #{n_emitters}  (4 Elixir + 3 PureScript)\n")

IO.puts("  lowering sites per emitter (intrinsics each one hand-lowers):")

for {label, prims} <- per_emitter do
  IO.puts("    #{String.pad_trailing(label, 20)} #{MapSet.size(prims)}")
end

IO.puts("\n  ── hand-written (today) ──")
IO.puts("  total lowering sites = Σ (intrinsic, emitter) pairs ...... #{sites}")
avg_touch = Float.round(sites / n_prims, 1)
IO.puts("  TOUCH COUNT to add intrinsic N+1 (avg emitters/intrinsic) #{avg_touch} files")
IO.puts("  worst-case touch (an intrinsic all emitters support) ..... #{n_emitters} files")

IO.puts("\n  ── one declarative table (prototype) ──")
IO.puts("  rows = intrinsics .......................................... #{n_prims}")
IO.puts("  cells = rows × target columns (the irreducible templates) .. ~#{sites}")
IO.puts("  TOUCH COUNT to add intrinsic N+1 ........................... 1 file (1 row)")

IO.puts("""

  ── reading ──
  • LINE COUNT is ~conserved: the per-target template IS the lowering logic (#{sites} cells
    either way). A table does not shrink the code; it RELOCATES it.
  • TOUCH COUNT is the real tax and it collapses: #{avg_touch}→1 files per new intrinsic
    (#{n_emitters}→1 worst case). That is the maintainability win — one place to add a
    feature across every target, vs editing each emitter and re-proving parity per file.
  • The trade is indirection: a generic table-driven emitter is harder to read than a
    direct `emit (ECall (EId "__prim_x")) = …` clause, and per-target escape hatches
    (precedence, ownership, the JS int-mode split) still need per-cell richness.
  • Verdict: worth prototyping for the *mechanical* prim/op families (high touch, low
    per-cell variance); NOT worth it for structurally-divergent nodes (patterns, captures,
    `with`) where each emitter's logic genuinely differs. Measure before generalizing.
""")
