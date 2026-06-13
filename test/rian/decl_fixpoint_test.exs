defmodule Rian.DeclFixpointTest do
  # async: false — loads real modules into the VM via :code.load_binary.
  use ExUnit.Case, async: false

  alias Rian.{Beam, Decl, Lexer, Pratt}
  alias Rian.IR.{Clause, Field, Func, Param, Type, Variant}

  # Stage 2 of the bootstrap ladder (ADR-0063) for **declarations**: the
  # Rian-written front-end (examples/rian/selfhost_decl.rian) parses `type` sums
  # and `def` functions into a `Decl` representation that — projected to `Rian.IR`
  # — (1) **matches what `Rian.Decl.parse` builds**, and (2) is handed to the real
  # backend (`Rian.Beam.compile_ir/2`) which **compiles and runs it**. That is the
  # Stage-2 thesis: a Rian front-end producing IR the existing backend consumes,
  # with no Elixir parse in the loop.
  #
  # Core forms only (type sums + single-clause `def` over simple types); the long
  # tail of `Rian.Decl` (multi-clause, capabilities, parametric types, mod/struct/
  # protocol/generics) remains — see ADR-0063.

  setup_all do
    {:ok, fe} = Beam.load(File.read!("examples/rian/selfhost_decl.rian"), :rian_decl_frontend)
    {:ok, frontend: fe}
  end

  # inject the reference `Rian.Lexer.tokenize/1` tokens into the front-end's `Tok` sum
  defp inject({:num, s}), do: {:t_num, s}
  defp inject({:id, s}), do: {:t_id, s}
  defp inject({:kw, s}), do: {:t_kw, s}
  defp inject({:op, o}), do: {:t_op, o}
  defp inject({:lparen}), do: :tlp
  defp inject({:rparen}), do: :trp
  defp inject({:comma}), do: :t_comma
  defp inject({:nl}), do: :tnl

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
  defp clause(pats, body), do: %Clause{pats: pats, body: {:block, [{:expr, body}]}, guard: nil}

  defp func(name, params, ret, clauses) do
    %Func{
      name: name,
      params: Enum.map(params, &param/1),
      ret: ret,
      clauses: clauses,
      pub?: false,
      tvars: [],
      bounds: %{},
      doc: nil,
      synthetic: false,
      test?: false,
      dispatch: nil
    }
  end

  # group a flat decl list into IR: a `d_sig` absorbs the following `d_clause`s of
  # the same name (multi-clause); a `d_func` is a single typed clause.
  defp group([]), do: []
  defp group([{:d_type, _, _} = t | rest]), do: [to_type(t) | group(rest)]

  defp group([{:d_func, name, params, ret, body} | rest]) do
    pats = Enum.map(params, fn {:par, n, _, _} -> {:var, n} end)
    [func(name, params, ret, [clause(pats, body)]) | group(rest)]
  end

  defp group([{:d_sig, name, params, ret} | rest]) do
    {cls, rest2} = Enum.split_while(rest, &match?({:d_clause, ^name, _, _}, &1))
    clauses = Enum.map(cls, fn {:d_clause, _, pats, body} -> clause(pats, body) end)
    [func(name, params, ret, clauses) | group(rest2)]
  end

  defp to_prog(decls) do
    ir = group(decls)

    %{
      types: Enum.filter(ir, &match?(%Type{}, &1)),
      funcs: Enum.filter(ir, &match?(%Func{}, &1)),
      structs: [],
      ranges: [],
      mods: []
    }
  end

  # clause bodies differ in form (Decl.parse keeps a source string; the front-end a
  # parsed AST) — normalize both through `Pratt.parse_body/1` to compare.
  defp norm_func(f),
    do: %{f | clauses: Enum.map(f.clauses, &%{&1 | body: Pratt.parse_body(&1.body)})}

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
      "def classify(n) := n * 2"
  ]

  describe "Stage 2 declarations — the Rian front-end builds the same IR as Rian.Decl.parse" do
    test "type sums and def functions project to IR equal to Rian.Decl.parse", %{frontend: fe} do
      for src <- @corpus do
        prog = front_decls(fe, src) |> to_prog()
        ref = Decl.parse(src)

        assert prog.types == ref.types, "types diverged from Rian.Decl.parse on #{inspect(src)}"

        assert Enum.map(prog.funcs, &norm_func/1) == Enum.map(ref.funcs, &norm_func/1),
               "funcs diverged from Rian.Decl.parse on #{inspect(src)}"
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
  end
end
