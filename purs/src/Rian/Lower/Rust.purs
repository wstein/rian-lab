-- | Rust source emitter (ADR-0049 / ADR-0061) — the PureScript port of `Rian.Lower`'s
-- | `to_rust` half (lib/rian/lower.ex), ADR-0084 Phase 5. A direct Rust source emitter on
-- | the typed Core IR (ADR-0050), consuming `Rian.Core.fromExpr`/`fromPat`. **Rust is the
-- | genuine shipping text target of `Rian.Lower`** (the Elixir-text half is not ported — see
-- | `Rian.Roundtrip`'s subsumption note; `Rian.Beam` is the BEAM path).
-- |
-- | A Rian function lowers to `fn name(params) -> ret { match scrut { pat => arm, … } }`,
-- | mirroring the clause dispatcher (clauses-guards §5.2): one param matches it directly, N
-- | match the argument tuple. A sum `type` becomes a `#[derive(Clone, Debug, PartialEq)] enum`
-- | (re-emitted per function unit, as `Rian.Decl.compile` does); construction and patterns are
-- | `Enum::Variant(…)` / `Enum::Variant { label: … }` (named where the variant declared
-- | labels — the `meta` carries them). Parameter types come from the capability lowering
-- | (`Rian.Capability.rustParam`); the return from `Rian.Capability.owned`.
-- |
-- | **Staged port.** Increments so far:
-- |   1. single-clause portable core — primitive `val` params, the precedence-aware operator
-- |      algebra, `div`/`rem`/float-`/`, unary `-`/`not`, `if`, local calls (recursion);
-- |   2a. **total** multi-clause functions (a var/catch-all clause or full variant coverage →
-- |      Rust-exhaustive, no shim), sum `enum` decls + construction + `Enum::Variant` patterns,
-- |      and `case` (→ a nested `match`);
-- |   3–6. strings/chars/symbols, the partial/total `match` shim (`_ => panic!`/`unreachable!()`),
-- |      structs, and lists (`vec![…]` / `&[T]` slices / cons rebuild);
-- |   7a–b. generics — bare-tvar pass-through + bounded `forall T: Eq` and protocol traits/UFCS;
-- |   7c. the whole-program `rustProgram` assembly + protocol `impl` blocks;
-- |   7d. parametric-type monomorphization (`enum Pair<K, V>` + `pinst`) + owned-element clone;
-- |   7e. closures (`Fn` → `&impl Fn` / `Box<dyn Fn>`);
-- |   7f. deeper capability borrows — a cons-head `&T` rebound `clone()`, an `iso Vec` matched
-- |      via `.as_slice()` with its tail rebound `to_vec()`, and a `Vec` return coercing a
-- |      borrowed `&[T]` slice leaf to owned (`coerceOwnedVecAst`).
-- |   mop-up. `Map(K,V)` HashMap prims (`__prim_map_new`/`get`/`has`/`put` → `HashMap::new()` /
-- |      `.get(k).cloned().unwrap()` / `.contains_key` / a clone-and-insert functional update),
-- |      captures (`&(&1*2)` → `|a1| …`, `&fn/arity` → `|a0,…| fn(a0,…)`, `&N` → `aN`, arity from
-- |      `Core.capArity`), and `with` → a nested `match` chain (`withChainRs`). A map *literal*
-- |      (`%{…}`) / update stays BEAM-only (a clean crash). (Captures-in-return + `with` bodies
-- |      mirror the reference's output, which has known boxing/borrow gaps — parity, not rustc-valid.)
-- | An unported node raises a clear "stage" crash, kept out of the `rust`/`rustprog` parity
-- | corpus (oracle = `Rian.Decl.compile`'s `:rust` / `Rian.Lower.rust_program`).
module Rian.Lower.Rust
  ( compile
  , rustProgram
  , lowerRustProg
  ) where

import Prelude

import Data.Array (all, any, concat, concatMap, drop, elem, filter, find, foldl, head, index, last, length, mapMaybe, mapWithIndex, nub, null, range, reverse, snoc, sort, uncons, zipWith)
import Data.Array (groupBy) as Array
import Data.Array.NonEmpty (toArray) as NEA
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (foldMap)
import Data.Int (hexadecimal, toStringAs) as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing, maybe)
import Data.String (Pattern(..), Replacement(..), replaceAll, split, stripPrefix, stripSuffix)
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (charAt, fromCharArray, toCharArray) as CU
import Data.String.Common (joinWith, toLower, toUpper, trim)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Capability (copy, owned, rustParam) as Cap
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CPat(..), CStmt(..), CWithClause, LitVal(..), capArity, fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.Exhaustiveness (analyze, programEnv)
import Rian.External (render) as Ext
import Rian.IR (Cap(..), Clause, ExtSpec(..), Func, ImplDecl, ImplMethod, Method, Param, Prog, Protocol, Range, Struct, Type, Variant, bodySurface)
import Rian.Macro (mapNode)
import Rian.Opaque (erase)
import Rian.PatternLower (Env, lowerMany)
import Rian.Pratt (Pat, Surface(..), parseBody) as P
import Rian.Prelude (withPrelude)
import Rian.Prim (normalize)
import Rian.TypeStr (splitTopCommas) as TS

-- ctor name → its enum, whether it has named fields, and the per-field labels.
type VInfo = { enum :: String, named :: Boolean, labels :: Array (Maybe String) }
type Meta = Array (Tuple String VInfo)

-- the per-clause emit context: the variant registry `vi`, the clause's `borrowed` vars (a
-- `&T`/`&[T]` binding, cloned to owned in a construction position — ADR-0055/0061), `slices`
-- (the `&[T]` slice binders — a `val Vec` param or a cons-tail `@..` binder — that a `Vec`
-- return must `.to_vec()` to owned, ADR-0047 Gap E), the `Fn`-typed param names (a call to
-- one is a closure call: args clone), and `fnBox` — set when the function returns a closure, so
-- a value-position lambda is `Box::new(move …)` (ADR-0061).
type Ec =
  { vi :: Meta
  , bor :: Array String
  , slices :: Array String
  , fnParams :: Array String
  , fnBox :: Maybe { clone :: Boolean, rc :: Boolean }
  -- value unions (ADR-0083): the program's function signatures (name → params), so a call
  -- passing a member to a union param wraps it `RUnion_…::from(x)`; the union-typed locals in
  -- scope (var → `Union(…)` type), so a `case` over one lowers to a `match` on the synth enum;
  -- and the union case-arm binders, each holding an OWNED member (so a `&str` host arg borrows).
  , sigs :: Array (Tuple String (Array Param))
  , unions :: Array (Tuple String String)
  , ownedBinders :: Array String
  }

-- | Compile `src`'s functions to a single Rust module (a string). Mirrors the `:rust`
-- | half of `Rian.Decl.compile`: each non-dispatch function is lowered as its own unit (the
-- | program's `enum` defs, then the `fn`) and the units joined `\n\n` (a protocol dispatcher
-- | has no Rust shape — Rust uses traits — so it is dropped).
-- @rian_sig pub def compile(src val String) String
compile :: String -> String
compile src =
  let
    prog0 = runProgramTail (assemble (parseToProg src))
  in
    case checkProgram prog0 of
      Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
      Nothing ->
        let
          prog = erase prog0
          types = allTypes prog
          meta = buildMeta types
          env = programEnv types prog.structs prog.ranges
          -- the per-unit `rust` stream does NOT monomorphize (no parametric map, matching
          -- `Rian.Decl.compile`'s per-func `to_rust`); the whole-program `rustProgram` does.
          enums = joinWith "\n\n" (map (rustEnum []) types)
          structDefs = joinWith "\n\n" (map rustStruct prog.structs)
          methods = prog.protocols >>= \pr -> map _.name pr.methods
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
          funcUnits = map (\f -> rustUnit structDefs enums meta env methods f) funcs
          -- protocols → a `trait Rian<Name> { … }` unit, emitted last (as `Rian.Decl.compile` does).
          protoUnit = if null prog.protocols then "" else joinWith "\n\n" (map rustTrait prog.protocols)
        in
          joinWith "\n\n" (filter (_ /= "") (funcUnits <> [ protoUnit ]))

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> foldl (\acc m -> acc <> m.funcs) [] prog.mods

allTypes :: Prog -> Array Type
allTypes prog = prog.types <> foldl (\acc m -> acc <> m.types) [] prog.mods

-- the per-function unit: the program's `enum` defs (repeated per unit, as the reference does),
-- then this function. Empty parts (no types) drop out.
rustUnit :: String -> String -> Meta -> Env -> Array String -> Func -> String
rustUnit structDefs enums meta env methods f =
  joinWith "\n\n" (filter (_ /= "") [ structDefs, enums, rustFn [] meta env methods [] f ])

-- a `struct Name(f T, …)` → a `#[derive(Clone, Debug, PartialEq)] struct Name { f: T, … }`.
rustStruct :: Struct -> String
rustStruct s =
  "#[derive(Clone, Debug, PartialEq)]\nstruct " <> s.name <> " { "
    <> joinWith ", " (map (\f -> fromMaybe "" f.label <> ": " <> Cap.owned f.ty) s.fields)
    <> " }"

-- ── protocols → traits (ADR-0061 §2) ────────────────────────────────────────────

-- a `protocol P` → `trait RianP { fn m(&self, …) -> ret; }`. The first method param is the
-- receiver (`&self`); the rest keep their (Self-borrowed) signature. (Impls + associated types
-- are the later increment.)
rustTrait :: Protocol -> String
rustTrait pr =
  "trait Rian" <> pr.name <> " {\n" <> joinWith "\n" (map methodSig pr.methods) <> "\n}"
  where
  methodSig m =
    "    fn " <> m.name <> "(" <> traitParams m.params <> ") -> " <> rustRet (fromMaybe "" m.ret) <> ";"

traitParams :: String -> String
traitParams paramStr = case filter (_ /= "") (TS.splitTopCommas paramStr) of
  [] -> "&self"
  ps -> joinWith ", " ([ "&self" ] <> map sigParam (drop 1 ps))

sigParam :: String -> String
sigParam pstr = let Tuple nm ty = nameType pstr in nm <> ": " <> refType "Self" ty

-- a trait/impl-method param type → its borrowed Rust form. `Self` → `&<selfRepr>` (`&Self` in a
-- trait, `&bool` in an impl). A non-`Self` param is the later increment (needs the `val`
-- capability lowering, whose `Cap` ctor isn't exported).
refType :: String -> String -> String
refType selfRepr "Self" = "&" <> selfRepr
refType _ _ = unsafeCrashWith "rust: non-Self trait param (stage)"

-- split a `name Type` param into its name (or `_`) and type.
nameType :: String -> Tuple String String
nameType pstr = case filter (_ /= "") (split (Pattern " ") pstr) of
  [ ty ] -> Tuple "_" ty
  arr -> case uncons arr of
    Just { head: nm, tail: rest } -> Tuple nm (joinWith " " rest)
    Nothing -> Tuple "_" ""

-- rewrite a protocol-method call `m(recv, rest…)` to a receiver method `recv.m(rest…)` on the
-- surface (ADR-0061 §2), recursing; a non-method call passes through. Mirrors `rewrite_proto_calls`.
rewriteProtoCalls :: Array String -> P.Surface -> P.Surface
rewriteProtoCalls methods = walk
  where
  walk node = case node of
    P.SCall (P.SId m) args
      | elem m methods -> case uncons args of
          Just { head: recv, tail: rest } -> P.SCall (P.SDot (walk recv) m) (map walk rest)
          Nothing -> mapNode walk node
    _ -> mapNode walk node

-- | Assemble a whole program into **one** Rust module (ADR-0061): every `struct`/`enum`/
-- | `trait`/`impl` once, then every non-dispatch function. The whole-program counterpart of
-- | `compile` (which repeats type defs per unit) — the `rustprog` parity stream, oracle =
-- | `Rian.Lower.rust_program`.
-- @rian_sig pub def rustProgram(src val String) String
rustProgram :: String -> String
rustProgram src =
  case checkProgram prog0 of
    Just msg -> unsafeCrashWith ("Rian.Check: " <> msg)
    Nothing -> lowerRustProg prog0
  where
  prog0 = runProgramTail (assemble (parseToProg src))

-- | The post-gate half of `rustProgram` (parse + check done) — lower an already-checked program
-- | to one Rust module. Exposed so `Rian.Lower.All` parses + checks ONCE across all targets.
lowerRustProg :: Prog -> String
lowerRustProg prog0 =
        let
          prog = erase prog0
          types = allTypes prog
          meta = buildMeta types
          env = programEnv types prog.structs prog.ranges
          methods = prog.protocols >>= \pr -> map _.name pr.methods
          -- parametric types are monomorphized here (`enum Pair<K, V>`, `-> Pair<K, V>`).
          pm = parametricMap types
          structs = joinWith "\n\n" (map rustStruct prog.structs)
          enums = joinWith "\n\n" (map (rustEnum pm) types)
          traits = joinWith "\n\n" (map rustTrait prog.protocols)
          impls = joinWith "\n\n" (map (rustImpl meta methods prog.protocols) prog.implDecls)
          traitImpl = joinWith "\n\n" (filter (_ /= "") [ traits, impls ])
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
          -- synthesized value-union enums (ADR-0083) + the program signatures threaded for the
          -- call-site union `From`-wrap / borrow.
          unionEnums = synthUnionEnums prog
          sigs = funcSigs prog
          fns = joinWith "\n\n" (map (rustFn pm meta env methods sigs) funcs)
        in
          joinWith "\n\n" (filter (_ /= "") [ structs, enums, unionEnums, traitImpl, fns ])

-- an `impl P for T` → `impl RianP for <rust T> { fn m(&self, …) -> ret { let recv = self; body } }`
-- (ADR-0061 §2). The method's param/return types come from the protocol's declared signature.
rustImpl :: Meta -> Array String -> Array Protocol -> ImplDecl -> String
rustImpl meta methods protocols impl =
  let
    rustType = Cap.owned impl.ty
    copyRecv = Cap.copy impl.ty
    sigFor = case find (\pr -> pr.name == impl.proto) protocols of
      Just pr -> pr.methods
      Nothing -> []
    bodies = joinWith "\n" (map (rustImplMethod meta methods rustType copyRecv sigFor) impl.methods)
  in
    "impl Rian" <> impl.proto <> " for " <> rustType <> " {\n" <> bodies <> "\n}"

rustImplMethod :: Meta -> Array String -> String -> Boolean -> Array Method -> ImplMethod -> String
rustImplMethod meta methods rustType copyRecv sigFor m =
  let
    names = map trim (TS.splitTopCommas m.params)
    recv = fromMaybe "_" (head names)
    sig = case find (\sm -> sm.name == m.name) sigFor of
      Just s -> s
      Nothing -> { name: m.name, params: "", ret: Nothing }
    restSig = drop 1 (TS.splitTopCommas sig.params)
    params = joinWith ", " ([ "&self" ] <> zipWith (implParam rustType) (drop 1 names) restSig)
    retTy = replaceAll (Pattern "Self") (Replacement rustType) (fromMaybe "" sig.ret)
    otherSelf = any (\sp -> snd (nameType sp) == "Self") restSig
    recvRhs = if copyRecv && not otherSelf then "*self" else "self"
    bodySurf = P.parseBody (fromMaybe "" m.body)
    -- impl-method bodies don't yet need the borrowed-clone / closure context (corpus methods
    -- construct nothing and take no `Fn` params).
    body = coerceRet retTy (fst (emit { vi: meta, bor: [], slices: [], fnParams: [], fnBox: Nothing, sigs: [], unions: [], ownedBinders: [] } (fromExpr (rewriteProtoCalls methods (normalize bodySurf)))))
  in
    "    fn " <> m.name <> "(" <> params <> ") -> " <> rustRet retTy
      <> " { let " <> recv <> " = " <> recvRhs <> "; " <> body <> " }"

-- an impl-method param `name: <borrowed sig type>` (the name is the impl's, the type the protocol's).
implParam :: String -> String -> String -> String
implParam rustType name sigP = name <> ": " <> refType rustType (snd (nameType sigP))

-- ── sum types → enums ──────────────────────────────────────────────────────────

buildMeta :: Array Type -> Meta
buildMeta types =
  withPrelude types
    >>= \t -> map (\v -> Tuple v.ctor (vinfo t v)) t.variants

vinfo :: Type -> Variant -> VInfo
vinfo t v =
  { enum: t.name
  , named: v.fields /= [] && all (\f -> isJust f.label) v.fields
  , labels: map _.label v.fields
  }

lookupCtor :: Meta -> String -> VInfo
lookupCtor meta ctor = case find (\(Tuple c _) -> c == ctor) meta of
  Just (Tuple _ info) -> info
  Nothing -> unsafeCrashWith ("rust: unknown ctor " <> ctor)

rustEnum :: ParaMap -> Type -> String
rustEnum pm t =
  "#[derive(Clone, Debug, PartialEq)]\nenum " <> t.name <> enumGenerics pm t <> " {\n"
    <> joinWith "\n" (map (variantDecl pm) t.variants)
    <> "\n}"

-- a parametric type's generic list `<K: Clone, V: Clone>` (the `'static`/`Fn`-field bound is a
-- later closures increment); a non-parametric type → "".
enumGenerics :: ParaMap -> Type -> String
enumGenerics pm t = case paraLookup pm t.name of
  [] -> ""
  params -> "<" <> joinWith ", " (map (\p -> p <> ": Clone") params) <> ">"

variantDecl :: ParaMap -> Variant -> String
variantDecl pm v
  | v.fields == [] = "    " <> v.ctor <> ","
  | all (\f -> isJust f.label) v.fields =
      "    " <> v.ctor <> " { "
        <> joinWith ", " (map (\f -> fromMaybe "" f.label <> ": " <> rustFieldType pm f.ty) v.fields)
        <> " },"
  | otherwise =
      "    " <> v.ctor <> "(" <> joinWith ", " (map (\f -> rustFieldType pm f.ty) v.fields) <> "),"

-- a variant field's Rust type: a referenced parametric type → its instantiation (`Pair<K, V>`);
-- else the owned base (a tvar `T` → `T`, `Int53` → `i64`). (`Fn`-field → `Rc<dyn …>` is later.)
rustFieldType :: ParaMap -> String -> String
rustFieldType pm ft = case find (\(Tuple n _) -> n == ft) pm of
  Just (Tuple _ params) -> ft <> "<" <> joinWith ", " params <> ">"
  Nothing -> Cap.owned ft

-- ── function / clause dispatch ────────────────────────────────────────────────

rustFn :: ParaMap -> Meta -> Env -> Array String -> Array (Tuple String (Array Param)) -> Func -> String
rustFn _ _ _ _ _ f | not (null f.externals) = externalRustFn f
rustFn pm meta env methods sigs f =
  let
    -- parametric instantiation for this function (`Box` → `Box<T>` in its sig); empty in the
    -- per-unit `rust` stream (no `pm`), filled in the whole-program `rustprog` stream.
    pinst = pairInst pm f
    -- a value-union param/return is the synth enum (owned), not the capability lowering (ADR-0083).
    paramTy p = let t = fromMaybe "" p.ty in if isUnionType t then unionEnumName t else rustifyParametric pinst (Cap.rustParam p.cap t)
    paramDecls = joinWith ", " (map (\p -> p.name <> ": " <> paramTy p) f.params)
    ret = let r = fromMaybe "" f.ret in if isUnionType r then unionEnumName r else rustifyParametric pinst (rustRet r)
    -- param positions that are an owned `iso Vec` destructured by a cons/list pattern: they
    -- match via `.as_slice()` and their binders are rebound owned in each arm (ADR-0047).
    iso = isoConsPositions f
    scrut = rustScrut iso f.params
    arms = joinWith "\n" (map (clauseArm meta methods sigs f iso) f.clauses)
  in
    "fn " <> f.name <> rustGenerics f <> "(" <> paramDecls <> ") -> " <> ret <> " {\n"
      <> "    match "
      <> scrut
      <> " {\n"
      <> arms
      <> shim env f
      <> "\n    }\n}"

-- the per-target exhaustiveness shim (ADR-0036). A **partial** function (clause heads not
-- total, by `Rian.Exhaustiveness`) gets `_ => panic!(…)` — the runtime no-match the BEAM's
-- `FunctionClauseError` / JS-JVM `throw` give; a non-partial **range-total** literal match
-- gets `_ => unreachable!()` (the Rian gate proved totality, but `rustc` sees the open base
-- primitive as non-exhaustive). A closed sum / var-headed match needs neither.
shim :: Env -> Func -> String
shim env f
  | isPartial env f = "\n        _ => panic!(" <> strLit (f.name <> ": no clause matched") <> "),"
  | rustTotalShim f = "\n        _ => unreachable!(),"
  | otherwise = ""

-- partial = the clause heads are not exhaustive (the same analysis `Rian.Lower.check!` stamps).
isPartial :: Env -> Func -> Boolean
isPartial env f = case head f.clauses of
  Nothing -> false
  Just c0 ->
    let
      arity = length c0.pats
      arms = map clauseArm_ f.clauses
      clauseArm_ c =
        let Tuple pats intro = lowerMany (map fromPat c.pats) env
        in { pat: pats, guard: isJust c.guard || intro }
    in
      not (analyze arms arity env).exhaustive

-- a literal-headed match over an OPEN base primitive (no catch-all, no variant) that the
-- gate proved total — `rustc` still needs an `unreachable!()` arm. Pattern-only (mirrors
-- `rust_total_shim?`); only consulted when not partial.
rustTotalShim :: Func -> Boolean
rustTotalShim f =
  let
    flat = concatMap (\c -> map fromPat c.pats) f.clauses
    hasCatchall = any (\c -> all catchallPat (map fromPat c.pats)) f.clauses
    literalHeaded = any isLitPat flat || any isCharPat flat
    hasVariant = any isCtorPat flat
  in
    not hasCatchall && literalHeaded && not hasVariant

catchallPat :: CPat -> Boolean
catchallPat PWild = true
catchallPat (PVar _) = true
catchallPat _ = false

isLitPat :: CPat -> Boolean
isLitPat (PLit _) = true
isLitPat _ = false

isCharPat :: CPat -> Boolean
isCharPat (PChar _) = true
isCharPat _ = false

isCtorPat :: CPat -> Boolean
isCtorPat (PCtor _ _) = true
isCtorPat _ = false

-- the match scrutinee: one param matches directly, N>1 match the argument tuple. An `iso Vec`
-- position (in `iso`) is an owned `Vec<T>` matched via `.as_slice()` so cons patterns apply.
rustScrut :: Array Int -> Array Param -> String
rustScrut iso params = case mapWithIndex part params of
  [ one ] -> one
  many -> "(" <> joinWith ", " many <> ")"
  where
  part i p = if elem i iso then p.name <> ".as_slice()" else p.name

-- one `pat => body,` arm. The clause-head patterns form the match pattern (one, or a tuple
-- of N); the body lowers through the precedence-aware emitter, then is return-coerced. `iso` is
-- the function's `iso Vec` cons positions, driving the owned arm rebinds.
clauseArm :: Meta -> Array String -> Array (Tuple String (Array Param)) -> Func -> Array Int -> Clause -> String
clauseArm meta methods sigs f iso c =
  let
    pat = tupleOrOne (map (corePatRs meta) c.pats)
    -- the per-clause emit context: variant registry, borrowed (`&`-bound) vars, the `&[T]`
    -- slice binders, `Fn`-typed params (closure calls), the closure-return box flag, the program
    -- signatures (for the call-site union `From`-wrap / borrow), and the union-typed locals.
    ec =
      { vi: meta
      , bor: borrowedVars f.params c.pats
      , slices: sliceBinders f.params c.pats
      , fnParams: map _.name (filter (\p -> isFnType (fromMaybe "" p.ty)) f.params)
      , fnBox: if isFnType (fromMaybe "" f.ret) then Just { clone: fnReturnsTvar (fromMaybe "" f.ret) f.tvars, rc: false } else Nothing
      , sigs: sigs
      , unions: unionLocals f
      , ownedBinders: []
      }
    -- rewrite protocol-method calls to receiver methods (`eq(a, b)` → `a.eq(b)`, ADR-0061 §2)
    -- on the surface, before lowering to Core.
    cbody = case c.body of
      Just b -> fromExpr (rewriteProtoCalls methods (normalize (bodySurface b)))
      Nothing -> unsafeCrashWith ("rust: clause of " <> f.name <> " has no body")
    ret = fromMaybe "" f.ret
    -- make a cons clause's borrowed binders owned at arm entry: a slice-element HEAD bound under
    -- the `.as_slice()` match is a `&T` borrow → `clone()` (only if the body uses it, else `rustc`
    -- flags an unused `let`); a cons TAIL is a `&[T]` slice, rebound `to_vec()` only for an `iso`
    -- (owned-`Vec`) position (a `val` slice keeps zero-copy recursion). Mirrors `arm_rebinds`.
    rebinds = armRebinds iso (usedIds cbody) c.pats
    -- the arm body: with rebinds it is a `{ let …; … }` block (the rebinds can't push into
    -- branches); otherwise the plain (return-coerced below) body.
    body = fst (emit ec cbody)
    armBody = if null rebinds then rustArmBody cbody body else "{ " <> joinWith " " rebinds <> " " <> body <> " }"
    -- the return coercion (mirrors the reference's clause-arm `cond`): a `Vec` return coerces a
    -- borrowed-collection leaf to owned (`.to_vec()`, pushed into if/case tails for a no-rebind
    -- body; wrapping a rebind body whose value is a slice id); a bare-tvar return clones the
    -- borrowed `T` leaves; else the plain string/owned coercion.
    arm
      | isVecType ret && null rebinds = coerceOwnedVecAst ec cbody
      | isVecType ret && tailSliceId ec cbody = "(" <> armBody <> ").to_vec()"
      | not (null f.tvars) && elem ret f.tvars && null rebinds = coerceOwnedTvar ec cbody
      | not (null f.tvars) && elem ret f.tvars = "(" <> armBody <> ").clone()"
      | otherwise = coerceRet ret armBody
  in
    "        " <> pat <> " => " <> arm <> ","

-- ── deeper capability borrows (ADR-0047/0055/0061) ──────────────────────────────

-- the clause vars that are a `&[T]` SLICE at runtime: a `Vec`-typed `val` param (lowers to
-- `&[T]`) or a cons-tail `@..` binder. A slice stored into an owned `Vec<T>` (a `Vec` return)
-- needs `.to_vec()`, not `.clone()` (which would clone the reference, staying `&[T]`). Mirrors
-- `slice_binders`.
sliceBinders :: Array Param -> Array P.Pat -> Array String
sliceBinders params pats =
  let
    paramSlices = map _.name (filter (\p -> isJust (stripPrefix (Pattern "&[") (Cap.rustParam p.cap (fromMaybe "" p.ty)))) params)
    tails = concatMap (consTailNames <<< fromPat) pats
  in
    paramSlices <> tails

consTailNames :: CPat -> Array String
consTailNames (PList _ (Just (PVar n))) = [ n ]
consTailNames _ = []

-- param positions that are an owned `iso Vec` destructured by a cons/list pattern in some
-- clause — those match `param.as_slice()` and rebind owned in each arm. Mirrors `iso_cons_positions`.
isoConsPositions :: Func -> Array Int
isoConsPositions f =
  map fst (filter keep (mapWithIndex Tuple f.params))
  where
  keep (Tuple i p) =
    p.cap == Iso && isVecType (fromMaybe "" p.ty)
      && any (\c -> isPListPat (index c.pats i)) f.clauses
  isPListPat (Just pat) = case fromPat pat of
    PList _ _ -> true
    _ -> false
  isPListPat Nothing = false

-- the owned rebinds for one clause's cons binders: each USED slice-element HEAD → `let h =
-- h.clone();`, and (for an `iso` position) the cons TAIL → `let t = t.to_vec();`. Mirrors
-- `arm_rebinds`.
armRebinds :: Array Int -> Array String -> Array P.Pat -> Array String
armRebinds iso used pats =
  concat (mapWithIndex perPat pats)
  where
  perPat i pat =
    let
      core = fromPat pat
      heads = map (\n -> "let " <> n <> " = " <> n <> ".clone();") (filter (\n -> elem n used) (sliceElemVars core))
      tails = if elem i iso then consTailRebinds core else []
    in
      heads <> tails

consTailRebinds :: CPat -> Array String
consTailRebinds (PList _ (Just (PVar n))) = [ "let " <> n <> " = " <> n <> ".to_vec();" ]
consTailRebinds _ = []

-- variables bound inside the *element* positions of a list pattern — under a slice match they
-- are `&T` borrows. Mirrors `slice_elem_vars`.
sliceElemVars :: CPat -> Array String
sliceElemVars (PList elems _) = concatMap allPatVars elems
sliceElemVars _ = []

allPatVars :: CPat -> Array String
allPatVars (PVar n) = [ n ]
allPatVars (PCtor _ args) = concatMap allPatVars args
allPatVars (PTuple es) = concatMap allPatVars es
allPatVars (PList elems tail) = concatMap allPatVars elems <> maybe [] allPatVars tail
allPatVars _ = []

-- a `Vec`-returning body whose value is a `&[T]` slice id (`def drop(cs, 0) := cs`) — the arm
-- needs `(…).to_vec()` to materialise the owned `Vec`. Mirrors `tail_slice_id?`.
tailSliceId :: Ec -> CExpr -> Boolean
tailSliceId ec (EBlock [ CExprStmt e ]) = sliceVar ec e
tailSliceId ec e = sliceVar ec e

sliceVar :: Ec -> CExpr -> Boolean
sliceVar ec (EId n) = elem n ec.slices
sliceVar _ _ = false

-- Gap E (ADR-0061): a `Vec`-returning body that tail-returns a BORROWED collection (a `&[T]`
-- slice binder) needs `.to_vec()`. Like the `String` Gap, push the coercion into if/case TAIL
-- leaves rather than wrapping the whole expression; only a borrowed-collection leaf is cloned,
-- an owned leaf (`vec![…]`, a cons rebuild, an owned call) is emitted untouched. Mirrors
-- `coerce_owned_vec_ast`.
coerceOwnedVecAst :: Ec -> CExpr -> String
coerceOwnedVecAst ec (EIf c t e) =
  "if " <> p ec 0 c <> " { " <> coerceOwnedVecAst ec t <> " } else { " <> coerceOwnedVecAst ec e <> " }"
coerceOwnedVecAst ec (ECase scrut arms) = rustCaseWith ec scrut arms (coerceOwnedVecAst ec)
coerceOwnedVecAst ec (EBlock [ CExprStmt e ]) = coerceOwnedVecAst ec e
coerceOwnedVecAst ec e@(EId n) =
  let s = p ec 0 e
  in if elem n ec.slices then s <> ".to_vec()" else s
coerceOwnedVecAst ec ast = p ec 0 ast

isVecType :: String -> Boolean
isVecType t = isJust (stripPrefix (Pattern "Vec(") t)

-- identifier names referenced anywhere in a Core body expression (for the arm-rebind
-- used-binder filter). Mirrors `used_ids`/`collect_ids`.
usedIds :: CExpr -> Array String
usedIds (EId n) = [ n ]
usedIds (EUnary _ e) = usedIds e
usedIds (EBin _ a b) = usedIds a <> usedIds b
usedIds (ECall f as) = usedIds f <> concatMap usedIds as
usedIds (EDot e _) = usedIds e
usedIds (EIf c t e) = usedIds c <> usedIds t <> usedIds e
usedIds (ECase s arms) = usedIds s <> concatMap armIds arms
usedIds (EWith cls e arms) = concatMap (\w -> usedIds w.expr) cls <> usedIds e <> concatMap armIds arms
usedIds (EBlock stmts) = concatMap stmtIds stmts
usedIds (EList es tl) = concatMap usedIds es <> maybe [] usedIds tl
usedIds (EMap pairs) = concatMap mapPairIds pairs
usedIds (EMapUpdate b pairs) = usedIds b <> concatMap mapPairIds pairs
usedIds (ETuple es) = concatMap usedIds es
usedIds (ELambda _ e) = usedIds e
usedIds (ECapture e) = usedIds e
usedIds (ECaptureNamed e _) = usedIds e
usedIds (ELabel _ e) = usedIds e
usedIds (EStruct _ fs) = concatMap (\(Tuple _ e) -> usedIds e) fs
usedIds (EVariant _ fs) = concatMap (\(Tuple _ e) -> usedIds e) fs
usedIds _ = []

armIds :: CArm -> Array String
armIds a = maybe [] usedIds a.guard <> usedIds a.body

stmtIds :: CStmt -> Array String
stmtIds (CBind _ e) = usedIds e
stmtIds (CTypedBind _ _ e) = usedIds e
stmtIds (CExprStmt e) = usedIds e

mapPairIds :: CMapPair -> Array String
mapPairIds (CMAtom _ v) = usedIds v
mapPairIds (CMKey k v) = usedIds k <> usedIds v

-- the clause vars that are a `&`-reference at runtime: a pattern var binding a `&`-typed
-- (capability-borrowed) param. Such a var is cloned to owned in a construction position
-- (`rust_owned_elem`). Mirrors `borrowed_vars` for the var-pattern case.
borrowedVars :: Array Param -> Array P.Pat -> Array String
borrowedVars params pats =
  concatMap pick (zipWith Tuple params pats)
  where
  pick (Tuple pm pat) =
    if isBorrow (Cap.rustParam pm.cap (fromMaybe "" pm.ty)) then patVarNames (fromPat pat) else []
  isBorrow s = isJust (stripPrefix (Pattern "&") s)

-- the variable names a pattern binds (for the borrowed set) — recursing ctor/tuple/list args.
patVarNames :: CPat -> Array String
patVarNames (PVar n) = [ n ]
patVarNames (PCtor _ args) = concatMap patVarNames args
patVarNames (PTuple es) = concatMap patVarNames es
patVarNames (PList es _) = concatMap patVarNames es
patVarNames _ = []

-- the Rust generic list `<T: Clone, …>`: each tvar's declared bounds (`forall T: Eq` →
-- `RianEq`) plus `Clone` (a generic body clones borrowed leaves to the owned return). The
-- closure-`'static` / `Map`-key `Eq + Hash` bounds are the later generics increment.
rustGenerics :: Func -> String
rustGenerics f = case f.tvars of
  [] -> ""
  tvs -> "<" <> joinWith ", " (map gbound tvs) <> ">"
  where
  gbound tv = tv <> ": " <> joinWith " + " (map (\b -> "Rian" <> b) (boundsOf tv) <> [ "Clone" ])
  boundsOf tv = case find (\(Tuple k _) -> k == tv) f.bounds of
    Just (Tuple _ bs) -> bs
    Nothing -> []

-- clone a bare-tvar return's borrowed leaves to the owned `T` (pushed into `if`/block tails);
-- mirrors `coerce_owned_tvar_ast` for the leaf/`if`/block cases.
coerceOwnedTvar :: Ec -> CExpr -> String
coerceOwnedTvar ec (EBlock [ CExprStmt e ]) = coerceOwnedTvar ec e
coerceOwnedTvar ec (EBlock stmts) = "({ " <> emitBlock ec (EBlock stmts) <> " }).clone()"
coerceOwnedTvar ec (EIf c t e) =
  "if " <> p ec 0 c <> " { " <> coerceOwnedTvar ec t <> " } else { " <> coerceOwnedTvar ec e <> " }"
-- push the clone into each `case` arm's body (not around the whole `match`).
coerceOwnedTvar ec (ECase scrut arms) = rustCaseWith ec scrut arms (coerceOwnedTvar ec)
coerceOwnedTvar ec ast = "(" <> p ec 0 ast <> ").clone()"

-- a multi-statement block body is braced as a match-arm value (`{ … }`); a single
-- expression (or single-stmt block) is the value directly. Mirrors `rust_arm_body`.
rustArmBody :: CExpr -> String -> String
rustArmBody (EBlock stmts) s | length stmts >= 2 = "{ " <> s <> " }"
rustArmBody _ s = s

tupleOrOne :: Array String -> String
tupleOrOne [ one ] = one
tupleOrOne many = "(" <> joinWith ", " many <> ")"

-- ── patterns ───────────────────────────────────────────────────────────────────

corePatRs :: Meta -> P.Pat -> String
corePatRs meta pat = patRs meta (fromPat pat)

patRs :: Meta -> CPat -> String
patRs _ PWild = "_"
patRs _ (PVar x) = x
patRs _ (PLit (LInt v)) = show v
patRs _ (PLit (LStr s)) = strLit s
patRs _ (PAtom a) = strLit a
patRs _ (PChar cp) = rustCharLit cp
patRs meta (PList elems Nothing) = "[" <> joinWith ", " (map (patRs meta) elems) <> "]"
patRs meta (PList elems (Just tail)) =
  "[" <> joinWith ", " (map (patRs meta) elems <> [ restPat tail ]) <> "]"
patRs meta (PCtor name args) =
  let info = lookupCtor meta name
  in
    if null args then info.enum <> "::" <> name
    else if info.named then
      info.enum <> "::" <> name <> " { "
        <> joinWith ", " (zipLabels info.labels (map (patRs meta) args))
        <> " }"
    else
      info.enum <> "::" <> name <> "(" <> joinWith ", " (map (patRs meta) args) <> ")"
patRs _ _ = unsafeCrashWith "rust: pattern not yet ported (stage)"

-- a cons tail → a Rust slice rest pattern: `t @ ..` (bind the rest) or `..` (ignore).
restPat :: CPat -> String
restPat (PVar n) = n <> " @ .."
restPat PWild = ".."
restPat _ = unsafeCrashWith "rust: cons tail must be a var or `_` (stage)"

-- zip declared labels with rendered field strings: `radius: r, …` (an anonymous field → `_i`).
zipLabels :: Array (Maybe String) -> Array String -> Array String
zipLabels labels rendered = mapWithIndex (\i s -> fieldKey i <> ": " <> s) rendered
  where
  fieldKey i = case index labels i of
    Just (Just l) -> l
    _ -> "_" <> show i

-- ── return-type lowering ───────────────────────────────────────────────────────

rustRet :: String -> String
rustRet ret = case resultParts ret of
  Plain t -> Cap.owned t
  Res ok err -> "Result<" <> Cap.owned ok <> ", " <> Cap.owned err <> ">"

data RetParts = Plain String | Res String String

resultParts :: String -> RetParts
resultParts ret =
  case stripPrefix (Pattern "Result(") ret >>= stripSuffix (Pattern ")") of
    Just inner -> case TS.splitTopCommas inner of
      [ ok, err ] -> Res ok err
      _ -> Plain ret
    Nothing -> Plain ret

coerceRet :: String -> String -> String
coerceRet ret body = if stringRepr ret then "(" <> body <> ").to_string()" else body

stringRepr :: String -> Boolean
stringRepr "String" = true
stringRepr "Symbol" = true
stringRepr _ = false

-- ── value unions (ADR-0083) → synthesized Rust enums + From impls + dispatch ────
-- A `String | Int53` param/return → a generated `enum RUnion_Int53_String { … }`. The whole-
-- program assembly emits one enum (+ `From` impls) per distinct union type; a `case` over a union
-- local lowers to a `match` on the enum, and a call passing a member wraps it `RUnion_…::from(x)`.
-- Mirrors `Rian.Lower`'s `synth_union_enums` / `union_enum_decl` / `union_from_arg`.

isUnionType :: String -> Boolean
isUnionType t = isJust (stripPrefix (Pattern "Union(") t)

unionMembersOf :: String -> Array String
unionMembersOf t = case stripPrefix (Pattern "Union(") t >>= stripSuffix (Pattern ")") of
  Just inner -> TS.splitTopCommas inner
  Nothing -> []

-- a member's variant name: non-alphanumerics → `_` (so `Vec(Int8)` → `Vec_Int8_`), matching
-- the reference's `variant_name`.
variantName :: String -> String
variantName = CU.fromCharArray <<< map (\c -> if isAlnum c then c else '_') <<< CU.toCharArray

isAlnum :: Char -> Boolean
isAlnum c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

unionEnumName :: String -> String
unionEnumName t = "RUnion_" <> joinWith "_" (map variantName (unionMembersOf t))

-- the Rust spelling of a union member's payload (`Int53` → `i64`, `String` → `String`).
memberRust :: String -> String
memberRust = Cap.owned

-- every distinct value-union type referenced by a param/return across the program, sorted (the
-- reference's `collect_union_types`).
collectUnionTypes :: Prog -> Array String
collectUnionTypes prog = nub (sort (filter isUnionType (concatMap fnTypes (allFuncs prog))))
  where
  fnTypes f = [ fromMaybe "" f.ret ] <> map (\p -> fromMaybe "" p.ty) f.params

synthUnionEnums :: Prog -> String
synthUnionEnums prog = joinWith "\n\n" (map unionEnumDecl (collectUnionTypes prog))

unionEnumDecl :: String -> String
unionEnumDecl t =
  let
    members = unionMembersOf t
    name = unionEnumName t
    variants = joinWith " " (map (\m -> variantName m <> "(" <> memberRust m <> "),") members)
    froms = joinWith "\n" (concatMap (memberFroms name) members)
  in
    "#[derive(Clone, Debug, PartialEq)]\nenum " <> name <> " { " <> variants <> " }\n" <> froms

memberFroms :: String -> String -> Array String
memberFroms name m =
  let
    v = variantName m
    rt = memberRust m
    base = "impl From<" <> rt <> "> for " <> name <> " { fn from(x: " <> rt <> ") -> Self { Self::" <> v <> "(x) } }"
  in
    if rt == "String" then [ base, "impl From<&str> for " <> name <> " { fn from(x: &str) -> Self { Self::" <> v <> "(x.to_string()) } }" ]
    else [ base ]

-- the program's function signatures (name → params) for the call-site `From`-wrap / borrow.
funcSigs :: Prog -> Array (Tuple String (Array Param))
funcSigs prog = map (\f -> Tuple f.name f.params) (allFuncs prog)

lookupSig :: String -> Array (Tuple String (Array Param)) -> Maybe (Array Param)
lookupSig name = map snd <<< find (\(Tuple k _) -> k == name)

-- the union-typed locals of a clause: params whose declared type is a `Union(…)` (var → that type).
unionLocals :: Func -> Array (Tuple String String)
unionLocals f = mapMaybe pick f.params
  where
  pick p = case p.ty of
    Just t | isUnionType t -> Just (Tuple p.name t)
    _ -> Nothing

-- does this argument PRODUCE an owned value that a `&`-param must borrow? — a union case-arm binder
-- (the synth enum owns its payload) or a stringify prim (`n.to_string()` / `format!(…)`). Gated to
-- the union-arm context (non-empty `ownedBinders`) so non-union code is byte-for-byte unchanged.
ownedArgRs :: Ec -> CExpr -> Boolean
ownedArgRs ec (EId v) = elem v ec.ownedBinders
ownedArgRs _ (ECall (EId "__prim_int_to_string") _) = true
ownedArgRs _ (ECall (EId "__prim_float_repr") _) = true
ownedArgRs _ (ECall (EId "__prim_char_to_string") _) = true
ownedArgRs _ (ECall (EId "__prim_to_string") _) = true
ownedArgRs _ (ECall (EId "__prim_str_concat") _) = true
ownedArgRs _ (ECall (EId "__prim_str_concat_all") _) = true
ownedArgRs _ _ = false

-- a call to a known program function: coerce each argument against the callee's params — a union
-- param gets `RUnion_…::from(arg)` (unless the arg is already that union local); a borrow (`&str`/
-- `&T`) param fed an owned arg (case-arm binder / stringify prim, inside a union arm) gets `&arg`.
coercedCall :: Ec -> String -> Array Param -> Array CExpr -> String
coercedCall ec name params args =
  name <> "(" <> joinWith ", " (mapWithIndex coerce args) <> ")"
  where
  coerce i a = case index params i of
    Just pm -> coerceArg ec pm a
    Nothing -> p ec 0 a

coerceArg :: Ec -> Param -> CExpr -> String
coerceArg ec pm a =
  let ty = fromMaybe "" pm.ty
  in
    if isUnionType ty then case a of
      EId v | elem (Tuple v ty) ec.unions -> p ec 0 a
      _ -> unionEnumName ty <> "::from(" <> p ec 0 a <> ")"
    else if isBorrowParam pm && not (null ec.ownedBinders) && ownedArgRs ec a then "&" <> p ec 12 a
    else p ec 0 a

isBorrowParam :: Param -> Boolean
isBorrowParam pm = isJust (stripPrefix (Pattern "&") (Cap.rustParam pm.cap (fromMaybe "" pm.ty)))

-- the `:rs` external spec, if any (the target key is the bare `"rs"`, as `Decl` stores it).
rustExternal :: Func -> Maybe ExtSpec
rustExternal f = map snd (find (\(Tuple t _) -> t == "rs") f.externals)

-- an `@external` function (ADR-0068): emit the `:rs` host body verbatim — Rust uses named params, so
-- the spec references them directly (no positional binding). No `:rs` body → off `:rs` (Reach pins
-- it); reaching here is an off-target compile error. Mirrors `Rian.Lower.rust_fn`'s external clause.
externalRustFn :: Func -> String
externalRustFn f = case rustExternal f of
  Nothing -> unsafeCrashWith ("`" <> f.name <> "`: no `@external(:rs, …)` body — not reachable on :rs")
  Just (ExtFile _ _) -> unsafeCrashWith ("`" <> f.name <> "`: :rs file-reference externals not yet ported")
  Just spec -> externalRustBody f (Ext.render spec f.params)

externalRustBody :: Func -> String -> String
externalRustBody f host =
  let
    paramDecl p = let t = fromMaybe "" p.ty in p.name <> ": " <> (if isUnionType t then unionEnumName t else Cap.rustParam p.cap t)
    paramDecls = joinWith ", " (map paramDecl f.params)
    ret = let r = fromMaybe "" f.ret in if isUnionType r then unionEnumName r else rustRet r
  in
    "fn " <> f.name <> "(" <> paramDecls <> ") -> " <> ret <> " { " <> host <> " }"

-- ── expression emission (precedence-aware `{string, prec}`) ────────────────────

p :: Ec -> Int -> CExpr -> String
p ec ctx node =
  let Tuple s pr = emit ec node
  in if pr < ctx then "(" <> s <> ")" else s

emit :: Ec -> CExpr -> Tuple String Int
emit _ (ENum n) = Tuple n 12
emit _ (EStr s) = Tuple (strLit s) 12
-- a `Symbol` (`:ok`) is equality-only, lowered to a `&str` literal (ADR-0041).
emit _ (EAtom a) = Tuple (strLit a) 12
-- a `Char` (ADR-0036) is a native Rust `char` literal.
emit _ (EChar cp) = Tuple (rustCharLit cp) 12
emit _ (EId "pi") = Tuple "std::f64::consts::PI" 12
-- a bare PascalCase id is a nullary variant value → `Enum::Variant`.
emit ec (EId x) = case find (\(Tuple c _) -> c == x) ec.vi of
  Just (Tuple _ info) -> Tuple (info.enum <> "::" <> x) 12
  Nothing -> Tuple x 12
emit ec (EUnary "-" x) = Tuple ("-" <> p ec 11 x) 11
emit ec (EUnary "not" x) = Tuple ("!" <> p ec 11 x) 11
emit ec (EIf c t e) =
  Tuple ("if " <> p ec 0 c <> " { " <> emitBlock ec t <> " } else { " <> emitBlock ec e <> " }") 0
-- string concatenation `<>` → one `format!("{}{}…", …)` over the flattened operands.
emit ec (EBin "<>" l r) =
  let parts = flattenConcat (EBin "<>" l r)
  in Tuple ("format!(\"" <> foldMap (const "{}") parts <> "\", " <> joinWith ", " (map (p ec 0) parts) <> ")") 12
emit ec (EBin "div" l r) = Tuple (p ec 10 l <> " / " <> p ec 11 r) 10
emit ec (EBin "rem" l r) = Tuple (p ec 10 l <> " % " <> p ec 11 r) 10
emit ec (EBin "/" l r) = Tuple ("(" <> p ec 0 l <> " as f64) / (" <> p ec 0 r <> " as f64)") 10
emit ec (EBin op l r) =
  let
    pr = prec op
    Tuple lc rc = case assoc op of
      AL -> Tuple pr (pr + 1)
      AR -> Tuple (pr + 1) pr
      AN -> Tuple (pr + 1) (pr + 1)
  in
    Tuple (p ec lc l <> " " <> disp op <> " " <> p ec rc r) pr
emit ec (ECase scrut arms) = Tuple (rustCase ec scrut arms) 0
-- a list literal → `vec![…]`; a cons `[e… | tl]` → prepend onto an owned copy of the tail
-- (`.to_vec()` turns the `&[T]` slice / `Vec` owned), reversed so order is `e…, tail…` (ADR-0047).
emit ec (EList elems Nothing) =
  Tuple ("vec![" <> joinWith ", " (map (rustOwnedElem ec) elems) <> "]") 12
emit ec (EList elems (Just tl)) =
  let prepends = joinWith " " (map (\e -> "__v.insert(0, " <> rustOwnedElem ec e <> ");") (reverse elems))
  in Tuple ("{ let mut __v = " <> p ec 12 tl <> ".to_vec(); " <> prepends <> " __v }") 0
emit ec (EBlock stmts) = Tuple (emitBlock ec (EBlock stmts)) 0
-- a struct construction `Name { f: v, … }` (a PascalCase, all-labeled call that is not a sum ctor).
emit ec (EStruct name pairs) =
  Tuple (name <> " { " <> joinWith ", " (map (\(Tuple k v) -> k <> ": " <> p ec 0 v) pairs) <> " }") 12
-- field access / module/variant path: `p.x`, `Type::Variant`, `module::fn`, `RianTrait::m` (UFCS).
emit _ (EDot (EId m) n)
  | isJust (stripPrefix (Pattern "Rian") m) && pascal m = Tuple (m <> "::" <> n) 12
  | not (pascal m) = Tuple (m <> "." <> n) 12
  | pascal n = Tuple (m <> "::" <> n) 12
  | otherwise = Tuple (toLower m <> "::" <> n) 12
emit ec (EDot hd n) = Tuple (p ec 12 hd <> "::" <> n) 12
-- a closure (`Fn`) value: a callback-arg lambda stays bare `|a| …`; a value-position lambda in a
-- closure-returning function is `Box::new(move |a| …)` (cloning a captured tvar body per call).
emit ec (ELambda params body) =
  let
    ps = joinWith ", " (map _.name params)
    bodyStr = p ec 0 body
  in
    case ec.fnBox of
      Nothing -> Tuple ("|" <> ps <> "| " <> bodyStr) 12
      Just fb ->
        let
          inner = if fb.clone then "(" <> bodyStr <> ").clone()" else bodyStr
          ctor = if fb.rc then "std::rc::Rc::new" else "Box::new"
        in
          Tuple (ctor <> "(move |" <> ps <> "| " <> inner <> ")") 12
-- the stringify / interpolation prims (ADR-0069): each lowers to its native Rust form, mirroring
-- the reference's `__prim_*` emit. `<>` (EBin above) and `Prim.str_concat` (here) both → `format!`.
emit ec (ECall (EId "__prim_int_to_string") [ n ]) = Tuple (p ec 12 n <> ".to_string()") 12
emit ec (ECall (EId "__prim_char_to_string") [ c ]) = Tuple (p ec 12 c <> ".to_string()") 12
emit ec (ECall (EId "__prim_to_string") [ x ]) = Tuple ("format!(\"{}\", " <> p ec 0 x <> ")") 12
emit ec (ECall (EId "__prim_float_repr") [ n ]) = Tuple ("format!(\"{:e}\", " <> p ec 0 n <> ")") 12
emit ec (ECall (EId "__prim_int_to_float") [ n ]) = Tuple ("(" <> p ec 12 n <> " as f64)") 12
emit ec (ECall (EId "__prim_panic") [ msg ]) = Tuple ("panic!(\"{}\", " <> p ec 0 msg <> ")") 12
emit ec (ECall (EId "__prim_str_concat") args) = Tuple (rustFormat ec args) 12
-- variadic single-shot join (ADR-0069 §6): one `format!`, one allocation; every part is a `String`.
emit ec (ECall (EId "__prim_str_concat_all") args) = Tuple (rustFormat ec args) 12
-- `Map(K, V)` prims (ADR-0047) → Rust `HashMap` ops. A `val` map/key/value is a borrow, so `get`
-- clones the value out (`.cloned().unwrap()`), `put` builds a fresh owned map (clone + insert cloned
-- key/value — a functional update matching BEAM/JS), `new`/`has` map directly. `K: Eq + Hash` is
-- added by `rustGenerics`.
emit _ (ECall (EId "__prim_map_new") []) = Tuple "std::collections::HashMap::new()" 12
emit ec (ECall (EId "__prim_map_get") [ m, k ]) =
  Tuple (p ec 12 m <> ".get(" <> p ec 12 k <> ").cloned().unwrap()") 12
emit ec (ECall (EId "__prim_map_has") [ m, k ]) =
  Tuple (p ec 12 m <> ".contains_key(" <> p ec 12 k <> ")") 12
emit ec (ECall (EId "__prim_map_put") [ m, k, v ]) =
  Tuple ("{ let mut __m = " <> p ec 12 m <> ".clone(); __m.insert(" <> p ec 12 k <> ".clone(), " <> p ec 12 v <> ".clone()); __m }") 0
-- a call to a known sum ctor is construction (`Enum::Variant(…)`); a call to a `Fn`-typed param is
-- a closure call (args clone); a PascalCase all-labeled call is struct construction; else a call.
emit ec (ECall (EId name) args)
  | isJust (find (\(Tuple c _) -> c == name) ec.vi) = Tuple (ctorConstruct ec name args) 12
  | elem name ec.fnParams = Tuple (name <> "(" <> joinWith ", " (map (closureArg ec) args) <> ")") 12
  | pascal name && not (null args) && all isELabel args = Tuple (structConstruct ec name args) 12
  -- a call to a known program function: coerce args against its params (value-union `From`-wrap /
  -- owned→borrow); with no union/borrow coercion this is byte-for-byte the plain call below.
  | otherwise = case lookupSig name ec.sigs of
      Just params -> Tuple (coercedCall ec name params args) 12
      Nothing -> Tuple (name <> "(" <> joinWith ", " (map (p ec 0) args) <> ")") 12
emit ec (ECall f args) =
  Tuple (p ec 12 f <> "(" <> joinWith ", " (map (p ec 0) args) <> ")") 12
-- ── captures (ADR-0061) → explicit Rust closures ──
-- a placeholder `&N` → the closure's `aN` parameter.
emit _ (ECapArg n) = Tuple ("a" <> show n) 12
-- an anonymous capture `&(&1 * 2)` → `|a1, … aN| body` (arity from `Core.capArity`).
emit ec (ECapture body) = Tuple ("|" <> closureParams 1 (capArity body) <> "| " <> p ec 0 body) 12
-- a named `&fn/arity` → a forwarding closure `|a0, … | fn(a0, …)` over `a0..arity-1`.
emit ec (ECaptureNamed path arity) =
  let ps = closureParams 0 (arity - 1)
  in Tuple ("|" <> ps <> "| " <> p ec 12 path <> "(" <> ps <> ")") 12
-- `with c1 <- e1; … body else arms` → a nested `match` chain (ADR-0040); a non-matching value
-- falls to the `else` arms (or returns itself). Mirrors `with_chain_rs`.
emit ec (EWith clauses body els) =
  let
    elseRs = joinWith " " (map (\a -> patRs ec.vi a.pat <> caseGuard ec a.guard <> " => " <> p ec 0 a.body <> ",") els)
  in
    Tuple (withChainRs ec clauses (emitBlock ec body) elseRs) 0
-- map literals/updates have no portable Rust lowering (a `Map(K,V)` is built via the `Dict`
-- prelude's `__prim_map_*` ops); they stay BEAM-only (matching the reference).
emit _ (EMap _) = unsafeCrashWith "map literals are BEAM-only in PoC"
emit _ (EMapUpdate _ _) = unsafeCrashWith "map updates are BEAM-only in PoC"
emit _ _ = unsafeCrashWith "rust: expression not yet ported (stage)"

-- "aFrom, …, aTo" — the closure parameters of a capture; empty when the range is empty.
closureParams :: Int -> Int -> String
closureParams from to = if to < from then "" else joinWith ", " (map (\i -> "a" <> show i) (range from to))

-- the nested-`match` desugaring of a `with` chain (ADR-0040). Each clause matches its pattern and
-- continues; the synthesized `__w` binder falls through to the `else` arms (or returns itself).
withChainRs :: Ec -> Array CWithClause -> String -> String -> String
withChainRs ec clauses body elseRs = case uncons clauses of
  Nothing -> "{ " <> body <> " }"
  Just { head: wc, tail } ->
    let fallback = if elseRs == "" then "__w => __w," else "__w => match __w { " <> elseRs <> " },"
    in "match " <> p ec 0 wc.expr <> " { " <> patRs ec.vi wc.pat <> " => "
         <> withChainRs ec tail body elseRs <> " " <> fallback <> " }"

-- a closure-call argument: an `EId` is `.clone()`d (the closure can't borrow a moved capture);
-- any other expression passes through. Mirrors `closure_arg`.
closureArg :: Ec -> CExpr -> String
closureArg ec e = case e of
  EId _ -> p ec 12 e <> ".clone()"
  _ -> p ec 0 e

-- is a type a `Fn(...)` closure type?
isFnType :: String -> Boolean
isFnType t = isJust (stripPrefix (Pattern "Fn(") t)

-- does a `Fn(args, R)` return a type variable `R`? (then a returned closure clones its body).
fnReturnsTvar :: String -> Array String -> Boolean
fnReturnsTvar fnTy tvars = case stripPrefix (Pattern "Fn(") fnTy >>= stripSuffix (Pattern ")") of
  Just inner -> case last (TS.splitTopCommas inner) of
    Just r -> elem (trim r) tvars
    Nothing -> false
  Nothing -> false

-- struct construction from labeled args (source order — Rust named fields are order-free).
structConstruct :: Ec -> String -> Array CExpr -> String
structConstruct ec name args =
  name <> " { " <> joinWith ", " (map field args) <> " }"
  where
  field (ELabel l v) = l <> ": " <> rustOwnedElem ec v
  field _ = unsafeCrashWith "rust: non-labeled struct field (stage)"

isELabel :: CExpr -> Boolean
isELabel (ELabel _ _) = true
isELabel _ = false

-- PascalCase? (first char A–Z) — distinguishes a type/ctor/struct name from a value.
pascal :: String -> Boolean
pascal s = case CU.charAt 0 s of
  Just c -> c >= 'A' && c <= 'Z'
  Nothing -> false

-- positional construction of a sum variant — `Enum::Variant(v, …)`, or
-- `Enum::Variant { label: v, … }` for a variant that declared field labels.
ctorConstruct :: Ec -> String -> Array CExpr -> String
ctorConstruct ec name args =
  let info = lookupCtor ec.vi name
  in
    if null args then info.enum <> "::" <> name
    else if info.named then
      info.enum <> "::" <> name <> " { "
        <> joinWith ", " (zipLabels info.labels (map (rustOwnedElem ec) args))
        <> " }"
    else
      info.enum <> "::" <> name <> "(" <> joinWith ", " (map (rustOwnedElem ec) args) <> ")"

-- a value stored into an owned position (a variant/struct field, a `Vec` element). A borrowed
-- binding (`&T`/`&[T]` — in `ec.bor`) is cloned to the owned `T`; a literal/owned value is itself.
-- (The slice→`.to_vec()` and `&str`→`.to_string()` owned coercions are a later borrow increment.)
-- coerce a value to its OWNED Rust form for a construction / element / `:=`-bind position
-- (mirrors `rust_owned_elem`): a string/`Symbol` *literal* is a `&str` → `.to_string()`; a `&[T]`
-- slice binder → `.to_vec()`; a `&`-borrowed param binder → `.clone()`; an owned value is itself.
-- (The reference also `.to_string()`s a `String`-*typed* `EId` rebind; that needs the node type,
-- which the untyped Core `EId` here doesn't carry — a literal/borrow rebind is the common case.)
rustOwnedElem :: Ec -> CExpr -> String
rustOwnedElem ec e = case e of
  EStr _ -> p ec 0 e <> ".to_string()"
  EAtom _ -> p ec 0 e <> ".to_string()"
  EId n
    | elem n ec.slices -> p ec 0 e <> ".to_vec()"
    | elem n ec.bor -> p ec 0 e <> ".clone()"
  _ -> p ec 0 e

-- a `case` → a Rust `match`; each arm `pat <guard> => body,`, joined by spaces. A `case` whose
-- arms match a list is over a slice, so the scrutinee is borrowed as `&(scrut)[..]` (ADR-0047).
rustCase :: Ec -> CExpr -> Array CArm -> String
rustCase ec scrut arms = rustCaseWith ec scrut arms (p ec 0)

-- `rust_case` with a custom arm-body emitter (the bare-tvar return pushes `.clone()` into the
-- arm bodies; the default emits them plainly).
rustCaseWith :: Ec -> CExpr -> Array CArm -> (CExpr -> String) -> String
rustCaseWith ec scrut arms bodyFn =
  case unionScrut ec scrut of
    -- a `case` over a value-union local (ADR-0083) → a `match` on the synth enum; each type-pattern
    -- arm binds the OWNED member (added to `ownedBinders` so a `&str` host arg in the body borrows).
    Just enum -> "match " <> p ec 0 scrut <> " { " <> joinWith " " (map (unionArm ec enum) arms) <> " }"
    Nothing ->
      let
        sliced = any (\a -> isListPat a.pat) arms
        scrutRs = if sliced then "&(" <> p ec 0 scrut <> ")[..]" else p ec 0 scrut
        arm a = patRs ec.vi a.pat <> caseGuard ec a.guard <> " => " <> bodyFn a.body <> ","
      in
        "match " <> scrutRs <> " { " <> joinWith " " (map arm arms) <> " }"

-- the synth enum name if the scrutinee is a value-union local (`case x` over a `String | Int53`
-- param), else `Nothing` — the ordinary `match`. (A union-returning-call scrutinee is deferred.)
unionScrut :: Ec -> CExpr -> Maybe String
unionScrut ec (EId v) = case find (\(Tuple k _) -> k == v) ec.unions of
  Just (Tuple _ ty) -> Just (unionEnumName ty)
  Nothing -> Nothing
unionScrut _ _ = Nothing

-- one arm of a value-union `match`: a type-pattern `s String ->` → `RUnion_…::String(s)` with `s`
-- bound owned (so the body borrows it for a `&` host param); any other pattern emits normally.
unionArm :: Ec -> String -> CArm -> String
unionArm ec enum a = case a.pat of
  PTyped binder tname _ ->
    let ec' = ec { ownedBinders = snoc ec.ownedBinders binder }
    in enum <> "::" <> variantName tname <> "(" <> binder <> ")" <> caseGuard ec' a.guard <> " => " <> p ec' 0 a.body <> ","
  _ -> patRs ec.vi a.pat <> caseGuard ec a.guard <> " => " <> p ec 0 a.body <> ","

isListPat :: CPat -> Boolean
isListPat (PList _ _) = true
isListPat _ = false

caseGuard :: Ec -> Maybe CExpr -> String
caseGuard _ Nothing = ""
caseGuard ec (Just g) = " if " <> p ec 0 g

-- a block in tail position (an `if` branch / arm): statements joined, the final an expression.
emitBlock :: Ec -> CExpr -> String
emitBlock _ (EBlock []) = "()"
emitBlock ec (EBlock stmts) =
  let n = length stmts
  in joinWith " " (mapWithIndex (\i s -> stmtRs ec (i < n - 1) s) stmts)
emitBlock ec e = p ec 0 e

-- one block statement; `nonfinal` marks a non-last expression — a side effect before the next, so
-- it ends in `;` (`{ puts(…); puts(…) }`). The final expression is the block's value (no `;`).
stmtRs :: Ec -> Boolean -> CStmt -> String
stmtRs ec true (CExprStmt e) = p ec 0 e <> ";"
stmtRs ec false (CExprStmt e) = p ec 0 e
-- a `:=` bind owns its RHS (`rust_owned_elem`): a `&T`/`&str`/`&[T]` rebind is cloned/`to_string`/
-- `to_vec`'d so the binder is owned and downstream construction needs no further coercion.
stmtRs ec _ (CBind n e) = "let " <> n <> " = " <> rustOwnedElem ec e <> ";"
stmtRs ec _ (CTypedBind n _ e) = "let " <> n <> " = " <> rustOwnedElem ec e <> ";"

-- ── operator precedence (mirrors `Rian.Lower` prec/assoc/disp) ─────────────────

data Assoc = AL | AR | AN

prec :: String -> Int
prec op
  | op == "*" || op == "/" || op == "rem" || op == "div" = 10
  | op == "+" || op == "-" = 9
  | op == "<>" = 8
  | op == "in" = 7
  | op == "|>" = 6
  | op == "<" || op == "<=" || op == ">" || op == ">=" = 5
  | op == "==" || op == "!=" = 4
  | op == "and" = 3
  | op == "or" = 2
  | otherwise = 1 -- `<~`

assoc :: String -> Assoc
assoc op
  | op == "<>" || op == "<~" = AR
  | op == "<" || op == "<=" || op == ">" || op == ">=" || op == "==" || op == "!=" || op == "in" = AN
  | otherwise = AL

disp :: String -> String
disp "and" = "&&"
disp "or" = "||"
disp "<~" = "="
disp op = op

-- ── string / char literals (shared Elixir/Rust escapes; Rust `\u{HEX}`) ─────────

-- flatten a left/right-nested `<>` chain into its operands (for the `format!` join).
flattenConcat :: CExpr -> Array CExpr
flattenConcat (EBin "<>" l r) = flattenConcat l <> flattenConcat r
flattenConcat e = [ e ]

-- a `String`/`Symbol` literal as a double-quoted Rust string (`\n \r \t \\ \"` + `\u{HEX}`).
strLit :: String -> String
strLit s = "\"" <> foldMap strLitCp (CP.toCodePointArray s) <> "\""

strLitCp :: CP.CodePoint -> String
strLitCp cp =
  let n = fromEnum cp
  in
    if n == 92 then "\\\\"
    else if n == 34 then "\\\""
    else if n == 10 then "\\n"
    else if n == 13 then "\\r"
    else if n == 9 then "\\t"
    else if n < 0x20 || n == 0x7F then "\\u{" <> toUpper (Int.toStringAs Int.hexadecimal n) <> "}"
    else CP.singleton cp

-- a string-concatenation / interpolation join (ADR-0069) → one `format!`. A string-LITERAL part is
-- baked into the template (`"Hello, ${name}!"` → `format!("Hello, {}!", name)`, not the mechanical
-- `format!("{}{}{}", "Hello, ", name, "!")`); a non-literal part stays a `{}` placeholder + an arg.
rustFormat :: Ec -> Array CExpr -> String
rustFormat ec args =
  let
    template = foldMap fmtPart args
    fmtArgs = mapMaybe (argPart ec) args
    argsPart = if null fmtArgs then "" else ", " <> joinWith ", " fmtArgs
  in
    "format!(\"" <> template <> "\"" <> argsPart <> ")"

-- a part's template contribution: a string LITERAL is baked, any other part is a `{}` placeholder.
fmtPart :: CExpr -> String
fmtPart (EStr s) = fmtSeg s
fmtPart _ = "{}"

-- a part's `format!` argument: only the non-literal parts (the baked literals carry no arg).
argPart :: Ec -> CExpr -> Maybe String
argPart _ (EStr _) = Nothing
argPart ec a = Just (p ec 0 a)

-- a literal segment for a `format!` template: per-codepoint string escaping (reusing `strLitCp`), but
-- a literal brace is DOUBLED (`{` → `{{`) so `format!` reads it as text, not a placeholder.
fmtSeg :: String -> String
fmtSeg s = foldMap fmtSegCp (CP.toCodePointArray s)

fmtSegCp :: CP.CodePoint -> String
fmtSegCp cp = case fromEnum cp of
  0x7B -> "{{"
  0x7D -> "}}"
  _ -> strLitCp cp

-- a Unicode codepoint as a Rust `char` literal, escaping the specials.
rustCharLit :: Int -> String
rustCharLit 10 = "'\\n'"
rustCharLit 9 = "'\\t'"
rustCharLit 13 = "'\\r'"
rustCharLit 0 = "'\\0'"
rustCharLit 92 = "'\\\\'"
rustCharLit 39 = "'\\''"
rustCharLit cp = "'" <> chr cp <> "'"

chr :: Int -> String
chr n = fromMaybe "" (map CP.singleton (toEnum n :: Maybe CP.CodePoint))

-- ── parametric types → generics / monomorphization (ADR-0061) ───────────────────

-- a parametric type name → its tvar params (`Pair` → `["K", "V"]`); non-parametric types absent.
type ParaMap = Array (Tuple String (Array String))

paraLookup :: ParaMap -> String -> Array String
paraLookup pm name = fromMaybe [] (map snd (find (\(Tuple n _) -> n == name) pm))

-- `parametric_param_map`: each user type → the tvars in its fields, by a fixpoint over the type
-- graph (a field that is another user type contributes that type's params — chains converge).
parametricMap :: Array Type -> ParaMap
parametricMap types =
  filter (\(Tuple _ ps) -> not (null ps)) (converge [])
  where
  names = map _.name types
  converge acc =
    let next = map (\t -> Tuple t.name (typeParamTvars acc t)) types
    in if next == acc then next else converge next
  typeParamTvars acc t =
    nub $ concatMap
      (\v -> concatMap (\f -> if elem f.ty names then paraLookup acc f.ty else typeTvars f.ty) v.fields)
      t.variants

-- the tvar-shaped identifiers in a type string (`Vec(T)` → `["T"]`, `Int53` → `[]`).
typeTvars :: String -> Array String
typeTvars t = filter tvarName (typeWords t)

-- the `\w+` identifier runs in a type string (regex-free, like `Rian.JS.typeWords`).
typeWords :: String -> Array String
typeWords s = filter (_ /= "") (go (CU.toCharArray s) [] [])
  where
  go cs cur acc = case uncons cs of
    Nothing -> snoc acc (CU.fromCharArray cur)
    Just { head: c, tail } ->
      if wordChar c then go tail (snoc cur c) acc
      else go tail [] (snoc acc (CU.fromCharArray cur))

-- a type variable name: a single upper-case letter + an optional digit (`T`, `K`, `T0`).
tvarName :: String -> Boolean
tvarName s = case CU.toCharArray s of
  [ c ] -> upper c
  [ c, d ] -> upper c && d >= '0' && d <= '9'
  _ -> false
  where
  upper c = c >= 'A' && c <= 'Z'

wordChar :: Char -> Boolean
wordChar c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'

-- whole-word substitution (`Box` → `Box<T>` in `&Box`, never inside `Boxer`): tokenize into
-- word / non-word runs and replace exact-match word tokens. Mirrors `Rian.Lower.word_replace`.
wordReplace :: String -> String -> String -> String
wordReplace name repl s =
  joinWith "" (map (\t -> if t == name then repl else t) toks)
  where
  toks = map (CU.fromCharArray <<< NEA.toArray) (Array.groupBy (\a b -> wordChar a == wordChar b) (CU.toCharArray s))

-- a per-function instantiation: each used parametric type name → its `<args>` string.
type Pinst = Array (Tuple String String)

-- rewrite each parametric type name in a Rust type string to its instantiation
-- (`&[Pair]` + `Pair→<K, V>` → `&[Pair<K, V>]`). Mirrors `rustify_parametric`.
rustifyParametric :: Pinst -> String -> String
rustifyParametric pinst t = foldl (\acc (Tuple name args) -> wordReplace name (name <> args) acc) t pinst

-- the per-function instantiation map: each parametric type the signature mentions → `<params>`
-- (a generic function reuses the type's param names; concrete builders are a later increment).
pairInst :: ParaMap -> Func -> Pinst
pairInst pm f =
  map (\(Tuple name params) -> Tuple name ("<" <> joinWith ", " params <> ">"))
    (filter (\(Tuple name _) -> parametricUsed name) pm)
  where
  sig = map (fromMaybe "") (map _.ty f.params) <> [ fromMaybe "" f.ret ]
  parametricUsed name = any (\s -> elem name (typeWords s)) sig
