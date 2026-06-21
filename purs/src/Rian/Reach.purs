-- | Target-reachability analysis (ADR-0057) — the PureScript port of `Rian.Reach`
-- | (lib/rian/reach.ex), ADR-0084. For each function it computes the set of target
-- | environments it lowers to — `:ex`/`:rs`/`:js`/`:jvm`. A function is portable unless it
-- | uses a target-pinning construct: host FFI / concurrency (off non-`:ex`), a `ref`
-- | capability (off `:ex`, BEAM-rejected), arbitrary-precision `Int` (off `:rs`/`:jvm`), a
-- | JS-wide fixed integer (off `:js`), `Any` (off `:rs`), a map literal/update (off
-- | `:rs`/`:jvm`), a `Result` value (off `:jvm`), or a BEAM-only prim. Reachability
-- | propagates along the local call graph by a monotone-decreasing fixpoint
-- | (`reach(f) = local(f) ∩ ⋂ reach(callee)`), the same shape as the error-set solver.
-- |
-- | **First slice (ADR-0084):** the signature pins (ref/Int/width/Any), the body scan
-- | (FFI/concurrency/Result/map/prims + call edges), and the fixpoint. DEFERRED (the dense
-- | emitter-gap tail): value unions, the parametric-`:rs` subset, `Any`-in-JVM-operator,
-- | clause-head pins, and associated-type dispatch — so the corpus avoids those constructs.
-- | Bitstrings are absent from the portable Core entirely (BEAM-only), so that pin is moot.
-- | `Prelude.defines?` is not yet ported, so the corpus avoids portable-prelude module calls.
-- |
-- | Parity (`rch` stream): `analyzeSexpr` serializes `{name/arity → sorted-reach + blocker
-- | constructs}` for a parsed scope.
module Rian.Reach
  ( Blocker
  , analyze
  , analyzeSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (all, any, elem, foldl)
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.String (Pattern(..), contains, stripPrefix, stripSuffix) as Str
import Data.String.CodePoints as CP
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst, snd)
import Rian.Core (CArm, CExpr(..), CMapPair(..), CStmt(..), fromExpr)
import Rian.Decl (parseToProg)
import Rian.IR (Cap(..), Clause, Func, Prog)
import Rian.Pratt (MapPatPair(..), Pat(..), Surface, parse, parseBody) as P
import Rian.Prim (normalize, overflowOps) as Prim
import Rian.TypeStr (splitTopCommas)

-- | A target-pinning construct: its human name, kind, and the targets it kills.
type Blocker = { construct :: String, kind :: String, kills :: Array String }

type Entry = { reach :: Array String, blockers :: Array Blocker }
type Acc = { blockers :: Array Blocker, callees :: Array String }

-- the runtime-discriminator context the union-narrowing rule needs: the sum + struct names.
type Disc = { sumNames :: Array String, structNames :: Array String }

-- the closed target vocabulary, in canonical (sorted) order so reach sets compare by `==`.
targetsAll :: Array String
targetsAll = [ "ex", "js", "jvm", "rs" ]

-- Erlang / Elixir concurrency-or-state modules + functions (ex-only AND native-per-target).
concErl :: Array String
concErl = [ "ets", "dets", "mnesia", "gen_server", "gen_statem", "gen_event", "global", "pg", "pg2", "sys", "supervisor" ]

concErlFun :: Array String
concErlFun = [ "spawn", "spawn_link", "spawn_monitor", "send", "send_after", "start_timer", "monitor", "link" ]

concEx :: Array String
concEx = [ "GenServer", "Task", "Process", "Agent", "Supervisor", "DynamicSupervisor", "Registry", "GenStage", "GenEvent", "Node" ]

-- the JS-wide fixed integers (>2^53, no faithful JS representation): `^(Int|UInt)(64|128)$`.
jsWideInts :: Array String
jsWideInts = [ "Int64", "Int128", "UInt64", "UInt128" ]

-- | Analyze a parsed program: `name/arity → {reach, blockers}` (an assoc list).
analyze :: Prog -> Array (Tuple String Entry)
analyze prog =
  map report facts
  where
  funs = allFuncs prog
  modnames = map _.name prog.mods
  localNames = map _.name funs
  disc = { sumNames: map _.name prog.types, structNames: map _.name prog.structs }

  -- per-function local facts: local reach (vocabulary minus killed targets, or the @external
  -- target set), the local-call callees, and the blockers.
  facts :: Array (Tuple (Tuple String Int) { local :: Array String, callees :: Array String, blockers :: Array Blocker })
  facts = map fact funs

  fact f =
    let
      scanned = scanFunc disc modnames f
      killed = Array.nub (Array.concatMap _.kills scanned.blockers)
      lc =
        if Array.null f.externals then
          { local: difference targetsAll killed, callees: Array.filter (_ `elem` localNames) scanned.callees }
        else
          { local: Array.sort (map fst f.externals), callees: [] }
    in
      Tuple (Tuple f.name (Array.length f.params))
        { local: lc.local, callees: lc.callees, blockers: scanned.blockers }

  table = fixpoint facts (map (\(Tuple n fc) -> Tuple n fc.local) facts)

  report (Tuple (Tuple name arity) fc) =
    Tuple (name <> "/" <> show arity)
      { reach: fromMaybe targetsAll (map snd (Array.find (\(Tuple k _) -> k == Tuple name arity) table))
      -- blockers accumulate prepended (sig set then body scan); reverse to source order.
      , blockers: Array.reverse fc.blockers
      }

allFuncs :: Prog -> Array Func
allFuncs prog = prog.funcs <> Array.concatMap _.funcs prog.mods

-- ── per-function scan: signature pins + clause body/guard scan ──
-- sigBlockers are built in the reference's canonical order (ref/int/width/any/any_op/union/pin);
-- they seed the accumulator, the body scan PREPENDS, and `analyze`'s report reverses to source
-- order — so a multi-blocker function (e.g. Any + Any-in-operator) matches byte-for-byte.
scanFunc :: Disc -> Array String -> Func -> Acc
scanFunc disc modnames f = foldl (scanClause modnames) { blockers: sigBlockers, callees: [] } f.clauses
  where
  sigTypes = Array.mapMaybe identity (map _.ty f.params <> [ f.ret ])
  ref = if any (\p -> p.cap == Ref) f.params then [ refBlocker ] else []
  int = if any (_ == "Int") sigTypes then [ intBlocker ] else []
  width = if any (_ `elem` jsWideInts) sigTypes then [ widthBlocker ] else []
  anyB = if any (mentionsWord "Any") sigTypes then [ anyBlocker ] else []
  anyOp = if anyParamInJvmOp f then [ anyJvmOpBlocker ] else []
  unionK = Array.nub (Array.concatMap (unionKills disc) sigTypes)
  union = if Array.null unionK then [] else [ unionBlocker unionK ]
  pin = if any (\c -> any patHasPin c.pats) f.clauses then [ pinBlocker ] else []
  sigBlockers = ref <> int <> width <> anyB <> anyOp <> union <> pin

scanClause :: Array String -> Acc -> Clause -> Acc
scanClause modnames acc c =
  let
    acc' = maybe acc (\b -> scan modnames acc (coreOf P.parseBody b)) c.body
  in
    maybe acc' (\g -> scan modnames acc' (coreOf P.parse g)) c.guard

-- parse → normalize (`Prim.*` → `__prim_*`, as the reference's `parse_body` does) → Core.
coreOf :: (String -> P.Surface) -> String -> CExpr
coreOf parser src = fromExpr (Prim.normalize (parser src))

-- ── the body walker: classify each node, recurse children ──
-- NOTE: purerl gotchas avoided here — (1) NO array-literal pattern in a function head
-- (purerl Arrays aren't Erlang lists; `[EAtom t, v]` function_clauses), (2) NO fall-through
-- `case`/guard (miscompiles to a crash) — `if`/`else` + a `Maybe` helper instead, (3) an
-- explicit lambda in `foldl` (not the point-free `scan modnames` partial app).
scan :: Array String -> Acc -> CExpr -> Acc
scan modnames acc node@(ETuple elems) =
  case resultPayload elems of
    -- a Result value `{:ok, v}`/`{:error, e}`: pin off `:jvm`, then scan only the payload.
    Just v -> scan modnames (addBlocker resultValueBlocker acc) v
    Nothing -> recurse modnames acc node (childrenOf node)
-- an Erlang FFI call `:mod.fun(args)`: classify, then scan only the args (not the head atom).
scan modnames acc node@(ECall (EDot (EAtom _) _) args) = recurse modnames acc node args
scan modnames acc node = recurse modnames acc node (childrenOf node)

recurse :: Array String -> Acc -> CExpr -> Array CExpr -> Acc
recurse modnames acc node kids = foldl (\a n -> scan modnames a n) (classify modnames acc node) kids

-- the payload of a top-level Result tuple `{:ok, v}`/`{:error, e}`, else `Nothing`.
resultPayload :: Array CExpr -> Maybe CExpr
resultPayload elems = case Array.index elems 0 of
  Just (EAtom t) -> if (t == "ok" || t == "error") && Array.length elems == 2 then Array.index elems 1 else Nothing
  _ -> Nothing

-- per-node classification (the FFI/prim/map blockers + local-call edges).
classify :: Array String -> Acc -> CExpr -> Acc
classify _ acc (ECall (EDot (EAtom m) fun) _) =
  addBlocker (ffi (":" <> m <> "." <> fun) (concErlP m fun)) acc
classify modnames acc (ECall (EDot (EId m) fun) _) =
  if not (pascal m) then acc
  else if m `elem` modnames then acc
  else addBlocker (ffi (m <> "." <> fun) (m `elem` concEx)) acc
classify _ acc (ECall (EId f) _) =
  if f `elem` widePrims then addBlocker widePrimBlocker acc
  else if f == "__prim_str_to_atom" then addBlocker atomPrimBlocker acc
  else if f == "__prim_to_string" then addBlocker toStringPrimBlocker acc
  else addCallee f acc
classify _ acc (EMap pairs) = addBlocker (mapLiteralBlocker pairs) acc
classify _ acc (EMapUpdate _ pairs) = addBlocker (mapUpdateBlocker pairs) acc
classify _ acc _ = acc

widePrims :: Array String
widePrims = Prim.overflowOps

addBlocker :: Blocker -> Acc -> Acc
addBlocker b acc = acc { blockers = [ b ] <> acc.blockers }

addCallee :: String -> Acc -> Acc
addCallee f acc = acc { callees = acc.callees <> [ f ] }

-- direct sub-expressions of a Core node (the scan recursion targets). Patterns hold no
-- sub-`CExpr` that bears FFI, so they contribute nothing.
childrenOf :: CExpr -> Array CExpr
childrenOf = case _ of
  EUnary _ x -> [ x ]
  EBin _ l r -> [ l, r ]
  ECall f args -> [ f ] <> args
  EDot h _ -> [ h ]
  EIf c t e -> [ c, t, e ]
  ECase s arms -> [ s ] <> Array.concatMap armChildren arms
  EWith clauses body arms -> map _.expr clauses <> [ body ] <> Array.concatMap armChildren arms
  EBlock stmts -> Array.concatMap stmtChild stmts
  EList es tail -> es <> Array.fromFoldable tail
  EMap pairs -> Array.concatMap pairChild pairs
  EMapUpdate base pairs -> [ base ] <> Array.concatMap pairChild pairs
  ETuple es -> es
  ELambda _ body -> [ body ]
  ECapture b -> [ b ]
  ECaptureNamed p _ -> [ p ]
  ELabel _ e -> [ e ]
  _ -> [] -- ENum / EStr / EChar / EId / EAtom / ECapArg

armChildren :: CArm -> Array CExpr
armChildren a = Array.fromFoldable a.guard <> [ a.body ]

stmtChild :: CStmt -> Array CExpr
stmtChild (CBind _ e) = [ e ]
stmtChild (CTypedBind _ _ e) = [ e ]
stmtChild (CExprStmt e) = [ e ]

pairChild :: CMapPair -> Array CExpr
pairChild (CMAtom _ v) = [ v ]
pairChild (CMKey k v) = [ k, v ]

-- ── blockers ──
ffi :: String -> Boolean -> Blocker
ffi construct conc = { construct, kind: if conc then "concurrency" else "ffi", kills: [ "js", "jvm", "rs" ] }

concErlP :: String -> String -> Boolean
concErlP m fun = m `elem` concErl || (m == "erlang" && fun `elem` concErlFun)

refBlocker :: Blocker
refBlocker = { construct: "ref capability (&mut)", kind: "capability", kills: [ "ex" ] }

intBlocker :: Blocker
intBlocker = { construct: "Int (arbitrary precision)", kind: "numeric", kills: [ "jvm", "rs" ] }

widthBlocker :: Blocker
widthBlocker = { construct: "fixed-width integer >2^53 (no JS representation)", kind: "numeric", kills: [ "js" ] }

anyBlocker :: Blocker
anyBlocker = { construct: "Any (top type)", kind: "typed", kills: [ "rs" ] }

anyJvmOpBlocker :: Blocker
anyJvmOpBlocker =
  { construct: "Any value in a typed operator (Kotlin `Any` has no operators)", kind: "typed", kills: [ "jvm" ] }

unionBlocker :: Array String -> Blocker
unionBlocker kills = { construct: "value union (A | B)", kind: "typed", kills }

pinBlocker :: Blocker
pinBlocker = { construct: "pin (`^x`)", kind: "pin", kills: [ "rs" ] }

resultValueBlocker :: Blocker
resultValueBlocker = { construct: "Result value (`{:ok,_}`/`{:error,_}`)", kind: "result", kills: [ "jvm" ] }

widePrimBlocker :: Blocker
widePrimBlocker = { construct: "64-bit overflow op (no JS representation)", kind: "numeric", kills: [ "js" ] }

atomPrimBlocker :: Blocker
atomPrimBlocker = { construct: "`Prim.str_to_atom` (atom is BEAM-only)", kind: "atom", kills: [ "js", "jvm", "rs" ] }

toStringPrimBlocker :: Blocker
toStringPrimBlocker = { construct: "`Prim.to_string` (runtime Show — no universal Rust Display)", kind: "prim", kills: [ "rs" ] }

mapLiteralBlocker :: Array CMapPair -> Blocker
mapLiteralBlocker pairs =
  if any computedKey pairs then { construct: "non-atom map key (`%{expr => v}`)", kind: "map", kills: [ "js", "jvm", "rs" ] }
  else { construct: "map literal (`%{…}`)", kind: "map", kills: [ "jvm", "rs" ] }

mapUpdateBlocker :: Array CMapPair -> Blocker
mapUpdateBlocker pairs =
  if any computedKey pairs then { construct: "non-atom map key (`%{base | expr => v}`)", kind: "map", kills: [ "js", "jvm", "rs" ] }
  else { construct: "map update (`%{base | …}`)", kind: "map", kills: [ "jvm", "rs" ] }

computedKey :: CMapPair -> Boolean
computedKey (CMKey _ _) = true
computedKey _ = false

-- ── set ops on canonical (sorted) target arrays ──
intersect :: Array String -> Array String -> Array String
intersect a b = Array.filter (_ `elem` b) a

difference :: Array String -> Array String -> Array String
difference a b = Array.filter (\x -> not (x `elem` b)) a

-- reach(f) = local(f) ∩ ⋂ reach(callee). Name-folded callee = intersection of its arities'
-- reaches (no matching arity imposes no constraint — folds from `targetsAll`).
fixpoint
  :: Array (Tuple (Tuple String Int) { local :: Array String, callees :: Array String, blockers :: Array Blocker })
  -> Array (Tuple (Tuple String Int) (Array String))
  -> Array (Tuple (Tuple String Int) (Array String))
fixpoint facts table =
  let
    next = map (\(Tuple n fc) -> Tuple n (foldl (\acc c -> intersect acc (reachFor table c)) fc.local fc.callees)) facts
  in
    if next == table then table else fixpoint facts next

reachFor :: Array (Tuple (Tuple String Int) (Array String)) -> String -> Array String
reachFor table name =
  foldl intersect targetsAll (map snd (Array.filter (\(Tuple (Tuple n _) _) -> n == name) table))

-- ── type-string helpers ──
pascal :: String -> Boolean
pascal s = case Array.head (CP.toCodePointArray s) of
  Just cp -> cp >= CP.codePointFromChar 'A' && cp <= CP.codePointFromChar 'Z'
  Nothing -> false

-- does a type string name `w` as a whole identifier token (`\bw\b`)?
mentionsWord :: String -> String -> Boolean
mentionsWord w t = w `elem` identTokens t

-- the `[A-Za-z_]\w*` identifier tokens of a string (maximal word runs, trailing run flushed).
identTokens :: String -> Array String
identTokens s =
  let final = foldl step { toks: [], cur: "" } (CP.toCodePointArray s)
  in final.toks <> (if final.cur == "" then [] else [ final.cur ])
  where
  step acc cp =
    if isWordCp cp then acc { cur = acc.cur <> CP.singleton cp }
    else if acc.cur == "" then acc
    else acc { toks = acc.toks <> [ acc.cur ], cur = "" }

isWordCp :: CP.CodePoint -> Boolean
isWordCp cp =
  inR '0' '9' || inR 'a' 'z' || inR 'A' 'Z' || cp == CP.codePointFromChar '_'
  where
  inR lo hi = cp >= CP.codePointFromChar lo && cp <= CP.codePointFromChar hi

-- ── any_op: an `Any`-typed parameter fed to a non-equality operator (Kotlin `Any` has no
-- operators, so it does not compile on JVM; JS is dynamic and runs it). ──
anyParamInJvmOp :: Func -> Boolean
anyParamInJvmOp f =
  not (Array.null anyNames)
    && any (\c -> maybe false (\b -> anyOpNode anyNames (coreOf P.parseBody b)) c.body) f.clauses
  where
  anyNames = map _.name (Array.filter (\p -> p.ty == Just "Any") f.params)

anyOpNode :: Array String -> CExpr -> Boolean
anyOpNode names node = hit || any (anyOpNode names) (childrenOf node)
  where
  hit = case node of
    EBin op l r -> not (op `elem` [ "==", "!=" ]) && (anyOperand names l || anyOperand names r)
    _ -> false

anyOperand :: Array String -> CExpr -> Boolean
anyOperand names (EId n) = n `elem` names
anyOperand _ _ = false

-- ── union: a value-union type `A | B` (canonical `Union(...)`, ADR-0083). Narrowable (every
-- member a DISTINCT runtime discriminator) kills nothing; otherwise (a clash / tvar / nested
-- union) it pins off every target. ──
unionKills :: Disc -> String -> Array String
unionKills disc t = if unionClass disc t == "neither" then targetsAll else []

unionClass :: Disc -> String -> String
unionClass disc t =
  if Str.contains (Str.Pattern "Union(") t then
    case unionMembers t of
      Nothing -> "neither"
      Just members ->
        let discs = map (discriminator disc) members
        in
          if all isJust discs && Array.length (Array.nub discs) == Array.length discs then "narrowable"
          else "neither"
  else "none"

-- the members of a TOP-LEVEL `Union(...)`, or `Nothing` if malformed or nested.
unionMembers :: String -> Maybe (Array String)
unionMembers t = case Str.stripPrefix (Str.Pattern "Union(") t of
  Nothing -> Nothing
  Just rest -> case Str.stripSuffix (Str.Pattern ")") rest of
    Nothing -> Nothing
    Just inner ->
      let members = splitTopCommas inner
      in if any (Str.contains (Str.Pattern "Union(")) members then Nothing else Just members

-- the runtime discriminator class a member narrows under (`Nothing` = a tvar/unknown type).
-- `Char`/`Int*`/`UInt*` share `integer` (a clash); distinct sums/structs are distinguishable.
discriminator :: Disc -> String -> Maybe String
discriminator disc t =
  if t == "Bool" then Just "boolean"
  else if t == "String" then Just "binary"
  else if t == "Char" then Just "integer"
  else if isIntName t then Just "integer"
  else if isFloatName t then Just "float"
  else if t `elem` disc.sumNames then Just ("sum:" <> t)
  else if t `elem` disc.structNames then Just ("struct:" <> t)
  else Nothing

isIntName :: String -> Boolean
isIntName s = digitsAfter "Int" (fromMaybe s (Str.stripPrefix (Str.Pattern "U") s))

isFloatName :: String -> Boolean
isFloatName = digitsAfter "Float"

digitsAfter :: String -> String -> Boolean
digitsAfter prefix s = case Str.stripPrefix (Str.Pattern prefix) s of
  Nothing -> false
  Just rest -> all isDigit (CP.toCodePointArray rest)
  where
  isDigit cp = cp >= CP.codePointFromChar '0' && cp <= CP.codePointFromChar '9'

-- ── pin: a `^x` pin anywhere in a clause-head pattern (Rust lacks the match-guard transform). ──
patHasPin :: P.Pat -> Boolean
patHasPin (P.PPin _) = true
patHasPin (P.PTuple ps) = any patHasPin ps
patHasPin (P.PListP ps tl) = any patHasPin ps || maybe false patHasPin tl
patHasPin (P.PCtor _ ps) = any patHasPin ps
patHasPin (P.PStruct _ ps) = any (\(Tuple _ p) -> patHasPin p) ps
patHasPin (P.PAs _ p) = patHasPin p
patHasPin (P.PMap ps) = any mapPatPin ps
patHasPin _ = false

mapPatPin :: P.MapPatPair -> Boolean
mapPatPin (P.MPAtom _ p) = patHasPin p
mapPatPin (P.MPKey _ p) = patHasPin p

-- | The `rch` parity unit: serialize the reach report (`name/arity reach=… blockers=…`), keyed
-- | order-independent (sorted by function key; reach sorted; blockers in report order).
analyzeSexpr :: String -> String
analyzeSexpr src =
  joinWith "\n" (map serEntry (Array.sortWith fst (analyze (parseToProg src))))
  where
  serEntry (Tuple key e) =
    key <> " reach=" <> joinWith "," e.reach <> " blockers=" <> joinWith "|" (map _.construct e.blockers)
