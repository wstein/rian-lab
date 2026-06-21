-- | Test entry point for the PureScript/purerl port (ADR-0084).
-- |
-- | Run with `spago test` once the purerl toolchain is bootstrapped (see
-- | `purs/README.md`). Each migrated module gets a spec here; the lexer/parser
-- | specs additionally assert **parity** against the Elixir reference's recorded
-- | token/AST fixtures, so a ported module is a regression test, not a demo
-- | (mirrors `Rian.Fixpoint` in the Elixir tree).
-- |
-- | This module imports `spec`/`effect` from the package set and therefore only
-- | typechecks after the toolchain bootstrap; the Prim-only `Rian.Token` invariants
-- | are checked offline by `purs compile` (see the README's verification section).
module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)

import Rian.Token (Token(..), isNewline, isTrivia, tokenName)

main :: Effect Unit
main = launchAff_ $ runSpec [ consoleReporter ] do
  describe "Rian.Token" do
    it "classifies the newline separator" do
      isNewline TNl `shouldEqual` true
      isNewline (TOp ":=") `shouldEqual` false
    it "classifies formatter-only trivia" do
      isTrivia (TComment "# hi") `shouldEqual` true
      isTrivia (THeredoc "doc") `shouldEqual` true
      isTrivia (TStr "x") `shouldEqual` false
    it "names constructors for diagnostics" do
      tokenName (TId "empty?") `shouldEqual` "TId"
      tokenName TMapopen `shouldEqual` "TMapopen"
