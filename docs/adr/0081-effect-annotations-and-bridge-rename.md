# ADR-0081 — `@effects(host)` surface effect annotation; `@rian`→`@rian_sig` bridge rename

**Status:** Accepted — **bridge rename (§4) implemented**; the **effect surface (§1–§3) is direction
only**, gated on ADR-0048. This ADR fixes the **naming and shape** of the host-effect surface
annotation (the concrete realization of ADR-0048's "host effect") and untangles the two annotation
*layers* (Elixir-bridge vs Rian-surface) that the `@rian`/`@rian_host` names currently conflate. It does
not, by itself, build the effect system.
**Implemented:** partial — the **bridge rename `@rian`→`@rian_sig`** (keeping `@rian_host`) is done
across `lib/rian` + `Rian.Ann` + `Rian.Transpile` (clean cut, no compat shim). The **effect surface**
(`@effects(host)`) is not: the host effect stays an inferred `:ex` pin (ADR-0058) and the transpiler
keeps emitting the interim `# @rian_host:` comment (ADR-0048) until ADR-0048's effect grammar lands —
half-building the grammar (parsed-but-unenforced) would be a trap, so it is deferred whole. Staged in §5.
**Refs:** ADR-0048 (effect tracking — the `host` effect this gives a surface), ADR-0068 (`@external`:
target-scoped FFI *bodies* — the mechanism this is explicitly **not**, §3), ADR-0034 (infer-local /
declare-public — effects are inferred for `defp`, declared+checked at the `pub` boundary), ADR-0057
(concurrency & host FFI are native-per-target), ADR-0058 (portability is **inferred**, not a binary
flag — Reach already pins a host-caller to `:ex` with no annotation), ADR-0050 (one typed Core IR — the
keyword's meaning lives only in its desugaring), ADR-0051 (`@doc`/`@moduledoc`/`@typedoc` annotations),
ADR-0060 (`@test`), ADR-0035/0040 (errors are values; no catchable exceptions — the boundary
`@effects(host)` marks)
**Owners:** Elena Rostova (FFI / lowering) · Maya Lin (emitters / grammar) · Samir Patel
(no-silent-non-portability guard) · Arthur Pendelton (Reach) · Kira Neri (honesty) · Rachel Okafor (PM)
**Origin:** the annotation-naming debate (2026-06-18) and its follow-ups. The debate rejected
`@foreign` (collides with `@external`) and agreed to split the bridge/surface namespaces; two follow-up
calls settled the rest — **the surface effect is the explicit `@effects(host)` with no short keyword**
(not `@host`, not `@foreign`), and **rename `@rian` → `@rian_sig`** keeping the `@rian_*` Elixir-bridge
namespace (the bridge annotations live in *Elixir* source, so `@rian_sig`/`@rian_host` are honest
siblings, not flattened to `@sig`/`@host`).

## Context

There are **two distinct annotation layers** in this codebase that the names `@rian` / `@rian_host`
make look like siblings — and they are not:

- **Elixir-bridge annotations** live only in `lib/rian/*.ex`. They describe *crossing into Rian* from
  the host language:
  - `@rian "pub def arity(Func) Int53"` / `@rian """struct …"""` (30+ sites, 10 files) — embeds a
    native Rian signature where the Elixir→Rian transpiler's inference can't recover it (ADR-0034
    declare-public). Persisted to `.beam` so tooling reads it without the source (`Rian.Ann`).
  - `@rian_host "<reason>"` (24 sites, 10 files) — tags the **next** `def`/`defp` as a sanctioned
    host/fault boundary: a `try/rescue` that turns a host-runtime or parser raise into a value
    (`Code.format_string!`, ad-hoc compile, file I/O, the parser's `{:error,_}` seam). Read by
    `Rian.Ann.host_funcs/1` and excluded from the `mix rian.transpile --check` gate (honest
    non-portability, ADR-0035/0040 — not a Rian-concept clash).
- **Rian-surface annotations** live in `.rian` files and describe *Rian semantics*:
  - `@external(:target, "spec")` (ADR-0068, **implemented**) — a per-target host *body*; the function
    has no portable body. Parsed by `Rian.Decl.take_decl/1`.
  - `@targets(ex, rs, js)` (ADR-0058), `@test` (ADR-0060), `@doc`/`@moduledoc`/`@typedoc` (ADR-0051).

The `rian_` prefix on `@rian`/`@rian_host` is **noise in-language** (a `@rian` annotation *inside* Rian
would be a tautology) and actively teaches the wrong model — a newcomer reading `lib/rian/ir.ex` sees
`@rian` 13× and reasonably assumes it is a `.rian` construct they will write. It never is.

Two further facts constrain the design:

1. **The host effect is already inferred.** `Rian.Reach` pins a function to `:ex` whenever its body
   reaches a host call — *with no annotation* (ADR-0058). So the annotation is not what *creates*
   non-portability; it is, at most, a **declared, checked assertion** at the `pub` boundary
   (ADR-0034 §1, exactly like error sets) plus the `--check` allowlist key.
2. **`@foreign` collides with `@external`.** "Foreign" and "external" are synonyms; ADR-0068 already
   owns the foreign-*body* concept. A `@foreign` *effect* annotation would be indistinguishable in
   prose from the `@external` *body* annotation. Rejected (see *Alternatives considered*).

ADR-0048 already names `@rian_host` "the **interim**, honest, greppable placeholder" for a future
`host`/`fault` effect row. This ADR fixes what that row's surface looks like.

## Decision

### 1. The host effect surfaces as `@effects(...)` — one uniform row, no per-effect keyword

When ADR-0048's effect system lands, an effect is declared as a row; the host effect is `@effects(host)`:

```rian
@effects(host)
pub def load_result(src String) (Module | String) := …
```

There is **deliberately no short sugar** (`@host`, `@foreign`, …): every effect — present and future
(`@effects(io)`, `@effects(host, io)`, …) — uses the *same* `@effects(...)` form, so the grammar is
**one** production in `Rian.Decl.take_decl/1` (mirroring `@targets(...)`), with **no** per-effect
keyword to add, document, or desugar. A bespoke `@host` keyword would buy three saved characters at the
cost of a sugar/desugar layer and the temptation to grow a keyword per effect (`@io`,
`@nondeterministic`, …); the uniform row is the smaller, more honest surface. (Rationale: the
2026-06-18 naming debate's anti-sprawl position, taken to its conclusion — the only effect spelling is
`@effects(...)`.)

### 2. The effect is inferred; the annotation is a declare-public assertion

Per ADR-0034 §1 and ADR-0058:

- A **`defp`** carries the host effect **by inference** — no annotation. Reach already does this.
- A **`pub`** function *may* declare `@effects(host)`; the checker **verifies** the declaration against
  the inferred effect set (a `pub` that declares `@effects(host)` but never touches the host is an
  error; one that omits it but does is a declare-public violation, same shape as an undeclared error in
  the return type).

Consequence for the transpiler: it emits `@effects(host)` **only on `pub` host boundaries**; a private
host-caller is left annotation-free and carried by inference. (Until the grammar lands, it keeps
emitting the `# @rian_host:` comment introduced for the marker cleanup — see §5.)

### 3. `@effects(host)` (effect) is **not** `@external` (body)

| | `@external(:target, "spec")` (ADR-0068) | `@effects(host)` (this ADR) |
|---|---|---|
| What it is | a **body** mechanism | an **effect** on a function that *has* a portable body |
| Portable body? | **none** — the body *is* the host call, one per target | **yes** — pure Rian logic that *may fault in*, or *catch a raise from*, the host |
| Per-target? | yes — one binding per `:target` | no — one effect, target-agnostic |
| Reach reads it as | the honest target set the externals cover | a pin to `:ex` (host effect ⇒ BEAM-only, ADR-0057) |
| Example | `@external(:ex, ":erlang.float_to_binary(x)")` | a `Result`-returning wrapper over `Code.format_string!` |

The spec must carry this table verbatim; the two are the most confusable pair in the annotation
vocabulary — and the reason a short `@foreign`/`@host` keyword is rejected in favour of the explicit
`@effects(host)` (§1, *Alternatives considered*).

### 4. Bridge rename: `@rian` → `@rian_sig` (keep `@rian_host`)

The bridge annotations live in **Elixir** source, alongside `@doc`/`@spec`/`@impl`. There, the
`@rian_*` prefix is not noise — it is the **namespace** that says "this attribute is the Elixir→Rian
bridge," and it keeps the annotation from reading as a generic Elixir construct. Flattening `@rian` to
`@sig` would *drop* that namespace and, worse, invite confusion with `@spec` (which `@rian` deliberately
does **not** generate — Rian is the type system). So the bridge stays namespaced:

- `@rian` → **`@rian_sig`** — embeds a Rian **signature** (`@rian_sig "pub def arity(Func) Int53"`).
- `@rian_host` → **kept** — already correctly namespaced.

This *resolves* the original "false sibling" complaint by making the siblings **true**: `@rian_sig` and
`@rian_host` are two sub-kinds (`sig`, `host`) of one Elixir-bridge family (`@rian_*`), rather than a
bare base (`@rian`) with a lone modifier (`@rian_host`) that read as base-plus-suffix. The Rian
*surface* host effect is the separate `@effects(host)` (§1), so the layers stay distinct **and** get
distinct spellings — the cross-boundary mapping is explicit:

> Elixir-bridge `@rian_host` (tags an `.ex` def) **transpiles to** Rian-surface `@effects(host)`.

**Rejected sub-forms.** `@sig` — drops the bridge namespace, collides conceptually with `@spec`.
`@rian(sig)` / a tagged value (`@rian sig: "…"`, `@rian {:sig, "…"}`) — `@name(tag)` is not an Elixir
attribute form, so a sub-kind would have to live in the *value*, changing it from a bare string to a
keyword/tuple and rippling into `Rian.Ann.from_source/1`/`from_beam/1` parsing and every call site —
strictly more churn than a distinct attribute name, for no gain.

`@rian_sig` and the persisted `.beam` attribute it registers (`:rian_sig`, was `:rian`) are read by
`Rian.Ann.from_source/1` / `from_beam/1` and the transpiler's signature harvest. `@rian_host` and its
`:rian_host` attribute are unchanged.

### 5. Reach / `--check` / migration follow inference, not the keyword

The `mix rian.transpile --check` allowlist is keyed today on `@rian_host`. Under §2 it must become
**inference-backed**: a private host-caller stays sanctioned *without* an annotation (Reach already
knows it touches the host). A regression test must assert this — an un-annotated private host-caller is
not a `--check` failure. (This is the one item the panel flagged as a real implementation risk, not a
naming question.)

## Consequences

- **Migration surface:** ~30 `@rian`→`@rian_sig` edits across `lib/rian/*.ex`; `@rian_host` (24 sites)
  is **unchanged**. `Rian.Ann.__using__` registers `:rian_sig` instead of `:rian`; `from_beam/1` reads
  the persisted `:rian_sig`. `host_funcs/1` and the `:rian_host` attribute are untouched. Tooling that
  reads the `:rian` `.beam` attribute needs a window reading *both* `:rian` and `:rian_sig` (§ migration).
- **Grammar cost:** one `take_decl` clause for `@effects(...)` — mirrors the existing `@targets(...)`
  handling. No new Core node, no sugar to desugar.
- **Doc debt cleared:** the `Rian.Ann` moduledoc and the spec gain the bridge-vs-surface split and the
  `@external`-vs-`@effects(host)` table; the transpiler moduledoc/header switch the "`# @rian_host:`
  note" line to "`@effects(host)` on `pub` boundaries" once §5 lands.
- **No silent behavior change:** until the Rian grammar accepts `@effects(...)`, the transpiler's
  output is unchanged (still the `# @rian_host:` comment), so this ADR can be accepted as direction
  without touching emitted drafts.

## Migration plan (staged, each independently shippable)

1. **Docs only (now).** Add the bridge-vs-surface split to `Rian.Ann` moduledoc; no code/name changes.
   The transpiler keeps the `# @rian_host:` comment.
2. **Bridge rename.** `@rian`→`@rian_sig` in `lib/rian/*.ex` (`@rian_host` unchanged), with `Rian.Ann`
   reading both the old `:rian` and new `:rian_sig` persisted attributes for one release (deprecation
   window), then dropping `:rian`. Independent of the effect system.
3. **Surface landing (with ADR-0048).** `Rian.Decl` parses `@effects(...)`; `Rian.Check` verifies the
   declare-public assertion (§2); the `--check` allowlist switches to inference (§5); the transpiler
   emits `@effects(host)` on `pub` boundaries and the `# @rian_host:` comment fallback is removed.

## Alternatives considered

- **`@foreign` for the host effect — 2/5.** Semantically defensible, but lexically a synonym of the
  shipped `@external` (ADR-0068); the two would be indistinguishable in prose. Rejected (§3).
- **A short effect keyword — `@host` (standalone, or as sugar for `@effects(host)`) — 2/5.** Saves three
  characters but adds a keyword (and, as sugar, a desugar layer) and invites one keyword per future
  effect (`@io`, `@nondeterministic`, …). The uniform `@effects(...)` row is the smaller surface and the
  one chosen (§1) — no sugar, no per-effect keyword (Maya Lin's anti-sprawl position, taken to its end).
- **No annotation, pure inference — 2/5.** Honest (Reach already infers it) but loses the declare-
  public boundary assertion (ADR-0034) and the at-a-glance legibility Samir Patel requires; and leaves
  the `--check` allowlist without an explicit `pub`-boundary signal. The chosen design keeps inference
  for `defp` and a checked declaration for `pub`.
- **`@rian` → `@sig` — rejected.** Drops the `@rian_*` bridge namespace in Elixir source and reads as a
  cousin of `@spec` (the exact association to avoid — `@rian`/`@rian_sig` deliberately generates no
  typespec). The bridge needs a namespace; `@sig` has none.
- **`@rian(sig)` / tagged value (`@rian sig: "…"`, `@rian {:sig, "…"}`) — rejected.** `@name(tag)` is
  not an Elixir attribute form; a sub-kind would have to move into the *value*, turning the bare-string
  value into a keyword/tuple and rippling through `Rian.Ann` parsing and every call site. Strictly more
  churn than a distinct attribute name, for no gain.
- **Keep `@rian` as-is — rejected.** The bare base `@rian` reads as base-plus-suffix against
  `@rian_host`, obscuring that they are two sub-kinds of one bridge family (Kira Neri). `@rian_sig`
  makes the sibling relation honest. Churn is ~30 sites (Rachel Okafor), bounded by the §5 deprecation
  window.

## Open questions

1. **`--check` allowlist under inference (§5).** Exact rule for "a private host-caller is sanctioned":
   is it *any* function Reach pins to `:ex` via a host call, or only those transitively reachable from a
   `@effects(host)`-declared `pub`? The former is simpler; the latter is stricter about declaring intent.
2. **`@effects` placement.** A head annotation (this ADR) vs. an effect position *inside* the signature
   (`pub def f(...) Ret !host`, à la Koka). The annotation form composes with the existing `@`-grammar
   and the transpiler; an in-signature form is terser but a larger grammar change. Deferred to ADR-0048.
3. **Deprecation-window length** for the persisted `:rian`/`:rian_host` `.beam` attributes (§ migration
   step 2) — one release, or until the next self-host fixed point is re-cut?
