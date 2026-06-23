-- | Run a `.rian` program on the BEAM — the non-interactive runner (ADR-0031), the PureScript port
-- | of `Rian.Run` (lib/rian/run.ex). `eval` gates the source, loads every module (+ the portable
-- | prelude), finds the single module exporting a zero-arg entry (default `main`), applies it, and
-- | returns its value as `Right rendered` (the `~p` image) or an error as `Left msg` — errors-as-
-- | values (ADR-0035): a parse/check failure short-circuits, a successful run's value comes back.
-- |
-- | NOT ported (the file/Manifest/bundling half — `run_file`/`bundle_and_load`/`cli`): they read
-- | files, resolve `@external(:ex)` file-references against the project root, and bundle foreign
-- | `.ffi.ex` via `Rian.External.lower_beam` — all at the Erlang-FFI / filesystem boundary, not this
-- | string-in/value-out leaf. The run mechanics live in `Rian.Beam.runEntry` (which owns the BEAM
-- | compile/load/apply FFI); this module is the thin errors-as-values shape over it.
module Rian.Run
  ( eval
  , evalCanon
  ) where

import Prelude

import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), stripPrefix) as Str
import Rian.Beam (runEntry)

-- | Evaluate Rian `src`: gate it, load every module, and apply the zero-arg entry `main_` — `Right
-- | value` (the `~p`-rendered result) or `Left message`. Mirrors `Rian.Run.eval/2`.
-- @rian_sig pub def eval(src val String, main_ val String) Result(String, String)
eval :: String -> String -> Either String String
eval src main_ = case Str.stripPrefix (Str.Pattern "ok\t") tagged of
  Just v -> Right v
  Nothing -> Left (fromOk (Str.stripPrefix (Str.Pattern "error\t") tagged))
  where
  tagged = runEntry src main_
  fromOk = case _ of
    Just m -> m
    Nothing -> tagged -- a malformed tag is itself the (unexpected) message

-- | Parity entry (`run` stream): render `eval` to a canonical string — `"ok:<value>"` / `"error:<msg>"`
-- | — matching the Elixir reference's same rendering, so the runner's value/error contract is gated.
evalCanon :: String -> String -> String
evalCanon src main_ = either (\m -> "error:" <> m) (\v -> "ok:" <> v) (eval src main_)
