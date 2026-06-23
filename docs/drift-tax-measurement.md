# Drift-tax measurement + declarative-lowering-table prototype

> Debate follow-up #3 (the multi-target strategy debate, ADR-0049 §5a / ADR-0086 §3).
> Samir's claim: "every feature is lowered once per emitter, so adding a target multiplies
> maintenance." This turns that claim into a **number** before committing to a table-driven
> refactor. Reproduce with `mix run scripts/measure_drift_tax.exs`.

## The measurement (the `__prim_*` intrinsic family)

The intrinsic set is the cleanest case to measure: it is *already* a near-declarative table —
one intrinsic, each emitter lowers it to a native form (ADR-0047).

| metric | value |
| --- | --- |
| distinct intrinsics | **20** |
| emitters | **7** (4 Elixir reference + 3 PureScript ports: Rust, JVM, JS) |
| total lowering **sites** = Σ (intrinsic, emitter) pairs hand-written | **109** |
| **touch count** to add intrinsic N+1 (avg emitters/intrinsic) | **5.5 files** |
| worst-case touch (an intrinsic every emitter supports) | **7 files** |

Per-emitter lowering sites: BEAM 20 · Rust(ex) 18 · JVM(ex) 15 · JS(ex) 15 · Rust(ps) 12 ·
JVM(ps) 14 · JS(ps) 15.

## What a single declarative table would change

| metric | hand-written (today) | one declarative table |
| --- | --- | --- |
| rows | — | 20 (one per intrinsic) |
| cells (the irreducible per-target templates) | ~109 | ~109 |
| **touch count / new intrinsic** | **5.5 (≤7)** | **1** |

### Prototype shape (illustrative — *not* wired into the build)

```purescript
-- one row per intrinsic; the columns ARE the per-target templates.
type PrimLowering = { js :: Array String -> String
                    , rust :: Array String -> String
                    , jvm :: Array String -> String }

primTable :: String -> Maybe PrimLowering
primTable = case _ of
  "__prim_int_to_string" -> Just
    { js:   \a -> at a 0 <> ".toString()"
    , rust: \a -> at a 0 <> ".to_string()"
    , jvm:  \a -> at a 0 <> ".toString()" }
  "__prim_panic" -> Just
    { js:   \a -> "(() => { throw new Error(" <> at a 0 <> "); })()"
    , rust: \a -> "panic!(\"{}\", " <> at a 0 <> ")"
    , jvm:  \a -> "throw RuntimeException(" <> at a 0 <> ")" }
  _ -> Nothing

-- a generic consumer each emitter shares (one clause, not N):
--   emit (ECall (EId p) args) | Just row <- primTable p = (column row) (map emit args)
```

Adding intrinsic #21 is **one row** (every target, one file) instead of editing each emitter
and re-proving parity per file.

## Reading (the honest verdict)

1. **Line count is ~conserved.** The per-target template *is* the lowering logic — ~109 cells
   either way. A table does not shrink the code; it **relocates** it. Anyone selling a table on
   "fewer lines" is wrong.
2. **Touch count is the real tax, and it collapses: 5.5 → 1** (7 → 1 worst case). One place to
   add a feature across every target, versus editing N emitters and re-running N parity gates.
   That is the maintainability win, and it grows linearly with target count — exactly Samir's point.
3. **The trade is indirection + per-cell richness.** A direct `emit (ECall (EId "__prim_x")) = …`
   clause is more readable than a table lookup, and real escape hatches remain — operator
   **precedence** (Rust's `Tuple … prec`), **ownership** (`.clone()`/`Box::new`), the JS
   whole-program **int-mode** split (`number` vs `BigInt`). A table cell must still be a *function*
   rich enough for those, not a format string.
4. **Verdict — scope it.** Worth a real prototype for the **mechanical prim/op families** (high
   touch, low per-cell variance: stringify, arithmetic, the HashMap ops). **Not** worth it for
   structurally-divergent nodes — **patterns, captures, `with`, exhaustiveness** — where each
   emitter's logic genuinely differs and a "table" would just be N functions wearing a trench coat.
   Measure each family before generalizing; the number above is the bar a refactor must beat.
