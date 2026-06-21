-- | Rewrites the reserved `Prim.<name>(args)` surface namespace into the canonical
-- | compiler intrinsic `__prim_<name>(args)` — the PureScript port of `Rian.Prim`
-- | (lib/rian/prim.ex), ADR-0084 / ADR-0047 §2. A bare 1-arg `panic(msg)` is the one
-- | ergonomic spelling rewritten to `__prim_panic(msg)` (ADR-0035/0040). An unknown
-- | `Prim.<name>` is a hard error (the namespace is reserved).
-- |
-- | The Elixir reference walks the raw tuple AST generically; here it is a structural
-- | recursion over `Rian.Pratt`'s typed `Surface`. It is a **separate pass** from the
-- | parser (`Rian.Pratt.parse` stays normalize-free to avoid a `Pratt`↔`Prim` module
-- | cycle); callers compose `normalize` over the parsed surface, exactly where the Elixir
-- | `parse`/`parse_body` call it.
module Rian.Prim
  ( names
  , overflowOps
  , normalize
  , normalizeSexpr
  ) where

import Prelude

import Data.Foldable (elem)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Pratt as P

-- | The closed set of compiler intrinsics the reserved `Prim.*` surface exposes
-- | (ADR-0047 §2). Must stay in sync with the `__prim_*` clauses in the emitters.
-- @rian_sig pub def names() Vec(String)
names :: Array String
names =
  [ "str_chars", "str_from_chars", "str_concat", "str_concat_all", "str_to_atom", "str_to_float"
  , "char_code", "int_to_string", "int_to_float", "char_to_string", "to_string"
  , "map_new", "map_get", "map_put", "map_has"
  , "wrapping_add", "saturating_add", "checked_add"
  , "panic"
  ]

-- | The canonical `__prim_*` 64-bit-overflow ops (JS-unsupported; off `:js`).
-- @rian_sig pub def overflowOps() Vec(String)
overflowOps :: Array String
overflowOps = map (\n -> "__prim_" <> n) [ "wrapping_add", "saturating_add", "checked_add" ]

-- | Rewrite `Prim.<name>(args)` → `__prim_<name>(args)` (and bare `panic(msg)`)
-- | throughout an expression. Idempotent; non-`Prim` calls pass through; an unknown
-- | `Prim.<name>` raises.
-- @rian_sig pub def normalize(node val Surface) Surface
normalize :: P.Surface -> P.Surface
normalize (P.SCall (P.SDot (P.SId "Prim") name) args)
  | name `elem` names = P.SCall (P.SId ("__prim_" <> name)) (map normalize args)
  | otherwise = unsafeCrashWith ("unknown primitive `Prim." <> name <> "` (ADR-0047 §2)")
normalize (P.SCall (P.SId "panic") [ arg ]) = P.SCall (P.SId "__prim_panic") [ normalize arg ]
normalize (P.SCall f args) = P.SCall (normalize f) (map normalize args)
normalize (P.SUnary op x) = P.SUnary op (normalize x)
normalize (P.SBin op l r) = P.SBin op (normalize l) (normalize r)
normalize (P.SDot h n) = P.SDot (normalize h) n
normalize (P.SLabel n e) = P.SLabel n (normalize e)
normalize (P.SCapture b) = P.SCapture (normalize b)
normalize (P.SCaptureNamed p a) = P.SCaptureNamed (normalize p) a
normalize (P.STuple es) = P.STuple (map normalize es)
normalize (P.SListLit es tail) = P.SListLit (map normalize es) (map normalize tail)
normalize (P.SMapLit ps) = P.SMapLit (map normMapPair ps)
normalize (P.SIf c t e) = P.SIf (normalize c) (normalize t) (normalize e)
normalize (P.SCase scrut arms) = P.SCase (normalize scrut) (map normArm arms)
normalize (P.SLambda params body) = P.SLambda params (normalize body)
normalize (P.SBlock stmts) = P.SBlock (map normStmt stmts)
normalize (P.SWith clauses body els) =
  P.SWith (map normWithClause clauses) (normalize body) (map normArm els)
normalize (P.SFor clauses body) = P.SFor (map normForClause clauses) (normalize body)
normalize (P.SStrInterp parts) = P.SStrInterp (map normIPart parts)
normalize leaf = leaf -- SNum, SStr, SChar, SId, SAtom, SCapArg

-- normalize the expression positions of the compound nodes (patterns carry no `Prim`
-- call in surface source, so they pass through).
normMapPair :: P.MapPair -> P.MapPair
normMapPair (P.MAtom k v) = P.MAtom k (normalize v)
normMapPair (P.MKey k v) = P.MKey (normalize k) (normalize v)

normArm :: P.Arm -> P.Arm
normArm a = a { guard = map normalize a.guard, body = normalize a.body }

normWithClause :: P.WithClause -> P.WithClause
normWithClause c = c { expr = normalize c.expr }

normForClause :: P.ForClause -> P.ForClause
normForClause (P.FGen p src) = P.FGen p (normalize src)
normForClause (P.FFilter c) = P.FFilter (normalize c)

normStmt :: P.Stmt -> P.Stmt
normStmt (P.StBind n e) = P.StBind n (normalize e)
normStmt (P.StTypedBind n t e) = P.StTypedBind n t (normalize e)
normStmt (P.StBindArrow n e) = P.StBindArrow n (normalize e)
normStmt (P.StExpr e) = P.StExpr (normalize e)

normIPart :: P.IPart -> P.IPart
normIPart (P.ILit s) = P.ILit s
normIPart (P.IHole e) = P.IHole (normalize e)

-- | Parse, normalize, and render — the `prm` parity-stream entry. Equals the Elixir
-- | `Pratt.parse_sexpr` (which applies `normalize` inside `parse`).
normalizeSexpr :: String -> String
normalizeSexpr = P.sexpr <<< normalize <<< P.parse
