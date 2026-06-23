# Generates purs/src/Rian/PreludeSrc.purs — the portable-prelude `.rian` sources bundled as
# PureScript string literals, so `Rian.Beam` can compile + load them with no source tree at runtime
# (the analogue of the Elixir reference's `@external_resource` + `File.read!`). Run after editing any
# `examples/rian/prelude_{int,str,dict,list}.rian`. Dual-checked by the `beam` parity stream.
names = ~w(int str dict list)

items =
  Enum.map_join(names, ",\n", fn n ->
    src = File.read!("examples/rian/prelude_#{n}.rian")

    if String.contains?(src, ~s(""")),
      do: raise("triple-quote in prelude_#{n}.rian — embedding breaks")

    "  -- examples/rian/prelude_#{n}.rian\n  \"\"\"\n" <> src <> "\"\"\""
  end)

out = """
-- | The portable-prelude `.rian` sources (`List`/`Dict`/`Str`/`Int`, ADR-0047 §2), **bundled** into
-- | the compiler so `Rian.Beam` can compile + load them as private `Elixir.Rian.Prelude.<Name>`
-- | modules with no source tree at runtime — the PureScript analogue of the Elixir reference's
-- | `@external_resource` + compile-time `File.read!` (`lib/rian/prelude.ex`). GENERATED from
-- | `examples/rian/prelude_{int,str,dict,list}.rian` by `scripts/gen_prelude_src.exs`; do not edit by
-- | hand — regenerate when a prelude source changes (a drift surfaces as a `beam`-stream miss).
module Rian.PreludeSrc
  ( sources
  ) where

-- | The four portable-prelude module sources (`Int`/`Str`/`Dict`/`List`).
sources :: Array String
sources =
  [
#{items}
  ]
"""

File.write!("purs/src/Rian/PreludeSrc.purs", out)
IO.puts("wrote purs/src/Rian/PreludeSrc.purs (#{byte_size(out)} bytes)")
