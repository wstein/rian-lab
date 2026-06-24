-- | Compile-time evaluation — `comptime(expr)` (ADR-0030) — the PureScript port of
-- | `Rian.Comptime` (lib/rian/comptime.ex), ADR-0084. A pure surface AST → AST pass: a
-- | `comptime(e)` call is replaced by the constant `e` evaluates to in a sandboxed evaluator
-- | (arithmetic / comparison / boolean over literals — no calls, vars, or FFI). The other half of
-- | the `lower_meta` tail pass (with `Macro.expand`); it runs even when no macros are declared.
module Rian.Comptime
  ( fold
  , foldConstants
  , literal
  , unwrapBlock
  , substitute
  , inlinableBody
  ) where

import Prelude

import Data.Array (any, head, length, nub)
import Data.Either (Either(..))
import Data.Foldable (find)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String (Pattern(..), contains, replaceAll, Replacement(..)) as Str
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Macro (childrenOf, mapNode)
import Rian.Pratt (Stmt(..), Surface(..))

-- a compile-time value: an arbitrary-precision concept narrowed here to `Int`, `Number`, `Bool`.
data CtVal = CtInt Int | CtFloat Number | CtBool Boolean

-- | EXPLICIT `comptime(e)` — fold to the constant `e` evaluates to (crashes on a non-constant, the
-- | loose escape hatch); recurse into all other nodes. Used by `lower_meta` (Assemble).
-- @rian_sig pub def fold(node val Surface) Surface
fold :: Surface -> Surface
fold node@(SCall (SId "comptime") args) =
  if length args == 1 then case head args of
    Just e -> foldVal (eval e)
    Nothing -> mapNode fold node
  else mapNode fold node
fold node = mapNode fold node

-- | AUTOMATIC constant folding (ADR-0046): fold any pure constant `+ - * / div rem`/comparison/
-- | boolean expression to its literal. OPPORTUNISTIC (a non-constant operand just leaves the node)
-- | and TYPE-PRESERVING: folds only when the numeric literals are kind-homogeneous (all int OR all
-- | float), so it never folds a mixed `Int * Float` the checker rejects. A distinct program-tail
-- | pass (`Assemble.runProgramTail`); mirrors `Rian.Comptime.fold_constants`.
-- @rian_sig pub def fold_constants(node val Surface) Surface
foldConstants :: Surface -> Surface
foldConstants (SBin op l r) = foldBin op (foldConstants l) (foldConstants r)
foldConstants (SUnary op x) | op == "-" || op == "not" = foldEval (SUnary op (foldConstants x))
foldConstants node = mapNode foldConstants node

-- operands folded first; then simplify by operator. `<>` over two string literals concatenates;
-- the evaluation-preserving boolean identities (`true and x` → `x`, etc.) drop no operand (so no
-- effect/Reach change — the dropping pair is left to the backend's short-circuit). Mirrors `fold_bin`.
foldBin :: String -> Surface -> Surface -> Surface
foldBin "<>" (SStr a) (SStr b) = SStr (a <> b)
foldBin op l r = foldEval (SBin op l r)

foldEval :: Surface -> Surface
foldEval node =
  if homogeneousNums node then case eval node of
    Right v -> valSurface v
    Left _ -> node
  else node

foldVal :: Either String CtVal -> Surface
foldVal (Right v) = valSurface v
foldVal (Left reason) = unsafeCrashWith ("comptime: " <> reason)

valSurface :: CtVal -> Surface
valSurface (CtInt n) = SNum (show n)
valSurface (CtFloat f) = SNum (show f)
valSurface (CtBool true) = SId "true"
valSurface (CtBool false) = SId "false"

-- all numeric literals in the arithmetic subtree the same kind? (a mixed set is a cross-kind op the
-- checker rejects — refuse to fold). A non-arithmetic child contributes nothing; `eval` fails on it.
homogeneousNums :: Surface -> Boolean
homogeneousNums node = length (nub (numKinds node)) <= 1

numKinds :: Surface -> Array String
numKinds (SNum n) = [ numKind n ]
numKinds (SBin _ l r) = numKinds l <> numKinds r
numKinds (SUnary _ x) = numKinds x
numKinds _ = []

numKind :: String -> String
numKind n =
  let clean = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n
  in
    if Str.contains (Str.Pattern ".") clean || Str.contains (Str.Pattern "e") clean || Str.contains (Str.Pattern "E") clean then "float"
    else "int"

-- ── the pure sandboxed evaluator ──
eval :: Surface -> Either String CtVal
eval (SNum n) =
  let clean = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n in
  if Str.contains (Str.Pattern ".") clean || Str.contains (Str.Pattern "e") clean || Str.contains (Str.Pattern "E") clean then
    case Number.fromString clean of
      Just f -> Right (CtFloat f)
      Nothing -> Left ("bad number `" <> n <> "`")
  else case Int.fromString clean of
    Just i -> Right (CtInt i)
    Nothing -> Left ("bad number `" <> n <> "`")
eval (SUnary "-" x) = map negateVal (eval x)
eval (SUnary "not" x) = do
  v <- eval x
  case v of
    CtBool b -> Right (CtBool (not b))
    _ -> Left "comptime: `not` expects a boolean"
eval (SBin op l r) = do
  a <- eval l
  b <- eval r
  binOp op a b
eval (SCall _ _) = Left "calls are not allowed in a pure comptime sandbox"
eval (SId "true") = Right (CtBool true)
eval (SId "false") = Right (CtBool false)
eval (SId x) = Left ("`" <> x <> "` is not a compile-time constant")
eval (SDot _ _) = Left "FFI/field access is not allowed in comptime"
eval _ = Left "unsupported in comptime"

negateVal :: CtVal -> CtVal
negateVal (CtInt n) = CtInt (-n)
negateVal (CtFloat f) = CtFloat (-f)
negateVal v = v

binOp :: String -> CtVal -> CtVal -> Either String CtVal
binOp "+" a b = numBin (+) (+) a b
binOp "-" a b = numBin (-) (-) a b
binOp "*" a b = numBin (*) (*) a b
binOp "/" a b = case toNum a, toNum b of
  Just _, Just 0.0 -> Left "division by zero"
  Just x, Just y -> Right (CtFloat (x / y))
  _, _ -> Left "`/` requires numbers"
binOp "div" a b = intDiv div a b
binOp "rem" a b = intDiv mod a b
binOp "<" a b = cmpVal "<" a b
binOp "<=" a b = cmpVal "<=" a b
binOp ">" a b = cmpVal ">" a b
binOp ">=" a b = cmpVal ">=" a b
binOp "==" a b = cmpVal "==" a b
binOp "!=" a b = cmpVal "!=" a b
binOp "and" a b = boolOp (&&) a b
binOp "or" a b = boolOp (||) a b
binOp op _ _ = Left ("operator `" <> op <> "` not allowed in comptime")

boolOp :: (Boolean -> Boolean -> Boolean) -> CtVal -> CtVal -> Either String CtVal
boolOp f (CtBool p) (CtBool q) = Right (CtBool (f p q))
boolOp _ _ _ = Left "`and`/`or` require booleans"

-- int op when both are int, else widen to float (mirrors Erlang's polymorphic numbers).
numBin :: (Int -> Int -> Int) -> (Number -> Number -> Number) -> CtVal -> CtVal -> Either String CtVal
numBin fi _ (CtInt a) (CtInt b) = Right (CtInt (fi a b))
numBin _ ff a b = case toNum a, toNum b of
  Just x, Just y -> Right (CtFloat (ff x y))
  _, _ -> Left "arithmetic requires numbers"

intDiv :: (Int -> Int -> Int) -> CtVal -> CtVal -> Either String CtVal
intDiv _ _ (CtInt 0) = Left "division by zero"
intDiv f (CtInt a) (CtInt b) = Right (CtInt (f a b))
intDiv _ _ _ = Left "`div`/`rem` require integer operands"

-- a comparison yields a `Bool`; numbers compare numerically (int vs float widen), bools by value.
cmpVal :: String -> CtVal -> CtVal -> Either String CtVal
cmpVal op a b = case toNum a, toNum b of
  Just x, Just y -> Right (CtBool (numCmp op x y))
  _, _ -> case a, b of
    CtBool p, CtBool q -> Right (CtBool (boolCmp op p q))
    _, _ -> Left "comparison requires comparable operands"

numCmp :: String -> Number -> Number -> Boolean
numCmp "<" x y = x < y
numCmp "<=" x y = x <= y
numCmp ">" x y = x > y
numCmp ">=" x y = x >= y
numCmp "==" x y = x == y
numCmp _ x y = x /= y

boolCmp :: String -> Boolean -> Boolean -> Boolean
boolCmp "==" p q = p == q
boolCmp "!=" p q = p /= q
boolCmp "<" p q = p < q
boolCmp "<=" p q = p <= q
boolCmp ">" p q = p > q
boolCmp _ p q = p >= q

toNum :: CtVal -> Maybe Number
toNum (CtInt n) = Just (Int.toNumber n)
toNum (CtFloat f) = Just f
toNum _ = Nothing

-- ── helpers shared with the post-check `Rian.Optimize` pass (constant call inlining) ──

-- | Is `node` a constant literal (num / string / `Char` / `true`/`false`)?
literal :: Surface -> Boolean
literal (SNum _) = true
literal (SStr _) = true
literal (SChar _) = true
literal (SId "true") = true
literal (SId "false") = true
literal _ = false

-- | Unwrap a single-expression block to that expression (else identity).
unwrapBlock :: Surface -> Surface
unwrapBlock (SBlock [ StExpr e ]) = e
unwrapBlock node = node

-- | Substitute `subst` (param name → value) into a surface body everywhere. Sound only on a
-- | binder-free body (`inlinableBody`), so no `SId` reference is ever a shadowed binding.
substitute :: Array (Tuple String Surface) -> Surface -> Surface
substitute subst (SId name) = case find (\(Tuple k _) -> k == name) subst of
  Just (Tuple _ v) -> v
  Nothing -> SId name
substitute subst node = mapNode (substitute subst) node

-- | Is a function body safe to inline by substituting its params? — true iff BINDER-FREE (no
-- | `:=`/lambda/`case`/`with`), so substitution can never land in a scope that shadows a param.
inlinableBody :: Surface -> Boolean
inlinableBody = not <<< hasBinders

hasBinders :: Surface -> Boolean
hasBinders (SLambda _ _) = true
hasBinders (SCase _ _) = true
hasBinders (SWith _ _ _) = true
hasBinders node@(SBlock stmts) = any bindStmt stmts || any hasBinders (childrenOf node)
  where
  bindStmt (StBind _ _) = true
  bindStmt (StTypedBind _ _ _) = true
  bindStmt _ = false
hasBinders node = any hasBinders (childrenOf node)
