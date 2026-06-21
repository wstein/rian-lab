-- | Compile-time evaluation — `comptime(expr)` (ADR-0030) — the PureScript port of
-- | `Rian.Comptime` (lib/rian/comptime.ex), ADR-0084. A pure surface AST → AST pass: a
-- | `comptime(e)` call is replaced by the constant `e` evaluates to in a sandboxed evaluator
-- | (arithmetic / comparison / boolean over literals — no calls, vars, or FFI). The other half of
-- | the `lower_meta` tail pass (with `Macro.expand`); it runs even when no macros are declared.
module Rian.Comptime
  ( fold
  ) where

import Prelude

import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String (Pattern(..), contains, replaceAll, Replacement(..)) as Str
import Partial.Unsafe (unsafeCrashWith)
import Rian.Macro (mapNode)
import Rian.Pratt (Surface(..))

-- a compile-time value: an arbitrary-precision concept narrowed here to `Int`, `Number`, `Bool`.
data CtVal = CtInt Int | CtFloat Number | CtBool Boolean

-- | Fold every `comptime(e)` to the constant `e` evaluates to; recurse into all other nodes.
-- @rian_sig pub def fold(node val Surface) Surface
fold :: Surface -> Surface
fold node@(SCall (SId "comptime") args) =
  if length args == 1 then case head args of
    Just e -> foldVal (eval e)
    Nothing -> mapNode fold node
  else mapNode fold node
fold node = mapNode fold node

foldVal :: Either String CtVal -> Surface
foldVal (Right (CtInt n)) = SNum (show n)
foldVal (Right (CtFloat f)) = SNum (show f)
foldVal (Right (CtBool true)) = SId "true"
foldVal (Right (CtBool false)) = SId "false"
foldVal (Left reason) = unsafeCrashWith ("comptime: " <> reason)

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
binOp op _ _ = Left ("operator `" <> op <> "` not allowed in comptime")

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
