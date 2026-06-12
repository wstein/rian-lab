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
> [ADR-0031](docs/adr/0031-bootstrap-strategy.md)) now compiles real
> single-parameter `.rian` files end-to-end — `type` declarations and `def`
> functions parse to the pipeline IR, lower to Elixir + Rust, and run (try
> `mix run examples/decl_run.exs`). Still hand-built IR / not yet parsed:
> multi-parameter functions, `case`/block bodies, string literals, and
> `mod`/`struct`/`alias`. See [docs/README.md](docs/README.md) for an honest
> status map.

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
files. These are illustrative source, not yet compilable: there is no
declaration parser yet (ADR-0031), so the verified passes are driven by the
Elixir scripts in [examples/](examples/) until that lands.
