# RianLab

Reference implementation and design corpus for **Rian** — a typed,
capability-disciplined language hosted on the Erlang/BEAM ecosystem that lowers
the *same source* to two targets:

- **BEAM** — idiomatic Elixir/Erlang, reusing OTP and Hex with no fork.
- **Rust** — idiomatic, ownership-checked code, driven by Rian's reference
  capabilities (`val` / `iso` / `ref` / `tag`) instead of hand-written lifetimes.

> **Status: proof-of-concept.** The lowering passes, exhaustiveness gate,
> capability model, and hygienic macros are implemented and tested at the
> component level. A **Stage 0.1 declaration parser** ([`Rian.Decl`](lib/rian/decl.ex),
> [ADR-0031](docs/adr/0031-bootstrap-strategy.md)) — token-driven recursive
> descent over a real lexer ([`Rian.Lexer`](lib/rian/lexer.ex)) — now compiles
> real `.rian` files end-to-end: `type`/`struct`/`alias`/`const`/`use`/`mod`
> declarations and single- or multi-parameter `def` functions (with `pub`
> visibility), `:=` one-liner **and** multiline `… end` block bodies (`case`,
> string literals, `when` guards), and struct/sum-variant construction — all
> parse to the pipeline IR, lower to Elixir + Rust, and run. The whole modules
> tour ([examples/rian/05_modules.rian](examples/rian/05_modules.rian)) compiles
> end-to-end. A conservative, unification-based **type checker**
> ([`Rian.Check`](lib/rian/check.ex), [ADR-0034](docs/adr/0034-type-system-foundations.md))
> gates compilation and narrows types through `case`/clauses. Try
> `mix run examples/decl_run.exs`. See [docs/README.md](docs/README.md) for an
> honest status map.

## Pipeline

```text
parse (Pratt)
  → pattern lowering
  → exhaustiveness gate     # refuses to emit on a non-total / dead match
  → macro / comptime expansion
  → emit Elixir | emit Rust
```

The front-end is **target-agnostic**: the parser, exhaustiveness engine, pattern
lowering, and operator table all sit above the emitter, so the BEAM and Rust
backends share one core.

## Compiling a `.rian` file

```sh
mix rian.compile examples/area.rian                       # BEAM bytecode + Rust
mix rian.compile examples/rian/05_modules.rian --rust     # Rust only
mix rian.compile examples/rian/08_lambdas_collections.rian --beam  # BEAM bytecode only (allows Erlang FFI)
mix rian.compile examples/area.rian --beam --show-elixir  # + the Elixir-text debug view
mix rian.tour                                             # regenerate the by-example site dataset from the emitters
```

By default both **real** targets are emitted: the BEAM target is compiled to
loadable **bytecode** through the Erlang abstract-forms backend
([`Rian.Beam`](lib/rian/beam.ex), the canonical BEAM path — reported by module,
exports, and `.beam` size), and Rust as idiomatic source. `--beam` permits
Erlang FFI (`:lists.sum/1`, which has no Rust form); `--rust` narrows to Rust.

The Elixir-text emitter ([`Rian.Lower`](lib/rian/lower.ex)) is a **debug
artifact**, not the execution path — BEAM runs from bytecode, not this text. It
is printed only with `--show-elixir` (additive). The task exits non-zero on a
parse, exhaustiveness, or type-check error. From code the BEAM entry point is
`Rian.Beam.compile/2` / `Rian.Beam.compile_program/1`; `Rian.Decl.compile/1`
still drives the Rust + debug-Elixir text.

## Layout

| Path | Contents |
| --- | --- |
| [lib/rian/](lib/rian/) | Compiler modules (`Rian.*`) |
| [test/rian/](test/rian/) | Component test suites |
| [examples/](examples/) | Runnable demonstration scripts (Elixir drivers) |
| [examples/rian/](examples/rian/README.md) | Rian-by-example — an annotated `.rian` tour of the surface syntax |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [docs/spec/](docs/spec/) | Language specifications |
| [docs/README.md](docs/README.md) | Index + status of the whole corpus |

### Modules

| Module | Responsibility |
| --- | --- |
| [`Rian.Decl`](lib/rian/decl.ex) | Stage 0.1 declaration parser: `.rian` source → pipeline IR |
| [`Rian.Pratt`](lib/rian/pratt.ex) | Precedence-climbing expression parser |
| [`Rian.Exhaustiveness`](lib/rian/exhaustiveness.ex) | Maranget usefulness algorithm — the emission gate |
| [`Rian.PatternLower`](lib/rian/pattern_lower.ex) | Surface patterns → checker IR |
| [`Rian.Capability`](lib/rian/capability.ex) | Capability → Rust signature + BEAM linearity |
| [`Rian.Lower`](lib/rian/lower.ex) | End-to-end lowering to Elixir and Rust |
| [`Rian.Macro`](lib/rian/macro.ex) / [`Rian.Comptime`](lib/rian/comptime.ex) | Hygienic macros, pure comptime |

## Getting started

```sh
mix deps.get          # fetches ex_doc (dev only)
mix test              # full component suite
mix run examples/lower_run.exs   # end-to-end area/1 lowering demo
mix docs              # render ADRs + specs + module docs (ExDoc)
```

Some example scripts shell out to `rustc` to compile the emitted Rust and write
`*.rs` files to the working directory; those outputs are gitignored.

## Documentation

Start with the corpus index: **[docs/README.md](docs/README.md)**.

To read the language *by example*, see the annotated source tour in
**[examples/rian/](examples/rian/README.md)** — it walks the surface syntax (expressions,
types, capabilities, modules, macros, FFI) in faithful, spec-checked `.rian`
files that compile through the declaration parser (`Rian.Decl`, ADR-0031) and
lower to every target.

### Website

The Starlight docs and the bespoke marketing/tutorial pages both live in
**[site/](site/README.md)**. The interactive *Rian by Example*, homepage,
playground, and docs-reader pages render their per-target code from
`site/src/data/tour.json` — a committed dataset produced by `mix rian.tour` from
the *real* emitters, so what the site shows is exactly what the compiler emits.
`Rian.TourTest` fails the build if the committed file drifts from `generate/0`.
