-- | The portable prelude (ADR-0047 tier 1 / ADR-0041 module-resolution kind 3): types
-- | auto-available in every module on every target, with no user declaration. The
-- | PureScript port of `Rian.Prelude` (lib/rian/prelude.ex), ADR-0084.
-- |
-- | This ports the **flagship decision** — `Option(T) = Some(T) | None`, no `nil`
-- | (ADR-0047 §3): a sealed sum like any other (so `case` over it is exhaustiveness-
-- | checkable), but *built in* — the checker, the exhaustiveness env, and the lowering
-- | meta all know `Some`/`None` without a `type Option := …` in the source. `with_prelude`
-- | is what `Rian.Exhaustiveness.program_env` prepends so a `case` over `Option` is total.
-- |
-- | NOT ported (the BEAM/Reach-coupled function linkage, ADR-0047 §2): `module_names`,
-- | `defines?`, `atom`, `beams`, `load` — they bundle `examples/rian/prelude_*.rian` at
-- | compile time and compile them to private `Rian.Prelude.<Name>` `.beam` modules via
-- | `Rian.Beam` (unported), so they belong to the Erlang-FFI boundary, not this leaf.
module Rian.Prelude
  ( types
  , withPrelude
  , withPreludeSexpr
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.String.Common (joinWith)
import Rian.Decl (parseToProg, typeSexpr)
import Rian.IR (Type)

-- | The built-in prelude types (known everywhere, never re-emitted as user types).
-- @rian_sig pub def types() Vec(Type)
types :: Array Type
types =
  [ { name: "Option"
    , variants:
        [ { ctor: "Some", fields: [ { label: Nothing, ty: "T" } ] }
        , { ctor: "None", fields: [] }
        ]
    , pub: false
    , doc: Nothing
    }
  ]

-- | Prepend the prelude types to a program's user types (for env / meta / inference).
-- @rian_sig pub def withPrelude(types val Vec(Type)) Vec(Type)
withPrelude :: Array Type -> Array Type
withPrelude userTypes = types <> userTypes

-- | Parity entry (`prl` stream): prepend the prelude to a source's user types and serialize.
withPreludeSexpr :: String -> String
withPreludeSexpr src = joinWith "\n" (map typeSexpr (withPrelude (parseToProg src).types))
