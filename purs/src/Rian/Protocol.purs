-- | `protocol` / `impl` expansion — the PureScript port of `Rian.Protocol`
-- | (lib/rian/protocol.ex), ADR-0042 part 2 / ADR-0084. A `protocol` names method
-- | signatures; an `impl P for T` supplies their bodies for one concrete type. Both
-- | desugar into ordinary `def`s (the raw-`DefMap`s the rest of the pipeline consumes):
-- |
-- |   * each `impl P for T` method becomes a private `impl_<p>_<t>_<m>` function;
-- |   * each protocol method becomes a **guarded dispatcher** with one clause per impl,
-- |     selecting the impl by the first argument's runtime shape — a type-test BIF for a
-- |     primitive, the constructor tag for a sum, the `:__struct__` tag for a struct.
-- |
-- | The runtime discriminator (`Rian.Coherence.guardFor`) is shared with the coherence
-- | shared-guard rule, so rule and codegen agree by construction (ADR-0061 §5). Coherence
-- | itself (`Rian.Coherence`) is consulted before codegen.
-- |
-- | Parity (`pex` stream): `expandSexpr` parses a single scope, expands its protocols/impls,
-- | and serializes the generated `DefMap`s — mirroring `gen_fixtures`'s `expand_def_s`.
module Rian.Protocol
  ( DefMap
  , expand
  , expandSexpr
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), maybe)
import Data.String (Pattern(..)) as Str
import Data.String as Str
import Data.String.CodePoints as CP
import Data.String.Common (joinWith)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafeCrashWith)
import Rian.Coherence (Registry, guardFor, registry, violations)
import Rian.Decl (parseToProg)
import Rian.IR (ImplDecl, ImplMethod, Method, Protocol, Struct, Type)
import Rian.TypeStr (splitTopCommas)

-- | A generated raw `def`: a guarded dispatcher head/clause, or a mangled impl method.
type DefMap =
  { dispatch :: String -- "dispatcher" | "impl"
  , name :: String
  , params :: String
  , ret :: Maybe String
  , guard :: Maybe String
  , body :: Maybe String
  , pub :: Boolean
  , tvars :: Array String
  , synthetic :: Boolean
  }

-- | Expand `protocols` + `impls` into the dispatcher / `impl_*` def stream. `targets` is the
-- | scope's `@targets` (`Nothing` = all). Crashes on a coherence violation (mirrors `check!`).
expand :: Array Protocol -> Array ImplDecl -> Array Type -> Array Struct -> Maybe (Array String) -> Array DefMap
expand protocols impls types structs targets =
  case Array.head (violations protocols impls reg targets) of
    Just vio -> unsafeCrashWith ("coherence violation: " <> vio.rule <> " " <> vio.proto <> " " <> vio.ty)
    Nothing -> dispatchers <> methods
  where
  reg = registry types structs
  dispatchers = Array.concatMap (\p -> Array.concatMap (\sig -> dispatcher p.name sig impls reg) p.methods) protocols
  methods = Array.concatMap (implMethods protocols) impls

-- ── dispatcher: one guarded clause per impl ──
dispatcher :: String -> Method -> Array ImplDecl -> Registry -> Array DefMap
dispatcher proto sig impls reg =
  if Array.null clauses then []
  else [ sigMap ] <> clauses
  where
  arity = Array.length (splitTopCommas sig.params)
  vars = map (\i -> "v" <> show i) (Array.range 0 (arity - 1))
  pat = joinWith ", " vars
  protoImpls = Array.filter (\i -> i.proto == proto) impls

  clauses = map clauseFor protoImpls
  clauseFor i =
    { dispatch: "dispatcher"
    , name: sig.name
    , params: pat
    , ret: Nothing
    , guard: Just (guardFor reg i.ty proto)
    , body: Just (mangle proto i.ty sig.name <> "(" <> pat <> ")")
    , pub: false
    , tvars: []
    , synthetic: false
    }

  -- a protocol's associated types (each impl's bound keys, ADR-0074) join `Self` as the
  -- dispatcher's type variables, so a `Self`/`Elem`-mentioning return reads as polymorphic.
  assocTvars = Array.nub (Array.concatMap (\i -> map fst i.assoc) protoImpls)
  sigMap =
    { dispatch: "dispatcher"
    , name: sig.name
    , params: dispatcherParams sig.params vars
    , ret: sig.ret
    , guard: Nothing
    , body: Nothing
    , pub: true
    , tvars: Array.nub ([ "Self" ] <> assocTvars)
    , synthetic: true
    }

-- the dispatcher signature keeps the protocol's parameter *types* but renames the params to
-- the dispatch vars (`v0`, `v1`, …).
dispatcherParams :: String -> Array String -> String
dispatcherParams sigParams vars =
  joinWith ", " (Array.zipWith (\p v -> v <> " " <> paramType p) (splitTopCommas sigParams) vars)

-- ── impl methods: mangled single-clause functions ──
implMethods :: Array Protocol -> ImplDecl -> Array DefMap
implMethods protocols impl = map mk impl.methods
  where
  protoMethods = maybe [] _.methods (Array.find (\p -> p.name == impl.proto) protocols)

  mk :: ImplMethod -> DefMap
  mk m =
    let
      sig = Array.find (\s -> s.name == m.name) protoMethods
      sigParams = maybe "" _.params sig
      sigRet = sig >>= _.ret
      names = map Str.trim (splitTopCommas m.params)
      types = map paramType (splitTopCommas sigParams)
      params = joinWith ", " (Array.zipWith (\n t -> n <> " " <> resolve t) names types)
    in
      { dispatch: "impl"
      , name: mangle impl.proto impl.ty m.name
      , params
      , ret: map resolve sigRet
      , guard: m.guard
      , body: m.body
      , pub: false
      , tvars: []
      , synthetic: false
      }
    where
    -- resolve `Self` (-> the impl type) and each associated type (`Elem` -> its binding) in a
    -- declared type string (ADR-0074 W1) so the impl method's signature matches its body.
    resolve t = substAssoc impl.assoc (substSelf impl.ty t)

-- ── helpers ──
mangle :: String -> String -> String -> String
mangle proto ty method = "impl_" <> Str.toLower proto <> "_" <> Str.toLower ty <> "_" <> method

-- the type of a `name Type` (or bare `Type`) parameter — the last whitespace token.
paramType :: String -> String
paramType p = maybe "" identity (Array.last (Array.filter (_ /= "") (Str.split (Str.Pattern " ") (Str.trim p))))

substSelf :: String -> String -> String
substSelf ty t = wordReplace "Self" ty t

substAssoc :: Array (Tuple String (Maybe String)) -> String -> String
substAssoc assoc t = Array.foldl step t assoc
  where
  step acc (Tuple a (Just conc)) = wordReplace a conc acc
  step acc (Tuple _ Nothing) = acc

-- replace whole-word occurrences of `target` with `repl` (the `\b…\b` regex the reference uses):
-- a "word" is a maximal run of `[A-Za-z0-9_]`, so `Self` in `Vec(Self)` is replaced but not in `MySelf`.
wordReplace :: String -> String -> String -> String
wordReplace target repl input =
  let
    final = Array.foldl go { out: "", cur: "" } (CP.toCodePointArray input)
  in
    final.out <> emit final.cur
  where
  emit w = if w == target then repl else w
  go acc cp =
    if isWordCp cp then acc { cur = acc.cur <> CP.singleton cp }
    else { out: acc.out <> emit acc.cur <> CP.singleton cp, cur: "" }

isWordCp :: CP.CodePoint -> Boolean
isWordCp cp =
  inRange '0' '9' || inRange 'a' 'z' || inRange 'A' 'Z' || cp == CP.codePointFromChar '_'
  where
  inRange lo hi = cp >= CP.codePointFromChar lo && cp <= CP.codePointFromChar hi

-- | The `pex` parity unit: parse a single scope, expand its protocols + (local-protocol)
-- | impls, and serialize the generated `DefMap`s.
expandSexpr :: String -> String
expandSexpr src =
  joinWith "\n" (map defSexpr (expand protos impls prog.types prog.structs Nothing))
  where
  prog = parseToProg src
  protos = prog.protocols
  impls = Array.filter (\i -> Array.any (\p -> p.name == i.proto) protos) prog.implDecls

defSexpr :: DefMap -> String
defSexpr d =
  "(" <> d.dispatch <> " " <> d.name
    <> " params=" <> d.params
    <> maybe "" (\r -> " ret=" <> r) d.ret
    <> maybe "" (\g -> " when=" <> g) d.guard
    <> maybe "" (\b -> " body=" <> b) d.body
    <> " pub=" <> show d.pub
    <> " tvars=" <> joinWith "," d.tvars
    <> (if d.synthetic then " syn" else "")
    <> ")"
