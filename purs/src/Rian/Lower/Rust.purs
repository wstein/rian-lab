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
-- |      and `case` (→ a nested `match`).
-- | Still later: the partial/total `match` shim (`_ => panic!`/`unreachable!()` — needs the
-- | exhaustiveness/`partial` flag), structs, lists, strings/chars, capability borrows,
-- | generics/monomorphization, and protocol traits. An unported node raises a clear "stage"
-- | crash, kept out of the `rust` parity corpus (oracle = `Rian.Decl.compile`'s `:rust`).
module Rian.Lower.Rust
  ( compile
  , rustProgram
  ) where

import Prelude

import Data.Array (all, any, concatMap, drop, elem, filter, find, foldl, head, index, length, mapWithIndex, null, reverse, uncons, zipWith)
import Data.Enum (fromEnum, toEnum)
import Data.Foldable (foldMap)
import Data.Int (hexadecimal, toStringAs) as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing)
import Data.String (Pattern(..), Replacement(..), replaceAll, split, stripPrefix, stripSuffix)
import Data.String.CodePoints (CodePoint, singleton, toCodePointArray) as CP
import Data.String.CodeUnits (charAt) as CU
import Data.String.Common (joinWith, toLower, toUpper, trim)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Capability (copy, owned, rustParam) as Cap
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.Exhaustiveness (analyze, programEnv)
import Rian.IR (Clause, Func, ImplDecl, ImplMethod, Method, Param, Prog, Protocol, Range, Struct, Type, Variant, bodySurface)
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
          enums = joinWith "\n\n" (map rustEnum types)
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
  joinWith "\n\n" (filter (_ /= "") [ structDefs, enums, rustFn meta env methods f ])

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
          methods = prog.protocols >>= \pr -> map _.name pr.methods
          structs = joinWith "\n\n" (map rustStruct prog.structs)
          enums = joinWith "\n\n" (map rustEnum types)
          traits = joinWith "\n\n" (map rustTrait prog.protocols)
          impls = joinWith "\n\n" (map (rustImpl meta methods prog.protocols) prog.implDecls)
          traitImpl = joinWith "\n\n" (filter (_ /= "") [ traits, impls ])
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
          fns = joinWith "\n\n" (map (rustFn meta env methods) funcs)
        in
          joinWith "\n\n" (filter (_ /= "") [ structs, enums, traitImpl, fns ])

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
    body = coerceRet retTy (fst (emit meta (fromExpr (rewriteProtoCalls methods (normalize bodySurf)))))
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

rustEnum :: Type -> String
rustEnum t =
  "#[derive(Clone, Debug, PartialEq)]\nenum " <> t.name <> " {\n"
    <> joinWith "\n" (map variantDecl t.variants)
    <> "\n}"

variantDecl :: Variant -> String
variantDecl v
  | v.fields == [] = "    " <> v.ctor <> ","
  | all (\f -> isJust f.label) v.fields =
      "    " <> v.ctor <> " { "
        <> joinWith ", " (map (\f -> fromMaybe "" f.label <> ": " <> Cap.owned f.ty) v.fields)
        <> " },"
  | otherwise =
      "    " <> v.ctor <> "(" <> joinWith ", " (map (\f -> Cap.owned f.ty) v.fields) <> "),"

-- ── function / clause dispatch ────────────────────────────────────────────────

rustFn :: Meta -> Env -> Array String -> Func -> String
rustFn meta env methods f =
  let
    paramDecls = joinWith ", " (map paramDecl f.params)
    ret = rustRet (fromMaybe "" f.ret)
    scrut = rustScrut f.params
    arms = joinWith "\n" (map (clauseArm meta methods f) f.clauses)
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

-- a parameter's Rust declaration: `name: <capability-lowered type>` (ADR-0055).
paramDecl :: Param -> String
paramDecl pm = pm.name <> ": " <> Cap.rustParam pm.cap (fromMaybe "" pm.ty)

-- the match scrutinee: one param matches directly, N>1 match the argument tuple.
rustScrut :: Array Param -> String
rustScrut params = case map _.name params of
  [ one ] -> one
  many -> "(" <> joinWith ", " many <> ")"

-- one `pat => body,` arm. The clause-head patterns form the match pattern (one, or a tuple
-- of N); the body lowers through the precedence-aware emitter, then is return-coerced.
clauseArm :: Meta -> Array String -> Func -> Clause -> String
clauseArm meta methods f c =
  let
    pat = tupleOrOne (map (corePatRs meta) c.pats)
    -- rewrite protocol-method calls to receiver methods (`eq(a, b)` → `a.eq(b)`, ADR-0061 §2)
    -- on the surface, before lowering to Core.
    cbody = case c.body of
      Just b -> fromExpr (rewriteProtoCalls methods (normalize (bodySurface b)))
      Nothing -> unsafeCrashWith ("rust: clause of " <> f.name <> " has no body")
    ret = fromMaybe "" f.ret
    -- a generic function returning a bare tvar `T` clones the borrowed `&T` leaves to the
    -- owned `T` the signature promises (`T: Clone`); else the plain string/owned-Vec return
    -- coercion. (Rebinds + the owned-Vec/String leaf coercions are the deeper-borrow increment.)
    arm =
      if not (null f.tvars) && elem ret f.tvars then coerceOwnedTvar meta cbody
      else coerceRet ret (rustArmBody cbody (fst (emit meta cbody)))
  in
    "        " <> pat <> " => " <> arm <> ","

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
coerceOwnedTvar :: Meta -> CExpr -> String
coerceOwnedTvar meta (EBlock [ CExprStmt e ]) = coerceOwnedTvar meta e
coerceOwnedTvar meta (EBlock stmts) = "({ " <> emitBlock meta (EBlock stmts) <> " }).clone()"
coerceOwnedTvar meta (EIf c t e) =
  "if " <> p meta 0 c <> " { " <> coerceOwnedTvar meta t <> " } else { " <> coerceOwnedTvar meta e <> " }"
coerceOwnedTvar meta ast = "(" <> p meta 0 ast <> ").clone()"

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

-- ── expression emission (precedence-aware `{string, prec}`) ────────────────────

p :: Meta -> Int -> CExpr -> String
p meta ctx node =
  let Tuple s pr = emit meta node
  in if pr < ctx then "(" <> s <> ")" else s

emit :: Meta -> CExpr -> Tuple String Int
emit _ (ENum n) = Tuple n 12
emit _ (EStr s) = Tuple (strLit s) 12
-- a `Symbol` (`:ok`) is equality-only, lowered to a `&str` literal (ADR-0041).
emit _ (EAtom a) = Tuple (strLit a) 12
-- a `Char` (ADR-0036) is a native Rust `char` literal.
emit _ (EChar cp) = Tuple (rustCharLit cp) 12
emit _ (EId "pi") = Tuple "std::f64::consts::PI" 12
-- a bare PascalCase id is a nullary variant value → `Enum::Variant`.
emit meta (EId x) = case find (\(Tuple c _) -> c == x) meta of
  Just (Tuple _ info) -> Tuple (info.enum <> "::" <> x) 12
  Nothing -> Tuple x 12
emit meta (EUnary "-" x) = Tuple ("-" <> p meta 11 x) 11
emit meta (EUnary "not" x) = Tuple ("!" <> p meta 11 x) 11
emit meta (EIf c t e) =
  Tuple ("if " <> p meta 0 c <> " { " <> emitBlock meta t <> " } else { " <> emitBlock meta e <> " }") 0
-- string concatenation `<>` → one `format!("{}{}…", …)` over the flattened operands.
emit meta (EBin "<>" l r) =
  let parts = flattenConcat (EBin "<>" l r)
  in Tuple ("format!(\"" <> foldMap (const "{}") parts <> "\", " <> joinWith ", " (map (p meta 0) parts) <> ")") 12
emit meta (EBin "div" l r) = Tuple (p meta 10 l <> " / " <> p meta 11 r) 10
emit meta (EBin "rem" l r) = Tuple (p meta 10 l <> " % " <> p meta 11 r) 10
emit meta (EBin "/" l r) = Tuple ("(" <> p meta 0 l <> " as f64) / (" <> p meta 0 r <> " as f64)") 10
emit meta (EBin op l r) =
  let
    pr = prec op
    Tuple lc rc = case assoc op of
      AL -> Tuple pr (pr + 1)
      AR -> Tuple (pr + 1) pr
      AN -> Tuple (pr + 1) (pr + 1)
  in
    Tuple (p meta lc l <> " " <> disp op <> " " <> p meta rc r) pr
emit meta (ECase scrut arms) = Tuple (rustCase meta scrut arms) 0
-- a list literal → `vec![…]`; a cons `[e… | tl]` → prepend onto an owned copy of the tail
-- (`.to_vec()` turns the `&[T]` slice / `Vec` owned), reversed so order is `e…, tail…` (ADR-0047).
emit meta (EList elems Nothing) =
  Tuple ("vec![" <> joinWith ", " (map (rustOwnedElem meta) elems) <> "]") 12
emit meta (EList elems (Just tl)) =
  let prepends = joinWith " " (map (\e -> "__v.insert(0, " <> rustOwnedElem meta e <> ");") (reverse elems))
  in Tuple ("{ let mut __v = " <> p meta 12 tl <> ".to_vec(); " <> prepends <> " __v }") 0
emit meta (EBlock stmts) = Tuple (emitBlock meta (EBlock stmts)) 0
-- a struct construction `Name { f: v, … }` (a PascalCase, all-labeled call that is not a sum ctor).
emit meta (EStruct name pairs) =
  Tuple (name <> " { " <> joinWith ", " (map (\(Tuple k v) -> k <> ": " <> p meta 0 v) pairs) <> " }") 12
-- field access / module/variant path: `p.x`, `Type::Variant`, `module::fn`, `RianTrait::m` (UFCS).
emit meta (EDot (EId m) n)
  | isJust (stripPrefix (Pattern "Rian") m) && pascal m = Tuple (m <> "::" <> n) 12
  | not (pascal m) = Tuple (m <> "." <> n) 12
  | pascal n = Tuple (m <> "::" <> n) 12
  | otherwise = Tuple (toLower m <> "::" <> n) 12
emit meta (EDot hd n) = Tuple (p meta 12 hd <> "::" <> n) 12
-- a call to a known sum ctor is construction (`Enum::Variant(…)`); a PascalCase all-labeled call
-- is struct construction (`Name { f: v }`); otherwise a local call.
emit meta (ECall (EId name) args)
  | isJust (find (\(Tuple c _) -> c == name) meta) = Tuple (ctorConstruct meta name args) 12
  | pascal name && not (null args) && all isELabel args = Tuple (structConstruct meta name args) 12
emit meta (ECall f args) =
  Tuple (p meta 12 f <> "(" <> joinWith ", " (map (p meta 0) args) <> ")") 12
emit _ _ = unsafeCrashWith "rust: expression not yet ported (stage)"

-- struct construction from labeled args (source order — Rust named fields are order-free).
structConstruct :: Meta -> String -> Array CExpr -> String
structConstruct meta name args =
  name <> " { " <> joinWith ", " (map field args) <> " }"
  where
  field (ELabel l v) = l <> ": " <> p meta 0 v
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
ctorConstruct :: Meta -> String -> Array CExpr -> String
ctorConstruct meta name args =
  let info = lookupCtor meta name
  in
    if null args then info.enum <> "::" <> name
    else if info.named then
      info.enum <> "::" <> name <> " { "
        <> joinWith ", " (zipLabels info.labels (map (rustOwnedElem meta) args))
        <> " }"
    else
      info.enum <> "::" <> name <> "(" <> joinWith ", " (map (rustOwnedElem meta) args) <> ")"

-- a value stored into an owned field. (Increment 2a: Copy primitives — no borrow/clone yet;
-- the owned↔borrow coercion lands with the capability-borrow increment.)
rustOwnedElem :: Meta -> CExpr -> String
rustOwnedElem meta e = p meta 0 e

-- a `case` → a Rust `match`; each arm `pat <guard> => body,`, joined by spaces. A `case` whose
-- arms match a list is over a slice, so the scrutinee is borrowed as `&(scrut)[..]` (ADR-0047).
rustCase :: Meta -> CExpr -> Array CArm -> String
rustCase meta scrut arms =
  let
    sliced = any (\a -> isListPat a.pat) arms
    scrutRs = if sliced then "&(" <> p meta 0 scrut <> ")[..]" else p meta 0 scrut
  in
    "match " <> scrutRs <> " { " <> joinWith " " (map (caseArm meta) arms) <> " }"

isListPat :: CPat -> Boolean
isListPat (PList _ _) = true
isListPat _ = false

caseArm :: Meta -> CArm -> String
caseArm meta a =
  patRs meta a.pat <> caseGuard meta a.guard <> " => " <> p meta 0 a.body <> ","

caseGuard :: Meta -> Maybe CExpr -> String
caseGuard _ Nothing = ""
caseGuard meta (Just g) = " if " <> p meta 0 g

-- a block in tail position (an `if` branch / arm): statements joined, the final an expression.
emitBlock :: Meta -> CExpr -> String
emitBlock _ (EBlock []) = "()"
emitBlock meta (EBlock stmts) = joinWith " " (map (stmtRs meta) stmts)
emitBlock meta e = p meta 0 e

stmtRs :: Meta -> CStmt -> String
stmtRs meta (CExprStmt e) = p meta 0 e
stmtRs meta (CBind n e) = "let " <> n <> " = " <> p meta 0 e <> ";"
stmtRs meta (CTypedBind n _ e) = "let " <> n <> " = " <> p meta 0 e <> ";"

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
