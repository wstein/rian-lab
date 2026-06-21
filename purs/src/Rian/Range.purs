-- | Desugars **range construction** `Name.of(n)` (ADR-0036) into a portable in-bounds
-- | check over the typed Core, given the program's range table — the PureScript port of
-- | `Rian.Range` (lib/rian/range.ex), ADR-0084. A `range Digit := 0..9` gives a checked
-- | constructor `Digit.of(n) : Digit | RangeError`; rather than teach every emitter a new
-- | construct, `Name.of(n)` rewrites *before* lowering to an ordinary `if`-`Result`:
-- |
-- |     Digit.of(n)  ~>  if 0 <= n and n <= 9 do {:ok, n} else {:error, RangeError} end
-- |
-- | The Elixir reference walks the Core generically; here it is a structural recursion over
-- | `Rian.Core`'s `CExpr`. (`table/1`, which builds the table from `IR.Range`, lands with
-- | `Decl`'s range stage; this module is the rewrite itself.)
module Rian.Range
  ( Bound
  , Table
  , expandOf
  , expandOfSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Rian.Core (CExpr(..), CMapPair(..), CStmt(..), coreSexpr, fromExpr)
import Rian.Pratt (parse)

type Bound = { lo :: Int, hi :: Int }
type Table = Array (Tuple String Bound)

lookupBound :: String -> Table -> Maybe Bound
lookupBound n = map snd <<< Array.find (\t -> fst t == n)

-- | Rewrite every `Name.of(n)` (for a `Name` in `table`) in a core expression; identity when
-- | the table is empty.
-- @rian_sig pub def expandOf(node val Expr, table val Dict(String, Bound)) Expr
expandOf :: Table -> CExpr -> CExpr
expandOf table node = if Array.null table then node else go node
  where
  go (ECall (EDot (EId n) "of") [ a ]) = case lookupBound n table of
    Just b -> check b.lo b.hi (go a)
    Nothing -> ECall (EDot (EId n) "of") [ go a ]
  go (EUnary op x) = EUnary op (go x)
  go (EBin op l r) = EBin op (go l) (go r)
  go (ECall f args) = ECall (go f) (map go args)
  go (EDot h n) = EDot (go h) n
  go (EIf c t e) = EIf (go c) (go t) (go e)
  go (ECase s arms) = ECase (go s) (map goArm arms)
  go (EWith cls body els) = EWith (map goWith cls) (go body) (map goArm els)
  go (EBlock stmts) = EBlock (map goStmt stmts)
  go (EList es tl) = EList (map go es) (map go tl)
  go (EMap ps) = EMap (map goMapPair ps)
  go (ETuple es) = ETuple (map go es)
  go (ELambda ps b) = ELambda ps (go b)
  go (ECapture b) = ECapture (go b)
  go (ECaptureNamed p a) = ECaptureNamed (go p) a
  go (ELabel n e) = ELabel n (go e)
  go leaf = leaf -- ENum, EStr, EChar, EId, EAtom, ECapArg
  goArm a = a { guard = map go a.guard, body = go a.body }
  goWith c = c { expr = go c.expr }
  goStmt (CBind n e) = CBind n (go e)
  goStmt (CTypedBind n t e) = CTypedBind n t (go e)
  goStmt (CExprStmt e) = CExprStmt (go e)
  goMapPair (CMAtom k v) = CMAtom k (go v)
  goMapPair (CMKey k v) = CMKey (go k) (go v)

-- `if lo <= a and a <= hi do {:ok, a} else {:error, RangeError} end`
check :: Int -> Int -> CExpr -> CExpr
check lo hi a =
  EIf
    (EBin "and" (EBin "<=" (lit lo) a) (EBin "<=" a (lit hi)))
    (ETuple [ EAtom "ok", a ])
    (ETuple [ EAtom "error", EId "RangeError" ])

lit :: Int -> CExpr
lit n = ENum (show n)

-- | The `rng` parity-stream entry: parse, lower to Core, rewrite with a fixed test table,
-- | and render. The table must match the one in `gen_fixtures.exs`.
expandOfSexpr :: String -> String
expandOfSexpr = coreSexpr <<< expandOf testTable <<< fromExpr <<< parse

testTable :: Table
testTable = [ Tuple "Digit" { lo: 0, hi: 9 }, Tuple "Byte" { lo: 0, hi: 255 } ]
