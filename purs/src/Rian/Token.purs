-- | The lexer token — the data spine shared by `Rian.Lexer`, `Rian.Pratt`, and
-- | the self-hosted compiler (it is the surface `Token` sum named in
-- | `Rian.Lexer`'s `@rian_sig`). This is the first module of the Elixir → PureScript
-- | migration (ADR-0084): the leaf-most shared type, so everything downstream can
-- | depend on it.
-- |
-- | This module is deliberately written against only the built-in `Prim` types
-- | (no `Prelude` import) so it typechecks **offline**, before the purerl package
-- | set is fetched. Once the toolchain is bootstrapped (see `purs/README.md`), the
-- | derived `Eq`/`Show` instances and the `Data.String`-backed payload helpers move
-- | here from their hand-rolled forms.
module Rian.Token
  ( Token(..)
  , isNewline
  , isTrivia
  , tokenName
  ) where

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

-- | The token's constructor name — used for diagnostics and the parity harness
-- | (a `Prim`-only stand-in for `Show` until the package set lands).
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
