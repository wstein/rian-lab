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
  , runProgramTail
  , assembleSexpr
  , assembleBodiesSexpr
  ) where

import Prelude

import Data.Array (concatMap, filter, groupBy, length, mapMaybe, null)
import Data.Array.NonEmpty as NEA
import Data.Foldable (any)
import Data.Maybe (Maybe(..))
import Data.String.Common (joinWith)
import Rian.Check (Ic, clauseEnv, fillLocalRets, programIc)
import Rian.Comptime (fold) as Comptime
import Rian.Core (coreSexpr, fromExpr)
import Rian.Decl (RawDef, buildFunc, parseToProg, progSexpr)
import Rian.IR (Body(..), Clause, Func, Prog, bodySurface)
import Rian.Interp (resolve) as Interp
import Rian.Macro (Env, buildEnv, childrenOf, expand) as Macro
import Rian.Pratt (Surface(..), parseBody, sexpr) as P
import Rian.Prim (normalize)
import Rian.Protocol (DefMap, expand)
import Rian.ShowStdlib (theModule) as ShowStdlib
import Rian.IOStdlib (funcs) as IOStdlib
import Rian.TypeStr (splitTopCommas)

-- | Run the assemble tail passes: synthesize the protocol dispatcher / `impl_*` functions
-- | (`Protocol.expand`), then `lower_meta` over every clause body — `Macro.expand` then
-- | `Comptime.fold` (ADR-0030).
assemble :: Prog -> Prog
assemble prog = lowerMeta (prog { funcs = prog.funcs <> synthFuncs })
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

-- a synthesized `Protocol.DefMap` as the raw `def` map `buildFunc` consumes; the dispatch marker
-- (`"dispatcher"`/`"impl"`) is carried onto the `Func` so an emitter can skip the BEAM dispatcher
-- and regenerate it per-target (ADR-0061 §3).
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
  , effects: []
  -- carry the protocol-desugar marker (`"dispatcher"`/`"impl"`) so the emitters can skip the
  -- BEAM-shaped dispatcher and regenerate it per-target (ADR-0061 §3).
  , dispatch: Just d.dispatch
  }

-- ── `lower_meta` (ADR-0030): macro-expand then comptime-fold every clause body ──
-- A `Raw` body is parsed, normalized, `Macro.expand`ed (a no-op for an empty env), then
-- `Comptime.fold`ed; the result is stored as `Expanded` ONLY when it actually changed (the
-- reference's "an untouched body keeps its source string" invariant — change-detected by the
-- canonical `sexpr`, since `Surface` has no `Eq`). Runs always — comptime fires without macros.
lowerMeta :: Prog -> Prog
lowerMeta prog =
  prog
    { funcs = map (lowerMetaFunc env) prog.funcs
    , mods = map (\m -> m { funcs = map (lowerMetaFunc env) m.funcs }) prog.mods
    }
  where
  env = Macro.buildEnv prog.macros

lowerMetaFunc :: Macro.Env -> Func -> Func
lowerMetaFunc env f = f { clauses = map (lowerMetaClause env) f.clauses }

lowerMetaClause :: Macro.Env -> Clause -> Clause
lowerMetaClause env c = case c.body of
  Just (Raw s) ->
    let
      ast = normalize (P.parseBody s)
      folded = Comptime.fold (Macro.expand env ast false)
    in
      if P.sexpr folded == P.sexpr ast then c else c { body = Just (Expanded folded) }
  _ -> c

-- | The `asm` parity unit: serialize the assembled program (user + synthesized functions) via the
-- | shared `progSexpr` oracle — matching the reference's `Decl.parse`, which runs the synthesis.
assembleSexpr :: String -> String
assembleSexpr src = progSexpr (assemble (parseToProg src))

-- | The `mxb` parity unit: the Core of every assembled clause body (macros expanded), serialized
-- | via the shared `coreSexpr` oracle — proves the `lower_meta` macro wiring, sidestepping the
-- | body-string serializer (which the reference can't run on an expanded AST).
assembleBodiesSexpr :: String -> String
assembleBodiesSexpr src = joinWith ";" (concatMap funcBodies (allProgFuncs (assemble (parseToProg src))))
  where
  funcBodies f = mapMaybe (\c -> map (\b -> coreSexpr (fromExpr (normalize (bodySurface b)))) c.body) f.clauses

allProgFuncs :: Prog -> Array Func
allProgFuncs prog = prog.funcs <> concatMap _.funcs prog.mods

--------------------------------------------------------------------------------
-- program tail: interpolation resolution + stdlib injection (ADR-0069)
--------------------------------------------------------------------------------

-- | Run the program-wide tail after `assemble` (the reference's `run_program_tail`, minus the
-- | `InferLocal.fill_returns` pass, which is separate): resolve `${…}` interpolation, then inject the
-- | `Show` stdlib if a `Float64` was interpolated. Kept distinct from `assemble` (= `assemble_only`)
-- | so the `asm`/`mxb` parity streams are unaffected; the emitters compose it before lowering.
runProgramTail :: Prog -> Prog
runProgramTail = injectStdlib <<< resolveInterp

-- Program-wide string-interpolation resolution (ADR-0069): one inference context over all modules'
-- signatures/types/structs/ctors (funs filled by `fillLocalRets` so a `${f(x)}` over an un-annotated
-- function resolves), then rewrite every clause body's holes. Mirrors `Decl.resolve_interp`.
resolveInterp :: Prog -> Prog
resolveInterp prog =
  let
    ic0 = programIc prog
    ic = ic0 { funs = fillLocalRets (allProgFuncs prog) ic0 }
    show = map _.ty (filter (\i -> i.proto == "Show") prog.implDecls)
    resolveFuncs = map (resolveFuncInterp ic show)
  in
    prog { funcs = resolveFuncs prog.funcs, mods = map (\m -> m { funcs = resolveFuncs m.funcs }) prog.mods }

resolveFuncInterp :: Ic -> Array String -> Func -> Func
resolveFuncInterp ic show f = f { clauses = map (resolveClauseInterp f ic show) f.clauses }

resolveClauseInterp :: Func -> Ic -> Array String -> Clause -> Clause
resolveClauseInterp f ic show c = case c.body of
  Nothing -> c
  Just body ->
    let
      ast = bodySurface body
      out = Interp.resolve (clauseEnv c.pats f.params ic) ic show ast
    in
      -- change-detect via the canonical sexpr (Surface has no `Eq`), keeping an untouched body Raw.
      if P.sexpr out == P.sexpr ast then c else c { body = Just (Expanded out) }

-- Prelude injection (ADR-0047 / ADR-0069 §6): a program that interpolates a `Float64` calls
-- `Show.float`, so supply the `Show` module unless one is already defined. Read off the rewritten
-- program (the `Show.float` call) rather than a flag, so the resolver stays pure. Mirrors
-- `inject_stdlib`.
injectStdlib :: Prog -> Prog
injectStdlib = injectIo <<< injectShow

injectShow :: Prog -> Prog
injectShow prog =
  if needsShowFloat prog && not (any (\m -> m.name == "Show") prog.mods) then prog { mods = [ ShowStdlib.theModule ] <> prog.mods }
  else prog

-- Console I/O (ADR-0068/0069): a program that calls `puts`/`print` but does not define its own IO
-- gets the IO prelude's functions EMITTED into it (`Rian.IOStdlib`), so they run on a source target
-- (`console.log`/`println`) instead of dangling. Mirrors `Rian.Decl.inject_io`.
injectIo :: Prog -> Prog
injectIo prog =
  if needsIo prog && not (ioDefined prog) then prog { funcs = IOStdlib.funcs <> prog.funcs }
  else prog

ioDefined :: Prog -> Boolean
ioDefined prog = any (\f -> f.name == "puts" || f.name == "print" || f.name == "line" || f.name == "write") prog.funcs

needsIo :: Prog -> Boolean
needsIo prog = any (\f -> any (callsIo <<< _.body) f.clauses) (allProgFuncs prog)

callsIo :: Maybe Body -> Boolean
callsIo Nothing = false
callsIo (Just body) = go (bodySurface body)
  where
  go (P.SCall (P.SId n) _) = n == "puts" || n == "print"
  go node = any go (Macro.childrenOf node)

needsShowFloat :: Prog -> Boolean
needsShowFloat prog = any (\f -> any (callsShowFloat <<< _.body) f.clauses) (allProgFuncs prog)

callsShowFloat :: Maybe Body -> Boolean
callsShowFloat Nothing = false
callsShowFloat (Just body) = go (bodySurface body)
  where
  go (P.SCall (P.SDot (P.SId "Show") "float") _) = true
  go node = any go (Macro.childrenOf node)
