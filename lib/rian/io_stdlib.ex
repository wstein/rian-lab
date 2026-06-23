defmodule Rian.IOStdlib do
  @moduledoc false
  use Rian.Ann

  # The console-I/O prelude (ADR-0068/0069) — the `Console` raw per-target host wrappers plus the
  # portable polymorphic `puts`/`print` — parsed ONCE at compile time from the documented source
  # and baked into the BEAM. Unlike the BEAM-linked `List`/`Str`/`Dict` (`Rian.Prelude`), these
  # bodies are **emitted into a program** that references them (`Rian.Decl.inject_stdlib`), so
  # `puts`/`print` actually run on a source target (`console.log`/`println`/`IO.puts`).
  #
  # Parsing here runs the full program tail (so the `${n}` holes in `puts` resolve to
  # `__prim_int_to_string` via the narrowing pass) — but `inject_stdlib`'s IO branch is guarded by
  # `io_defined?`, which is TRUE for this source, so it does not recurse into itself.
  @path Path.join([__DIR__, "..", "..", "examples", "rian", "prelude_io.rian"])
  @external_resource @path
  @prog @path |> File.read!() |> Rian.Decl.parse()

  @doc "The IO functions (`line`/`write` host wrappers + polymorphic `puts`/`print`), top-level."
  @rian_sig "pub def funcs() Vec(Func)"
  @spec funcs() :: [struct()]
  def funcs, do: @prog.funcs
end
