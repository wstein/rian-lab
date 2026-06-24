-- | Declarative, hygienic macros — `macro name(params) := template` (ADR-0030). The
-- | PureScript port of `Rian.Macro` (lib/rian/macro.ex), ADR-0084. A pure surface
-- | AST → AST pass before typecheck: a macro call is substituted at the AST level
-- | (precedence always correct), template-local binders are gensym-renamed so they
-- | cannot capture the caller's variables, and (in `portable` mode) a template that
-- | introduces a failable bind (`with … <- …`) is rejected (ADR-0035).
-- |
-- | Parity (`mac` stream): a **fixed** macro env (mirrored in `gen_fixtures.exs`) expands
-- | a call expression, which is lowered to Core and serialized via the shared `coreSexpr`
-- | oracle. The corpus is **binder-free** because `freshen`'s gensym is non-deterministic
-- | in the reference (`:erlang.unique_integer`); hygiene is ported but not byte-tested.
module Rian.Macro
  ( Macro
  , Env
  , buildEnv
  , expand
  , mapNode
  , childrenOf
  , expandSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..), snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Core (coreSexpr, fromExpr) as Core
import Rian.Pratt (Arm, ForClause(..), IPart(..), MapPair(..), Param, Stmt(..), Surface(..), WithClause, parse, parseBody) as P

-- a macro definition: its parameter names and its parsed template.
type Macro = { params :: Array String, template :: P.Surface }

-- the macro environment: `name -> Macro` as an association list (no Data.Map in the
-- purerl package set).
type Env = Array (Tuple String Macro)

-- | Build a macro env from defs (`name`/`params`/`template` source string).
buildEnv :: Array { name :: String, params :: Array String, template :: String } -> Env
buildEnv = map (\d -> Tuple d.name { params: d.params, template: parseTemplate d.template })

-- A macro template is parsed as a function-style BODY (ADR-0030), so a multi-statement block
-- template — `macro m(x)\n  t := …\n  x + t\nend` — is a `SBlock` that substitution/hygiene already
-- walk. A single-expression template (`macro square(x) := x * x`) is the one-statement block,
-- unwrapped to the bare expression so it expands + prints exactly as before (no spurious block).
parseTemplate :: String -> P.Surface
parseTemplate t = case P.parseBody t of
  P.SBlock [ P.StExpr e ] -> e
  block -> block

envLookup :: Env -> String -> Maybe Macro
envLookup env name = map snd (Array.find (\(Tuple k _) -> k == name) env)

maxDepth :: Int
maxDepth = 200

-- | Expand all macro calls in `ast`. `portable` rejects a template that introduces a
-- | failable bind (`with … <- …`) — the discipline `Rian.Decl` drives for `@targets` code.
expand :: Env -> P.Surface -> Boolean -> P.Surface
expand env ast portable = doExpand env portable 0 ast

doExpand :: Env -> Boolean -> Int -> P.Surface -> P.Surface
doExpand _ _ d _ | d > maxDepth = unsafeCrashWith "Macro: expansion too deep"
doExpand env portable d node@(P.SCall (P.SId name) args) =
  case envLookup env name of
    Just m | Array.length m.params == Array.length args ->
      if portable && introducesFailableBind m.template then
        unsafeCrashWith
          ( "Macro: `" <> name <> "` introduces a failable bind (`with … <- …`) — not allowed "
              <> "in portable/@targets code (ADR-0035 no-hidden-control-flow, ADR-0039)"
          )
      else
        let
          eargs = map (doExpand env portable d) args
          tmpl = freshen m.template m.params d
          subst = Array.zip m.params eargs
        in
          doExpand env portable (d + 1) (substitute subst tmpl)
    _ -> mapNode (doExpand env portable d) node
doExpand env portable d node = mapNode (doExpand env portable d) node

-- a failable bind parses to an `SWith`; detect one anywhere in the template (the
-- portable-core guard, ADR-0035).
introducesFailableBind :: P.Surface -> Boolean
introducesFailableBind (P.SWith _ _ _) = true
introducesFailableBind node = Array.any introducesFailableBind (childrenOf node)

-- ── substitution: replace `SId param` with the argument AST ──
substitute :: Array (Tuple String P.Surface) -> P.Surface -> P.Surface
substitute subst (P.SId x) = fromMaybe (P.SId x) (map snd (Array.find (\(Tuple k _) -> k == x) subst))
substitute subst node = mapNode (substitute subst) node

-- ── hygiene: gensym-rename template-local binders (not the params) ──
-- The reference's gensym is non-deterministic; here `d` seeds a deterministic name
-- (the parity corpus is binder-free, so this never appears in tested output).
freshen :: P.Surface -> Array String -> Int -> P.Surface
freshen tmpl params d =
  let binders = Array.filter (\b -> not (Array.elem b params)) (Array.nub (collectBinders tmpl))
  in
    if Array.null binders then tmpl
    else rename (map (\b -> Tuple b (b <> "__h" <> show d)) binders) tmpl

-- template-local binder names — block `:=` binds and lambda params — anywhere in the AST.
collectBinders :: P.Surface -> Array String
collectBinders node = bindersHere node <> Array.concatMap collectBinders (childrenOf node)

bindersHere :: P.Surface -> Array String
bindersHere (P.SBlock stmts) = Array.concatMap stmtBinder stmts
  where
  stmtBinder (P.StBind n _) = [ n ]
  stmtBinder (P.StTypedBind n _ _) = [ n ]
  stmtBinder _ = []
bindersHere (P.SLambda ps _) = map _.name ps
bindersHere _ = []

-- the rename happens at `SId`; the two binder-introducing nodes (`SBlock` binds,
-- `SLambda` params) also rename their bound NAMES; everything else recurses via `mapNode`.
rename :: Array (Tuple String String) -> P.Surface -> P.Surface
rename ren (P.SId x) = P.SId (renameName ren x)
rename ren (P.SLambda ps b) = P.SLambda (map (\p -> p { name = renameName ren p.name }) ps) (rename ren b)
rename ren (P.SBlock stmts) = P.SBlock (map renameStmt stmts)
  where
  renameStmt (P.StBind n e) = P.StBind (renameName ren n) (rename ren e)
  renameStmt (P.StTypedBind n t e) = P.StTypedBind (renameName ren n) t (rename ren e)
  renameStmt s = mapStmt (rename ren) s
rename ren node = mapNode (rename ren) node

renameName :: Array (Tuple String String) -> String -> String
renameName ren x = fromMaybe x (map snd (Array.find (\(Tuple k _) -> k == x) ren))

-- ── generic one-level child map (the heart of the pass) ──
mapNode :: (P.Surface -> P.Surface) -> P.Surface -> P.Surface
mapNode f = case _ of
  P.SUnary op x -> P.SUnary op (f x)
  P.SBin op l r -> P.SBin op (f l) (f r)
  P.SCall fn args -> P.SCall (f fn) (map f args)
  P.SDot h n -> P.SDot (f h) n
  P.SLabel n e -> P.SLabel n (f e)
  P.SCapture b -> P.SCapture (f b)
  P.SCaptureNamed p a -> P.SCaptureNamed (f p) a
  P.SLambda ps b -> P.SLambda ps (f b)
  P.SIf c t e -> P.SIf (f c) (f t) (f e)
  P.SCase s arms -> P.SCase (f s) (map (mapArm f) arms)
  P.SWith clauses body els -> P.SWith (map (mapWithClause f) clauses) (f body) (map (mapArm f) els)
  P.SBlock stmts -> P.SBlock (map (mapStmt f) stmts)
  P.SListLit es tail -> P.SListLit (map f es) (map f tail)
  P.SMapLit ps -> P.SMapLit (map (mapPair f) ps)
  P.SMapUpdate base ps -> P.SMapUpdate (f base) (map (mapPair f) ps)
  P.STuple es -> P.STuple (map f es)
  P.SFor clauses body -> P.SFor (map (mapForClause f) clauses) (f body)
  P.SStrInterp parts -> P.SStrInterp (map (mapIPart f) parts)
  leaf -> leaf -- SNum / SStr / SChar / SId / SAtom / SCapArg

mapStmt :: (P.Surface -> P.Surface) -> P.Stmt -> P.Stmt
mapStmt f (P.StBind n e) = P.StBind n (f e)
mapStmt f (P.StTypedBind n t e) = P.StTypedBind n t (f e)
mapStmt f (P.StBindArrow n e) = P.StBindArrow n (f e)
mapStmt f (P.StBindPat p e) = P.StBindPat p (f e)
mapStmt f (P.StExpr e) = P.StExpr (f e)

mapArm :: (P.Surface -> P.Surface) -> P.Arm -> P.Arm
mapArm f a = a { guard = map f a.guard, body = f a.body }

mapWithClause :: (P.Surface -> P.Surface) -> P.WithClause -> P.WithClause
mapWithClause f c = c { expr = f c.expr }

mapPair :: (P.Surface -> P.Surface) -> P.MapPair -> P.MapPair
mapPair f (P.MAtom k v) = P.MAtom k (f v)
mapPair f (P.MKey k v) = P.MKey (f k) (f v)

mapForClause :: (P.Surface -> P.Surface) -> P.ForClause -> P.ForClause
mapForClause f (P.FGen p src) = P.FGen p (f src)
mapForClause f (P.FFilter c) = P.FFilter (f c)

mapIPart :: (P.Surface -> P.Surface) -> P.IPart -> P.IPart
mapIPart _ (P.ILit s) = P.ILit s
mapIPart f (P.IHole e) = P.IHole (f e)

-- direct child expressions of a node — the recursion targets for `collectBinders` /
-- `introducesFailableBind`. (A binder NAME is not a child here — `bindersHere` reads it.)
childrenOf :: P.Surface -> Array P.Surface
childrenOf (P.SUnary _ x) = [ x ]
childrenOf (P.SBin _ l r) = [ l, r ]
childrenOf (P.SCall fn args) = [ fn ] <> args
childrenOf (P.SDot h _) = [ h ]
childrenOf (P.SLabel _ e) = [ e ]
childrenOf (P.SCapture b) = [ b ]
childrenOf (P.SCaptureNamed p _) = [ p ]
childrenOf (P.SLambda _ b) = [ b ]
childrenOf (P.SIf c t e) = [ c, t, e ]
childrenOf (P.SCase s arms) = [ s ] <> Array.concatMap armChildren arms
childrenOf (P.SWith clauses body els) = map _.expr clauses <> [ body ] <> Array.concatMap armChildren els
childrenOf (P.SBlock stmts) = Array.concatMap stmtChild stmts
childrenOf (P.SListLit es tail) = es <> Array.fromFoldable tail
childrenOf (P.SMapLit ps) = Array.concatMap pairChildren ps
childrenOf (P.SMapUpdate base ps) = [ base ] <> Array.concatMap pairChildren ps
childrenOf (P.STuple es) = es
childrenOf (P.SFor clauses body) = Array.concatMap forChildren clauses <> [ body ]
childrenOf (P.SStrInterp parts) = Array.concatMap iPartChildren parts
childrenOf _ = []

armChildren :: P.Arm -> Array P.Surface
armChildren a = Array.fromFoldable a.guard <> [ a.body ]

stmtChild :: P.Stmt -> Array P.Surface
stmtChild (P.StBind _ e) = [ e ]
stmtChild (P.StTypedBind _ _ e) = [ e ]
stmtChild (P.StBindArrow _ e) = [ e ]
stmtChild (P.StBindPat _ e) = [ e ]
stmtChild (P.StExpr e) = [ e ]

pairChildren :: P.MapPair -> Array P.Surface
pairChildren (P.MAtom _ v) = [ v ]
pairChildren (P.MKey k v) = [ k, v ]

forChildren :: P.ForClause -> Array P.Surface
forChildren (P.FGen _ src) = [ src ]
forChildren (P.FFilter c) = [ c ]

iPartChildren :: P.IPart -> Array P.Surface
iPartChildren (P.ILit _) = []
iPartChildren (P.IHole e) = [ e ]

-- ── parity (`mac` stream): a fixed env, mirrored in gen_fixtures ──
-- Binder-free templates only (so `freshen` is a no-op → deterministic output).
testDefs :: Array { name :: String, params :: Array String, template :: String }
testDefs =
  [ { name: "double", params: [ "x" ], template: "x + x" }
  , { name: "inc", params: [ "x" ], template: "x + 1" }
  , { name: "swap", params: [ "a", "b" ], template: "(b, a)" }
  , { name: "apply", params: [ "f", "x" ], template: "f(x)" }
  , { name: "pick", params: [ "c", "a", "b" ], template: "if c do a else b end" }
  ]

-- | Expand a call expression with the fixed `testDefs` env, lower to Core, serialize via
-- | the shared `coreSexpr` oracle (the `mac` parity unit).
expandSexpr :: String -> String
expandSexpr src = Core.coreSexpr (Core.fromExpr (expand (buildEnv testDefs) (P.parse src) false))
