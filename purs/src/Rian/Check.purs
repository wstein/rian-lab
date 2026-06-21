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
  , Ic
  , Fsig
  , RangeInfo
  , OpaqueInfo
  , Fbound
  , programIc
  , inferReturnType
  , inferParamType
  , fillLocalRets
  , checkProgram
  , unifySexpr
  , joinSexpr
  , inferSexpr
  , inferBodySexpr
  , inferIcSexpr
  , programIcSexpr
  , inferReturnTypeSexpr
  , fillLocalRetsSexpr
  , checkProgramSexpr
  , inferParamTypeSexpr
  ) where

import Prelude hiding (join)

import Data.Array (concatMap, filter, find, findMap, foldl, fromFoldable, head, index, last, length, mapMaybe, mapWithIndex, nub, nubEq, null, snoc, sortWith, uncons, zip, zipWith)
import Data.Foldable (all, any, elem)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing, maybe)
import Data.String as Str
import Data.String.CodeUnits (singleton, toCharArray)
import Data.String.Common (joinWith, replaceAll, split)
import Data.Tuple (Tuple(..), fst, snd)
import Rian.Builtins as Builtins
import Rian.Core (CExpr(..), CMapPair(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Func, Param, Prog, Type, bodySurface)
import Rian.Prelude (withPrelude)
import Rian.Pratt (Arm, ForClause(..), IPart(..), MapPair(..), Param, Pat, Stmt(..), Surface(..), WithClause, parse, parseBody) as P
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
infer :: CExpr -> Env -> Ic -> Ty
infer (ENum n) _ _ = if hasDotOrE n then TName "Float64" else TName "Int53"
infer (EStr _) _ _ = TName "String"
infer (EChar _) _ _ = TName "Char"
infer (EId "true") _ _ = TName "Bool"
infer (EId "false") _ _ = TName "Bool"
infer (EId x) env _ = fromMaybe Unknown (envLookup x env)
infer (EUnary "-" x) env ic = infer x env ic
infer (EUnary "not" _) _ _ = TName "Bool"
infer (EBin op l r) env ic = inferBin op l r env ic
infer (EList elems tail) env ic = inferList elems tail env ic
infer (ETuple elems) env ic = inferTuple elems env ic
infer (EMap pairs) env ic = inferMap pairs env ic
-- `if`'s value is the LUB-join of its two arms (a value union when they don't share an LUB).
-- The arms are `do`/`else` blocks, so each is an `EBlock` whose value is its last statement.
infer (EIf _ t e) env ic = branchJoin [ Tuple t (infer t env ic), Tuple e (infer e env ic) ]
-- `case` — flow narrowing: each arm body infers under an env where the arm pattern's bindings
-- are refined against the scrutinee's type (`ic.tdefs`); the case's type is the LUB-join of arms.
infer (ECase scrut arms) env ic =
  let st = infer scrut env ic
  in branchJoin (map (\arm -> Tuple arm.body (infer arm.body (narrow arm.pat st ic env) ic)) arms)
-- a lambda `(a, b) -> body` infers the arrow type `Fn(a_t.., body_t)`.
infer (ELambda ps body) env ic = inferLambda ps body env ic
infer (EBlock stmts) env ic = inferBlock stmts env Unknown ic
-- a `with` yields its do-block value on the happy path (clause-bound vars infer `Unknown`).
infer (EWith _ body _) env ic = infer body env ic
-- prim intrinsics (after `Rian.Prim.normalize` rewrote `Prim.x`/`panic` to `__prim_x`).
infer (ECall (EId "__prim_char_code") _) _ _ = TName "Int53"
infer (ECall (EId "__prim_int_to_float") _) _ _ = TName "Float64"
infer (ECall (EId "__prim_str_to_atom") _) _ _ = TName "Symbol"
infer (ECall (EId "__prim_str_concat_all") _) _ _ = TName "String"
infer (ECall (EId "__prim_char_to_string") _) _ _ = TName "String"
infer (ECall (EId "__prim_panic") _) _ _ = Unknown
-- `inspect/1` is the host value→text function: always `String`.
infer (ECall (EId "inspect") [ _ ]) _ _ = TName "String"
-- a bare call: a `Fn`-typed var applied → its return; else a sum/struct constructor (`ic.ctors`
-- → its type), a program function (`ic.funs` → its declared return), or a Kernel-auto-import
-- builtin. (An empty `ic` falls straight through to the builtin — the env-only behaviour.)
infer (ECall (EId f) args) env ic = case envLookup f env of
  Just ft | isFnTy ft -> fnRet ft
  _ -> case ctorType ic f of
    Just ty -> TName ty
    Nothing -> case calledRetWith ic f args env of
      Unknown -> builtinOrUnknown Nothing f (length args)
      v -> v
-- `Name.of(n)` — range/opaque construction (ADR-0036/0067): an opaque's constructor is total
-- (returns the nominal `Name`); a range's returns `Result(base,RangeError)` (collapsed form,
-- matching declared-return storage). Otherwise it falls through to a function value.
infer (ECall (EDot (EId n) "of") args) env ic =
  if isJust (find (\(Tuple k _) -> k == n) ic.opaques) then TName n
  else case rangeBase ic n of
    Just base -> TName ("Result(" <> base <> ",RangeError)")
    Nothing -> let ft = infer (EDot (EId n) "of") env ic in if isFnTy ft then fnRet ft else Unknown
-- a ZERO-arg dot-call is the `abstract`-cast position (`m.base()`): cast inference (ic.opaques
-- ops/casts) is a later slice, so it is `Unknown` — and this intercepts a zero-arg `Mod.fun()`
-- (e.g. `Map.new()`) before the builtin clause, matching the reference's clause order.
infer (ECall (EDot _ _) []) _env _ = Unknown
-- a module call `Mod.fun(args)`: a program function's declared return (`ic.funs`, keyed by
-- name+arity, module-flattened as on the BEAM), else a fixed-head poly stdlib call (`List.map`)
-- instantiated from the argument types, else a host/stdlib builtin.
infer (ECall (EDot (EId modn) fn) args) env ic = case lookupFunRaw ic.funs fn (length args) of
  Just ret -> TName ret
  Nothing -> case Builtins.polySig (Just modn) fn (length args) of
    Just sig -> instantiateLax sig (map (\a -> infer a env ic) args)
    Nothing -> builtinOrUnknown (Just modn) fn (length args)
-- an Erlang-BIF FFI call `:erlang.phash2(x)` — typed from the foreign registry.
infer (ECall (EDot (EAtom modn) fn) args) _ _ = builtinOrUnknown (Just modn) fn (length args)
-- any other callable (a lambda result, a returned function): its return when it is known
-- to be a function, else `Unknown`.
infer (ECall fn _) env ic = let ft = infer fn env ic in if isFnTy ft then fnRet ft else Unknown
infer _ _ _ = Unknown

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
inferBlock :: Array CStmt -> Env -> Ty -> Ic -> Ty
inferBlock stmts env value ic = case uncons stmts of
  Nothing -> value
  Just { head: CBind n e, tail: rest } -> let t = infer e env ic in inferBlock rest (envPut n t env) t ic
  Just { head: CTypedBind n t _, tail: rest } -> inferBlock rest (envPut n (TName t) env) (TName t) ic
  Just { head: CExprStmt e, tail: rest } -> inferBlock rest env (infer e env ic) ic

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

inferBin :: String -> CExpr -> CExpr -> Env -> Ic -> Ty
inferBin op l r env ic =
  let
    lt = infer l env ic
    rt = infer r env ic
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

inferList :: Array CExpr -> Maybe CExpr -> Env -> Ic -> Ty
inferList elems tail env ic =
  let
    elemT = debottom (foldl (\acc e -> join (infer e env ic) acc) Bottom elems)
    te = listElem (inferTail tail env ic)
  in
    if te == Unknown || te == elemT then listOf (conservative elemT) else Unknown

inferTail :: Maybe CExpr -> Env -> Ic -> Ty
inferTail Nothing _ _ = Unknown
inferTail (Just t) env ic = infer t env ic

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
inferTuple :: Array CExpr -> Env -> Ic -> Ty
inferTuple elems env ic = case head elems of
  Just (EAtom _) -> Unknown
  _ -> TName ("(" <> joinWith "," (map (\e -> tyStr (conservativeUnk (infer e env ic))) elems) <> ")")

-- a `%{…}` literal infers `Dict(KeyT,ValT)` — key/value types each LUB-join across the pairs.
inferMap :: Array CMapPair -> Env -> Ic -> Ty
inferMap pairs env ic =
  let
    kt = joinAll (map (inferMapKey env ic) pairs)
    vt = joinAll (map (\p -> infer (mapVal p) env ic) pairs)
  in
    TName ("Dict(" <> tyStr (conservativeUnk kt) <> "," <> tyStr (conservativeUnk vt) <> ")")

inferMapKey :: Env -> Ic -> CMapPair -> Ty
inferMapKey _ _ (CMAtom _ _) = TName "Symbol"
inferMapKey env ic (CMKey k _) = infer k env ic

mapVal :: CMapPair -> CExpr
mapVal (CMAtom _ v) = v
mapVal (CMKey _ v) = v

-- ── small inference helpers ──────────────────────────────────────────────────

-- ── lambdas (arrow types) ────────────────────────────────────────────────────

inferLambda :: Array P.Param -> CExpr -> Env -> Ic -> Ty
inferLambda ps body env ic =
  let
    lenv = foldl (\e prm -> envPut prm.name (paramTy prm) e) env ps
    args = map paramTy ps
  in
    buildFn args (infer body lenv ic)
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
inferSexpr src = tyStr (infer (fromExpr (normalize (P.parse src))) fixedEnv emptyIc)

-- | The `bdy` stream: infer a function body (`;`-separated statements with binds threaded
-- | through the env), composing `lexer → Pratt.parseBody → Prim.normalize → Core → infer`.
inferBodySexpr :: String -> String
inferBodySexpr src = tyStr (infer (fromExpr (normalize (P.parseBody src))) fixedEnv emptyIc)

-- the empty inference context — `infer` with it reproduces the env-only behaviour.
emptyIc :: Ic
emptyIc = { tdefs: [], fields: [], funs: [], fsigs: [], ctors: [], ranges: [], opaques: [], impls: [], fbounds: [] }

-- | The `ifc` stream: infer an expression under a real `ic` built from `program_ic` over a
-- | leading program, `;;`-separated from the expression. Tests the ic-using call clauses
-- | (a sum/struct constructor, a program function's return, a cross-module call).
inferIcSexpr :: String -> String
inferIcSexpr src = case split (Str.Pattern ";;") src of
  [ prog, expr ] -> tyStr (infer (fromExpr (normalize (P.parse expr))) fixedEnv (programIc (parseToProg prog)))
  _ -> "?"

-- ── ic-using call inference ──
-- a sum/struct constructor → the type it builds (`ic.ctors`).
ctorType :: Ic -> String -> Maybe String
ctorType ic name = map snd (find (\(Tuple k _) -> k == name) ic.ctors)

-- a program function's declared return (`ic.funs`), keyed name+arity; a generic return (one
-- mentioning a tvar) stays `Unknown` (pinning it to its literal form would lie to a concrete
-- caller). Not found → `Unknown`.
calledRet :: Ic -> String -> Int -> Ty
calledRet ic f arity = case lookupFunRaw ic.funs f arity of
  Nothing -> Unknown
  Just ret -> if hasTvar ret then Unknown else TName ret

-- the raw declared return string for `name/arity` in `ic.funs` (`Nothing` = absent or un-filled).
lookupFunRaw :: Array (Tuple (Tuple String Int) (Maybe String)) -> String -> Int -> Maybe String
lookupFunRaw funs f arity = case find (\(Tuple k _) -> k == Tuple f arity) funs of
  Just (Tuple _ ret) -> ret
  Nothing -> Nothing

-- a program function's return: a generic callee (its `fsigs` carries `forall` tvars) instantiates
-- its return from the call's argument types; otherwise the declared (non-generic) return.
calledRetWith :: Ic -> String -> Array CExpr -> Env -> Ty
calledRetWith ic f args env = case find (\(Tuple k _) -> k == Tuple f (length args)) ic.fsigs of
  Just (Tuple _ sig) | not (null sig.tvars) -> instantiateRet sig (map (\a -> infer a env ic) args)
  _ -> calledRet ic f (length args)

-- instantiate a generic return: bind each tvar from the args, then word-substitute it in `ret`.
-- Only tvars that actually appear in `ret` need binding (`length … Int53 forall T` is `Int53`
-- regardless of `T`); an unbindable needed tvar yields `Unknown` (sound).
instantiateRet :: Fsig -> Array Ty -> Ty
instantiateRet sig argTypes = case sig.ret of
  Nothing -> Unknown
  Just ret ->
    let
      subs = foldl bindOne [] (zip sig.params argTypes)
      needed = filter (\tv -> elem tv (typeIdents ret)) sig.tvars
    in
      if all (\tv -> any (\(Tuple k _) -> k == tv) subs) needed then TName (foldl applySub ret subs)
      else Unknown
  where
  bindOne acc (Tuple mp a) = case mp of
    Just p -> bindTvar p a sig.tvars acc
    Nothing -> acc
  applySub r (Tuple tv ty) = wordReplace tv ty r

-- the ordinal base of a `range` named `n` (`ic.ranges`), else `Nothing`.
rangeBase :: Ic -> String -> Maybe String
rangeBase ic n = map (\(Tuple _ info) -> info.base) (find (\(Tuple k _) -> k == n) ic.ranges)

-- ── `case` flow narrowing (refine arm-pattern bindings against the scrutinee) ──
narrow :: CPat -> Ty -> Ic -> Env -> Env
narrow (PVar name) ty _ env = envPut name (concretize ty) env
narrow (PTyped name tname) _ _ env = envPut name (TName tname) env
narrow (PCtor ctor args) _ ic env =
  foldl (\e (Tuple i p) -> narrow p (fieldTy i) ic e) env (mapWithIndex Tuple args)
  where
  fieldTypes = fromMaybe [] (map snd (find (\(Tuple k _) -> k == ctor) ic.tdefs))
  fieldTy i = maybe Unknown TName (index fieldTypes i)
narrow _ _ _ env = env

-- a bare-tvar field type narrows to `Unknown` (generics are not instantiated in a pattern).
concretize :: Ty -> Ty
concretize (TName t) = if isTvar t then Unknown else TName t
concretize t = t

-- replace whole-word occurrences of `target` with `repl` (the reference's `\b…\b` regex).
wordReplace :: String -> String -> String -> String
wordReplace target repl input =
  let final = foldl go { out: "", cur: "" } (toCharArray input)
  in final.out <> emit final.cur
  where
  emit w = if w == target then repl else w
  go acc c =
    if isWordChar c then acc { cur = acc.cur <> singleton c }
    else { out: acc.out <> emit acc.cur <> singleton c, cur: "" }

-- does a type string mention a type-variable token (`^[A-Z][0-9]?$` per identifier)?
hasTvar :: String -> Boolean
hasTvar t = any isTvar (typeIdents t)

-- the `[A-Za-z_]\w*` identifier tokens of a type string (maximal word runs).
typeIdents :: String -> Array String
typeIdents t =
  let final = foldl step { toks: [], cur: "" } (toCharArray t)
  in final.toks <> (if final.cur == "" then [] else [ final.cur ])
  where
  step acc c =
    if isWordChar c then acc { cur = acc.cur <> singleton c }
    else if acc.cur == "" then acc
    else acc { toks = acc.toks <> [ acc.cur ], cur = "" }

isWordChar :: Char -> Boolean
isWordChar c = isUpper c || (c >= 'a' && c <= 'z') || isDigit c || c == '_'

--------------------------------------------------------------------------------
-- back-inference: a private function's return / fill_local_rets (ADR-0034 infer-local)
--------------------------------------------------------------------------------

-- | Infer a private function's RETURN type from its clause bodies — the join of each clause's
-- | inferred body type under `ic`. `Unknown` when no clause pins it. A clause that IS a direct
-- | self-call contributes `Bottom` (the fixpoint, not a new alternative), so the type is fixed
-- | by the base-case clauses. The engine behind `Rian.InferLocal` filling an untyped function.
-- @rian_sig pub def infer_return_type(func val Func, ic val Ic) String
inferReturnType :: Func -> Ic -> Ty
inferReturnType f ic =
  let types = map clauseType f.clauses
  in
    if any (\t -> t == Unknown || t == Mismatch) types then Unknown
    else case joinAlts types of
      TName t -> TName t
      _ -> Unknown
  where
  clauseType c = case c.body of
    Nothing -> Unknown
    Just b ->
      let body = fromExpr (normalize (bodySurface b))
      in
        if selfRecursiveBody body f.name then Bottom
        else infer body (bindTvarParams (clauseEnv c.pats f.params ic) c.pats f.params f.tvars) ic

-- a clause-head env: each var-pattern param binds to its declared (concretized) type, narrowed
-- against the param's type (reuses `narrow`, so ctor-pattern fields refine too).
clauseEnv :: Array P.Pat -> Array Param -> Ic -> Env
clauseEnv pats params ic =
  foldl (\env (Tuple pat param) -> narrow (fromPat pat) (maybe Unknown TName param.ty) ic env) [] (zip pats params)

-- re-bind a bare-var param whose declared type is one of the function's own `forall` tvars to
-- that tvar (so a pass-through `def id(x) := x` infers the return `T`).
bindTvarParams :: Env -> Array P.Pat -> Array Param -> Array String -> Env
bindTvarParams env pats ps tvs = foldl step env (zip pats ps)
  where
  step e (Tuple pat p) = case fromPat pat of
    PVar vn -> if maybe false (\t -> elem t tvs) p.ty then envPut vn (TName (fromMaybe "" p.ty)) e else e
    _ -> e

-- a clause body that IS a direct self-call (a bare `f(args)` or a block ending in one).
selfRecursiveBody :: CExpr -> String -> Boolean
selfRecursiveBody (ECall (EId n) _) name = n == name
selfRecursiveBody (EBlock stmts) name = case last stmts of
  Just (CExprStmt e) -> selfRecursiveBody e name
  _ -> false
selfRecursiveBody _ _ = false

-- | Call-result return inference (the `funs` table fixpoint): every un-annotated non-generic
-- | function's return inferred from its body, so a caller resolves the call's type. A bounded
-- | fixpoint — each pass only fills a `Nothing`, so it converges monotonically.
-- @rian_sig pub def fill_local_rets(funcs val Vec(Func), ic val Ic) Dict(String, String)
fillLocalRets :: Array Func -> Ic -> Array (Tuple (Tuple String Int) (Maybe String))
fillLocalRets allFuncs ic = fixIter (length untyped) ic.funs
  where
  untyped = filter (\f -> isNothing f.ret && null f.tvars) allFuncs
  fixIter n funs =
    if n <= 0 then funs
    else
      let next = foldl (fillStep ic) funs untyped
      in if next == funs then funs else fixIter (n - 1) next

fillStep :: Ic -> Array (Tuple (Tuple String Int) (Maybe String)) -> Func -> Array (Tuple (Tuple String Int) (Maybe String))
fillStep ic acc f =
  let key = Tuple f.name (length f.params)
  in case lookupFunRaw acc f.name (length f.params) of
    Just _ -> acc
    Nothing -> case inferReturnType f (ic { funs = acc }) of
      TName t -> map (\(Tuple k old) -> if k == key then Tuple k (Just t) else Tuple k old) acc
      _ -> acc

-- | The `irt` stream: each function's `inferReturnType` under a fully-filled `ic` (matching the
-- | reference's `program_ic`, which runs `fill_local_rets`). `name/arity=>type` sorted.
inferReturnTypeSexpr :: String -> String
inferReturnTypeSexpr src =
  joinWith ";" (sortWith identity (map entry funcs))
  where
  prog = parseToProg src
  funcs = prog.funcs <> concatMap _.funcs prog.mods
  ic0 = programIc prog
  ic = ic0 { funs = fillLocalRets funcs ic0 }
  entry f = f.name <> "/" <> show (length f.params) <> "=>" <> tyStr (inferReturnType f ic)

-- | The `flr` stream: dump `fill_local_rets`' converged `funs` table (un-annotated returns
-- | filled from bodies). `name/arity=>ret` sorted.
fillLocalRetsSexpr :: String -> String
fillLocalRetsSexpr src =
  joinWith ";" (sortWith identity (map entry (fillLocalRets funcs (programIc prog))))
  where
  prog = parseToProg src
  funcs = prog.funcs <> concatMap _.funcs prog.mods
  entry (Tuple (Tuple n a) ret) = n <> "/" <> show a <> "=>" <> fromMaybe "_" ret

--------------------------------------------------------------------------------
-- the program gate (ADR-0034): each function's body must be assignable to its return
--------------------------------------------------------------------------------

-- | The compile-time return gate: the first function whose body type is not assignable to its
-- | declared return (`Just message`), else `Nothing` (`:ok`). This slice covers the
-- | return-assignability check (the headline gate); error-sets/effects/bounds/coherence and the
-- | literal-width-adoption relaxation are later — the corpus avoids them.
checkProgram :: Prog -> Maybe String
checkProgram prog = findMap checkFunc funcs
  where
  funcs = prog.funcs <> concatMap _.funcs prog.mods
  ic0 = programIc prog
  ic = ic0 { funs = fillLocalRets funcs ic0 }
  tsets = errorSetsTable prog
  table = solveErrorSets funcs tsets
  -- per function: the body must be assignable to the declared return, AND a Result return's
  -- produced error set ⊆ its declared `E` (ADR-0040).
  checkFunc f = case checkReturn ic f of
    Just msg -> Just msg
    Nothing -> checkErrorSet tsets table f

-- a function's declared (non-generic) return must accept every clause body's inferred type.
checkReturn :: Ic -> Func -> Maybe String
checkReturn ic f = case f.ret of
  Nothing -> Nothing
  Just ret ->
    if genericRet ret f.tvars then Nothing
    else findMap (clauseErr ret) f.clauses
  where
  clauseErr ret c = case c.body of
    Nothing -> Nothing
    Just b ->
      let bt = infer (fromExpr (normalize (bodySurface b))) (clauseEnv c.pats f.params ic) ic
      in
        if assignable bt (TName ret) then Nothing
        else Just ("`" <> f.name <> "`: body has type `" <> tyStr bt <> "` but the declared return type is `" <> ret <> "`")

-- a return mentioning one of the function's `forall` tvars is generic — checked conservatively.
genericRet :: String -> Array String -> Boolean
genericRet ret tvars = any (\tv -> elem tv (typeIdents ret)) tvars

-- assignability (ADR-0059): `Unknown` is a wildcard; a union flows where all its members do (and
-- a value flows into a union); a bare sum head accepts its parameterization; `Any`/`_Unk` are
-- wildcards at any depth; a constructed type accepts an opaque-nominal return; numerics widen;
-- else they must unify (a proven mismatch is rejected).
assignable :: Ty -> Ty -> Boolean
assignable Unknown _ = true
assignable _ Unknown = true
assignable (TName from) (TName to) = assignableStr from to
assignable from to = from == to

assignableStr :: String -> String -> Boolean
assignableStr from to =
  if from == to then true
  else if isUnion from then all (\m -> assignableStr m to) (unionMembersOf from)
  else if isUnion to then any (assignableStr from) (unionMembersOf to)
  else if bareHeadOf from to then true
  else if (hasWildcard from || hasWildcard to) && unkAssignable from to then true
  else if constructedType from && opaqueNominal to then true
  else case numKind (TName from), numKind (TName to) of
    Just a, Just b -> numWidens a b
    _, _ -> unify (TName from) (TName to) /= Mismatch

isUnion :: String -> Boolean
isUnion s = isJust (Str.stripPrefix (Str.Pattern "Union(") s)

unionMembersOf :: String -> Array String
unionMembersOf s = splitTopCommas (chopLastParen (fromMaybe s (Str.stripPrefix (Str.Pattern "Union(") s)))

-- `from` is the bare head of the parameterized `to` (`Option` of `Option(Vec(Char))`).
bareHeadOf :: String -> String -> Boolean
bareHeadOf from to = not (Str.contains (Str.Pattern "(") from) && isJust (Str.stripPrefix (Str.Pattern (from <> "(")) to)

constructedType :: String -> Boolean
constructedType t = Str.contains (Str.Pattern "(") t

hasWildcard :: String -> Boolean
hasWildcard t = Str.contains (Str.Pattern "Any") t || Str.contains (Str.Pattern "_Unk") t

-- a PascalCase nominal that is not a scalar primitive (a user/alias type the checker can't resolve).
opaqueNominal :: String -> Boolean
opaqueNominal t =
  let cs = toCharArray t
  in maybe false isUpper (head cs) && all isWordChar cs && not (scalarPrim t)

scalarPrim :: String -> Boolean
scalarPrim t = elem t [ "Bool", "String", "Char", "Symbol" ] || intType (TName t) || isFloatStr t

isFloatStr :: String -> Boolean
isFloatStr t = case Str.stripPrefix (Str.Pattern "Float") t of
  Just rest -> all isDigit (toCharArray rest)
  Nothing -> false

-- structural assignability treating `Any`/`_Unk` as a wildcard at any depth (same head + arity,
-- componentwise).
unkAssignable :: String -> String -> Boolean
unkAssignable a b =
  if a == "Any" || a == "_Unk" || b == "Any" || b == "_Unk" then true
  else if a == b then true
  else headsMatch (splitHead a) (splitHead b)

headsMatch :: Tuple String (Array String) -> Tuple String (Array String) -> Boolean
headsMatch (Tuple h1 as) (Tuple h2 bs) =
  h1 == h2 && length as == length bs && all (\(Tuple x y) -> unkAssignable x y) (zip as bs)

-- `"Vec(Int64)"` → `("Vec", ["Int64"])`; `"(A,B)"` → `("", ["A","B"])`; a non-parametric → `(t, [])`.
splitHead :: String -> Tuple String (Array String)
splitHead t = case Str.stripSuffix (Str.Pattern ")") t of
  Just body -> case Str.indexOf (Str.Pattern "(") body of
    Just i -> Tuple (Str.take i body) (splitTopCommas (Str.drop (i + 1) body))
    Nothing -> Tuple t []
  Nothing -> Tuple t []

chopLastParen :: String -> String
chopLastParen s = fromMaybe s (Str.stripSuffix (Str.Pattern ")") s)

-- numeric widening (`from`'s width fits `to`'s): same kind ≤; uint→int (strict, sign bit);
-- int/uint → float (mantissa); float→float ≤.
numWidens :: { kind :: Kind, bits :: Int } -> { kind :: Kind, bits :: Int } -> Boolean
numWidens { kind: KInt, bits: a } { kind: KInt, bits: b } = a <= b
numWidens { kind: KUint, bits: a } { kind: KUint, bits: b } = a <= b
numWidens { kind: KUint, bits: a } { kind: KInt, bits: b } = a < b
numWidens { kind: KInt, bits: a } { kind: KFloat, bits: b } = a - 1 <= floatMantissa b
numWidens { kind: KUint, bits: a } { kind: KFloat, bits: b } = a <= floatMantissa b
numWidens { kind: KFloat, bits: a } { kind: KFloat, bits: b } = a <= b
numWidens _ _ = false

-- | The `gate` parity unit: `check_program`'s verdict — `ok` or the first mismatch message.
checkProgramSexpr :: String -> String
checkProgramSexpr src = fromMaybe "ok" (checkProgram (parseToProg src))

--------------------------------------------------------------------------------
-- infer_param_type: bidirectional private-parameter inference (ADR-0034)
--------------------------------------------------------------------------------

-- | Infer a private function's parameter type at position `i` — an arithmetic/compare operator,
-- | a string concat, or a typed callee parameter pushes its expected type onto the variable; a
-- | literal/ctor clause-head pattern pins it. `Unknown` when unconstrained (InferLocal generalizes
-- | to `forall T`); `Mismatch` on a provable conflict.
-- @rian_sig pub def infer_param_type(func val Func, i val Int53, ic val Ic) String
inferParamType :: Func -> Int -> Ic -> Ty
inferParamType f i ic = foldl (\acc c -> foldConstraint acc (clauseC c)) Unknown f.clauses
  where
  clauseC c = case index c.pats i of
    Nothing -> Unknown
    Just pat -> case fromPat pat of
      PVar vn -> maybe Unknown (\b -> varConstraint vn (clauseEnv c.pats f.params ic) ic (fromExpr (normalize (bodySurface b)))) c.body
      other -> patternType ic other

-- the type a clause-head pattern requires of its scrutinee (structural patterns stay `Unknown`).
patternType :: Ic -> CPat -> Ty
patternType _ (PLit (LInt _)) = TName "Int53"
patternType _ (PLit (LStr _)) = TName "String"
patternType _ (PChar _) = TName "Char"
patternType ic (PCtor c _) = maybe Unknown TName (ctorType ic c)
patternType _ _ = Unknown

-- fold two parameter constraints: `Unknown` = identity, a concrete wins, two differing concretes
-- conflict. `unify`'s clash is softened to `Unknown` by `conservative` — restore it (a clash IS
-- the signal for parameter inference).
foldConstraint :: Ty -> Ty -> Ty
foldConstraint Unknown t = t
foldConstraint t Unknown = t
foldConstraint Mismatch _ = Mismatch
foldConstraint _ Mismatch = Mismatch
foldConstraint a b = nilableMismatch (conservative (unify a b)) a b

nilableMismatch :: Ty -> Ty -> Ty -> Ty
nilableMismatch Unknown (TName a) (TName b) = if a /= b then Mismatch else Unknown
nilableMismatch t _ _ = t

foldConstraints :: Array Ty -> Ty
foldConstraints = foldl foldConstraint Unknown

-- the type the body forces on variable `name` (the "expected type in", recursed structurally).
varConstraint :: String -> Env -> Ic -> CExpr -> Ty
varConstraint name env ic node = case node of
  EBin op l r ->
    let
      here =
        if op == "<>" && (varIs name l || varIs name r) then TName "String"
        else if isArithOp op && varIs name l then numHint (infer r env ic)
        else if isArithOp op && varIs name r then numHint (infer l env ic)
        else if elem op boolOps && varIs name l then concretize (infer r env ic)
        else if elem op boolOps && varIs name r then concretize (infer l env ic)
        else Unknown
    in
      foldConstraints [ here, varConstraint name env ic l, varConstraint name env ic r ]
  ECall (EId fn) as ->
    let
      fromCallee = case find (\(Tuple k _) -> k == Tuple fn (length as)) ic.fsigs of
        Just (Tuple _ sig) ->
          foldl (\acc (Tuple i a) -> if varIs name a then foldConstraint acc (concretize (sigParamTy sig i)) else acc)
            Unknown
            (mapWithIndex Tuple as)
        Nothing -> Unknown
    in
      foldl (\acc a -> foldConstraint acc (varConstraint name env ic a)) fromCallee as
  ECall _ as -> foldConstraints (map (varConstraint name env ic) as)
  EUnary _ a -> varConstraint name env ic a
  EIf c t e -> foldConstraints (map (varConstraint name env ic) [ c, t, e ])
  EBlock stmts -> foldConstraints (map (\s -> varConstraint name env ic (stmtExpr s)) stmts)
  ECase s arms ->
    let
      fromScrut = if varIs name s then foldConstraints (map (\a -> patternType ic a.pat) arms) else Unknown
    in
      foldConstraints ([ fromScrut, varConstraint name env ic s ] <> map (\a -> varConstraint name env ic a.body) arms)
  EList es _ -> foldConstraints (map (varConstraint name env ic) es)
  _ -> foldConstraints (map (varConstraint name env ic) (cexprChildren node))

-- the callee's i-th declared parameter type (`Unknown` when out of range or itself untyped).
sigParamTy :: Fsig -> Int -> Ty
sigParamTy sig i = case index sig.params i of
  Just (Just t) -> TName t
  _ -> Unknown

isArithOp :: String -> Boolean
isArithOp op = elem op arithOps || elem op intOps

varIs :: String -> CExpr -> Boolean
varIs name (EId n) = n == name
varIs _ _ = false

-- an arithmetic neighbour's numeric hint: an int type's ordinal base; else the `Int53` default.
numHint :: Ty -> Ty
numHint (TName t) = if intType (TName t) then ordinalBase (TName t) else Unknown
numHint _ = TName "Int53"

stmtExpr :: CStmt -> CExpr
stmtExpr (CBind _ e) = e
stmtExpr (CTypedBind _ _ e) = e
stmtExpr (CExprStmt e) = e

-- direct sub-expressions (the generic `var_constraint` recurse — a var use may sit in any child).
cexprChildren :: CExpr -> Array CExpr
cexprChildren = case _ of
  EUnary _ x -> [ x ]
  EBin _ l r -> [ l, r ]
  ECall f as -> [ f ] <> as
  EDot h _ -> [ h ]
  EIf c t e -> [ c, t, e ]
  ECase s arms -> [ s ] <> concatMap (\a -> [ a.body ]) arms
  EWith cls body arms -> map _.expr cls <> [ body ] <> map _.body arms
  EBlock stmts -> map stmtExpr stmts
  EList es tl -> es <> fromFoldable tl
  EMap ps -> concatMap mapPairExpr ps
  EMapUpdate base ps -> [ base ] <> concatMap mapPairExpr ps
  ETuple es -> es
  ELambda _ b -> [ b ]
  ECapture b -> [ b ]
  ECaptureNamed p _ -> [ p ]
  ELabel _ e -> [ e ]
  _ -> []

mapPairExpr :: CMapPair -> Array CExpr
mapPairExpr (CMAtom _ v) = [ v ]
mapPairExpr (CMKey k v) = [ k, v ]

-- | The `ipt` parity unit: each function's parameters' inferred types (`name/i=>type`), under a
-- | filled `ic`.
inferParamTypeSexpr :: String -> String
inferParamTypeSexpr src =
  joinWith ";" (sortWith identity (concatMap perFunc funcs))
  where
  prog = parseToProg src
  funcs = prog.funcs <> concatMap _.funcs prog.mods
  ic0 = programIc prog
  ic = ic0 { funs = fillLocalRets funcs ic0 }
  perFunc f = mapWithIndex (\i _ -> f.name <> "/" <> show i <> "=>" <> tyStr (inferParamType f i ic)) f.params

--------------------------------------------------------------------------------
-- error sets (ADR-0040 §4): a Result(T, E) return's produced error set ⊆ E
--------------------------------------------------------------------------------

-- sum type name → its variant tag names (the error-set table).
errorSetsTable :: Prog -> Array (Tuple String (Array String))
errorSetsTable prog = map (\t -> Tuple t.name (map _.ctor t.variants)) (allTypes prog)

-- a `Result(T, E)` return's declared error set: `E` expanded to its variant tags (`{E}` for a bare
-- name), with the error-type name — else `Nothing` (not a Result).
declaredSet :: Array (Tuple String (Array String)) -> String -> Maybe (Tuple String (Array String))
declaredSet tsets ret = case Str.stripPrefix (Str.Pattern "Result(") ret of
  Nothing -> Nothing
  Just rest ->
    let parts = splitTopCommas (chopLastParen rest)
    in
      if length parts == 2 then case index parts 0, index parts 1 of
        Just okT, Just errT -> if okT /= "" then Just (Tuple errT (fromMaybe [ errT ] (map snd (find (\(Tuple n _) -> n == errT) tsets)))) else Nothing
        _, _ -> Nothing
      else Nothing

-- the tags a function directly builds (`{:error, Tag}`) over its clause bodies.
directTags :: Func -> Array String
directTags f = nub (concatMap (\c -> maybe [] (\b -> errorTags (bodySurface b)) c.body) f.clauses)

-- functions whose errors propagate (a `with`-clause source when the `with` has no `else`).
propagatedCallees :: Func -> Array String
propagatedCallees f = concatMap (\c -> maybe [] (\b -> withCallees (bodySurface b)) c.body) f.clauses

errorTags :: P.Surface -> Array String
errorTags node = case node of
  P.STuple elems -> case errorPayload elems of
    Just e -> maybe [] (\t -> [ t ]) (tagName e) <> errorTags e
    Nothing -> concatMap errorTags (surfaceChildren node)
  _ -> concatMap errorTags (surfaceChildren node)

errorPayload :: Array P.Surface -> Maybe P.Surface
errorPayload elems = case index elems 0 of
  Just (P.SAtom "error") -> if length elems == 2 then index elems 1 else Nothing
  _ -> Nothing

tagName :: P.Surface -> Maybe String
tagName (P.SId n) = if pascalStr n then Just n else Nothing
tagName (P.SCall (P.SId n) _) = if pascalStr n then Just n else Nothing
tagName _ = Nothing

pascalStr :: String -> Boolean
pascalStr s = maybe false isUpper (head (toCharArray s))

withCallees :: P.Surface -> Array String
withCallees node = case node of
  P.SWith clauses body arms ->
    if null arms then concatMap (\c -> callName c.expr) clauses <> withCallees body <> concatMap (\c -> withCallees c.expr) clauses
    else concatMap withCallees (surfaceChildren node)
  _ -> concatMap withCallees (surfaceChildren node)

callName :: P.Surface -> Array String
callName (P.SCall (P.SId n) _) = [ n ]
callName _ = []

-- direct sub-expressions of a surface node (the generic error_tags / with_callees recurse).
surfaceChildren :: P.Surface -> Array P.Surface
surfaceChildren = case _ of
  P.SUnary _ x -> [ x ]
  P.SBin _ l r -> [ l, r ]
  P.SCall f as -> [ f ] <> as
  P.SDot h _ -> [ h ]
  P.SLabel _ e -> [ e ]
  P.SCapture b -> [ b ]
  P.SCaptureNamed p _ -> [ p ]
  P.SLambda _ b -> [ b ]
  P.SIf c t e -> [ c, t, e ]
  P.SCase s arms -> [ s ] <> concatMap armSurf arms
  P.SWith cls body arms -> map _.expr cls <> [ body ] <> concatMap armSurf arms
  P.SBlock stmts -> concatMap stmtSurf stmts
  P.SListLit es tl -> es <> fromFoldable tl
  P.SMapLit ps -> concatMap mapPairSurf ps
  P.SMapUpdate base ps -> [ base ] <> concatMap mapPairSurf ps
  P.STuple es -> es
  P.SFor cls body -> concatMap forSurf cls <> [ body ]
  P.SStrInterp parts -> concatMap ipartSurf parts
  _ -> []

armSurf :: P.Arm -> Array P.Surface
armSurf a = fromFoldable a.guard <> [ a.body ]

stmtSurf :: P.Stmt -> Array P.Surface
stmtSurf (P.StBind _ e) = [ e ]
stmtSurf (P.StTypedBind _ _ e) = [ e ]
stmtSurf (P.StBindArrow _ e) = [ e ]
stmtSurf (P.StBindPat _ e) = [ e ]
stmtSurf (P.StExpr e) = [ e ]

mapPairSurf :: P.MapPair -> Array P.Surface
mapPairSurf (P.MAtom _ v) = [ v ]
mapPairSurf (P.MKey k v) = [ k, v ]

forSurf :: P.ForClause -> Array P.Surface
forSurf (P.FGen _ src) = [ src ]
forSurf (P.FFilter c) = [ c ]

ipartSurf :: P.IPart -> Array P.Surface
ipartSurf (P.ILit _) = []
ipartSurf (P.IHole e) = [ e ]

-- | Solve every function's error set by call-graph fixpoint: a declared `E` exposes exactly `E`;
-- | an unannotated one infers `direct ∪ ⋃ callee-set`, iterated until stable (sets only grow).
solveErrorSets :: Array Func -> Array (Tuple String (Array String)) -> Array (Tuple (Tuple String Int) (Array String))
solveErrorSets funcs tsets = esFixpoint facts (map (\(Tuple n fc) -> Tuple n (fromMaybe fc.direct fc.declared)) facts)
  where
  facts = map (\f -> Tuple (Tuple f.name (length f.params)) { direct: directTags f, callees: propagatedCallees f, declared: f.ret >>= \r -> map snd (declaredSet tsets r) }) funcs

esFixpoint
  :: Array (Tuple (Tuple String Int) { direct :: Array String, callees :: Array String, declared :: Maybe (Array String) })
  -> Array (Tuple (Tuple String Int) (Array String))
  -> Array (Tuple (Tuple String Int) (Array String))
esFixpoint facts table =
  let
    step (Tuple n fc) = case fc.declared of
      Just d -> Tuple n d
      Nothing -> Tuple n (foldl (\acc c -> unionTags acc (propagatedFor table c)) fc.direct fc.callees)
    next = map step facts
  in
    if next == table then table else esFixpoint facts next

propagatedFor :: Array (Tuple (Tuple String Int) (Array String)) -> String -> Array String
propagatedFor table name = foldl unionTags [] (map snd (filter (\(Tuple (Tuple n _) _) -> n == name) table))

unionTags :: Array String -> Array String -> Array String
unionTags a b = sortWith identity (nub (a <> b))

-- a function's produced error set: directly-built tags ∪ propagated callee sets.
producedSet :: Array (Tuple (Tuple String Int) (Array String)) -> Func -> Array String
producedSet table f = unionTags (directTags f) (foldl (\acc c -> unionTags acc (propagatedFor table c)) [] (propagatedCallees f))

-- a Result return's produced set must be a subset of its declared `E`.
checkErrorSet :: Array (Tuple String (Array String)) -> Array (Tuple (Tuple String Int) (Array String)) -> Func -> Maybe String
checkErrorSet tsets table f = case f.ret of
  Nothing -> Nothing
  Just ret -> case declaredSet tsets ret of
    Nothing -> Nothing
    Just (Tuple errT declared) ->
      let extra = filter (\t -> not (elem t declared)) (producedSet table f)
      in
        if null extra then Nothing
        else Just ("`" <> f.name <> "`: returns error(s) " <> inspectStrs extra <> " not in its declared set `" <> errT <> "`")

inspectStrs :: Array String -> String
inspectStrs xs = "[" <> joinWith ", " (map (\x -> "\"" <> x <> "\"") xs) <> "]"

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

--------------------------------------------------------------------------------
-- the whole-program inference context (`ic`) — `program_ic`'s base tables
--------------------------------------------------------------------------------

-- | The whole-program inference context the program-level `infer` clauses consult: ctor field
-- | types (flow narrowing), single-variant field types (`.f`), function returns + signatures,
-- | ctor→type, range/opaque/impl/bound tables. (The `funs` fixpoint fill — `fill_local_rets`,
-- | which needs `infer_return_type` — lands with the inference threading; here `funs` is raw.)
type Ic =
  { tdefs :: Array (Tuple String (Array String))
  , fields :: Array (Tuple String (Array (Tuple String String)))
  , funs :: Array (Tuple (Tuple String Int) (Maybe String))
  , fsigs :: Array (Tuple (Tuple String Int) Fsig)
  , ctors :: Array (Tuple String String)
  , ranges :: Array (Tuple String RangeInfo)
  , opaques :: Array (Tuple String OpaqueInfo)
  , impls :: Array (Tuple String (Array String))
  , fbounds :: Array (Tuple String Fbound)
  }

type Fsig = { params :: Array (Maybe String), ret :: Maybe String, tvars :: Array String }
type RangeInfo = { base :: String, lo :: Int, hi :: Int }
type OpaqueInfo = { base :: String, ops :: Array String, casts :: Array String }
type Fbound = { params :: Array (Maybe String), tvars :: Array String, bounds :: Array (Tuple String (Array String)) }

-- | Build the inference context from a parsed program (mirrors `Rian.Check.program_ic`).
programIc :: Prog -> Ic
programIc prog =
  { tdefs: typeTable types
  , fields: fieldTable types
  , funs: map (\f -> Tuple (key f) f.ret) allFuncs
  , fsigs: map (\f -> Tuple (key f) (fsig f)) allFuncs
  , ctors: ctorTypes types prog
  , ranges: map (\r -> Tuple r.name { base: r.base, lo: r.lo, hi: r.hi }) allRanges
  , opaques: map (\o -> Tuple o.name { base: o.base, ops: o.ops, casts: o.casts }) allOpaques
  , impls: implTable prog
  , fbounds: fboundTable allFuncs
  }
  where
  types = allTypes prog
  allFuncs = prog.funcs <> concatMap _.funcs prog.mods
  allRanges = prog.ranges <> concatMap _.ranges prog.mods
  allOpaques = prog.opaques <> concatMap _.opaques prog.mods
  key f = Tuple f.name (length f.params)

-- prelude `Option` is prepended (a `case` over it is total, ADR-0047 §3).
allTypes :: Prog -> Array Type
allTypes prog = withPrelude (prog.types <> concatMap _.types prog.mods)

-- every sum-variant ctor → its ordered field types (flow narrowing).
typeTable :: Array Type -> Array (Tuple String (Array String))
typeTable types = concatMap (\t -> map (\v -> Tuple v.ctor (map _.ty v.fields)) t.variants) types

-- a single-variant struct/record's ctor → its named `(field, type)` pairs (for `p.field`).
fieldTable :: Array Type -> Array (Tuple String (Array (Tuple String String)))
fieldTable types = mapMaybe single types
  where
  single t = if length t.variants == 1 then map variantFields (head t.variants) else Nothing
  variantFields v = Tuple v.ctor (mapMaybe labeled v.fields)
  labeled fl = map (\l -> Tuple l fl.ty) fl.label

fsig :: Func -> Fsig
fsig f = { params: map _.ty f.params, ret: f.ret, tvars: f.tvars }

-- variant ctor → its sum type's name; a struct ctor builds its own type.
ctorTypes :: Array Type -> Prog -> Array (Tuple String String)
ctorTypes types prog =
  concatMap (\t -> map (\v -> Tuple v.ctor t.name) t.variants) types
    <> map (\s -> Tuple s.name s.name) (prog.structs <> concatMap _.structs prog.mods)

-- protocol name → the (sorted) set of types that `impl` it.
implTable :: Prog -> Array (Tuple String (Array String))
implTable prog =
  map (\p -> Tuple p (sortWith identity (nub (typesOf p)))) protos
  where
  pairs = map (\i -> Tuple i.proto i.ty) prog.implDecls
  protos = nub (map fst pairs)
  typesOf p = map snd (filter (\(Tuple pr _) -> pr == p) pairs)

-- bounded generics only: fn name → its params / tvars / bounds (call-site instantiation).
fboundTable :: Array Func -> Array (Tuple String Fbound)
fboundTable funcs =
  map (\f -> Tuple f.name { params: map _.ty f.params, tvars: f.tvars, bounds: f.bounds })
    (filter (\f -> not (null f.bounds)) funcs)

-- | The `pic` parity unit: dump `programIc`'s tables (each sorted by key) for a parsed scope.
programIcSexpr :: String -> String
programIcSexpr src =
  joinWith "\n"
    [ "tdefs " <> dump (\fts -> joinWith "," fts) ic.tdefs
    , "fields " <> dump (\fs -> joinWith "," (map (\(Tuple f t) -> f <> ":" <> t) fs)) ic.fields
    , "funs " <> dumpK keyStr maybeStr ic.funs
    , "fsigs " <> dumpK keyStr fsigStr ic.fsigs
    , "ctors " <> dump identity ic.ctors
    , "ranges " <> dump (\r -> r.base <> ":" <> show r.lo <> ":" <> show r.hi) ic.ranges
    , "opaques " <> dump (\o -> o.base <> "|" <> joinWith "," o.ops <> "|" <> joinWith "," o.casts) ic.opaques
    , "impls " <> dump (joinWith ",") ic.impls
    , "fbounds " <> dump fboundStr ic.fbounds
    ]
  where
  ic = programIc (parseToProg src)
  keyStr (Tuple n a) = n <> "/" <> show a
  maybeStr = fromMaybe "_"
  fsigStr s = joinWith "," (map maybeStr s.params) <> "|" <> maybeStr s.ret <> "|" <> joinWith "," s.tvars
  fboundStr fb = joinWith "," (map maybeStr fb.params) <> "|" <> joinWith "," fb.tvars
    <> "|" <> joinWith "," (map (\(Tuple t bs) -> t <> ":" <> joinWith "+" bs) fb.bounds)

-- render a `key → value` table sorted by key (String key).
dump :: forall v. (v -> String) -> Array (Tuple String v) -> String
dump f tbl = joinWith ";" (map (\(Tuple k v) -> k <> "=>" <> f v) (sortWith fst tbl))

-- render a table with a non-String key, sorted by its rendered key.
dumpK :: forall k v. (k -> String) -> (v -> String) -> Array (Tuple k v) -> String
dumpK kf vf tbl = joinWith ";" (sortWith identity (map (\(Tuple k v) -> kf k <> "=>" <> vf v) tbl))
