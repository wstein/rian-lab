# ADR-0026 — Erlang/BEAM Ecosystem Integration (No Fork)

**Status:** Accepted · **Supersedes (partially):** the "transpile to Elixir source" framing
**Owners:** Maya Lin (architecture) · Kira Neri (toolchain) · Liam Davis (ecosystem)

## Context

Rian must feel like a first-class BEAM citizen sharing the Erlang toolchain. The question
raised: should we fork the Elixir repository to achieve this?

Three concerns were conflated and must be separated:
1. **Host** — what the compiler is written in (Elixir).
2. **BEAM target** — what Rian emits for the BEAM (currently Elixir *source*).
3. **Ecosystem** — Hex, rebar3/mix, OTP behaviours, docs, dialyzer.

"First-class Erlang citizen" is concerns (2) and (3). Forking addresses neither well.

## Decision

**Do not fork Elixir or OTP.** Integrate via stable, public BEAM APIs.

1. **BEAM target = Erlang-native, not Elixir source.** The production backend emits **Core
   Erlang / abstract forms** and compiles them in-process via `:compile.forms/2`, loading with
   `:code.load_binary/3`. A readable Erlang `.erl` emitter is the pragmatic first step and a
   permanent debug/inspection output. Emitting **Elixir source is demoted to optional** — it
   adds an Elixir build dependency and the `'Elixir.Mod':func` prefix for Erlang callers,
   neither acceptable for first-class Erlang status. This revises the original "transpiles to
   Elixir" goal; the lowering structure is unchanged, only the surface output.

2. **Compiler stays Elixir-hosted but ships as a self-contained binary/escript**, so end users
   need no Elixir installed. Its output owes nothing to Elixir. (A Rust-hosted compiler, the
   Gleam model, is deferred — large rewrite, not required for first-class status.)

3. **Ecosystem integration:**
   - **Hex** — publish Rian packages; consume Hex deps.
   - **rebar3 plugin + Mix compiler** — Rian sources compile inside existing Erlang and Elixir
     projects (Gleam's `rebar_gleam` / `mix_gleam` model).
   - **OTP behaviours first-class** — gen_server / supervisor / application callbacks emitted
     with the right `-behaviour()` attribute and exports.
   - **Predictable module naming** — Rian modules are ordinary BEAM modules; MFA interop is free
     both ways (`rian_geometry:area(...)` from Erlang, `:rian_geometry.area(...)` from Elixir).
   - **EEP-48 doc chunks** — `h` in IEx/erl shell, ExDoc, `code:get_doc/1` work on Rian modules.
   - **Dialyzer-compatible `-spec`/`-type`** — Rian is typed, so emit precise specs.
   - **OTP releases** via relx / `mix release` (later).
   - **Upstream small hooks** if a build/packaging gap blocks us, rather than forking.

## Rationale (precedent)

No outside team that succeeded on the BEAM forked the language above it:
- **Gleam** — Rust compiler, emits Erlang source, on Hex, rebar3 + mix integration.
- **LFE** — emits Core Erlang, on Hex, rebar3-native.
- **Elixir** — built on Erlang via the public compiler/runtime; never forked OTP.

The BEAM provides Core Erlang precisely so languages interoperate without forking. Driving
`:compile`/`:code` directly *is* sharing the Erlang toolchain.

## Ratings

| Option | Rating |
|---|---|
| Don't fork; build on public APIs | 5/5 |
| Fork Elixir / fork OTP | 1/5 (reject) |
| Emit Core Erlang / abstract forms (`:compile.forms`) | 5/5 |
| Emit readable `.erl` first (Gleam-style) | 4/5 |
| Keep Elixir source as canonical target | 2/5 (demote) |
| Hex publish + consume | 5/5 |
| rebar3 plugin + Mix compiler | 5/5 |
| OTP behaviours first-class | 5/5 |
| Predictable naming / free MFA interop | 5/5 |
| EEP-48 docs | 4/5 |
| Dialyzer `-spec` emission | 4/5 |
| Ship compiler as self-contained binary | 4/5 |
| Rust-hosted compiler (Gleam model) | 3/5 (defer) |

## Consequences

- Retarget the existing Elixir-source emitter to an Erlang emitter (`.erl` first, then
  Core Erlang / abstract forms). Same lowering pipeline; new surface.
- The exhaustiveness gate, pattern lowering, operator table, and capability lowering are all
  target-agnostic above the emitter and carry over unchanged.
- Interop acceptance test: a Rian module callable from both `erl` and IEx with no shims.

## Open items
- ~~Choose Core Erlang vs abstract forms as the production IR.~~ **Resolved 2026-06-12: abstract
  forms.** For a *typed* language emitting precise `-spec`/`-type` and EEP-48 docs, abstract forms
  carry specs and docs **directly**, and the readable `.erl` debug emitter (the "readable `.erl`
  first" step above) is their prettyprint — so it costs nothing extra. Core Erlang's only edge is
  codegen regularity; revisit *only* if nested-pattern/guard codegen against abstract forms proves
  painful. Cutover sequencing is in [ADR-0031](0031-bootstrap-strategy.md) (open items).
- ~~Behaviour syntax in Rian surface (how a Rian module declares `gen_server`).~~ **Resolved by
  [ADR-0044](0044-otp-behaviours.md):** `@behaviour(gen_server)` annotation on a `mod`, callbacks as
  checked `def`s, state type threaded; BEAM-only.
- Hex metadata mapping (app name, version, deps) from a Rian manifest.
