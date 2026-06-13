# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

RianLab is the **Elixir reference implementation + design corpus** for **Rian** — a typed,
capability-disciplined language that lowers the *same source* to multiple targets: the BEAM
(Elixir/Erlang), Rust, and ECMAScript. There is no separate Rian runtime here; `lib/rian/` is a
compiler written in Elixir that parses `.rian` source and emits idiomatic code per target.

**The ADRs are the source of truth, not the code.** `docs/adr/*.md` (~30 of them) are where language
decisions live; `lib/rian/` implements them. When you change language *behaviour*, update the
matching ADR — and conversely, an ADR marked "Accepted" may still be unimplemented or partially
implemented (check the `**Status:**` header and the code before trusting it). `docs/spec/` holds
prose specs; `examples/rian/` is the annotated by-example tour and the self-hosting spikes.

## Commands

```bash
mix test                                  # full suite (loads real modules into the VM)
mix test test/rian/check_test.exs         # one file
mix test test/rian/check_test.exs:51      # one test (by line number)
mix test --only rust                      # only the rustc-backed tests

mix format                                # THE linter — no credo/dialyzer in this repo
mix compile --warnings-as-errors          # warnings are errors; run before every commit

mix rian.compile FILE [--beam|--rust|--js|--jvm] [--show-elixir]  # BEAM bytecode (Rian.Beam) + Rust/JS/Kotlin source; --show-elixir = text debug view
mix rian.jar FILE [-o OUT.jar] [--main FUNC]      # runnable JVM .jar via Kotlin+kotlinc (ADR-0049/0062 rung B)
mix rian.repl                                     # compiling REPL (parse→check→abstract-forms→load→run)
mix rian.targets FILE [--require ex,rs,js]        # per-function target-reachability report / gate
mix examples                                      # end-to-end lowering demo
```

- `@tag :rust` tests shell out to `rustc` and **run by default**, no-op'ing if `rustc` is absent;
  some JS tests require `node`. Both are present in CI-like environments.
- `mix test` is the real coverage signal, but much of it runs on hand-built source strings / a toy
  corpus — see `Rian.Fixpoint` and `SELFHOST.md` for where self-hosting verification actually bites.

## Architecture — the compile pipeline

Source flows through these stages; the **typed Core IR is the spine** that decouples them (ADR-0050):

1. **`Rian.Lexer`** — shared tokenizer. `tokenize/1` (declaration stream, newline-significant) and
   `expr_tokens/1` (expression stream).
2. **`Rian.Decl`** (declarations) + **`Rian.Pratt`** (expressions & patterns). There is exactly **one
   pattern parser** (`Pratt.parse_pat`, shared by clause heads and `case` arms — ADR-0050 §2).
   `Decl` splits declarations on significant newlines, but a `def … :=` body is **newline-tolerant**
   (P1): it continues across a newline inside unbalanced `(`/`[`/`{`, after a trailing binary operator
   or before a leading one, or onto the next line — so `:=` expressions may span lines.
3. **`Rian.Core`** — the typed, sealed-sum Core IR (`from_expr`/`from_pat` translate surface tuples →
   core structs like `ENum`/`EChar`/`PCtor`). **Every downstream pass consumes Core.**
4. **Gates** (refuse to emit on failure): `Rian.Check` (unification-based inference + error sets),
   `Rian.Exhaustiveness` (Maranget usefulness; the gate that has most earned its keep),
   `Rian.Capability` (BEAM linearity for `iso`/`ref`).
5. **Emitters**, all consuming Core:
   - **`Rian.Beam`** — Erlang **abstract forms** via `:compile.forms` → real loadable `.beam`. This
     is the **default BEAM execution path and the self-hosting bootstrap target**.
   - **`Rian.Lower`** — a **text** emitter that produces *both* idiomatic Elixir source *and* Rust in
     one module. The Elixir-text path is a demo/inspection backend (it has a known higher-order
     limitation, see its moduledoc); **`Rian.Beam` is the real BEAM backend.** So BEAM has two
     emitters — don't confuse them.
   - **`Rian.JS`** — ECMAScript (ADR-0049 Tier 1); partial (`struct`/`with`/lambdas/FFI raise
     `Unsupported`).
   - **`Rian.JVM`** — Kotlin/JVM (ADR-0049 **Tier 2**); a direct source emitter on Core, like JS.
     MVP: functions, primitives, operators, `if`, sum variants (→ `sealed interface` + `data class` +
     smart-cast patterns); lists/maps/structs/`case`/FFI raise `Unsupported`. Verified via
     `kotlinc`+`java`. `:jvm` is now in the `Rian.Reach` target vocabulary.

**Consequence for any new language feature:** a new AST node must be threaded through `Pratt` → `Core`
→ `Check` → `PatternLower`/`Exhaustiveness` → the emitters (`Beam`, `Lower`, `JS`; **`JVM`** where the
Tier-2 subset covers it) → `Macro`/`Capability` where relevant. Missing one surfaces as a
`FunctionClauseError` or an `Unsupported` raise. This per-feature drift tax is the central
architectural cost.

## Cross-cutting models you must understand before editing

- **Capabilities** (`Rian.Capability`) drive Rust parameter signatures and BEAM linearity — how Rian
  gets ownership-checked Rust without hand-written lifetimes. The **portable core is `val`/`iso`/`tag`**
  (BEAM-legal): `val`→`&[T]`/`&T`, `iso`→owned `Vec<T>`/move (use-once), `tag`→`&T`. **`ref` (`&mut`) is
  NOT in the portable core (P5):** it is BEAM-rejected, so a `ref` parameter pins the function off
  `:ex` — `Rian.Reach` reports it as a `:capability` blocker killing `:ex` (the matrix is honest, not a
  tidy-looking four). See ADR-0055/0025/ADR-0064-adjacent P5.
- **Portability is *inferred*, not annotated** (`Rian.Reach`, ADR-0057/0058). A function is
  "portable" iff it reaches all of `:ex`/`:rs`/`:js`; host FFI (and all concurrency) pins it to
  `:ex`. **Concurrency/OTP is native-per-target by design** — it is *not* a Rian surface (ADR-0057
  superseded the OTP-behaviours ADR-0044). A binary `@shared`/portable flag was explicitly rejected
  in favour of a target-environment *set*.
- **The primitive layer** (ADR-0047): a small set of intrinsics each emitter lowers to its native op,
  with portable `List`/`Dict`/`Str` ops written once in Rian over them (`examples/rian/prelude_*.rian`).
  In source they are the **reserved `Prim.*` namespace** (`Prim.str_chars`, `Prim.char_code`, …);
  `Rian.Prim.normalize/1` (hooked into `Pratt.parse`/`parse_body`) rewrites `Prim.<name>` to the
  canonical `__prim_<name>` intrinsic at the parse boundary, validating against `Rian.Prim.names/0`
  (an unknown `Prim.x` is a hard error). The bare `__prim_*` form is legacy. User code uses the
  `Str`/`Char`/`Dict` wrappers, never `Prim.*`.
- **The checker is deliberately conservative**: it infers `:unknown` rather than guess, and only
  reports an error on a *provable* mismatch. Don't "tighten" it into rejecting valid code.
- **Self-hosting** (`SELFHOST.md`, `examples/rian/selfhost_*.rian`): a compiler pipeline written in
  Rian that compiles to `.beam`. `Rian.Fixpoint` diffs a Rian-written lexer's tokens against the
  reference `Rian.Lexer` — that's how a ported slice becomes a regression test, not a demo.

## Conventions

- **`mix compile --warnings-as-errors` is enforced.** The most common self-inflicted failure: Elixir
  requires same-name/arity function clauses to be **grouped contiguously** — inserting a helper
  between two `infer`/`emit`/`pat_rs` clauses breaks the build. Keep clause groups together.
- Tests that load modules into the VM (`Rian.Beam`, REPL) use `async: false`.
- **Commit after each stage/phase**, not as one big drop. Use Conventional Commits and cite the
  governing ADR in the body (e.g. `feat(types): … (ADR-0036)`).
- **A change isn't done until the docs match it — not just code and tests.** When behaviour changes,
  update the governing **ADR** (and `docs/spec/`, `examples/rian/`, `SELFHOST.md`, the status tables
  in `docs/README.md`, and module/inline docs) in the *same* phase. Remove outdated content rather
  than leaving it flagged as stale; treat a contradiction between an ADR and the code as a bug to
  fix, not annotate.
