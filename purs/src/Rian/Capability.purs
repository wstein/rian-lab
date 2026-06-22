-- | Capability lowering — the PureScript port of `Rian.Capability` (lib/rian/capability.ex),
-- | ADR-0025/0055/0061 / ADR-0084. Two concerns:
-- |
-- |   * **Rust signature lowering** (`rustParam`): capability + type → the Rust parameter
-- |     spelling (`val Vec(T)` → `&[T]`, `iso String` → `String`, `ref T` → `&mut <owned>`,
-- |     a `Fn(...)` callback → `&impl Fn(...)`, …) — pure string transforms over the type.
-- |   * **BEAM linearity** (`countUses`/`linCheck`): no borrow checker on the BEAM, so an
-- |     `iso`/`ref` binding may be used at most once along any path. `countUses` is the
-- |     branch-aware (max over `if`/`case` arms) free-variable occurrence count.
-- |
-- | Parity: `cap` stream (rustParam over a `cap type` table) + `lin` stream (countUses over an
-- | expression, serialized as sorted `name:count`). `split_top_commas` trims in the reference,
-- | so parts feeding `owned` are trimmed here too.
module Rian.Capability
  ( rustParam
  , owned
  , borrowed
  , copy
  , countUses
  , rustParamSexpr
  , countUsesSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (all, elem, foldl)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String (Pattern(..), drop, indexOf, stripPrefix, stripSuffix, take) as Str
import Data.String.Common (joinWith, trim)
import Data.String.CodePoints as CP
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.IR (Cap(..))
import Rian.Pratt (MapPair(..), Pat(..), Stmt(..), Surface(..), parse) as P
import Rian.TypeStr (splitTopCommas)

-- the width-explicit Copy scalars (Int*/UInt*/Float*) + Bool/Char (ADR-0033); not String/Symbol.
copyTypes :: Array String
copyTypes =
  Array.concatMap (\p -> map (\w -> p <> w) [ "8", "16", "32", "64", "128" ]) [ "Int", "UInt" ]
    <> [ "Int53", "Float32", "Float64", "Bool", "Char" ]

-- @rian_sig pub def copy?(t val String) Bool
copy :: String -> Boolean
copy t = elem t copyTypes

-- ── Rust parameter-type lowering ──
-- @rian_sig pub def rust_param(a val Symbol, t val String) String
rustParam :: Cap -> String -> String
rustParam cap t =
  if isJustPrefix "Fn(" t then "&impl " <> fnTrait t
  else case cap of
    Iso -> owned t
    Val -> if copy t then rustName t else borrowed t
    Ref -> "&mut " <> owned t
    Tag -> "&" <> owned t

-- `Fn(A.., R)` (last component is the return) → the Rust `Fn(A..) -> R` trait spelling.
fnTrait :: String -> String
fnTrait t =
  case splitTopCommas (chopParen (afterPrefix "Fn(" t)) of
    [] -> "Fn()"
    parts -> case Array.unsnoc parts of
      Just { init: args, last: ret } ->
        "Fn(" <> joinWith ", " (map ownedTrim args) <> ") -> " <> ownedTrim ret
      Nothing -> "Fn()"

rustName :: String -> String
rustName t = if copy t then rustScalar t else t

-- a Copy scalar's Rust spelling (`Int53` → `i64`, `Int64` → `i64`, `UInt8` → `u8`, …).
rustScalar :: String -> String
rustScalar t =
  if t == "Int53" then "i64"
  else if t == "Bool" then "bool"
  else if t == "Char" then "char"
  else case Str.stripPrefix (Str.Pattern "UInt") t of
    Just w -> "u" <> w
    Nothing -> case Str.stripPrefix (Str.Pattern "Int") t of
      Just w -> "i" <> w
      Nothing -> case Str.stripPrefix (Str.Pattern "Float") t of
        Just w -> "f" <> w
        Nothing -> t

-- @rian_sig pub def owned(a val String) String
owned :: String -> String
owned t =
  if t == "String" then "String"
  else if t == "Symbol" then "String"
  else if t == "Int" then unsafeCrashWith intNoRust
  else if isJustPrefix "Fn(" t then "Box<dyn " <> fnTrait t <> ">"
  else if isJustPrefix "(" t then ownedTuple t
  else if isJustPrefix "Vec(" t then "Vec<" <> ownedTrim (chopParen (afterPrefix "Vec(" t)) <> ">"
  else if isJustPrefix "Map(" t then ownedMap t
  else ownedFallback t

intNoRust :: String
intNoRust =
  "`Int` (arbitrary precision, ADR-0064) has no Rust lowering yet — it needs a bignum; "
    <> "use a fixed width (`Int64`) on Rust, or target the BEAM/JS"

ownedTuple :: String -> String
ownedTuple t =
  case Str.stripSuffix (Str.Pattern ")") t of
    Just _ -> "(" <> joinWith ", " (map ownedTrim (splitTopCommas (chopParen (afterPrefix "(" t)))) <> ")"
    Nothing -> rustName t

ownedMap :: String -> String
ownedMap t =
  "std::collections::HashMap<" <> joinWith ", " (map ownedTrim (splitTopCommas (chopParen (afterPrefix "Map(" t)))) <> ">"

ownedFallback :: String -> String
ownedFallback t = case parametric t of
  Just (Tuple name args) -> name <> "<" <> joinWith ", " (map ownedTrim args) <> ">"
  Nothing -> rustName t

ownedTrim :: String -> String
ownedTrim t = owned (trim t)

-- `Name(A, B, …)` → `{name, [A, B, …]}` (name an identifier), else `Nothing`.
parametric :: String -> Maybe (Tuple String (Array String))
parametric t = case Str.stripSuffix (Str.Pattern ")") t of
  Nothing -> Nothing
  Just body -> case Str.indexOf (Str.Pattern "(") body of
    Nothing -> Nothing
    Just i ->
      let name = Str.take i body
      in if name /= "" && isIdent name then Just (Tuple name (splitTopCommas (Str.drop (i + 1) body))) else Nothing

-- @rian_sig pub def borrowed(a val String) String
borrowed :: String -> String
borrowed t =
  if t == "String" then "&str"
  else if t == "Symbol" then "&str"
  else if isJustPrefix "Vec(" t then "&[" <> ownedTrim (chopParen (afterPrefix "Vec(" t)) <> "]"
  else if isJustPrefix "Map(" t then "&" <> owned t
  else "&" <> rustName t

-- ── string helpers ──
afterPrefix :: String -> String -> String
afterPrefix pre t = fromMaybe t (Str.stripPrefix (Str.Pattern pre) t)

chopParen :: String -> String
chopParen s = fromMaybe s (Str.stripSuffix (Str.Pattern ")") s)

isJustPrefix :: String -> String -> Boolean
isJustPrefix pre t = isJust (Str.stripPrefix (Str.Pattern pre) t)

-- an `[A-Za-z_]\w*` identifier: a letter/underscore start, then word chars.
isIdent :: String -> Boolean
isIdent s = case Array.head cps of
  Nothing -> false
  Just h -> identStart h && all wordCp cps
  where
  cps = CP.toCodePointArray s
  identStart cp = letterCp cp || cp == CP.codePointFromChar '_'
  wordCp cp = letterCp cp || digitCp cp || cp == CP.codePointFromChar '_'
  letterCp cp = (cp >= CP.codePointFromChar 'A' && cp <= CP.codePointFromChar 'Z') || (cp >= CP.codePointFromChar 'a' && cp <= CP.codePointFromChar 'z')
  digitCp cp = cp >= CP.codePointFromChar '0' && cp <= CP.codePointFromChar '9'

-- ── BEAM linearity: free-variable occurrence counts ──
type Uses = Array (Tuple String Int)

-- @rian_sig pub def count_uses(ast val Expr) _Unk
countUses :: P.Surface -> Uses
countUses = go []

-- `bound` names shadow the outer linear environment (lambda params, block binds, arm pats).
go :: Array String -> P.Surface -> Uses
go bound (P.SId x) = if elem x bound then [] else [ Tuple x 1 ]
go bound (P.SDot head _) = go bound head
go bound (P.SCapture body) = go bound body
go bound (P.SCaptureNamed path _) = go bound path
go bound (P.SUnary _ x) = go bound x
go bound (P.SBin _ l r) = merge (go bound l) (go bound r)
go bound (P.SCall f args) = foldl (\acc n -> merge acc (go bound n)) [] ([ f ] <> args)
go bound (P.SListLit elems tail) =
  merge (foldl (\acc e -> merge acc (go bound e)) [] elems) (maybe' (map (go bound) tail))
go bound (P.SMapLit pairs) = foldl (\acc p -> merge acc (go bound (pairVal p))) [] pairs
go bound (P.SLambda params body) = go (bound <> map _.name params) body
go bound (P.SIf c t e) = merge (go bound c) (maxMerge (go bound t) (go bound e))
go bound (P.SCase scrut arms) = merge (go bound scrut) (foldl maxMerge [] (map armUses arms))
  where
  armUses a =
    let inner = bound <> patVars a.pat
    in merge (maybe' (map (go inner) a.guard)) (go inner a.body)
go bound (P.SBlock stmts) = countBlock bound [] stmts
go _ _ = [] -- num/str/char/atom/cap_arg + (by reference design) any node the reference omits

pairVal :: P.MapPair -> P.Surface
pairVal (P.MAtom _ v) = v
pairVal (P.MKey _ v) = v

countBlock :: Array String -> Uses -> Array P.Stmt -> Uses
countBlock bound acc stmts = case Array.uncons stmts of
  Nothing -> acc
  Just { head: s, tail } -> case s of
    P.StBind n e -> countBlock (bound <> [ n ]) (merge acc (go bound e)) tail
    P.StTypedBind n _ e -> countBlock (bound <> [ n ]) (merge acc (go bound e)) tail
    P.StBindArrow n e -> countBlock (bound <> [ n ]) (merge acc (go bound e)) tail
    P.StBindPat p e -> countBlock (bound <> patVars p) (merge acc (go bound e)) tail
    P.StExpr e -> countBlock bound (merge acc (go bound e)) tail

-- variables a pattern binds (only var + ctor, mirroring the reference's `pat_vars`).
patVars :: P.Pat -> Array String
patVars (P.PVar x) = [ x ]
patVars (P.PCtor _ args _) = Array.concatMap patVars args
patVars _ = []

maybe' :: Maybe Uses -> Uses
maybe' = fromMaybe []

merge :: Uses -> Uses -> Uses
merge = combine (+)

maxMerge :: Uses -> Uses -> Uses
maxMerge = combine max

combine :: (Int -> Int -> Int) -> Uses -> Uses -> Uses
combine f a b = foldl step a b
  where
  step acc (Tuple k n) = case Array.findIndex (\(Tuple k2 _) -> k2 == k) acc of
    Just i -> fromMaybe acc (Array.modifyAt i (\(Tuple k2 m) -> Tuple k2 (f m n)) acc)
    Nothing -> acc <> [ Tuple k n ]

-- ── parity entries ──
-- | `cap` stream: `rustParam` over a `<cap> <type>` input (`val Vec(Int64)` → `&[i64]`).
rustParamSexpr :: String -> String
rustParamSexpr s = case Str.indexOf (Str.Pattern " ") s of
  Just i -> rustParam (capOf (Str.take i s)) (Str.drop (i + 1) s)
  Nothing -> "?"
  where
  capOf "iso" = Iso
  capOf "ref" = Ref
  capOf "tag" = Tag
  capOf _ = Val

-- | `lin` stream: `countUses` of a parsed expression, serialized as sorted `name:count`.
countUsesSexpr :: String -> String
countUsesSexpr src =
  joinWith ";" (map (\(Tuple k n) -> k <> ":" <> show n) (Array.sortWith fst (countUses (P.parse src))))
