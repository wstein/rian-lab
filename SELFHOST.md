# Self-hosting blocker ledger

Evidence from the **self-hosting spike** (ADR-0027/0031): writing a Rian lexer in
Rian (`examples/rian/selfhost_lexer.rian`), typing its own data, compiling through
`Rian.Decl`, running on the BEAM. The point is the *ranked blocker list* — what a
real Rian-in-Rian program needs that the toolchain can't yet do — not a green
checkmark.

Method: write idiomatic Rian, hit a wall, record it here, fix the cheap-and-
essential ones, work around the rest (and record the cost).

## Blockers found

| # | Blocker | Severity | Status | Note |
|---|---|---|---|---|
| B1 | **List patterns** `[]` / `[h \| t]` in `case` and clause heads | **fatal** | **fixed** | No list recursion without them. `PatternLower` already modelled `{:list,…}`; only the surface parsers + emitters lacked it. |
| B2 | **Char literals** `'a'` won't lex | high (ergonomics) | worked around | Lexer can't scan `'`. Spike uses integer codepoints (`43` for `'+'`) — readable-but-noisy. Real fix: a `Char` token (ADR-0036). |
| B3 | cons-list **on Rust** is BEAM-only (construction *and* now patterns) | medium | by design | A cons-recursion lexer is BEAM-only on Rust; the portable form needs a `Vec`/slice prelude (ADR-0041 #3). Recorded, not fixed. |
| B4 | **No parametric types** — the checker can't represent `Vec(Token)`/`Vec(Int64)` | **high** | open | Direct evidence for ADR-0042. See "Checker observations" — the checker is *inert* over the lexer's core. |
| B5 | **No portable collections** — `String→chars`, list ops, cons all BEAM-only | high (multi-target) | open | The lexer cannot lower to Rust at all. A portable prelude (ADR-0041 #3) is the gate for multi-target self-hosting; irrelevant to the BEAM bootstrap. |

## Crutches used (measured, per the spike's honesty rule)

- `String.to_charlist/1` via FFI to turn the input into a list of codepoints —
  BEAM-only. A portable prelude (ADR-0041 #3) would own this.

## Outcome

**The spike works.** `SelfhostLexer.tokenize("12 + 34 * (5 - 6)")` runs on the
BEAM and returns the full typed token list
(`[{:t_num, 12}, :t_plus, {:t_num, 34}, :t_star, :tl_paren, …]`). After B1, the
front end is **self-hosting-capable for the BEAM**: multi-clause functions, list
patterns, literal-byte clause heads, `when` guards, recursion, sum-variant
construction, and cons-list building all compose and lower correctly.

## Checker observations (Samir's criterion)

- **The checker is inert over the lexer's core (B4).** Every list-returning body
  (`[]`, `[TPlus | lex(rest)]`, `lex_num(...)`) infers `:unknown`, because the
  checker has no parametric/list type — so it cannot verify `lex` returns a
  `Vec(Token)`. It *would* catch a crude `lex([]) := 0` (literal `0` is `Int64`,
  contradicting the declared `Vec(Token)`), but anything list- or call-shaped
  passes unexamined. For a language whose pitch is "compile-time checks are the
  spine" (ADR-0046 §1), the checker adds ~no value to realistic recursive code
  until generics + list inference land. **This is the single strongest piece of
  evidence for prioritising ADR-0042.**
- **Exhaustiveness is the check that paid off.** It *forced* the final
  `def lex([_ | rest])` catch-all — without it the match is non-exhaustive and
  emission is (correctly) refused. The totality gate is real, useful, and already
  carries its weight on self-hosting-shaped code.

## String-emit fragility (Maya's criterion)

- The text backend handled this lexer without incident — but the lexer emits **no
  string literals or special characters**. The fragility (escaping, interpolation,
  source positions) is latent, not exercised. The deeper issue stands: this is
  `Code.eval_string`, not compilation — **no `.beam` artifact, no real error
  locations, not a reproducible build** (Kira/Maya). Self-hosting *the compiler*
  (which itself emits code) would compound this. Motivates the abstract-forms
  backend (ADR-0031).
- Minor: `TLParen` lowers to `:tl_paren` (the `to_snake` heuristic splits
  `TL|Paren`). Cosmetic, but a self-hosted lexer/codegen would want predictable
  name mangling.

## Ranked verdict (for sequencing)

1. **ADR-0042 generics (BEAM-first)** — without it the checker is inert on the
   exact code self-hosting is made of. Highest leverage. (B4)
2. **Abstract-forms backend (ADR-0031)** — turn `eval`-of-strings into real,
   reproducible compilation before self-hosting the compiler. (Maya/Kira)
3. **Core IR + parser unification** — B1 had to be fixed in *three* places
   (`Pratt.parse_pat`, `Decl.pattern`, the emitters); that triplication is the
   fork a self-hosted front end would inherit.
4. **Portable prelude (ADR-0041 #3)** — the gate only when self-hosting targets
   beyond the BEAM; the bootstrap itself is happy on Elixir-stdlib FFI.
