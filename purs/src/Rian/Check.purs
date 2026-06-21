-- | Type checking (ADR-0034) — the PureScript port of `Rian.Check` (lib/rian/check.ex),
-- | ADR-0084. **Stage 1: the type algebra** — the two lattice kernels every later pass is
-- | built on:
-- |
-- |   * `unify` — equal → itself, `Unknown` → the other, `Any` → the other, `Fn(…)`
-- |     structurally (componentwise), else `Mismatch`. This is the "match a partial
-- |     inference against a declaration" join, where `Unknown` is a *wildcard*.
-- |   * `join` — the least-upper-bound for branch/arm/element types (the arms of an `if`/
-- |     `case`, the elements of a list). Here `Unknown` is *absorbing* (top), `Bottom` is
-- |     the fold identity, `Any` absorbs, and `_Unk` defers. Numeric widths join to their
-- |     LUB over the `⊑` widening order; same-constructor parametric types join covariantly.
-- |
-- | `infer`/`annotate`/the error-set fixpoint/the program gates land in later stages (they
-- | consume the inference context + the whole-program call graph). The Elixir `ty` is a
-- | `String | :unknown | :mismatch | :bottom`; here it is a real sum (`Ty`) — the
-- | "reframe, not lift" the migration calls for (a name string vs the three sentinels).
module Rian.Check
  ( Ty(..)
  , tyStr
  , tyOf
  , unify
  , join
  , Env
  , infer
  , unifySexpr
  , joinSexpr
  , inferSexpr
  , inferBodySexpr
  ) where

import Prelude hiding (join)

import Data.Array (filter, find, foldl, head, last, length, nubEq, null, snoc, uncons, zip, zipWith)
import Data.Foldable (all, any, elem)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as Str
import Data.String.CodeUnits (toCharArray)
import Data.String.Common (joinWith, replaceAll, split)
import Data.Tuple (Tuple(..), snd)
import Rian.Builtins as Builtins
import Rian.Core (CExpr(..), CMapPair(..), CStmt(..), fromExpr)
import Rian.Pratt (Param, parse, parseBody) as P
import Rian.Prim (normalize)
import Rian.TypeStr (splitTopCommas)

-- | An inferred type: a type-name string (`"Int53"`, `"Fn(_,Int64)"`, `"Vec(Int53)"`), or
-- | one of the three sentinels — `Unknown` (`:unknown`, an unfinished inference hole),
-- | `Mismatch` (a proven clash), `Bottom` (`:bottom`, the join identity / empty branch set).
data Ty = TName String | Unknown | Mismatch | Bottom

derive instance Eq Ty

-- | The Elixir-atom rendering of a `Ty`, for the parity oracle.
tyStr :: Ty -> String
tyStr (TName s) = s
tyStr Unknown = ":unknown"
tyStr Mismatch = ":mismatch"
tyStr Bottom = ":bottom"

-- | Read a parity-input type token back into a `Ty` (the sentinels round-trip).
tyOf :: String -> Ty
tyOf ":unknown" = Unknown
tyOf ":mismatch" = Mismatch
tyOf ":bottom" = Bottom
tyOf s = TName s

-- ── unification kernel ───────────────────────────────────────────────────────

-- | Unify two types: equal → itself; `Unknown` → the other; `Any` → the other; `Fn(…)`
-- | structurally; else `Mismatch`.
-- @rian_sig pub def unify(t val String, u val String) String
unify :: Ty -> Ty -> Ty
unify t u
  | t == u = t
unify Unknown t = t
unify t Unknown = t
unify (TName "Any") t = t
unify t (TName "Any") = t
unify (TName a) (TName b)
  | isFn a && isFn b = unifyFn a b
unify _ _ = Mismatch

-- componentwise-unify two `Fn(...)` strings; `Mismatch` on differing arity / any clash.
unifyFn :: String -> String -> Ty
unifyFn a b =
  let
    pa = fnParts a
    pb = fnParts b
  in
    if length pa == length pb then
      let parts = zipWith compUnify pa pb in
      if any (_ == Mismatch) parts then Mismatch
      else TName ("Fn(" <> joinWith "," (map tyStr parts) <> ")")
    else Mismatch

compUnify :: Ty -> Ty -> Ty
compUnify x y
  | x == y = x
  | wildcard x = y
  | wildcard y = x
  | isFnTy x && isFnTy y = unifyFn (tyStr x) (tyStr y)
  | otherwise = case numLub x y of
      Just j -> j
      Nothing -> Mismatch

-- two numeric widths reconcile to their LUB (so an inferred `Fn(_,Int53)` over literals
-- matches a declared `Fn(Int64,Int64)`); `Nothing` when they have no common width.
numLub :: Ty -> Ty -> Maybe Ty
numLub x y =
  case numKind x, numKind y of
    Just _, Just _ -> case join x y of
      Unknown -> Nothing
      t -> Just t
    _, _ -> Nothing

fnParts :: String -> Array Ty
fnParts s = map tyOf (splitTopCommas (Str.drop 3 (dropLastParen s)))

isFn :: String -> Boolean
isFn s = Str.take 3 s == "Fn("

isFnTy :: Ty -> Boolean
isFnTy (TName s) = isFn s
isFnTy _ = false

wildcard :: Ty -> Boolean
wildcard (TName "_") = true
wildcard (TName s) = isTvar s
wildcard _ = false

-- a `forall` type variable: a single uppercase letter, optionally one digit (`T`, `T1`).
isTvar :: String -> Boolean
isTvar s = case toCharArray s of
  [ c ] -> isUpper c
  [ c, d ] -> isUpper c && isDigit d
  _ -> false

-- ── join: least-upper-bound for branch/arm/element types ─────────────────────

-- | The LUB of two branch/arm/element types (ADR-0059). NOT `unify`: here `Unknown` is
-- | *absorbing* (top), `Bottom` is the identity, `Any` absorbs, `_Unk` defers.
-- @rian_sig pub def join(from val String, to val String) String
join :: Ty -> Ty -> Ty
join t u
  | t == u = t
join Bottom t = t
join t Bottom = t
join (TName "_Unk") t = t
join t (TName "_Unk") = t
join (TName "Any") _ = TName "Any"
join _ (TName "Any") = TName "Any"
join Unknown _ = Unknown
join _ Unknown = Unknown
join from to =
  case numKind from, numKind to of
    Just a, Just b -> numJoin a b
    _, _ -> parametricJoin from to

-- ── numeric LUB over the `⊑` widening order ──────────────────────────────────

data Kind = KInt | KUint | KFloat

derive instance Eq Kind

-- a numeric type name → `{kind, bits}`, or `Nothing` (a bare `Int` / non-numeric).
numKind :: Ty -> Maybe { kind :: Kind, bits :: Int }
numKind (TName s) =
  case Str.stripPrefix (Str.Pattern "UInt") s of
    Just w -> numBits KUint w
    Nothing -> case Str.stripPrefix (Str.Pattern "Int") s of
      Just w -> numBits KInt w
      Nothing -> case Str.stripPrefix (Str.Pattern "Float") s of
        Just w -> numBits KFloat w
        Nothing -> Nothing
numKind _ = Nothing

numBits :: Kind -> String -> Maybe { kind :: Kind, bits :: Int }
numBits kind w = case Int.fromString w of
  Just n -> Just { kind, bits: n }
  Nothing -> Nothing

-- The mixed-kind combinations are explicit; same-kind (`KInt`/`KInt`, …) is the final
-- catch-all (`kindPrefix k <> max width`). The cases are disjoint, so this matches the
-- Elixir order (same-kind first there) for every input.
numJoin :: { kind :: Kind, bits :: Int } -> { kind :: Kind, bits :: Int } -> Ty
numJoin { kind: KUint, bits: a } { kind: KInt, bits: b } = uintSignedJoin a b
numJoin { kind: KInt, bits: a } { kind: KUint, bits: b } = uintSignedJoin b a
numJoin { kind: KInt, bits: a } { kind: KFloat, bits: b } = intFloatJoin (a - 1) b
numJoin { kind: KFloat, bits: b } { kind: KInt, bits: a } = intFloatJoin (a - 1) b
numJoin { kind: KUint, bits: a } { kind: KFloat, bits: b } = intFloatJoin a b
numJoin { kind: KFloat, bits: b } { kind: KUint, bits: a } = intFloatJoin a b
numJoin a b = TName (kindPrefix a.kind <> show (max a.bits b.bits))

intWidths :: Array Int
intWidths = [ 8, 16, 32, 64, 128 ]

floatWidths :: Array Int
floatWidths = [ 32, 64 ]

-- `UIntₐ ⊔ Int_b` = least Int width strictly wider than `a` and at least `b`.
uintSignedJoin :: Int -> Int -> Ty
uintSignedJoin u i = case find (\c -> c > u && c >= i) intWidths of
  Just c -> TName ("Int" <> show c)
  Nothing -> Unknown

intFloatJoin :: Int -> Int -> Ty
intFloatJoin exactBits fb = case find (\c -> c >= fb && floatMantissa c >= exactBits) floatWidths of
  Just c -> TName ("Float" <> show c)
  Nothing -> Unknown

floatMantissa :: Int -> Int
floatMantissa 64 = 53
floatMantissa 32 = 24
floatMantissa _ = 0

kindPrefix :: Kind -> String
kindPrefix KInt = "Int"
kindPrefix KUint = "UInt"
kindPrefix KFloat = "Float"

-- ── parametric (same-constructor covariant) join ─────────────────────────────

parametricJoin :: Ty -> Ty -> Ty
parametricJoin from to
  | isFnTy from || isFnTy to = Unknown
parametricJoin from to =
  case parseParametric from, parseParametric to of
    Just f, Just t
      | f.name == t.name && length f.args == length t.args ->
          let parts = zipWith join f.args t.args in
          if any (_ == Unknown) parts then Unknown
          else TName (f.name <> "(" <> joinWith "," (map tyStr parts) <> ")")
    _, _ -> Unknown

-- `Name(a, b)` → `{name, [a, b]}` (the outer constructor + its top-level args).
parseParametric :: Ty -> Maybe { name :: String, args :: Array Ty }
parseParametric (TName s) =
  case Str.indexOf (Str.Pattern "(") s of
    Just i ->
      let
        name = Str.take i s
        rest = Str.drop (i + 1) s
      in
        case Str.stripSuffix (Str.Pattern ")") rest of
          Just inner | isIdent name -> Just { name, args: map tyOf (splitTopCommas inner) }
          _ -> Nothing
    Nothing -> Nothing
parseParametric _ = Nothing

-- ── small string helpers ─────────────────────────────────────────────────────

-- drop the trailing `)` of a well-formed `Fn(...)` / `Name(...)` before splitting args.
dropLastParen :: String -> String
dropLastParen s = case Str.stripSuffix (Str.Pattern ")") s of
  Just t -> t
  Nothing -> s

-- `^[A-Za-z_]\w*$` — an identifier (a constructor name).
isIdent :: String -> Boolean
isIdent s = case uncons (toCharArray s) of
  Nothing -> false
  Just r -> isIdentStart r.head && all isWord r.tail

isIdentStart :: Char -> Boolean
isIdentStart c = isUpper c || isLower c || c == '_'

isWord :: Char -> Boolean
isWord c = isIdentStart c || isDigit c

isUpper :: Char -> Boolean
isUpper c = c >= 'A' && c <= 'Z'

isLower :: Char -> Boolean
isLower c = c >= 'a' && c <= 'z'

isDigit :: Char -> Boolean
isDigit c = c >= '0' && c <= '9'

-- ── inference (stage 2: the expression core) ─────────────────────────────────
-- | A per-scope variable environment: name → inferred type. Modelled as an association
-- | list (no `Data.Map` in the purerl set), like the rest of the port.
type Env = Array (Tuple String Ty)

-- | Infer the type of an expression under `env`; `Unknown` when unsure. This stage covers
-- | the pure expression core (literals, vars, unary/binary ops, list/tuple/map literals).
-- | `if`/`case` (branch-join + value unions), lambdas, calls/generics, `.field`, atoms, and
-- | the inference context (`ic` — ctors/fsigs/abstract ops) arrive in later stages, so those
-- | nodes defer to `Unknown` here (the conservative slice never over-claims).
-- @rian_sig pub def infer(ast val Expr, env val Dict(String, String)) String
infer :: CExpr -> Env -> Ty
infer (ENum n) _ = if hasDotOrE n then TName "Float64" else TName "Int53"
infer (EStr _) _ = TName "String"
infer (EChar _) _ = TName "Char"
infer (EId "true") _ = TName "Bool"
infer (EId "false") _ = TName "Bool"
infer (EId x) env = fromMaybe Unknown (envLookup x env)
infer (EUnary "-" x) env = infer x env
infer (EUnary "not" _) _ = TName "Bool"
infer (EBin op l r) env = inferBin op l r env
infer (EList elems tail) env = inferList elems tail env
infer (ETuple elems) env = inferTuple elems env
infer (EMap pairs) env = inferMap pairs env
-- `if`'s value is the LUB-join of its two arms (a value union when they don't share an LUB).
-- The arms are `do`/`else` blocks, so each is an `EBlock` whose value is its last statement.
infer (EIf _ t e) env = branchJoin [ Tuple t (infer t env), Tuple e (infer e env) ]
-- a lambda `(a, b) -> body` infers the arrow type `Fn(a_t.., body_t)`.
infer (ELambda ps body) env = inferLambda ps body env
infer (EBlock stmts) env = inferBlock stmts env Unknown
-- a `with` yields its do-block value on the happy path (clause-bound vars infer `Unknown`).
infer (EWith _ body _) env = infer body env
-- prim intrinsics (after `Rian.Prim.normalize` rewrote `Prim.x`/`panic` to `__prim_x`).
infer (ECall (EId "__prim_char_code") _) _ = TName "Int53"
infer (ECall (EId "__prim_int_to_float") _) _ = TName "Float64"
infer (ECall (EId "__prim_str_to_atom") _) _ = TName "Symbol"
infer (ECall (EId "__prim_str_concat_all") _) _ = TName "String"
infer (ECall (EId "__prim_char_to_string") _) _ = TName "String"
infer (ECall (EId "__prim_panic") _) _ = Unknown
-- `inspect/1` is the host value→text function: always `String`.
infer (ECall (EId "inspect") [ _ ]) _ = TName "String"
-- a bare call: a `Fn`-typed var applied → its return; else a Kernel auto-import builtin.
infer (ECall (EId f) args) env = case envLookup f env of
  Just ft | isFnTy ft -> fnRet ft
  _ -> builtinOrUnknown Nothing f (length args)
-- a ZERO-arg dot-call is the `abstract`-cast position (`m.base()`): with no inference context
-- there is no declared cast, so it is `Unknown` — and this intercepts a zero-arg `Mod.fun()`
-- (e.g. `Map.new()`) before the builtin clause, matching the reference's clause order.
infer (ECall (EDot _ _) []) _env = Unknown
-- a module call `Mod.fun(args)`: a host/stdlib builtin's return, or a fixed-head poly stdlib
-- call (`List.map`) instantiated from the argument types.
infer (ECall (EDot (EId modn) fn) args) env = case Builtins.polySig (Just modn) fn (length args) of
  -- a fixed-head polymorphic stdlib call (`List.reverse` → `Vec(…)`): instantiate its tvars
  -- from the argument types, `Any`-filling any that can't bind.
  Just sig -> instantiateLax sig (map (\a -> infer a env) args)
  Nothing -> builtinOrUnknown (Just modn) fn (length args)
-- an Erlang-BIF FFI call `:erlang.phash2(x)` — typed from the foreign registry.
infer (ECall (EDot (EAtom modn) fn) args) _ = builtinOrUnknown (Just modn) fn (length args)
-- any other callable (a lambda result, a returned function): its return when it is known
-- to be a function, else `Unknown`.
infer (ECall fn _) env = let ft = infer fn env in if isFnTy ft then fnRet ft else Unknown
infer _ _ = Unknown

builtinOrUnknown :: Maybe String -> String -> Int -> Ty
builtinOrUnknown m f a = maybe Unknown TName (Builtins.ret m f a)

-- instantiate a fixed-head poly signature `{params, ret, tvars}` against the inferred
-- argument types: bind each tvar from the args, then substitute it in `ret` (`Any` when
-- unbound). "Lax" — a tvar nested in an `Fn(…)` param is not unified (it stays `Any`).
instantiateLax :: Builtins.PolySig -> Array Ty -> Ty
instantiateLax sig argTypes =
  let subs = foldl (\acc (Tuple param arg) -> bindTvar param arg sig.tvars acc) [] (zip sig.params argTypes) in
  TName (foldl (\r tv -> replaceAll (Str.Pattern tv) (Str.Replacement (lookupSub tv subs)) r) sig.ret sig.tvars)
  where
  lookupSub tv subs = fromMaybe "Any" (map snd (find (\(Tuple k _) -> k == tv) subs))

-- extract `tvar → concrete` bindings by matching a param's declared type against the inferred
-- argument type: a bare tvar binds directly; `Vec(T)` vs `Vec(A)` recurses; else nothing.
-- First binding wins (`Map.put_new`).
bindTvar :: String -> Ty -> Array String -> Array (Tuple String String) -> Array (Tuple String String)
bindTvar _ Unknown _ acc = acc
bindTvar param (TName arg) tvars acc
  | param `elem` tvars = if any (\(Tuple k _) -> k == param) acc then acc else snoc acc (Tuple param arg)
  | isVecOf param && isVecOf arg = bindTvar (vecInner param) (TName (vecInner arg)) tvars acc
  | otherwise = acc
bindTvar _ _ _ acc = acc

isVecOf :: String -> Boolean
isVecOf s = Str.take 4 s == "Vec("

vecInner :: String -> String
vecInner s = fromMaybe s (Str.stripSuffix (Str.Pattern ")") (Str.drop 4 s))

-- the return type of a `Fn(A.., R)` (the last component; a `_` placeholder → `Unknown`).
fnRet :: Ty -> Ty
fnRet (TName s) = case last (fnParts s) of
  Just (TName "_") -> Unknown
  Just t -> t
  Nothing -> Unknown
fnRet _ = Unknown

-- block-statement threading: a bind extends the env and becomes the running value; the
-- block's type is its last statement's.
inferBlock :: Array CStmt -> Env -> Ty -> Ty
inferBlock stmts env value = case uncons stmts of
  Nothing -> value
  Just { head: CBind n e, tail: rest } -> let t = infer e env in inferBlock rest (envPut n t env) t
  Just { head: CTypedBind n t _, tail: rest } -> inferBlock rest (envPut n (TName t) env) (TName t)
  Just { head: CExprStmt e, tail: rest } -> inferBlock rest env (infer e env)

envLookup :: String -> Env -> Maybe Ty
envLookup k = map snd <<< find (\(Tuple k' _) -> k' == k)

envPut :: String -> Ty -> Env -> Env
envPut k v env = snoc (filter (\(Tuple k' _) -> k' /= k) env) (Tuple k v)

-- ── binary operators ─────────────────────────────────────────────────────────

boolOps :: Array String
boolOps = [ "<", "<=", ">", ">=", "==", "!=", "and", "or", "in" ]

intOps :: Array String
intOps = [ "div", "rem" ]

arithOps :: Array String
arithOps = [ "+", "-", "*" ]

inferBin :: String -> CExpr -> CExpr -> Env -> Ty
inferBin op l r env =
  let
    lt = infer l env
    rt = infer r env
  in
    -- (abstract-operator resolution needs the inference context; empty here, so it falls
    -- through to the default arithmetic rules — a later stage threads `ic`.)
    if op `elem` boolOps then TName "Bool"
    else if op == "<>" then TName "String"
    else if op == "/" then TName "Float64"
    else if op `elem` intOps || op `elem` arithOps then arithType l r lt rt
    else Unknown

-- Arithmetic result type: an integer *literal* operand is width-flexible (adopts a concrete
-- same-kind neighbour), so `typed op literal` keeps the typed width; else the two ordinal
-- bases unify (`Char` widens to `Int53`). A proven clash is conservatively `Unknown`.
arithType :: CExpr -> CExpr -> Ty -> Ty -> Ty
arithType l r lt rt
  | intLitExpr l && adoptableInt rt = ordinalBase rt
  | intLitExpr r && adoptableInt lt = ordinalBase lt
  | otherwise = conservative (unify (ordinalBase lt) (ordinalBase rt))

adoptableInt :: Ty -> Boolean
adoptableInt = intType

-- `Char ± _` widens to its `Int53` ordinal base (`'9' - '0' = 9 ∉ Char`, ADR-0036).
ordinalBase :: Ty -> Ty
ordinalBase (TName "Char") = TName "Int53"
ordinalBase t = t

-- `^U?Int\d*$` — a (possibly bare) signed/unsigned integer type name.
intType :: Ty -> Boolean
intType (TName s) =
  case Str.stripPrefix (Str.Pattern "Int") (fromMaybe s (Str.stripPrefix (Str.Pattern "U") s)) of
    Just rest -> all isDigit (toCharArray rest)
    Nothing -> false
intType _ = false

-- an integer-literal expression (a literal, a negation of one, or arithmetic over them) —
-- the operand that adopts its neighbour's width.
intLitExpr :: CExpr -> Boolean
intLitExpr (ENum t) = intLiteral t
intLitExpr (EUnary "-" a) = intLitExpr a
intLitExpr (EBin op l r) | op `elem` arithOps || op `elem` intOps = intLitExpr l && intLitExpr r
intLitExpr _ = false

intLiteral :: String -> Boolean
intLiteral n = not (hasDotOrE n)

-- ── list / tuple / map literals ──────────────────────────────────────────────

inferList :: Array CExpr -> Maybe CExpr -> Env -> Ty
inferList elems tail env =
  let
    elemT = debottom (foldl (\acc e -> join (infer e env) acc) Bottom elems)
    te = listElem (inferTail tail env)
  in
    if te == Unknown || te == elemT then listOf (conservative elemT) else Unknown

inferTail :: Maybe CExpr -> Env -> Ty
inferTail Nothing _ = Unknown
inferTail (Just t) env = infer t env

listElem :: Ty -> Ty
listElem (TName s) = case Str.stripPrefix (Str.Pattern "Vec(") s of
  Just rest -> TName (fromMaybe rest (Str.stripSuffix (Str.Pattern ")") rest))
  Nothing -> Unknown
listElem _ = Unknown

listOf :: Ty -> Ty
listOf (TName t) = TName ("Vec(" <> t <> ")")
listOf _ = TName "Vec(Any)"

-- a tuple literal infers its structural shape `(Ta,Tb,…)` — an unpinnable element defers to
-- `Any`. An ATOM-tagged tuple (`{:ok, v}`) is a tagged sum value, not a raw tuple → `Unknown`.
inferTuple :: Array CExpr -> Env -> Ty
inferTuple elems env = case head elems of
  Just (EAtom _) -> Unknown
  _ -> TName ("(" <> joinWith "," (map (\e -> tyStr (conservativeUnk (infer e env))) elems) <> ")")

-- a `%{…}` literal infers `Dict(KeyT,ValT)` — key/value types each LUB-join across the pairs.
inferMap :: Array CMapPair -> Env -> Ty
inferMap pairs env =
  let
    kt = joinAll (map (inferMapKey env) pairs)
    vt = joinAll (map (\p -> infer (mapVal p) env) pairs)
  in
    TName ("Dict(" <> tyStr (conservativeUnk kt) <> "," <> tyStr (conservativeUnk vt) <> ")")

inferMapKey :: Env -> CMapPair -> Ty
inferMapKey _ (CMAtom _ _) = TName "Symbol"
inferMapKey env (CMKey k _) = infer k env

mapVal :: CMapPair -> CExpr
mapVal (CMAtom _ v) = v
mapVal (CMKey _ v) = v

-- ── small inference helpers ──────────────────────────────────────────────────

-- ── lambdas (arrow types) ────────────────────────────────────────────────────

inferLambda :: Array P.Param -> CExpr -> Env -> Ty
inferLambda ps body env =
  let
    lenv = foldl (\e prm -> envPut prm.name (paramTy prm) e) env ps
    args = map paramTy ps
  in
    buildFn args (infer body lenv)
  where
  paramTy prm = maybe Unknown TName prm.ty

-- `Fn(A1,…,An,R)` from inferred component types (an `Unknown`/wildcard slot → `_`).
buildFn :: Array Ty -> Ty -> Ty
buildFn args ret = TName ("Fn(" <> joinWith "," (map compStr (snoc args ret)) <> ")")

compStr :: Ty -> String
compStr Unknown = "_"
compStr (TName s) = s
compStr t = tyStr t

-- ── branch / arm join (if / case arms) ───────────────────────────────────────

-- The type of an expression whose value is one of several typed branches. An integer-literal
-- branch is width-flexible (adopts the non-literal branches' integer type); otherwise the
-- branches join as ALTERNATIVES — a common LUB, else a value union (ADR-0083).
branchJoin :: Array (Tuple CExpr Ty) -> Ty
branchJoin typed =
  let
    allTs = map snd typed
    nonLit = map snd (filter (\(Tuple e _) -> not (intLitExpr e)) typed)
  in
    if null nonLit then joinAll allTs
    else if intType (joinAll nonLit) then joinAll nonLit
    else joinAlts allTs

-- join branches as alternatives: a common LUB where one exists, else a value `Union(…)`;
-- a genuinely uninferable (`Unknown`/`Mismatch`) branch poisons the whole to `Unknown`.
joinAlts :: Array Ty -> Ty
joinAlts types =
  if any (\t -> t == Unknown || t == Mismatch) types then Unknown
  else debottom (foldl step Bottom types)
  where
  step acc t
    | acc == Unknown = Unknown
    | otherwise = case join acc t of
        Unknown -> unionJoin acc t
        j -> j

unionJoin :: Ty -> Ty -> Ty
unionJoin from to =
  let members = nubEq (unionMembers from <> unionMembers to) in
  case members of
    [ m ] -> TName m
    _ -> if primDiscClash members then Unknown else TName ("Union(" <> joinWith "," members <> ")")

unionMembers :: Ty -> Array String
unionMembers (TName s) =
  case Str.stripPrefix (Str.Pattern "Union(") s of
    Just rest -> splitTopCommas (dropLastParen rest)
    Nothing -> [ s ]
unionMembers _ = []

-- do any two members share a non-`Other` primitive discriminator (so a `case` couldn't tell
-- them apart)? Only primitives collide.
primDiscClash :: Array String -> Boolean
primDiscClash members =
  let discs = filter (_ /= PdOther) (map primDisc members) in
  length (nubEq discs) /= length discs

data PrimDisc = PdInteger | PdFloat | PdBinary | PdBoolean | PdOther

derive instance Eq PrimDisc

primDisc :: String -> PrimDisc
primDisc "Bool" = PdBoolean
primDisc "String" = PdBinary
primDisc "Char" = PdInteger
primDisc s
  | intType (TName s) = PdInteger
  | floatTypeStr s = PdFloat
  | otherwise = PdOther

-- `^Float\d*$`.
floatTypeStr :: String -> Boolean
floatTypeStr s = case Str.stripPrefix (Str.Pattern "Float") s of
  Just rest -> all isDigit (toCharArray rest)
  Nothing -> false

joinAll :: Array Ty -> Ty
joinAll = debottom <<< foldl (\acc t -> join t acc) Bottom

debottom :: Ty -> Ty
debottom Bottom = Unknown
debottom t = t

-- a proven clash relaxes to `Unknown` (the checker only reports a provable mismatch later).
conservative :: Ty -> Ty
conservative Mismatch = Unknown
conservative t = t

-- a structural element the checker can't pin becomes `Any` (the dynamic top), so the
-- enclosing tuple/map type stays concrete instead of collapsing to `:unknown`.
conservativeUnk :: Ty -> Ty
conservativeUnk (TName s) = TName s
conservativeUnk _ = TName "Any"

hasDotOrE :: String -> Boolean
hasDotOrE n = Str.contains (Str.Pattern ".") n || Str.contains (Str.Pattern "e") n || Str.contains (Str.Pattern "E") n

-- ── parity entries ───────────────────────────────────────────────────────────

-- | The `uni` / `joi` streams: a `t;;u` pair (the sentinels spelled `:unknown` etc.).
unifySexpr :: String -> String
unifySexpr = pairOp unify

joinSexpr :: String -> String
joinSexpr = pairOp join

pairOp :: (Ty -> Ty -> Ty) -> String -> String
pairOp f src = case split (Str.Pattern ";;") src of
  [ a, b ] -> tyStr (f (tyOf a) (tyOf b))
  _ -> "?"

-- | The `inf` stream: infer an expression's type under a fixed env (mirrored in the oracle),
-- | composing `lexer → Pratt → Core → infer`.
-- `Prim.normalize` (rewriting `Prim.x`/`panic` → `__prim_x`) matches the reference's
-- normalizing `Pratt.parse`; it is identity over non-`Prim` expressions.
inferSexpr :: String -> String
inferSexpr src = tyStr (infer (fromExpr (normalize (P.parse src))) fixedEnv)

-- | The `bdy` stream: infer a function body (`;`-separated statements with binds threaded
-- | through the env), composing `lexer → Pratt.parseBody → Prim.normalize → Core → infer`.
inferBodySexpr :: String -> String
inferBodySexpr src = tyStr (infer (fromExpr (normalize (P.parseBody src))) fixedEnv)

-- the parity env (must match `CheckCanon.fixed_env` in gen_fixtures.exs).
fixedEnv :: Env
fixedEnv =
  [ Tuple "x" (TName "Int64")
  , Tuple "y" (TName "Int64")
  , Tuple "n" (TName "Int53")
  , Tuple "b" (TName "Bool")
  , Tuple "s" (TName "String")
  , Tuple "f" (TName "Float64")
  , Tuple "c" (TName "Char")
  , Tuple "xs" (TName "Vec(Int53)")
  , Tuple "g" (TName "Fn(Int64,Bool)")
  ]
