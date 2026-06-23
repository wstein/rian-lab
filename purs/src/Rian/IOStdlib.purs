-- | The console-I/O prelude (ADR-0068/0069/0083) — the raw per-target `line`/`write` `@external`
-- | host wrappers plus the portable polymorphic `puts`/`print` value-union front doors. The
-- | reference reads `examples/rian/prelude_io.rian` at compile time; purerl has no compile-time
-- | file read, so the code is inlined here and parsed once. `Rian.Assemble.injectStdlib` emits
-- | these functions into a program that calls `puts`/`print` (so they run on a source target,
-- | unlike the BEAM-linked `Str`/`List`/`Dict`). The `io` parity stream asserts the extracted
-- | functions match the reference's (file-read) ones, so any drift fails the gate.
-- |
-- | No interpolation here (the `Int53` arm calls `Prim.int_to_string` directly), so `parseToProg`
-- | suffices — no `runProgramTail`, hence no import cycle with `Rian.Assemble`.
module Rian.IOStdlib
  ( funcs
  ) where

import Rian.Decl (parseToProg)
import Rian.IR (Func)

-- inlined from examples/rian/prelude_io.rian (comments stripped — the lexer drops them, so this
-- parses to the same functions the reference reads from the file).
source :: String
source =
  """
@external(:ex, "IO.puts(s)")
@external(:js, "console.log(s)")
@external(:rs, "println!(\"{}\", s)")
@external(:jvm, "println(s)")
pub def line(s val String) Unit

@external(:ex, "IO.write(s)")
@external(:js, "process.stdout.write(s)")
@external(:rs, "print!(\"{}\", s)")
@external(:jvm, "print(s)")
pub def write(s val String) Unit

pub def puts(x String | Int53) Unit := case x do
  s String -> line(s)
  n Int53 -> line(Prim.int_to_string(n))
end

pub def print(x String | Int53) Unit := case x do
  s String -> write(s)
  n Int53 -> write(Prim.int_to_string(n))
end
"""

-- | The IO functions (`line`/`write` host wrappers + the polymorphic `puts`/`print`), top-level.
-- @rian_sig pub def funcs() Vec(Func)
funcs :: Array Func
funcs = (parseToProg source).funcs
