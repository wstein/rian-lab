-- | The canonical `Show` stdlib module (ADR-0069 §6 — the portable `Float64`→String formatter
-- | `Show.float`, auto-injected into `${…}` interpolation by `Rian.Assemble.injectStdlib`). The
-- | reference reads `examples/rian/stdlib_show.rian` at compile time; purerl has no compile-time
-- | file read, so the source is inlined here and parsed once. The `shs` parity stream asserts the
-- | extracted module matches the reference's (file-read) module, so any drift fails the gate.
module Rian.ShowStdlib
  ( theModule
  , moduleSexpr
  ) where

import Prelude

import Data.Array (find)
import Data.Maybe (Maybe(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Decl (modSexpr, parseToProg)
import Rian.IR (Mod)

-- inlined verbatim from examples/rian/stdlib_show.rian (leading/trailing blank lines are collapsed
-- by the lexer, so this parses to the same module the reference reads from the file).
source :: String
source = """
# ===========================================================================
# Show — portable, opt-in value→String formatting (ADR-0069 §6 / ADR-0047)
# ===========================================================================
# `Show.float` is the canonical ECMAScript `Number::toString` (ECMA-262 §7.1.12.1)
# for a `Float64`, written ONCE in portable Rian over the per-target shortest-repr
# prim `__prim_float_repr`. The shortest-round-trip *digits* are mathematically
# unique, so every backend's native formatter already agrees on them; this module
# normalizes the *presentation* (`1.0` vs `1`, exponent style) to the single ECMA
# canonical, so the output is byte-identical across targets by construction.
#
# Auto-wired into `${…}` interpolation: a `Float64` hole calls `Show.float`, and
# `Rian.Decl` injects this module on demand (ADR-0069 §6). Emits **byte-identically
# on all four targets** — `:ex`, `:js`, `:rs`, and `:jvm` — conformance-tested against
# ECMAScript `String(x)` over the exponent thresholds, subnormals, ±0, and the
# denormal extremes. (`__prim_float_repr` is contracted to return the *shortest*
# round-tripping decimal; each target's native formatter honors that, the JVM by a
# shortest-search since `Double.toString` is not always shortest at the denormals.)
#
# `__prim_float_repr` is an INTERNAL building block (each target's native shortest
# string, which diverges in presentation) — never user-facing, only consumed here.
#
# ADRs: 0069 (interpolation/Show) · 0047 (portable prelude) · 0064 (Int53)
# ---------------------------------------------------------------------------

mod Show do
  # a (digit chars, exponent) split and an (int chars, frac chars) split
  type EParts := EP(Vec(Char), Int53)
  type MParts := MP(Vec(Char), Vec(Char))
  type SParts := SP(Vec(Char), Int53)

  # ── public: ECMA-262 §7.1.12.1 canonical string for a Float64 ────────────
  pub def float(x Float64) String
  pub def float(x) := signed(Prim.str_chars(__prim_float_repr(x)))

  # a leading '-' is carried through; the magnitude is formatted canonically.
  # Negative zero stringifies WITHOUT a sign (ECMA-262 §7.1.12.1 step 1).
  def signed(cs Vec(Char)) String
  def signed(['-' | rest]) := neg(magnitude(rest))
  def signed(cs) := magnitude(cs)

  def neg(m String) String := if is_zero(m) do "0" else Prim.str_concat("-", m) end

  def is_zero(m String) Bool
  def is_zero(m)
    case Prim.str_chars(m) do
      ['0'] -> true
      _ -> false
    end
  end

  def magnitude(cs Vec(Char)) String
  def magnitude(cs)
    case split_e(cs) do
      EP(mant, e) ->
        case split_dot(mant) do
          MP(ip, fp) -> assemble(ip, fp, e)
        end
    end
  end

  # ── parse the native repr (`12.5`, `1.0e21`, `1.0E-7`, `1e+0`) ───────────
  # split at the first 'e'/'E' into (mantissa, exponent)
  def split_e(cs Vec(Char)) EParts
  def split_e([]) := EP([], 0)
  def split_e(['e' | rest]) := EP([], parse_exp(rest))
  def split_e(['E' | rest]) := EP([], parse_exp(rest))
  def split_e([c | rest])
    case split_e(rest) do
      EP(m, e) -> EP([c | m], e)
    end
  end

  # split the mantissa at '.' into (int part, frac part)
  def split_dot(cs Vec(Char)) MParts
  def split_dot([]) := MP([], [])
  def split_dot(['.' | rest]) := MP([], rest)
  def split_dot([c | rest])
    case split_dot(rest) do
      MP(i, f) -> MP([c | i], f)
    end
  end

  def parse_exp(cs Vec(Char)) Int53
  def parse_exp(['+' | rest]) := parse_nat(rest, 0)
  def parse_exp(['-' | rest]) := 0 - parse_nat(rest, 0)
  def parse_exp(cs) := parse_nat(cs, 0)

  def parse_nat(cs Vec(Char), acc Int53) Int53
  def parse_nat([], acc) := acc
  def parse_nat([c | rest], acc) := parse_nat(rest, acc * 10 + (Prim.char_code(c) - 48))

  # ── assemble the canonical form from the parsed (int, frac, exp) ─────────
  # value = (int ++ frac) · 10^(exp − len frac). With the significant digits `s`
  # (no leading/trailing zeros, length k) and n = k + (exp − len frac) + t, the
  # canonical form follows ECMA-262 §7.1.12.1 (n = the position of the point).
  def assemble(ip Vec(Char), fp Vec(Char), e Int53) String
  def assemble(ip, fp, e)
    case strip_leading(append(ip, fp)) do
      [] -> "0"
      ls ->
        case strip_trailing(ls) do
          SP(s, t) -> build(s, len(s), len(s) + (e - len(fp)) + t)
        end
    end
  end

  def build(s Vec(Char), k Int53, n Int53) String :=
    if n >= k and n <= 21 do Prim.str_from_chars(append(s, zeros(n - k)))
    else if n > 0 and n <= 21 do Prim.str_from_chars(append(take(s, n), ['.' | drop(s, n)]))
    else if n > 0 - 6 and n <= 0 do Prim.str_from_chars(append(['0', '.' | zeros(0 - n)], s))
    else sci(s, k, n - 1) end end end

  # exponential: d[.ddd]e±E
  def sci(s Vec(Char), k Int53, ex Int53) String
  def sci(s, k, ex)
    # `take(s, 1)` (not the bare slice `s`) keeps both `if` branches an owned Vec
    mant := if k == 1 do take(s, 1) else point_after_first(s) end
    esign := if ex >= 0 do "e+" else "e-" end
    Prim.str_concat(
      Prim.str_from_chars(mant),
      Prim.str_concat(esign, Prim.int_to_string(abs(ex)))
    )
  end

  def point_after_first(s Vec(Char)) Vec(Char)
  def point_after_first([c | rest]) := [c, '.' | rest]
  def point_after_first([]) := []

  # ── small portable list/char helpers ────────────────────────────────────
  def strip_leading(cs Vec(Char)) Vec(Char)
  def strip_leading(['0' | rest]) := strip_leading(rest)
  def strip_leading(cs) := cs

  # drop trailing '0's, returning the kept chars and the count dropped
  def strip_trailing(cs Vec(Char)) SParts
  def strip_trailing(cs)
    case drop_leading_count(reverse(cs, []), 0) do
      SP(rs, t) -> SP(reverse(rs, []), t)
    end
  end

  def drop_leading_count(cs Vec(Char), n Int53) SParts
  def drop_leading_count(['0' | rest], n) := drop_leading_count(rest, n + 1)
  def drop_leading_count(cs, n) := SP(cs, n)

  def reverse(cs Vec(Char), acc Vec(Char)) Vec(Char)
  def reverse([], acc) := acc
  def reverse([c | rest], acc) := reverse(rest, [c | acc])

  def append(a Vec(Char), b Vec(Char)) Vec(Char)
  def append([], b) := b
  def append([c | rest], b) := [c | append(rest, b)]

  def len(cs Vec(Char)) Int53
  def len([]) := 0
  def len([_ | rest]) := 1 + len(rest)

  def take(cs Vec(Char), n Int53) Vec(Char)
  def take(cs, 0) := []
  def take([], n) := []
  def take([c | rest], n) := [c | take(rest, n - 1)]

  def drop(cs Vec(Char), n Int53) Vec(Char)
  def drop(cs, 0) := cs
  def drop([], n) := []
  def drop([c | rest], n) := drop(rest, n - 1)

  def zeros(n Int53) Vec(Char)
  def zeros(0) := []
  def zeros(n) := ['0' | zeros(n - 1)]

  def abs(x Int53) Int53
  def abs(x) := if x >= 0 do x else 0 - x end
end
"""

-- | The parsed `Show` module. (No protocols/macros/interpolation in `Show`, so `parseToProg`
-- | yields the same module the reference's full `Decl.parse` does.)
-- @rian_sig pub def module() Mod
theModule :: Mod
theModule = case find (\m -> m.name == "Show") (parseToProg source).mods of
  Just m -> m
  Nothing -> unsafeCrashWith "Rian.ShowStdlib: no `Show` module in stdlib_show.rian"

-- | `shs` parity entry: the serialized `Show` module (input ignored — the module is fixed).
moduleSexpr :: String -> String
moduleSexpr _ = modSexpr theModule
