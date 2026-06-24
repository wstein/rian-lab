-- | Post-CHECK semantic simplification (ADR-0046 §3) — the PureScript twin of `Rian.Optimize`
-- | (lib/rian/optimize.ex), ADR-0084. Eliminates a branch/operator that the checker has already
-- | validated, so it runs AFTER `Check` (in `Lower.All.prepare`), never in `Decl.parse` — the bare
-- | `parse → emit` parity path stays unsimplified. Pure surface AST → AST over each clause body.
-- |
-- |   * #2 dead-`if` — a constant condition selects its branch (`if false do A else B end` → `B`).
-- |   * #3 constant-`case` — a literal (int/string) scrutinee selects the matching arm (conservative).
-- |   * #4 boolean identities — the evaluation-preserving ones (`true and x` → `x`, etc.).
module Rian.Optimize
  ( simplify
  , simplifyExpr
  , optSexpr
  ) where

import Prelude

import Data.Array (uncons)
import Data.Int (fromString) as Int
import Data.Maybe (Maybe(..), isJust)
import Data.String (Pattern(..), Replacement(..), contains, replaceAll) as Str
import Rian.Core (coreSexpr, fromExpr) as Core
import Rian.IR (Body(..), Clause, Func, Prog, bodySurface)
import Rian.Macro (mapNode)
import Rian.Pratt (Arm, Pat(..), Surface(..), parse, sexpr) as P

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
-- #3 constant-`case` arm selection: a literal (int/string) scrutinee picks the matching arm; a
-- `var`/ctor pattern or a guard stops it (the case is kept, scrutinee + bodies simplified). Mirrors
-- `Rian.Optimize`'s `select_const_arm`/`match_arm`/`scrut_value`.
simplifyExpr (P.SCase scrut arms) =
  let scrut2 = simplifyExpr scrut
  in case selectConstArm scrut2 arms of
    Just body -> simplifyExpr body
    Nothing -> P.SCase scrut2 (map (\a -> a { body = simplifyExpr a.body }) arms)
simplifyExpr node = mapNode simplifyExpr node

data CV = CVInt Int | CVStr String

selectConstArm :: P.Surface -> Array P.Arm -> Maybe P.Surface
selectConstArm scrut arms = case scrutVal scrut of
  Just v -> matchArm v arms
  Nothing -> Nothing

scrutVal :: P.Surface -> Maybe CV
scrutVal (P.SNum n) =
  let clean = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n
  in
    if Str.contains (Str.Pattern ".") clean || Str.contains (Str.Pattern "e") clean || Str.contains (Str.Pattern "E") clean then Nothing
    else map CVInt (Int.fromString clean)
scrutVal (P.SStr s) = Just (CVStr s)
scrutVal _ = Nothing

matchArm :: CV -> Array P.Arm -> Maybe P.Surface
matchArm v arms = case uncons arms of
  Nothing -> Nothing
  Just { head: arm, tail } ->
    if isJust arm.guard then Nothing
    else case arm.pat, v of
      P.PWild, _ -> Just arm.body
      P.PLitInt pv, CVInt sv -> if pv == sv then Just arm.body else matchArm v tail
      P.PLitStr pv, CVStr sv -> if pv == sv then Just arm.body else matchArm v tail
      _, _ -> Nothing

-- | The `opt` parity entry: simplify a source expression and serialize through the shared Core
-- | s-expression oracle (so PS and the Elixir reference are compared byte-for-byte).
optSexpr :: String -> String
optSexpr src = Core.coreSexpr (Core.fromExpr (simplifyExpr (P.parse src)))
