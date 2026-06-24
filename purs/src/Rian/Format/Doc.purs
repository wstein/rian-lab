-- | A Wadler-style pretty-printing document algebra with Lindig's strict, linear-time renderer
-- | (*Strictly Pretty*, 2000) plus the Prettier extensions (`softline`/`hardline`/`lineSuffix`/
-- | `ifBreak` + break propagation) — the wrapping engine behind `Rian.Format` Tier 2. The PureScript
-- | port of `Rian.Format.Doc` (lib/rian/format/doc.ex), ADR-0084 Phase 9.
-- |
-- | `render doc width` runs Lindig's worklist of `{indent, mode, doc}` items with a bounded `fits`
-- | lookahead, so it is O(document size). A `group` renders flat iff it has no propagated hard break
-- | *and* fits the columns remaining on the line.
module Rian.Format.Doc
  ( Doc(..)
  , empty
  , text
  , nest
  , line
  , softline
  , hardline
  , lineSuffix
  , ifBreak
  , concat
  , concat2
  , join
  , group
  , groupForce
  , render
  , renderScenario
  ) where

import Prelude

import Data.Array (any, filter, intersperse, null, reverse, uncons, (:))
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..))
import Data.String (joinWith)
import Data.String.CodePoints (length) as CP

-- @rian_sig type Doc := Empty | Hardline | Text(String) | Line(String) | Concat(Vec(Doc)) | Nest(Int53, Doc) | Group(Bool, Doc) | LineSuffix(Doc) | IfBreak(Doc, Doc)
data Doc
  = Empty
  | Hardline
  | Text String
  | Line String
  | Concat (Array Doc)
  | Nest Int Doc
  | Group Boolean Doc
  | LineSuffix Doc
  | IfBreak Doc Doc

-- the render mode of a worklist item: a flat (one-line) or a broken (multi-line) group.
data Mode = Flat | Break

derive instance Eq Mode

type Item = { i :: Int, m :: Mode, d :: Doc }

-- ── constructors ──────────────────────────────────────────────────────────
empty :: Doc
empty = Empty

text :: String -> Doc
text = Text

nest :: Int -> Doc -> Doc
nest = Nest

line :: Doc
line = Line " "

softline :: Doc
softline = Line ""

hardline :: Doc
hardline = Hardline

lineSuffix :: Doc -> Doc
lineSuffix = LineSuffix

ifBreak :: Doc -> Doc -> Doc
ifBreak = IfBreak

-- | Concatenate a list of docs (flattening `Empty`).
-- @rian_sig pub def concat(docs val Vec(Doc)) Doc
concat :: Array Doc -> Doc
concat docs = case filter (not <<< isEmpty) docs of
  [] -> Empty
  [ one ] -> one
  many -> Concat many
  where
  isEmpty Empty = true
  isEmpty _ = false

-- | The two-doc concat (`concat/2` in the reference).
-- @rian_sig pub def concat2(a val Doc, b val Doc) Doc
concat2 :: Doc -> Doc -> Doc
concat2 a b = concat [ a, b ]

-- | Join `docs` with `sep` between each.
-- @rian_sig pub def join(sep val Doc, docs val Vec(Doc)) Doc
join :: Doc -> Array Doc -> Doc
join _ [] = Empty
join sep docs = concat (intersperse sep docs)

-- | A group: render flat if it fits, else broken. A group containing a `Hardline` (at any depth) is
-- | permanently broken.
-- @rian_sig pub def group(doc val Doc) Doc
group :: Doc -> Doc
group doc = Group (mustBreak doc) doc

-- | `group` with `force` — must-break regardless of width (the magic trailing comma).
-- @rian_sig pub def groupForce(doc val Doc, force val Bool) Doc
groupForce :: Doc -> Boolean -> Doc
groupForce doc force = Group (force || mustBreak doc) doc

-- ── break propagation (Prettier's propagateBreaks) ────────────────────────
-- true if `doc` transitively contains a hard break, so every enclosing group must render broken.
mustBreak :: Doc -> Boolean
mustBreak Hardline = true
mustBreak (Concat ds) = any mustBreak ds
mustBreak (Nest _ d) = mustBreak d
mustBreak (Group mb _) = mb
mustBreak (LineSuffix d) = mustBreak d
mustBreak (IfBreak b f) = mustBreak b || mustBreak f
mustBreak _ = false

-- ── fits: can the worklist render flat within `w` remaining columns? ──────
-- Lindig's bounded lookahead. A break in `Break` mode (or a `Hardline`) ends the line, so what
-- follows no longer counts — it "fits".
fits :: Int -> Array Item -> Boolean
fits w _ | w < 0 = false
fits w work = case uncons work of
  Nothing -> true
  Just { head: it, tail: rest } -> case it.d of
    Empty -> fits w rest
    Text s -> fits (w - CP.length s) rest
    Concat ds -> fits w (map (\d -> { i: it.i, m: it.m, d }) ds <> rest)
    Nest n d -> fits w ({ i: it.i + n, m: it.m, d } : rest)
    Line s -> case it.m of
      Break -> true
      Flat -> fits (w - CP.length s) rest
    Hardline -> true
    Group true d -> fits w ({ i: it.i, m: Break, d } : rest)
    Group false d -> fits w ({ i: it.i, m: Flat, d } : rest)
    LineSuffix _ -> fits w rest
    IfBreak b f -> case it.m of
      Flat -> fits w ({ i: it.i, m: Flat, d: f } : rest)
      Break -> fits w ({ i: it.i, m: Break, d: b } : rest)

-- ── render ────────────────────────────────────────────────────────────────
-- | Render `doc` to a string within a soft `width` column budget.
-- @rian_sig pub def render(doc val Doc, width val Int53) String
render :: Doc -> Int -> String
render doc width = joinWith "" (reverse (doRender width 0 [ { i: 0, m: Break, d: doc } ] [] []))

-- state: worklist, current column `k`, buffered line-suffix docs (reversed), output (reversed).
doRender :: Int -> Int -> Array Item -> Array Doc -> Array String -> Array String
doRender w k work suffix out = case uncons work of
  Nothing ->
    if null suffix then out else flushSuffix suffix out
  Just { head: it, tail: rest } -> case it.d of
    Empty -> doRender w k rest suffix out
    Text s -> doRender w (k + CP.length s) rest suffix (s : out)
    Concat ds -> doRender w k (map (\d -> { i: it.i, m: it.m, d }) ds <> rest) suffix out
    Nest n d -> doRender w k ({ i: it.i + n, m: it.m, d } : rest) suffix out
    -- a line break in flat mode is just its flat string
    Line s | it.m == Flat -> doRender w (k + CP.length s) rest suffix (s : out)
    -- a line break in break mode: flush deferred suffixes, then newline + indent
    Line _ -> doRender w it.i rest [] (spaces it.i : "\n" : flushSuffix suffix out)
    Hardline -> doRender w it.i rest [] (spaces it.i : "\n" : flushSuffix suffix out)
    -- defer line-suffix content (e.g. a trailing comment) to the next newline
    LineSuffix d -> doRender w k rest (d : suffix) out
    IfBreak b f -> case it.m of
      Flat -> doRender w k ({ i: it.i, m: Flat, d: f } : rest) suffix out
      Break -> doRender w k ({ i: it.i, m: Break, d: b } : rest) suffix out
    -- the crux: choose flat or broken for a group
    Group mustBrk d ->
      let mode = if not mustBrk && fits (w - k) ({ i: it.i, m: Flat, d } : rest) then Flat else Break
      in doRender w k ({ i: it.i, m: mode, d } : rest) suffix out

-- emit buffered line-suffix docs (in insertion order) right before a newline. `suffix` is held
-- reversed; suffix content is always flat (trailing comments).
flushSuffix :: Array Doc -> Array String -> Array String
flushSuffix suffix out =
  if null suffix then out
  else foldl (\acc d -> flatString d : acc) out (reverse suffix)

flatString :: Doc -> String
flatString Empty = ""
flatString (Text s) = s
flatString (Concat ds) = joinWith "" (map flatString ds)
flatString (Nest _ d) = flatString d
flatString (Group _ d) = flatString d
flatString (Line s) = s
flatString Hardline = ""
flatString (LineSuffix d) = flatString d
flatString (IfBreak _ f) = flatString f

spaces :: Int -> String
spaces n = joinWith "" (replicate n " ")
  where
  replicate i s = if i <= 0 then [] else s : replicate (i - 1) s

-- ── parity (`fdoc` stream): build a named scenario doc + render it ──────────
-- | Render a fixed parity scenario by name (mirrors the `doc_scenarios` table in gen_fixtures): each
-- | exercises a slice of the algebra. The name is the only input; both sides build the same `Doc`.
renderScenario :: String -> String
renderScenario name = case name of
  "flat-fits" -> render (group (concat [ text "f(", softline, text "a, b", softline, text ")" ])) 40
  "flat-breaks" -> render (group (concat [ text "f(", softline, text "aaaaaaaaaa, bbbbbbbbbb", softline, text ")" ])) 10
  "nest" -> render (group (nest 2 (concat [ text "[", line, text "x", line, text "y" ]))) 4
  "softline" -> render (group (concat [ text "a", softline, text "b" ])) 1
  "hardline-forces" -> render (group (concat [ text "a", hardline, text "b" ])) 80
  "line-flat-space" -> render (group (concat [ text "a", line, text "b" ])) 80
  "if-break-comma" -> render (group (concat [ text "[", nest 2 (concat [ softline, text "x", ifBreak (text ",") empty ]), softline, text "]" ])) 4
  "if-break-flat" -> render (group (concat [ text "[", text "x", ifBreak (text ",") empty, text "]" ])) 80
  "line-suffix" -> render (group (concat [ text "a", lineSuffix (text " # c"), hardline, text "b" ])) 80
  "join" -> render (join (concat [ text ",", line ]) [ text "a", text "b", text "c" ]) 80
  "nested-groups" -> render (group (concat [ text "{", nest 2 (concat [ line, group (concat [ text "k:", line, text "vvvvvvvvvvvvvvv" ]) ]), line, text "}" ])) 12
  _ -> "unknown-scenario:" <> name
