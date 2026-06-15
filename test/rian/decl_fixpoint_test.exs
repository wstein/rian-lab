defmodule Rian.DeclFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl, Lexer, Pratt}
  alias Rian.IR.{Clause, Field, Func, Mod, Param, Struct, Type, Variant}

  # Stage 2 of the bootstrap ladder (ADR-0063) for **declarations**: the
  # Rian-written front-end (examples/rian/selfhost_decl.rian) parses `type` sums
  # and `def` functions into a `Decl` representation that — projected to `Rian.IR`
  # — (1) **matches what `Rian.Decl.parse` builds**, and (2) is handed to the real
  # backend (`Rian.Beam.compile_ir/2`) which **compiles and runs it**. That is the
  # Stage-2 thesis: a Rian front-end producing IR the existing backend consumes,
  # with no Elixir parse in the loop.
  #
  # Covers: `type` sums; `struct` records; `mod` nesting (incl. `pub def`); `def`
  # functions (single + multi-clause); clause patterns (var/lit/ctor/wildcard/
  # cons-list); capabilities (val/iso/ref/tag); parametric types (`Vec(T)`); list
  # construction; `.field` access + labeled construction; `when` guards; and
  # `forall` generics (`Ret forall T, U: Eq + Ord` -> Func.tvars/Func.bounds).
  # Remaining long tail of `Rian.Decl`: string/char clause patterns, `alias`/
  # `protocol`/doc-comments, and the portable stdlib breadth — see ADR-0063.

  setup_all do
    {:ok, fe} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :rian_decl_frontend)
    {:ok, frontend: fe}
  end

  # inject the reference `Rian.Lexer.tokenize/1` tokens into the front-end's `Tok` sum
  defp inject({:num, s}), do: {:t_num, s}
  defp inject({:str, s}), do: {:t_str, s}
  defp inject({:char, cp}), do: {:t_char, cp}
  defp inject({:id, s}), do: {:t_id, s}
  defp inject({:kw, s}), do: {:t_kw, s}
  defp inject({:op, o}), do: {:t_op, o}
  defp inject({:lparen}), do: :tlp
  defp inject({:rparen}), do: :trp
  defp inject({:comma}), do: :t_comma
  defp inject({:nl}), do: :tnl
  defp inject({:lbracket}), do: :tl_bracket
  defp inject({:rbracket}), do: :tr_bracket

  defp front_decls(fe, src), do: fe.parse_program(src |> Lexer.tokenize() |> Enum.map(&inject/1))

  # project the front-end's `Decl` terms onto `Rian.IR`. Pattern tuples and body
  # ASTs already lower to the surface shapes (Wild->:wild, {:ctor,..}, {:bin,..});
  # only the struct wrappers + multi-clause grouping happen here.
  defp to_type({:d_type, name, vs}) do
    %Type{
      name: name,
      variants:
        Enum.map(vs, fn {:v, c, ts} ->
          %Variant{ctor: c, fields: Enum.map(ts, &%Field{type: &1})}
        end)
    }
  end

  defp param({:par, n, cap, t}), do: %Param{name: n, type: t, cap: String.to_atom(cap)}

  defp clause(pats, body),
    do: %Clause{pats: Enum.map(pats, &cp/1), body: to_body(body), guard: nil}

  # a `:=` one-liner body is a single `{:expr, …}` block; a multi-statement block
  # body (`BlockE`) projects each statement onto Rian.Pratt's `{:bind,…}`/`{:expr,…}`,
  # matching what `Pratt.parse_body` builds from Rian.Decl's `;`-joined body string.
  defp to_body({:block_e, stmts}), do: {:block, Enum.map(stmts, &stmt/1)}
  defp to_body(body), do: {:block, [{:expr, ce(body)}]}

  defp stmt({:s_bind, n, e}), do: {:bind, n, ce(e)}
  defp stmt({:s_expr, e}), do: {:expr, ce(e)}

  # convert the front-end's nil/cons list PATTERNS to Rian.Decl's `{:list, …}` shape
  # (var/lit/ctor/wild lower directly); flatten the cons chain.
  defp cp({:ctor, c, args}), do: {:ctor, c, Enum.map(args, &cp/1)}
  defp cp({:str_p, s}), do: {:lit, s}
  defp cp({:char_p, code}), do: {:char_lit, code}
  defp cp(:nil_p), do: {:list, [], :close}

  defp cp({:cons_p, _, _} = c) do
    {elems, tail} = flat_p(c)
    {:list, Enum.map(elems, &cp/1), tail}
  end

  defp cp(leaf), do: leaf

  defp flat_p(:nil_p), do: {[], :close}
  defp flat_p({:cons_p, h, :nil_p}), do: {[h], :close}

  defp flat_p({:cons_p, h, {:cons_p, _, _} = t}) do
    {es, tl} = flat_p(t)
    {[h | es], tl}
  end

  defp flat_p({:cons_p, h, t}), do: {[h], {:tail, cp(t)}}

  # convert the front-end's nil/cons list EXPRESSIONS to `{:list_lit, …}` (recurse
  # into bin/unary/call); num/id lower directly.
  defp ce(:nil_e), do: {:list_lit, [], nil}

  defp ce({:cons_e, _, _} = c) do
    {elems, tail} = flat_e(c)
    {:list_lit, Enum.map(elems, &ce/1), tail}
  end

  defp ce({:bin, op, l, r}), do: {:bin, op, ce(l), ce(r)}
  defp ce({:unary, op, x}), do: {:unary, op, ce(x)}
  defp ce({:call, f, args}), do: {:call, ce(f), Enum.map(args, &ce/1)}
  defp ce({:dot, e, field}), do: {:dot, ce(e), field}
  defp ce({:label, name, v}), do: {:label, name, ce(v)}
  # the front-end's `If(cond, then, else)` (single-expr branches) projects onto
  # Rian.Pratt's `{:if, c, {:block, [{:expr, t}]}, {:block, [{:expr, e}]}}`.
  defp ce({:if, c, t, e}),
    do: {:if, ce(c), {:block, [{:expr, ce(t)}]}, {:block, [{:expr, ce(e)}]}}

  # the front-end's `Case(scrut, arms)` projects onto Rian.Pratt's
  # `{:case, scrut, [{pat, guard | nil, body}, …]}` — single-expr arm bodies.
  defp ce({:case, scrut, arms}), do: {:case, ce(scrut), Enum.map(arms, &carm/1)}
  defp ce(leaf), do: leaf

  defp carm({:c_arm, pat, body}), do: {cp(pat), nil, ce(body)}
  defp carm({:c_arm_g, pat, g, body}), do: {cp(pat), ce(g), ce(body)}

  defp flat_e(:nil_e), do: {[], nil}
  defp flat_e({:cons_e, h, :nil_e}), do: {[h], nil}

  defp flat_e({:cons_e, h, {:cons_e, _, _} = t}) do
    {es, tl} = flat_e(t)
    {[h | es], tl}
  end

  defp flat_e({:cons_e, h, t}), do: {[h], {:tail, ce(t)}}

  # the front-end carries `forall` binders as `{:tv, name, bounds}` (ADR-0042);
  # project them onto Func.tvars (order-preserved) + Func.bounds (constrained only),
  # mirroring Rian.Decl.split_forall.
  defp func(name, params, ret, clauses, pub, tvs) do
    %Func{
      name: name,
      params: Enum.map(params, &param/1),
      ret: ret,
      clauses: clauses,
      pub?: pub,
      tvars: Enum.map(tvs, fn {:tv, n, _} -> n end),
      bounds: for({:tv, n, bs} <- tvs, bs != [], into: %{}, do: {n, bs}),
      doc: nil,
      synthetic: false,
      test?: false,
      dispatch: nil
    }
  end

  defp to_struct({:d_struct, name, params}),
    do: %Struct{
      name: name,
      fields: Enum.map(params, fn {:par, n, _, t} -> %Field{label: n, type: t} end)
    }

  defp to_mod({:d_mod, name, decls}) do
    ir = group(decls)

    %Mod{
      name: name,
      types: Enum.filter(ir, &match?(%Type{}, &1)),
      structs: Enum.filter(ir, &match?(%Struct{}, &1)),
      funcs: Enum.filter(ir, &match?(%Func{}, &1)),
      uses: [],
      ranges: [],
      consts: [],
      doc: nil,
      targets: nil
    }
  end

  # group a flat decl list into IR: a `d_sig` absorbs the following `d_clause`s of
  # the same name (multi-clause); a `d_func` is a single typed clause.
  defp group([]), do: []
  defp group([{:d_type, _, _} = t | rest]), do: [to_type(t) | group(rest)]
  defp group([{:d_struct, _, _} = s | rest]), do: [to_struct(s) | group(rest)]
  defp group([{:d_mod, _, _} = m | rest]), do: [to_mod(m) | group(rest)]

  defp group([{:d_func, pub, name, params, ret, tvs, body} | rest]) do
    pats = Enum.map(params, fn {:par, n, _, _} -> {:var, n} end)
    [func(name, params, ret, [clause(pats, body)], pub, tvs) | group(rest)]
  end

  defp group([{:d_sig, pub, name, params, ret, tvs} | rest]) do
    {cls, rest2} =
      Enum.split_while(rest, fn d ->
        match?({:d_clause, ^name, _, _}, d) or match?({:d_clause_g, ^name, _, _, _}, d)
      end)

    [func(name, params, ret, Enum.map(cls, &to_clause/1), pub, tvs) | group(rest2)]
  end

  defp to_clause({:d_clause, _, pats, body}), do: clause(pats, body)

  defp to_clause({:d_clause_g, _, pats, guard, body}),
    do: %Clause{
      pats: Enum.map(pats, &cp/1),
      body: {:block, [{:expr, ce(body)}]},
      guard: ce(guard)
    }

  defp to_prog(decls) do
    ir = group(decls)

    %{
      types: Enum.filter(ir, &match?(%Type{}, &1)),
      funcs: Enum.filter(ir, &match?(%Func{}, &1)),
      structs: Enum.filter(ir, &match?(%Struct{}, &1)),
      mods: Enum.filter(ir, &match?(%Mod{}, &1)),
      ranges: []
    }
  end

  # clause bodies/guards differ in form (Decl.parse keeps source strings; the
  # front-end parsed ASTs) — normalize both through `Pratt.parse_body`/`parse` to
  # compare (`Pratt.parse/1` is idempotent on an AST).
  defp norm_func(f) do
    %{
      f
      | clauses:
          Enum.map(f.clauses, fn c ->
            %{c | body: Pratt.parse_body(c.body), guard: c.guard && Pratt.parse(c.guard)}
          end)
    }
  end

  @corpus [
    "type Color := Red | RGB(Int64, Int64)",
    "def sq(n Int64) Int64 := n * n",
    "def add(a Int64, b Int64) Int64 := a + b",
    "type Expr := Num(Int64) | Add(Expr, Expr) | Zero",
    "def poly(a Int64, b Int64, c Int64) Int64 := a * b + c - a",
    "type Color := Red | Green\ndef pick(n Int64) Int64 := n * 2 + 1",
    # capabilities (val/iso/ref)
    "def consume(x iso Int64, y ref Int64) Int64 := x + y",
    # multi-clause with clause patterns (ctor / nested literal / var / wildcard)
    "type E := Num(Int64) | Add(E, E)\n" <>
      "def fold(e E) E\n" <>
      "def fold(Num(n)) := Num(n)\n" <>
      "def fold(Add(Num(0), b)) := b\n" <>
      "def fold(Add(a, b)) := Add(a, b)\n" <>
      "def fold(_) := Num(0)",
    # multi-clause over integers (literal + var clauses)
    "def classify(n Int64) Int64\n" <>
      "def classify(0) := 100\n" <>
      "def classify(n) := n * 2",
    # parametric types + cons/list patterns + list construction (cons recursion)
    "def rev(xs val Vec(Int64), acc val Vec(Int64)) Vec(Int64)\n" <>
      "def rev([], acc) := acc\n" <>
      "def rev([x | xs], acc) := rev(xs, [x | acc])",
    "def len(xs val Vec(Int64)) Int64\n" <>
      "def len([]) := 0\n" <>
      "def len([_ | t]) := 1 + len(t)",
    # `if … do … else … end` expressions (single-expr branches) — ADR-0063 widening
    "def max(a Int64, b Int64) Int64 := if a > b do a else b end",
    "def clampv(x Int64) Int64 := if x > 10 do 10 else x end",
    # `if` in a multi-clause body, with a nested arithmetic condition + recursion
    "def sign(n Int64) Int64\n" <>
      "def sign(0) := 0\n" <>
      "def sign(n) := if n > 0 do 1 else 0 end",
    # `if` whose branches are themselves compound expressions (calls / arithmetic)
    "def pickf(a Int64, b Int64) Int64 := if a == b do a + b else a - b end",
    # `when` guards
    "def clamp(n Int64) Int64\n" <>
      "def clamp(n) when n < 0 := 0\n" <>
      "def clamp(n) := n",
    # struct declarations + field access + labeled construction
    "struct Point(x Int64, y Int64)",
    "struct Point(x Int64, y Int64)\n" <>
      "def mag(p Point) Int64 := p.x * p.x + p.y * p.y\n" <>
      "def origin() Point := Point(x: 0, y: 0)",
    # mod with a pub def
    "mod Calc do\n  pub def double(n Int64) Int64 := n * 2\nend",
    "mod M do\n  type T := A | B\n  pub def f(n Int64) Int64 := n + 1\nend",
    # generics — `forall` binders (ADR-0042): unconstrained, bounded, multi-tvar
    "def id(x val T) T forall T := x",
    "def cmp(a val T, b val T) Bool forall T: Eq := a == b",
    "def srt(xs val Vec(T)) Vec(T) forall T: Ord + Eq\ndef srt(xs) := xs",
    "def pair(a val A, b val B) A forall A, B := a",
    "def head(xs val Vec(T)) T forall T\ndef head([h | _]) := h",
    # String / Char literals — in expression and pattern position (toward the lexer)
    "def tag() String := \"ok\"",
    "def greet(name String) String := name",
    "def isz(c Char) Bool := c == '0'",
    "def cls(c Char) Int64\ndef cls('+') := 1\ndef cls(_) := 0",
    "def m(s String) Int64\ndef m(\"x\") := 1\ndef m(_) := 0",
    # multi-statement block bodies (`<nl> binds <nl> expr <nl> end`) — ADR-0063 widening
    "def double_inc(n Int64) Int64\n  d := n * 2\n  d + 1\nend",
    "def two_binds(a Int64, b Int64) Int64\n  x := a + b\n  y := x * 2\n  y - 1\nend",
    # a block body next to a bodiless multi-clause head (the disambiguation case)
    "def f(n Int64) Int64\n  k := n + 1\n  k\nend\ndef g(n Int64) Int64 := n",
    # a block body holding an `if` statement (nested do/end is balanced by take_block)
    "def grade(n Int64) Int64\n  base := n * 10\n  if base > 50 do base else 0 end\nend",
    # a block body inside a `mod`
    "mod Calc do\n  pub def inc2(n Int64) Int64\n    t := n + 1\n    t + 1\n  end\nend",
    # `case` expressions — literal/var/wildcard arms, with and without a `when` guard
    "def classify(n Int64) Int64 := case n do\n  0 -> 100\n  _ -> n * 2\nend",
    "def sgn(n Int64) Int64 := case n do\n  0 -> 0\n  m when m > 0 -> 1\n  _ -> -1\nend",
    "def ctor(s Sign) Int64 := case s do\n  Pos -> 1\n  Neg -> -1\nend",
    # UNTYPED clause + block body (`def f(p) <nl> stmts end`) — the dominant
    # selfhost_decl idiom (a bodiless DSig followed by block-bodied clauses), which
    # the parser previously rejected (DErr). Bind+expr blocks and a case block.
    "def inc(n Int64) Int64\ndef inc(n)\n  d := n + 1\n  d\nend",
    "def cls(n Int64) Int64\ndef cls(n)\n  case n do\n    0 -> 100\n    _ -> n\n  end\nend",
    "def hd(xs Vec(Int64), d Int64) Int64\ndef hd([], d)\n  d\nend\ndef hd([h | _], d)\n  h\nend",
    # `case` arm body on the NEXT line (`PAT -> <nl> body`) — the selfhost_decl idiom
    "def nl_arm(n Int64) Int64\ndef nl_arm(n)\n  case n do\n    0 ->\n      n + 1\n    m -> m\n  end\nend",
    # a NESTED `case` in an arm body (case-inside-case, as selfhost_decl's parsers do)
    "def nz(n Int64) Int64\ndef nz(n)\n  case n do\n    0 ->\n      case n do\n        0 -> 10\n        k -> k\n      end\n    m -> m\n  end\nend"
  ]

  defp norm_mod(m), do: %{m | funcs: Enum.map(m.funcs, &norm_func/1)}

  describe "Stage 2 declarations — the Rian front-end builds the same IR as Rian.Decl.parse" do
    test "type sums and def functions project to IR equal to Rian.Decl.parse", %{frontend: fe} do
      for src <- @corpus do
        prog = front_decls(fe, src) |> to_prog()
        ref = Decl.parse(src)

        assert prog.types == ref.types, "types diverged from Rian.Decl.parse on #{inspect(src)}"
        assert prog.structs == ref.structs, "structs diverged on #{inspect(src)}"

        assert Enum.map(prog.funcs, &norm_func/1) == Enum.map(ref.funcs, &norm_func/1),
               "funcs diverged from Rian.Decl.parse on #{inspect(src)}"

        assert Enum.map(prog.mods, &norm_mod/1) == Enum.map(ref.mods, &norm_mod/1),
               "mods diverged from Rian.Decl.parse on #{inspect(src)}"
      end
    end
  end

  describe "Stage 2 handoff — the Rian-front-end IR compiles and runs on the real backend" do
    test "a multi-function program built by the Rian front-end runs via Beam.compile_ir", %{
      frontend: fe
    } do
      src = """
      def sq(n Int64) Int64 := n * n
      def add(a Int64, b Int64) Int64 := a + b
      def main(x Int64) Int64 := add(sq(x), x)
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Run)

      assert mod.sq(5) == 25
      assert mod.add(2, 3) == 5
      # main calls the other two (local calls resolve in the one compiled module)
      assert mod.main(4) == 20
    end

    test "a program with a sum type declaration compiles through the backend", %{frontend: fe} do
      src = """
      type Sign := Pos | Neg
      def twice(n Int64) Int64 := n + n
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Sum)
      assert mod.twice(21) == 42
    end

    test "a MULTI-CLAUSE pattern-matching function (the dominant Rian form) runs", %{frontend: fe} do
      # parsed entirely by the Rian front-end: ctor patterns, nested literal, wildcard
      src = """
      type E := Num(Int64) | Add(E, E)
      def simp(e E) E
      def simp(Add(Num(0), b)) := b
      def simp(Add(a, b)) := Add(a, b)
      def simp(e) := e
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Simp)

      # sum values lower to tagged tuples: Num(n) -> {:num, n}, Add(l,r) -> {:add, l, r}
      assert mod.simp({:add, {:num, 0}, {:num, 9}}) == {:num, 9}
      assert mod.simp({:add, {:num, 1}, {:num, 2}}) == {:add, {:num, 1}, {:num, 2}}
      assert mod.simp({:num, 5}) == {:num, 5}
    end

    test "a multi-clause function over integer literals runs", %{frontend: fe} do
      src = """
      def classify(n Int64) Int64
      def classify(0) := 100
      def classify(n) := n * 2
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Classify)
      assert mod.classify(0) == 100
      assert mod.classify(7) == 14
    end

    test "a CONS-RECURSIVE function (list patterns + construction) runs", %{frontend: fe} do
      # the lexer/parser idiom: `[]` / `[h | t]` patterns and `[x | acc]` construction
      src = """
      def rev(xs val Vec(Int64), acc val Vec(Int64)) Vec(Int64)
      def rev([], acc) := acc
      def rev([x | xs], acc) := rev(xs, [x | acc])
      def reverse(xs val Vec(Int64)) Vec(Int64) := rev(xs, [])
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Rev)
      assert mod.reverse([1, 2, 3]) == [3, 2, 1]
      assert mod.rev([1, 2], [9]) == [2, 1, 9]
    end

    test "a GUARDED multi-clause function runs", %{frontend: fe} do
      src = """
      def clamp(n Int64) Int64
      def clamp(n) when n < 0 := 0
      def clamp(n) := n
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Clamp)
      assert mod.clamp(-5) == 0
      assert mod.clamp(7) == 7
    end

    test "a STRUCT program (construction + field access) runs", %{frontend: fe} do
      src = """
      struct Point(x Int64, y Int64)
      def mag(p Point) Int64 := p.x * p.x + p.y * p.y
      def origin() Point := Point(x: 0, y: 0)
      def shift(p Point) Int64 := mag(p) + p.x
      """

      prog = front_decls(fe, src) |> to_prog()
      {:ok, mod} = Beam.load_ir(prog, :RianStage2Struct)
      # a struct value is a tagged map; construct one and read it back
      pt = mod.origin()
      assert mod.mag(%{__struct__: :point, x: 3, y: 4}) == 25
      assert mod.shift(%{__struct__: :point, x: 3, y: 4}) == 28
      assert pt.x == 0 and pt.y == 0
    end

    test "a MOD declaration compiles to its own BEAM module and runs", %{frontend: fe} do
      src = """
      mod Calc do
        pub def double(n Int64) Int64 := n * 2
        pub def quad(n Int64) Int64 := double(double(n))
      end
      """

      prog = front_decls(fe, src) |> to_prog()
      [mod] = Beam.load_program_ir(prog)
      assert mod == Calc
      assert Calc.double(21) == 42
      # quad calls double — a local call within the compiled mod
      assert Calc.quad(5) == 20
    end

    test "a GENERIC function (forall binders, tvars erased on the BEAM) runs", %{frontend: fe} do
      # the front-end parses `forall T` / `forall T: Eq`; on the BEAM generics are
      # erased, so a polymorphic identity + list-head compile and run unchanged.
      src = """
      def id(x val T) T forall T := x
      def head(xs val Vec(T)) T forall T
      def head([h | _]) := h
      """

      prog = front_decls(fe, src) |> to_prog()
      # the binders survived into the IR (not silently dropped)
      assert Enum.find(prog.funcs, &(&1.name == "id")).tvars == ["T"]
      assert Enum.find(prog.funcs, &(&1.name == "head")).tvars == ["T"]

      {:ok, mod} = Beam.load_ir(prog, :RianStage2Generic)
      assert mod.id(42) == 42
      assert mod.id({:a, :b}) == {:a, :b}
      assert mod.head([7, 8, 9]) == 7
    end
  end
end
