-- | Protocol/impl **coherence** (ADR-0061 §5) — the PureScript port of `Rian.Coherence`
-- | (lib/rian/coherence.ex), ADR-0084. A pure pass over the parsed IR returning the
-- | structured violations: unknown protocol, method-set / method-arity mismatch, missing
-- | runtime discriminator, duplicate `(proto, type)`, and shared runtime discriminator
-- | (`Int64`+`Char`, only on the runtime-dispatch targets `:ex`/`:js`).
-- |
-- | Parity unit (the `coh` stream): `violations` compares the *rule* and the offending
-- | `(proto, type)` — the portable essence — not the human message text (an Elixir
-- | presentation concern). The runtime discriminator is keyed by an equivalence class
-- | (`int`/`bool`/`bin`/`float`/`sum:<name>`/`struct:<name>`) rather than the BEAM guard
-- | string: two types overlap iff their classes match, which is the same outcome the
-- | reference's guard-string equality produces for any non-pathological program.
module Rian.Coherence
  ( Violation
  , Registry
  , violations
  , violationsSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (all, elem)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..)) as Str
import Data.String as Str
import Data.String.CodePoints as CP
import Data.String.Common (joinWith)
import Rian.Decl (parseToProg)
import Rian.IR (ImplDecl, Protocol, Prog)
import Rian.TypeStr (splitTopCommas)

-- | A coherence violation: the `rule` and the offending `(proto, ty)`. The message is
-- | omitted — the gate's message text is an Elixir-presentation concern, not portable.
type Violation = { rule :: String, proto :: String, ty :: String }

-- | The dispatchable types in scope, by name: sum types and struct names.
type Registry = { sums :: Array String, structs :: Array String }

-- | The coherence violations among `impls`, in check order (empty = coherent). Mirrors
-- | `Rian.Coherence.violations/4`: every impl's per-impl rules, then the cross-impl
-- | duplicate / shared-discriminator rules. `targets` is the scope's `@targets`
-- | (`Nothing` = unannotated = all targets, so the runtime-discriminator rule applies).
violations :: Array Protocol -> Array ImplDecl -> Registry -> Maybe (Array String) -> Array Violation
violations protocols impls reg targets =
  Array.concatMap (implViolations protocols reg) impls <> overlapViolations impls reg targets

-- ── per-impl rules ──────────────────────────────────────────────────────────
implViolations :: Array Protocol -> Registry -> ImplDecl -> Array Violation
implViolations protocols reg impl =
  case Array.find (\p -> p.name == impl.proto) protocols of
    Nothing -> [ v "unknown_protocol" impl.proto impl.ty ]
    Just proto ->
      methodSetViolations proto impl
        <> arityViolations proto impl
        <> discriminatorViolations reg impl

methodSetViolations :: Protocol -> ImplDecl -> Array Violation
methodSetViolations proto impl =
  let
    want = Array.sort (Array.nub (map _.name proto.methods))
    got = Array.sort (Array.nub (map _.name impl.methods))
  in
    if want == got then [] else [ v "method_set" impl.proto impl.ty ]

-- each impl method the protocol *declares* must take the same number of parameters;
-- a method not in the protocol is a method-set violation, reported separately.
arityViolations :: Protocol -> ImplDecl -> Array Violation
arityViolations proto impl =
  Array.concatMap check impl.methods
  where
  check m =
    case Array.find (\s -> s.name == m.name) proto.methods of
      Nothing -> []
      Just sig ->
        if Array.length (splitTopCommas m.params) == Array.length (splitTopCommas sig.params) then []
        else [ v "method_arity" impl.proto impl.ty ]

discriminatorViolations :: Registry -> ImplDecl -> Array Violation
discriminatorViolations reg impl =
  case classify reg impl.ty of
    Just _ -> []
    Nothing -> [ v "discriminator" impl.proto impl.ty ]

-- ── cross-impl rules: one per (proto,type); no shared runtime discriminator ──
overlapViolations :: Array ImplDecl -> Registry -> Maybe (Array String) -> Array Violation
overlapViolations impls reg targets =
  (Array.foldl step { vs: [], keys: [], guards: [] } impls).vs
  where
  disc = runtimeDispatchTarget targets

  step acc impl =
    let
      key = impl.proto <> "/" <> impl.ty
    in
      if key `elem` acc.keys then
        -- a duplicate `(proto, type)`: reported once, the same type — not two
        -- different types sharing a guard, so the discriminator test is skipped.
        acc { vs = acc.vs <> [ v "duplicate" impl.proto impl.ty ] }
      else case classify reg impl.ty of
        Just g ->
          let
            gkey = impl.proto <> "/" <> g
            amb =
              if disc && gkey `elem` acc.guards then [ v "shared_discriminator" impl.proto impl.ty ]
              else []
          in
            { vs: acc.vs <> amb, keys: [ key ] <> acc.keys, guards: [ gkey ] <> acc.guards }
        Nothing ->
          { vs: acc.vs, keys: [ key ] <> acc.keys, guards: acc.guards }

-- the runtime-discriminator rule applies when the scope can reach a runtime dispatch
-- target (`:ex`/`:js`); an unannotated scope (`Nothing`) reaches all.
runtimeDispatchTarget :: Maybe (Array String) -> Boolean
runtimeDispatchTarget Nothing = true
runtimeDispatchTarget (Just ts) = elem "ex" ts || elem "js" ts

-- ── type → runtime discriminator (equivalence class) ────────────────────────
-- two types overlap iff they classify equal; `Nothing` = no discriminator.
classify :: Registry -> String -> Maybe String
classify reg ty
  | ty == "Bool" = Just "bool"
  | ty == "String" = Just "bin"
  | ty == "Char" = Just "int"
  | isIntName ty = Just "int"
  | isFloatName ty = Just "float"
  | ty `elem` reg.sums = Just ("sum:" <> ty)
  | ty `elem` reg.structs = Just ("struct:" <> ty)
  | otherwise = Nothing

-- `^U?Int\d*$` — an optional `U`, `Int`, then only digits (possibly none).
isIntName :: String -> Boolean
isIntName s = digitsAfter "Int" (dropU s)
  where
  dropU x = fromMaybe x (Str.stripPrefix (Str.Pattern "U") x)

-- `^Float\d*$`.
isFloatName :: String -> Boolean
isFloatName = digitsAfter "Float"

digitsAfter :: String -> String -> Boolean
digitsAfter prefix s =
  case Str.stripPrefix (Str.Pattern prefix) s of
    Nothing -> false
    Just rest -> all isDigit (CP.toCodePointArray rest)
  where
  isDigit cp = cp >= CP.codePointFromChar '0' && cp <= CP.codePointFromChar '9'

v :: String -> String -> String -> Violation
v rule proto ty = { rule, proto, ty }

-- | The `coh` parity unit: parse a single-scope source (synthesis-free, no desugar) and
-- | serialize its coherence violations as `rule:proto:ty` joined by `;`.
violationsSexpr :: String -> String
violationsSexpr src =
  joinWith ";" (map ser (violations prog.protocols prog.implDecls reg Nothing))
  where
  prog :: Prog
  prog = parseToProg src
  reg = { sums: map _.name prog.types, structs: map _.name prog.structs }
  ser vio = vio.rule <> ":" <> vio.proto <> ":" <> vio.ty
