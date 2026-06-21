# Generates purs/test/fixtures/parity.fixtures — the parity oracle for the PureScript port
# (ADR-0084). Runs the Elixir reference (Lexer/TypeStr/Pratt/Core) over per-module corpora and
# writes, per record: `<stream>\t<hex(source)>\t<canonical>`. The Erlang harness
# (purs/test/parity.erl, run by scripts/purerl-build.sh) re-runs each source through the
# purerl build and asserts the same canonical string. Run from the repo root:
# `mix run purs/test/gen_fixtures.exs`.
defmodule Canon do
  # Canonical, language-agnostic serialization of a token list. String payloads are
  # lowercase hex of their UTF-8 bytes so the line is delimiter-safe and byte-identical
  # to the Erlang harness's serializer.
  def tokens(toks), do: Enum.map_join(toks, "|", &tok/1)

  defp tok({:nl}), do: "nl"
  defp tok({:lparen}), do: "lparen"
  defp tok({:rparen}), do: "rparen"
  defp tok({:lbracket}), do: "lbracket"
  defp tok({:rbracket}), do: "rbracket"
  defp tok({:lbrace}), do: "lbrace"
  defp tok({:rbrace}), do: "rbrace"
  defp tok({:mapopen}), do: "mapopen"
  defp tok({:bitopen}), do: "bitopen"
  defp tok({:bitclose}), do: "bitclose"
  defp tok({:comma}), do: "comma"
  defp tok({:semi}), do: "semi"
  defp tok({:str, s}), do: "str:" <> hex(s)
  defp tok({:char, n}), do: "char:" <> Integer.to_string(n)
  defp tok({:num, s}), do: "num:" <> hex(s)
  defp tok({:op, s}), do: "op:" <> hex(s)
  defp tok({:kw, s}), do: "kw:" <> hex(s)
  defp tok({:id, s}), do: "id:" <> hex(s)
  defp tok({:annot, s}), do: "annot:" <> hex(s)
  defp tok({:comment, s}), do: "comment:" <> hex(s)
  defp tok({:heredoc, s}), do: "heredoc:" <> hex(s)
  defp tok({:istr, parts}), do: "istr:" <> Enum.map_join(parts, ",", &part/1)

  defp part({:lit, s}), do: "lit=" <> hex(s)
  defp part({:hole, s}), do: "hole=" <> hex(s)

  # a Vec(String) result → a `,`-joined list of hex'd elements.
  def strlist(list), do: Enum.map_join(list, ",", &hex/1)

  def hex(s), do: Base.encode16(s, case: :lower)
end

# Canonical s-expression for the typed Core (Rian.Core.from_expr/from_pat output) — the `cor`
# parity oracle. Mirrors `coreSexpr`/`corePatSexpr` in purs/src/Rian/Core.purs byte-for-byte.
defmodule CoreCanon do
  alias Rian.Core.{ENum, EStr, EChar, EId, EAtom, EUnary, EBin, ECall, EDot, EIf, ECase}
  alias Rian.Core.{EWith, EBlock, EList, EMap, ETuple, ELambda, ECapture, ECaptureNamed}
  alias Rian.Core.{ECapArg, ELabel, PWild, PVar, PLit, PChar, PAtom, PTuple, PList, PCtor}
  alias Rian.Core.{PAs, PStruct, PMap, PPin, PTyped}

  def expr(%ENum{text: t}), do: t
  def expr(%EStr{value: s}), do: "\"#{s}\""
  def expr(%EChar{value: c}), do: "?#{c}"
  def expr(%EId{name: x}), do: x
  def expr(%EAtom{name: a}), do: ":" <> a
  def expr(%EUnary{op: op, arg: x}), do: "(#{op} #{expr(x)})"
  def expr(%EBin{op: op, left: l, right: r}), do: "(#{op} #{expr(l)} #{expr(r)})"

  def expr(%ECall{fun: f, args: args}),
    do: "(call #{expr(f)}#{Enum.map_join(args, "", fn a -> " " <> expr(a) end)})"

  def expr(%EDot{head: h, name: n}), do: "(. #{expr(h)} #{n})"
  def expr(%EIf{cond: c, then: t, else: e}), do: "(if #{expr(c)} #{expr(t)} #{expr(e)})"

  def expr(%ECase{scrut: s, arms: arms}),
    do:
      "(case #{expr(s)}#{Enum.map_join(arms, "", fn {p, _g, b} -> " (#{pat(p)} -> #{expr(b)})" end)})"

  def expr(%EWith{clauses: cls, body: body, els: els}) do
    cs = Enum.map_join(cls, " ", fn {p, e} -> "(<- #{pat(p)} #{expr(e)})" end)

    e =
      if els == [],
        do: "",
        else:
          " (else#{Enum.map_join(els, "", fn {p, _g, b} -> " (#{pat(p)} -> #{expr(b)})" end)})"

    "(with #{cs} #{expr(body)}#{e})"
  end

  def expr(%EBlock{stmts: stmts}),
    do: "(block#{Enum.map_join(stmts, "", fn s -> " " <> stmt(s) end)})"

  def expr(%EList{elems: es, tail: :close}), do: "[#{Enum.map_join(es, " ", &expr/1)}]"
  def expr(%EList{elems: es, tail: t}), do: "[#{Enum.map_join(es, " ", &expr/1)} | #{expr(t)}]"
  def expr(%EMap{pairs: ps}), do: "%{#{Enum.map_join(ps, " ", &map_pair/1)}}"
  def expr(%ETuple{elems: es}), do: "{#{Enum.map_join(es, " ", &expr/1)}}"

  def expr(%ELambda{params: ps, body: b}),
    do: "(lambda (#{Enum.map_join(ps, " ", fn {n, _} -> n end)}) #{expr(b)})"

  def expr(%ECapture{body: b}), do: "(& #{expr(b)})"
  def expr(%ECaptureNamed{path: p, arity: a}), do: "(&/ #{expr(p)} #{a})"
  def expr(%ECapArg{n: n}), do: "&#{n}"
  def expr(%ELabel{name: n, expr: e}), do: "#{n}: #{expr(e)}"

  defp map_pair({{:key, k}, v}), do: "#{expr(k)} => #{expr(v)}"
  defp map_pair({k, v}), do: "#{k}: #{expr(v)}"

  defp stmt({:bind, n, e}), do: "(:= #{n} #{expr(e)})"
  defp stmt({:typed_bind, n, t, e}), do: "(:= #{n} #{t} #{expr(e)})"
  defp stmt({:expr, e}), do: expr(e)

  def pat(%PWild{}), do: "_"
  def pat(%PVar{name: x}), do: x
  def pat(%PLit{value: v}) when is_binary(v), do: "\"#{v}\""
  def pat(%PLit{value: v}), do: to_string(v)
  def pat(%PChar{value: cp}), do: "?#{cp}"
  def pat(%PAtom{name: a}), do: ":" <> a
  def pat(%PTuple{elems: ps}), do: "{#{Enum.map_join(ps, ", ", &pat/1)}}"
  def pat(%PList{elems: ps, tail: :close}), do: "[#{Enum.map_join(ps, ", ", &pat/1)}]"
  def pat(%PList{elems: ps, tail: t}), do: "[#{Enum.map_join(ps, ", ", &pat/1)} | #{pat(t)}]"
  def pat(%PCtor{ctor: n, args: []}), do: n
  def pat(%PCtor{ctor: n, args: args}), do: "#{n}(#{Enum.map_join(args, ", ", &pat/1)})"
  def pat(%PAs{name: n, pat: p}), do: "(@ #{n} #{pat(p)})"

  def pat(%PStruct{name: n, fields: fs}),
    do: "#{n}(#{Enum.map_join(fs, ", ", fn {k, p} -> "#{k}: #{pat(p)}" end)})"

  def pat(%PMap{pairs: ps}), do: "%{#{Enum.map_join(ps, ", ", &map_pat_pair/1)}}"

  # pins + type-patterns are excluded from the Core corpus (no shared renderer / no reference clause).
  def pat(%PPin{}), do: raise("pin pattern is excluded from the Core parity corpus")
  def pat(%PTyped{}), do: raise("type-pattern has no sexpr clause")

  defp map_pat_pair({{:key, k}, p}), do: "#{expr(k)} => #{pat(p)}"
  defp map_pat_pair({k, p}), do: "#{k}: #{pat(p)}"
end

# Canonical s-expression for the declaration IR (Rian.Decl assemble → Prog) — the `dcl`
# parity oracle. Mirrors `progSexpr`/`typeSexpr`/… in purs/src/Rian/Decl.purs byte-for-byte.
defmodule DeclCanon do
  alias Rian.IR.{Type, Variant, Field, Struct, Func, Param, Clause, Mod, Const, Use}

  def prog(p) do
    types = Enum.map(Map.get(p, :types, []), &type_s/1)
    structs = Enum.map(Map.get(p, :structs, []), &struct_s/1)
    funcs = Enum.map(Map.get(p, :funcs, []), &func_s/1)
    mods = Enum.map(Map.get(p, :mods, []), &mod_s/1)
    Enum.join(types ++ structs ++ funcs ++ mods, "\n")
  end

  defp mod_s(%Mod{name: n, uses: us, types: ts, structs: ss, consts: cs, funcs: fs, doc: doc}) do
    "(mod #{n}#{doc_flag(doc)}" <>
      Enum.map_join(us, "", fn u -> " " <> use_s(u) end) <>
      Enum.map_join(ts, "", fn t -> " " <> type_s(t) end) <>
      Enum.map_join(ss, "", fn s -> " " <> struct_s(s) end) <>
      Enum.map_join(cs, "", fn c -> " " <> const_s(c) end) <>
      Enum.map_join(fs, "", fn f -> " " <> func_s(f) end) <> ")"
  end

  defp use_s(%Use{path: path, names: names}),
    do: "(use #{path}#{Enum.map_join(names, "", fn n -> " " <> n end)})"

  defp const_s(%Const{name: n, type: t, value: v, pub?: pub, doc: doc}),
    do: "(const #{n}#{pub_flag(pub)}#{doc_flag(doc)} #{const_ty(t)} #{v})"

  defp const_ty(nil), do: "_infer"
  defp const_ty(t), do: t

  defp func_s(%Func{
         name: n,
         params: ps,
         ret: ret,
         clauses: cs,
         pub?: pub,
         tvars: tvars,
         bounds: bounds,
         doc: doc
       }) do
    tv = Enum.map_join(tvars, "", fn t -> " tvar=#{t}" end)

    bd =
      Enum.map_join(Enum.sort(Map.to_list(bounds)), "", fn {bn, bs} ->
        " bound=#{bn}:#{Enum.join(bs, "+")}"
      end)

    "(func #{n}#{pub_flag(pub)}#{doc_flag(doc)}#{tv}#{bd}#{ret_flag(ret)} (params#{Enum.map_join(ps, "", &param_s/1)})#{Enum.map_join(cs, "", &clause_s/1)})"
  end

  defp ret_flag(nil), do: ""
  defp ret_flag(r), do: " ret=#{r}"
  defp param_s(%Param{name: n, type: t, cap: cap}), do: " (param #{n} #{cap} #{ty_of(t)})"
  defp ty_of(:infer), do: "_infer"
  defp ty_of(t), do: t

  defp clause_s(%Clause{pats: ps, body: body, guard: guard}),
    do: " (clause (#{Enum.map_join(ps, " ", &surf_pat/1)})#{guard_of(guard)}#{body_of(body)})"

  defp guard_of(nil), do: ""
  defp guard_of(g), do: " when=#{g}"
  defp body_of(nil), do: ""
  defp body_of(b), do: " body=#{b}"

  # surface-pattern renderer — mirrors `sexprPat` in Pratt.purs (the reference's private one).
  defp surf_pat(:wild), do: "_"
  defp surf_pat({:lit, v}) when is_binary(v), do: "\"#{v}\""
  defp surf_pat({:lit, v}), do: to_string(v)
  defp surf_pat({:char_lit, cp}), do: "?#{cp}"
  defp surf_pat({:atom, a}), do: ":#{a}"
  defp surf_pat({:var, x}), do: x
  defp surf_pat({:tuple, ps}), do: "{#{Enum.map_join(ps, ", ", &surf_pat/1)}}"
  defp surf_pat({:list, ps, :close}), do: "[#{Enum.map_join(ps, ", ", &surf_pat/1)}]"

  defp surf_pat({:list, ps, {:tail, t}}),
    do: "[#{Enum.map_join(ps, ", ", &surf_pat/1)} | #{surf_pat(t)}]"

  defp surf_pat({:as, n, p}), do: "(@ #{n} #{surf_pat(p)})"
  defp surf_pat({:ctor, n, []}), do: n
  defp surf_pat({:ctor, n, args}), do: "#{n}(#{Enum.map_join(args, ", ", &surf_pat/1)})"

  defp surf_pat({:struct, n, fields}),
    do: "#{n}(#{Enum.map_join(fields, ", ", fn {k, p} -> "#{k}: #{surf_pat(p)}" end)})"

  defp surf_pat({:map, fields}),
    do: "%{#{Enum.map_join(fields, ", ", fn {k, p} -> "#{k}: #{surf_pat(p)}" end)}}"

  defp type_s(%Type{name: n, variants: vs, pub?: pub, doc: doc}),
    do: "(type #{n}#{pub_flag(pub)}#{doc_flag(doc)}#{Enum.map_join(vs, "", &variant_s/1)})"

  defp struct_s(%Struct{name: n, fields: fs, pub?: pub, doc: doc}),
    do: "(struct #{n}#{pub_flag(pub)}#{doc_flag(doc)}#{Enum.map_join(fs, "", &field_s/1)})"

  defp variant_s(%Variant{ctor: c, fields: fs}),
    do: " (variant #{c}#{Enum.map_join(fs, "", &field_s/1)})"

  defp field_s(%Field{label: l, type: t}), do: " (field #{label_of(l)} #{t})"
  defp label_of(nil), do: "_"
  defp label_of(l), do: l
  defp pub_flag(true), do: " pub"
  defp pub_flag(false), do: ""
  defp doc_flag(nil), do: ""
  defp doc_flag(d), do: " doc=#{d}"
end

alias Rian.Lexer
alias Rian.TypeStr
alias Rian.Pratt
alias Rian.Core
alias Rian.Decl

# Rian.Decl corpus (data-type declarations: type / struct, with @doc / pub / field caps /
# union-type fields / multi-line). Excludes def/mod/const/alias/range/opaque/protocol/macro.
decl_corpus = [
  "type Color := Red | Green | Blue",
  "type Shape := Circle(r Float64) | Square(s Float64)",
  "type Tree := Leaf | Node(left Tree, value Int53, right Tree)",
  "type Opt := None | Some(value Int53)",
  "pub type Dir := North | South | East | West",
  "type T := A(x Int53 | String) | B",
  "struct Point(x Int53, y Int53)",
  "struct Empty",
  "struct Pair(a String, b Int53)",
  "pub struct Vec2(x Float64, y Float64)",
  "struct Buf(data iso Vec(Int53))",
  "struct Ref(item val Shape)",
  "type Maybe := Nothing | Just(val String)",
  "@doc \"a color\"\ntype Hue := Warm | Cool",
  "type Long :=\n  Red |\n  Green |\n  Blue",
  "struct Nested(m Map(String, Vec(Int53)), n Int53)",
  # def: single-clause :=, typed/infer/parametric/structural params, pub, guard, forall, multi-clause
  "def add(x Int64, y Int64) Int64 := x + y",
  "def id(x) := x",
  "def pi() Float64 := 3.14",
  "pub def double(n Int53) Int53 := n * 2",
  "def head(xs Vec(Int53)) Int53 := first(xs)",
  "def first({a, b}) := a",
  "def car([h | t]) := h",
  "def unwrap(Some(x)) := x",
  "def apply(f, x) := f(x)",
  "def answer() Int53 := 42",
  "def cmp(a Int53, b Int53) Bool when a > b := true",
  "def identity(x T) T forall T := x",
  "def both(a T, b U) Bool forall T, U := true",
  "def store(data iso Vec(Int53)) Int53 := len(data)",
  "def max2(a Int64, b Int64) Int64\ndef max2(a, b) when a >= b := a\ndef max2(a, b) := b",
  # stage 3: mod / const / use / alias
  "mod Math do\npub const PI Float64 := 3.14\npub def double(n Int53) Int53 := n * 2\nend",
  "mod Geo do\ntype Shape := Circle(r Float64) | Square(s Float64)\nstruct Point(x Int53, y Int53)\nend",
  "mod M do\nuse Std\nuse List.(map, filter)\nconst N Int53 := 10\nend",
  "mod Empty do\nend",
  "mod C do\nconst X := 42\nconst S := \"hi\"\nend",
  "mod D do\n@doc \"the answer\"\npub const ANSWER Int53 := 42\nend",
  "alias Id := Int53\nstruct Box(item Id)",
  "alias Pair := Tuple(Int53, Int53)\ndef swap(p Pair) Pair := p",
  "alias A := Int53\nalias B := A\nstruct S(x B)",
  "alias Name := String\nmod U do\nstruct Person(name Name, age Int53)\nend"
]

# Rian.Prim corpus: `Prim.<name>(args)` → `__prim_<name>(args)` and bare `panic(msg)`.
# Oracle = Pratt.parse_sexpr (which already applies Prim.normalize inside `parse`); the PS
# side composes Prim.normalize. Excludes unknown `Prim.x` (raises on both sides).
prim_corpus = [
  "Prim.char_code(c)",
  "Prim.str_concat(a, b)",
  "Prim.str_concat_all(parts)",
  "Prim.map_get(m, k)",
  "Prim.wrapping_add(a, b)",
  "Prim.panic(msg)",
  "panic(msg)",
  "panic(a, b)",
  "f(Prim.char_code(c))",
  "x + Prim.char_code(c)",
  "Str.chars(s)",
  "[Prim.char_code(c), x]",
  "if c do Prim.panic(m) else x end"
]

# Rian.Core corpus (Phase 2): exercises from_expr/from_pat + the desugarings (pipe `|>` →
# call, range `..` → List.seq, comprehension → flat_map). Excludes pins, pattern generators,
# interpolation, bitstrings, map update (no shared Core oracle / staged).
core_corpus = [
  "a + b",
  "a |> f(b)",
  "x |> f",
  "1 .. 10",
  "n - 1 .. m + 1",
  "f(a, b)",
  "M.f(x)",
  "a.b.c",
  "[1, 2, 3]",
  "[h | t]",
  "{1, 2}",
  "%{a: 1, b: 2}",
  ~S|%{"k" => v}|,
  ":ok",
  "if c do a else b end",
  "if c do a end",
  "case x do 1 -> a\n_ -> b end",
  "case t do {a, b} -> a\n_ -> 0 end",
  "case r do Ok(v) -> v\nErr(e) -> e end",
  "case xs do [] -> 0\n[h | t] -> h end",
  "case p do Point(x: a, y: b) -> a\n_ -> 0 end",
  "case v do n @ Foo(x) -> n\n_ -> v end",
  "case w do \"hi\" -> 1\n_ -> 0 end",
  "case n do -1 -> a\n0 -> b\n_ -> c end",
  "case m do %{a: x} -> x\n_ -> 0 end",
  "(x) -> x + 1",
  "(x, y) -> x",
  "for x <- xs do x + 1 end",
  "for x <- xs, x > 0 do x end",
  "for x <- xs, y <- ys do x + y end",
  "with Ok(x) <- r do x end",
  "with Ok(x) <- r do x else Err(e) -> e end",
  "&foo/1",
  "&(&1 + &2)",
  "Point(x: 1, y: 2)",
  "if c do x := 1; x + 2 end",
  "if c do x Int64 := 5; x end"
]

# Pratt expression-core corpus (ADR-0084 Phase 3, stage 1). Scoped to the ported forms —
# no if/case/with/for/lambda/blocks/patterns/bitstrings/interpolation/map-update — and
# Prim-free, so `parse` runs without `Rian.Prim.normalize` changing anything.
pratt_corpus = [
  "a + b",
  "a + b * c",
  "a * b + c",
  "a - b - c",
  "a <> b <> c",
  "a == b",
  "-a",
  "not b",
  "- a + b",
  "n - 1 .. m + 1",
  "a and b or c",
  "a |> f(b)",
  "f(x)",
  "f(x, y)",
  "M.f(x)",
  "a.b.c",
  "f(x)(y)",
  "[]",
  "[1, 2, 3]",
  "[h | t]",
  "[a, b | rest]",
  "{}",
  "{1, 2}",
  "(a)",
  "(a, b)",
  "(a, b, c)",
  "%{}",
  "%{a: 1, b: 2}",
  ~S|%{"k" => v, "j" => w}|,
  "%{a: 1, b: 2 + 3}",
  ":ok",
  "Foo.bar",
  "Point(x: 1, y: 2)",
  "&foo/1",
  "&Mod.fun/2",
  "&(&1 + &2)",
  "f(&1, b)",
  "'A' == c",
  "1_000 + 2",
  "1e9",
  "x",
  # if / case / lambda / blocks + patterns (stage 1).
  # NB: case ARMS are newline-separated (the lexer strips the newline); `;` is the
  # block-statement separator *within* an arm/`do` body, not an arm separator.
  "if c do a else b end",
  "if c do a end",
  "if x > 0 do pos else neg end",
  "case x do 1 -> a\n2 -> b end",
  "case x do n when n > 0 -> a\n_ -> b end",
  "case t do {a, b} -> a\n_ -> 0 end",
  "case xs do [] -> 0\n[h | t] -> h end",
  "case r do Ok(v) -> v\nErr(e) -> e end",
  "case s do :ok -> 1\n:error -> 0 end",
  "case p do Point(x: a, y: b) -> a\n_ -> 0 end",
  "case v do n @ Foo(x) -> n\n_ -> v end",
  "case v do ^expected -> 1\n_ -> 0 end",
  "case m do %{a: x} -> x\n_ -> 0 end",
  "case w do \"hi\" -> 1\n_ -> 0 end",
  "case n do -1 -> a\n0 -> b\n_ -> c end",
  "(x) -> x + 1",
  "(x, y) -> x",
  "(x Int) -> x",
  "() -> 0",
  "(n) -> if n > 0 do n else 0 end",
  "if c do x := 1; x + 2 end",
  "if c do x Int64 := 5; x end",
  "case xs do [h | t] -> y := h; y + 1\n_ -> 0 end",
  # stage 2a: with / for / string interpolation
  "with Ok(x) <- r do x end",
  "with a <- f(x), b <- g(a) do a + b end",
  "with Ok(x) <- r do x else Err(e) -> e end",
  "for x <- xs do x + 1 end",
  "for x <- xs, x > 0 do x end",
  "for {a, b} <- pairs do a end",
  "for x <- xs, y <- ys do x + y end",
  ~S|"a${b}c"|,
  ~S|"${x + 1}"|,
  ~S|"sum=${a + b}!"|,
  ~S|"${f(x)}"|
]

# Type-string corpus for Rian.TypeStr (split_top_commas / split_top_pipes / normalize).
typestr_corpus = [
  "",
  "String",
  "String, Vec(Int64)",
  "Map(K, V), Bool",
  "Fn(A, B), C",
  "Map(K, Vec(V)), Result(T, E), Bool",
  " Int53 ,  String ",
  "Vec(Int53)",
  "Int53 | String",
  "B | A | B",
  "Vec(Int) | Str | Int53",
  "Union(B, A)",
  "Union(Int53, String) | Bool",
  "(A | B) | C",
  "Result(Vec(T), E) | Nil",
  "Map(K, V)"
]

# Sources that lex successfully (error cases are covered by the Elixir suite).
corpus = [
  "a + b",
  "if c do a else b end",
  "empty?",
  "gate!",
  "Reach.gate!(prog)",
  "a != b",
  "a!=b",
  "n @ p",
  "@doc",
  "1_000",
  "3.14",
  "1e9",
  "1E9",
  "1.5e-3",
  "6.022e23",
  "0xff",
  ~s("hi"),
  ~S|"a\"b"|,
  ~S|"a\\b"|,
  ~S|"line\nbreak"|,
  ~S|"tab\there"|,
  ~S|f("say \"hi\"")|,
  ~S|"\a\b\d\e\f\r\s\v\0"|,
  ~S|"\x41"|,
  ~S|"\x7"|,
  ~S|"\u{e9}"|,
  ~S|"é"|,
  ~S|"\u{1F600}"|,
  ~S|"café"|,
  "a and not b",
  "'A'",
  "'+'",
  "' '",
  "c == '0'",
  ~S('\n'),
  ~S('\t'),
  ~S('\\'),
  ~S('\''),
  ~S('\0'),
  "'\\u{1F600}'",
  "'é'",
  "\n\na\n\n\nb\n\n",
  "def case when type struct alias mod pub const macro use",
  "a # ignored\nb",
  "a # trailing comment, no newline",
  "# whole-line comment, no newline",
  "def area(s val Shape) Float64\n  case s do\n    Circle(r) -> pi * r * r\n  end\nend\n",
  "%{a: 1, end: 2}",
  "<<1, 2>>",
  ":==",
  ":<>",
  ":and",
  "a :: b",
  "x := 2",
  ~S|"a${b}c"|,
  ~S|"${x + 1}"|,
  ~S|"$5.00"|,
  ~S|"pre${ %{k: v} }post"|,
  "\"\"\"hi\"\"\"",
  "\"\"\"\"\"\""
]

# Sources for detokenize round-trips (rendered back to a re-lexable string).
detok_corpus = [
  "a + b",
  "'A'",
  ~S('\n'),
  ~S('\t'),
  ~S('\r'),
  ~S('\0'),
  ~S|"a\"b"|,
  ~S|"a\\b"|,
  ~S|"a\nb"|,
  "@doc",
  ":and",
  "x := 2"
]

lines =
  Enum.flat_map(corpus, fn src ->
    [
      "tok\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.tokenize(src))}",
      "expr\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.expr_tokens(src))}",
      "triv\t#{Canon.hex(src)}\t#{Canon.tokens(Lexer.tokenize_trivia(src))}"
    ]
  end) ++
    Enum.flat_map(detok_corpus, fn src ->
      [
        "detok\t#{Canon.hex(src)}\t#{Canon.hex(Lexer.detokenize(Lexer.tokenize(src)))}",
        "detok;\t#{Canon.hex(src)}\t#{Canon.hex(Lexer.detokenize(Lexer.tokenize(src), ";"))}"
      ]
    end) ++
    Enum.flat_map(typestr_corpus, fn s ->
      [
        "tsc\t#{Canon.hex(s)}\t#{Canon.strlist(TypeStr.split_top_commas(s))}",
        "tsp\t#{Canon.hex(s)}\t#{Canon.strlist(TypeStr.split_top_pipes(s))}",
        "tsn\t#{Canon.hex(s)}\t#{Canon.hex(TypeStr.normalize(s))}"
      ]
    end) ++
    Enum.map(pratt_corpus, fn s ->
      "psx\t#{Canon.hex(s)}\t#{Canon.hex(Pratt.parse_sexpr(s))}"
    end) ++
    Enum.map(core_corpus, fn s ->
      "cor\t#{Canon.hex(s)}\t#{Canon.hex(CoreCanon.expr(Core.from_expr(Pratt.parse(s))))}"
    end) ++
    Enum.map(prim_corpus, fn s ->
      "prm\t#{Canon.hex(s)}\t#{Canon.hex(Pratt.parse_sexpr(s))}"
    end) ++
    Enum.map(decl_corpus, fn s ->
      "dcl\t#{Canon.hex(s)}\t#{Canon.hex(DeclCanon.prog(Decl.parse(s, assemble_only: true)))}"
    end)

path = Path.join([__DIR__, "fixtures", "parity.fixtures"])
File.mkdir_p!(Path.dirname(path))
File.write!(path, Enum.join(lines, "\n") <> "\n")
IO.puts("wrote #{length(lines)} fixture records to #{path}")
