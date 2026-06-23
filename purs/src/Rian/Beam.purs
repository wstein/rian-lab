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
-- | `none`); `i64Overflow`/`i64Project`. Inc 7: **`const` declarations + references** — a
-- | `const NAME := value` → a 0-arity accessor `name() -> value`, and a reference resolves at the
-- | surface level (`SId NAME` → `SConstRef`, `resolveConstsS` over `Rian.Macro.mapNode`, threaded as
-- | `cnames`) so it lowers to a call to the accessor. Inc 8: **value-union type-pattern
-- | discrimination** (ADR-0083) — a `case`-arm `name Type` (`PTyped`) is desugared to a `PVar name`
-- | bound under a runtime type-test guard, reusing the protocol-dispatch discriminator: a primitive
-- | BIF (`is_boolean`/`is_binary`/`is_integer`/`is_float`), a sum's tag-membership
-- | (`is_tuple(v) and element(1, v) == :tag` / `v == :tag`), or a struct's `__struct__` test. A
-- | `desugarTyped` pre-pass over the body Core (threaded the sum/struct registry like `cnames`)
-- | rewrites the arms, so `expr_form` stays registry-free. Inc 9: **`@external` host-body splice**
-- | (ADR-0068) + **module-qualified calls** — an `@external(:ex, spec)` function gets a synthetic
-- | clause whose head binds the params and whose body is the rendered host expression
-- | (`Rian.External.render`: a raw string verbatim, a `Mod.fun`/`:erlang.fun` reference → a
-- | positional call), reusing the normal Core → forms FFI lowering (`beamFunc`); an `@external` with
-- | no `:ex` body is honestly off `:ex` and emits nothing. The new remote-call clauses lower a
-- | `Mod.fun(args)` / `:erlang.fun(args)` to an Erlang remote call (`moduleAtom`: a PascalCase head →
-- | the Elixir module `Elixir.Mod`, a lowercase/atom head → an Erlang module verbatim). Inc 10:
-- | **cross-module / aux-mod loading** — `runMain` now compiles the top-level functions into the main
-- | `rian_main` module *and* each sibling `mod` into its own `Elixir.<Name>` module, loading all
-- | before running `rian_main:main()` (`runModulesImpl`), so a cross-module call resolves. This
-- | lands **`${float}`**: `Rian.Assemble.runProgramTail` injects a `Show` module for a `Float64`
-- | hole, which now compiles + loads as an aux mod and runs end-to-end (the String⇄charlist prims
-- | `__prim_str_chars`/`_from_chars`/`_to_atom` lower to the pure-Erlang `unicode:*`/`erlang:*` BIFs
-- | rather than the reference's `Elixir.String.*` — an equivalent result with no Elixir runtime
-- | needed, the one deliberate emit divergence). **Deferred (later increments):** specs/`type` attrs,
-- | and the **`List`/`Dict`/`Str`/`Int` prelude linkage** (the `Rian.Prelude.<Name>` redirect in
-- | `moduleAtom` + bundling/compiling the prelude `.rian` sources). An unported node raises a clear
-- | crash.
module Rian.Beam
  ( runMain
  ) where

import Prelude

import Data.Array (all, elem, filter, find, head, length, null, uncons)
import Data.Foldable (foldl, foldr)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), Replacement(..), contains, drop, replaceAll, stripPrefix, take) as Str
import Data.String.CodeUnits (charAt, toCharArray) as CU
import Data.String.Common (toUpper)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CMapPatPair(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.External (render) as External
import Rian.IR (Body, Clause, Const, Func, Prog, bodySurface)
import Rian.IR as IR
import Rian.Macro (mapNode)
import Rian.PatternLower (toSnake)
import Rian.Pratt (Pat(..), Surface(..), parse) as P
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
-- compile each module's forms → load all → run `Main:main()` → the `~p`-rendered result (or a
-- diagnostic). The first arg is the array of module-forms (aux mods + the main module).
foreign import runModulesImpl :: Array ETerm -> String -> String

-- | Compile `src` to BEAM abstract forms, load the module, run its `main/0`, and return the
-- | stringified result (or a `Rian.Check:`/`compile_error:` diagnostic). The execution-parity entry.
-- @rian_sig pub def runMain(src val String) String
runMain :: String -> String
runMain src =
  case checkProgram prog of
    Just msg -> "Rian.Check: " <> msg
    Nothing -> runModulesImpl (auxForms <> [ mainForms ]) "rian_main"
  where
  prog = runProgramTail (assemble (parseToProg src))
  -- the main module = the top-level funcs (or the single pulled-up `mod`), named `rian_main`.
  mainForms = moduleForms "rian_main" (funcsOf prog) (constsOf prog) (registryFrom (typesOf prog) (structsOf prog))
  -- each sibling `mod` (e.g. the injected `Show` for `${float}`, or a user multi-`mod` program) →
  -- its own `Elixir.<Name>` module, loaded first so a cross-module call resolves. Skipped when there
  -- are no top-level funcs (then `funcsOf` already pulled the single `mod` up as main). Mirrors
  -- `load_aux_mods`.
  auxForms = case prog.funcs of
    [] -> []
    _ -> map auxModuleForms prog.mods
  auxModuleForms m = moduleForms ("Elixir." <> m.name) m.funcs m.consts (registryFrom m.types m.structs)

-- the functions to compile: a single `mod`'s, else the top-level ones (mirrors `funcs_of`).
funcsOf :: Prog -> Array Func
funcsOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.funcs
    _ -> []
  fs -> fs

-- an `@external` function (ADR-0068): on the BEAM the `:ex` spec is a Rian-surface host expression,
-- so splice it as the body — a synthetic clause whose head binds the params (as vars) — and reuse
-- the normal Core → abstract-forms FFI lowering (the remote-call `expr_form` clauses). An
-- `@external` with no `:ex` body is honestly off `:ex` and emits nothing. Mirrors `beam_func`.
beamFunc :: Func -> Array Func
beamFunc f
  | not (null f.externals) = case lookupAssoc "ex" f.externals of
      Nothing -> []
      Just spec ->
        let
          clause = { pats: map (\p -> P.PVar p.name) f.params, body: Just (IR.Raw (External.render spec f.params)), guard: Nothing }
        in
          [ f { clauses = [ clause ], externals = [] } ]
  | otherwise = [ f ]

-- ── module assembly ──────────────────────────────────────────────────────────
-- build one module's forms from its own functions / consts / type-registry (so the main module and
-- each aux `mod` share one builder, mirroring the reference `beam_for`'s per-scope arguments).
moduleForms :: String -> Array Func -> Array Const -> Registry -> ETerm
moduleForms modName funcs0 consts reg =
  let
    funcs = funcs0 >>= beamFunc
    cnames = map _.name consts
    exports =
      map (\f -> nameArity f.name (funcArity f)) funcs
        <> map (\c -> nameArity (toSnake c.name) 0) consts
  in
    mkList
      ([ attrModule modName, attrExport exports ]
        <> map (functionForm cnames reg) funcs
        <> map (constForm cnames reg) consts)

-- a `const NAME := value` (ADR-0033) → its 0-arity accessor `name() -> value` (snake-cased name,
-- so `EConstRef` resolves to the same target). The value is a source expression string.
constForm :: Array String -> Registry -> Const -> ETerm
constForm cnames reg c = fFunction (toSnake c.name) 0 [ fClause [] noGuard (bodyForms (desugarTyped reg (parseResolved cnames (P.parse c.value)))) ]

-- parse a body/value/guard surface, rewriting a reference to a declared `const` (`SId NAME` with
-- NAME in the set) into a `SConstRef` so it lowers to the accessor call (mirrors `resolve_consts`),
-- then normalize + lower to Core.
parseResolved :: Array String -> P.Surface -> CExpr
parseResolved cnames s = fromExpr (normalize (resolveConstsS cnames s))

resolveConstsS :: Array String -> P.Surface -> P.Surface
resolveConstsS cnames = go
  where
  go (P.SId name)
    | elem name cnames = P.SConstRef name
  go node = mapNode go node

-- the consts to compile: a single `mod`'s (a top-level `const` is module-scoped, ADR-0033, so the
-- whole-program IR carries consts only on `mod`s — none for a flat file). Mirrors `consts_of`.
constsOf :: Prog -> Array Const
constsOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.consts
    _ -> []
  _ -> []

funcArity :: Func -> Int
funcArity f = case head f.clauses of
  Just c -> length c.pats
  Nothing -> length f.params

-- a function → `{function, 1, Name, Arity, [Clause]}`.
functionForm :: Array String -> Registry -> Func -> ETerm
functionForm cnames reg f =
  fFunction f.name (funcArity f) (map (clauseForm cnames reg) f.clauses)

-- a function clause → `{clause, 1, [PatForm], Guard, [BodyForm]}`. A multi-clause `def` is one
-- Erlang function with one clause per group member (Erlang dispatches natively); a `when` guard
-- lowers to the Erlang guard sequence `[[GuardExpr]]`. `cnames` resolves const references in the body.
clauseForm :: Array String -> Registry -> Clause -> ETerm
clauseForm cnames reg c =
  fClause (map (patForm <<< fromPat) c.pats) (clauseGuardForm cnames c.guard) (bodyForms (desugarTyped reg (bodyExprOf cnames c.body)))

-- a function clause's `when` guard (a source string) → the Erlang guard sequence; `Nothing` → `[]`.
clauseGuardForm :: Array String -> Maybe String -> ETerm
clauseGuardForm _ Nothing = noGuard
clauseGuardForm cnames (Just g) = mkList [ mkList [ exprForm (parseResolved cnames (P.parse g)) ] ]

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
-- a `const NAME` reference → a call to its 0-arity accessor `name()` (ADR-0033).
exprForm (EConstRef name) = fCall (fAtom (toSnake name)) []
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
-- a value-union struct discriminator's map-value read (inc 8) → the guard-safe BIF `erlang:map_get/2`.
exprForm (ECall (EId "__beam_map_get") [ k, m ]) = remoteCall "erlang" "map_get" [ exprForm k, exprForm m ]
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
-- the String ⇄ charlist/atom conversions: the purerl backend lowers these to the **pure-Erlang**
-- BIFs (not the Elixir-stdlib calls the Elixir reference emits — `Elixir.String.to_charlist` etc.,
-- which themselves delegate to exactly these), so the emitted `.beam` runs with no Elixir runtime
-- loaded. The result is identical, so execution parity against the reference holds; this is the one
-- deliberate emit divergence, and it is what makes the injected `Show` module (and thus `${float}`)
-- run in the plain-Erlang harness.
exprForm (ECall (EId "__prim_str_chars") [ s ]) = remoteCall "unicode" "characters_to_list" [ exprForm s, fAtom "utf8" ]
exprForm (ECall (EId "__prim_str_from_chars") [ cs ]) = remoteCall "unicode" "characters_to_binary" [ exprForm cs, fAtom "utf8" ]
exprForm (ECall (EId "__prim_str_to_atom") [ s ]) = remoteCall "erlang" "binary_to_atom" [ exprForm s, fAtom "utf8" ]
-- explicit 64-bit overflow ops (ADR-0035 §3): BEAM ints are bignums, so compute the true sum once
-- (an immediately-applied `fun`) then project onto signed-64: wrap / saturate / check.
exprForm (ECall (EId "__prim_wrapping_add") [ a, b ]) = i64Overflow Wrapping a b
exprForm (ECall (EId "__prim_saturating_add") [ a, b ]) = i64Overflow Saturating a b
exprForm (ECall (EId "__prim_checked_add") [ a, b ]) = i64Overflow Checked a b
-- a module-qualified call `Mod.fun(args)` / `:erlang.fun(args)` (inc 9, `@external` host bodies) →
-- an Erlang remote call. A PascalCase head is an Elixir module (`String` → `'Elixir.String'`); a
-- lowercase/atom head is an Erlang module verbatim (`:erlang` → `erlang`).
exprForm (ECall (EDot (EId m) fun) args) = remoteCall (moduleAtom m fun) fun (map exprForm args)
exprForm (ECall (EDot (EAtom m) fun) args) = remoteCall m fun (map exprForm args)
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

-- ── value-union type-pattern discrimination (inc 8, ADR-0083) ─────────────────
-- The sum/struct registry threaded (like `cnames`) so a case-arm type-pattern `n Type` can build
-- its runtime discriminator: `sums` = each value-`type` name → its variants; `structs` = the names.
type Registry = { sums :: Array (Tuple String (Array IR.Variant)), structs :: Array String }

-- the registry for a scope's own type/struct declarations.
registryFrom :: Array IR.Type -> Array IR.Struct -> Registry
registryFrom types structs =
  { sums: map (\t -> Tuple t.name t.variants) types, structs: map _.name structs }

typesOf :: Prog -> Array IR.Type
typesOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.types
    _ -> prog.types
  _ -> prog.types

structsOf :: Prog -> Array IR.Struct
structsOf prog = case prog.funcs of
  [] -> case prog.mods of
    [ m ] -> m.structs
    _ -> prog.structs
  _ -> prog.structs

-- Rewrite every case-arm (and `with`-else-arm) type-pattern `n Type` to a plain `PVar n` bound under
-- a runtime type-test guard, reusing the protocol-dispatch discriminator. Mirrors the reference
-- `Rian.Beam.desugar_typed`. The walk recurses through every sub-expression so a NESTED `case`'s
-- arms are desugared too; `expr_form` itself stays registry-free (it only ever sees `PVar` + a guard).
desugarTyped :: Registry -> CExpr -> CExpr
desugarTyped reg = go
  where
  go (ECase scrut arms) = ECase (go scrut) (map goArm arms)
  go (EWith clauses body els) =
    EWith (map (\c -> c { expr = go c.expr }) clauses) (go body) (map goArm els)
  go (EUnary op x) = EUnary op (go x)
  go (EBin op l r) = EBin op (go l) (go r)
  go (ECall f args) = ECall (go f) (map go args)
  go (EDot h n) = EDot (go h) n
  go (EIf c t e) = EIf (go c) (go t) (go e)
  go (EBlock stmts) = EBlock (map goStmt stmts)
  go (EList es tail) = EList (map go es) (map go tail)
  go (EMap ps) = EMap (map goPair ps)
  go (EMapUpdate b ps) = EMapUpdate (go b) (map goPair ps)
  go (ETuple es) = ETuple (map go es)
  go (ELambda ps b) = ELambda ps (go b)
  go (ECapture b) = ECapture (go b)
  go (ECaptureNamed p a) = ECaptureNamed (go p) a
  go (ELabel n e) = ELabel n (go e)
  go (EStruct n fs) = EStruct n (map (\(Tuple k v) -> Tuple k (go v)) fs)
  go (EVariant n fs) = EVariant n (map (\(Tuple k v) -> Tuple k (go v)) fs)
  go e = e

  goStmt (CBind n e) = CBind n (go e)
  goStmt (CTypedBind n t e) = CTypedBind n t (go e)
  goStmt (CExprStmt e) = CExprStmt (go e)

  goPair (CMAtom k v) = CMAtom k (go v)
  goPair (CMKey k v) = CMKey (go k) (go v)

  -- a type-pattern arm `n Type [when g]` → `PVar n` guarded by `is_<Type>(n) [and g]`.
  goArm arm =
    let
      arm2 = arm { body = go arm.body, guard = map go arm.guard }
    in
      case arm2.pat of
        PTyped name tname _ ->
          let
            test = typeTest reg tname name
            g = case arm2.guard of
              Nothing -> test
              Just existing -> EBin "and" test existing
          in
            arm2 { pat = PVar name, guard = Just g }
        _ -> arm2

-- the runtime type-test (a Core guard over `var`) for a value-union member `tname`: a primitive BIF
-- (`is_boolean`/`is_binary`/`is_integer`/`is_float`), or — reusing the dispatcher discriminator — a
-- sum's tag-membership / a struct's `__struct__` test. Mirrors `Rian.Beam.type_test`.
typeTest :: Registry -> String -> String -> CExpr
typeTest reg tname var
  | tname == "Bool" = call1 "is_boolean" (EId var)
  | tname == "String" = call1 "is_binary" (EId var)
  | tname == "Char" = call1 "is_integer" (EId var)
  | isIntType tname = call1 "is_integer" (EId var)
  | isFloatType tname = call1 "is_float" (EId var)
  | otherwise = case lookupAssoc tname reg.sums of
      Just variants -> sumGuard variants var
      Nothing ->
        if elem tname reg.structs then structGuard tname var
        else unsafeCrashWith ("abstract-forms: type-pattern over `" <> tname <> "` (no discriminator)")

-- a sum value's discriminator (mirrors `sum_guard_str`): a tagged-tuple variant tests
-- `is_tuple(var) and element(1, var) == :tag`; a nullary variant tests `var == :tag`.
sumGuard :: Array IR.Variant -> String -> CExpr
sumGuard variants var =
  orParts (tupledPart <> nullaryPart)
  where
  tupled = filter (\v -> not (null v.fields)) variants
  nullary = filter (\v -> null v.fields) variants
  tupledPart =
    if null tupled then []
    else
      [ EBin "and" (call1 "is_tuple" (EId var))
          (orParts (map (\v -> EBin "==" (elem1 var) (EAtom (toSnake v.ctor))) tupled))
      ]
  nullaryPart =
    if null nullary then []
    else [ orParts (map (\v -> EBin "==" (EId var) (EAtom (toSnake v.ctor))) nullary) ]
  elem1 w = ECall (EId "element") [ ENum "1", EId w ]

-- a struct value's discriminator (mirrors `struct_guard_str`), guard-safe: `is_map` + the
-- `__struct__` key + `erlang:map_get(:__struct__, var) == :tag` (`__beam_map_get` → the guard BIF).
structGuard :: String -> String -> CExpr
structGuard tname var =
  EBin "and" (call1 "is_map" (EId var))
    ( EBin "and" (ECall (EId "is_map_key") [ EAtom "__struct__", EId var ])
        (EBin "==" (ECall (EId "__beam_map_get") [ EAtom "__struct__", EId var ]) (EAtom (toSnake tname)))
    )

call1 :: String -> CExpr -> CExpr
call1 f x = ECall (EId f) [ x ]

-- `or` over a non-empty list of guard expressions (left-associated, as the reference's join).
orParts :: Array CExpr -> CExpr
orParts xs = case uncons xs of
  Just { head: h, tail: t } -> foldl (\acc e -> EBin "or" acc e) h t
  Nothing -> EId "false"

lookupAssoc :: forall a. String -> Array (Tuple String a) -> Maybe a
lookupAssoc k xs = case find (\(Tuple n _) -> n == k) xs of
  Just (Tuple _ v) -> Just v
  Nothing -> Nothing

-- `^U?Int\d*$` / `^Float\d*$` — the integer / float width families (each tests `is_integer`/`is_float`).
isIntType :: String -> Boolean
isIntType s =
  case Str.stripPrefix (Str.Pattern "Int") (fromMaybe s (Str.stripPrefix (Str.Pattern "U") s)) of
    Just rest -> allDigits rest
    Nothing -> false

isFloatType :: String -> Boolean
isFloatType s = case Str.stripPrefix (Str.Pattern "Float") s of
  Just rest -> allDigits rest
  Nothing -> false

allDigits :: String -> Boolean
allDigits s = all (\c -> c >= '0' && c <= '9') (CU.toCharArray s)

-- ── patterns → abstract forms (inc 1: wildcards / vars / literals / atoms) ──
patForm :: CPat -> ETerm
patForm PWild = fVar "_"
patForm (PVar x) = fVar (varAtom x)
patForm (PLit (LInt n)) = fIntegerI n
patForm (PLit (LStr s)) = fStr s
-- a char-literal pattern `'-'` → its integer codepoint (a `Char` is an integer, as `EChar`).
patForm (PChar cp) = fIntegerI cp
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

-- the Erlang module atom for an `EId`-headed `Mod.fun` call: a PascalCase head is an Elixir module
-- (`String` → `Elixir.String`), a lowercase one is an Erlang module verbatim. Mirrors `module_atom`
-- (the portable-prelude redirect — `List`/`Dict`/`Str`/`Int` → the linked `Rian.Prelude.<Name>` — is
-- the cross-module/prelude increment; until then a prelude call lowers to its bare module name).
moduleAtom :: String -> String -> String
moduleAtom m _fun = if startsUpper m then "Elixir." <> m else m

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

-- a clause's body `Body` → its `CExpr` (re-parse + normalize + const-resolve, like the reference).
bodyExprOf :: Array String -> Maybe Body -> CExpr
bodyExprOf cnames (Just b) = parseResolved cnames (bodySurface b)
bodyExprOf _ Nothing = unsafeCrashWith "abstract-forms: clause has no body"
