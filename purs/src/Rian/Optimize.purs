-- | Post-CHECK semantic simplification (ADR-0046 §3) — the PureScript twin of `Rian.Optimize`
-- | (lib/rian/optimize.ex), ADR-0084. Eliminates a branch/operator that the checker has already
-- | validated, so it runs AFTER `Check` (in `Lower.All.prepare`), never in `Decl.parse` — the bare
-- | `parse → emit` parity path stays unsimplified. Pure surface AST → AST over each clause body.
-- |
-- |   * #2 dead-`if` — a constant condition selects its branch (`if false do A else B end` → `B`).
module Rian.Optimize
  ( simplify
  , simplifyExpr
  , optSexpr
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Rian.Core (coreSexpr, fromExpr) as Core
import Rian.IR (Body(..), Clause, Func, Prog, bodySurface)
import Rian.Macro (mapNode)
import Rian.Pratt (Surface(..), parse, sexpr) as P

-- | Apply `simplifyExpr` to every clause body, program-wide (mirrors `Rian.Optimize.simplify`).
simplify :: Prog -> Prog
simplify prog =
  prog
    { funcs = map simplifyFunc prog.funcs
    , mods = map (\m -> m { funcs = map simplifyFunc m.funcs }) prog.mods
    }

simplifyFunc :: Func -> Func
simplifyFunc f = f { clauses = map simplifyClause f.clauses }

simplifyClause :: Clause -> Clause
simplifyClause c = case c.body of
  Nothing -> c
  Just body ->
    let
      ast = bodySurface body
      out = simplifyExpr ast
    in
      if P.sexpr out == P.sexpr ast then c else c { body = Just (Expanded out) }

-- | Simplify one surface expression. #2 dead-`if`: a now-constant condition selects its branch
-- | (the other branch — and any type error/Reach pin it carried — is dropped; sound here because
-- | the checker already validated both branches and Reach runs after this pass).
simplifyExpr :: P.Surface -> P.Surface
simplifyExpr (P.SIf c t e) = case simplifyExpr c of
  P.SId "true" -> simplifyExpr t
  P.SId "false" -> simplifyExpr e
  c2 -> P.SIf c2 (simplifyExpr t) (simplifyExpr e)
-- #4 evaluation-preserving boolean identities (`true and x` → `x`, etc.); the dropping pair is left
-- to the backend's short-circuit. Sound post-check (the checker already pinned the operand `Bool`).
simplifyExpr (P.SBin "and" l r) = case simplifyExpr l, simplifyExpr r of
  P.SId "true", r2 -> r2
  l2, P.SId "true" -> l2
  l2, r2 -> P.SBin "and" l2 r2
simplifyExpr (P.SBin "or" l r) = case simplifyExpr l, simplifyExpr r of
  P.SId "false", r2 -> r2
  l2, P.SId "false" -> l2
  l2, r2 -> P.SBin "or" l2 r2
simplifyExpr node = mapNode simplifyExpr node

-- | The `opt` parity entry: simplify a source expression and serialize through the shared Core
-- | s-expression oracle (so PS and the Elixir reference are compared byte-for-byte).
optSexpr :: String -> String
optSexpr src = Core.coreSexpr (Core.fromExpr (simplifyExpr (P.parse src)))
