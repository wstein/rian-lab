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
| B2 | **Char literals** `'a'` won't lex | high (ergonomics) | **fixed** | The lexer scans `'A'`/`'+'`/`'\n'`/`'\u{1F600}'` (ADR-0036, Crystal-style single-codepoint) and the checker types them as a distinct **`Char`** — lowered **native per target** (codepoint integer on BEAM, BigInt in JS, native `char` on Rust). The lexer reads `lex(cs Vec(Char))` with `when c == '+'` / `['(' \| rest]`; arithmetic converts explicitly via `__prim_char_code(c) : Int64` (no hidden widening). Lowers and runs on all three targets. Only `range` *construction* over `Char` (`'A'..'Z'`) remains future. |
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

## Fixpoint harness — demo → regression test

A spike that *runs* proves capability; it does not prove *correctness against the
reference*. `Rian.Fixpoint` closes that gap: it compiles a Rian-written lexer to
real `.beam` and **diffs its token stream against `Rian.Lexer`** (the Elixir
tokenizer the rest of the toolchain trusts) over a corpus. Drift in *either*
lexer now fails the diff, so the self-hosting lexer is a checked equivalence, not
a one-off demonstration.

A Rian lexer emits its own `Token` sum (lowered to `{:t_num, n}` / `:t_plus` /
…), so the harness takes a `project` function mapping each Rian token onto the
reference shape; over the shared input domain the projected streams must be
identical. Today that domain is the toy lexer's arithmetic (`digits`, `+ - * /
( )`, spaces), where `selfhost_lexer.rian` and `Rian.Lexer.expr_tokens/1` agree
token-for-token across the corpus (`test/rian/fixpoint_test.exs`), and a
deliberately wrong projection is *caught* — the diff has teeth, it is not
vacuously green.

This is the verification step the **real-lexer port** plugs into: as the Rian
lexer grows toward the full Rian token vocabulary, widen the corpus and
projection and the harness keeps proving agreement — turning each ported slice
into a regression test rather than a fresh demo.

### Real-lexer port — slice 1: identifiers + keywords

[`examples/rian/selfhost_lexer_v2.rian`](examples/rian/selfhost_lexer_v2.rian)
begins the port of the *real* `Rian.Lexer` (not the arithmetic toy). Slice 1
adds **identifiers and keywords** on top of numbers/operators/parens — newly
writable because `Char` is now a real ordinal type (ADR-0036): the scanner
classifies bytes with `Char` comparisons (`c >= 'a' and c <= 'z'`, inlined in
`when` guards since BEAM guards can't call user functions), folds digit runs
with ordinal arithmetic (`acc * 10 + c - '0'`), accumulates a name as a
`Vec(Char)` and `__prim_str_from_chars`-es it, and decides keyword-vs-identifier
by string-literal clause heads. It compiles to real `.beam` and **agrees with
`Rian.Lexer.expr_tokens/1`** over a corpus of identifiers, keywords, integers,
operators, and parens (the slice-1 fixpoint test). Direct evidence that the
`Char`/range work unblocked the port.

**Slices 2–4 widened the vocabulary, each fixpoint-locked with teeth:**

- **Slice 2 — comparison + word operators.** `< > <= >= == !=` (two-char
  longest-match via `[a, b | rest]` peeking) and the word-operators
  `and or not in rem div` (which the reference lexes as `{:op, w}`, not keywords),
  plus the full 16-keyword set.
- **Slice 3 — string and char literals.** `"…"` and `'X'` scanned char-by-char
  (`scan_str`/`scan_char`), the body rebuilt via `Prim.str_from_chars`, the char's
  codepoint via `Prim.char_code`.
- **Slice 4 — number lexemes.** A model change: `TNum` now carries the source
  *lexeme* (a `String`), not a folded `Int64`, because the reference keeps the
  text — `1_000` stays `1_000` — and applies `norm_num` (a bare exponent gains
  `.0` and lowercases its marker: `1e9`/`1E9` → `1.0e9`; a decimal keeps its
  marker, `1.0E9`). The scanner accumulates the lexeme char-by-char across
  `lex_int`/`lex_frac`/`lex_exp`, mirroring `Rian.Lexer.@num_re`
  (`\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?`). It agrees with the reference over
  `_` separators, decimals, and signed/unsigned exponents (the slice-4 corpus +
  a number-lexeme teeth test).

- **Slice 5 — `tokenize/1` parity (the declaration stream).** The jump from
  `expr_tokens/1` to the full **`tokenize/1`** stream `Rian.Decl` actually
  consumes: **significant newlines** (`{:nl}`, runs collapsed via `dedup_nl` +
  leading/trailing drop, matching `Rian.Lexer.collapse_nl`), `;` `,`, **`@annot`**,
  brackets `[] {} %{`, line comments (`# …`), and the full operator set
  (`-> .. := |> <> <~ <- . | : &`) — every operator unified as one
  `TOp(String)`, mirroring the reference's `@multi`/`@single` longest-match. The
  port now agrees with **`Rian.Lexer.tokenize/1`** (not just `expr_tokens/1`) over
  a corpus of multi-line declarations, punctuation, annotations, and operators
  (`Fixpoint.check/4` takes the reference tokenizer; slice-5 corpus + a
  `{:nl}`-divergence teeth test). **This is the gateway rung: the Rian lexer now
  produces the declaration token stream the parser will consume.**

### Parser port — fixpoint-locked against `Rian.Pratt` (rung 2)

[`examples/rian/selfhost_parse.rian`](examples/rian/selfhost_parse.rian) turns the
parser spike from a *demo* into a *checked equivalence* — the parser analog of the
lexer fixpoint. A Rian-written precedence-climbing parser compiles to real `.beam`
and its output is **diffed against the reference `Rian.Pratt.parse`** over a corpus
(`test/rian/parse_fixpoint_test.exs`). The diff needs **no projection**: the AST
constructors are named so their BEAM lowering *is* Pratt's surface-tuple shape —
`Num(s)` → `{:num, s}`, `Id(s)` → `{:id, s}`, `Bin(op,l,r)` → `{:bin, op, l, r}` —
so `parse(tokens)` **term-equals** `Rian.Pratt.parse(source)`. The test injects the
reference `Rian.Lexer` tokens into the parser's `Tok` sum (the same stream Pratt
consumes), and asserts precedence (`1 + 2 * 3` nests `*` under `+`) and
left-associativity (`1 - 2 - 3` ⇒ `(1 - 2) - 3`) match Pratt exactly.

The parser ports **precedence climbing** — the same algorithm `Rian.Pratt` uses,
with the same binding powers (`opinfo`/`bp`) — so it now covers the **full binary
operator table**: `* / rem div` (level 3), `+ -` (4), `<>` (5, right-assoc),
`< <= > >=` (8), `== !=` (9), `and` (10), `or` (11), over identifiers, integer
literals, and parentheses. (BEAM guards can't call user functions, so every
precedence decision is made in the body — an `if` over `lbp(op)` — never in a
guard.) The corpus exercises the ladder (`a or b and c` ⇒ `a or (b and c)`,
`a + b == c * d`, right-assoc `a <> b <> c`) and matches Pratt term-for-term.
Prefix operators, calls, pipes, and Pratt's non-assoc *raise* (`a < b < c`) are
later slices; each widening is a regression test, not a fresh demo.

### Bootstrap plan + the fixed-point ladder (rungs 3-4, ADR-0063)

The boundary and the finish line are now **defined** (ADR-0063): the minimal viable
self-hosted compiler is a **Rian front-end (lexer+parser → the same Core IR) feeding
the existing Elixir checker + `Rian.Beam` emitter**, with the boundary marching down
over time. The proof is a four-stage ladder:

- **Stage 0 — equivalence** (done): each ported stage matches the reference on a
  corpus (the lexer + parser fixpoints above).
- **Stage 1 — self-application** (done for the lexer): the Rian-written lexer
  tokenizes **real toolchain source** — the self-hosting pipeline (including the
  Rian *parser's* own source), the portable preludes, and tour modules — and agrees
  with `Rian.Lexer.tokenize/1` token-for-token. It matches **27 of the 33** `.rian`
  sources; the rest use heredoc doc-comments, and the lexer cannot yet lex *its own*
  source (char escapes `'\n'`) — the documented frontier.
  See [`test/rian/selfhost_fixedpoint_test.exs`](test/rian/selfhost_fixedpoint_test.exs).
- **Stage 2 — front-end self-host** (future): the Rian front-end produces the *same
  Core IR* the Elixir front-end builds, then the existing backend compiles it — the
  first genuinely self-hosted compile. Gated on the parser→IR port + the portable
  stdlib breadth (ADR-0047).
- **Stage 3 — bootstrap fixed point** (future): the whole compiler in Rian; compile
  its source with the Elixir host → v1, compile with v1 → v2, assert **v1 == v2**
  (bit-identical `.beam`). The canonical terminus.

**Next:** widen the parser slice (calls, comparisons, pipes, then patterns) toward
`Rian.Decl` coverage and Stage 2; port the `Enum`/`Map`/`String` stdlib breadth the
real front-end needs. Remaining lexer gaps (heredocs `"""`, string-body escapes,
`\u{…}` char escapes — which block self-lexing) are small and unforced by Stage 2.

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

The surface then gained top-level **`def` declarations** — a program is a run of
`def name = expr;` declarations followed by a result expression, exactly how a
real Rian module is shaped. Each declaration desugars to a `let` wrapping the
rest, so the existing fold/codegen/VM handle it unchanged:
`run("def a = 2; def b = 3; a * b + a") = 8`. Declarations and inner `let`s
compose, and (being still arithmetic + binding) the whole thing lowers to JS and
runs under node too.

**User-defined functions land via interpretation.** [`examples/rian/selfhost_funcs.rian`](examples/rian/selfhost_funcs.rian)
is a tree-walking interpreter whose program is a **function table**
(`name → Fun` of params + body) plus an `Expr`. A call evaluates its arguments
in the caller's environment, binds them to the callee's params in a *fresh*
environment, and evaluates the body with the table still in scope — so self- and
mutual recursion work: `evalx(App("fact", [Num 5])) = 120`, `even`/`odd`. It runs
on **BEAM and under node** (it leans on maps, variants, `case`/clauses, and
recursion — all multi-target). This proves first-class user functions over the
existing IR machinery; a *compiled* CALL/RET stack VM (return addresses, frame
pointer) is the further step. (`evalx`, not `eval` — `eval` is a reserved
function name in a JS module.)

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

**The whole calc compiler runs under node.** The ECMAScript emitter grew lists
(→ arrays, cons `[h | t]` → `[h, ...t]`, closed/cons clause patterns via
`length`/`slice`), `case` (→ an IIFE if-chain), strings (`<>` → `+`), maps
(`%{k: v}` → a JS object), and the handful of stdlib calls the spikes lean on,
mapped to portable JS (`Map.get`/`Map.put` immutable, `String.to_charlist`,
`List.to_string`, `:lists.reverse`). With those, **`selfhost_calc.rian` lowers to
JS in full** — lexer (FFI), parser, optimizer, codegen (slot map), VM — and runs
under node:

```text
run("2 + 3 * 4")        = 14     run("let x = 5 in x + 1")               = 6
run("1 + 2 * (3 - 4)")  = -1     run("let x = 1 in (let x = 2 in x) + x") = 3
```

So the complete self-hosting compiler runs on **two targets** (BEAM + JavaScript)
from one IR. The FFI mappings are a stopgap; the portable prelude (ADR-0047 §2)
should own `Map`/`String`/`List` so they are not per-emitter special cases.

**`List` is portable as pure Rian.** [`examples/rian/selfhost_listlib.rian`](examples/rian/selfhost_listlib.rian)
writes `reverse`/`append`/`length`/`sum` over cons recursion with **no host
FFI**, so they lower to every backend through the existing machinery — verified
identical on BEAM and node (`reverse([1,2,3]) = [3,2,1]`). This is the ADR-0047
§2 approach done right for lists: a program calls `ListLib.reverse` instead of
`:lists.reverse`, and nothing is per-emitter. `Map` and `String` are *not* like
this — they bottom out in real per-target primitives (a hashed map, a UTF-8
buffer), so they need a **primitive-layer**: a small set of `__prim_*` operations
each emitter lowers, with the portable ops written in Rian over them.

**That primitive layer now exists for `Map`.** [`examples/rian/prelude_dict.rian`](examples/rian/prelude_dict.rian)
defines a portable `Dict` over `__prim_map_new/get/put/has` — lowered natively by
each backend (`#{}`/`:maps.get`/`:maps.put`/`:maps.is_key` on the BEAM;
`{}`/`m[k]`/spread/`Object.hasOwn` in JS). The **composite** ops (`get_or`, `inc`)
are written **once in Rian** over those primitives, not per-emitter, and run
identically on BEAM and under node (`inc`-counters `a=2, b=1`;
`get_or(absent, 99) = 99`). The per-target code is confined to four primitives;
everything above is portable — the ADR-0047 §2 shape, demonstrated end to end.
**`String` now has its primitive layer too.** [`examples/rian/prelude_str.rian`](examples/rian/prelude_str.rian)
defines a portable `Str` over `__prim_str_chars`/`__prim_str_from_chars`/
`__prim_str_concat` — lowered to `String.to_charlist`/`List.to_string`/binary-
append on the BEAM, codepoints/`+` in JS, and `chars()`/`collect()`/`format!`
on Rust (all three compile and run: `chars("ab") = [97,98]`, `concat`, etc.).
`length` is a composite written in Rian. Crucially, **the lexer is now FFI-free**:
`selfhost_lexer.rian`'s `tokenize` uses `__prim_str_chars(src)` instead of
`String.to_charlist`, so its source carries no host call — it runs on BEAM and
under node from one portable definition.

So both collection members (`Map`, `String`) follow the ADR-0047 §2 shape:
per-target code confined to a handful of `__prim_*`, everything above portable.

**The call-site borrow pass now closes that gap — and the lexer reaches Rust.**
A per-module signature table drives a small Rust pre-pass: when an argument
*produces* an owned `Vec`/`String` (a `__prim_*` call, a constructor, or a
value-returning call) but the callee's parameter is a borrow (`&[T]`/`&str`), the
argument is wrapped in `&`. Paired with rebinding a cons clause's borrowed
*heads* to owned (`let c = c.clone();`) at arm entry — so a head re-inserted into
a list or compared in the body is owned — the **FFI-free lexer now lowers to Rust
and runs under rustc**: `tokenize("12 + 3 * 4")` yields 5 tokens, through cons
patterns, guard derefs (`*c >= 48`), and fresh-head construction. So the
self-hosting **lexer runs on all three targets** (BEAM, JS, Rust), and `Str` (incl.
the `length` composite) lowers fully. The lexer is also **callable cross-module**
on Rust now: a type named in a `pub` function's signature is emitted `pub` (a
`pub enum` / `pub struct`, fields public too), so `pub fn tokenize(…) ->
Vec<Token>` no longer exposes a private `Token` — external code can name
`selfhost_lexer::Token` and call `tokenize`.

**The parser is now total**, so it clears the exhaustiveness gate too: an
unexpected/leftover token yields an `EErr` node rather than a missing clause, and
the parser lowers to both targets (`parse([]) = EErr` on the BEAM; the emitted
Rust carries `Expr::EErr`). That was the gate the user flagged — Rust requires
exhaustive `match`es, the same totality Rian enforces, so the fix was total
clauses, by design.

Lowering the parser surfaced the **next** Rust item (a separate, real codegen
feature, not exhaustiveness): a **recursive ADT** — `type Expr := Add(Expr, Expr)`
→ `enum Expr { Add(Expr, Expr) }` — has infinite size in Rust and must be
`Box`-indirected (`Add(Box<Expr>, Box<Expr>)`, `Box::new(...)` at construction,
deref at use). This affects every tree-shaped ADT (parser/optimizer/evaluator/
checker), which run fine on BEAM/JS (boxing is implicit there) but need the Box
pass to `rustc`-compile. It is the consolidated next Rust increment.

**Rust gets cons.** A Rian `Vec(T)` param lowers to a `&[T]` slice, so cons
patterns become **Rust slice patterns** — `[h | t]` → `[h, t @ ..]` — matched
directly (match ergonomics give `h: &T`, `t: &[T]`), and cons *construction*
`[e | tail]` prepends onto an owned copy (`tail.to_vec()` then `insert(0, e)`).
A reduce (`sum([h|t]) := h + sum(t)`) and a fresh-head builder
(`countdown(n) := [n | countdown(n-1)]`) lower to Rust and **compile + run
under rustc** (`sum(&countdown(4)) = 10`) with `val Vec` → `&[T]` slice patterns.

For functions that **return or rebuild** a list — where the borrowed-slice
convention forces clones — the answer is the **`iso` capability** (`iso Vec(T)` →
an owned `Vec<T>`, capability-consistent: `iso` owns/moves). An `iso Vec` param
destructured by a cons pattern is matched via `.as_slice()`, and its binders are
rebound to owned values (`let h = h.clone(); let t = t.to_vec();`). With that,
`cat([], ys) := ys` (return a param) and `cat([h|t], ys) := [h | cat(t,ys)]`
(re-insert a borrowed head) — and `rev`, which calls `cat` — lower to Rust and
**compile + run under rustc** (`cat([1,2],[3,4]) = [1,2,3,4]`, `rev([1,2,3]) =
[3,2,1]`). So `val` handles reduce/build (zero-copy slices), `iso` handles
return/rebuild (owned).

**Guards over borrowed binders now deref.** A binder bound inside a slice/list
element is a `&T` borrow (match ergonomics), so a guard comparing it needs `*`.
The Rust emitter now derefs those binders in guards: `when c == 32` over a
`&i64` lowers to `if *c == 32`, and `when c >= 48 and c <= 57` to
`if *c >= 48 && *c <= 57`. Guard-heavy cons functions compile + run under rustc
(`count_spaces([32,1,32,2]) = 2`). (Arithmetic on a `&T` in the *body* already
works via the `forward_ref` `Add`/etc. impls, so only guards needed the deref.)

Two edges still stand on Rust, both genuine (not emitter bugs): a deliberately
**partial** function (e.g. the spike `parse_factor`, which doesn't cover every
token) **cannot** lower to a Rust `match`, because Rust requires exhaustive
matches — totality is enforced, by design; the fix is total clauses, not an
emitter change. And the **lexer**'s `String.to_charlist`/`:lists` FFI has no
Rust mapping (a portable `String`/`List` prelude is the path — `List` is already
pure-Rian; `String` needs the primitive layer below).
