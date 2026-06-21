-- | Opaque-type erasure (ADR-0067 / ADR-0043) — the PureScript port of `Rian.Opaque`
-- | (lib/rian/opaque.ex), ADR-0084. Erases `opaque T := Base` / `abstract` types from a parsed
-- | program AFTER the gates (which need the nominal view) and before any emitter: an opaque is
-- | nominal to `Check` but zero-cost at runtime — the value *is* the base value. This pass makes
-- | that real:
-- |
-- |   1. substitute every opaque name → its `base` in all type positions (params, returns,
-- |      struct/variant fields, consts), to a fixpoint so opaque-over-opaque resolves;
-- |   2. rewrite the total constructor `T.of(x)` → bare `x` (an opaque adds no failure mode);
-- |   3. rewrite a declared `abstract` cast `v.cast()` → bare `v` — but ONLY when `v`'s type is an
-- |      abstract that declares that cast (so an unrelated `other.cast()` is left alone).
-- |
-- | A program with no opaques is returned unchanged (the common, zero-overhead case).
module Rian.Opaque
  ( erase
  , eraseSexpr
  ) where

import Prelude

import Data.Array (concatMap, foldl, head, length, null)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String (Pattern(..), split) as Str
import Data.String.Common (joinWith, trim)
import Data.Tuple (Tuple(..))
import Rian.Check (Env, Ty(..), emptyIc, infer)
import Rian.Core (coreSexpr, fromExpr)
import Rian.Decl (parseToProg, splitWords)
import Rian.IR (Body(..), Clause, Func, Mod, Opaque, Prog, Struct, Type, bodySurface)
import Rian.Macro (mapNode)
import Rian.Pratt (Surface(..))
import Rian.Prim (normalize)

-- `names` = opaque-name → base (type substitution); `casts` = cast-name → the abstract names that
-- declare it (so `v.cast()` strips only when `v`'s type is one of those abstracts, ADR-0067 §2).
type Ctx = { names :: Array (Tuple String String), casts :: Array (Tuple String (Array String)) }

-- | Erase all opaque types from a parsed program. A no-op when it has none.
-- @rian_sig pub def erase(prog val Prog) Prog
erase :: Prog -> Prog
erase prog =
  let all = opaques prog
  in if null all then prog else doErase (eraseCtx all) prog

-- every opaque in the program (top level + every module).
opaques :: Prog -> Array Opaque
opaques prog = prog.opaques <> concatMap _.opaques prog.mods

eraseCtx :: Array Opaque -> Ctx
eraseCtx all = { names: map (\o -> Tuple o.name o.base) all, casts: foldl addOpaque [] all }
  where
  addOpaque acc o = foldl (\a c -> addCast a (castName c) o.name) acc o.casts

-- the cast's name is the leading identifier of its member string (`base() Int53` → `base`).
castName :: String -> String
castName s = trim (fromMaybe s (head (Str.split (Str.Pattern "(") s)))

-- record that abstract `nm` declares cast `cn` (appending to the existing set, or starting one).
addCast :: Array (Tuple String (Array String)) -> String -> String -> Array (Tuple String (Array String))
addCast assoc cn nm = case assocLookup cn assoc of
  Just _ -> map (\(Tuple k v) -> if k == cn then Tuple k (v <> [ nm ]) else Tuple k v) assoc
  Nothing -> assoc <> [ Tuple cn [ nm ] ]

-- first-match assoc lookup (a manual foldl: purerl miscompiles `find` over some arrays).
assocLookup :: forall v. String -> Array (Tuple String v) -> Maybe v
assocLookup k = foldl step Nothing
  where
  step acc (Tuple k2 v) = case acc of
    Just _ -> acc
    Nothing -> if k2 == k then Just v else Nothing

doErase :: Ctx -> Prog -> Prog
doErase ctx prog = prog
  { types = map (eraseType ctx) prog.types
  , structs = map (eraseStruct ctx) prog.structs
  , funcs = map (eraseFunc ctx) prog.funcs
  , mods = map (eraseMod ctx) prog.mods
  }

eraseMod :: Ctx -> Mod -> Mod
eraseMod ctx m = m
  { types = map (eraseType ctx) m.types
  , structs = map (eraseStruct ctx) m.structs
  , consts = map (\c -> c { ty = map (substType ctx.names) c.ty }) m.consts
  , funcs = map (eraseFunc ctx) m.funcs
  }

eraseType :: Ctx -> Type -> Type
eraseType ctx t = t { variants = map (\v -> v { fields = map (eraseField ctx) v.fields }) t.variants }

eraseStruct :: Ctx -> Struct -> Struct
eraseStruct ctx s = s { fields = map (eraseField ctx) s.fields }

eraseField :: forall r. Ctx -> { ty :: String | r } -> { ty :: String | r }
eraseField ctx f = f { ty = substType ctx.names f.ty }

eraseFunc :: Ctx -> Func -> Func
eraseFunc ctx f =
  f
    { params = map (\p -> p { ty = map (substType ctx.names) p.ty }) f.params
    , ret = map (substType ctx.names) f.ret
    , clauses = map (eraseClause ctx env) f.clauses
    }
  where
  -- name → type from the ORIGINAL (pre-substitution) params, for the type-scoped cast erasure.
  env = map (\p -> Tuple p.name (maybe Unknown TName p.ty)) f.params

eraseClause :: Ctx -> Env -> Clause -> Clause
eraseClause ctx env c = case c.body of
  Nothing -> c
  Just b -> c { body = Just (Expanded (strip ctx env (normalize (bodySurface b)))) }

-- ── type substitution: opaque name → base, simultaneously, to a fixpoint ──
-- Each pass replaces ALL opaque names at once (a word looked up in `names`), so the result is
-- order-independent; it repeats until stable so opaque-over-opaque resolves transitively, capped by
-- a chain-length `fuel` against a cyclic definition.
substType :: Array (Tuple String String) -> String -> String
substType names t = if null names then t else substFix names t (length names + 1)

substFix :: Array (Tuple String String) -> String -> Int -> String
substFix names t fuel =
  if fuel <= 0 then t
  else let next = substOnce names t in if next == t then t else substFix names next (fuel - 1)

substOnce :: Array (Tuple String String) -> String -> String
substOnce names s = joinWith "" (map (\w -> fromMaybe w (assocLookup w names)) (splitWords s))

-- ── strip the two runtime-identity constructs from a clause body, recursively ──
strip :: Ctx -> Env -> Surface -> Surface
strip ctx env node = case node of
  SCall (SDot hd method) args -> stripDot ctx env node hd method args
  _ -> mapNode (strip ctx env) node

stripDot :: Ctx -> Env -> Surface -> Surface -> String -> Array Surface -> Surface
stripDot ctx env node hd method args =
  -- `T.of(x)` (opaque constructor) → strip `x`
  if method == "of" && idIsOpaque ctx hd && length args == 1 then
    case head args of
      Just a -> strip ctx env a
      Nothing -> recurse
  -- `v.cast()` → strip `v`, when `v`'s type is an abstract declaring `cast`
  else if length args == 0 && castMatches ctx env hd method then
    strip ctx env hd
  else recurse
  where
  recurse = mapNode (strip ctx env) node

idIsOpaque :: Ctx -> Surface -> Boolean
idIsOpaque ctx hd = case hd of
  SId n -> case assocLookup n ctx.names of
    Just _ -> true
    Nothing -> false
  _ -> false

castMatches :: Ctx -> Env -> Surface -> String -> Boolean
castMatches ctx env hd cn = case assocLookup cn ctx.casts of
  Nothing -> false
  Just decls -> case infer (fromExpr hd) env emptyIc of
    TName t -> isMember t decls
    _ -> false

isMember :: String -> Array String -> Boolean
isMember x = foldl (\acc d -> acc || d == x) false

-- | The `opq` parity unit: the erased program's functions — `name:p0,p1=>ret=bodyCore` — proving
-- | the type substitution (params/ret) and the `.of`/cast stripping (the body's Core), sorted.
eraseSexpr :: String -> String
eraseSexpr src = joinWith ";" (map entry (allFuncs (erase (parseToProg src))))
  where
  allFuncs prog = prog.funcs <> concatMap _.funcs prog.mods
  entry f =
    f.name
      <> ":" <> joinWith "," (map (\p -> fromMaybe "_" p.ty) f.params)
      <> "=>" <> fromMaybe "_" f.ret
      <> "=" <> bodyCore f
  bodyCore f = case head f.clauses of
    Just c -> case c.body of
      Just b -> coreSexpr (fromExpr (normalize (bodySurface b)))
      Nothing -> "_"
    Nothing -> "_"
