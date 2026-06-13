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

  # project the front-end's `Decl` terms onto `Rian.IR` (the body stays a parsed
  # AST — `Rian.Beam` consumes it via `Pratt.parse_body/1`'s passthrough).
  defp to_type({:d_type, name, vs}) do
    %Type{
      name: name,
      variants:
        Enum.map(vs, fn {:v, c, ts} ->
          %Variant{ctor: c, fields: Enum.map(ts, &%Field{type: &1})}
        end)
    }
  end

  defp to_func({:d_func, name, params, ret, body}) do
    %Func{
      name: name,
      params: Enum.map(params, fn {:par, n, t} -> %Param{name: n, type: t, cap: :val} end),
      ret: ret,
      clauses: [
        %Clause{
          pats: Enum.map(params, fn {:par, n, _} -> {:var, n} end),
          body: {:block, [{:expr, body}]},
          guard: nil
        }
      ],
      pub?: false,
      tvars: [],
      bounds: %{},
      doc: nil,
      synthetic: false,
      test?: false,
      dispatch: nil
    }
  end

  defp to_prog(decls) do
    %{
      types: for(d <- decls, match?({:d_type, _, _}, d), do: to_type(d)),
      funcs: for(d <- decls, match?({:d_func, _, _, _, _}, d), do: to_func(d)),
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
    "type Color := Red | Green\ndef pick(n Int64) Int64 := n * 2 + 1"
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
  end
end
