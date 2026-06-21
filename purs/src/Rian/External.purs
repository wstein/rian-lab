-- | Renders a parsed `@external` spec (ADR-0068) to a target host call — the neutral home
-- | shared by every emitter, so the backends don't reach into `Rian.Decl` for it. The
-- | PureScript port of `Rian.External.render` (lib/rian/external.ex), ADR-0084.
-- |
-- | NOT ported (File/Check/Beam-coupled, the build-time half): `resolve`/`resolve_one`/
-- | `has_beam_file_ref?`/`lower_beam` — they stat foreign files, check arity via `Rian.Check`,
-- | and bundle `.beam` via `Rian.Beam`; they belong to the Erlang-FFI boundary, not this leaf.
module Rian.External
  ( render
  , externalRenderSexpr
  ) where

import Prelude

import Data.Array (filter, null, sortWith)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Decl (parseToProg)
import Rian.IR (ExtSpec(..), Param)

-- | Render one `@external` spec against a function's `params`. A raw host-expression string
-- | is verbatim; a function reference (`Mod.fun` / `:erlang.fun`) becomes a positional host
-- | call; a foreign-file reference has no direct rendering (bundled by `rian build`).
-- @rian_sig pub def render(spec val _Unk, params val Vec(_Unk)) String
render :: ExtSpec -> Array Param -> String
render (ExtStr s) _ = s
render (ExtRef parts erlang) params =
  let path = (if erlang then ":" else "") <> joinWith "." parts in
  path <> "(" <> joinWith ", " (map _.name params) <> ")"
render (ExtFile path _) _ =
  unsafeCrashWith
    ( "foreign-file `@external(…, \"" <> path <> "\", …)` cannot be rendered directly — a `:ex` "
        <> "file-reference is bundled by `rian build`; other targets' bundling is not yet implemented"
    )

-- | Parity entry (`ext` stream): render every function's externals (sorted by target) against
-- | its own params, composing `Decl` (@external parse) with the rendering.
externalRenderSexpr :: String -> String
externalRenderSexpr src =
  joinWith "\n" (map renderFunc (filter (not <<< null <<< _.externals) (parseToProg src).funcs))
  where
  renderFunc f =
    joinWith " "
      (map (\(Tuple t spec) -> t <> "=" <> render spec f.params) (sortWith fst f.externals))
