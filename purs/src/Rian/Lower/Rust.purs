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
  ) where

import Prelude

import Data.Array (all, filter, find, foldl, index, length, mapWithIndex, null)
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing)
import Data.String (Pattern(..), stripPrefix, stripSuffix)
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Assemble (assemble, runProgramTail)
import Rian.Capability (owned, rustParam) as Cap
import Rian.Check (checkProgram)
import Rian.Core (CArm, CExpr(..), CPat(..), CStmt(..), LitVal(..), fromExpr, fromPat)
import Rian.Decl (parseToProg)
import Rian.IR (Clause, Func, Param, Prog, Type, Variant, bodySurface)
import Rian.Opaque (erase)
import Rian.Pratt (Pat) as P
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
          enums = joinWith "\n\n" (map rustEnum types)
          funcs = filter (\f -> isNothing f.dispatch) (allFuncs prog)
        in
          joinWith "\n\n" (map (\f -> rustUnit enums meta f) funcs)

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> foldl (\acc m -> acc <> m.funcs) [] prog.mods

allTypes :: Prog -> Array Type
allTypes prog = prog.types <> foldl (\acc m -> acc <> m.types) [] prog.mods

-- the per-function unit: the program's `enum` defs (repeated per unit, as the reference does),
-- then this function. Empty parts (no types) drop out.
rustUnit :: String -> Meta -> Func -> String
rustUnit enums meta f = joinWith "\n\n" (filter (_ /= "") [ enums, rustFn meta f ])

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

rustFn :: Meta -> Func -> String
rustFn meta f =
  let
    paramDecls = joinWith ", " (map paramDecl f.params)
    ret = rustRet (fromMaybe "" f.ret)
    scrut = rustScrut f.params
    arms = joinWith "\n" (map (clauseArm meta f) f.clauses)
  in
    "fn " <> f.name <> "(" <> paramDecls <> ") -> " <> ret <> " {\n"
      <> "    match "
      <> scrut
      <> " {\n"
      <> arms
      <> "\n    }\n}"

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
clauseArm :: Meta -> Func -> Clause -> String
clauseArm meta f c =
  let
    pat = tupleOrOne (map (corePatRs meta) c.pats)
    cbody = case c.body of
      Just b -> fromExpr (normalize (bodySurface b))
      Nothing -> unsafeCrashWith ("rust: clause of " <> f.name <> " has no body")
    arm = coerceRet (fromMaybe "" f.ret) (rustArmBody cbody (fst (emit meta cbody)))
  in
    "        " <> pat <> " => " <> arm <> ","

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
emit _ (EId "pi") = Tuple "std::f64::consts::PI" 12
-- a bare PascalCase id is a nullary variant value → `Enum::Variant`.
emit meta (EId x) = case find (\(Tuple c _) -> c == x) meta of
  Just (Tuple _ info) -> Tuple (info.enum <> "::" <> x) 12
  Nothing -> Tuple x 12
emit meta (EUnary "-" x) = Tuple ("-" <> p meta 11 x) 11
emit meta (EUnary "not" x) = Tuple ("!" <> p meta 11 x) 11
emit meta (EIf c t e) =
  Tuple ("if " <> p meta 0 c <> " { " <> emitBlock meta t <> " } else { " <> emitBlock meta e <> " }") 0
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
emit meta (EBlock stmts) = Tuple (emitBlock meta (EBlock stmts)) 0
-- a call to a known sum ctor is construction (`Enum::Variant(…)`); otherwise a local call.
emit meta (ECall (EId name) args)
  | isJust (find (\(Tuple c _) -> c == name) meta) = Tuple (ctorConstruct meta name args) 12
emit meta (ECall f args) =
  Tuple (p meta 12 f <> "(" <> joinWith ", " (map (p meta 0) args) <> ")") 12
emit _ _ = unsafeCrashWith "rust: expression not yet ported (stage)"

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

-- a `case` → a Rust `match`; each arm `pat <guard> => body,`, joined by spaces.
rustCase :: Meta -> CExpr -> Array CArm -> String
rustCase meta scrut arms =
  "match " <> p meta 0 scrut <> " { " <> joinWith " " (map (caseArm meta) arms) <> " }"

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
