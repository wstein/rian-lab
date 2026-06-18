# ADR-0081 — `@effects`/`@host` surface effect annotations; `@rian`→`@sig`, `@rian_host`→`@host` bridge rename

**Status:** Proposed (direction) · not yet implemented — this ADR fixes the **naming and shape** of the
host-effect surface annotation (the concrete realization of ADR-0048's "host effect") and untangles the
two annotation *layers* (Elixir-bridge vs Rian-surface) that the `@rian`/`@rian_host` names currently
conflate. It does not, by itself, build the effect system.
**Implemented:** no — the host effect stays an inferred `:ex` pin (ADR-0058) and the transpiler keeps
emitting the interim `# @rian_host:` comment (ADR-0048) until ADR-0048's effect surface lands. The
bridge rename (`@rian`→`@sig`, `@rian_host`→`@host`) is a mechanical follow-up that *can* land
independently; staged in §5.
**Refs:** ADR-0048 (effect tracking — the `host` effect this gives a surface), ADR-0068 (`@external`:
target-scoped FFI *bodies* — the mechanism this is explicitly **not**, §3), ADR-0034 (infer-local /
declare-public — effects are inferred for `defp`, declared+checked at the `pub` boundary), ADR-0057
(concurrency & host FFI are native-per-target), ADR-0058 (portability is **inferred**, not a binary
flag — Reach already pins a host-caller to `:ex` with no annotation), ADR-0050 (one typed Core IR — the
keyword's meaning lives only in its desugaring), ADR-0051 (`@doc`/`@moduledoc`/`@typedoc` annotations),
ADR-0060 (`@test`), ADR-0035/0040 (errors are values; no catchable exceptions — the boundary `@host`
marks)
**Owners:** Elena Rostova (FFI / lowering) · Maya Lin (emitters / grammar) · Samir Patel
(no-silent-non-portability guard) · Arthur Pendelton (Reach) · Kira Neri (honesty) · Rachel Okafor (PM)
**Origin:** the annotation-naming debate (2026-06-18). Consensus on `@host`-not-`@foreign` and on
splitting the bridge/surface namespaces; two directional calls taken on top of the consensus —
**`@host` as sugar for a general `@effects(host)` row**, and **rename `@rian` → `@sig`** (with
`@rian_host` → `@host` as the coherent completion).

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
   prose from the `@external` *body* annotation. Rejected (see §6).

ADR-0048 already names `@rian_host` "the **interim**, honest, greppable placeholder" for a future
`host`/`fault` effect row. This ADR fixes what that row's surface looks like.

## Decision

### 1. The host effect surfaces as `@effects(...)`, with `@host` as sugar for `@effects(host)`

When ADR-0048's effect system lands, an effect is declared as a row:

```rian
@effects(host)
pub def load_result(src String) (Module | String) := …
```

`@host` is **pure sugar** for the single-effect common case:

```rian
@host
pub def load_result(src String) (Module | String) := …      # ≡ @effects(host)
```

The keyword's meaning lives **only in the desugaring** — `@host` rewrites to `@effects(host)` at the
parse boundary, so `Rian.Check`, `Rian.Reach`, and every emitter see exactly one representation
(ADR-0050; mirrors how `Prim.*` normalizes to `__prim_*` and how `into:` desugars to `List.reduce`,
ADR-0047/0079). This forecloses an annotation-per-effect grammar (`@io`, `@nondeterministic`, …): the
family is **one** production in `Rian.Decl.take_decl/1`, with `@host` as the only sugared member until a
second effect earns one.

### 2. The effect is inferred; the annotation is a declare-public assertion

Per ADR-0034 §1 and ADR-0058:

- A **`defp`** carries the host effect **by inference** — no annotation. Reach already does this.
- A **`pub`** function *may* declare `@host`/`@effects(host)`; the checker **verifies** the declaration
  against the inferred effect set (a `pub` that declares `@host` but never touches the host is an
  error; one that omits it but does is a declare-public violation, same shape as an undeclared error in
  the return type).

Consequence for the transpiler: it emits `@host` **only on `pub` host boundaries**; a private
host-caller is left annotation-free and carried by inference. (Until the grammar lands, it keeps
emitting the `# @rian_host:` comment introduced for the marker cleanup — see §5.)

### 3. `@host` (effect) is **not** `@external` (body)

| | `@external(:target, "spec")` (ADR-0068) | `@host` / `@effects(host)` (this ADR) |
|---|---|---|
| What it is | a **body** mechanism | an **effect** on a function that *has* a portable body |
| Portable body? | **none** — the body *is* the host call, one per target | **yes** — pure Rian logic that *may fault in*, or *catch a raise from*, the host |
| Per-target? | yes — one binding per `:target` | no — one effect, target-agnostic |
| Reach reads it as | the honest target set the externals cover | a pin to `:ex` (host effect ⇒ BEAM-only, ADR-0057) |
| Example | `@external(:ex, ":erlang.float_to_binary(x)")` | a `Result`-returning wrapper over `Code.format_string!` |

The spec must carry this table verbatim; the two are the most confusable pair in the annotation
vocabulary and the reason `@foreign` is rejected.

### 4. Bridge rename: `@rian` → `@sig`, `@rian_host` → `@host`

The Elixir-bridge annotations are renamed to describe *what they mean*, not *which language they bridge
to*:

- `@rian` → **`@sig`** — it embeds a Rian **signature** (`@sig "pub def arity(Func) Int53"`).
- `@rian_host` → **`@host`** — it tags a host-effect boundary, the same word as the Rian surface.

This is the *fix* for the false-sibling problem, not a new collision: `@rian`/`@rian_host` only
*looked* related; `@sig` (signature embedding) and `@host` (effect tag) are honestly orthogonal.
Bridge `@host` and surface `@host` share a spelling but **never share a file** (`.ex` vs `.rian`), so
the compiler never sees both at once; the shared name makes the cross-boundary mapping legible:

> Elixir-bridge `@host` (tags an `.ex` def) **transpiles to** Rian-surface `@host` (≡ `@effects(host)`).

`@sig` and the persisted `.beam` attribute it registers (`:sig`, was `:rian`) are read by
`Rian.Ann.from_source/1` / `from_beam/1` and the transpiler's signature harvest.

### 5. Reach / `--check` / migration follow inference, not the keyword

The `mix rian.transpile --check` allowlist is keyed today on `@rian_host`. Under §2 it must become
**inference-backed**: a private host-caller stays sanctioned *without* an annotation (Reach already
knows it touches the host). A regression test must assert this — an un-annotated private host-caller is
not a `--check` failure. (This is the one item the panel flagged as a real implementation risk, not a
naming question.)

## Consequences

- **Migration surface:** ~30 `@rian`→`@sig` and ~24 `@rian_host`→`@host` edits across `lib/rian/*.ex`;
  `Rian.Ann.__using__` registers `:sig`/`:host` instead of `:rian`/`:rian_host`; `host_funcs/1` reads
  `:host`; `from_beam/1` reads the persisted `:sig`. Tooling that reads `.beam` attributes needs a
  window reading *both* old and new keys (§ migration).
- **Grammar cost:** one `take_decl` clause for `@effects(...)` plus the `@host` sugar — mirrors the
  existing `@targets(...)` handling. No new Core node (it desugars).
- **Doc debt cleared:** the `Rian.Ann` moduledoc and the spec gain the bridge-vs-surface split and the
  `@external`-vs-`@host` table; the transpiler moduledoc/header switch the "`# @rian_host:` note" line
  to "`@host` on `pub` boundaries" once §5 lands.
- **No silent behavior change:** until the Rian grammar accepts `@effects`/`@host`, the transpiler's
  output is unchanged (still the `# @rian_host:` comment), so this ADR can be accepted as direction
  without touching emitted drafts.

## Migration plan (staged, each independently shippable)

1. **Docs only (now).** Add the bridge-vs-surface split to `Rian.Ann` moduledoc; no code/name changes.
   The transpiler keeps the `# @rian_host:` comment.
2. **Bridge rename.** `@rian`→`@sig`, `@rian_host`→`@host` in `lib/rian/*.ex`, with `Rian.Ann` reading
   both the old and new persisted attributes for one release (deprecation window), then dropping the
   old keys. Independent of the effect system.
3. **Surface landing (with ADR-0048).** `Rian.Decl` parses `@effects(...)`/`@host`; `Rian.Check`
   verifies the declare-public assertion (§2); the `--check` allowlist switches to inference (§5); the
   transpiler emits `@host` on `pub` boundaries and the `# @rian_host:` comment fallback is removed.

## Alternatives considered

- **`@foreign` for the host effect — 2/5.** Semantically defensible, but lexically a synonym of the
  shipped `@external` (ADR-0068); the two would be indistinguishable in prose. Rejected (§3).
- **`@host` as a standalone keyword, no `@effects` family — 2/5.** Cheaper today; invites a new keyword
  per future effect. The `@effects(host)`-with-`@host`-sugar form costs one extra parser production and
  scales (Maya Lin).
- **No annotation, pure inference — 2/5.** Honest (Reach already infers it) but loses the declare-
  public boundary assertion (ADR-0034) and the at-a-glance legibility Samir Patel requires; and leaves
  the `--check` allowlist without an explicit `pub`-boundary signal. The chosen design keeps inference
  for `defp` and a checked declaration for `pub`.
- **Keep `@rian`/`@rian_host` — rejected (by direction).** The false-sibling naming actively
  mis-teaches the bridge/surface boundary (Kira Neri). Churn is real (Rachel Okafor), hence the staged
  deprecation window in §5, but the mental-model cost was judged to outweigh it.
- **`@rian_sig` / `@sig_host` — not taken.** Verbose, and `_host`/`_sig` suffixes re-create the orphan-
  prefix problem once the `@rian` sibling is gone.

## Open questions

1. **`--check` allowlist under inference (§5).** Exact rule for "a private host-caller is sanctioned":
   is it *any* function Reach pins to `:ex` via a host call, or only those transitively reachable from a
   `@host`-declared `pub`? The former is simpler; the latter is stricter about declaring intent.
2. **`@effects` placement.** A head annotation (this ADR) vs. an effect position *inside* the signature
   (`pub def f(...) Ret !host`, à la Koka). The annotation form composes with the existing `@`-grammar
   and the transpiler; an in-signature form is terser but a larger grammar change. Deferred to ADR-0048.
3. **Deprecation-window length** for the persisted `:rian`/`:rian_host` `.beam` attributes (§ migration
   step 2) — one release, or until the next self-host fixed point is re-cut?
