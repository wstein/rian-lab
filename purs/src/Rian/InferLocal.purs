-- | Infer-local / declare-public (ADR-0034) — the PureScript port of `Rian.InferLocal`
-- | (lib/rian/infer_local.ex), ADR-0084. Fills the return type a **private** function leaves
-- | undeclared by local inference (a `def`-style helper needn't write a signature the compiler
-- | can recover); `pub` functions are untouched — they stay the explicit, declared boundary.
-- |
-- | This slice fills **returns** (the headline): every un-annotated private function's return is
-- | inferred from its body via the `Rian.Check.fill_local_rets` fixpoint (so a private→private
-- | chain resolves), and a return that still can't be pinned — self-recursion, an unmodelled
-- | body — renders `Any` (the dynamic top, ADR-0034): a real type, valid on every target but
-- | `:rs`, so the function is honestly dynamic rather than a parse error. **Parameter** inference
-- | (`infer_param_type` + the `forall T` generalization) is a later slice — the corpus here has
-- | only typed parameters, so the param fixpoint is a no-op.
module Rian.InferLocal
  ( fillReturns
  , fillReturnsSexpr
  ) where

import Prelude

import Data.Array (concatMap, find, length, sortWith)
import Data.Foldable (any)
import Data.Maybe (Maybe(..), fromMaybe, isNothing)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..))
import Rian.Check (fillLocalRets, programIc)
import Rian.Decl (parseToProg)
import Rian.IR (Func, Prog)

-- | Fill undeclared private-function return types by local inference. A no-op unless some
-- | private function omitted its return (or has an `:infer` param — deferred).
fillReturns :: Prog -> Prog
fillReturns prog =
  if any (\f -> untypedRet f || hasInferParam f) (allFuncs prog) then writeFilled prog
  else prog
  where
  writeFilled p =
    let filled = fillLocalRets (allFuncs p) (programIc p)
    in p { funcs = map (fill filled) p.funcs, mods = map (\m -> m { funcs = map (fill filled) m.funcs }) p.mods }

  fill filled f = if untypedRet f then f { ret = Just (filledRet filled f) } else f

  -- the inferred return for an untyped private function, or `Any` when it can't be pinned.
  filledRet filled f = fromMaybe "Any" (lookupFilled filled f)

  lookupFilled filled f = case find (\(Tuple k _) -> k == Tuple f.name (length f.params)) filled of
    Just (Tuple _ ret) -> ret
    Nothing -> Nothing

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> concatMap _.funcs prog.mods

-- an undeclared **private** return (`pub` boundaries stay explicit).
untypedRet :: Func -> Boolean
untypedRet f = not f.pub && isNothing f.ret

-- a parameter left untyped (`:infer`, a lone lowercase token) — its inference is a later slice.
hasInferParam :: Func -> Boolean
hasInferParam f = any (\p -> isNothing p.ty) f.params

-- | The `ilr` parity unit: every function's return after `fillReturns`, `name/arity=>ret` sorted.
fillReturnsSexpr :: String -> String
fillReturnsSexpr src =
  joinWith ";" (sortWith identity (map entry (allFuncs (fillReturns (parseToProg src)))))
  where
  entry f = f.name <> "/" <> show (length f.params) <> "=>" <> fromMaybe "_" f.ret
