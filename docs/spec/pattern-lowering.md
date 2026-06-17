# Rian Language Specification — Pattern Lowering Pass

**Status:** Locked + reference implementation verified · **Refs:** ADR-0022
**Owner:** Samir Patel · **Closes:** integration open-item in `rian-spec-exhaustiveness.md` §7
**Implementation:** `lib/rian/pattern_lower.ex` · **Tests:** `test/rian/pattern_lower_test.exs` (17/17 pass)

This pass runs on the typed core IR **before** exhaustiveness analysis. It desugars surface
patterns into the checker's representation and converts refutable refinements (pins, key-bearing
maps) into guards, so the verified checker sees exactly the shape it expects.

---

## 1. Position in the pipeline

```
parse → typecheck → [PATTERN LOWERING] → exhaustiveness/reachability → backend lowering
```

The checker (`Rian.Exhaustiveness`) requires:
- patterns as `:wild | {:ctor, id, [pattern]}`,
- a per-clause `guard: boolean` where refutable clauses are excluded from exhaustiveness.

This pass produces exactly that.

---

## 2. Transformations

| Surface pattern | Checker result | Guard introduced? |
|---|---|---|
| `_`, `{:var, n}` | `:wild` | no |
| `name @ p` | lower(`p`) (binder dropped) | from `p` |
| `^e` (pin) | `:wild` | **yes** — emits `__pᵢ == e` |
| literal `v` | `{:ctor, {:lit, v}, []}` | no |
| `Ctor(p…)` | `{:ctor, snake(Ctor), [lower(p)…]}` | from args |
| `{p…}` (tuple) | `{:ctor, {:tuple, n}, [lower(p)…]}` | from args |
| `[]` | `{:ctor, :nil, []}` | no |
| `[a, b \| t]` | nested `{:ctor, :cons, …}` | from elems/tail |
| `Struct(field: p, …)` | reorder to declared field order, missing → `:wild` | from fields |
| `%{}` (empty map) | `:wild` | no (irrefutable) |
| `%{k: p, …}` (open map) | `:wild` | **yes** (refutable, BEAM-only) |

Rationale: binders and as-patterns are irrelevant to coverage (always `:wild`); pins and
key-bearing maps are *refutable*, so they must not count toward exhaustiveness — modeling them
as guards reuses the checker's existing "guards don't count" rule rather than adding a new code
path.

Name conversion: `to_snake/1` maps `Circle`→`:circle`, `JNum`→`:j_num`, `JArr`→`:j_arr`;
already-snake atoms pass through.

---

## 3. Verified behavior (17/17 passing)

| Scenario | Result |
|---|---|
| `to_snake("JNum")` | `:j_num` |
| `{:var, x}`, `_` | `:wild`, no guard |
| `p @ Some(y)` | `{:ctor, :some, [:wild]}`, no guard |
| `^expected` | `:wild`, **guard introduced** |
| clause with a pin | `guard: true` → excluded from exhaustiveness |
| one pinned 2-arg clause | non-exhaustive (guarded clause cannot cover) |
| `{1, y}` (tuple) | `{:ctor, {:tuple, 2}, [{:ctor,{:lit,1},[]}, :wild]}` |
| `Point(y: a)` (struct) | reordered to `{:ctor, :point, [:wild, :wild]}` |
| single `Point()` clause | exhaustive (one constructor) |
| `[]`, `[h\|t]`, `[a,b\|rest]` | nil / cons / nested cons |
| empty map `%{}` | `:wild`, no guard |
| key-bearing map | `:wild`, **guard introduced** |
| surface Option clauses → lower → analyze (missing None) | witness `None` |
| surface Option `Some`+`None` → lower → analyze | exhaustive |

The last two confirm the **end-to-end** path: raw surface clauses lowered by this pass and fed
to the verified checker reproduce the same diagnostics as hand-built checker patterns.

---

## 4. Open items
- A surface pin `^x` is reachable (`Pratt.parse_pat` reads the `^` token → `{:pin, e}` →
  `Core.PPin`) and the **BEAM** lowers it to repeated-var equality. The Rust/JS/JVM emitters
  have **no** pin guard-transform yet, so `Rian.Reach` pins any clause with a `^x` head
  BEAM-only (`:rs`/`:js`/`:jvm` blocked) — honest until the guard form below lands.
- Emit the concrete pin guards (`__pᵢ == e`) into the IR for the non-BEAM backends (the checker
  only needs the boolean today; codegen needs the expression) — then drop the Reach blocker.
- Or-pattern row expansion, if/when or-patterns are un-deferred.
- Struct field defaults / `@enforce_keys` interaction with missing-field → `:wild`.
