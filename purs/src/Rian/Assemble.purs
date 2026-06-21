-- | Assemble tail passes (ADR-0042/0030, ADR-0084) — the part of the reference's `Decl.parse`
-- | that PS `Decl.parseToProg` defers because it would import `Protocol`/`Macro` and cycle with
-- | their parity entries (which import `Decl.parseToProg`). A separate top module composes them
-- | instead: nothing imports `Rian.Assemble`, so there is no cycle.
-- |
-- | This slice synthesizes the **protocol dispatcher / `impl_*` functions** (`Protocol.expand`)
-- | into `prog.funcs`, exactly as `Decl.assemble` does — so a program using `protocol`/`impl`
-- | carries the generated functions downstream (the checker, the emitters). **Macro expansion**
-- | (`lower_meta`) is a follow-up: it stores an expanded AST in the clause body, which needs the
-- | IR `Clause.body` to become `String | Surface` (a ripple through `Check`/`Reach`).
-- |
-- | Top-level protocols only for now (the program-global `protocols`/`implDecls` are synthesized
-- | into the top scope; per-`mod` synthesis is the same shape, deferred with the corpus).
module Rian.Assemble
  ( assemble
  , assembleSexpr
  , assembleBodiesSexpr
  ) where

import Prelude

import Data.Array (concatMap, filter, groupBy, length, mapMaybe, null)
import Data.Array.NonEmpty as NEA
import Data.Foldable (any)
import Data.Maybe (Maybe(..))
import Data.String.Common (joinWith)
import Rian.Core (coreSexpr, fromExpr)
import Rian.Decl (RawDef, buildFunc, parseToProg, progSexpr)
import Rian.IR (Body(..), Clause, Func, Prog, bodySurface)
import Rian.Macro (Env, buildEnv, expand) as Macro
import Rian.Pratt (parseBody) as P
import Rian.Prim (normalize)
import Rian.Protocol (DefMap, expand)
import Rian.TypeStr (splitTopCommas)

-- | Run the assemble tail passes: synthesize the protocol dispatcher / `impl_*` functions
-- | (`Protocol.expand`), then expand `macro` calls in every clause body (`lower_meta`, ADR-0030).
assemble :: Prog -> Prog
assemble prog = expandMacros (prog { funcs = prog.funcs <> synthFuncs })
  where
  -- only impls of a locally-declared protocol synthesize here (the orphan/own-type cases are
  -- `Decl.check_cross_module!`'s job, not this pass).
  impls = filter (\i -> any (\p -> p.name == i.proto) prog.protocols) prog.implDecls
  defMaps =
    if null prog.protocols then []
    else expand prog.protocols impls prog.types prog.structs Nothing
  -- the dispatcher's bodiless sig + per-impl clauses share a name → group into one multi-clause
  -- function; each mangled `impl_*` method is its own single-clause group (as `Decl.assemble` does).
  synthFuncs = map (buildFunc <<< NEA.toArray) (groupBy sameDef (map defMapToRawDef defMaps))

-- group by name + arity (`Decl.assemble`'s `sameFunc`): the dispatcher sig + its per-impl clauses
-- share both, so they collapse into one multi-clause function.
sameDef :: RawDef -> RawDef -> Boolean
sameDef a b = a.name == b.name && length (splitTopCommas a.params) == length (splitTopCommas b.params)

-- a synthesized `Protocol.DefMap` as the raw `def` map `buildFunc` consumes (the synthetic /
-- dispatch metadata is not carried — the IR `Func` has no such field, and the gate/emitters
-- read the func by name/params/clauses).
defMapToRawDef :: DefMap -> RawDef
defMapToRawDef d =
  { name: d.name
  , params: d.params
  , ret: d.ret
  , guard: d.guard
  , body: d.body
  , pub: d.pub
  , tvars: d.tvars
  , bounds: []
  , doc: Nothing
  , externals: []
  }

-- ── macro expansion (`lower_meta`, ADR-0030): expand `macro` calls in every clause body ──
-- A `Raw` body is parsed, normalized, and macro-expanded; the result is stored as an `Expanded`
-- AST (the form the reference's `meta_clause` leaves behind). A no-op when no macros are declared.
expandMacros :: Prog -> Prog
expandMacros prog =
  if null prog.macros then prog
  else
    let env = Macro.buildEnv prog.macros
    in prog
      { funcs = map (expandFunc env) prog.funcs
      , mods = map (\m -> m { funcs = map (expandFunc env) m.funcs }) prog.mods
      }

expandFunc :: Macro.Env -> Func -> Func
expandFunc env f = f { clauses = map (expandClause env) f.clauses }

expandClause :: Macro.Env -> Clause -> Clause
expandClause env c = case c.body of
  Just (Raw s) -> c { body = Just (Expanded (Macro.expand env (normalize (P.parseBody s)) false)) }
  _ -> c

-- | The `asm` parity unit: serialize the assembled program (user + synthesized functions) via the
-- | shared `progSexpr` oracle — matching the reference's `Decl.parse`, which runs the synthesis.
assembleSexpr :: String -> String
assembleSexpr src = progSexpr (assemble (parseToProg src))

-- | The `mxb` parity unit: the Core of every assembled clause body (macros expanded), serialized
-- | via the shared `coreSexpr` oracle — proves the `lower_meta` macro wiring, sidestepping the
-- | body-string serializer (which the reference can't run on an expanded AST).
assembleBodiesSexpr :: String -> String
assembleBodiesSexpr src = joinWith ";" (concatMap funcBodies (allFuncs (assemble (parseToProg src))))
  where
  allFuncs prog = prog.funcs <> concatMap _.funcs prog.mods
  funcBodies f = mapMaybe (\c -> map (\b -> coreSexpr (fromExpr (normalize (bodySurface b)))) c.body) f.clauses
