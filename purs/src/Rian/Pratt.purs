-- | Precedence-climbing parser for Rian expressions — the PureScript port of
-- | `Rian.Pratt` (lib/rian/pratt.ex), ADR-0084 Phase 3. Consumes `Rian.Lexer`'s
-- | newline-free `exprTokens` stream and produces the **surface AST** that
-- | `Rian.Core.from_expr` lowers into the typed Core.
-- |
-- | **Staged port.** This module currently covers the expression grammar core
-- | (literals, the full operator-precedence table, calls, dot access, parens/tuples,
-- | lists, map literals, captures, labeled arguments). The remaining forms —
-- | `if`/`case`/`with`/`for`/`lambda`/blocks, patterns, bitstrings, `${}`
-- | interpolation, and map *update* — raise a clear "stage 2" error and are excluded
-- | from the parity corpus, exactly as the partial JS/JVM emitters raise `Unsupported`.
-- | Parity is gated by the reference's own `parse_sexpr` renderer (see `parseSexpr`).
module Rian.Pratt
  ( Surface(..)
  , MapPair(..)
  , parse
  , parseSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (elem, foldMap)
import Data.Int as Int
import Data.List (List(..), (:))
import Data.List as List
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.Common (joinWith, replaceAll)
import Data.String.Pattern (Pattern(..), Replacement(..))
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Lexer (exprTokens)
import Rian.Token (Token(..))

--------------------------------------------------------------------------------
-- Surface AST (the transient tuple AST in the Elixir reference, as a real sum)
--------------------------------------------------------------------------------

data Surface
  = SNum String
  | SStr String
  | SChar Int
  | SId String
  | SAtom String
  | SUnary String Surface
  | SBin String Surface Surface
  | SCall Surface (Array Surface)
  | SDot Surface String
  | SLabel String Surface
  | SCapture Surface
  | SCaptureNamed Surface Int
  | SCapArg Int
  | STuple (Array Surface)
  | SListLit (Array Surface) (Maybe Surface) -- Nothing = closed `[…]`, Just = cons `[… | t]`
  | SMapLit (Array MapPair)

-- a map-literal pair: atom-key shorthand `k: v`, or a computed key `keyExpr => v`.
data MapPair
  = MAtom String Surface
  | MKey Surface Surface

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

type Parsed a = Tuple a (List Token)

-- @rian_sig pub def parse(src val String) _Unk
parse :: String -> Surface
parse src =
  let Tuple ast rest = parseExpr (List.fromFoldable (exprTokens src)) 0
  in if List.null rest then ast else unsafeCrashWith ("Pratt: trailing tokens: " <> here rest)

-- @rian_sig pub def parseSexpr(src val String) String
parseSexpr :: String -> String
parseSexpr = sexpr <<< parse

--------------------------------------------------------------------------------
-- Operator precedence (opinfo/bp, mirroring pratt.ex)
--------------------------------------------------------------------------------

data Assoc = AL | AR | AN

derive instance Eq Assoc

infixOps :: Array String
infixOps =
  [ "+", "-", "*", "/", "rem", "div", "<>", "in", "|>", "<", "<=", ">", ">="
  , "==", "!=", "and", "or", "<~", ".."
  ]

opinfo :: String -> { lvl :: Int, assoc :: Assoc }
opinfo op
  | op `elem` [ "*", "/", "rem", "div" ] = { lvl: 3, assoc: AL }
  | op `elem` [ "+", "-" ] = { lvl: 4, assoc: AL }
  | op == "<>" = { lvl: 5, assoc: AR }
  | op == "in" = { lvl: 6, assoc: AN }
  | op == ".." = { lvl: 6, assoc: AN }
  | op == "|>" = { lvl: 7, assoc: AL }
  | op `elem` [ "<", "<=", ">", ">=" ] = { lvl: 8, assoc: AN }
  | op `elem` [ "==", "!=" ] = { lvl: 9, assoc: AN }
  | op == "and" = { lvl: 10, assoc: AL }
  | op == "or" = { lvl: 11, assoc: AL }
  | op == "<~" = { lvl: 12, assoc: AR }
  | otherwise = unsafeCrashWith ("Pratt: no precedence for operator `" <> op <> "`")

level :: String -> Int
level op = (opinfo op).lvl

-- left/right binding powers; non-assoc shares the left form (the `same_level_root?`
-- check rejects an actual chain).
bp :: String -> { l :: Int, r :: Int }
bp op =
  let info = opinfo op
      base = (13 - info.lvl) * 10
  in case info.assoc of
    AL -> { l: base, r: base + 1 }
    AR -> { l: base + 1, r: base }
    AN -> { l: base, r: base + 1 }

--------------------------------------------------------------------------------
-- Precedence climbing
--------------------------------------------------------------------------------

parseExpr :: List Token -> Int -> Parsed Surface
parseExpr toks minBp =
  let Tuple lhs rest = parsePrefix toks
  in climb lhs rest minBp

climb :: Surface -> List Token -> Int -> Parsed Surface
climb lhs toks minBp = case peekInfix toks of
  Nothing -> Tuple lhs toks
  Just op ->
    let powers = bp op
    in
      if powers.l < minBp then Tuple lhs toks
      else if (opinfo op).assoc == AN && sameLevelRoot lhs op then
        unsafeCrashWith ("Pratt: `" <> op <> "` is non-associative; parenthesize")
      else
        let Tuple rhs rest = parseExpr (List.drop 1 toks) powers.r
        in climb (SBin op lhs rhs) rest minBp

peekInfix :: List Token -> Maybe String
peekInfix (TOp op : _) | op `elem` infixOps = Just op
peekInfix _ = Nothing

sameLevelRoot :: Surface -> String -> Boolean
sameLevelRoot (SBin op2 _ _) op = level op2 == level op
sameLevelRoot _ _ = false

--------------------------------------------------------------------------------
-- Prefix / primary / postfix
--------------------------------------------------------------------------------

parsePrefix :: List Token -> Parsed Surface
parsePrefix (TOp op : rest) | op == "-" || op == "not" =
  let Tuple operand r = parseExpr rest 110 in Tuple (SUnary op operand) r
parsePrefix (TOp "&" : rest) = parseCapture rest
parsePrefix toks = parsePrimary toks

parsePrimary :: List Token -> Parsed Surface
parsePrimary (TKw "if" : _) = stage2 "if"
parsePrimary (TKw "case" : _) = stage2 "case"
parsePrimary (TKw "with" : _) = stage2 "with"
parsePrimary (TKw "for" : _) = stage2 "for"
parsePrimary (TLbracket : rest) = parseList rest []
parsePrimary (TMapopen : rest) = parseMapStart rest
parsePrimary (TBitopen : _) = stage2 "bitstring"
parsePrimary (TLbrace : rest) = parseTuple rest []
parsePrimary toks@(TLparen : rest) =
  if lambdaAhead toks then stage2 "lambda"
  else
    let Tuple e r = parseExpr rest 0
    in case r of
      (TRparen : r2) -> parsePostfix e r2
      (TComma : r2) -> let Tuple tup r3 = parseParenTuple r2 [ e ] in parsePostfix tup r3
      _ -> unsafeCrashWith ("Pratt: expected `)`, got " <> here r)
parsePrimary (TOp ":" : TId name : rest) = parsePostfix (SAtom name) rest
parsePrimary (TOp ":" : TKw name : rest) = parsePostfix (SAtom name) rest
parsePrimary (TOp ":" : TStr s : rest) = parsePostfix (SAtom s) rest
parsePrimary (TStr s : rest) = parsePostfix (SStr s) rest
parsePrimary (TIstr _ : _) = stage2 "string interpolation"
parsePrimary (TNum n : rest) = parsePostfix (SNum n) rest
parsePrimary (TChar cp : rest) = parsePostfix (SChar cp) rest
parsePrimary (TId x : rest) = parsePostfix (SId x) rest
parsePrimary other = unsafeCrashWith ("Pratt: unexpected token: " <> here other)

parsePostfix :: Surface -> List Token -> Parsed Surface
parsePostfix node (TOp "." : TId n : rest) = parsePostfix (SDot node n) rest
parsePostfix node (TOp "." : TKw n : rest) = parsePostfix (SDot node n) rest
parsePostfix node (TLparen : rest) =
  let Tuple args rest2 = parseArgs rest in parsePostfix (SCall node args) rest2
parsePostfix node toks = Tuple node toks

--------------------------------------------------------------------------------
-- Call arguments (with labeled `name: expr`)
--------------------------------------------------------------------------------

parseArgs :: List Token -> Parsed (Array Surface)
parseArgs (TRparen : rest) = Tuple [] rest
parseArgs (TId name : TOp ":" : rest) =
  let Tuple v r = parseExpr rest 0 in finishArg (SLabel name v) r
parseArgs (TKw name : TOp ":" : rest) =
  let Tuple v r = parseExpr rest 0 in finishArg (SLabel name v) r
parseArgs toks =
  let Tuple a r = parseExpr toks 0 in finishArg a r

finishArg :: Surface -> List Token -> Parsed (Array Surface)
finishArg a (TComma : rest) = let Tuple more r = parseArgs rest in Tuple (Array.cons a more) r
finishArg a (TRparen : rest) = Tuple [ a ] rest
finishArg _ _ = unsafeCrashWith "Pratt: expected `,` or `)` in arguments"

--------------------------------------------------------------------------------
-- Captures (`&(…)`, `&name/arity`, `&N`)
--------------------------------------------------------------------------------

parseCapture :: List Token -> Parsed Surface
parseCapture (TNum n : rest) = parsePostfix (SCapArg (intOf n)) rest
parseCapture (TLparen : rest) =
  let Tuple body r = parseExpr rest 0 in Tuple (SCapture body) (expectRparen r)
parseCapture toks =
  let Tuple path rest = parsePath toks
  in case expectSlash rest of
    (TNum n : r) -> Tuple (SCaptureNamed path (intOf n)) r
    _ -> unsafeCrashWith "Pratt: expected an integer arity after `/`"

parsePath :: List Token -> Parsed Surface
parsePath (TOp ":" : TId name : rest) = collectDots (SAtom name) rest
parsePath (TOp ":" : TKw name : rest) = collectDots (SAtom name) rest
parsePath (TOp ":" : TStr s : rest) = collectDots (SAtom s) rest
parsePath (TId name : rest) = collectDots (SId name) rest
parsePath other = unsafeCrashWith ("Pratt: bad capture path: " <> here other)

collectDots :: Surface -> List Token -> Parsed Surface
collectDots node (TOp "." : TId n : rest) = collectDots (SDot node n) rest
collectDots node rest = Tuple node rest

--------------------------------------------------------------------------------
-- Collections: list, tuple, paren-tuple, map literal
--------------------------------------------------------------------------------

parseList :: List Token -> Array Surface -> Parsed Surface
parseList (TRbracket : rest) acc = Tuple (SListLit (Array.reverse acc) Nothing) rest
parseList toks acc =
  let Tuple e rest = parseExpr toks 0
  in case rest of
    (TComma : r) -> parseList r (Array.cons e acc)
    (TRbracket : r) -> Tuple (SListLit (Array.reverse (Array.cons e acc)) Nothing) r
    (TOp "|" : r) ->
      let Tuple tl r2 = parseExpr r 0 in Tuple (SListLit (Array.reverse (Array.cons e acc)) (Just tl)) (expectRbracket r2)
    _ -> unsafeCrashWith ("Pratt: bad list: " <> here rest)

parseTuple :: List Token -> Array Surface -> Parsed Surface
parseTuple (TRbrace : rest) acc = Tuple (STuple (Array.reverse acc)) rest
parseTuple toks acc =
  let Tuple e rest = parseExpr toks 0
  in case rest of
    (TComma : r) -> parseTuple r (Array.cons e acc)
    (TRbrace : r) -> Tuple (STuple (Array.reverse (Array.cons e acc))) r
    _ -> unsafeCrashWith ("Pratt: bad tuple: " <> here rest)

parseParenTuple :: List Token -> Array Surface -> Parsed Surface
parseParenTuple toks acc =
  let Tuple e rest = parseExpr toks 0
  in case rest of
    (TComma : r) -> parseParenTuple r (Array.cons e acc)
    (TRparen : r) -> Tuple (STuple (Array.reverse (Array.cons e acc))) r
    _ -> unsafeCrashWith ("Pratt: expected `,` or `)` in tuple, got " <> here rest)

parseMapStart :: List Token -> Parsed Surface
parseMapStart (TRbrace : rest) = Tuple (SMapLit []) rest
parseMapStart toks@(TId _ : TOp ":" : _) = mapLit (parseMapPairs toks [])
parseMapStart toks@(TKw _ : TOp ":" : _) = mapLit (parseMapPairs toks [])
parseMapStart toks =
  let Tuple first rest = parseExpr toks 0
  in case rest of
    (TOp "|" : _) -> stage2 "map update"
    (TOp "=>" : r) ->
      let Tuple v r2 = parseExpr r 0 in mapLit (mapPairsAfter r2 [ MKey first v ])
    _ -> unsafeCrashWith ("Pratt: bad map: " <> here rest)

mapLit :: Parsed (Array MapPair) -> Parsed Surface
mapLit (Tuple pairs r) = Tuple (SMapLit pairs) r

parseMapPairs :: List Token -> Array MapPair -> Parsed (Array MapPair)
parseMapPairs (TRbrace : rest) acc = Tuple (Array.reverse acc) rest
parseMapPairs (TId k : TOp ":" : rest) acc =
  let Tuple v r = parseExpr rest 0 in mapPairsAfter r (Array.cons (MAtom k v) acc)
parseMapPairs (TKw k : TOp ":" : rest) acc =
  let Tuple v r = parseExpr rest 0 in mapPairsAfter r (Array.cons (MAtom k v) acc)
parseMapPairs toks acc =
  let Tuple k rest = parseExpr toks 0
      r = expectOp2 rest "=>"
      Tuple v r2 = parseExpr r 0
  in mapPairsAfter r2 (Array.cons (MKey k v) acc)

mapPairsAfter :: List Token -> Array MapPair -> Parsed (Array MapPair)
mapPairsAfter (TComma : r) acc = parseMapPairs r acc
mapPairsAfter (TRbrace : r) acc = Tuple (Array.reverse acc) r
mapPairsAfter other _ = unsafeCrashWith ("Pratt: bad map: " <> here other)

--------------------------------------------------------------------------------
-- Lambda lookahead (so a lambda is distinguished from grouping; staged out for now)
--------------------------------------------------------------------------------

lambdaAhead :: List Token -> Boolean
lambdaAhead (TLparen : rest) = case afterParen rest 1 of
  (TOp "->" : _) -> true
  _ -> false
lambdaAhead _ = false

afterParen :: List Token -> Int -> List Token
afterParen toks 0 = toks
afterParen (TLparen : t) d = afterParen t (d + 1)
afterParen (TRparen : t) 1 = t
afterParen (TRparen : t) d = afterParen t (d - 1)
afterParen (_ : t) d = afterParen t d
afterParen Nil _ = Nil

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

intOf :: String -> Int
intOf n = fromMaybe 0 (Int.fromString (replaceAll (Pattern "_") (Replacement "") n))

expectOp2 :: List Token -> String -> List Token
expectOp2 (TOp x : rest) o | x == o = rest
expectOp2 toks o = unsafeCrashWith ("Pratt: expected `" <> o <> "`, got " <> here toks)

expectSlash :: List Token -> List Token
expectSlash (TOp "/" : rest) = rest
expectSlash toks = unsafeCrashWith ("Pratt: expected `/`, got " <> here toks)

expectRbracket :: List Token -> List Token
expectRbracket (TRbracket : rest) = rest
expectRbracket toks = unsafeCrashWith ("Pratt: expected `]`, got " <> here toks)

expectRparen :: List Token -> List Token
expectRparen (TRparen : rest) = rest
expectRparen toks = unsafeCrashWith ("Pratt: expected `)`, got " <> here toks)

stage2 :: forall a. String -> a
stage2 what = unsafeCrashWith ("Pratt: `" <> what <> "` is not yet ported (stage 2)")

here :: List Token -> String
here Nil = "end of input"
here (TOp o : _) = "operator `" <> o <> "`"
here (TKw k : _) = "keyword `" <> k <> "`"
here (TId x : _) = "identifier `" <> x <> "`"
here (TNum n : _) = "number `" <> n <> "`"
here (_ : _) = "token"

--------------------------------------------------------------------------------
-- s-expression renderer — the canonical parity oracle (mirrors sexpr/1)
--------------------------------------------------------------------------------

sexpr :: Surface -> String
sexpr (SNum n) = n
sexpr (SStr s) = "\"" <> s <> "\""
sexpr (SChar cp) = "?" <> show cp
sexpr (SId x) = x
sexpr (SAtom a) = ":" <> a
sexpr (SBin op l r) = "(" <> op <> " " <> sexpr l <> " " <> sexpr r <> ")"
sexpr (SUnary op x) = "(" <> op <> " " <> sexpr x <> ")"
sexpr (SDot o n) = "(. " <> sexpr o <> " " <> n <> ")"
sexpr (SCapArg n) = "&" <> show n
sexpr (SCapture b) = "(& " <> sexpr b <> ")"
sexpr (SCaptureNamed p a) = "(&/ " <> sexpr p <> " " <> show a <> ")"
sexpr (SLabel n e) = n <> ": " <> sexpr e
sexpr (SCall f args) = "(call " <> sexpr f <> foldMap (\a -> " " <> sexpr a) args <> ")"
sexpr (STuple es) = "{" <> joinWith " " (map sexpr es) <> "}"
sexpr (SListLit elems Nothing) = "[" <> joinWith " " (map sexpr elems) <> "]"
sexpr (SListLit elems (Just t)) = "[" <> joinWith " " (map sexpr elems) <> " | " <> sexpr t <> "]"
sexpr (SMapLit pairs) = "%{" <> joinWith " " (map sexprMapPair pairs) <> "}"

sexprMapPair :: MapPair -> String
sexprMapPair (MAtom k v) = k <> ": " <> sexpr v
sexprMapPair (MKey k v) = sexpr k <> " => " <> sexpr v
