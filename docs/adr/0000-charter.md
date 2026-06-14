# ADR-0000 — Charter: Rian's thesis, the borrowing rule, the target model, and how to read this corpus

**Status:** Accepted — living (the index/charter; amended as the corpus evolves)
**Refs:** everything. This ADR states what the other ~40 are *for*. Most-load-bearing: ADR-0050 (one typed Core IR), ADR-0057 (concurrency native-per-target), ADR-0058 (inferred reachability), ADR-0032 (concept-borrowing), ADR-0035 (no hidden control flow), ADR-0049 (target tiers).
**Owners:** the whole team (Rachel Okafor, custodian).
**Origin:** the corpus-review debate (2026-06-14) — consensus #2, rated **5/5**. A reader had to reverse-engineer Rian's identity from 40 documents; this writes it down once.

## 1. The thesis (one paragraph)

**Rian shares typed *sequential* application logic — and its tests — across the BEAM, ECMAScript,
Rust, and the JVM, from a single source.** Concurrency is **native-per-target by design** (OTP on the
BEAM, async/threads in Rust, Promises/workers in JS — ADR-0057): you write the pure logic once in Rian
and call it from a native process/task/worker. Portability is **inferred, not declared** (ADR-0058):
the compiler *computes* which targets a function reaches (`Rian.Reach`); there is no binary
`@shared` flag. Safety is **gate-shaped**: inference, exhaustiveness, capability, and reachability are
refuse-to-emit gates, deliberately conservative — they never reject a valid program, only a *proven*
wrong one.

If a proposed feature does not serve "**portable sequential logic + tests, inferred portability,
native-per-target concurrency**," it does not belong in Rian.

## 2. The borrowing rule (the anti-magpie clause)

Rian borrows **surface freely and semantics never.** The family it borrows *spelling* from — Crystal
(primitives, `def`/`case`/`when`), Elixir/Erlang (the runtime, `with`, `|>`), Gleam (`Result`,
`@external`), Scala (opaque types), Haxe (abstract types) — is a source of *familiar syntax*
(ADR-0032), not of *meaning*. Every borrow must (a) serve §1's thesis and (b) keep Rian's own
semantics. We adopted Gleam's `@external` spelling but **rejected** Haxe's `#if`-in-body semantics
(ADR-0068); we borrowed Haxe's `abstract` *mechanism* but **rejected** its implicit-cast semantics
(ADR-0067). A borrow that imports foreign *semantics* is rejected on sight.

## 3. The target / portability model (how one source reaches four backends)

```text
source ─▶ Lexer ─▶ Decl/Pratt ─▶  Rian.Core (one typed IR, ADR-0050)  ─▶  gates  ─▶  emitters
                                          │                          (Check, Exhaustiveness,    Beam · Lower · JS · JVM
                                          │                           Capability, Reach)         (pure consumers of Core)
                                          ▼
                                  Reach computes each function's reachable target set
                                  (ADR-0058); host FFI / per-target bodies via @external
                                  (ADR-0068); concurrency is not in this picture (ADR-0057)
```

- **One IR, many emitters** (ADR-0050): an emitter is a pure consumer of `Rian.Core`. A new backend is
  a new consumer, not a new fork. *Evidence:* the JS and JVM emitters were added without forking the
  front end.
- **The portable core is the sequential subset that emits everywhere.** Concurrency, host FFI, and
  target-specific representation are *not* portable and are not pretended to be (ADR-0057/0068).
- **Tiers gate honesty** (ADR-0049 §5a): a target is Tier 1 only while the portable-core conformance
  suite is green on it; targets graduate, never waive. Resisting target sprawl is policy, not vibe.
- **Future targets are open** by construction (a new emitter on the Core IR) **and budgeted** by policy
  (each one can only narrow the portable LCD; adding one is a deliberate, gated decision).

## 4. What is distinctive (so it isn't mistaken for a clone)

The novel pairing is **inferred portability × the capability model**: one annotation
(`val`/`iso`/`ref`/`tag`, ADR-0055) yields ownership-checked Rust *and* BEAM use-once linearity,
while reachability is *computed* rather than asserted. No language in the family ships exactly this.
That pairing is the soul; the surface is the wardrobe.

## 5. How to read this corpus (the status taxonomy)

**The ADRs are the source of truth for decisions; they are *not* a claim of shipped code.** To avoid
mistaking a decision for an implementation, read statuses as:

| Status | Means | Shipped? |
| --- | --- | --- |
| **Proposed** | under discussion / a design or shootout; may change | no |
| **Accepted** | the decision is made and stable | maybe — check the code |
| **Accepted (direction)** | decision made, implementation **partial or pending** (often "· gated on …") | partially / not yet |
| **Implemented** | built **and verified** by tests | yes |
| ~~strikethrough~~ / **Superseded by ADR-NNNN** | retired; kept for the record | n/a |

**The authoritative answer to "is this real?" is not the ADR header — it is (a) the
[Status at a glance](../README.md) table in `docs/README.md` and (b) the tests.** When an ADR's
`Implemented:` line or the status table and the code disagree, that is a **bug to fix** (CLAUDE.md), not
a footnote. Rolling a precise `Implemented:` line onto every ADR is tracked as follow-up work
(corpus-review consensus #1); until it lands, the status table is the shipped-ness index.

## 6. Standing principles the corpus must not quietly break

- **No hidden control flow / no implicit coercion** (ADR-0035). Where sugar bends this (`<-`
  propagation, macros), the ADR must *say so explicitly and justify it* — invoking 0035 as a slogan
  while overriding it is itself a violation.
- **Conservative gates** (ADR-0034/0059): infer `:unknown` rather than guess; reject only a *proven*
  mismatch.
- **Errors are typed values** (ADR-0040): one model (`Result` / `T | E` / `with` / `<-`), layered
  sugar — not four mechanisms.
- **No nil** (ADR-0047): `Option`, never null.

## Open items

- **Per-ADR `Implemented:` line + a docs-build check** that the line matches reality (consensus #1).
- **Target-honest Reach** for emitter-unsupported constructs (atoms/`Result` on JS/JVM), so the reach
  matrix matches the emitters rather than ADR-0041's architectural claim (consensus #4).
