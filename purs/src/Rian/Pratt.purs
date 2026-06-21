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
  , Arm
  , Param
  , Stmt(..)
  , Pat(..)
  , MapPatPair(..)
  , WithClause
  , ForClause(..)
  , IPart(..)
  , parse
  , parseSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Enum (fromEnum)
import Data.Foldable (elem, foldMap)
import Data.Int as Int
import Data.List (List(..), (:))
import Data.List as List
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CodePoints as CP
import Data.String.Common (joinWith, replaceAll)
import Data.String.Pattern (Pattern(..), Replacement(..))
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Lexer (exprTokens)
import Rian.Token (Token(..), StrPart(..))

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
  | SIf Surface Surface Surface -- then/else are blocks
  | SCase Surface (Array Arm)
  | SLambda (Array Param) Surface
  | SBlock (Array Stmt)
  | SWith (Array WithClause) Surface (Array Arm)
  | SFor (Array ForClause) Surface
  | SStrInterp (Array IPart) -- `"… ${e} …"` (ADR-0069), holes re-parsed as expressions

-- a map-literal pair: atom-key shorthand `k: v`, or a computed key `keyExpr => v`.
data MapPair
  = MAtom String Surface
  | MKey Surface Surface

-- a `with` clause `pat <- expr`.
type WithClause = { pat :: Pat, expr :: Surface }

-- a `for` clause: a generator `pat <- src` or a boolean filter.
data ForClause
  = FGen Pat Surface
  | FFilter Surface

-- a segment of an interpolated string: a literal run, or a re-parsed `${…}` hole.
data IPart
  = ILit String
  | IHole Surface

-- a `case`/`with`-else arm; the guard is rendered nowhere (matching `sexpr/1`).
type Arm = { pat :: Pat, guard :: Maybe Surface, body :: Surface }

-- a lambda parameter: a name with an optional declared type.
type Param = { name :: String, ty :: Maybe String }

-- a block statement: a simple bind, a typed bind, or an expression.
data Stmt
  = StBind String Surface
  | StTypedBind String String Surface
  | StExpr Surface

-- surface patterns (clause heads & case arms). Bitstring patterns are stage 2.
data Pat
  = PWild
  | PLitInt Int
  | PLitStr String
  | PCharLit Int
  | PAtom String
  | PTuple (Array Pat)
  | PListP (Array Pat) (Maybe Pat)
  | PCtor String (Array Pat)
  | PStruct String (Array (Tuple String Pat))
  | PVar String
  | PAs String Pat
  | PTyped String String
  | PPin Surface
  | PMap (Array MapPatPair)

data MapPatPair
  = MPAtom String Pat
  | MPKey Surface Pat

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
parsePrimary (TKw "if" : rest) = parseIf rest
parsePrimary (TKw "case" : rest) = parseCase rest
parsePrimary (TKw "with" : rest) = parseWith rest
parsePrimary (TKw "for" : rest) = parseFor rest
parsePrimary (TLbracket : rest) = parseList rest []
parsePrimary (TMapopen : rest) = parseMapStart rest
parsePrimary (TBitopen : _) = stage2 "bitstring"
parsePrimary (TLbrace : rest) = parseTuple rest []
parsePrimary toks@(TLparen : rest) =
  if lambdaAhead toks then parseLambda toks
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
parsePrimary (TIstr parts : rest) = parsePostfix (strInterp parts) rest
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

expectKw :: List Token -> String -> List Token
expectKw (TKw x : rest) k | x == k = rest
expectKw toks k = unsafeCrashWith ("Pratt: expected `" <> k <> "`, got " <> here toks)

firstCp :: String -> Maybe Int
firstCp s = Array.head (map fromEnum (CP.toCodePointArray s))

isUpperHead :: String -> Boolean
isUpperHead s = case firstCp s of
  Just c -> c >= 65 && c <= 90
  Nothing -> false

isLowerHead :: String -> Boolean
isLowerHead s = case firstCp s of
  Just c -> c >= 97 && c <= 122
  Nothing -> false

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
-- if / case / lambda / blocks
--------------------------------------------------------------------------------

parseIf :: List Token -> Parsed Surface
parseIf tokens =
  let
    Tuple cnd t1 = parseExpr tokens 0
    t2 = expectKw t1 "do"
    Tuple thenB t3 = parseBlock t2
    Tuple elseB t4 = case t3 of
      (TKw "else" : r) -> parseBlock r
      _ -> Tuple (SBlock []) t3
    t5 = expectKw t4 "end"
  in Tuple (SIf cnd thenB elseB) t5

parseCase :: List Token -> Parsed Surface
parseCase tokens =
  let
    Tuple scrut t1 = parseExpr tokens 0
    t2 = expectKw t1 "do"
    Tuple arms t3 = parseArms t2 []
    t4 = expectKw t3 "end"
  in Tuple (SCase scrut arms) t4

parseArms :: List Token -> Array Arm -> Parsed (Array Arm)
parseArms toks@(TKw "end" : _) acc = Tuple (Array.reverse acc) toks
parseArms tokens acc =
  let
    Tuple pat t1 = parsePat tokens
    Tuple guard t2 = case t1 of
      (TKw "when" : r) -> let Tuple g r2 = parseExpr r 0 in Tuple (Just g) r2
      _ -> Tuple Nothing t1
    t3 = expectOp2 t2 "->"
    Tuple body t4 = parseBlockValue t3
  in parseArms t4 (Array.cons { pat, guard, body } acc)

-- a `->` body unwraps a single-expression block back to a bare expression.
parseBlockValue :: List Token -> Parsed Surface
parseBlockValue tokens = case parseBlock tokens of
  Tuple (SBlock [ StExpr e ]) rest -> Tuple e rest
  Tuple block rest -> Tuple block rest

parseLambda :: List Token -> Parsed Surface
parseLambda (TLparen : rest) =
  let
    Tuple params t1 = parseParams rest
    t2 = expectOp2 t1 "->"
    Tuple body t3 = parseLambdaBody t2
  in Tuple (SLambda params body) t3
parseLambda toks = unsafeCrashWith ("Pratt: bad lambda: " <> here toks)

parseLambdaBody :: List Token -> Parsed Surface
parseLambdaBody (TKw "do" : rest) =
  let Tuple block r = parseBlock rest in Tuple block (expectKw r "end")
parseLambdaBody tokens = parseExpr tokens 0

parseParams :: List Token -> Parsed (Array Param)
parseParams (TRparen : rest) = Tuple [] rest
parseParams tokens =
  let Tuple param rest = parseParam tokens
  in case rest of
    (TComma : r) -> let Tuple ps r2 = parseParams r in Tuple (Array.cons param ps) r2
    (TRparen : r) -> Tuple [ param ] r
    _ -> unsafeCrashWith ("Pratt: bad lambda params: " <> here rest)

parseParam :: List Token -> Parsed Param
parseParam (TId name : TId ty : rest) = Tuple { name, ty: Just ty } rest
parseParam (TId name : rest) = Tuple { name, ty: Nothing } rest
parseParam other = unsafeCrashWith ("Pratt: bad lambda param: " <> here other)

parseBlock :: List Token -> Parsed Surface
parseBlock tokens =
  let Tuple stmts rest = parseStmts tokens [] in Tuple (SBlock (Array.reverse stmts)) rest

parseStmts :: List Token -> Array Stmt -> Parsed (Array Stmt)
parseStmts toks@(TKw k : _) acc | k == "else" || k == "end" = Tuple acc toks
parseStmts Nil acc = Tuple acc Nil
parseStmts tokens acc =
  let Tuple stmt rest = parseStmt tokens
  in case rest of
    (TSemi : r) -> parseStmts r (Array.cons stmt acc)
    _ -> Tuple (Array.cons stmt acc) rest

parseStmt :: List Token -> Parsed Stmt
parseStmt (TId name : TOp ":=" : rest) =
  let Tuple e r = parseExpr rest 0 in Tuple (StBind name e) r
parseStmt (TId _ : TOp "<-" : _) = stage2 "error-propagation `<-` bind"
parseStmt toks@(TId name : TId _ : _) =
  let
    Tuple ty afterType = parseType (List.drop 1 toks)
  in case afterType of
    (TOp ":=" : r) -> let Tuple e r2 = parseExpr r 0 in Tuple (StTypedBind name ty e) r2
    _ -> let Tuple e r2 = parseExpr toks 0 in Tuple (StExpr e) r2
parseStmt tokens = let Tuple e r = parseExpr tokens 0 in Tuple (StExpr e) r

-- a type phrase: `Name` or `Name(t1, t2, …)`, rendered with no interior spaces.
parseType :: List Token -> Parsed String
parseType (TId name : TLparen : rest) =
  let Tuple args r = parseTypeArgs rest [] in Tuple (name <> "(" <> joinWith "," args <> ")") r
parseType (TId name : rest) = Tuple name rest
parseType other = unsafeCrashWith ("Pratt: malformed type: " <> here other)

parseTypeArgs :: List Token -> Array String -> Parsed (Array String)
parseTypeArgs tokens acc =
  let Tuple t rest = parseType tokens
  in case rest of
    (TRparen : r) -> Tuple (Array.reverse (Array.cons t acc)) r
    (TComma : r) -> parseTypeArgs r (Array.cons t acc)
    _ -> unsafeCrashWith ("Pratt: malformed type argument list: " <> here rest)

--------------------------------------------------------------------------------
-- with / for (comprehension) / string interpolation
--------------------------------------------------------------------------------

parseWith :: List Token -> Parsed Surface
parseWith tokens =
  let
    Tuple clauses t1 = parseWithClauses tokens []
    t2 = expectKw t1 "do"
    Tuple body t3 = parseBlock t2
    Tuple els t4 = case t3 of
      (TKw "else" : r) -> parseArms r []
      _ -> Tuple [] t3
    t5 = expectKw t4 "end"
  in Tuple (SWith clauses body els) t5

parseWithClauses :: List Token -> Array WithClause -> Parsed (Array WithClause)
parseWithClauses tokens acc =
  let
    Tuple pat t1 = parsePat tokens
    t2 = expectOp2 t1 "<-"
    Tuple expr t3 = parseExpr t2 0
    acc' = Array.cons { pat, expr } acc
  in case t3 of
    (TComma : r) -> parseWithClauses r acc'
    _ -> Tuple (Array.reverse acc') t3

parseFor :: List Token -> Parsed Surface
parseFor tokens =
  let
    Tuple clauses t1 = parseForClauses tokens []
    t2 = expectKw t1 "do"
    Tuple body t3 = parseBlock t2
    t4 = expectKw t3 "end"
  in Tuple (SFor clauses body) t4

parseForClauses :: List Token -> Array ForClause -> Parsed (Array ForClause)
parseForClauses tokens acc =
  let Tuple clause rest = parseForClause tokens
      acc' = Array.cons clause acc
  in case rest of
    (TComma : r) -> parseForClauses r acc'
    _ -> Tuple (Array.reverse acc') rest

parseForClause :: List Token -> Parsed ForClause
parseForClause tokens =
  if forGenerator tokens 0 then
    let
      Tuple pat r1 = parsePat tokens
      r2 = expectOp2 r1 "<-"
      Tuple src r3 = parseExpr r2 0
    in Tuple (FGen pat src) r3
  else
    let Tuple expr r = parseExpr tokens 0 in Tuple (FFilter expr) r

-- a generator iff a top-level `<-` precedes the clause boundary (`,`/`do` at depth 0).
forGenerator :: List Token -> Int -> Boolean
forGenerator (TOp "<-" : _) 0 = true
forGenerator (TComma : _) 0 = false
forGenerator (TKw "do" : _) 0 = false
forGenerator Nil _ = false
forGenerator (t : rest) depth = forGenerator rest (depth + forDepth t)

forDepth :: Token -> Int
forDepth TLparen = 1
forDepth TLbracket = 1
forDepth TLbrace = 1
forDepth TMapopen = 1
forDepth TBitopen = 1
forDepth TRparen = -1
forDepth TRbracket = -1
forDepth TRbrace = -1
forDepth TBitclose = -1
forDepth _ = 0

-- build the interpolation node: literal segments pass through; each hole's raw source
-- is re-parsed as an expression (an empty hole is a parse error).
strInterp :: Array StrPart -> Surface
strInterp parts = SStrInterp (map resolve parts)
  where
  resolve (Lit s) = ILit s
  resolve (Hole src) =
    if trimmedEmpty src then unsafeCrashWith "Pratt: empty interpolation hole `${}`"
    else IHole (parse src)
  trimmedEmpty s = replaceAll (Pattern " ") (Replacement "") s == ""

--------------------------------------------------------------------------------
-- Patterns (the one pattern parser, ADR-0050 §2)
--------------------------------------------------------------------------------

parsePat :: List Token -> Parsed Pat
parsePat (TId "_" : rest) = Tuple PWild rest
parsePat (TOp "-" : TNum n : rest) = Tuple (PLitInt (negate (intOf n))) rest
parsePat (TNum n : rest) = Tuple (PLitInt (intOf n)) rest
parsePat (TChar cp : rest) = Tuple (PCharLit cp) rest
parsePat (TOp ":" : TId name : rest) = Tuple (PAtom name) rest
parsePat (TOp ":" : TKw name : rest) = Tuple (PAtom name) rest
parsePat (TOp ":" : TStr s : rest) = Tuple (PAtom s) rest
parsePat (TStr s : rest) = Tuple (PLitStr s) rest
parsePat (TLbrace : rest) = parsePatTuple rest []
parsePat (TLparen : rest) =
  let Tuple p r = parsePat rest
  in case r of
    (TRparen : r2) -> Tuple p r2
    (TComma : r2) -> parseParenPatTuple r2 [ p ]
    _ -> unsafeCrashWith ("Pratt: expected `)` or `,` in pattern, got " <> here r)
parsePat (TLbracket : rest) = parsePatList rest []
parsePat (TMapopen : rest) = parsePatMap rest []
parsePat (TBitopen : _) = stage2 "bitstring pattern"
parsePat (TOp "^" : rest) = let Tuple e r = parseExpr rest 0 in Tuple (PPin e) r
parsePat (TId name : TOp "@" : rest) = let Tuple p r = parsePat rest in Tuple (PAs name p) r
parsePat (TId name : TId ty : rest) | isLowerHead name && isUpperHead ty = Tuple (PTyped name ty) rest
parsePat (TId name : rest) =
  if isUpperHead name then case rest of
    (TLparen : TId _ : TOp ":" : _) -> parsePatStruct name rest
    (TLparen : TKw _ : TOp ":" : _) -> parsePatStruct name rest
    (TLparen : r) -> let Tuple args r2 = parsePatArgs r [] in Tuple (PCtor name args) r2
    _ -> Tuple (PCtor name []) rest
  else Tuple (PVar name) rest
parsePat other = unsafeCrashWith ("Pratt: unsupported pattern: " <> here other)

parsePatStruct :: String -> List Token -> Parsed Pat
parsePatStruct name (TLparen : rest) =
  let Tuple fields r = parsePatFields rest [] in Tuple (PStruct name fields) r
parsePatStruct _ other = unsafeCrashWith ("Pratt: bad struct pattern: " <> here other)

parsePatFields :: List Token -> Array (Tuple String Pat) -> Parsed (Array (Tuple String Pat))
parsePatFields (TRparen : rest) acc = Tuple (Array.reverse acc) rest
parsePatFields (TId k : TOp ":" : rest) acc = patFieldAfter k rest acc
parsePatFields (TKw k : TOp ":" : rest) acc = patFieldAfter k rest acc
parsePatFields other _ = unsafeCrashWith ("Pratt: bad struct pattern fields: " <> here other)

patFieldAfter :: String -> List Token -> Array (Tuple String Pat) -> Parsed (Array (Tuple String Pat))
patFieldAfter k rest acc =
  let Tuple p r = parsePat rest
  in case r of
    (TComma : r2) -> parsePatFields r2 (Array.cons (Tuple k p) acc)
    (TRparen : r2) -> Tuple (Array.reverse (Array.cons (Tuple k p) acc)) r2
    _ -> unsafeCrashWith ("Pratt: bad struct pattern: " <> here r)

parsePatArgs :: List Token -> Array Pat -> Parsed (Array Pat)
parsePatArgs (TRparen : rest) acc = Tuple (Array.reverse acc) rest
parsePatArgs tokens acc =
  let Tuple p rest = parsePat tokens
  in case rest of
    (TComma : r) -> parsePatArgs r (Array.cons p acc)
    (TRparen : r) -> Tuple (Array.reverse (Array.cons p acc)) r
    _ -> unsafeCrashWith ("Pratt: expected `,` or `)` in pattern, got " <> here rest)

parsePatTuple :: List Token -> Array Pat -> Parsed Pat
parsePatTuple (TRbrace : rest) acc = Tuple (PTuple (Array.reverse acc)) rest
parsePatTuple tokens acc =
  let Tuple p rest = parsePat tokens
  in case rest of
    (TComma : r) -> parsePatTuple r (Array.cons p acc)
    (TRbrace : r) -> Tuple (PTuple (Array.reverse (Array.cons p acc))) r
    _ -> unsafeCrashWith ("Pratt: bad tuple pattern: " <> here rest)

parseParenPatTuple :: List Token -> Array Pat -> Parsed Pat
parseParenPatTuple tokens acc =
  let Tuple p rest = parsePat tokens
  in case rest of
    (TComma : r) -> parseParenPatTuple r (Array.cons p acc)
    (TRparen : r) -> Tuple (PTuple (Array.reverse (Array.cons p acc))) r
    _ -> unsafeCrashWith ("Pratt: expected `,` or `)` in tuple pattern, got " <> here rest)

parsePatList :: List Token -> Array Pat -> Parsed Pat
parsePatList (TRbracket : rest) acc = Tuple (PListP (Array.reverse acc) Nothing) rest
parsePatList tokens acc =
  let Tuple p rest = parsePat tokens
  in case rest of
    (TComma : r) -> parsePatList r (Array.cons p acc)
    (TRbracket : r) -> Tuple (PListP (Array.reverse (Array.cons p acc)) Nothing) r
    (TOp "|" : r) ->
      let Tuple tl r2 = parsePat r in Tuple (PListP (Array.reverse (Array.cons p acc)) (Just tl)) (expectRbracket r2)
    _ -> unsafeCrashWith ("Pratt: bad list pattern: " <> here rest)

parsePatMap :: List Token -> Array MapPatPair -> Parsed Pat
parsePatMap (TRbrace : rest) acc = Tuple (PMap (Array.reverse acc)) rest
parsePatMap (TId k : TOp ":" : rest) acc =
  let Tuple p r = parsePat rest in patMapAfter r (Array.cons (MPAtom k p) acc)
parsePatMap (TKw k : TOp ":" : rest) acc =
  let Tuple p r = parsePat rest in patMapAfter r (Array.cons (MPAtom k p) acc)
parsePatMap tokens acc =
  let
    Tuple k rest = parseExpr tokens 0
    r = expectOp2 rest "=>"
    Tuple p r2 = parsePat r
  in patMapAfter r2 (Array.cons (MPKey k p) acc)

patMapAfter :: List Token -> Array MapPatPair -> Parsed Pat
patMapAfter (TComma : r) acc = parsePatMap r acc
patMapAfter (TRbrace : r) acc = Tuple (PMap (Array.reverse acc)) r
patMapAfter other _ = unsafeCrashWith ("Pratt: bad map pattern: " <> here other)

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
sexpr (SIf c t e) = "(if " <> sexpr c <> " " <> sexpr t <> " " <> sexpr e <> ")"
sexpr (SCase s arms) =
  "(case " <> sexpr s <> foldMap (\a -> " (" <> sexprPat a.pat <> " -> " <> sexpr a.body <> ")") arms <> ")"
sexpr (SLambda ps b) =
  "(lambda (" <> joinWith " " (map _.name ps) <> ") " <> sexpr b <> ")"
sexpr (SBlock stmts) = "(block" <> foldMap (\s -> " " <> sexprStmt s) stmts <> ")"
sexpr (SWith clauses body els) =
  "(with " <> joinWith " " (map withClause clauses) <> " " <> sexpr body <> elseArms els <> ")"
  where
  withClause c = "(<- " <> sexprPat c.pat <> " " <> sexpr c.expr <> ")"
  elseArms [] = ""
  elseArms arms = " (else" <> foldMap (\a -> " (" <> sexprPat a.pat <> " -> " <> sexpr a.body <> ")") arms <> ")"
sexpr (SFor clauses body) =
  "(for " <> joinWith " " (map forClause clauses) <> " " <> sexpr body <> ")"
  where
  forClause (FGen p src) = "(<- " <> sexprPat p <> " " <> sexpr src <> ")"
  forClause (FFilter c) = "(? " <> sexpr c <> ")"
sexpr (SStrInterp parts) = "(str-interp " <> joinWith " " (map iPart parts) <> ")"
  where
  iPart (ILit s) = "\"" <> s <> "\""
  iPart (IHole e) = "${" <> sexpr e <> "}"

sexprMapPair :: MapPair -> String
sexprMapPair (MAtom k v) = k <> ": " <> sexpr v
sexprMapPair (MKey k v) = sexpr k <> " => " <> sexpr v

sexprStmt :: Stmt -> String
sexprStmt (StBind n e) = "(:= " <> n <> " " <> sexpr e <> ")"
sexprStmt (StTypedBind n t e) = "(:= " <> n <> " " <> t <> " " <> sexpr e <> ")"
sexprStmt (StExpr e) = sexpr e

sexprPat :: Pat -> String
sexprPat PWild = "_"
sexprPat (PLitStr v) = "\"" <> v <> "\""
sexprPat (PLitInt v) = show v
sexprPat (PCharLit cp) = "?" <> show cp
sexprPat (PAtom a) = ":" <> a
sexprPat (PTuple ps) = "{" <> joinWith ", " (map sexprPat ps) <> "}"
sexprPat (PListP ps Nothing) = "[" <> joinWith ", " (map sexprPat ps) <> "]"
sexprPat (PListP ps (Just t)) = "[" <> joinWith ", " (map sexprPat ps) <> " | " <> sexprPat t <> "]"
sexprPat (PVar x) = x
sexprPat (PAs n p) = "(@ " <> n <> " " <> sexprPat p <> ")"
sexprPat (PCtor n []) = n
sexprPat (PCtor n args) = n <> "(" <> joinWith ", " (map sexprPat args) <> ")"
sexprPat (PMap fields) = "%{" <> joinWith ", " (map sexprMapPatPair fields) <> "}"
sexprPat (PStruct n fields) =
  n <> "(" <> joinWith ", " (map (\(Tuple k p) -> k <> ": " <> sexprPat p) fields) <> ")"
sexprPat (PPin e) = "(^ " <> sexpr e <> ")"
-- a type-pattern has no `sexpr_pat` clause in the reference (it crashes there too); it is
-- excluded from the parity corpus.
sexprPat (PTyped _ _) = unsafeCrashWith "Pratt: sexpr of a type-pattern (no reference clause)"

sexprMapPatPair :: MapPatPair -> String
sexprMapPatPair (MPAtom k p) = k <> ": " <> sexprPat p
sexprMapPatPair (MPKey k p) = sexpr k <> " => " <> sexprPat p
