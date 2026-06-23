-- | Parse-once, lower-many front door (ADR-0090). The four source emitters (`Rian.JS`,
-- | `Rian.Lower.Rust`, `Rian.JVM`) share an identical front-end — lex → Pratt → Core →
-- | `assemble` → `runProgramTail` → `checkProgram` — and only then branch per target. Calling
-- | each `compile`/`rustProgram` separately re-runs that whole prefix per target; `prepare` runs
-- | it **once** and hands the checked `Prog` to per-target `lower*` passes.
-- |
-- | The split also keeps per-target gates independent: `prepare` raises only on a parse / shared
-- | type-gate error (the buffer is invalid for *every* target); each `lower*` raises its own
-- | target-specific rejection (a JS wide-int, a Rust-unsupported construct), which a caller can
-- | catch per pane. (BEAM is absent — `Rian.Beam` needs `:compile.forms`, an Erlang/OTP API.)
-- |
-- | This is the in-browser playground's entry (the bundle re-exports these); the Elixir tour
-- | generator can adopt the same parse-once shape.
module Rian.Lower.All
  ( Prepared
  , prepare
  , lowerJs
  , lowerTs
  , lowerRust
  , lowerJvm
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Decl (parseToProg)
import Rian.IR (Prog)
import Rian.JS (lowerJsProg, lowerTsProg) as JS
import Rian.JVM (lowerJvmProg) as JVM
import Rian.Lower.Rust (lowerRustProg) as Rust

-- | A program that has been parsed, tail-resolved (interpolation + `Show`), and passed the shared
-- | type gate — ready to lower to any target. (Opaque to callers; just thread it back in.)
type Prepared = Prog

-- | Run the shared front-end ONCE: parse → assemble → program tail → `checkProgram`. Crashes with
-- | the gate message on a type error (the buffer is invalid for every target); the same order the
-- | individual emitters use, so `lower* (prepare src)` is byte-identical to each `compile src`.
-- @rian_sig pub def prepare(src val String) Prog
prepare :: String -> Prepared
prepare src =
  case checkProgram prog0 of
    Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
    Nothing -> prog0
  where
  prog0 = runProgramTail (assemble (parseToProg src))

-- @rian_sig pub def lower_js(p val Prog) String
lowerJs :: Prepared -> String
lowerJs = JS.lowerJsProg

-- @rian_sig pub def lower_ts(p val Prog) String
lowerTs :: Prepared -> String
lowerTs = JS.lowerTsProg

-- @rian_sig pub def lower_rust(p val Prog) String
lowerRust :: Prepared -> String
lowerRust = Rust.lowerRustProg

-- @rian_sig pub def lower_jvm(p val Prog) String
lowerJvm :: Prepared -> String
lowerJvm = JVM.lowerJvmProg
