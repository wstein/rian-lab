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
   genuinely-compiled `.beam` module**, not eval'd source. Since extended with
   **higher-order functions** (lambdas/captures + fun-valued *variable
   application*, ADR-0042), **strings** (literal/`<>`/string-pattern, ADR-0041),
   and **`with`** error-composition (→ nested `case`, ADR-0039). Still
   `Rian.Beam.Unsupported` (never a miscompile): `struct` declarations (need
   `%Name{}` map forms), named-arg construction, map literals.
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
   node). The checker (`Check.infer`) consumes the core too, and `Check.annotate`
   fills node `type`s (§3). **`Rian.Lower.emit/2` now consumes the core** — the
   last surface-tuple expression consumer; the Rust pattern-meta baking stays a
   surface pre-pass whose `{:rpat}` marker passes through `from_pat`, so no meta
   threading was needed. The exhaustiveness normalizer (`PatternLower`) consumes
   the core too. **Every parser-downstream pass — Beam, JS, Lower, Check,
   PatternLower — now reads one representation.** Remaining (the §3 *payoff*,
   future): emitters *reading* `node.type` for representation choices rather than
   recomputing from meta.
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
5. **Self-hosting parser spike (ADR-0027/0031)** — **a Pratt slice runs in Rian,
   no wall.** [`examples/rian/selfhost_parser.rian`](examples/rian/selfhost_parser.rian)
   ports precedence climbing over `+ - * /` with parentheses into Rian: it
   consumes the lexer's `Vec(Token)`, builds its own `Expr` sum, and threads
   `(Expr, Vec(Token))` through each step as a single-constructor `Parse` pair.
   It **compiles to real `.beam` and runs** — `1 + 2 * (3 - 4)` →
   `Add(Num(1), Mul(Num(2), Sub(Num(3), Num(4))))`, correct precedence and
   left-associativity. Crucially it raised **no `Rian.Beam.Unsupported`**: the
   four increments above (function types/HOF, strings, `with`, plus the existing
   variant/list/`case`/recursion core) were exactly enough to compile a real
   parser layer. The spike used only sum construction, nested list+variant
   patterns, `case`, and recursion — no struct or map was needed (an AST is a
   sum; the token stream is a list). **The next layer (an evaluator / a typed
   AST with a symbol table) is where `struct`/map literals on BEAM become the
   likely next blocker** — but that is now a prediction to be tested by the next
   spike, not a present wall.
6. **Self-hosting evaluator spike + maps on BEAM (ADR-0027/0031/0041)** — **the
   prediction held, and the wall is down.** [`examples/rian/selfhost_eval.rian`](examples/rian/selfhost_eval.rian)
   is the layer after the parser: it folds the `Expr` sum to an `Int64`,
   threading a **symbol table** (`Map(String, Int64)`) with `let`-binding and
   `Var` lookup. Written idiomatically, it hit exactly the predicted wall — the
   empty starting environment `%{}` raised `Rian.Beam.Unsupported`
   (`EMap`). That drove the increment: `Rian.Beam` now lowers a **map literal**
   `%{k: v, …}` to a BEAM map (identifier key `k` → atom `:k`, the Elixir
   convention); map access/insert already rode the `Map` FFI. With that, the
   evaluator **compiles and runs**: `let x = 10 in let y = 4 in (x + y) * 2` →
   `28`, and the full `lex → parse → eval` pipeline (all three Rian modules
   compiled to `.beam`) gives `2 + 3 * 4` → `14`.
7. **Self-hosting type-checker spike + structs on BEAM (ADR-0027/0031/0043)** —
   **the prediction held again; structs are down.**
   [`examples/rian/selfhost_check.rian`](examples/rian/selfhost_check.rian) is
   the layer after the evaluator: it infers a `Ty` (`TInt`/`TBool`) for the
   `Expr` language under a typing environment and reports a **structured type
   error** via `struct Mismatch(op, expected, got)`. Written idiomatically it hit
   exactly the predicted wall — the `struct` declaration raised
   `Rian.Beam.Unsupported`. That drove the increment: a `struct` declaration is
   now **erased**, a struct *value* is a tagged map — named construction
   `Name(field: v, …)` builds a map keyed by field-name atoms (+ `__struct__`),
   and field access `value.field` reads it via `maps:get/2` (no field schema
   threaded). The checker now **compiles and runs**: it types `1 + 2` → `Int`,
   `1 < 2` → `Bool`, and reports `1 + true` → *type error in add: expected Int,
   got Bool* — the `Mismatch` struct round-tripping through field access. **Four
   layers (lexer → parser → evaluator → type-checker) now compile to real `.beam`
   and run.** Still unlowered (next, if a spike demands them): *positional*
   struct construction, map/struct *patterns*, and map *update* (`%{m | k: v}`).
8. **Self-hosting code generator + stack VM (ADR-0027/0031)** — **a fifth layer,
   no wall.** [`examples/rian/selfhost_codegen.rian`](examples/rian/selfhost_codegen.rian)
   compiles the `Expr` sum to a post-order list of stack-machine `Instr`
   (`Push`/`IAdd`/…) and executes them on a stack (`Vec(Int64)`). The **full
   `lex → parse → codegen → run` pipeline — five Rian modules, all compiled to
   `.beam`** — turns source straight into a value: `2 + 3 * 4` → `14`,
   `1 + 2 * (3 - 4)` → `-1`. Like the parser, it raised **no
   `Rian.Beam.Unsupported`**: a code generator over a *sum* AST destructures
   with variant patterns and builds instruction lists with cons — both long
   supported — and the VM reads the stack with two-head cons patterns
   (`[b, a | s]`). The predicted struct/map-*pattern* wall was **not** reached,
   because every spike's IR is sum-based (variants), not struct-based; that wall
   awaits a spike whose IR nodes are structs matched by shape (e.g. an optimizer
   rewriting struct-shaped IR). **Net: the abstract-forms backend now compiles a
   five-stage compiler/runtime pipeline written in Rian, end to end.**
9. **Self-hosting optimizer (constant folding) (ADR-0027/0031)** — **the
   prediction did *not* fire, and that is the finding.**
   [`examples/rian/selfhost_opt.rian`](examples/rian/selfhost_opt.rian) is a real
   optimization pass: it folds constant subtrees (`(2 + 3) * 4` → `Num(20)`) and
   applies algebraic identities (`x * 1` → `x`, `x * 0` → `0`, `x + 0` → `x`),
   matching IR nodes **by shape** — `Add(Num(a), Num(b))`, `Mul(_, Num(0))`,
   `Add(a, Num(0))` — with nested variant and literal-in-variant patterns. This
   is exactly where the struct/map-*pattern* wall was predicted. It did not
   appear, and **needed zero backend changes**: an optimizer over a *sum* IR
   destructures with variant patterns (long supported), not struct patterns.
   Slotted before the codegen, it shrinks output — `(2 + 3) * 4` emits a single
   `Push 20` instead of five instructions. The codegen also handles **variables
   and `let`** via load/store **slots**: it threads a compile-time `name → slot`
   environment and the VM threads a slot store (`Map(Int64, Int64)`), so
   `let x = 5 in x + 1` lowers to `[Push 5, Store 0, Load 0, Push 1, IAdd]` and
   lexical shadowing resolves to distinct slots — still **zero backend changes**
   (maps suffice).

## Conclusion of the spike series

Six layers — **lexer → parser → optimizer → type-checker → codegen → stack VM** —
are now written in Rian and compile to real `.beam`, composing into a full
source-to-value pipeline. The spike method drove exactly the increments the code
*demanded* (maps for the evaluator's symbol table; structs for the checker's
diagnostic record) and nothing it didn't.

The one prediction that never fired — **struct/map *patterns*** — was the honest
boundary of "self-hosting-complete for idiomatic Rian": Rian is sum-oriented, so
ASTs and IRs are matched with *variant* patterns (supported) and structs are read
by *field access* (supported), never matched by shape. No spike forced them.

**They have since been built anyway (parser + abstract forms).** `Rian.Pratt`
now parses a struct pattern `Name(field: p, …)` (symmetric with construction) and
a map pattern `%{k: p, …}`, and `Rian.Beam` lowers them to Erlang map patterns —
a struct pattern requires `__struct__ := :name` plus its named fields, a map
pattern matches any map carrying the listed keys. So the last pattern gap is
closed: clause heads and `case` arms can destructure structs and maps by shape,
not just by field access. Remaining ergonomic gaps (positional struct
construction, map update `%{m | k: v}`) are small, self-contained, and still
unforced by the pipeline.

## The whole compiler as one Rian artifact

[`examples/rian/selfhost_calc.rian`](examples/rian/selfhost_calc.rian) unifies
every layer — lexer, parser, optimizer, code generator, stack VM — into a
**single self-contained Rian module** that compiles to **one real `.beam`** and
turns source text straight into a value:

```text
run("1 + 2 * (3 - 4)")  =  -1        run("(2 + 3) * 4")  =  20
String -> Vec(Token) -> Expr -> Expr(folded) -> Vec(Instr) -> Int64
```

This is the front-to-back pipeline as one artifact, written entirely in Rian and
compiled by the abstract-forms backend — no `eval`, no per-stage test glue. The
optimizer is in-line: a constant program folds to a single instruction
(`emit("2 + 3 * 4") == [Push(14)]`). It is the strongest single piece of evidence
that the toolchain compiles a real, multi-pass compiler written in its own
language.

The calc's surface has since **grown past arithmetic**: the lexer scans
identifiers and the `let`/`in` keywords (and `=`), the parser builds `Let`/`Var`,
and the codegen allocates load/store slots — so variables flow from source text
end to end: `run("let x = 5 in x + 1") = 6`, with correct lexical shadowing
(`run("let x = 1 in (let x = 2 in x) + x") = 3`). Building an identifier token
means accumulating codepoints and `List.to_string`-ing them (BEAM FFI) — the same
class of crutch the lexer already used; a portable `String` builder is the
multi-target fix.

## Module system — a compiler is many modules

A real compiler is split across files; [`examples/rian/selfhost_modules.rian`](examples/rian/selfhost_modules.rian)
splits the calc into `mod CalcLex` / `CalcParse` / `CalcGen` / `Calc`.
`Rian.Beam.load_program/1` compiles **each `mod` to its own BEAM module** named
`Elixir.<Mod>` — the very atom a Pascal-qualified call lowers to — so a Rian
cross-module call (`CalcLex.lex(…)`) resolves with no extra machinery. The driver
`Calc.run("2 + 3 * 4")` runs across four separately-compiled modules and yields
`14`. Two facts make this cheap: a qualified call already lowered to a
`Elixir.<Mod>` remote call (free BEAM FFI, ADR-0041), and **variant tags are
global** — a `Token`/`Expr` constructor lowers to the same atom in every module,
so `CalcParse` pattern-matches `CalcLex`'s tokens without re-declaring `Token`.
Only the functions cross module boundaries; the types are erased to shared tags.

## Multi-target (ADR-0049 / ADR-0050)

The BEAM path drove these spikes, but the typed core IR is shared, so a
*sum-based* spike can lower to other targets without a new fork. The **optimizer**
(`selfhost_opt.rian`, variants + nested patterns, no lists/FFI) now lowers to
**three targets**:

- **BEAM** — abstract forms, verified running (`fold` of `(2 + 3) * 4` → `Num(20)`).
- **Rust** — `Rian.Lower` emits an idiomatic `enum Expr { … }` + `fn fold(e: &Expr) -> Expr { match e { … } }` with nested/literal patterns. (The textual emitter does not yet insert clones/derefs, so a borrow-checking ownership pass is future work; the structure is faithful.)
- **JavaScript** — `Rian.JS` (ADR-0049) now lowers **sum variants**: construction `Ctor(a, …)` → a tagged array `["Ctor", a, …]`, with clause patterns that check the tag and recurse into fields. The optimizer **runs under node**: `fold` of `(2 + 3) * 4` → `["Num", 20]`, `x * 1 + 0` → `["Var", "x"]`.

This validates the ADR-0050 thesis on real self-hosting code: one IR, three back
ends, zero forks.

**JS reaches the parser.** The ECMAScript emitter now also lowers **lists**
(→ arrays, cons `[h | t]` → `[h, ...t]`, closed/cons clause patterns via
`length`/`slice`) and **`case`** (→ an IIFE if-chain over the arm patterns). So
the *cons-recursive* **parser** spike — `case`, nested variant + list patterns,
recursion, no FFI/maps — now lowers to JS and **runs under node**: the token
stream for `1 + 2 * (3 - 4)` parses to
`["Add", ["Num", 1], ["Mul", ["Num", 2], ["Sub", ["Num", 3], ["Num", 4]]]]`,
correct precedence. Still JS-blocked: the **lexer** (FFI `String.to_charlist`)
and **codegen/VM** (maps for the slot store, strings) — JS maps/strings are the
next increments. On **Rust**, the cons-recursive layers remain BEAM-only until a
portable `Vec`/slice prelude (ADR-0047 §2) lands.
