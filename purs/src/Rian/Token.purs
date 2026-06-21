-- | The lexer token — the data spine shared by `Rian.Lexer`, `Rian.Pratt`, and
-- | the self-hosted compiler (it is the surface `Token` sum named in
-- | `Rian.Lexer`'s `@rian_sig`). This is the first module of the Elixir → PureScript
-- | migration (ADR-0084): the leaf-most shared type, so everything downstream can
-- | depend on it.
module Rian.Token
  ( Token(..)
  , isNewline
  , isTrivia
  , tokenName
  ) where

import Prelude

import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)

-- | A lexer token. Mirrors `Rian.Lexer`'s `@type token` (lib/rian/lexer.ex) and the
-- | self-hosted `Token` sum one-for-one, so the migrated lexer can emit it directly.
data Token
  = TNl
  | TLparen
  | TRparen
  | TLbracket
  | TRbracket
  | TLbrace
  | TRbrace
  | TMapopen
  | TBitopen
  | TBitclose
  | TComma
  | TSemi
  | TStr String
  | TChar Int
  | TNum String
  | TOp String
  | TKw String
  | TId String
  | TAnnot String
  | TComment String
  | THeredoc String

derive instance Eq Token
derive instance Generic Token _

-- | `show` renders the constructor with its payload (`(TStr "x")`), so token streams
-- | print readably in parity-test failures.
instance Show Token where
  show = genericShow

-- | A significant newline separator (`{:nl}`). Drives the declaration stream;
-- | stripped from the expression stream.
isNewline :: Token -> Boolean
isNewline TNl = true
isNewline _ = false

-- | Formatter-only trivia the compiler pipeline discards (`strip_trivia/1`):
-- | comments and the raw heredoc form.
isTrivia :: Token -> Boolean
isTrivia (TComment _) = true
isTrivia (THeredoc _) = true
isTrivia _ = false

-- | The token's constructor name — used for diagnostics and the parity harness.
tokenName :: Token -> String
tokenName TNl = "TNl"
tokenName TLparen = "TLparen"
tokenName TRparen = "TRparen"
tokenName TLbracket = "TLbracket"
tokenName TRbracket = "TRbracket"
tokenName TLbrace = "TLbrace"
tokenName TRbrace = "TRbrace"
tokenName TMapopen = "TMapopen"
tokenName TBitopen = "TBitopen"
tokenName TBitclose = "TBitclose"
tokenName TComma = "TComma"
tokenName TSemi = "TSemi"
tokenName (TStr _) = "TStr"
tokenName (TChar _) = "TChar"
tokenName (TNum _) = "TNum"
tokenName (TOp _) = "TOp"
tokenName (TKw _) = "TKw"
tokenName (TId _) = "TId"
tokenName (TAnnot _) = "TAnnot"
tokenName (TComment _) = "TComment"
tokenName (THeredoc _) = "THeredoc"
