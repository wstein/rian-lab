-- | Erlang **abstract-forms** BEAM backend (ADR-0031 / ADR-0026) — the PureScript port of
-- | `Rian.Beam` (lib/rian/beam.ex), ADR-0084 **Phase 8** (execution / self-host). Rather than emit
-- | source text, this lowers a checked program directly to the Erlang **abstract format** and runs
-- | it through `compile:forms/2` → `code:load_binary/3` → `Mod:main()` — real `.beam` bytecode, no
-- | Elixir-compiler dependency. The bulk (the forms construction) is pure PureScript over an opaque
-- | `ETerm`; the Erlang FFI tail (the term constructors + compile/load/run) lives in `Beam.erl`.
-- |
-- | **Staged port.** Inc 1: the foundation — the `ETerm` term-builders, module assembly
-- | (`-module`/`-export` + function forms), and the portable expression/pattern core (integer/float/
-- | char/atom/bool literals, the operator algebra, variables, `:=` binds, local calls, `if`). Inc 2:
-- | **multi-clause dispatch** (a multi-clause `def` → one Erlang function, one clause per group
-- | member — Erlang dispatches natively), **`when` guards** (function-clause + `case`-arm → the
-- | Erlang guard sequence `[[G]]`), and **`case`** expressions. Inc 3: the **structural data layer**
-- | — **sum constructors/patterns** (`Circle(r)` ⇄ the tagged tuple `{circle, R}`, a nullary ctor →
-- | its atom; `ctorForm`), **lists** (`[a,b]`/`[h|t]` → a `{cons,…}`/`{nil,…}` chain; `consForm`),
-- | **tuples** (`{a,b}` → `{tuple,…}`; `tupleForm`), and **String** literals (→ a `<<"…">>` BEAM
-- | binary; `fStr`/`strBytes`). Inc 4: **structs** (a labeled `Point(x: …)` call / `EStruct` →
-- | a `__struct__`-tagged Erlang map; field access `p.x` → `maps:get`; `PStruct` → a map pattern
-- | requiring `__struct__ := tag`) and **maps** (`%{k: v}` → `#{k => v}`, `PMap` → a map pattern;
-- | `mapForm`/`mapField*`). Verified by EXECUTION: `runMain` compiles + loads + runs `main/0` and
-- | stringifies the result, parity-gated (the `beam` stream) against the Elixir reference running the
-- | same program. Inc 5: the **self-contained portable `Prim.*` intrinsics** — stringify
-- | (`__prim_int_to_string`/`float_repr`/`to_string`/`char_to_string`/`char_code`), concat
-- | (`__prim_str_concat`/`_all` + `<>` → a `<<…/binary>>` binary), the `Dict` map ops
-- | (`map_new`/`get`/`put`/`has` → native `#{}`/`maps:*`), `__prim_panic` → `erlang:error`, list
-- | membership `in` → `lists:member`, and the `Str.chars`/`from_chars`/`str_to_*` conversions — so
-- | `${int}` interpolation, string building, and maps run with no extra modules. Inc 6: the
-- | **64-bit overflow ops** (`__prim_wrapping_add`/`saturating_add`/`checked_add`) — BEAM ints are
-- | bignums, so each computes the true sum once (an immediately-applied `fun`) then projects onto
-- | signed-64 (wrap via `band` + sign-correct, saturate via `erlang:min`/`max`, check → `{some,S}`/
-- | `none`); `i64Overflow`/`i64Project`. **Deferred (later
-- | increments):** the type-directed lowering (the annotated/range-expanded core — `Show`/overflow/
-- | value-union discrimination), `@external`, specs/`type` attrs, remote `Mod.fun` user calls, and
-- | the whole-program / cross-module + const + prelude machinery (so `${float}` via `Show.float` and
-- | `List`/`Str`/`Dict` prelude calls land there). An unported node raises a clear crash.
module Rian.Beam
  ( runMain
  ) where

import Prelude

import Data.Array (head, length)
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), Replacement(..), contains, drop, replaceAll, stripPrefix, take) as Str
import Data.String.CodeUnits (charAt) as CU
import Data.String.Common (toUpper)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CMapPatPair(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Body, Clause, Func, Prog, bodySurface)
import Rian.PatternLower (toSnake)
import Rian.Pratt (parse) as P
import Rian.Prim (normalize)

-- ── the Erlang-FFI boundary (Beam.erl) ───────────────────────────────────────
foreign import data ETerm :: Type
foreign import mkAtomTerm :: String -> ETerm -- a raw atom
foreign import mkIntStr :: String -> ETerm -- a raw integer, from a Rian numeric string
foreign import mkIntI :: Int -> ETerm -- a raw integer, from a PureScript Int
foreign import mkFloatStr :: String -> ETerm -- a raw float
foreign import mkBinary :: String -> ETerm -- a raw binary (a Rian String literal)
foreign import strBytes :: String -> ETerm -- a String's UTF-8 byte charlist (a `{string,…}` node)
foreign import mkTuple :: Array ETerm -> ETerm
foreign import mkList :: Array ETerm -> ETerm
-- compile the forms list → load → run `Mod:main()` → the `~p`-rendered result (or a diagnostic).
foreign import runMainImpl :: ETerm -> String -> String

-- | Compile `src` to BEAM abstract forms, load the module, run its `main/0`, and return the
-- | stringified result (or a `Rian.Check:`/`compile_error:` diagnostic). The execution-parity entry.
-- @rian_sig pub def runMain(src val String) String
runMain :: String -> String
runMain src =
  case checkProgram prog of
    Just msg -> "Rian.Check: " <> msg
    Nothing -> runMainImpl (moduleForms "rian_main" prog) "rian_main"
  where
  prog = runProgramTail (assemble (parseToProg src))

-- the functions to compile: a single `mod`'s, else the top-level ones (mirrors `funcs_of`).
funcsOf :: Prog -> Array Func
funcsOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.funcs
    _ -> []
  fs -> fs

-- ── module assembly ──────────────────────────────────────────────────────────
moduleForms :: String -> Prog -> ETerm
moduleForms modName prog =
  let
    funcs = funcsOf prog
    exports = map (\f -> nameArity f.name (funcArity f)) funcs
  in
    mkList ([ attrModule modName, attrExport exports ] <> map functionForm funcs)

funcArity :: Func -> Int
funcArity f = case head f.clauses of
  Just c -> length c.pats
  Nothing -> length f.params

-- a function → `{function, 1, Name, Arity, [Clause]}`.
functionForm :: Func -> ETerm
functionForm f =
  fFunction f.name (funcArity f) (map clauseForm f.clauses)

-- a function clause → `{clause, 1, [PatForm], Guard, [BodyForm]}`. A multi-clause `def` is one
-- Erlang function with one clause per group member (Erlang dispatches natively); a `when` guard
-- lowers to the Erlang guard sequence `[[GuardExpr]]`.
clauseForm :: Clause -> ETerm
clauseForm c =
  fClause (map (patForm <<< fromPat) c.pats) (clauseGuardForm c.guard) (bodyForms (bodyExprOf c.body))

-- a function clause's `when` guard (a source string) → the Erlang guard sequence; `Nothing` → `[]`.
clauseGuardForm :: Maybe String -> ETerm
clauseGuardForm Nothing = noGuard
clauseGuardForm (Just g) = mkList [ mkList [ exprForm (fromExpr (normalize (P.parse g))) ] ]

-- a `case`-arm guard (already core) → the Erlang guard sequence `[[GuardExpr]]`; `Nothing` → `[]`.
armGuardForm :: Maybe CExpr -> ETerm
armGuardForm Nothing = noGuard
armGuardForm (Just g) = mkList [ mkList [ exprForm g ] ]

-- a `:=` body parses to an `EBlock`; lower each statement to a body form (a bare expression is a
-- one-statement body).
bodyForms :: CExpr -> Array ETerm
bodyForms (EBlock stmts) = map stmtForm stmts
bodyForms e = [ exprForm e ]

stmtForm :: CStmt -> ETerm
stmtForm (CExprStmt e) = exprForm e
-- a `:=` bind → an Erlang `{match, 1, {var,…}, Rhs}` (the declared type is erased, ADR-0034 §1).
stmtForm (CBind n e) = mkTuple [ mkAtomTerm "match", ln, fVar (varAtom n), exprForm e ]
stmtForm (CTypedBind n _ e) = mkTuple [ mkAtomTerm "match", ln, fVar (varAtom n), exprForm e ]

-- ── expressions → abstract forms ─────────────────────────────────────────────
exprForm :: CExpr -> ETerm
exprForm (ENum n) = numForm n
exprForm (EChar cp) = fIntegerI cp
exprForm (EStr s) = fStr s
exprForm (EId "true") = fAtom "true"
exprForm (EId "false") = fAtom "false"
-- a lowercase identifier is a variable; a PascalCase one is a nullary constructor (its atom tag).
exprForm (EId x) = if startsUpper x then fAtom (toSnake x) else fVar (varAtom x)
exprForm (EAtom a) = fAtom a
-- a list literal `[a, b]` / cons `[h | t]` → an Erlang `{cons, …}` chain (`{nil,…}`-terminated).
exprForm (EList elems tail) = consForm exprForm elems tail
-- a tuple `{a, b}` → an Erlang `{tuple, 1, […]}`.
exprForm (ETuple es) = tupleForm exprForm es
-- a struct construction `Name(f: v, …)` → a `__struct__`-tagged Erlang map.
exprForm (EStruct name fields) =
  mapForm ([ mapFieldAssoc (fAtom "__struct__") (fAtom (toSnake name)) ] <> map structFieldAssoc fields)
-- a map literal `%{k: v, …}` → an Erlang `#{k => v, …}`.
exprForm (EMap pairs) = mapForm (map mapPairAssoc pairs)
-- field access `value.field` → `maps:get(:field, Value)`.
exprForm (EDot head_ field) = remoteCall "maps" "get" [ fAtom field, exprForm head_ ]
exprForm (EUnary "-" x) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm "-", exprForm x ]
exprForm (EUnary "not" x) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm "not", exprForm x ]
-- string concat `<>` → a `<<L/binary, R/binary>>` binary (Erlang has no `<>` op).
exprForm (EBin "<>" l r) = fBin [ binSeg (exprForm l), binSeg (exprForm r) ]
-- list membership `x in xs` → `lists:member(x, xs)` (the portable surface op, ADR-0047).
exprForm (EBin "in" l r) = remoteCall "lists" "member" [ exprForm l, exprForm r ]
exprForm (EBin op l r) = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm (erlOp op), exprForm l, exprForm r ]
-- ── the portable `Prim.*` intrinsics (inc 5) → native Erlang/Elixir-runtime forms ──
exprForm (ECall (EId "__prim_map_new") []) = mapForm []
exprForm (ECall (EId "__prim_map_get") [ m, k ]) = remoteCall "maps" "get" [ exprForm k, exprForm m ]
exprForm (ECall (EId "__prim_map_put") [ m, k, v ]) = remoteCall "maps" "put" [ exprForm k, exprForm v, exprForm m ]
exprForm (ECall (EId "__prim_map_has") [ m, k ]) = remoteCall "maps" "is_key" [ exprForm k, exprForm m ]
exprForm (ECall (EId "__prim_str_concat") [ a, b ]) = fBin [ binSeg (exprForm a), binSeg (exprForm b) ]
exprForm (ECall (EId "__prim_str_concat_all") args) = fBin (map (binSeg <<< exprForm) args)
exprForm (ECall (EId "__prim_char_to_string") [ c ]) =
  fBin [ mkTuple [ mkAtomTerm "bin_element", ln, exprForm c, mkAtomTerm "default", mkList [ mkAtomTerm "utf8" ] ] ]
exprForm (ECall (EId "__prim_char_code") [ c ]) = exprForm c
exprForm (ECall (EId "__prim_int_to_string") [ n ]) = remoteCall "erlang" "integer_to_binary" [ exprForm n ]
exprForm (ECall (EId "__prim_int_to_float") [ n ]) = remoteCall "erlang" "float" [ exprForm n ]
exprForm (ECall (EId "__prim_float_repr") [ n ]) =
  remoteCall "erlang" "float_to_binary" [ exprForm n, mkTuple [ mkAtomTerm "cons", ln, fAtom "short", mkTuple [ mkAtomTerm "nil", ln ] ] ]
exprForm (ECall (EId "__prim_str_to_float") [ s ]) = remoteCall "erlang" "binary_to_float" [ exprForm s ]
exprForm (ECall (EId "__prim_to_string") [ x ]) = remoteCall "Elixir.String.Chars" "to_string" [ exprForm x ]
exprForm (ECall (EId "__prim_panic") [ m ]) = remoteCall "erlang" "error" [ exprForm m ]
exprForm (ECall (EId "__prim_str_chars") [ s ]) = remoteCall "Elixir.String" "to_charlist" [ exprForm s ]
exprForm (ECall (EId "__prim_str_from_chars") [ cs ]) = remoteCall "Elixir.List" "to_string" [ exprForm cs ]
exprForm (ECall (EId "__prim_str_to_atom") [ s ]) = remoteCall "Elixir.String" "to_atom" [ exprForm s ]
-- explicit 64-bit overflow ops (ADR-0035 §3): BEAM ints are bignums, so compute the true sum once
-- (an immediately-applied `fun`) then project onto signed-64: wrap / saturate / check.
exprForm (ECall (EId "__prim_wrapping_add") [ a, b ]) = i64Overflow Wrapping a b
exprForm (ECall (EId "__prim_saturating_add") [ a, b ]) = i64Overflow Saturating a b
exprForm (ECall (EId "__prim_checked_add") [ a, b ]) = i64Overflow Checked a b
-- an all-labeled call `Name(f: v, …)` is struct construction → a `__struct__`-tagged map; a
-- PascalCase positional call `Circle(r)` is sum construction → a tagged tuple `{circle, R}`; a
-- lowercase `f(args)` is a local call (inc 3/4: no var application / imports / cross-module yet).
exprForm (ECall (EId f) args) = case head args of
  Just (ELabel _ _) ->
    mapForm ([ mapFieldAssoc (fAtom "__struct__") (fAtom (toSnake f)) ] <> map labelAssoc args)
  _ ->
    if startsUpper f then ctorForm (toSnake f) (map exprForm args)
    else fCall (fAtom f) (map exprForm args)
-- `if c do t else e end` → an Erlang `case c of true -> t; false -> e end`.
exprForm (EIf c t e) =
  mkTuple
    [ mkAtomTerm "case"
    , ln
    , exprForm c
    , mkList [ fClause [ fAtom "true" ] noGuard (bodyForms t), fClause [ fAtom "false" ] noGuard (bodyForms e) ]
    ]
-- `case scrut do pat [when g] -> body … end` → an Erlang `{case, 1, Scrut, [Clause]}`.
exprForm (ECase scrut arms) =
  mkTuple [ mkAtomTerm "case", ln, exprForm scrut, mkList (map caseArmForm arms) ]
exprForm _ = unsafeCrashWith "abstract-forms: unported expression (Phase 8 inc 1)"

caseArmForm :: CArm -> ETerm
caseArmForm arm = fClause [ patForm arm.pat ] (armGuardForm arm.guard) (bodyForms arm.body)

-- ── patterns → abstract forms (inc 1: wildcards / vars / literals / atoms) ──
patForm :: CPat -> ETerm
patForm PWild = fVar "_"
patForm (PVar x) = fVar (varAtom x)
patForm (PLit (LInt n)) = fIntegerI n
patForm (PLit (LStr s)) = fStr s
patForm (PAtom a) = fAtom a
-- a sum pattern `Circle(r)` → the tagged-tuple pattern `{circle, R}` (a nullary ctor → its atom).
patForm (PCtor name args) = ctorForm (toSnake name) (map patForm args)
-- a list pattern `[a, b]` / `[h | t]` → an Erlang `{cons, …}` pattern chain.
patForm (PList elems tail) = consForm patForm elems tail
-- a tuple pattern `{a, b}` → an Erlang `{tuple, 1, […]}` pattern.
patForm (PTuple ps) = tupleForm patForm ps
-- a struct pattern `Name(f: p, …)` → a map pattern requiring `__struct__ := tag` + each field.
patForm (PStruct name fields) =
  mapForm ([ mapFieldExact (fAtom "__struct__") (fAtom (toSnake name)) ] <> map structFieldPat fields)
-- a map pattern `%{k: p, …}` → an Erlang map pattern over the named keys.
patForm (PMap pairs) = mapForm (map mapPatPairExact pairs)
patForm _ = unsafeCrashWith "abstract-forms: unported clause pattern (Phase 8)"

-- ── abstract-format node builders ────────────────────────────────────────────
ln :: ETerm
ln = mkIntI 1

fInteger :: String -> ETerm
fInteger n = mkTuple [ mkAtomTerm "integer", ln, mkIntStr n ]

fIntegerI :: Int -> ETerm
fIntegerI n = mkTuple [ mkAtomTerm "integer", ln, mkIntI n ]

fFloat :: String -> ETerm
fFloat n = mkTuple [ mkAtomTerm "float", ln, mkFloatStr n ]

fAtom :: String -> ETerm
fAtom a = mkTuple [ mkAtomTerm "atom", ln, mkAtomTerm a ]

fVar :: String -> ETerm
fVar v = mkTuple [ mkAtomTerm "var", ln, mkAtomTerm v ]

-- a Rian `String` literal → the BEAM binary of its UTF-8 bytes: `{bin, 1, [{bin_element, 1,
-- {string, 1, Bytes}, default, default}]}` (a `<<"…">>` literal). Mirrors `str_form`.
fStr :: String -> ETerm
fStr s =
  mkTuple
    [ mkAtomTerm "bin"
    , ln
    , mkList
        [ mkTuple
            [ mkAtomTerm "bin_element"
            , ln
            , mkTuple [ mkAtomTerm "string", ln, strBytes s ]
            , mkAtomTerm "default"
            , mkAtomTerm "default"
            ]
        ]
    ]

-- a `{cons, 1, H, T}` chain over `elems`, ending in `T` (a cons tail) or `{nil, 1}` (a closed list).
-- Shared by list expressions (`f = exprForm`) and patterns (`f = patForm`).
consForm :: forall a. (a -> ETerm) -> Array a -> Maybe a -> ETerm
consForm f elems tail = foldr (\e acc -> mkTuple [ mkAtomTerm "cons", ln, f e, acc ]) base elems
  where
  base = case tail of
    Nothing -> mkTuple [ mkAtomTerm "nil", ln ]
    Just t -> f t

-- a `{tuple, 1, […]}` over the elements (`f` = exprForm / patForm).
tupleForm :: forall a. (a -> ETerm) -> Array a -> ETerm
tupleForm f xs = mkTuple [ mkAtomTerm "tuple", ln, mkList (map f xs) ]

-- a sum constructor with `tag` (already snake-cased) over already-formed args: a nullary ctor is
-- its bare atom `{atom, 1, tag}`; an arg-carrying one is a tagged tuple `{tag, A, …}`. Mirrors the
-- reference's symmetric ctor construction / `PCtor` pattern.
ctorForm :: String -> Array ETerm -> ETerm
ctorForm tag args = case args of
  [] -> fAtom tag
  _ -> mkTuple [ mkAtomTerm "tuple", ln, mkList ([ fAtom tag ] <> args) ]

-- ── maps / structs (inc 4) ──
-- a `{map, 1, […]}` over already-formed field nodes (assoc for expressions, exact for patterns).
mapForm :: Array ETerm -> ETerm
mapForm fields = mkTuple [ mkAtomTerm "map", ln, mkList fields ]

mapFieldAssoc :: ETerm -> ETerm -> ETerm
mapFieldAssoc k v = mkTuple [ mkAtomTerm "map_field_assoc", ln, k, v ]

mapFieldExact :: ETerm -> ETerm -> ETerm
mapFieldExact k v = mkTuple [ mkAtomTerm "map_field_exact", ln, k, v ]

-- a struct field `f: v` (construction) → `f => v`; `f: p` (pattern) → `f := p`. The key is the
-- field-name atom.
structFieldAssoc :: Tuple String CExpr -> ETerm
structFieldAssoc (Tuple f v) = mapFieldAssoc (fAtom f) (exprForm v)

-- a labeled call argument `f: v` → the struct map field `f => v` (a labeled `Name(f: v, …)` call
-- is struct construction, mirroring the reference's `ECall{args: [ELabel | _]}`).
labelAssoc :: CExpr -> ETerm
labelAssoc (ELabel f v) = mapFieldAssoc (fAtom f) (exprForm v)
labelAssoc _ = unsafeCrashWith "abstract-forms: a non-label in a labeled call"

structFieldPat :: Tuple String CPat -> ETerm
structFieldPat (Tuple f p) = mapFieldExact (fAtom f) (patForm p)

-- a map-literal pair → `k => v` (an atom key, or a computed `{:key, e}` key).
mapPairAssoc :: CMapPair -> ETerm
mapPairAssoc (CMAtom k v) = mapFieldAssoc (fAtom k) (exprForm v)
mapPairAssoc (CMKey k v) = mapFieldAssoc (exprForm k) (exprForm v)

-- a map-pattern pair → `k := p` (a map pattern always matches exactly on the listed keys).
mapPatPairExact :: CMapPatPair -> ETerm
mapPatPairExact (CMPAtom k p) = mapFieldExact (fAtom k) (patForm p)
mapPatPairExact (CMPKey k p) = mapFieldExact (exprForm k) (patForm p)

-- a remote call `mod:fun(args)` → `{call, 1, {remote, 1, {atom,1,mod}, {atom,1,fun}}, [args]}`.
remoteCall :: String -> String -> Array ETerm -> ETerm
remoteCall mod fun args =
  mkTuple [ mkAtomTerm "call", ln, mkTuple [ mkAtomTerm "remote", ln, fAtom mod, fAtom fun ], mkList args ]

-- a binary `<<…>>` over already-formed segments, and a whole-binary segment `X/binary` (for `<>`).
fBin :: Array ETerm -> ETerm
fBin segs = mkTuple [ mkAtomTerm "bin", ln, mkList segs ]

binSeg :: ETerm -> ETerm
binSeg form = mkTuple [ mkAtomTerm "bin_element", ln, form, mkAtomTerm "default", mkList [ mkAtomTerm "binary" ] ]

-- ── 64-bit overflow projection (inc 6) ──
data OvfKind = Wrapping | Saturating | Checked

-- the true `a + b` (bignum) computed once via `(fun(OvfSum) -> project(OvfSum) end)(a + b)`.
i64Overflow :: OvfKind -> CExpr -> CExpr -> ETerm
i64Overflow kind a b =
  let
    sum = binOp "+" (exprForm a) (exprForm b)
    sv = fVar "OvfSum"
    clause = mkTuple [ mkAtomTerm "clause", ln, mkList [ sv ], noGuard, mkList [ i64Project kind sv ] ]
    funE = mkTuple [ mkAtomTerm "fun", ln, mkTuple [ mkAtomTerm "clauses", mkList [ clause ] ] ]
  in
    mkTuple [ mkAtomTerm "call", ln, funE, mkList [ sum ] ]

-- project the (bignum) sum onto signed 64-bit per kind. Mirrors `i64_project`.
i64Project :: OvfKind -> ETerm -> ETerm
i64Project Wrapping sv =
  let
    low = binOp "band" sv (fInteger "18446744073709551615")
  in
    mkTuple
      [ mkAtomTerm "case"
      , ln
      , binOp ">=" low (fInteger "9223372036854775808")
      , mkList
          [ fClause [ fAtom "true" ] noGuard [ binOp "-" low (fInteger "18446744073709551616") ]
          , fClause [ fAtom "false" ] noGuard [ low ]
          ]
      ]
i64Project Saturating sv =
  remoteCall "erlang" "max" [ remoteCall "erlang" "min" [ sv, fInteger "9223372036854775807" ], fInteger "-9223372036854775808" ]
i64Project Checked sv =
  let
    inRange = binOp "andalso" (binOp ">=" sv (fInteger "-9223372036854775808")) (binOp "=<" sv (fInteger "9223372036854775807"))
  in
    mkTuple
      [ mkAtomTerm "case"
      , ln
      , inRange
      , mkList
          [ fClause [ fAtom "true" ] noGuard [ mkTuple [ mkAtomTerm "tuple", ln, mkList [ fAtom "some", sv ] ] ]
          , fClause [ fAtom "false" ] noGuard [ fAtom "none" ]
          ]
      ]

-- a binary `{op, 1, Op, L, R}` over the Erlang operator atom `op`.
binOp :: String -> ETerm -> ETerm -> ETerm
binOp op l r = mkTuple [ mkAtomTerm "op", ln, mkAtomTerm op, l, r ]

fCall :: ETerm -> Array ETerm -> ETerm
fCall target args = mkTuple [ mkAtomTerm "call", ln, target, mkList args ]

fFunction :: String -> Int -> Array ETerm -> ETerm
fFunction name arity clauses =
  mkTuple [ mkAtomTerm "function", ln, mkAtomTerm name, mkIntI arity, mkList clauses ]

fClause :: Array ETerm -> ETerm -> Array ETerm -> ETerm
fClause pats guard body = mkTuple [ mkAtomTerm "clause", ln, mkList pats, guard, mkList body ]

-- the empty Erlang guard sequence (`[]` — an unguarded clause).
noGuard :: ETerm
noGuard = mkList []

attrModule :: String -> ETerm
attrModule m = mkTuple [ mkAtomTerm "attribute", ln, mkAtomTerm "module", mkAtomTerm m ]

attrExport :: Array ETerm -> ETerm
attrExport es = mkTuple [ mkAtomTerm "attribute", ln, mkAtomTerm "export", mkList es ]

-- a `{Name, Arity}` raw tuple (an export entry).
nameArity :: String -> Int -> ETerm
nameArity n a = mkTuple [ mkAtomTerm n, mkIntI a ]

-- ── leaf helpers ─────────────────────────────────────────────────────────────
-- a Rian numeric string → an integer or float abstract node (a `.`/`e` ⇒ float; `_` stripped).
numForm :: String -> ETerm
numForm n0 =
  let
    n = Str.replaceAll (Str.Pattern "_") (Str.Replacement "") n0
  in
    if Str.contains (Str.Pattern ".") n || Str.contains (Str.Pattern "e") n || Str.contains (Str.Pattern "E") n then fFloat n
    else fInteger n

-- a Rian operator → its Erlang name (the abstract `op` atom). Mirrors `erl_op`.
erlOp :: String -> String
erlOp "==" = "=="
erlOp "!=" = "/="
erlOp "<=" = "=<"
erlOp ">=" = ">="
erlOp "<" = "<"
erlOp ">" = ">"
erlOp "and" = "andalso"
erlOp "or" = "orelse"
erlOp "+" = "+"
erlOp "-" = "-"
erlOp "*" = "*"
erlOp "/" = "/"
erlOp "div" = "div"
erlOp "rem" = "rem"
erlOp op = unsafeCrashWith ("abstract-forms: operator `" <> op <> "`")

-- a Rian variable name → its Erlang variable atom: a `_`-prefixed name is kept verbatim, else the
-- first letter is upper-cased (Erlang variables are capitalized). Mirrors `var_atom`.
varAtom :: String -> String
varAtom x = case Str.stripPrefix (Str.Pattern "_") x of
  Just _ -> x
  Nothing -> toUpper (Str.take 1 x) <> Str.drop 1 x

-- the first character is an upper-case ASCII letter (a constructor / nominal head).
startsUpper :: String -> Boolean
startsUpper x = case CU.charAt 0 x of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

-- a clause's body `Body` → its `CExpr` (re-parse + normalize, like the other emitters).
bodyExprOf :: Maybe Body -> CExpr
bodyExprOf (Just b) = fromExpr (normalize (bodySurface b))
bodyExprOf Nothing = unsafeCrashWith "abstract-forms: clause has no body"
