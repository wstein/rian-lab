# ADR-0053 — REPL & Interactive Surfaces: a compiling, connected REPL; one eval engine, many surfaces

**Status:** Accepted (direction) · implementation wraps [`Rian.Beam`](../../lib/rian/beam.ex)
**Implemented:** partial — local compiling REPL is shipped (`Rian.Repl`, `Mix.Tasks.Rian.Repl`; `test/rian/repl_test.exs`, `test/rian/repl/history_test.exs`); the `--remote`/connected REPL (§2) and the Livebook/Jupyter surfaces (§8) are not built (see ADR-0054)
**Refs:** ADR-0026/0031 (BEAM host; `Rian.Beam` abstract-forms eval core), ADR-0033/0034 (single-assignment; the compile gate), ADR-0038 (LSP / editor-eval), ADR-0046 (BEAM dynamism preserved *for* the REPL), ADR-0048 (effect sets shown), ADR-0051 (`@doc` → `h` lookup), ADR-0052 (web playground — a sibling surface)
**Owners:** Arthur Pendelton (compiling REPL) · Maya Lin (architecture) · Liam Davis (IEx/IRB/Livebook) · Chloe Bennett (Jupyter/notebooks) · Elena Rostova (BEAM scoping) · Samir Patel (no-drift) · Marcus Chen (connected-prod security) · Kira Neri (remote/ops) · Rachel Okafor (PM)
**Models on:** IEx, IRB, and — decisively — the **Clojure connected REPL** (nREPL).

## Context

Rian has eval (`Rian.Beam.load/2` / `compile/2` — abstract forms → `:code.load_binary`) but **no
REPL**. "Best-in-class" (per the brief) means: improvisation/exploration, a smooth manual→production
transition, **compositional integrity** (read/eval/print as composable phases over the *real*
compiler — not a prompt bolted onto an interpreter), and a short debugging feedback loop. The BEAM
host gives Rian most of what makes Clojure's REPL great — hot code loading and connected/remote
shells — *for free*; ADR-0046 preserved that dynamism explicitly so this is possible.

## Decision

### 1. A *compiling* REPL — eval is the real compiler

Each entry runs the full pipeline: **`Lexer → Decl/Pratt → Check → Beam (abstract forms) →
:code.load_binary → eval → print`**. There is **no interpreter and no REPL dialect** — the REPL
compiles real Rian through the **full gate** (types, exhaustiveness, effects). So **what runs in the
REPL is production-ready by construction**, and the REPL cannot diverge from the compiler (the
FlatBars/ADR-0011 byte-identity discipline, applied to the prompt). This is Clojure's model
(compile each form to bytecode, load into the running runtime).

### 2. A *connected* REPL — the differentiator

`mix rian.repl` starts a fresh node; **`mix rian.repl --remote node@host` attaches to a running
Rian/BEAM application** and evaluates forms in its **live context**, redefining functions live via
BEAM hot code loading (the Clojure nREPL / IEx remote-shell model). REPL-driven development —
evaluate-in-the-running-app, not edit-compile-restart — is the point, and the BEAM makes it native.

**Prerequisites — gating, not parallel.** `--remote` is arbitrary code execution against a live
node, so it ships *after* both: (a) an authentication story (who is allowed to attach, how the
connection is authorized, how the audit trail is captured); and (b) a sandbox/fuel story (what
the connected session is and is not allowed to call, with caps on time/memory/effect scope).
These share the comptime/LSP sandbox concerns (ADR-0030/0038) and lean on effect visibility
(ADR-0048) for review — neither is started here; both are specified in [ADR-0054 — Connected
REPL Prerequisites](0054-connected-repl-prerequisites.md), which is required before `--remote`
lands.

### 3. Single-assignment at the prompt = redefinition, not mutation

The REPL is a stream of **top-level units**. A later `x := 2` after `x := 1` **redefines/shadows** the
top-level `x` — Clojure's `def` model — which is **redefinition, not `<~` mutation** and not in-scope
reassignment. Single-assignment semantics (ADR-0033) hold **within a unit**; the REPL top-level is
redefinable. No conflict with the language's own rule.

### 4. Rich, typed, effect-aware output

Each result prints its **value and inferred type (ADR-0034)**; once the effect checker lands
(ADR-0048 is direction-only today), the **effect set** joins the line — so a wrong effect footprint or
a non-total `case` fails *at the prompt*, exactly as at compile. `h Name` shows the `@doc`/`@moduledoc`
(ADR-0051 EEP-48 docs). IEx-grade essentials: multiline input, history, tab-completion (from the LSP
symbol table, ADR-0038), pretty-printing.

### 5. Smooth manual → production transition

Because REPL input is real gate-checked Rian, experiments graduate to code with no rewrite.
**Editor-integrated eval** (send the form under the cursor to the connected REPL via the LSP,
ADR-0038) and **"save session → `.rian`"** close the loop both ways.

### 6. One eval engine, surfaces per environment (no drift)

The compiling eval core (read → check → `Beam` → load → eval → print) is exposed as **composable
functions**, reused unchanged by every interactive surface:

```
        one eval engine  (read → check → compile(Beam) → load → eval → print)
        ├── terminal REPL  (IEx/Clojure-style; connected/--remote)   — this ADR
        ├── Livebook       (BEAM-native, reactive cells)             — preferred notebook
        ├── Jupyter kernel (reach; must impose ordered execution)    — later
        └── web playground (ADR-0052; JS target; FlatBars blueprint) — browser
```

No surface can diverge from the real compiler — the same no-drift discipline as the playground.

### 7. Terminal REPL is BEAM-only

Live redefinition + hot-reload is native on the BEAM and **not** on Rust/JS — so the *terminal* REPL
is BEAM-hosted (like the compiler host). The **JS-target interactive surface is the web playground**
(ADR-0052); we do not fake a Rust/JS terminal REPL. Native-per-target (ADR-0041), again.

**Rejected (2026-06-13 design review): a multi-target-by-default REPL.** A review proposed that the
REPL emit every expression to all Tier-1 targets and refuse to run anything that cannot emit to
`ex`+`rs`+`js`, to break the "BEAM comfort zone." Rejected on two grounds. (1) It does not catch its
own motivating example: a hot sequential loop *emits* to JS fine and then freezes the event loop at
*runtime* — that is a cost/complexity property no emitter gate observes, not a reachability one (the
bignum half of the example is already opt-in-visible via `Int.checked_add` &c., ADR-0035). (2) It
would reject valid Rian today, because the JS emitter still raises `Unsupported` on `struct`/`with`/
lambdas/FFI — making the REPL *less* capable to make a point. The portability discipline lives where
it is sound: the **CI gate** (`mix rian.targets --require …`, ADR-0058), default-on for shared/
`@targets` code. The keystroke-level check the review wanted is available **opt-in** — a `:targets
ex,rs,js` REPL pragma running the three-way emit on the next expression — not forced on the default
fast loop. The genuinely-unserved part (a *runtime-cost* axis distinct from reachability) is recorded
as future work, not solved by a REPL posture change.

### 8. Notebooks: Livebook over Jupyter

A notebook is **REPL-core + persistence + rich output + narrative**, so it shares this ADR's eval
engine. **Livebook is preferred over a generic Jupyter kernel** for a BEAM language: its cells are
**reactive / dependency-tracked**, which fits Rian's ordered, checked, single-assignment semantics —
whereas Jupyter's **out-of-order cell execution fights them** (run cell 3 before cell 1 and
redefinition/dependency is incoherent). A **Jupyter kernel stays possible** for reach (multi-language
notebooks), but it is the second priority and **must impose ordered execution** to stay sound.

## Ratings

| Decision | Rating |
|---|---|
| Compiling REPL (eval = real compiler; full gate; no REPL dialect) | 5/5 |
| Connected REPL (`--remote` into a running node; hot-reload) — the Clojure/IEx differentiator | 5/5 |
| Single-assignment → top-level redefinition/shadowing (not mutation) | 5/5 |
| Print value + inferred type + effect set; `h` docs; LSP completion | 4/5 |
| One eval engine, surfaces per environment (REPL/Livebook/Jupyter/playground) — no drift | 5/5 |
| Livebook preferred over Jupyter (reactive cells fit ordered semantics) | 4/5 |
| Terminal REPL BEAM-only; JS surface = playground | 4/5 |
| Connected-to-prod REPL needs auth + sandbox | 4/5 |

## Implementation sketch

`mix rian.repl` (and `Rian.Repl`) is a thin loop over the existing core:

1. **read** a unit (multiline-aware; `:=`/`def`/expr).
2. **eval** = `Rian.Beam.load/2` into the session's single module `rian_repl_<base>`, purged and
   reloaded per entry (with the prior session env in scope); a bare expression is wrapped as a
   polymorphic 0-arity entry and called. One module per session keeps the atom table and code
   memory bounded for arbitrarily long sessions.
3. **print** value + inferred type (ADR-0034) + effect set (ADR-0048).
4. helpers: `h`, history, completion (LSP), `--remote node@host` (connect + hot-reload via
   `:code.load_binary`).

The hard parts (parse, check, compile-to-bytecode, load) already exist in `Rian.Beam`; the REPL is
the loop + the typed/effect printer.

## v1 scope (implemented) vs direction

This ADR's *design* is the full surface above; the **shipped v1** is the local compiling REPL, the
part the existing components already support:

| In v1 (`Rian.Repl` + `mix rian.repl`) | Direction (future, not yet built) |
|---|---|
| Local compiling REPL — `Lexer → Decl/Pratt → Check → Beam → load → eval` (§1) | `--remote`/connected REPL into a running node (§2) |
| Top-level redefinition/shadowing; `:=` binds visible to later expressions (§3) | Editor-eval LSP protocol (§5) |
| Prints **value + inferred type** (§4); the current `Rian.Beam` construct scope | **Effect-set** in the output (needs the ADR-0048 effect checker) |
| One eval engine the future surfaces reuse (§6); BEAM-only (§7); `\help`/`\env`/`\type`/`\reset`/`\quit` meta-commands + engine introspection (`Rian.Repl.info/1`, `type_of/2`); native line editing, history & Rian-aware Tab-completion on a TTY (`Rian.Repl.complete/2`) | Livebook / Jupyter surfaces (§8); history persisted across sessions; richer completion (signatures, types) |

v1 is complete and correct for its scope (the `Rian.Beam` construct set: functions, sum variants,
`case`/`if`, guards, arithmetic, tuples/cons, atoms; **not** strings/`struct`/FFI/`with`, which raise a
clear error — never a silent miscompile). Top-level `:=` binds are visible to subsequent *expressions*,
not to function bodies (functions stay closed) — a deliberate, documented boundary.

## Consequences

- Closes the long-standing **REPL gap** (flagged in the early sweep) with a Clojure-grade, BEAM-native
  design built on existing components.
- **Cashes in ADR-0046** (BEAM dynamism was preserved *for* this) and reuses the **one-core-many-surfaces**
  pattern with the playground (ADR-0052).
- **No REPL/compile divergence** — the gate runs at the prompt (Samir).

## Open items

- **Connected-to-prod security** — *gating* prerequisites for `--remote`, specified in their own
  ADR: [ADR-0054 — Connected REPL Prerequisites](0054-connected-repl-prerequisites.md). Both
  attach authentication and an evaluation sandbox/fuel envelope ship before `--remote` does;
  they reuse the comptime sandbox (ADR-0030) and effect visibility (ADR-0048).
- **Session env model** — resolved in v1: prior `:=`/`def` units stay in scope across entries by
  re-emitting the accumulated session program into the session's single `rian_repl_<base>` module,
  purged and reloaded per entry; redefinition replaces the unit sharing a name (Clojure's `def`
  model).
- **Livebook integration shape** — a Rian smart-cell / kernel; and the eventual ordered-execution
  Jupyter kernel.
- **Editor-eval protocol** (ADR-0038) — the LSP message that ships a form to the connected REPL.
- **Line editing, history & completion** — `mix` launches the VM with `-noshell`, so the line
  editor is not running by default. On a real TTY the REPL upgrades that `-noshell` `user_drv` into
  an interactive line-editing group with `:user_drv.start_shell/1`, running the session as the
  group's "shell": this restores history and arrow recall and installs an `expand_fun` (backed by
  `Rian.Repl.complete/2`) for **Rian-aware Tab-completion** of keywords, `\`-meta-commands, and the
  session's own defined/bound names (kept current across the loop/group process boundary via a
  small public ETS table). Because the live session is what completion reads, completion is
  session-accurate, not a static list. In line-editing mode `Ctrl-D` is edlin's forward-delete, so
  `\quit` is the portable exit; quitting calls `System.stop/0` for a graceful shutdown that restores
  the terminal. When stdin/stdout is not a TTY (a pipe, CI) the REPL falls back to canonical-mode
  reads, where `rlwrap mix rian.repl` (with `--completions` feeding `rlwrap -f`) supplies history and
  static completion. The TTY path is exercised by pty harnesses
  (`test/manual/pty_completion_check.py`, `test/manual/pty_history_check.py`) rather than the ExUnit
  suite, since CI has no controlling terminal; the pure logic is unit-tested via `Rian.Repl.complete/2`,
  `Mix.Tasks.Rian.Repl.completion_for/2`, and `Rian.Repl.History`. The harnesses run on Linux via a
  manual GitHub Actions job (`.github/workflows/repl-pty.yml`, `workflow_dispatch`) that pins the same
  OTP 29 / Elixir 1.20 — the supported way to confirm `prim_tty`/terminal-restore parity off macOS.
