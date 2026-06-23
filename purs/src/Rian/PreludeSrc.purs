-- | The portable-prelude `.rian` sources (`List`/`Dict`/`Str`/`Int`, ADR-0047 §2), **bundled** into
-- | the compiler so `Rian.Beam` can compile + load them as private `Elixir.Rian.Prelude.<Name>`
-- | modules with no source tree at runtime — the PureScript analogue of the Elixir reference's
-- | `@external_resource` + compile-time `File.read!` (`lib/rian/prelude.ex`). GENERATED from
-- | `examples/rian/prelude_{int,str,dict,list}.rian` by `scripts/gen_prelude_src.exs`; do not edit by
-- | hand — regenerate when a prelude source changes (a drift surfaces as a `beam`-stream miss).
module Rian.PreludeSrc
  ( sources
  ) where

-- | The four portable-prelude module sources (`Int`/`Str`/`Dict`/`List`).
sources :: Array String
sources =
  [
  -- examples/rian/prelude_int.rian
  """
# ===========================================================================
# PORTABLE PRELUDE (ADR-0047 §2) — `Int`, explicit overflow ops (ADR-0035 §3)
# ===========================================================================
# Bare `+`/`-`/`*` on `Int64` are *native per target* (ADR-0034 decision-lock):
# a BEAM/JS bignum/BigInt that never overflows, a Rust `i64` that panics (debug)
# or wraps (release). That divergence is documented, never silent — but when you
# need a SINGLE deterministic answer across every backend, reach for these ops.
#
# Each bottoms out in a `Prim.*` the backend lowers to its own 64-bit-domain
# projection (Rust's native `i64::{wrapping,saturating,checked}_add`; a bignum
# project on BEAM/JS). `Prim` is the **target-internal** namespace — unstable
# and backend-specific; user code reaches `Int.checked_add/2` etc. instead:
#
#   Prim.wrapping_add(a, b)    two's-complement wrap into [−2⁶³, 2⁶³)
#   Prim.saturating_add(a, b)  clamp to the Int64 min/max
#   Prim.checked_add(a, b)     `Some(sum)` if it fits, else `None`
#
# PREFER A SUBRANGE FIRST (ADR-0036). If a value is bounded by construction —
# `type Digit := 0..9`, `Digit.of(n) : Digit | RangeError` — the bound lives in
# the type and the compiler proves it; no runtime overflow question arises. These
# ops are the fallback for genuinely-unbounded `Int64` arithmetic where you still
# want a deterministic overflow rule. `sub`/`mul` follow the identical pattern.
# ---------------------------------------------------------------------------

mod Int do
  # wrap on overflow (2's complement) — deterministic, total, may lose magnitude
  pub def wrapping_add(a Int64, b Int64) Int64 := Prim.wrapping_add(a, b)

  # clamp on overflow to the representable extreme — deterministic, total
  pub def saturating_add(a Int64, b Int64) Int64 := Prim.saturating_add(a, b)

  # surface overflow in the type: `Some(sum)` when it fits, `None` when it would
  # overflow — the caller must handle both arms (no hidden control flow, ADR-0035)
  pub def checked_add(a Int64, b Int64) Option(Int64) := Prim.checked_add(a, b)
end
""",
  -- examples/rian/prelude_str.rian
  """
# ===========================================================================
# PORTABLE PRELUDE (ADR-0047 §2) — `Str`, written in Rian over primitives
# ===========================================================================
# Like `Dict`, a `String` bottoms out in a per-target primitive — a BEAM UTF-8
# binary, a JS string, a Rust `String`/`&str`. The same primitive-layer pattern
# applies: a small set of `Prim.str_*` calls each backend lowers natively, with
# the useful operations written once in Rian over them.
#
#   Prim.str_chars(s)        the `Char`s of s  (BEAM String.to_charlist | JS [...s] | Rust s.chars())
#   Prim.str_from_chars(cs)  s from a `Vec(Char)`
#   Prim.str_concat(a, b)    a <> b
#
# `Prim` is the **target-internal** namespace (this layer is unstable and
# backend-specific); user code reaches for `Str.chars/1` etc. instead.
#
# `chars` yields a `Vec(Char)` (ADR-0036) — a codepoint integer on BEAM/JS, a
# native `char` on Rust. `chars("ab") = ['a', 'b']` · `length("héllo") = 5`.
# ---------------------------------------------------------------------------

mod Str do
  # ── the portable surface (forwards to the per-target primitives) ────────
  pub def chars(s String) Vec(Char) := Prim.str_chars(s)
  pub def from_chars(cs Vec(Char)) String := Prim.str_from_chars(cs)
  pub def concat(a String, b String) String := Prim.str_concat(a, b)

  # decimal rendering of an integer (BEAM integer_to_binary | JS String | Rust
  # to_string) — the portable image of `Integer.to_string/1`.
  pub def from_int(n Int53) String := Prim.int_to_string(n)

  # ── composite ops — written ONCE in Rian, portable to every backend ─────
  # length in codepoints: count the char list (cons recursion, no host FFI)
  pub def length(s String) Int53 := count(Prim.str_chars(s))

  def count(cs Vec(Char)) Int53
  def count([]) := 0
  def count([_ | t]) := 1 + count(t)

  # trim — strip leading and trailing ASCII whitespace (space/tab/newline/CR), the
  # portable image of `String.trim/1`: drop leading whitespace, reverse, drop again,
  # reverse back — over the char list, no host FFI. `rev` is local (self-contained,
  # so `Str` carries no cross-module dependency).
  pub def trim(s String) String := from_chars(rev(drop_ws(rev(drop_ws(chars(s))))))

  def drop_ws(Vec(Char)) Vec(Char)
  def drop_ws([]) := []
  def drop_ws([c | t]) := if is_ws(c) do drop_ws(t) else [c | t] end

  # whitespace by codepoint (space/tab/newline/CR) — the portable form, not
  # char-escape literals (`'\t'`).
  def is_ws(c Char) Bool := c == 32 or c == 9 or c == 10 or c == 13

  def rev(cs Vec(Char)) Vec(Char) := rev_onto(cs, [])

  def rev_onto(Vec(Char), Vec(Char)) Vec(Char)
  def rev_onto([], acc) := acc
  def rev_onto([h | t], acc) := rev_onto(t, [h | acc])

  # replace — substitute every (non-overlapping) occurrence of `pat` in `s` with
  # `rep`, the portable image of `String.replace/3`. A char-list scan: at each
  # position, if `pat` is a prefix, emit `rep` and skip past it, else emit one char.
  # Self-contained (local prefix/drop/length/append, no cross-module dependency).
  # An empty `pat` is a no-op (avoids a non-terminating match).
  pub def replace(String, String, String) String
  pub def replace(s, "", _) := s
  pub def replace(s, pat, rep) := from_chars(repl(chars(s), chars(pat), chars(rep)))

  def repl(Vec(Char), Vec(Char), Vec(Char)) Vec(Char)
  def repl([], _, _) := []
  def repl([h | t], pat, rep) := if starts([h | t], pat) do app(rep, repl(drop_n([h | t], len_c(pat)), pat, rep)) else [h | repl(t, pat, rep)] end

  def starts(Vec(Char), Vec(Char)) Bool
  def starts(_, []) := true
  def starts([], _) := false
  def starts([h | t], [ph | pt]) := if h == ph do starts(t, pt) else false end

  def drop_n(Vec(Char), Int53) Vec(Char)
  def drop_n(cs, 0) := cs
  def drop_n([], _) := []
  def drop_n([_ | t], n) := drop_n(t, n - 1)

  def len_c(Vec(Char)) Int53
  def len_c([]) := 0
  def len_c([_ | t]) := 1 + len_c(t)

  def app(Vec(Char), Vec(Char)) Vec(Char)
  def app([], ys) := ys
  def app([h | t], ys) := [h | app(t, ys)]
end
""",
  -- examples/rian/prelude_dict.rian
  """
# ===========================================================================
# PORTABLE PRELUDE (ADR-0047 §2) — `Dict`, written in Rian over primitives
# ===========================================================================
# Unlike `List` (pure cons, portable as-is), a `Map` bottoms out in a real
# per-target primitive — a BEAM map, a JS object, a Rust `HashMap`. The portable
# answer is a thin **primitive layer**: a small set of `Prim.map_*` calls that
# *each backend lowers natively*, with all the useful, COMPOSITE operations
# written once in Rian over them. The per-target code is confined to the
# primitives; everything above is portable.
#
#   Prim.map_new()        BEAM #{}            JS {}            (Rust HashMap…)
#   Prim.map_get(m, k)    :maps.get(k, m)     m[k]
#   Prim.map_put(m, k, v) :maps.put(k, v, m)  {...m, [k]: v}
#   Prim.map_has(m, k)    :maps.is_key(k, m)  Object.hasOwn(m, k)
#
# `Prim` is the **target-internal** namespace — unstable and backend-specific;
# user code reaches `Dict.get/2` etc. instead.
#
#   get_or(inc(empty(), "x"), "x", 0)  =  1
# ---------------------------------------------------------------------------

mod Dict do
  # ── the portable surface (forwards to the per-target primitives) ────────
  pub def empty() Map(K, V) forall K, V := Prim.map_new()
  pub def get(m Map(K, V), k K) V forall K, V := Prim.map_get(m, k)
  pub def put(m Map(K, V), k K, v V) Map(K, V) forall K, V := Prim.map_put(m, k, v)
  pub def has(m Map(K, V), k K) Bool forall K, V := Prim.map_has(m, k)

  # ── composite ops — written ONCE in Rian, portable to every backend ─────
  # look up `k`, or return `d` if absent
  pub def get_or(m Map(K, V), k K, d V) V forall K, V := if has(m, k) do get(m, k) else d end

  # increment an Int53 counter at `k` (0 if absent) — the symbol-table shape a
  # compiler reaches for, built from the primitives, not from host FFI. `zero()`
  # pins the fallback to `Int53` (a bare `0` would infer the default `Int64`, which
  # is off `:js`); `get_or`'s `V` then unifies to `Int53` from both the map and the
  # fallback (ADR-0064 §2a).
  def zero() Int53 := 0
  pub def inc(m Map(String, Int53), k String) Map(String, Int53) := put(m, k, get_or(m, k, zero()) + 1)

  # from_list — build a map from a list of `{key, value}` pairs (the portable image
  # of `Map.new/1`). Recursion builds the tail map first, then `put`s the head, so on
  # a duplicate key the FIRST occurrence wins (the head `put` is outermost). Each
  # clause returns a fresh `put(...)` (owned), so the Rust lowering needs no
  # borrowed-accumulator return. Inputs in practice have unique keys (a range table,
  # a builtins table), where head-vs-last is moot.
  pub def from_list(pairs Vec((K, V))) Map(K, V) forall K, V
  pub def from_list([]) := empty()
  pub def from_list([{k, v} | t]) := put(from_list(t), k, v)
end
""",
  -- examples/rian/prelude_list.rian
  """
# ===========================================================================
# PORTABLE PRELUDE (ADR-0047 §2) — `List`, written in Rian (pure cons)
# ===========================================================================
# Unlike `Dict`/`Str` (which bottom out in a per-target `Prim.*`), a list is pure
# cons (`[]` / `[h | t]`), so these reducers need NO primitive — they are plain
# structural recursion and lower to every backend unchanged.
#
# These are the EAGER, iterable-accepting reducers (the Python `sum`/`any`/`all`/
# `len` family) over a CONCRETE list — no lazy generator/`Iterator` protocol, which
# would need a portable lazy-sequence abstraction Rian deliberately does not provide
# (laziness is a per-target evaluation concern, like concurrency in ADR-0057). Each
# reducer has a natural identity for the empty list (0/1/false/true/0), so it is
# total — no `Option`, no empty-list crash.
#
# Capability: a reducer READS the list, so `val Vec(T)` (a borrowed `&[T]` slice on
# Rust); the cons recursion lowers to a slice rest-pattern there (ADR-0055/0064).
# Numeric reducers fix `Int53` (the portable all-target integer, ADR-0064 §2) — a
# bare `0`/`1` would infer `Int64`, which is off `:js`; the declared `Int53` return
# pins the literal across the base clause.
#
#   List.sum([1, 2, 3])         = 6
#   List.all([true, true])      = true
#   List.any([false, true])     = true
#   List.length(["a", "b"])     = 2
# ---------------------------------------------------------------------------

mod List do
  # Σ — the additive fold; identity 0.
  pub def sum(val Vec(Int53)) Int53
  pub def sum([]) := 0
  pub def sum([h | t]) := h + sum(t)

  # Π — the multiplicative fold; identity 1.
  pub def product(val Vec(Int53)) Int53
  pub def product([]) := 1
  pub def product([h | t]) := h * product(t)

  # ∃ — does any element hold? short-circuits on the first `true`. (`true`/`false`
  # are variable patterns in a clause head, so branch with `if`, not literal clauses.)
  pub def any(val Vec(Bool)) Bool
  pub def any([]) := false
  pub def any([h | t]) := if h do true else any(t) end

  # ∀ — do all elements hold? short-circuits on the first `false`.
  pub def all(val Vec(Bool)) Bool
  pub def all([]) := true
  pub def all([h | t]) := if h do all(t) else false end

  # |xs| — element count (Python `len`); generic over the element type.
  pub def length(val Vec(T)) Int53 forall T
  pub def length([]) := 0
  pub def length([_ | t]) := 1 + length(t)

  # ─── higher-order combinators (ADR-0042 `Fn(…)`) ─────────────────────────
  # The `Enum`-family workhorses, written as pure cons recursion over `Fn`-typed
  # callbacks. Argument order matches Elixir's `Enum.*` (collection first, then
  # callback), so a transpiled `Enum.map(xs, f)` maps to `List.map(xs, f)` verbatim.

  # map — `f` over each element. `f(elem)`, like `Enum.map/2`.
  pub def map(xs Vec(T), f Fn(T, U)) Vec(U) forall T, U
  pub def map([], _) := []
  pub def map([h | t], f) := [f(h) | map(t, f)]

  # filter — keep elements where `f(elem)` holds; reject — keep where it does not.
  pub def filter(xs Vec(T), f Fn(T, Bool)) Vec(T) forall T
  pub def filter([], _) := []
  pub def filter([h | t], f) := if f(h) do [h | filter(t, f)] else filter(t, f) end

  pub def reject(xs Vec(T), f Fn(T, Bool)) Vec(T) forall T
  pub def reject([], _) := []
  pub def reject([h | t], f) := if f(h) do reject(t, f) else [h | reject(t, f)] end

  # reduce — left fold with explicit seed; `f(elem, acc)`, like `Enum.reduce/3`.
  pub def reduce(xs Vec(T), acc U, f Fn(T, U, U)) U forall T, U
  pub def reduce([], acc, _) := acc
  pub def reduce([h | t], acc, f) := reduce(t, f(h, acc), f)

  # concat — append two lists; flat_map — map then concat (`Enum.flat_map/2`).
  pub def concat(xs Vec(T), ys Vec(T)) Vec(T) forall T
  pub def concat([], ys) := ys
  pub def concat([h | t], ys) := [h | concat(t, ys)]

  # the inclusive integer sequence `[lo, lo+1, …, hi]` — the eager list a `lo..hi` literal
  # desugars to (ADR-0036/0079; named `seq` since `range` is a reserved keyword). Empty when
  # `lo > hi`. Portable (all targets).
  pub def seq(lo Int53, hi Int53) Vec(Int53)
  pub def seq(lo, hi) := if lo > hi do [] else [lo | seq(lo + 1, hi)] end

  pub def flat_map(xs Vec(T), f Fn(T, Vec(U))) Vec(U) forall T, U
  pub def flat_map([], _) := []
  pub def flat_map([h | t], f) := concat(f(h), flat_map(t, f))

  # reverse — in linear time via an accumulator.
  pub def reverse(xs Vec(T)) Vec(T) forall T
  pub def reverse(xs) := rev_onto(xs, [])
  def rev_onto(xs Vec(T), acc Vec(T)) Vec(T) forall T
  def rev_onto([], acc) := acc
  def rev_onto([h | t], acc) := rev_onto(t, [h | acc])

  # any_by / all_by — the predicate forms of `Enum.any?/2` and `Enum.all?/2`.
  pub def any_by(xs Vec(T), f Fn(T, Bool)) Bool forall T
  pub def any_by([], _) := false
  pub def any_by([h | t], f) := if f(h) do true else any_by(t, f) end

  pub def all_by(xs Vec(T), f Fn(T, Bool)) Bool forall T
  pub def all_by([], _) := true
  pub def all_by([h | t], f) := if f(h) do all_by(t, f) else false end

  # join — concatenate string elements with a separator (`Enum.join/2`); map_join
  # maps first (`Enum.map_join/3`). Uses the `<>` string operator.
  pub def join(xs Vec(String), sep String) String
  pub def join([], _) := ""
  pub def join([x], _) := x
  pub def join([h | t], sep) := h <> sep <> join(t, sep)

  pub def map_join(xs Vec(T), sep String, f Fn(T, String)) String forall T
  pub def map_join(xs, sep, f) := join(map(xs, f), sep)

  # member — structural membership (`Enum.member?/2`), via generic `==`; `T: Eq` so the
  # equality is a protocol bound (UFCS `RianEq::eq` on Rust), not BEAM-only universal `==`.
  pub def member(xs Vec(T), x T) Bool forall T: Eq
  pub def member([], _) := false
  pub def member([h | t], x) := if h == x do true else member(t, x) end

  # take / drop — prefix and its complement (`Enum.take/2`, `Enum.drop/2`).
  pub def take(xs Vec(T), n Int53) Vec(T) forall T
  pub def take(_, 0) := []
  pub def take([], _) := []
  pub def take([h | t], n) := [h | take(t, n - 1)]

  pub def drop(xs Vec(T), n Int53) Vec(T) forall T
  pub def drop(xs, 0) := xs
  pub def drop([], _) := []
  pub def drop([_ | t], n) := drop(t, n - 1)

  # count_by — count elements satisfying `f` (`Enum.count/2`).
  pub def count_by(xs Vec(T), f Fn(T, Bool)) Int53 forall T
  pub def count_by([], _) := 0
  pub def count_by([h | t], f) := if f(h) do 1 + count_by(t, f) else count_by(t, f) end

  # find — first element satisfying `f`, as an `Option` (`Enum.find/2` returns
  # the bare value or nil; the portable Rian image is `Option`).
  pub def find(xs Vec(T), f Fn(T, Bool)) Option(T) forall T
  pub def find([], _) := None
  pub def find([h | t], f) := if f(h) do Some(h) else find(t, f) end

  # sort_by — insertion sort ordered by `le` (`le(a, b)` is true when `a` should
  # come at-or-before `b`); stable for equal keys. The portable image of
  # `Enum.sort/2` — cons recursion + an as-pattern, no host FFI.
  pub def sort_by(xs Vec(T), le Fn(T, T, Bool)) Vec(T) forall T
  pub def sort_by([], _) := []
  pub def sort_by([h | t], le) := insert_by(sort_by(t, le), h, le)

  def insert_by(Vec(T), T, Fn(T, T, Bool)) Vec(T) forall T
  def insert_by([], x, _) := [x]
  def insert_by(all @ [h | t], x, le) := if le(x, h) do [x | all] else [h | insert_by(t, x, le)] end

  # uniq — drop later duplicates, keeping the first occurrence (`Enum.uniq/1`); the
  # `Eq` bound makes the equality a protocol method (UFCS on Rust), not BEAM-only `==`.
  pub def uniq(xs Vec(T)) Vec(T) forall T: Eq
  pub def uniq([]) := []
  pub def uniq([h | t]) := [h | uniq(reject(t, (x) -> x == h))]
end
"""
  ]
