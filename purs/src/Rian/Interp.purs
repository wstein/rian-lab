-- | String-interpolation resolution (ADR-0069) — the PureScript port of `Rian.Interp`
-- | (lib/rian/interp.ex), ADR-0084. `Rian.Pratt` parses `"… ${e} …"` into an `SStrInterp` node;
-- | this pass (run program-wide after assembly by `Rian.Assemble.resolveInterp`) rewrites each into
-- | a plain stringify/concat chain *before* the checker and emitters see it — so there is no Core
-- | node and no per-emitter `SStrInterp` handling. Each hole is stringified by its statically
-- | inferred type (interpolation is monomorphic per call site, ADR-0069 §4):
-- |
-- |   * `String`            → the value itself (identity)
-- |   * `Int`/`Int*`/`UInt*`→ `__prim_int_to_string(value)`
-- |   * `Bool`              → `if value do "true" else "false" end`
-- |   * `Char`              → `__prim_char_to_string(value)`
-- |   * `Float64`           → `Show.float(value)` (the portable formatter; `Rian.ShowStdlib`)
-- |   * `Symbol`            → `__prim_to_string(value)` (a BEAM atom's name)
-- |   * a user type with an `impl Show` → `show(value)`
-- |
-- | A genuine `:unknown`/`:infer`/`Any` value falls through to runtime `__prim_to_string` (the
-- | checker's "infer `:unknown`, error only on a provable mismatch" contract, ADR-0069 §2); a
-- | `_Unk` transpiler-draft marker is deferred (passed through unchanged). A determined
-- | non-stringifiable type (`Float32`, a user type with no `impl Show`) is a hard error at the hole.
module Rian.Interp
  ( resolve
  , resolveBodySexpr
  , rebake
  ) where

import Prelude

import Data.Array (concatMap, filter, foldl, snoc, unsnoc)
import Data.Enum (toEnum)
import Data.String.CodePoints (singleton) as CP
import Data.Foldable (all, elem)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as Str
import Data.String.CodeUnits (toCharArray)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Check (Env, Ic, Ty(..), emptyIc, envPut, fixedEnv, infer, tyOf, tyStr)
import Rian.Core (coreSexpr, fromExpr)
import Rian.Macro (mapNode)
import Rian.Pratt (IPart(..), Pat(..), Stmt(..), Surface(..), parseBody) as P
import Rian.Prim (normalize)

-- | Rewrite every `SStrInterp` in a surface tree to a stringify/concat chain. `show` is the set of
-- | type names with an `impl Show` in the program (a hole of such a type lowers to `show(value)`).
resolve :: Env -> Ic -> Array String -> P.Surface -> P.Surface
resolve env ic show node = case node of
  P.SStrInterp parts -> concatChain (map (resolvePart env ic show) parts)

  -- scope-aware descent (ADR-0069 §4): a hole inside a `case` arm must see the arm's bound names
  -- typed, or it degrades to `:unknown`. Each arm pattern binds against the scrutinee's type.
  P.SCase scrut arms ->
    let
      scrut2 = resolve env ic show scrut
      st = infer (fromExpr (normalize scrut2)) env ic
      arm a =
        let env2 = foldl (\e (Tuple k v) -> envPut k v e) env (patBindings a.pat st)
        in a { guard = map (resolve env2 ic show) a.guard, body = resolve env2 ic show a.body }
    in
      P.SCase scrut2 (map arm arms)

  -- a block extends the env for the statements that follow each `:=` bind.
  P.SBlock stmts ->
    let
      step (Tuple acc e) stmt = case stmt of
        P.StBind n ex ->
          let ex2 = resolve e ic show ex
          in Tuple (snoc acc (P.StBind n ex2)) (envPut n (infer (fromExpr (normalize ex2)) e ic) e)
        P.StTypedBind n t ex -> Tuple (snoc acc (P.StTypedBind n t (resolve e ic show ex))) (envPut n (tyOf t) e)
        P.StExpr ex -> Tuple (snoc acc (P.StExpr (resolve e ic show ex))) e
        P.StBindArrow n ex -> Tuple (snoc acc (P.StBindArrow n (resolve e ic show ex))) e
        P.StBindPat p ex -> Tuple (snoc acc (P.StBindPat p (resolve e ic show ex))) e
    in
      P.SBlock (fst (foldl step (Tuple [] env) stmts))

  other -> mapNode (resolve env ic show) other
  where
  fst (Tuple a _) = a

-- a literal segment passes through; a hole resolves any nested interpolation, then stringifies by
-- the resolved expression's statically inferred type.
resolvePart :: Env -> Ic -> Array String -> P.IPart -> P.Surface
resolvePart _ _ _ (P.ILit s) = P.SStr s
resolvePart env ic show (P.IHole e) =
  let e2 = resolve env ic show e
  in case bakeConst e2 of
    Just s -> P.SStr s
    Nothing -> stringify show (infer (fromExpr (normalize e2)) env ic) e2

-- a hole that is now a CONSTANT literal (ADR-0046 auto-fold turned `${2 + 3 * 4}` into `${14}`) is
-- stringified at COMPILE time + baked into the template; `concatChain` merges it into the neighbouring
-- text (`"calc = ${2 + 3 * 4}"` → the single literal `"calc = 14"`). Int/Bool/Char are unambiguous;
-- Float is NOT baked — it needs the `Show.float` formatter. Mirrors `Rian.Interp.bake_const`.
bakeConst :: P.Surface -> Maybe String
bakeConst (P.SNum n) =
  let clean = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n
  in
    if Str.contains (Str.Pattern ".") clean || Str.contains (Str.Pattern "e") clean || Str.contains (Str.Pattern "E") clean then Nothing
    else Just clean
bakeConst (P.SId "true") = Just "true"
bakeConst (P.SId "false") = Just "false"
bakeConst (P.SChar cp) = map CP.singleton (toEnum cp)
bakeConst _ = Nothing

stringify :: Array String -> Ty -> P.Surface -> P.Surface
stringify show ty expr = case ty of
  TName "String" -> expr
  TName "Bool" -> P.SIf expr (blk "true") (blk "false")
  TName "Symbol" -> toStr expr
  TName "_Unk" -> expr
  Unknown -> toStr expr
  TName ":infer" -> toStr expr
  TName "Any" -> toStr expr
  TName "Char" -> call "__prim_char_to_string" expr
  TName "Float64" -> P.SCall (P.SDot (P.SId "Show") "float") [ expr ]
  TName "Float32" ->
    unsafeCrashWith "interpolation of a `Float32` is not supported — widen to `Float64` (ADR-0069)"
  TName t
    | isIntType t -> call "__prim_int_to_string" expr
    | elem t show -> call "show" expr
    | otherwise -> noShow t
  other -> noShow (tyStr other)
  where
  blk s = P.SBlock [ P.StExpr (P.SStr s) ]
  call name e = P.SCall (P.SId name) [ e ]
  toStr = call "__prim_to_string"
  noShow t = unsafeCrashWith
    ("no `Show` for `" <> t <> "` — interpolation requires a statically-known stringifiable type "
      <> "(String / Int* / Bool / Float64 / Char, or a type with an `impl Show`); got `" <> t <> "`")

-- `^U?Int\d*$` — a portable two's-complement integer width (regex-free).
isIntType :: String -> Boolean
isIntType t =
  case Str.stripPrefix (Str.Pattern "Int") (fromMaybe t (Str.stripPrefix (Str.Pattern "U") t)) of
    Just rest -> all (\c -> c >= '0' && c <= '9') (toCharArray rest)
    _ -> false

-- join the resolved parts into one string. Empty string literals are dropped (identity for
-- concatenation); ≥2 parts lower to one `__prim_str_concat_all` (a single allocation), one part is
-- the value itself, none is `""`.
concatChain :: Array P.Surface -> P.Surface
concatChain parts = case filter (not <<< isEmptyStr) (mergeStrs parts) of
  [] -> P.SStr ""
  [ only ] -> only
  kept -> P.SCall (P.SId "__prim_str_concat_all") kept
  where
  isEmptyStr (P.SStr "") = true
  isEmptyStr _ = false

-- fold consecutive string-literal parts into one — so a compile-time-baked constant hole merges with
-- the surrounding text into a single literal (`"calc = " <> "14"` → `"calc = 14"`). Mirrors `merge_strs`.
mergeStrs :: Array P.Surface -> Array P.Surface
mergeStrs = foldl step []
  where
  step acc (P.SStr b) = case unsnoc acc of
    Just { init, last: P.SStr a } -> snoc init (P.SStr (a <> b))
    _ -> snoc acc (P.SStr b)
  step acc part = snoc acc part

-- | Finish the interpolation bake AFTER post-check inlining (ADR-0046 §5) — the PS twin of
-- | `Rian.Interp.rebake`. A hole inlining just made constant (`${sq(2, 3)}` →
-- | `__prim_int_to_string(25)`) is re-baked to `"25"` and merged into the concat, so the playground
-- | emits the single literal `"sq(2, 3) = 25"`. SCOPED to the interpolation prims it emits — never an
-- | arbitrary `<>` / runtime concatenation (boundary A). Idempotent.
rebake :: P.Surface -> P.Surface
rebake (P.SCall (P.SId "__prim_int_to_string") [ arg ]) = case rebake arg of
  n@(P.SNum _) -> case bakeConst n of
    Just s -> P.SStr s
    Nothing -> P.SCall (P.SId "__prim_int_to_string") [ n ]
  other -> P.SCall (P.SId "__prim_int_to_string") [ other ]
rebake (P.SCall (P.SId "__prim_char_to_string") [ arg ]) = case rebake arg of
  c@(P.SChar _) -> case bakeConst c of
    Just s -> P.SStr s
    Nothing -> P.SCall (P.SId "__prim_char_to_string") [ c ]
  other -> P.SCall (P.SId "__prim_char_to_string") [ other ]
rebake (P.SCall (P.SId "__prim_str_concat_all") parts) = concatChain (map rebake parts)
rebake node = mapNode rebake node

-- the names a `case`-arm pattern introduces, typed for interpolation: a bare variable binds the
-- whole scrutinee type; an `@`-alias binds likewise; any destructuring var binds `:unknown` (its
-- component type is not recovered here — a hole over one still defers, no worse than before).
patBindings :: P.Pat -> Ty -> Array (Tuple String Ty)
patBindings (P.PVar x) st = [ Tuple x st ]
patBindings (P.PAs x p) st = snoc (patBindings p Unknown) (Tuple x st)
patBindings (P.PTuple ps) _ = concatMap (\p -> patBindings p Unknown) ps
patBindings (P.PListP ps tl) _ = concatMap (\p -> patBindings p Unknown) ps <> maybe [] (\t -> patBindings t Unknown) tl
patBindings (P.PCtor _ args) _ = concatMap (\p -> patBindings p Unknown) args
patBindings (P.PStruct _ fields) _ = concatMap (\(Tuple _ p) -> patBindings p Unknown) fields
patBindings _ _ = []

-- | `itp` parity entry: resolve a function body under the fixed env (no program ic, no `Show` impls),
-- | then serialize through Core (`coreSexpr`) — mirrors the `inf`/`bdy`/`cor` streams' setup, and
-- | confirms the resolved surface lowers (no `SStrInterp` survives).
resolveBodySexpr :: String -> String
resolveBodySexpr src = coreSexpr (fromExpr (resolve fixedEnv emptyIc [] (P.parseBody src)))
