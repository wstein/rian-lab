-- | The host-FFI boundary for BEAM reflection (ADR-0084), isolated in one tiny module so the rest
-- | of the port stays pure. Mirrors the reference's `Code.ensure_loaded?` + `function_exported?`,
-- | which `Check` uses to resolve an `@external` `Mod.fun`/`:erlang.fun` reference's arity
-- | (ADR-0068 / ADR-0041 §2, the no-silent-stub guarantee). BEAM-only by nature — it inspects
-- | loaded modules — so the function it backs (`check_external_refs`) is host-coupled, exactly as
-- | in the reference. FFI module: `src/Rian/HostRef.erl` (`rian_hostRef@foreign`).
module Rian.HostRef
  ( refExported
  ) where

-- | Does the host reference resolve at the given arity? `parts` is the dotted reference
-- | (`["erlang","length"]`), `erlang?` true = an Erlang `:mod.fun`, false = an Elixir `Mod.fun`.
-- | Returns `true` when it exports such a function OR when the module cannot be loaded
-- | (unverifiable → conservatively accepted, never a false error for a not-yet-loaded module);
-- | `false` ONLY when the module IS loaded but exports no such `fun/arity`.
foreign import refExported :: Array String -> Boolean -> Int -> Boolean
