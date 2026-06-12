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

## Progress against the verdict

1. **ADR-0042 generics (BEAM-first)** — **done (concrete generics).** The checker
   now infers `Vec(T)`, variant values, and call results, so the lexer's `lex`
   is genuinely type-checked (a `lex([]) := 0` bug is caught). `forall` binders
   parse; protocol/impl + structural type-variable unification are the next
   ADR-0042 increment. (Was B4.)
2. **Abstract-forms backend (ADR-0031)** — **the full lexer now compiles to real
   bytecode.** `Rian.Beam` lowers to the **Erlang abstract format** + `:compile.forms`
   → loadable `.beam` (no `eval`, no Elixir-compiler dep, line-tracked). Now
   covers sum-variant construction+patterns (tag = `snake(Ctor)`: `Num(n)` →
   `{:num, n}`, `Zero` → `:zero`) and remote/FFI calls (`String.to_charlist` →
   `'Elixir.String'`), plus a single `mod`. **`SelfhostLexer.tokenize/1` is now a
   genuinely-compiled `.beam` module**, not eval'd source. Still
   `Rian.Beam.Unsupported` (never a miscompile): `struct` declarations (need
   `%Name{}` map forms), named-arg construction, `String`/`<>`, `with`.
3. **Core IR + parser unification (ADR-0050)** — **parser fork closed; typed
   core IR begun.** (a) The duplicate `Decl.pattern` string parser is gone —
   clause heads and `case` arms share the one `Rian.Pratt.parse_pat` (§2). (b)
   `Rian.Core` defines the **typed core *pattern* IR** (sealed-sum structs, each
   carrying a `type` field per §3) + `from_pat/1`, and **all three pattern
   emitters consume it** (§1): `Rian.Beam` (Erlang forms), and `Rian.Lower`'s
   Elixir (`pat_ex`) and Rust (`pat_rs`) paths — surface → `Core.from_pat` →
   core → target. The pattern side now reads *one* representation (parser
   unified in §2; emitters unified here). The **expression catalogue** exists
   too, and a **third emitter — ECMAScript (`Rian.JS`, ADR-0049 Tier 1) — is
   built directly on the core** (`Core.from_expr`/`from_pat`), validating the
   ADR-0050 thesis in practice (a new backend with no new fork; runs under
   node). **Remaining (incremental, §5):** migrate `Rian.Lower`'s precedence-aware
   expression `emit/2` onto the core (entangled with the Rust pattern-meta
   baking — wants the §3 types-on-nodes work first); the exhaustiveness
   normalizer (`PatternLower`); the checker filling node `type`s.
4. **Portable prelude (ADR-0041 #3 / ADR-0047)** — **mechanism + first member
   landed.** `Rian.Prelude` injects built-in types into the checker /
   exhaustiveness env / lowering meta without a user declaration and without
   re-emitting them. First member is the flagship **`Option(T) = Some(T) | None`
   (no `nil`, ADR-0047 §3)**: lowers to `{:some, v}`/`:none` (BEAM) and native
   `Option::Some(v)`/`Option::None` (Rust); `case` over it is exhaustiveness-
   checked (a missing `None` is refused). **Remaining (large, open):** the
   portable `List`/`Map`/`String` *operations* written in Rian over a per-target
   collection-primitive layer (ADR-0047 §2) — this is what finally lets a
   cons/FFI program (the lexer) lower to Rust, and needs the collection-
   representation work (ADR-0041 / ADR-0049 emitters).
