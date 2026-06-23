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

  alias Rian.Core.{
    EWith,
    EBlock,
    EList,
    EMap,
    EMapUpdate,
    ETuple,
    ELambda,
    ECapture,
    ECaptureNamed
  }

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

  def expr(%EMapUpdate{base: b, pairs: ps}),
    do: "%{#{expr(b)} | #{Enum.map_join(ps, " ", &map_pair/1)}}"

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

  # pins stay excluded from the Core corpus (no shared renderer); type-patterns are covered.
  def pat(%PPin{}), do: raise("pin pattern is excluded from the Core parity corpus")
  def pat(%PTyped{name: n, tname: t}), do: "(: #{n} #{t})"

  defp map_pat_pair({{:key, k}, p}), do: "#{expr(k)} => #{pat(p)}"
  defp map_pat_pair({k, p}), do: "#{k}: #{pat(p)}"

  # ── the `ann` oracle: an annotated tree's per-node types in pre-order (`_` = `nil`). The child
  # order mirrors `expr/1` above (and `annPre`/`tKids` in purs/src/Rian/Check.purs). Proves
  # `Check.annotate`'s typing; the structure is already proven by `cor`/`bdy`.
  def ann_types(node), do: [mark(Map.get(node, :type)) | child_types(node)]

  defp mark(nil), do: "_"
  defp mark(t) when is_binary(t), do: t

  defp child_types(%EUnary{arg: a}), do: ann_types(a)
  defp child_types(%EBin{left: l, right: r}), do: ann_types(l) ++ ann_types(r)

  defp child_types(%ECall{fun: f, args: args}),
    do: ann_types(f) ++ Enum.flat_map(args, &ann_types/1)

  defp child_types(%EDot{head: h}), do: ann_types(h)

  defp child_types(%EIf{cond: c, then: t, else: e}),
    do: ann_types(c) ++ ann_types(t) ++ ann_types(e)

  defp child_types(%ECase{scrut: s, arms: arms}),
    do: ann_types(s) ++ Enum.flat_map(arms, &arm_types/1)

  defp child_types(%EWith{clauses: cls, body: body, els: els}),
    do:
      Enum.flat_map(cls, fn {_p, e} -> ann_types(e) end) ++
        ann_types(body) ++ Enum.flat_map(els, &arm_types/1)

  defp child_types(%EBlock{stmts: stmts}), do: Enum.flat_map(stmts, &stmt_types/1)

  defp child_types(%EList{elems: es, tail: :close}), do: Enum.flat_map(es, &ann_types/1)

  defp child_types(%EList{elems: es, tail: t}),
    do: Enum.flat_map(es, &ann_types/1) ++ ann_types(t)

  defp child_types(%EMap{pairs: ps}), do: Enum.flat_map(ps, &pair_types/1)

  defp child_types(%EMapUpdate{base: b, pairs: ps}),
    do: ann_types(b) ++ Enum.flat_map(ps, &pair_types/1)

  defp child_types(%ETuple{elems: es}), do: Enum.flat_map(es, &ann_types/1)
  defp child_types(%ELambda{body: b}), do: ann_types(b)
  defp child_types(%ECapture{body: b}), do: ann_types(b)
  defp child_types(%ECaptureNamed{path: p}), do: ann_types(p)
  defp child_types(%ELabel{expr: e}), do: ann_types(e)
  defp child_types(_leaf), do: []

  defp arm_types({_pat, nil, body}), do: ann_types(body)
  defp arm_types({_pat, g, body}), do: ann_types(g) ++ ann_types(body)

  defp stmt_types({:bind, _n, e}), do: ann_types(e)
  defp stmt_types({:typed_bind, _n, _t, e}), do: ann_types(e)
  defp stmt_types({:expr, e}), do: ann_types(e)

  defp pair_types({{:key, k}, v}), do: ann_types(k) ++ ann_types(v)
  defp pair_types({_k, v}), do: ann_types(v)
end

# Canonical s-expression for the declaration IR (Rian.Decl assemble → Prog) — the `dcl`
# parity oracle. Mirrors `progSexpr`/`typeSexpr`/… in purs/src/Rian/Decl.purs byte-for-byte.
defmodule DeclCanon do
  alias Rian.IR.{
    Type,
    Variant,
    Field,
    Struct,
    Func,
    Param,
    Clause,
    Mod,
    Const,
    Use,
    Range,
    Opaque
  }

  def prog(p) do
    types = Enum.map(Map.get(p, :types, []), &type_s/1)
    ranges = Enum.map(Map.get(p, :ranges, []), &range_s/1)
    opaques = Enum.map(Map.get(p, :opaques, []), &opaque_s/1)
    structs = Enum.map(Map.get(p, :structs, []), &struct_s/1)
    funcs = Enum.map(Map.get(p, :funcs, []), &func_s/1)
    mods = Enum.map(Map.get(p, :mods, []), &mod_s/1)
    Enum.join(types ++ ranges ++ opaques ++ structs ++ funcs ++ mods, "\n")
  end

  # the `prl` stream: a type list (`Prelude.with_prelude` output) serialized via `type_s`.
  def types_s(types), do: Enum.map_join(types, "\n", &type_s/1)

  # the `prc` stream: ONLY the program-global protocols + impl-decls (synthesis-free).
  def proto_impl(p) do
    protocols = Enum.map(Map.get(p, :protocols, []), &protocol_s/1)
    impls = Enum.map(Map.get(p, :impl_decls, []), &impl_s/1)
    Enum.join(protocols ++ impls, "\n")
  end

  # the `pex` stream: a generated `Protocol.expand` def map (dispatcher head/clause or impl method).
  def expand_def_s(d) do
    "(" <>
      Atom.to_string(d.dispatch) <>
      " " <>
      d.name <>
      " params=" <>
      (d.params || "") <>
      ret_flag(Map.get(d, :ret)) <>
      guard_of(Map.get(d, :guard)) <>
      body_of(Map.get(d, :body)) <>
      " pub=" <>
      to_string(d.pub) <>
      " tvars=" <>
      Enum.join(Map.get(d, :tvars, []), ",") <>
      if(Map.get(d, :synthetic), do: " syn", else: "") <> ")"
  end

  defp protocol_s(p) do
    "(protocol #{p.name}#{Enum.map_join(p.methods, "", &method_s/1)}#{Enum.map_join(p.assoc, "", fn a -> " assoc=#{a}" end)})"
  end

  defp method_s(m), do: " (method #{m.name} params=#{m.params}#{ret_flag(m.ret)})"

  defp impl_s(i) do
    "(impl #{i.proto} #{i.type}#{Enum.map_join(i.methods, "", &imethod_s/1)}#{Enum.map_join(Enum.sort(Map.to_list(i.assoc)), "", &assoc_s/1)})"
  end

  defp imethod_s(m),
    do: " (imethod #{m.name} params=#{m.params}#{guard_of(m.guard)}#{body_of(m.body)})"

  defp assoc_s({n, ty}), do: " assoc=#{n}" <> if(ty, do: ":=#{ty}", else: "")

  # public wrapper for the `shs` stream: serialize one module (mirrors PS `Decl.modSexpr`).
  def mod_one(m), do: mod_s(m)

  defp mod_s(%Mod{
         name: n,
         uses: us,
         types: ts,
         ranges: rs,
         opaques: os,
         structs: ss,
         consts: cs,
         funcs: fs,
         doc: doc
       }) do
    "(mod #{n}#{doc_flag(doc)}" <>
      Enum.map_join(us, "", fn u -> " " <> use_s(u) end) <>
      Enum.map_join(ts, "", fn t -> " " <> type_s(t) end) <>
      Enum.map_join(rs, "", fn r -> " " <> range_s(r) end) <>
      Enum.map_join(os, "", fn o -> " " <> opaque_s(o) end) <>
      Enum.map_join(ss, "", fn s -> " " <> struct_s(s) end) <>
      Enum.map_join(cs, "", fn c -> " " <> const_s(c) end) <>
      Enum.map_join(fs, "", fn f -> " " <> func_s(f) end) <> ")"
  end

  defp range_s(%Range{name: n, base: base, lo: lo, hi: hi, pub?: pub, doc: doc}),
    do: "(range #{n}#{pub_flag(pub)}#{doc_flag(doc)} #{base} #{lo}..#{hi})"

  defp opaque_s(%Opaque{name: n, base: base, pub?: pub, doc: doc, ops: ops, casts: casts}),
    do:
      "(opaque #{n}#{pub_flag(pub)}#{doc_flag(doc)} #{base}#{Enum.map_join(ops, "", &op_s/1)}#{Enum.map_join(casts, "", &cast_s/1)})"

  defp op_s(o), do: " op=#{o.op}(#{Enum.join(o.params, ", ")}) #{o.ret}"
  defp cast_s(c), do: " cast=#{c.name}() #{c.ret}"

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
         externals: ext,
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

    "(func #{n}#{pub_flag(pub)}#{doc_flag(doc)}#{tv}#{bd}#{ret_flag(ret)} (params#{Enum.map_join(ps, "", &param_s/1)})#{Enum.map_join(cs, "", &clause_s/1)}#{externals_s(ext)})"
  end

  defp externals_s(ext) when map_size(ext) == 0, do: ""

  defp externals_s(ext) do
    " (externals" <>
      Enum.map_join(Enum.sort(Map.to_list(ext)), "", fn {t, s} ->
        " (ext #{t} #{ext_spec_s(s)})"
      end) <>
      ")"
  end

  defp ext_spec_s(s) when is_binary(s), do: "str:" <> s

  defp ext_spec_s({:ref, parts, erl}),
    do: "ref:" <> if(erl, do: ":", else: "") <> Enum.join(parts, ".")

  defp ext_spec_s({:file, p, f}), do: "file:" <> p <> "," <> f

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

# Rian.Range leaf-gate corpus: rewrite `Name.of(n)` → an in-bounds `if`-Result over the Core,
# given a fixed test table (must match `testTable` in Range.purs).
range_table = %{
  "Digit" => %{lo: 0, hi: 9, base: "Int53"},
  "Byte" => %{lo: 0, hi: 255, base: "Int53"}
}

range_corpus = [
  "Digit.of(n)",
  "Byte.of(x)",
  "f(Digit.of(n))",
  "Other.of(n)",
  "Digit.of(n) + 1",
  "if c do Digit.of(a) else b end",
  "a + b",
  "[Digit.of(x), Byte.of(y)]",
  "Digit.of(Byte.of(n))"
]

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
  "alias Name := String\nmod U do\nstruct Person(name Name, age Int53)\nend",
  # stage 4a: range / opaque (+ range-as-alias substitution)
  "range Digit := 0..9",
  "pub range Byte := 0..255",
  "range Letter := 'a'..'z'",
  "opaque UserId := Int53",
  "pub opaque Tok := String",
  "opaque Wrapped := Vec(Int53)",
  "range Digit := 0..9\nstruct Pos(d Digit)",
  "mod R do\nrange Small := 0..3\nopaque Handle := Int64\nend",
  # stage 4b: def block bodies (`def … Ret <nl> body <nl> end`; no `do` — a top-level
  # newline becomes `;`, while nested `do`/`end`, brackets, and `with`-headers don't split)
  "def f()\n  x := 1\n  x + 1\nend",
  "def g(n Int53) Int53\n  n * 2\nend",
  "def h(x Int53) Int53\n  case x do\n    0 -> 1\n    _ -> x\n  end\nend",
  "def k(xs Vec(Int53)) Int53\n  with [h | _] <- xs do\n    h\n  end\nend",
  "def multi() Int53\n  a := [1, 2,\n        3]\n  sum(a)\nend",
  "def two(a, b)\ndef two(a, b)\n  a + b\nend",
  "def mk(a Int53) P\n  P(x: a,\n    y: a)\nend",
  "mod B do\npub def run() Int53\n  x := 10\n  x\nend\nend",
  # stage 4c: @external — target-scoped FFI bodies (string spec, refs, file ref, stacked, in a mod)
  "@external(:js, \"x => x\")\ndef ext1(x Int53) Int53",
  "@external(:rs, \"todo!()\")\n@external(:js, \"0\")\npub def ext2() Int53",
  "@external(:ex, Mod.fun)\ndef ext3(a Int53) Int53",
  "@external(:js, :erlang.length)\ndef ext4(xs Vec(Int53)) Int53",
  "@external(:rs, \"src.rs\", \"helper\")\ndef ext5() Int53",
  "mod F do\n@external(:jvm, \"Math.sqrt\")\npub def root(x Float64) Float64\nend",
  # stage 4d: abstract (opaque + op/cast rules in a do … end block)
  "abstract Meters := Float64 do\n  op +(a Meters, b Meters) Meters\n  to base() Float64\nend",
  "pub abstract Money := Int64 do\n  op +(a Money, b Money) Money\n  op *(a Money, b Int64) Money\n  to cents() Int64\nend",
  "abstract Empty := Int53 do\nend",
  "mod U do\nabstract Id := Int53 do\n  to raw() Int53\nend\nend",
  # op rule with parametric param + return types: the params/return contain parens, so the
  # balanced `extract_parens` split (not a greedy regex) must keep them intact.
  "abstract Vector := Vec(Int53) do\n  op map(f Fn(Int53, Int53), v Vector) Vec(Int53)\n  to items() Vec(Int53)\nend",
  # stage 4e (macro): a macro emits no IR (expanded before the checker); pair with a type/
  # struct (not a `def`, whose body assemble would macro-expand from a string to an AST) to
  # show the macro decl is consumed and dropped while the sibling survives.
  "macro twice(x) := x + x\ntype Tag := A | B",
  "macro inc(x) := x + 1\nstruct Box(v Int53)"
]

# Rian.External corpus — the `ext` stream: render each function's `@external` specs (ADR-0068)
# against its own params (composes the Decl @external parse with External.render).
ext_corpus = [
  "@external(:js, \"x => x * 2\")\ndef f(x Int53) Int53",
  "@external(:ex, Mod.fun)\ndef g(a Int53, b Int53) Int53",
  "@external(:js, :erlang.length)\ndef h(xs Vec(Int53)) Int53",
  "@external(:rs, \"todo!()\")\n@external(:js, \"0\")\npub def k() Int53"
]

# Rian.Decl protocol/impl corpus — the `prc` stream (ADR-0042 §3). Serializes ONLY the
# program-global protocols + impl-decls, NOT the full program: the Elixir `Protocol.expand`
# synthesizes dispatcher / `impl_*` funcs into `funcs` during assembly (a pass not ported),
# so the full `funcs` diverge while the protocol/impl IR matches. An `impl` needs its
# `protocol` in the same source (coherence runs in `assemble`), so they are paired.
# Rian.Prelude corpus — the `prl` stream: `Prelude.with_prelude(types)` prepends the built-in
# `Option(T)` to a source's user types (ADR-0047 §3). Serialized via the shared type renderer.
prelude_corpus = [
  "",
  "type Color := Red | Green | Blue",
  "type Pair := P(a Int53, b Int53)",
  "struct Foo(x Int53)",
  "type Maybe := Nothing | Just(val String)\ntype Dir := N | S"
]

# Rian.Exhaustiveness.program_env corpus — the `pge` stream: build the whole-program
# signature env (prelude Option + user types + ranges + structs) and dump its `ctors` table.
prog_env_corpus = [
  "",
  "type Tree := Leaf | Node(l Tree, r Tree)",
  "range Bit := 0..1",
  "struct Point(x Int53, y Int53)",
  # range/struct precede the type: `range`/`opaque` are not declaration-boundary keywords
  # (shared PS/Elixir quirk), so a `type` must be last or followed by a boundary kw.
  "range D := 0..2\nstruct Box(v Int53)\ntype Color := Red | Green | Blue"
]

proto_impl_corpus = [
  "protocol Show do\n  def show(x Self) String\nend",
  "protocol Container do\n  type Elem\n  def empty() Self\n  def insert(c Self, e Elem) Self\nend",
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := int_to_str(x)\nend",
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Bool do\n  def eq(a, b) := a == b\nend",
  "mod P do\nprotocol Ord do\n  def lt(a Self, b Self) Bool\nend\nimpl Ord for Int53 do\n  def lt(a, b) := a < b\nend\nend"
]

# Rian.Protocol corpus — the `pex` stream (ADR-0042 §4): the dispatcher / `impl_*` def maps
# `Protocol.expand` synthesizes. Exercises the runtime discriminator guards (primitive / sum
# (all-nullary + mixed) / struct), a multi-clause dispatcher (two impls), a two-param method,
# and a protocol with no impls (no dispatcher). Types/structs come LAST (after the impl `end`)
# to sidestep the `type`-absorbs-next quirk shared by both parsers.
pex_corpus = [
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := f(x)\nend",
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := a(x)\nend\nimpl Show for Bool do\n  def show(x) := b(x)\nend",
  "protocol Nm do\n  def nm(c Self) String\nend\nimpl Nm for Color do\n  def nm(c) := s(c)\nend\ntype Color := Red | Green | Blue",
  "protocol Tag do\n  def tag(o Self) Int53\nend\nimpl Tag for Box do\n  def tag(o) := 0\nend\ntype Box := Em | Full(v Int53)",
  "protocol Org do\n  def org(p Self) Bool\nend\nimpl Org for Point do\n  def org(p) := f(p)\nend\nstruct Point(x Int53, y Int53)",
  "protocol Empty do\n  def e(x Self) Bool\nend",
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Bool do\n  def eq(a, b) := a == b\nend"
]

# Rian.Reach corpus — the `rch` stream (ADR-0057). First slice: the signature pins
# (ref/Int/width/Any), the body scan (FFI / concurrency / Result / map / prims + call edges),
# and the call-graph fixpoint. Avoids the deferred emitter-gap detectors (union / parametric /
# Any-in-JVM-op / pin / dispatcher) and portable-prelude module calls (Prelude.defines? unported).
rch_corpus = [
  "def add(a Int53, b Int53) := a + b",
  "def bump(x ref Int53) := x",
  "def big(n Int) := n",
  "def wide(n Int64) := n",
  "def dyn(x Any) := x",
  "def now() := :erlang.system_time()",
  "def go(f Int53) := :erlang.spawn(f)",
  "def ext() := Foo.bar()",
  # portable-prelude module calls (Prelude.defines?): an exported `List.length` is portable by
  # construction (reaches all targets); a non-exported `List.bogus` falls through to host FFI.
  "def uselen(xs Vec(Int53)) Int53 := List.length(xs)",
  "def usebogus(xs Vec(Int53)) := List.bogus(xs)",
  "def m() := %{a: 1}",
  "def okv(x Int53) := {:ok, x}",
  "def shw(x Int53) := __prim_to_string(x)",
  "def host() := :erlang.now()\ndef caller() := host()",
  # slice 2 — emitter-gap detectors: Any-in-operator (off :jvm, + Any off :rs), a narrowable
  # union (kills nothing), a non-narrowable union (Int32+Char clash → off all), a sum-member
  # union, and a clause-head pin (off :rs).
  "def gop(x Any) := x + 1",
  "def heq(x Any) := x == 1",
  "def unar(x Int32 | Bool) := x",
  "def uclash(x Int32 | Char) := x",
  "def usum(x Color | Bool) := x\ntype Color := Red | Green",
  "def same(x Int53, ^x) := x",
  # slice 3 — the parametric-:rs subset. F3 aligned-generic (reaches :rs): a forall builder whose
  # construction args align positionally with the ctor's field tvars, and a forall passthrough with
  # no construction. F1 pins (no forall → no instantiation to infer): a bare construction, and a
  # Vec(T)-field builder. F2 pins (not Rust-emittable): a Map(K,V) field, and a recursion cycle.
  "def mk(a K, b V) Pair forall K, V := P(a, b)\ntype Pair := P(a K, b V)",
  "def swp(p Pair) Pair forall K, V := p\ntype Pair := P(a K, b V)",
  "def mkbad(a K, b V) Pair := P(a, b)\ntype Pair := P(a K, b V)",
  "def mkbox(x T) Box := Bx([x])\ntype Box := Bx(items Vec(T))",
  "def useb(x Bad) Bad := x\ntype Bad := B(m Map(K, V))",
  "def urec(x Rec) Rec := x\ntype Rec := R(nxt Rec, v T)"
]

# Rian.Reach `effect_sets` corpus — the `efs` stream (ADR-0048 §3): the inferred effect set per
# function — a clock primitive (host+clock), a known host module (host+io), a concurrency
# primitive (spawn), a pure function (none), and a caller inheriting a callee's effects.
efs_corpus = [
  "def now() := :erlang.system_time()",
  "def log(s String) := IO.puts(s)",
  "def go(f Int53) := :erlang.spawn(f)",
  "def pure(x Int53) := x + 1",
  "def caller() := tick()\ndef tick() := :erlang.system_time()"
]

# Rian.Capability corpus — the `cap` stream (ADR-0025/0061): Rust parameter-type lowering of a
# `<cap> <type>` pair (copy/borrow/owned, Fn callbacks, Vec/Map/tuple/parametric, nested).
cap_corpus = [
  "val Int64",
  "val String",
  "val Vec(Int64)",
  "val Foo",
  "val UInt8",
  "iso String",
  "iso Vec(Int64)",
  "iso Int64",
  "iso Float32",
  "iso Map(String, Int64)",
  "iso Option(Int64)",
  "iso (Int53, String)",
  "iso Vec(Option(Int64))",
  "ref Int64",
  "tag Foo",
  "val Fn(Int53, Int53)"
]

# Rian.Capability `lin` stream (ADR-0055): the branch-aware free-variable occurrence counts of
# an expression (use-once linearity for iso/ref). Covers binders (lambda/block/case-pat shadow),
# branch-aware `if`/`case` (max over arms), dot, list.
lin_corpus = [
  "x + x",
  "f(x, y)",
  "(a) -> a + b",
  "if c do x else x end",
  "g(h)",
  "case y do\n  z -> z + z\n  w -> q\nend",
  "p.field + p.field",
  "[a, a, b]"
]

# Rian.Check `program_ic` corpus — the `pic` stream: dump the whole-program inference-context
# tables. **Protocol-free** — the reference's `assemble` synthesizes dispatcher/`impl_*` funcs
# into `prog.funcs` (a tail pass not yet wired into PS `Decl`), so an `impl` would make `funs`/
# `fsigs`/`ctors` diverge; the `impls` table is therefore exercised empty for now. Functions are
# explicitly-typed so `fill_local_rets` is a no-op (PS builds `funs` raw). Covers tdefs (sum
# variants + prelude Option), fields (single-variant labels), funs/fsigs, ctors, ranges, opaques.
ic_corpus = [
  "type Color := Red | Green | Blue(shade Int53)\ntype Box := Bx(val Int53, tag String)\nstruct Point(x Int53, y Int53)\ndef area(p Point) Int53 := 0\nrange Bit := 0..1\nopaque Id := Int64",
  "",
  "def add(a Int53, b Int53) Int53 := a + b"
]

# Rian.Check `infer` with a real `ic` — the `ifc` stream. `prog ;; expr`: build `program_ic`
# over `prog`, infer `expr`. Covers the ic-using call clauses — a sum/struct constructor
# (`ic.ctors`), a program function's declared return (`ic.funs`), a cross-module call, and a
# user-fn call nested in arithmetic. Functions are explicitly-typed (non-generic).
ifc_corpus = [
  "type Color := Red | Green | Blue(shade Int53);;Blue(5)",
  "def foo(x Int53) String := x;;foo(1)",
  "def helper(x Int53) Bool := true;;M.helper(1)",
  "struct Point(x Int53, y Int53);;Point(1, 2)",
  "def baz(x Int53) Int53 := x;;baz(n) + 1",
  # slice C: ECase flow-narrowing (ctor-pattern field types via ic.tdefs), generic return
  # instantiation (forall via ic.fsigs), and `.of` range/opaque construction.
  "type Box := Bx(v Int53);;case b do\n  Bx(x) -> x\nend",
  "type Pair := P(a Int53, b String);;case b do\n  P(i, t) -> t\nend",
  "def idv(x T) T forall T := x;;idv(n)",
  "range Bit := 0..1;;Bit.of(n)",
  "opaque Id := Int64;;Id.of(n)"
]

# Rian.Check `infer_return_type` corpus — the `irt` stream. Un-annotated functions whose return
# infers from the body (literal/arith/string/param); a self-recursive function with no base case
# stays `:unknown`.
irt_corpus = [
  "def f(x Int53) := x + 1",
  "def g(s String) := s",
  "def two(a Int53, b Int53) := a + b",
  "def cnt(x Int53) := cnt(x)"
]

# Rian.Check `fill_local_rets` corpus — the `flr` stream. The fixpoint fills each un-annotated
# function's return; a caller of another un-annotated function resolves through the filled table.
flr_corpus = [
  "def f(x Int53) := x + 1\ndef g(x Int53) := f(x)",
  "def h(x Int53) := x * 2"
]

# Rian.InferLocal `fill_returns` corpus — the `ilr` stream. A private function's undeclared
# return is filled by inference (`Any` when uninferable, e.g. self-recursion); a `pub` boundary
# and an explicitly-typed return are kept. Params are typed (param inference is a later slice).
ilr_corpus = [
  "def f(x Int53) := x + 1",
  "def g(s String) := s\ndef h(s String) := g(s)",
  "def cnt(x Int53) := cnt(x)",
  "pub def p(x Int53) Int53 := x"
]

# parameter inference + `forall T` generalization (the InferLocal fixpoint's headline) — `ilp`:
ilp_corpus = [
  "def add(x, y) := x + y",
  "def idu(x) := x",
  "def fst(x, y) := x",
  "def cat(s) := s <> \"!\"",
  "def callee(x String) := x\ndef caller(y) := callee(y)"
]

# Rian.Check `check_program` corpus — the `gate` stream. The return-assignability gate: a body
# whose inferred type is assignable to the declared return passes (`ok`), else the first mismatch
# message. Concrete types (no error-sets / effects / bounds / coherence / literal-width-adoption).
# Rian.Check `infer_param_type` corpus — the `ipt` stream. An untyped private param is inferred
# from the body: an arithmetic neighbour (Int53), a string concat (String), a compare (Int53), a
# typed callee parameter (cross-function); a pure pass-through stays `:unknown` (InferLocal then
# generalizes it to `forall T`).
ipt_corpus = [
  "def f(x) := x + 1",
  "def cat(s) := s <> \"!\"",
  "def cmp(a) := a == 3",
  "def passthru(x) := x",
  "def callee(a Int53) := a\ndef caller(y) := callee(y)"
]

gate_corpus = [
  "pub def f(x Int53) Int53 := x",
  "pub def g(x Int53) String := x",
  "pub def h(x Bool) Bool := x",
  "pub def k(x Int53) Bool := x",
  # full assignable?: union membership / mismatch, a bare sum head, a constructed→opaque return,
  # and numeric widening.
  "pub def u(x Int32) Int32 | Bool := x",
  "pub def um(x String) Int32 | Bool := x",
  "pub def bh(x Int53) Option(Int53) := Some(x)",
  "pub def st() Pair := [1, 2]\ntype Pair := P(a Int53, b Int53)",
  "pub def w(x Int8) Int64 := x",
  # error sets (ADR-0040): a Result return's produced error set must be ⊆ its declared E.
  "pub def safe() Result(Int53, MyErr) := {:ok, 1}\ntype MyErr := Bad",
  "pub def bad() Result(Int53, MyErr) := {:error, Other}\ntype MyErr := Bad",
  "pub def okerr() Result(Int53, MyErr) := {:error, Bad}\ntype MyErr := Bad",
  # check_unk (ADR-0034): an unresolved `_Unk` hole in the signature is rejected (param, return,
  # private fn), and it fires BEFORE the return gate (the last case also has a return mismatch).
  "pub def uh(x _Unk) Int53 := x",
  "pub def ur(x Int53) _Unk := x",
  "def up(x _Unk) := x",
  "pub def um1(x _Unk) String := 1",
  # check_union_clash (ADR-0083): a value union whose members share a runtime discriminator is
  # rejected (param + return, integer + float classes); a distinct-discriminator union is fine; and
  # the clash fires BEFORE the return gate (the last case also has a return mismatch).
  "pub def uc(x Int32 | Char) Int53 := 1",
  "pub def ucr() Int8 | Int16 := 1",
  "pub def ucf(x Float32 | Float64) Int53 := 1",
  "pub def und(x Int53 | String) Int53 := 1",
  "pub def ucm(x Int8 | Char) String := 1",
  # check_external_caps (ADR-0068/0055): an `@external` param must be `val`/`tag` — `iso`/`ref`
  # linearity is not enforceable across an FFI boundary. A `val`/`tag` param, a string spec, and a
  # module ref the reference's reflection can't refute (`:erlang.length/1` is exported) all pass.
  "@external(:js, \"x => x\")\ndef ecbad(x iso Vec(Int53)) Int53",
  "@external(:js, \"x => x\")\ndef ecref(x ref Int53) Int53",
  "@external(:js, \"x => x\")\ndef ecok(x tag Int53) Int53",
  "@external(:js, :erlang.length)\ndef eclen(xs Vec(Int53)) Int53",
  # ref-arity resolution (ADR-0041 §2, host reflection via Rian.HostRef): a loaded module that
  # exports no such fun/arity is rejected (`:erlang.length/2` and `:erlang.no_such_bif/1` don't
  # exist); a ref to an unloadable module is conservatively accepted.
  "@external(:js, :erlang.length)\ndef ewrongarity(a Int53, b Int53) Int53",
  "@external(:js, :erlang.no_such_bif)\ndef enobif(x Int53) Int53",
  "@external(:ex, Mod.fun)\ndef eunloadable(a Int53) Int53",
  # check_labels (ADR-0065): a labeled arg is valid only on PascalCase construction — a lowercase
  # call and a qualified `Mod.foo` call are rejected; construction is fine.
  "pub def lblbad(x Int53) Int53 := g(a: x)",
  "pub def lblq(x Int53) Int53 := Mod.foo(a: x)",
  "type Pt := Pt(px Int53)\npub def lblok() Pt := Pt(px: 1)",
  # check_bounds (ADR-0042 §2): a bounded-generic call whose tvar is instantiated to a type lacking
  # the required `impl` is rejected; a type that has the impl is fine.
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := \"n\"\nend\ndef needsShow(x T) String forall T: Show := show(x)\npub def callbad(b Bool) String := needsShow(b)",
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := \"n\"\nend\ndef needsShow(x T) String forall T: Show := show(x)\npub def callok(n Int53) String := needsShow(n)",
  # check_numeric_mix (ADR-0035/0034 §1): an arithmetic op mixing an integer and a float operand is
  # rejected; same-kind arithmetic is fine. (Explicit returns so the return gate passes first.)
  "pub def nmix(x Int53) Float64 := x + 2.0",
  "pub def nmix2(x Int53) Int53 := x + 2",
  # check_value_position (ADR-0035 §6): an `else`-less `if` or a `<~` mutation in value position is
  # rejected; an `if` with `else` is fine.
  "pub def vpbad(x Bool) Int53 := if x do 1 end",
  "pub def vpmut(x Int53) Int53 := id(x <~ 1)",
  "pub def vpok(x Bool) Int53 := if x do 1 else 2 end",
  # check_effects (ADR-0048 §3): a declared `@effects(…)` set must equal the inferred set
  # (`IO.puts` performs `host` + `io`). Exact match → ok; under-declaration and over-declaration
  # are both rejected.
  "@effects(host, io)\ndef effok(x Int53) Symbol := IO.puts(x)",
  "@effects(io)\ndef effunder(x Int53) Symbol := IO.puts(x)",
  "@effects(host, io, fs)\ndef effover(x Int53) Symbol := IO.puts(x)",
  # check_binds (ADR-0034/0036/0064): a typed bind whose value clashes with its annotation is
  # rejected. Fixed-width literal range (ADR-0064 — incl. a >32-bit `UInt32` bound and a `Vec`
  # element); an in-range literal PASSES (a naive port would falsely reject `x Int8 := 5`); an
  # integer literal does not adopt a float; an outright type clash; and the ADR-0036 range bind
  # (out-of-bounds / in-bounds / kind-mismatch / non-literal assignable-to-base). The return gate
  # passes first (the body's last expression `n` is the `Int64` param).
  "def bnd1(n Int64) Int64 := x Int8 := 9999 ; n",
  "def bnd2(n Int64) Int64 := x Int8 := 5 ; n",
  "def bnd3(n Int64) Int64 := x UInt32 := 4294967296 ; n",
  "def bnd4(n Int64) Int64 := x UInt32 := 4294967295 ; n",
  "def bnd5(n Int64) Int64 := xs Vec(Int8) := [1, 2, 9999] ; n",
  "def bnd6(n Int64) Int64 := x Float64 := 66 ; n",
  "def bnd7(n Int64) Int64 := x Int53 := \"hi\" ; n",
  "range Digit := 0..9\ndef bnd8(n Int64) Int64 := d Digit := 12 ; n",
  "range Digit := 0..9\ndef bnd9(n Int64) Int64 := d Digit := 7 ; n",
  "range Digit := 0..9\ndef bnd10(n Int64) Int64 := d Digit := 'a' ; n",
  "range Digit := 0..9\ndef bnd11(n Int64) Int64 := d Digit := n ; n"
]

# Rian.Assemble corpus — the `asm` stream: a `protocol`/`impl` program assembled to the funcs the
# reference's `Decl.parse` synthesizes (dispatcher + `impl_*`), serialized via the shared `prog`
# oracle. Confirms PS `Assemble` reproduces `Decl.assemble`'s protocol-synthesis tail pass. (User
# `def`s before the protocol/impl, types last — mirrors the `pex` corpus.)
# Rian.Assemble macro expansion — the `mxb` stream (ADR-0030): the Core of every clause body
# AFTER `lower_meta` expands `macro` calls, serialized via the shared `coreSexpr` oracle. (Tests
# the macro WIRING — env from the program's macros, applied to func bodies — which the body-string
# serializer can't show, since the reference can't render an expanded AST through it.)
mxb_corpus = [
  "macro double(x) := x + x\npub def u(n Int53) Int53 := double(n)",
  "macro inc(x) := x + 1\npub def v(n Int53) Int53 := inc(n)",
  "macro swap(a, b) := (b, a)\ndef w(n Int53) := swap(n, 1)",
  "macro double(x) := x + x\npub def p(n Int53) Int53 := n + 1",
  # comptime (lower_meta's other half — fires without macros, and composes after expansion):
  "pub def c() Int53 := comptime(2 + 3)",
  "pub def d() Int53 := comptime(10 div 3)",
  "pub def lt() Bool := comptime(2 < 3)",
  "macro double(x) := x + x\npub def m() Int53 := comptime(double(2))"
]

# Rian.Opaque erase (ADR-0067) — opaque→base type subst + `.of`/cast body stripping. `opq`:
opq_corpus = [
  "opaque Token := String\npub def f(t Token) Token := t",
  "opaque Id := Int53\npub def g(x Id) Id := Id.of(x)",
  "opaque A := B\nopaque B := Int64\npub def h(a A) A := a",
  "abstract Meters := Int53 do\n  to base() Int53\nend\npub def m(d Meters) Int53 := d.base()"
]

# Rian.JS — the `js` stream (ADR-0049 Tier 1): the compiled ECMAScript module. Number-mode
# (`Int53`) programs; avoids the still-deferred constructs (protocols/@external/value-union over a
# user type). Oracle = `Rian.JS.compile`.
js_corpus = [
  "pub def add(x Int53, y Int53) Int53 := x + y",
  "pub def neg(b Bool) Bool := not b",
  "pub def cat(s String, t String) String := s <> t",
  "pub def fac(n Int53) Int53 := if n <= 1 do 1 else n * fac(n - 1) end",
  "def half(n Int53) Int53 := n div 2",
  "pub def fst(x Int53, y Int53) Int53 := x",
  # case + wildcards + strings
  "pub def classify(n Int53) String := case n do\n  0 -> \"zero\"\n  _ -> \"other\"\nend",
  # sum type construction + case over ctors
  "type Color := Red | Green | Blue\npub def nm(c Color) String := case c do\n  Red -> \"r\"\n  Green -> \"g\"\n  Blue -> \"b\"\nend",
  "type Box := Wrap(Int53) | Empty\npub def wrap(x Int53) Box := Wrap(x)",
  # sum variant with declared field names — JS keeps positional `_n` keys (ADR-0049 §3b; the JVM
  # `data class` is the named-field backend). Named construction `Circle(radius: r)` is reordered to
  # declared field order, then keyed positionally; `case`-arm + clause-head ctor patterns bind `._n`.
  "type Shape := Circle(radius Float64) | Square(side Float64)\npub def mk(r Float64) Shape := Circle(r)\npub def mkn(r Float64) Shape := Circle(radius: r)\npub def area(s Shape) Float64 := case s do\n  Circle(r) -> r\n  Square(x) -> x\nend",
  "type Shape := Circle(radius Float64) | Square(side Float64)\npub def area(Shape) Float64\npub def area(Circle(r)) := r\npub def area(Square(s)) := s",
  # a named arg out of declaration order is placed by name, then keyed positionally (`_0`/`_1`)
  "type Tag := Named(id Int53, Int53) | Bare(Int53)\npub def idOf(t Tag) Int53 := case t do\n  Named(a, b) -> a + b\n  Bare(c) -> c\nend",
  # list literals + cons + closed/cons clause patterns over a list
  "pub def pre(x Int53, xs Vec(Int53)) Vec(Int53) := [x | xs]",
  "pub def len(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [_ | t] -> 1 + len(t)\nend",
  # tuple value + membership + boolean ops
  "pub def between(x Int53) Bool := x >= 0 and x <= 9",
  # lambda value (JS arrow), a string escape, a Char literal/equality
  "pub def mkInc() Fn(Int53, Int53) := (a) -> a + 1",
  "pub def nl() String := \"a\\nb\\t\\\"c\"",
  "pub def isA(c Char) Bool := c == 'a'",
  # map literal + map-update
  "pub def m2() Dict(Symbol, Int53) := %{a: 1, b: 2}",
  # module `const` → top-level JS `const`; a reference in a function body resolves to it (ADR-0033)
  "mod M do\n  const K Int53 := 10\n  pub def f(x Int53) Int53 := x + K\nend",
  # a `pub` const exports; a sibling const references another; the function uses the result
  "mod M do\n  pub const Base Int53 := 100\n  const Step Int53 := Base + 1\n  pub def g(n Int53) Int53 := n * Step\nend",
  # `@external(:js, "expr")` inline host body (ADR-0068): params bound positionally by name
  ~S|@external(:js, "x + 1") pub def inc(x val Int53) Int53|,
  # `@external(:js, "./file.mjs", "fun")` file-reference: an ESM import + a call to the imported fn
  ~S|@external(:js, "./codec.ffi.mjs", "encode") pub def enc(x val Int53) Int53|,
  # value-union of SUM members (ADR-0083): a `case` arm `a Box` narrows by the tagged-array head
  "type Box := BoxV(Int53)\ntype Bag := BagV(Int53)\ndef kind(x Box | Bag) Int53 := case x do\n  a Box -> 1\n  b Bag -> 2\nend",
  # value-union of STRUCT members: a `case` arm `b Box` narrows by the `__struct__` tag
  "struct Box(v Int53)\nstruct Widget(n Int53)\ndef pick(x Box | Widget) Int53 := case x do\n  b Box -> b.v\n  w Widget -> w.n\nend",
  # protocol dispatch (ADR-0061 §3): one dispatcher routes by the first arg's shape — a sum tag, a
  # struct `__struct__`, and a primitive `typeof` — to the mangled `impl_*` methods
  "type Color := Red | Green\nstruct Point(x Int53)\nprotocol K do\n  def k(self Self) Int53\nend\nimpl K for Color do\n  def k(c) := 1\nend\nimpl K for Point do\n  def k(p) := 2\nend\nimpl K for Bool do\n  def k(b) := 3\nend",
  # string interpolation (ADR-0069): a String hole is identity, an Int hole stringifies — the
  # program tail (`resolveInterp`) rewrites `${…}` before lowering
  ~S|pub def greet(s String) String := "hi ${s}"|,
  ~S|pub def lbl(n Int53) String := "n=${n}"|,
  # a Float64 hole calls Show.float, so `injectStdlib` supplies the portable Show module (ADR-0069 §6)
  ~S|pub def f2s(x Float64) String := "${x}"|,
  # struct construction (ADR-0050): `Name(f: v)` → a `__struct__`-tagged object (one and two fields)
  "struct Box(v Int53)\npub def mk(x Int53) Box := Box(v: x)",
  "struct P(a Int53, b Int53)\npub def mk2(x Int53, y Int53) P := P(a: x, b: y)"
]

# Rian.JS.compile_types — the `jsdts` stream (ADR-0086 §5): the TypeScript `.d.ts` sidecar. Maps
# the JS-valid type subset (prims, Vec/Fn/Option/Result/tuple/Map, user sum/struct/range, `forall`
# generics) to its faithful TS carrier. Oracle = `Rian.JS.compile_types`.
jsdts_corpus = [
  "pub def add(x Int53, y Int53) Int53 := x + y",
  "pub def idg(x T) T forall T := x",
  "pub def hof(f Fn(Int53, Int53), xs Vec(Int53)) Vec(Int53) := xs",
  "pub def opt(o Option(Int53)) Int53 := 0",
  "pub def res(r Result(Int53, String)) Int53 := 0",
  "pub def dct(d Dict(String, Int53)) Int53 := 0",
  "type Color := Red | Green | Blue\npub def nm(c Color) String := \"x\"",
  # a sum variant → a discriminated union of tagged objects with positional keys
  # (`{ $: \"Circle\", _0: number } | …`); JS keeps positional `_n` (ADR-0049 §3b)
  "type Shape := Circle(radius Float64) | Square(side Float64)\npub def area(s Shape) Float64 := 0.0",
  "struct Point(x Int53, y Int53)\npub def gx(p Point) Int53 := p.x",
  "range Digit := 0..9\npub def dd(x Digit) Int53 := 0",
  "mod M do\n  pub const PI Int53 := 3\nend"
]

asm_corpus = [
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := f(x)\nend",
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Bool do\n  def eq(a, b) := a == b\nend",
  "pub def caller(n Int53) String := show(n)\nprotocol Show do\n  def show(x Self) String\nend\nimpl Show for Int53 do\n  def show(x) := g(x)\nend",
  "protocol Nm do\n  def nm(c Self) String\nend\nimpl Nm for Color do\n  def nm(c) := s(c)\nend\ntype Color := Red | Green | Blue(shade Int53)"
]

# Rian.Lower.Rust — the `rust` stream (ADR-0049, the `to_rust` port). Oracle =
# `Rian.Decl.compile`'s `:rust`, joined `\n\n` (same as `mix rian.compile --rust`).
# Increment 1: the single-clause portable core — primitive `val` params, the
# arithmetic/comparison/boolean operator algebra (precedence + parens), `div`/`rem`,
# unary `-`/`not`, `if`, and local calls (recursion). Sums/structs/lists/strings/
# multi-clause/generics are later increments.
rust_corpus = [
  "pub def add(x Int53, y Int53) Int53 := x + y",
  "def half(n Int53) Int53 := n div 2",
  "pub def rem3(n Int53) Int53 := n rem 3",
  "pub def neg(b Bool) Bool := not b",
  "pub def negate(x Int53) Int53 := -x",
  "pub def between(x Int53) Bool := x >= 0 and x <= 9",
  "pub def either(a Bool, b Bool) Bool := a or b",
  # precedence: `*` binds tighter than `+`, so the `+` operand parenthesizes
  "pub def poly(x Int53) Int53 := x * x + 2 * x",
  "pub def grouped(x Int53) Int53 := (x + 1) * (x - 1)",
  "pub def fst(x Int53, y Int53) Int53 := x",
  # `if` + recursion (tail call), and a float division (`/` → explicit f64 casts)
  "pub def fac(n Int53) Int53 := if n <= 1 do 1 else n * fac(n - 1) end",
  "pub def avg(a Float64, b Float64) Float64 := (a + b) / 2.0",
  # increment 2a — TOTAL multi-clause (a var clause covers the rest → Rust-exhaustive, no shim)
  "pub def fib(Int53) Int53\npub def fib(0) := 0\npub def fib(1) := 1\npub def fib(n) := fib(n - 1) + fib(n - 2)",
  # a nullary sum → an `enum`; full-coverage clause-head ctor patterns (`Color::Red`)
  "type Color := Red | Green | Blue\npub def code(Color) Int53\npub def code(Red) := 0\npub def code(Green) := 1\npub def code(Blue) := 2",
  # a payload sum → `enum Shape { Circle(f64), … }`; construction `Shape::Circle(r)` + ctor patterns
  "type Shape := Circle(Float64) | Square(Float64)\npub def area(Shape) Float64\npub def area(Circle(r)) := 3.14 * r * r\npub def area(Square(s)) := s * s\npub def mk(r Float64) Shape := Circle(r)",
  # a `case` over a sum value → a nested `match` (full variant coverage)
  "type Box := Wrap(Int53) | Empty\npub def unwrap(b Box) Int53 := case b do\n  Wrap(x) -> x\n  Empty -> 0\nend",
  # increment 3 — strings / chars / symbols. `String` → `&str` param / owned `String` return
  # (`coerce_ret` `.to_string()`); `<>` → `format!`; `Char` → native `char`; `Symbol` → `&str`.
  "pub def isA(c Char) Bool := c == 'a'",
  "pub def greet() String := \"hi\"",
  "pub def cat(a String, b String) String := a <> b",
  "pub def tag() Symbol := :ok",
  "pub def first(c Char) Char := c",
  # a `\\n` escape in a string literal exercises the shared escape table
  "pub def nl() String := \"a\\nb\"",
  # the match shim (ADR-0036): a PARTIAL function (literal heads, no catch-all) → `_ => panic!(…)`
  "pub def lat(Int53) Int53\npub def lat(0) := 10\npub def lat(1) := 20",
  # a range-TOTAL literal match (`Bit := 0..1`, both covered) → `_ => unreachable!()` (rustc shim)
  "range Bit := 0..1\npub def flip(Bit) Bit\npub def flip(0) := 1\npub def flip(1) := 0",
  # structs — `struct Name(f T,…)` → `#[derive(…)] struct Name { f: T,… }`; `val Name` → `&Name`
  # param; field access `p.x`; construction `Name { f: v }`. (Struct PATTERNS are unsupported in
  # both text emitters — `pat_ex`/`pat_rs` have no `PStruct` clause — so none here.)
  "struct Point(x Int53, y Int53)\npub def gx(p Point) Int53 := p.x",
  "struct Pair(a Int53, b Int53)\npub def sum(p Pair) Int53 := p.a + p.b",
  "struct Point(x Int53, y Int53)\npub def mk(a Int53, b Int53) Point := Point(x: a, y: b)",
  # lists (ADR-0047) — `Vec(T)` literal → `vec![…]`; `val Vec(T)` → `&[T]` slice; cons `[x | xs]`
  # → prepend onto `xs.to_vec()`; `case` over a list → `match &(xs)[..] { [] …, [h, t @ ..] … }`
  "pub def lit() Vec(Int53) := [1, 2, 3]",
  "pub def pre(x Int53, xs Vec(Int53)) Vec(Int53) := [x | xs]",
  "pub def len(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [_ | t] -> 1 + len(t)\nend",
  "pub def hd(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [h | _] -> h\nend",
  # generics (ADR-0061) — a bare-tvar pass-through: `forall T` → `fn id<T: Clone>(x: &T) -> T`,
  # the borrowed `&T` cloned to the owned return (`(x).clone()`)
  "pub def id(x T) T forall T := x",
  "pub def fst(x T, y U) T forall T, U := x",
  # bounded generics + protocol traits (ADR-0061 §2): `protocol P` → `trait RianP`; a
  # `forall T: Eq` bound → `<T: RianEq + Clone>`; a protocol-method call `eq(a, b)` → `a.eq(b)`
  # (receiver method). Impls (`impl P for T`) are the next increment — none here.
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\npub def same(a T, b T) Bool forall T: Eq := eq(a, b)",
  # closures (ADR-0061): a `Fn(...)` param → `&impl Fn(…) -> …` (a closure call clones its args);
  # a `Fn(...)` return → `Box<dyn Fn(…) -> …>` (the value-position lambda is `Box::new(move …)`).
  "pub def apply(f Fn(Int53, Int53), x Int53) Int53 := f(x)",
  "pub def adder(n Int53) Fn(Int53, Int53) := (a) -> a + n"
]

# Rian.JVM — the `jvm` stream (ADR-0049 Tier 2): the compiled Kotlin module. Oracle =
# `Rian.JVM.compile`. Increment 1: single-clause portable core only — primitive params, the
# operator algebra (`L`-suffixed int literals, float-`/`, comparisons, `and`/`or`, `<>`→`+`,
# unary `-`/`not`), `if`-expressions, local calls/recursion. Multi-clause, sums, lists, and
# guards arrive with later increments and stay out of this corpus until then.
jvm_corpus = [
  "pub def add(x Int64, y Int64) Int64 := x + y",
  "def half(n Int64) Int64 := n div 2",
  "pub def rem3(n Int64) Int64 := n rem 3",
  "pub def neg(b Bool) Bool := not b",
  "pub def negate(x Int64) Int64 := -x",
  "pub def between(x Int64) Bool := x >= 0 and x <= 9",
  "pub def either(a Bool, b Bool) Bool := a or b",
  # precedence: `*` binds tighter than `+`, so the `+` operands parenthesize
  "pub def poly(x Int64) Int64 := x * x + 2 * x",
  "pub def grouped(x Int64) Int64 := (x + 1) * (x - 1)",
  "pub def fst(x Int64, y Int64) Int64 := x",
  "pub def eq(a Int64, b Int64) Bool := a == b",
  "pub def neq(a Int64, b Int64) Bool := a != b",
  # `if` is a Kotlin expression; the `do … end` branches unwrap to expressions
  "pub def abs(n Int64) Int64 := if n < 0 do 0 - n else n end",
  # a private callee + a public caller (local calls / recursion-shaped)
  "def dbl(n Int64) Int64 := n * 2\npub def quad(x Int64) Int64 := dbl(dbl(x))",
  # the portable number/bool/string/symbol/char primitives
  "pub def halve(x Float64) Float64 := x / 2.0",
  ~S|pub def greet(s String) String := "hi " <> s|,
  "pub def same(c Char) Char := c",
  "pub def passthru(s Symbol) Symbol := s",
  "pub def ok() Symbol := :ok",
  # the fixed-width integers all map to `Long`
  "pub def w8(n Int8) Int8 := n",
  "pub def w32(n UInt32) UInt32 := n",
  # Int53 is the portable default → `Long`
  "pub def i53(n Int53) Int53 := n + 1",
  # ── inc 2: the multi-clause dispatcher (if-chain, literal tests, when guards, throw tail) ──
  # a literal clause then a var fallthrough (the var clause closes — no throw)
  "def f(n Int64) Int64\ndef f(0) := 1\ndef f(n) := n * 2",
  # recursion through the dispatcher (factorial)
  "pub def fac(n Int64) Int64\ndef fac(0) := 1\ndef fac(n) := n * fac(n - 1)",
  # a wildcard pattern (no test, no bind) beside a literal
  "def mul(a Int64, b Int64) Int64\ndef mul(0, _) := 0\ndef mul(a, b) := a * b",
  # a `when` guard with no structural test → a scoped `run { … }`, then a fallthrough
  "def max2(a Int64, b Int64) Int64\ndef max2(a, b) when a >= b := a\ndef max2(a, b) := b",
  # a guard riding a clause with a structural test absent (var head + guard → `run`), fallthrough
  "def g(n Int64) Int64\ndef g(n) when n > 10 := 100\ndef g(n) := n",
  # a non-total clause set → the trailing `throw RuntimeException(\"…: no clause matched\")`
  "def only0(n Int64) Int64\ndef only0(0) := 1",
  # a String literal pattern (`==` against the Kotlin string)
  ~S|def label(s String) Int64
def label("yes") := 1
def label(_) := 0|,
  # multiple positional literal tests joined by `&&`
  "def both0(a Int64, b Int64) Bool\ndef both0(0, 0) := true\ndef both0(a, b) := false",
  # ── inc 3: sum variants (sealed interface + data class, smart-cast `is`, `case`) ──
  # a recursive sum + ctor clause patterns (smart-cast `is Ctor`, positional `.f0`/`.f1` binds)
  "type Expr := Num(Int64) | Add(Expr, Expr)\ndef ev(e Expr) Int64\ndef ev(Num(n)) := n\ndef ev(Add(a, b)) := ev(a) + ev(b)",
  # labeled (`data class Circle(val radius: Long)`) + positional fields side by side
  "type Shape := Circle(radius Int64) | Sq(Int64)\ndef area(s Shape) Int64\ndef area(Circle(radius)) := radius * radius\ndef area(Sq(n)) := n * n",
  # a nullary variant → a singleton `object`; the construction `Num(5)` lowers to `Num(5L)`
  "type Expr := Lit(Int64) | Neg(Expr)\npub def build() Expr := Neg(Lit(5))\ndef ev(e Expr) Int64\ndef ev(Lit(n)) := n\ndef ev(Neg(x)) := 0 - ev(x)",
  # a `case` over a sum (nullary arms → `is A`/`is B`, → a labelled `run rcase@{ … }`)
  "type T := A | B\ndef f(t T) Int64 := case t do\n  A -> 1\n  B -> 2\nend",
  # a `case` with a ctor arm that binds a field
  "type Opt := Som(Int64) | Non\ndef get(o Opt) Int64 := case o do\n  Som(x) -> x\n  Non -> 0\nend",
  # a `case` arm carrying a `when` guard (tests + guard → a conditional `if`)
  "type Box := B(Int64)\ndef f(b Box) Int64 := case b do\n  B(n) when n > 0 -> n\n  B(n) -> 0 - n\nend",
  # ── inc 4: strings / chars / symbols (the `Prim.*` intrinsics + atom/char patterns) ──
  # a `Char` literal value + pattern → its codepoint `Long` (`'a'` → `97L`)
  ~S|def f(c Char) Int64
def f('a') := 1
def f(c) := 0|,
  "pub def ay() Char := 'a'",
  # a `Symbol`/atom pattern tests the interned name as a Kotlin String
  "def g(s Symbol) Int64\ndef g(:ok) := 1\ndef g(s) := 0",
  # the string prims: `<>`-concat via `Prim.str_concat`, codepoint `Prim.char_code`/`char_to_string`
  "pub def cat(a String, b String) String := Prim.str_concat(a, b)",
  "pub def cc(c Char) Int64 := Prim.char_code(c)",
  "pub def cstr(c Char) String := Prim.char_to_string(c)",
  # string interpolation (ADR-0069) → `__prim_str_concat_all` (+ `__prim_int_to_string` for `${int}`)
  ~S|pub def greet(s String) String := "hi ${s}"|,
  ~S|pub def show(n Int64) String := "n=${n}"|,
  # ── inc 5: lists / `Vec(T)` → Kotlin `List<T>` (`listOf`, cons `+`, size/index/drop) ──
  # (`Int53` — the portable default — so the literals need no width adoption; both → `Long`.
  # A `Vec(Int64)` literal return is held back: PS `Check` doesn't yet adopt the declared list
  # width, an unrelated `gate`-stream gap, not a JVM one.)
  "pub def three() Vec(Int53) := [1, 2, 3]",
  # a cons literal → `(listOf(x) + xs)`; `Vec(Int64)` param → `List<Long>`
  "pub def pre(x Int64, xs Vec(Int64)) Vec(Int64) := [x | xs]",
  # list clause patterns: a closed `[a, b]` tests `size ==`, a cons `[_ | t]` tests `size >=`
  "def pair(xs Vec(Int64)) Int64\ndef pair([a, b]) := a + b\ndef pair(xs) := 0",
  # recursion over a list (length) through the dispatcher
  "def len(xs Vec(Int64)) Int64\ndef len([]) := 0\ndef len([_ | t]) := 1 + len(t)",
  # a `case` over a list
  "def first(xs Vec(Int64)) Int64 := case xs do\n  [] -> 0\n  [h | _] -> h\nend",
  # nested `Vec(Vec(Int64))` → `List<List<Long>>`
  "pub def empty() Vec(Vec(Int64)) := []",
  # ── inc 6: structs → Kotlin `data class` (named fields, `.x` access, `is`/`as` patterns) ──
  # a `struct` decl + field access + labeled construction (`Point(x = 0L, y = 0L)`)
  "struct Point(x Int64, y Int64)\npub def area(p Point) Int64 := p.x * p.y\npub def origin() Point := Point(x: 0, y: 0)",
  # a struct clause pattern smart-casts (`a0 is Point`) and reads `(a0 as Point).x`
  "struct Point(x Int64, y Int64)\ndef getx(p Point) Int64\ndef getx(Point(x: a, y: b)) := a",
  # a struct carrying a `Vec` field (`val items: List<Long>`)
  "struct Bag(items Vec(Int64))\npub def mk(xs Vec(Int64)) Bag := Bag(items: xs)",
  # ── inc 7: generics + `Fn` types + lambdas + tuples (the HOF core, ADR-0061) ──
  # a generic function → `fun <T : Any> id(a0: T): T`
  "pub def id(x T) T forall T := x",
  # an `Fn(a, r)` parameter → `(Long) -> Long`; calling it is a plain call
  "pub def apply(f Fn(Int64, Int64), n Int64) Int64 := f(n)",
  # a lambda value → `{ n -> (n + 1L) }`, returned as an `Fn`
  "pub def inc() Fn(Int64, Int64) := (n) -> n + 1",
  # passing a lambda as a call argument
  "pub def apply2(f Fn(Int64, Int64), n Int64) Int64 := f(n)\npub def use2() Int64 := apply2((x) -> x * 2, 5)",
  # a 2-tuple value/type → `Pair`; the pattern destructures via `componentN()`
  "pub def mk2(a Int64, b Int64) (Int64, Int64) := {a, b}",
  "def fst(p (Int64, Int64)) Int64\ndef fst({a, b}) := a",
  # a 3-tuple → `Triple`
  "pub def tri(a Int64, b Int64, c Int64) (Int64, Int64, Int64) := {a, b, c}",
  # ── inc 8: protocols → a `when (a0)` runtime dispatcher over the receiver type (ADR-0042) ──
  # a protocol + two impls (`impl_eq_int64_eq`/`impl_eq_string_eq` stay regular funs) + a
  # dispatcher `eq(a0: Any, a1: Any) = when (a0) { is Long -> …; is String -> … }`
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Int64 do\n  def eq(a, b) := a == b\nend\nimpl Eq for String do\n  def eq(a, b) := a == b\nend\npub def same(a Int64, b Int64) Bool := eq(a, b)",
  # a bounded-generic consumer (`forall T: Eq`) — the bound erases to `<T : Any>`, the call
  # goes through the dynamic dispatcher
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Int64 do\n  def eq(a, b) := a == b\nend\npub def member(x T, y T) Bool forall T: Eq := eq(x, y)",
  # a protocol impl over a user sum type → an `is <Sum>` dispatcher arm (a var-head impl)
  "protocol Sz do\n  def sz(x Self) Int64\nend\ntype Bag := Bag(Int64)\nimpl Sz for Bag do\n  def sz(b) := 42\nend\npub def go(b Bag) Int64 := sz(b)",
  # ── ktType fidelity (review fix): `Dict(K,V)` → `Map<K,V>`, and the nominal `^[A-Z]` fallback ──
  # a `Dict(K, V)` type → a Kotlin `Map<K, V>` (passthrough — map *operations* are a later increment)
  "pub def passthru(d Dict(String, Int64)) Dict(String, Int64) := d",
  # a ctor-pattern impl head `def sz(Bag(n))` → the shared protocol-desugar now binds a fresh
  # typed receiver and moves the pattern into a `case` (`Rian.Protocol.impl_clause`, the
  # ctor-impl-head fix), so it lowers to VALID Kotlin (`a0: Bag` + a smart-cast case) — kotlinc-clean
  "protocol Sz do\n  def sz(x Self) Int64\nend\ntype Bag := Bag(Int64)\nimpl Sz for Bag do\n  def sz(Bag(n)) := n\nend\npub def go(b Bag) Int64 := sz(b)",
  # a multi-statement body (`:=` bind then value) → a scoped `run { val …; … }` (+ a `${…}` hole)
  "pub def hi(who String) String := name := who ; \"Hello, ${name}!\"",
  # ── Dict / map operations (Phase 5): `Dict(K,V)` → `Map<K,V>`, ops → Kotlin `Map` ops ──
  # a map literal `%{k: v, …}` → `mapOf("k" to v, …)` (Int53 values dodge the Check width gap)
  "pub def m() Dict(Symbol, Int53) := %{a: 1, b: 2}",
  # an empty map literal `%{}` → `mapOf()`
  "pub def e() Dict(Symbol, Int53) := %{}",
  # `Map.get` → `(m).getValue("k")`
  "pub def g(m Dict(Symbol, Int53)) Int53 := Map.get(m, :a)",
  # `Map.put` → `((m) + ("k" to v))`
  "pub def p(m Dict(Symbol, Int53)) Dict(Symbol, Int53) := Map.put(m, :c, 3)",
  # `Map.has` → `(m).containsKey("k")`
  "pub def h(m Dict(Symbol, Int53)) Bool := Map.has(m, :a)",
  # a map pattern `%{k: x}` in a `case` → a `containsKey` guard + `getValue` bind
  "pub def f(m Dict(Symbol, Int53)) Int53 := case m do\n  %{a: x} -> x\n  _ -> 0\nend",
  # ── captures (`&/1`) + `with` (Phase 5; shared `Core.capArity`/`desugarWith`) ──
  # an anonymous capture `&(&1 * 2)` → a Kotlin lambda `{ _1 -> (_1 * 2L) }`
  "pub def mk() Fn(Int53, Int53) := &(&1 * 2)",
  # a named capture `&inc/1` → a Kotlin function reference `::inc`
  "pub def inc(n Int53) Int53 := n + 1\npub def mk() Fn(Int53, Int53) := &inc/1",
  # an anonymous capture passed through a `Fn` parameter (a full apply program)
  "pub def apply(f Fn(Int53, Int53), x Int53) Int53 := f(x)\npub def go() Int53 := apply(&(&1 * 2), 5)",
  # `with Some(v) <- x do v else _ -> 0 end` → nested `case`s (ADR-0040, via `desugarWith`)
  "type Box := Some(Int53) | None\npub def f(x Box) Int53 := with Some(v) <- x do\n  v\nelse\n  _ -> 0\nend",
  # ── associated types (ADR-0074): an assoc `Elem` in a covariant `Vec(...)` return erases to
  # `List<Any>` (the `to_list` dispatcher); an element-AGNOSTIC consumer (generic `len`) needs no
  # use-site cast, so this lowers + kotlinc-compiles with the assoc-erasure pass alone.
  "protocol Foldable do\n  type Elem\n  def to_list(self Self) Vec(Elem)\nend\ntype Bag := Bag(items Vec(Int53))\nimpl Foldable for Bag do\n  type Elem := Int53\n  def to_list(b) := case b do Bag(xs) -> xs end\nend\npub def len(xs Vec(T)) Int53 forall T := case xs do\n  [] -> 0\n  [_ | t] -> 1 + len(t)\nend\npub def fcount(c C) Int53 forall C := len(to_list(c))",
  # the `coerce_casts` use-site cast (ADR-0074): an erased `to_list(c)` (`List<Any>`) flowing into a
  # CONCRETE `Vec(Int53)` param (`sum_l`) gets an `as List<Long>` cast (`sum_l((to_list(c) as List<Long>))`)
  "protocol Foldable do\n  type Elem\n  def to_list(self Self) Vec(Elem)\nend\ntype Bag := Bag(items Vec(Int53))\nimpl Foldable for Bag do\n  type Elem := Int53\n  def to_list(b) := case b do Bag(xs) -> xs end\nend\npub def sum_l(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [h | t] -> h + sum_l(t)\nend\npub def fsum(c C) Int53 forall C := sum_l(to_list(c))",
  # the env-bound variant: the erased result is BOUND to a local first (`xs := to_list(c)`), then
  # flows into the concrete param — the `env` of erased-bound locals threads through the block so
  # `xs` casts too (`run { val xs = to_list(c); sum_l((xs as List<Long>)) }`)
  "protocol Foldable do\n  type Elem\n  def to_list(self Self) Vec(Elem)\nend\ntype Bag := Bag(items Vec(Int53))\nimpl Foldable for Bag do\n  type Elem := Int53\n  def to_list(b) := case b do Bag(xs) -> xs end\nend\npub def sum_l(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [h | t] -> h + sum_l(t)\nend\npub def fsum2(c C) Int53 forall C := xs := to_list(c) ; sum_l(xs)"
]

# Rian.Lower.rust_program — the `rustprog` stream: the WHOLE-PROGRAM Rust assembly (ADR-0061)
# — one module, every struct/enum/trait/impl emitted ONCE (vs the per-unit-repeating `rust`
# stream / `Decl.compile`), then every non-dispatch fn. Oracle = `Rian.Lower.rust_program`.
# Covers: the once-assembly (no per-unit type repeat), protocol `trait`/`impl` blocks.
rustprog_corpus = [
  # baseline: a function-only program assembles to just the fn
  "pub def add(x Int53, y Int53) Int53 := x + y",
  # a sum type's `enum` is emitted ONCE here (the `rust` stream repeats it per unit)
  "type Shape := Circle(Float64) | Square(Float64)\npub def area(Shape) Float64\npub def area(Circle(r)) := r\npub def area(Square(s)) := s",
  # a protocol + impl → `trait RianEq { … }` + `impl RianEq for bool { fn eq(&self, b: &bool) … }`
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\nimpl Eq for Bool do\n  def eq(a, b) := a == b\nend",
  # a bounded-generic consumer alongside the protocol (no impl): trait + `<T: RianEq + Clone>`
  "protocol Eq do\n  def eq(a Self, b Self) Bool\nend\npub def same(a T, b T) Bool forall T: Eq := eq(a, b)",
  # parametric-type monomorphization (ADR-0061): `type Box := B(v T)` → `enum Box<T: Clone>`;
  # the signature `Box` → `Box<T>`; construction clones the borrowed payload (`B { v: x.clone() }`)
  "type Box := B(v T)\npub def wrap(x T) Box forall T := B(x)\npub def unwrap(b Box) T forall T := case b do\n  B(v) -> v\nend",
  # two type params: `enum Pair<K: Clone, V: Clone>`, `-> Pair<K, V>`, both payloads cloned
  "type Pair := P(k K, v V)\npub def mk(a K, b V) Pair forall K, V := P(a, b)",
  # deeper borrows (ADR-0047 Gap D/E). slice-leaf `.to_vec()`: a `val Vec` param (`&[i64]`)
  # returned where the signature promises an owned `Vec<i64>` → `cs.to_vec()`
  "pub def keep(cs val Vec(Int53)) Vec(Int53) := cs",
  # iso owned-`Vec` + cons-head rebind: an `iso Vec` matched via `.as_slice()`, the head `&i64`
  # cloned and the tail `&[i64]` rebound `to_vec()` so the recursive call takes an owned `Vec`
  "pub def sum(xs iso Vec(Int53)) Int53\npub def sum([]) := 0\npub def sum([h | t]) := h + sum(t)",
  # iso `Vec` rebuilt + returned owned: the rebinds plus the cons-rebuild owned-`Vec` return
  "pub def dup(xs iso Vec(Int53)) Vec(Int53)\npub def dup([]) := []\npub def dup([h | t]) := [h, h | dup(t)]",
  # string interpolation (ADR-0069) → one `format!` (`__prim_str_concat_all`), with `${int}`
  # going through `__prim_int_to_string` → `.to_string()`; a `:=` bind of a string literal owns it
  # (`let name = "Rian".to_string()`, `rust_owned_elem`)
  "pub def greet(age Int53) String := name := \"Rian\" ; \"hi ${name}, you are ${age}!\"",
  # ── Rust mop-up (Phase 5): HashMap prims, captures (&/1), with ──
  # `Map(K,V)` → `std::collections::HashMap`; `Prim.map_get` → `.get(k).cloned().unwrap()`
  "pub def g(m Map(Symbol, Int53)) Int53 := Prim.map_get(m, :a)",
  # `Prim.map_put` → a functional update (clone the map, insert cloned k/v)
  "pub def p(m Map(Symbol, Int53)) Map(Symbol, Int53) := Prim.map_put(m, :c, 3)",
  # `Prim.map_has` → `.contains_key(k)`; `Prim.map_new` → `HashMap::new()`
  "pub def h(m Map(Symbol, Int53)) Bool := Prim.map_has(m, :a)",
  "pub def e() Map(Symbol, Int53) := Prim.map_new()",
  # an anonymous capture `&(&1 * 2)` → an explicit closure `|a1| a1 * 2`
  # a named capture `&inc/1` → a forwarding closure `|a0| inc(a0)`
  # (parity-only: the reference emits a *bare* closure in return position — not nameable Rust
  # without `Box<dyn Fn>`/`impl Fn`; the PS port mirrors it byte-for-byte. Reach pins such a fn off :rs.)
  "pub def mk() Fn(Int53, Int53) := &(&1 * 2)",
  "pub def inc(n Int53) Int53 := n + 1\npub def mk() Fn(Int53, Int53) := &inc/1",
  # `with Wrap(v) <- x do v else _ -> 0 end` → a nested `match` chain (ADR-0040, `with_chain_rs`).
  # Ctor names avoid `Some`/`None` (a user variant colliding with the prelude `Option` exposes a
  # *separate* pre-existing patRs ctor→enum resolution divergence on Rust, not a `with` one).
  # parity-only: the reference's `with` body returns the borrowed `v` (a `&i64`) un-coerced — the
  # clause/case path's borrow-coercion isn't applied to `with` bodies (a pre-existing reference gap),
  # so it is not rustc-valid; the PS port mirrors it exactly.
  "type Box := Wrap(Int53) | Empty\npub def f(x Box) Int53 := with Wrap(v) <- x do\n  v\nelse\n  _ -> 0\nend"
]

# Rian.Shadow corpus — the `shd` stream (ADR-0034): capture-avoiding `:=` rename. Params
# fixed `["p"]` so a `p :=` rebind renames; the fresh scheme is `base$count`.
shadow_corpus = [
  "p := 1 ; p",
  "x := 1 ; x := 2 ; x",
  "x := 1 ; y := x + 1 ; y",
  "x := 1 ; x := 2 ; case x do\n  x -> x\nend",
  "a := s ; a",
  "x := 1 ; x := x + 1 ; x := x * 2 ; x",
  # `<-` error-propagation desugar (ADR-0066): a single arrow, a nested chain, and a
  # `:=` bind before the arrow (the `before` stmts pass through).
  "x <- foo() ; bar(x)",
  "a <- f() ; b <- g(a) ; c(a, b)",
  "y := 1 ; x <- foo(y) ; bar(x, y)",
  # destructuring binds (ADR-0066 P4): tuple, cons, ctor; and one mixed with `<-`.
  "{a, b} := pair ; a + b",
  "[h | t] := xs ; h",
  "Ok(v) := r ; v",
  "{a, b} := p ; x <- f(a) ; g(x, b)"
]

# Rian.Macro corpus — the `mac` stream. A FIXED macro env (mirrored byte-for-byte in
# `Rian.Macro.testDefs`, PS); a call expression is expanded, lowered to Core, and serialized
# via the shared `coreSexpr` oracle. Templates are binder-free (so `freshen`'s non-deterministic
# gensym never fires). The corpus exercises substitution, nested expansion, and `mapNode`.
macro_defs = [
  %{name: "double", params: ["x"], template: "x + x"},
  %{name: "inc", params: ["x"], template: "x + 1"},
  %{name: "swap", params: ["a", "b"], template: "(b, a)"},
  %{name: "apply", params: ["f", "x"], template: "f(x)"},
  %{name: "pick", params: ["c", "a", "b"], template: "if c do a else b end"}
]

mac_corpus = [
  "double(3)",
  "inc(double(2))",
  "swap(1, 2)",
  "apply(g, 5)",
  "pick(true, 1, 2)",
  "double(a) + inc(b)",
  "double(inc(x))",
  "not_a_macro(1)"
]

# Rian.Builtins corpus — the `bui` stream: host/stdlib foreign-call signatures
# (`mod;fun;arity`; `mod=nil` = Kernel auto-import). Covers table hits across modules,
# the `Int`-vs-`Int53` arbitrary-precision returns, misses, and poly-only entries (which
# are NOT `known?` — that checks the concrete-return table only).
builtins_corpus = [
  "nil;map_size;1",
  "nil;inspect;1",
  "nil;is_atom;1",
  "nil;to_string;1",
  "String;trim;1",
  "String;length;1",
  "String;to_integer;1",
  "String;split;2",
  "String;to_atom;1",
  "Enum;count;1",
  "Enum;join;2",
  "erlang;phash2;1",
  "erlang;binary_to_integer;1",
  "erlang;system_time;0",
  "IO;puts;1",
  "math;pi;0",
  "math;sqrt;1",
  "nil;nope;1",
  "String;trim;9",
  "List;map;2",
  "List;reverse;1",
  "Enum;filter;2",
  "Enum;map_reduce;3",
  "Map;new;0",
  "Map;put;3",
  "Map;merge;2"
]

# Rian.Check type-algebra corpus (ADR-0084 stage 1). `unify` (partial-inference vs decl:
# Unknown is a wildcard) and `join` (branch/arm LUB: Unknown absorbs, Bottom identity,
# numeric widening, covariant parametric). Pairs are `t;;u`.
check_unify_corpus = [
  "Int53;;Int53",
  ":unknown;;Int53",
  "Int53;;:unknown",
  "Any;;Int53",
  "Int53;;Any",
  "Int53;;Bool",
  "Fn(_,Int64);;Fn(Int64,Int64)",
  "Fn(Int64,Int64);;Fn(_,Int64)",
  "Fn(_,Int64);;Fn(Int64,Bool)",
  "Fn(Int64,Int64);;Fn(Int64)",
  "Fn(T,Int64);;Fn(Int64,Int64)",
  "Fn(_,Int53);;Fn(Int64,Int64)",
  "Fn(Int64,Fn(_,Bool));;Fn(Int64,Fn(Int64,Bool))",
  "Vec(Int53);;Vec(Int53)",
  "Vec(Int53);;Vec(Bool)"
]

# Rian.Check.infer stage 2 — the expression core, over the fixed env (x,y:Int64; n:Int53;
# b:Bool; s:String; f:Float64; c:Char; xs:Vec(Int53)). Excludes if/case/call/lambda/.field.
check_infer_corpus = [
  "1",
  "1.5",
  "2e3",
  "\"hi\"",
  "'a'",
  "true",
  "x",
  "n",
  "xs",
  "-x",
  "not b",
  "x + y",
  "x + 1",
  "1 + x",
  "n - 1",
  "x * y",
  "(13 - n) * 10",
  "x < y",
  "b and b",
  "n == n",
  "s <> s",
  "x / y",
  "n div n",
  "c - c",
  "c + 1",
  "[1, 2, 3]",
  "[x, y]",
  "[x, 1]",
  "[]",
  "{x, s}",
  "{1, b}",
  "{n}",
  "%{a: 1, b: 2}",
  "%{a: x, b: n}",
  # stage 3a: if (branch-join + value unions) + lambdas (arrow types)
  "if b do x else y end",
  "if b do 1 else 2 end",
  "if b do x else 1 end",
  "if b do n else x end",
  "if b do b else b end",
  "if b do x else s end",
  "if b do 1 else s end",
  "if b do x else f end",
  "if b do c else n end",
  "(x) -> x",
  "(a Int64) -> a",
  "(a Int64, b Int64) -> a + b",
  "(a) -> not a",
  "() -> 1",
  # stage 3b: calls — prims, inspect, builtin returns, Fn-typed-var application
  "map_size(xs)",
  "inspect(x)",
  "is_atom(x)",
  "nope(x)",
  "String.trim(s)",
  "String.length(s)",
  "String.to_integer(s)",
  "Path.join(s, s)",
  "Regex.escape(s)",
  "math.sqrt(f)",
  ":erlang.phash2(x)",
  "g(x)",
  "Prim.char_code(c)",
  "Prim.int_to_float(n)",
  "Prim.char_to_string(c)",
  "panic(s)",
  # stage 3c: poly stdlib generics (tvar instantiation from arg types, Any-fill when unbound)
  "List.reverse(xs)",
  "List.map(xs, g)",
  "Enum.filter(xs, g)",
  "Map.new()",
  "Map.put(xs, x, n)"
]

# Rian.Check.infer over function BODIES — the `bdy` stream (parseBody: `;`-separated
# statements with binds threaded through the env; the block's type is its last statement).
check_body_corpus = [
  "x + 1",
  "n",
  "z := x ; z + 1",
  "w Int8 := 5 ; w",
  "a := 1 ; b := a + 2 ; b",
  "p := n ; q := p * 10 ; q",
  "t := s ; t",
  "u := [x, y] ; u"
]

# Rian.Check.annotate — the `ann` stream: per-node types of an annotated body, pre-order (`_` =
# `nil`). Exercises typed nodes (leaves/bin/if/list/tuple/block-binds/call) and the reference's
# `nil` catch-alls (a lambda body, a `Mod.fun` dot head). Prim-free so `normalize` is identity.
ann_corpus = [
  "x + 1",
  "n",
  "z := x ; z + 1",
  "w Int8 := 5 ; w",
  "if b do n else x end",
  "[x, n]",
  "{x, b}",
  "(a Int64) -> a",
  "String.length(s)"
]

check_join_corpus = [
  "Int64;;Int64",
  ":bottom;;Int64",
  "Int64;;:bottom",
  "_Unk;;Bool",
  "Bool;;_Unk",
  "Any;;Int64",
  "Int64;;Any",
  ":unknown;;Int64",
  "Int8;;Int16",
  "UInt8;;UInt32",
  "Float32;;Float64",
  "UInt8;;Int16",
  "UInt32;;Int8",
  "UInt64;;Int8",
  "Int32;;Float64",
  "Int64;;Float64",
  "Int16;;Float32",
  "Vec(Int8);;Vec(Int16)",
  "Option(Int8);;Option(Int16)",
  "Vec(Int8);;Vec(Bool)",
  "Map(String,Int8);;Map(String,Int16)",
  "Vec(Option(Int8));;Vec(Option(Int16))",
  "Vec(Int8);;Option(Int8)",
  "Fn(Int8,Int8);;Fn(Int16,Int16)",
  "Bool;;String",
  "Int;;Int64"
]

# Rian.Coherence corpus — the `coh` stream (ADR-0061 §5). Single top-level scope, run
# **synthesis-free** (`Decl.coherence_violations`), so an INCOHERENT program — which the
# parse-time desugar would *raise* on — still yields its violation list on both sides.
# Each entry exercises one rule (or, for the first/last, the no-violation path).
coh_corpus = [
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def m(x) := true\nend",
  "impl Nope for Int64 do\n  def f(x) := x\nend",
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def wrong(x) := true\nend",
  "protocol Q do\n  def m(a Self, b Self) Bool\nend\nimpl Q for Int64 do\n  def m(a) := true\nend",
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def m(x) := true\nend\nimpl P for Int64 do\n  def m(x) := false\nend",
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def m(x) := true\nend\nimpl P for Char do\n  def m(x) := false\nend",
  "protocol Show do\n  def show(x Self) String\nend\nimpl Show for T do\n  def show(x) := \"x\"\nend",
  "type Foo := A | B\nprotocol P do\n  def m(x Self) Bool\nend\nimpl P for Foo do\n  def m(x) := true\nend"
]

# Rian.Coherence `@targets(:rs)` corpus — the `cohrs` stream. The SAME synthesis-free scope,
# but run for a Rust-only scope: a Rust-only module dispatches on static types, so the
# shared-runtime-discriminator rule is EXEMPT — while a `duplicate` (proto,type) or a
# method-set/arity mismatch still fires (those are not target-gated). Exercises the
# `runtime_dispatch_target([:rs]) == false` branch the `coh` stream (targets=nil) cannot reach.
cohrs_corpus = [
  # shared discriminator Int64+Char → exempt under :rs (empty); reported under nil (in `coh`).
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def m(x) := true\nend\nimpl P for Char do\n  def m(x) := false\nend",
  # a duplicate (proto,type) still fires under :rs — not a discriminator rule.
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def m(x) := true\nend\nimpl P for Int64 do\n  def m(x) := false\nend",
  # a method-set mismatch still fires under :rs.
  "protocol P do\n  def m(x Self) Bool\nend\nimpl P for Int64 do\n  def wrong(x) := true\nend"
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
# interpolation, bitstrings (no shared Core oracle / staged); map *update* is covered.
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
  "%{m | a: 1}",
  "%{m | a: 1, b: 2}",
  ~S(%{base | "k" => v}),
  ":ok",
  "if c do a else b end",
  "if c do a end",
  "case x do 1 -> a\n_ -> b end",
  "case t do {a, b} -> a\n_ -> 0 end",
  "case r do Ok(v) -> v\nErr(e) -> e end",
  "case xs do [] -> 0\n[h | t] -> h end",
  "case p do Point(x: a, y: b) -> a\n_ -> 0 end",
  "case x do n Int53 -> n\n_ -> 0 end",
  "case v do n Int53 -> n\ns String -> 0 end",
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

# Rian.PatternLower + Rian.Exhaustiveness gate corpus (the `plw` / `exh` streams). Each
# scenario builds a signature env (base + add_type / add_range), lowers real source-parsed
# pattern vectors through `PatternLower.lower_clause`, then runs `Exhaustiveness.analyze`.
# The scenario table is mirrored byte-for-byte in `Rian.Exhaustiveness.scenarios` (PS).
defmodule ShadowCanon do
  # the `shd` stream: dedup a `;`-separated body (params fixed `["p"]`, fresh `base$count`),
  # composing parse_body → Core → Shadow.dedup, serialized as a block via CoreCanon.
  def run(src) do
    block = Rian.Core.from_expr(Rian.Pratt.parse_body(src))

    stmts =
      case block do
        %Rian.Core.EBlock{stmts: ss} -> ss
        e -> [{:expr, e}]
      end

    result = Rian.Shadow.dedup(stmts, ["p"], fn b, c -> "#{b}$#{c}" end)
    CoreCanon.expr(%Rian.Core.EBlock{stmts: result})
  end
end

defmodule BuiltinsCanon do
  # the `bui` stream: `known?`/`ret`/`poly_sig` for a `mod;fun;arity` key (`mod` = `nil` for a
  # Kernel auto-import). Mirrors `Builtins.builtinSexpr` in PureScript.
  def run(src) do
    [m, f, a] = String.split(src, ";")
    modv = if m == "nil", do: nil, else: m
    arity = String.to_integer(a)

    "known=#{Rian.Builtins.known?(modv, f, arity)} ret=#{ret(modv, f, arity)} poly=#{poly(modv, f, arity)}"
  end

  defp ret(m, f, a), do: Rian.Builtins.ret(m, f, a) || ":nil"

  defp poly(m, f, a) do
    case Rian.Builtins.poly_sig(m, f, a) do
      nil -> ":nil"
      {params, r, tvars} -> "(#{Enum.join(params, ",")});#{r};#{Enum.join(tvars, ",")}"
    end
  end
end

defmodule CheckCanon do
  # the `uni`/`joi` streams: a `t;;u` pair through `Rian.Check.unify`/`join`. The Elixir `ty`
  # is `String | :unknown | :mismatch | :bottom`; the sentinels are spelled `:unknown` etc.
  def run(op, src) do
    [a, b] = String.split(src, ";;")
    out(apply(Rian.Check, op, [tin(a), tin(b)]))
  end

  # the `pic` stream: dump `Rian.Check.program_ic`'s 9 tables, each sorted by key.
  def ic_dump(src) do
    ic = Rian.Check.program_ic(Rian.Decl.parse(src, assemble_only: true))

    Enum.join(
      [
        "tdefs " <> ic_t(ic.tdefs, fn fts -> Enum.join(fts, ",") end),
        "fields " <>
          ic_t(ic.fields, fn fs -> Enum.map_join(fs, ",", fn {f, ty} -> "#{f}:#{ty}" end) end),
        "funs " <> ic_tk(ic.funs, &ic_ms/1),
        "fsigs " <> ic_tk(ic.fsigs, &ic_fs/1),
        "ctors " <> ic_t(ic.ctors, & &1),
        "ranges " <> ic_t(ic.ranges, fn r -> "#{r.base}:#{r.lo}:#{r.hi}" end),
        "opaques " <>
          ic_t(ic.opaques, fn o ->
            "#{o.base}|#{Enum.join(o.ops, ",")}|#{Enum.join(o.casts, ",")}"
          end),
        "impls " <> ic_t(ic.impls, fn ts -> Enum.join(Enum.sort(MapSet.to_list(ts)), ",") end),
        "fbounds " <> ic_t(ic.fbounds, &ic_fb/1)
      ],
      "\n"
    )
  end

  defp ic_t(m, vf),
    do: m |> Enum.map(fn {k, v} -> "#{k}=>#{vf.(v)}" end) |> Enum.sort() |> Enum.join(";")

  defp ic_tk(m, vf),
    do:
      m |> Enum.map(fn {{n, a}, v} -> "#{n}/#{a}=>#{vf.(v)}" end) |> Enum.sort() |> Enum.join(";")

  defp ic_ms(nil), do: "_"
  defp ic_ms(s), do: s

  defp ic_fs(%{params: p, ret: r, tvars: tv}),
    do: "#{Enum.map_join(p, ",", &ic_ms/1)}|#{ic_ms(r)}|#{Enum.join(tv, ",")}"

  defp ic_fb(%{params: p, tvars: tv, bounds: b}),
    do:
      "#{Enum.map_join(p, ",", &ic_ms/1)}|#{Enum.join(tv, ",")}|#{b |> Enum.sort() |> Enum.map_join(",", fn {tt, ps} -> "#{tt}:#{Enum.join(ps, "+")}" end)}"

  defp tin(":unknown"), do: :unknown
  defp tin(":mismatch"), do: :mismatch
  defp tin(":bottom"), do: :bottom
  defp tin(s), do: s

  defp out(:unknown), do: ":unknown"
  defp out(:mismatch), do: ":mismatch"
  defp out(:bottom), do: ":bottom"
  defp out(s) when is_binary(s), do: s

  # the `inf` stream: infer an expression under a fixed env (mirrors `Check.fixedEnv` in PS),
  # composing lexer → Pratt → Core → Check.infer (empty inference context).
  @fixed_env %{
    "x" => "Int64",
    "y" => "Int64",
    "n" => "Int53",
    "b" => "Bool",
    "s" => "String",
    "f" => "Float64",
    "c" => "Char",
    "xs" => "Vec(Int53)",
    "g" => "Fn(Int64,Bool)"
  }

  def infer(src) do
    out(Rian.Check.infer(Rian.Core.from_expr(Rian.Pratt.parse(src)), @fixed_env, %{}))
  end

  # the `ifc` stream: infer `expr` under a real `ic` built from `program_ic` over the leading
  # `prog`, the two `;;`-separated. Tests the ic-using call clauses (ctor / user-fn / cross-module).
  def infer_ic(src) do
    [prog, expr] = String.split(src, ";;")
    ic = Rian.Check.program_ic(Rian.Decl.parse(prog, assemble_only: true))
    out(Rian.Check.infer(Rian.Core.from_expr(Rian.Pratt.parse(expr)), @fixed_env, ic))
  end

  # the `irt` stream: each function's `infer_return_type` under a filled `ic` (`program_ic`).
  def infer_ret(src) do
    prog = Rian.Decl.parse(src, assemble_only: true)
    ic = Rian.Check.program_ic(prog)
    funcs = Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

    funcs
    |> Enum.map(fn f ->
      "#{f.name}/#{length(f.params)}=>#{out(Rian.Check.infer_return_type(f, ic))}"
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # the `flr` stream: the `fill_local_rets` converged funs table (un-annotated returns filled).
  def fill_rets(src) do
    prog = Rian.Decl.parse(src, assemble_only: true)
    ic = Rian.Check.program_ic(prog)
    funcs = Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

    Rian.Check.fill_local_rets(funcs, ic)
    |> Enum.map(fn {{n, a}, r} -> "#{n}/#{a}=>#{r || "_"}" end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # the `ilr` stream: every function's return after `Rian.InferLocal.fill_returns`.
  def fill_returns(src) do
    filled = Rian.InferLocal.fill_returns(Rian.Decl.parse(src, assemble_only: true))
    funcs = Map.get(filled, :funcs, []) ++ Enum.flat_map(Map.get(filled, :mods, []), & &1.funcs)

    funcs
    |> Enum.map(fn f -> "#{f.name}/#{length(f.params)}=>#{f.ret || "_"}" end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # the `ilp` stream: each function's FULL inferred signature after `fill_returns` —
  # `name/arity:p0,p1=>ret[tvars]` (proves parameter inference + `forall T` generalization).
  def fill_sig(src) do
    filled = Rian.InferLocal.fill_returns(Rian.Decl.parse(src, assemble_only: true))
    funcs = Map.get(filled, :funcs, []) ++ Enum.flat_map(Map.get(filled, :mods, []), & &1.funcs)
    pty = fn t -> if is_binary(t), do: t, else: "_" end

    funcs
    |> Enum.map(fn f ->
      ptys = f.params |> Enum.map(fn p -> pty.(p.type) end) |> Enum.join(",")
      tv = if f.tvars == [], do: "", else: "[" <> Enum.join(f.tvars, ",") <> "]"
      "#{f.name}/#{length(f.params)}:#{ptys}=>#{f.ret || "_"}#{tv}"
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # the `ipt` stream: each function's parameters' `infer_param_type` (`name/i=>type`) under a
  # filled `ic`.
  def infer_param(src) do
    prog = Rian.Decl.parse(src, assemble_only: true)
    ic = Rian.Check.program_ic(prog)
    funcs = Map.get(prog, :funcs, []) ++ Enum.flat_map(Map.get(prog, :mods, []), & &1.funcs)

    funcs
    |> Enum.flat_map(fn f ->
      Enum.map(0..(length(f.params) - 1)//1, fn i ->
        "#{f.name}/#{i}=>#{out(Rian.Check.infer_param_type(f, i, ic))}"
      end)
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # the `gate` stream: `check_program`'s verdict — `ok` or the first return-mismatch message.
  def gate(src) do
    case Rian.Check.check_program(Rian.Decl.parse(src, assemble_only: true)) do
      :ok -> "ok"
      {:error, msg} -> msg
    end
  end

  # the `bdy` stream: infer a `;`-separated function body (binds threaded through the env).
  def infer_body(src) do
    out(Rian.Check.infer(Rian.Core.from_expr(Rian.Pratt.parse_body(src)), @fixed_env, %{}))
  end

  # the `ann` stream: `Check.annotate` over a body, dumped as its per-node types in pre-order.
  def annotate_types(src) do
    Rian.Check.annotate(Rian.Pratt.parse_body(src), @fixed_env, %{})
    |> CoreCanon.ann_types()
    |> Enum.join(",")
  end
end

defmodule ExhFixtures do
  alias Rian.{Exhaustiveness, PatternLower, Pratt}

  defp env_tree,
    do: Exhaustiveness.add_type(Exhaustiveness.base_env(), :tree, [{:leaf, 0}, {:node, 2}])

  defp env_option,
    do: Exhaustiveness.add_type(Exhaustiveness.base_env(), :option, [{:some, 1}, {:none, 0}])

  defp env_digit, do: Exhaustiveness.add_range(Exhaustiveness.base_env(), :digit, 0, 3)
  defp env_point, do: Rian.PatternLower.add_struct(Exhaustiveness.base_env(), "Point", [:x, :y])

  def scenarios do
    base = Exhaustiveness.base_env()

    [
      {"list-exhaustive", base, [{"[]", false}, {"[h | t]", false}], 1},
      {"list-missing-nil", base, [{"[h | t]", false}], 1},
      {"list-wild", base, [{"[]", false}, {"_", false}], 1},
      {"tuple-2", base, [{"{x, y}", false}], 1},
      {"tree-exhaustive", env_tree(), [{"Leaf", false}, {"Node(l, r)", false}], 1},
      {"tree-missing-node", env_tree(), [{"Leaf", false}], 1},
      {"tree-nested-witness", env_tree(), [{"Node(Leaf, Leaf)", false}, {"Leaf", false}], 1},
      {"option-exhaustive", env_option(), [{"Some(x)", false}, {"None", false}], 1},
      {"option-missing-none", env_option(), [{"Some(x)", false}], 1},
      {"lit-int-infinite", base, [{"0", false}, {"1", false}], 1},
      {"lit-int-wild", base, [{"0", false}, {"_", false}], 1},
      {"range-exhaustive", env_digit(), [{"0", false}, {"1", false}, {"2", false}, {"3", false}],
       1},
      {"range-incomplete", env_digit(), [{"0", false}, {"1", false}], 1},
      {"unreachable-after-wild", base, [{"_", false}, {"[]", false}], 1},
      {"as-passthrough", base, [{"all @ [h | t]", false}, {"[]", false}], 1},
      {"guard-excluded", base, [{"[]", true}, {"_", false}], 1},
      {"two-arg", env_tree(), [{"Leaf, Leaf", false}, {"_, _", false}], 2},
      {"struct-exhaustive", env_point(), [{"Point(x: p, y: q)", false}], 1},
      {"struct-reordered", env_point(), [{"Point(y: q, x: p)", false}], 1},
      {"atom-infinite", base, [{":ok", false}, {":err", false}], 1},
      {"atom-wild", base, [{":ok", false}, {"_", false}], 1}
    ]
  end

  defp lower_arms(env, arms) do
    Enum.map(arms, fn {src, g} ->
      PatternLower.lower_clause(%{pats: Pratt.parse_pats(src), guard: g}, env)
    end)
  end

  def plow(env, arms) do
    lower_arms(env, arms)
    |> Enum.map_join(" ; ", fn c ->
      Exhaustiveness.render(c.pat) <> " g=" <> to_string(c.guard)
    end)
  end

  def exh(env, arms, n) do
    r = Exhaustiveness.analyze(lower_arms(env, arms), n, env)
    miss = if r.missing, do: Exhaustiveness.render(r.missing), else: "-"

    "exh=" <>
      to_string(r.exhaustive?) <> " miss=" <> miss <> " unr=" <> Enum.join(r.unreachable, ",")
  end

  # the `pge` stream: build `program_env` from a source and serialize its `ctors` table.
  def program_env(src) do
    prog = Rian.Decl.parse(src, assemble_only: true)
    env = Exhaustiveness.program_env(prog.types, prog.structs, prog.ranges)
    ctors = Enum.sort_by(env.ctors, fn {tn, _} -> to_string(tn) end)
    "(env" <> Enum.map_join(ctors, "", fn {tn, sig} -> " (#{tn} #{sig_str(sig)})" end) <> ")"
  end

  defp sig_str({:finite, cs}), do: Enum.map_join(cs, ",", &ctor_str/1)
  defp sig_str(:infinite), do: "*"
  defp ctor_str(nil), do: "nil"
  defp ctor_str(:cons), do: "cons"
  defp ctor_str({:tuple, n}), do: "tup#{n}"
  defp ctor_str({:lit, v}) when is_integer(v), do: "#" <> Integer.to_string(v)
  defp ctor_str({:lit, v}) when is_binary(v), do: "#" <> v
  defp ctor_str({:lit, v}) when is_atom(v), do: "#:" <> to_string(v)
  defp ctor_str(c) when is_atom(c), do: to_string(c)
end

# Rian.Interp — the `itp` stream (ADR-0069): resolve a function body's `${…}` holes under the same
# fixed env as `inf`/`bdy`, then serialize through Core (the resolved surface must lower — no
# `str_interp` survives). Oracle = Interp.resolve → Core.from_expr → CoreCanon.expr.
defmodule InterpCanon do
  @fixed_env %{
    "x" => "Int64",
    "y" => "Int64",
    "n" => "Int53",
    "b" => "Bool",
    "s" => "String",
    "f" => "Float64",
    "c" => "Char",
    "xs" => "Vec(Int53)",
    "g" => "Fn(Int64,Bool)"
  }

  def resolve_body(src) do
    src
    |> Rian.Pratt.parse_body()
    |> Rian.Interp.resolve(@fixed_env, %{}, MapSet.new())
    |> Rian.Core.from_expr()
    |> CoreCanon.expr()
  end
end

itp_corpus = [
  # String identity, the int/bool/char/float stringifiers, a multi-hole concat, an int literal
  ~S|"hi ${s}"|,
  ~S|"${n}"|,
  ~S|"${x}"|,
  ~S|"${b}"|,
  ~S|"${c}"|,
  ~S|"${f}"|,
  ~S|"a${n}b${s}c"|,
  ~S|"${42}"|,
  # an unbound hole falls through to runtime `__prim_to_string`; an atom is a `Symbol`
  ~S|"${zzz}"|,
  ~S|"${:foo}"|,
  # a non-interpolated string passes through unchanged
  ~S|"plain"|,
  # scope-aware: a `case` arm hole sees the scrutinee-typed bindings; a block `:=` extends the env
  "case b do\n  true -> \"${n}\"\n  false -> \"${s}\"\nend",
  ~S|m := n; "v=${m}"|
]

# Rian.Beam — the `beam` stream (ADR-0084 Phase 8): EXECUTION parity. Each program is compiled to
# Erlang abstract forms, loaded, and its `main/0` run; the `~p`-rendered result is the fixture. The
# PS side (`rian_beam@ps:runMain`) does the same on purerl, so a match proves the forms are not just
# structurally similar but actually *run the same*. Inc 1: literals, the operator algebra, vars,
# `:=` binds, and local calls over single-clause var-headed functions.
beam_corpus = [
  # an integer literal
  "pub def main() Int53 := 42",
  # the operator algebra + a local call (recursion-free)
  "pub def add(x Int53, y Int53) Int53 := x + y\npub def main() Int53 := add(40, 2)",
  # mixed arithmetic with precedence + `div`/`rem`
  "pub def main() Int53 := (1 + 2) * 3 - 10 div 3 + 7 rem 4",
  # a `:=` bind then use, and unary minus
  "pub def main() Int53 := x := 10 ; y := -(x * 2) ; x - y",
  # a float result
  "pub def main() Float64 := 3.0 * 2.5",
  # a boolean (comparison + `and`)
  "pub def main() Bool := (1 < 2) and (3 >= 3)",
  # recursion (a self local call) + `if … do … else … end`
  "pub def fact(n Int53) Int53 := if n <= 1 do 1 else n * fact(n - 1) end\npub def main() Int53 := fact(5)",
  # ── inc 2: multi-clause dispatch, function-clause guards, `case` ──
  # a multi-clause function (Erlang dispatches natively over the clause heads)
  "pub def f(x Int53) Int53\npub def f(0) := 10\npub def f(n) := n * 2\npub def main() Int53 := f(0) + f(5)",
  # a function-clause `when` guard
  "pub def sign(n Int53) Int53\npub def sign(n) when n > 0 := 1\npub def sign(n) := 0\npub def main() Int53 := sign(5) * 10 + sign(-3)",
  # a `case` with a literal arm + a wildcard
  "pub def classify(n Int53) Int53 := case n do\n  0 -> 100\n  _ -> 200\nend\npub def main() Int53 := classify(0) + classify(7)",
  # a `case` arm with a `when` guard
  "pub def g(n Int53) Int53 := case n do\n  x when x > 5 -> 1\n  _ -> 0\nend\npub def main() Int53 := g(9) * 10 + g(2)",
  # ── inc 3: sums (tagged tuples), lists, strings, tuples + their patterns ──
  # a sum type → construction `Circle(r)` = `{circle, R}` + `case` ctor patterns
  "type Shape := Circle(Int53) | Square(Int53)\npub def area(s Shape) Int53 := case s do\n  Circle(r) -> r * r\n  Square(x) -> x * x\nend\npub def main() Int53 := area(Circle(3)) + area(Square(4))",
  # a list literal (the `main/0` result is a list)
  "pub def main() Vec(Int53) := [1, 2, 3]",
  # list cons + `[]`/`[h | t]` patterns (recursive sum over a list)
  "pub def sum_l(xs Vec(Int53)) Int53 := case xs do\n  [] -> 0\n  [h | t] -> h + sum_l(t)\nend\npub def main() Int53 := sum_l([10, 20, 30])",
  # a String literal → a BEAM binary
  "pub def main() String := \"hello\"",
  # a tuple value + tuple pattern
  "pub def main() Int53 := case {1, 2} do\n  {a, b} -> a + b\nend",
  # ── inc 4: structs (tagged maps), map literals + their patterns ──
  # a struct → a `__struct__`-tagged map; construction `Point(x: …)` + field access `p.x`
  "struct Point(x Int53, y Int53)\npub def main() Int53 := p := Point(x: 3, y: 4) ; p.x + p.y",
  # a struct pattern in a `case` (`Point(x: vx, y: _)`)
  "struct Point(x Int53, y Int53)\npub def gx(p Point) Int53 := case p do\n  Point(x: vx, y: _) -> vx\nend\npub def main() Int53 := gx(Point(x: 5, y: 9))",
  # a map literal + a map pattern `%{a: x}`
  "pub def main() Int53 := case %{a: 1, b: 2} do\n  %{a: x} -> x\nend",
  # ── inc 5: self-contained portable prims (stringify/concat/membership) ──
  # `${int}` interpolation → `__prim_str_concat_all` + `__prim_int_to_string` (native, no prelude)
  "pub def main() String := n := 42 ; \"n = ${n}\"",
  # string concat `<>` → a `<<L/binary, R/binary>>` binary
  "pub def main() String := \"ab\" <> \"cd\"",
  # list membership `x in xs` → `lists:member/2`
  "pub def main() Bool := 2 in [1, 2, 3]",
  # ── inc 6: 64-bit overflow ops (bignum-compute then project onto signed 64) ──
  # wrapping: i64_max + 1 → two's-complement wrap to i64_min
  "pub def main() Int64 := Prim.wrapping_add(9223372036854775807, 1)",
  # saturating: clamp into [i64_min, i64_max]
  "pub def main() Int64 := Prim.saturating_add(9223372036854775807, 100)",
  # checked: in-range → `{some, S}` (Option)
  "pub def main() Option(Int64) := Prim.checked_add(40, 2)",
  # checked: overflow → `none`
  "pub def main() Option(Int64) := Prim.checked_add(9223372036854775807, 1)"
]

# Rian.JS.compile_ts — the `jsts` stream (ADR-0086 §5): the native typed `.ts` module. Reuses
# the `js` runtime corpus (every runtime program, emitted as TypeScript). Oracle = `compile_ts`.
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
    end) ++
    Enum.map(range_corpus, fn s ->
      core = Rian.Range.expand_of(Core.from_expr(Pratt.parse(s)), range_table)
      "rng\t#{Canon.hex(s)}\t#{Canon.hex(CoreCanon.expr(core))}"
    end) ++
    Enum.flat_map(ExhFixtures.scenarios(), fn {name, env, arms, n} ->
      [
        "plw\t#{Canon.hex(name)}\t#{Canon.hex(ExhFixtures.plow(env, arms))}",
        "exh\t#{Canon.hex(name)}\t#{Canon.hex(ExhFixtures.exh(env, arms, n))}"
      ]
    end) ++
    Enum.map(proto_impl_corpus, fn s ->
      "prc\t#{Canon.hex(s)}\t#{Canon.hex(DeclCanon.proto_impl(Decl.parse(s, assemble_only: true)))}"
    end) ++
    Enum.map(pex_corpus, fn s ->
      p = Decl.parse(s, assemble_only: true)
      protocols = Map.new(Map.get(p, :protocols, []), &{&1.name, &1.methods})

      impls =
        Map.get(p, :impl_decls, [])
        |> Enum.map(&{&1.proto, &1.type, &1.methods, &1.assoc})
        |> Enum.filter(fn {proto, _, _, _} -> Map.has_key?(protocols, proto) end)

      defs =
        Rian.Protocol.expand(protocols, impls, Map.get(p, :types, []), Map.get(p, :structs, []))

      canon = Enum.map_join(defs, "\n", &DeclCanon.expand_def_s/1)
      "pex\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(efs_corpus, fn s ->
      es = Rian.Reach.effect_sets(Decl.parse(s, assemble_only: true))

      canon =
        es
        |> Enum.map(fn {k, set} -> "#{k}=>#{Enum.join(Enum.sort(MapSet.to_list(set)), ",")}" end)
        |> Enum.sort()
        |> Enum.join(";")

      "efs\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(rch_corpus, fn s ->
      rep = Rian.Reach.analyze(Decl.parse(s, assemble_only: true))

      canon =
        rep
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map_join("\n", fn {k, %{reach: r, blockers: bs}} ->
          "#{k} reach=#{Enum.join(Enum.sort(MapSet.to_list(r)), ",")} blockers=#{Enum.map_join(bs, "|", & &1.construct)}"
        end)

      "rch\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(cap_corpus, fn s ->
      [cap, t] = String.split(s, " ", parts: 2)
      "cap\t#{Canon.hex(s)}\t#{Canon.hex(Rian.Capability.rust_param(String.to_atom(cap), t))}"
    end) ++
    Enum.map(lin_corpus, fn s ->
      canon =
        Rian.Capability.count_uses(Rian.Pratt.parse(s))
        |> Enum.sort()
        |> Enum.map_join(";", fn {k, n} -> "#{k}:#{n}" end)

      "lin\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(ic_corpus, fn s ->
      "pic\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.ic_dump(s))}"
    end) ++
    Enum.map(ifc_corpus, fn s ->
      "ifc\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.infer_ic(s))}"
    end) ++
    Enum.map(irt_corpus, fn s ->
      "irt\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.infer_ret(s))}"
    end) ++
    Enum.map(flr_corpus, fn s ->
      "flr\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.fill_rets(s))}"
    end) ++
    Enum.map(ilr_corpus, fn s ->
      "ilr\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.fill_returns(s))}"
    end) ++
    Enum.map(ilp_corpus, fn s ->
      "ilp\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.fill_sig(s))}"
    end) ++
    Enum.map(ipt_corpus, fn s ->
      "ipt\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.infer_param(s))}"
    end) ++
    Enum.map(gate_corpus, fn s ->
      "gate\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.gate(s))}"
    end) ++
    Enum.map(asm_corpus, fn s ->
      "asm\t#{Canon.hex(s)}\t#{Canon.hex(DeclCanon.prog(Decl.parse(s, assemble_only: true)))}"
    end) ++
    Enum.map(opq_corpus, fn s ->
      prog = Rian.Opaque.erase(Decl.parse(s, assemble_only: true))
      funcs = Map.get(prog, :funcs, [])

      canon =
        funcs
        |> Enum.map(fn f ->
          pts = f.params |> Enum.map(fn p -> p.type end) |> Enum.join(",")

          body =
            case f.clauses do
              [c | _] when c.body != nil ->
                CoreCanon.expr(Rian.Core.from_expr(Rian.Pratt.parse_body(c.body)))

              _ ->
                "_"
            end

          "#{f.name}:#{pts}=>#{f.ret}=#{body}"
        end)
        |> Enum.join(";")

      "opq\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(js_corpus, fn s ->
      "js\t#{Canon.hex(s)}\t#{Canon.hex(Rian.JS.compile(s))}"
    end) ++
    Enum.map(jsdts_corpus, fn s ->
      "jsdts\t#{Canon.hex(s)}\t#{Canon.hex(Rian.JS.compile_types(s))}"
    end) ++
    Enum.map(js_corpus, fn s ->
      "jsts\t#{Canon.hex(s)}\t#{Canon.hex(Rian.JS.compile_ts(s))}"
    end) ++
    Enum.map(rust_corpus, fn s ->
      rust =
        Rian.Decl.compile(s)
        |> Enum.filter(fn {_n, o} -> o[:rust] end)
        |> Enum.map_join("\n\n", fn {_n, o} -> o.rust end)

      "rust\t#{Canon.hex(s)}\t#{Canon.hex(rust)}"
    end) ++
    Enum.map(jvm_corpus, fn s ->
      "jvm\t#{Canon.hex(s)}\t#{Canon.hex(Rian.JVM.compile(s))}"
    end) ++
    Enum.map(beam_corpus, fn s ->
      {:ok, mod} = Rian.Beam.load(s, :rian_main)
      out = :erlang.iolist_to_binary(:io_lib.format(~c"~p", [apply(mod, :main, [])]))
      "beam\t#{Canon.hex(s)}\t#{Canon.hex(out)}"
    end) ++
    Enum.map(rustprog_corpus, fn s ->
      "rustprog\t#{Canon.hex(s)}\t#{Canon.hex(Rian.Lower.rust_program(Rian.Decl.parse(s)))}"
    end) ++
    [
      # Rian.ShowStdlib — the `shs` stream: the parsed `Show` stdlib module (ADR-0069 §6). Input
      # ignored (the module is fixed); asserts the PS inlined source parses to the reference module.
      "shs\t#{Canon.hex("show")}\t#{Canon.hex(DeclCanon.mod_one(Rian.ShowStdlib.module()))}"
    ] ++
    Enum.map(itp_corpus, fn s ->
      "itp\t#{Canon.hex(s)}\t#{Canon.hex(InterpCanon.resolve_body(s))}"
    end) ++
    Enum.map(mxb_corpus, fn s ->
      funcs = Map.get(Decl.parse(s, assemble_only: true), :funcs, [])

      canon =
        funcs
        |> Enum.flat_map(fn f ->
          Enum.map(f.clauses, fn c ->
            CoreCanon.expr(Rian.Core.from_expr(Rian.Pratt.parse_body(c.body)))
          end)
        end)
        |> Enum.join(";")

      "mxb\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(prelude_corpus, fn s ->
      types = Rian.Prelude.with_prelude(Decl.parse(s, assemble_only: true).types)
      "prl\t#{Canon.hex(s)}\t#{Canon.hex(DeclCanon.types_s(types))}"
    end) ++
    Enum.map(prog_env_corpus, fn s ->
      "pge\t#{Canon.hex(s)}\t#{Canon.hex(ExhFixtures.program_env(s))}"
    end) ++
    Enum.map(ext_corpus, fn s ->
      prog = Decl.parse(s, assemble_only: true)

      rendered =
        prog.funcs
        |> Enum.filter(fn f -> map_size(f.externals) > 0 end)
        |> Enum.map_join("\n", fn f ->
          Enum.map_join(Enum.sort(Map.to_list(f.externals)), " ", fn {t, spec} ->
            "#{t}=#{Rian.External.render(spec, f.params)}"
          end)
        end)

      "ext\t#{Canon.hex(s)}\t#{Canon.hex(rendered)}"
    end) ++
    Enum.map(coh_corpus, fn s ->
      canon =
        Enum.map_join(Decl.coherence_violations(s), ";", fn vio ->
          "#{vio.rule}:#{vio.proto}:#{vio.type}"
        end)

      "coh\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(cohrs_corpus, fn s ->
      canon =
        Enum.map_join(Decl.coherence_violations(s, [:rs]), ";", fn vio ->
          "#{vio.rule}:#{vio.proto}:#{vio.type}"
        end)

      "cohrs\t#{Canon.hex(s)}\t#{Canon.hex(canon)}"
    end) ++
    Enum.map(check_unify_corpus, fn s ->
      "uni\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.run(:unify, s))}"
    end) ++
    Enum.map(check_join_corpus, fn s ->
      "joi\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.run(:join, s))}"
    end) ++
    Enum.map(check_infer_corpus, fn s ->
      "inf\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.infer(s))}"
    end) ++
    Enum.map(check_body_corpus, fn s ->
      "bdy\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.infer_body(s))}"
    end) ++
    Enum.map(ann_corpus, fn s ->
      "ann\t#{Canon.hex(s)}\t#{Canon.hex(CheckCanon.annotate_types(s))}"
    end) ++
    Enum.map(builtins_corpus, fn s ->
      "bui\t#{Canon.hex(s)}\t#{Canon.hex(BuiltinsCanon.run(s))}"
    end) ++
    Enum.map(shadow_corpus, fn s ->
      "shd\t#{Canon.hex(s)}\t#{Canon.hex(ShadowCanon.run(s))}"
    end) ++
    Enum.map(mac_corpus, fn s ->
      env = Rian.Macro.build_env(macro_defs)
      expanded = Rian.Macro.expand(env, Rian.Pratt.parse(s))
      "mac\t#{Canon.hex(s)}\t#{Canon.hex(CoreCanon.expr(Rian.Core.from_expr(expanded)))}"
    end)

path = Path.join([__DIR__, "fixtures", "parity.fixtures"])
File.mkdir_p!(Path.dirname(path))
File.write!(path, Enum.join(lines, "\n") <> "\n")
IO.puts("wrote #{length(lines)} fixture records to #{path}")
