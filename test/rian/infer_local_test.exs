defmodule Rian.InferLocalTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Infer-local / declare-public (ADR-0034) — Phase 1: a private function's RETURN
  type is inferred from its body, so `defp`-style helpers needn't declare one. We
  simulate an untyped private function by parsing a typed one and nulling its `ret`,
  then assert `InferLocal.fill_returns/1` recovers it (and never fills a `pub`).
  """

  alias Rian.{Decl, InferLocal}

  defp all_funcs(prog), do: prog.funcs ++ Enum.flat_map(prog.mods, & &1.funcs)

  defp map_funcs(prog, f) do
    %{
      prog
      | funcs: Enum.map(prog.funcs, f),
        mods: Enum.map(prog.mods, fn m -> %{m | funcs: Enum.map(m.funcs, f)} end)
    }
  end

  defp null_ret(prog, name),
    do: map_funcs(prog, fn fu -> if fu.name == name, do: %{fu | ret: nil}, else: fu end)

  defp ret_of(prog, name), do: all_funcs(prog) |> Enum.find(&(&1.name == name)) |> Map.get(:ret)

  # parse, null the named returns (simulating undeclared), then infer-local.
  defp infer(src, names) do
    prog = Enum.reduce(names, Decl.parse(src), &null_ret(&2, &1))
    InferLocal.fill_returns(prog)
  end

  test "infers a private function's return from an arithmetic body" do
    out = infer("mod M do\n  def helper(x Int53) Int53 := x + 1\nend", ["helper"])
    assert ret_of(out, "helper") == "Int53"
  end

  test "infers String and Bool returns" do
    src = "mod M do\n  def g(s String) String := s <> \"!\"\n  def p(b Bool) Bool := not b\nend"
    out = infer(src, ["g", "p"])
    assert ret_of(out, "g") == "String"
    assert ret_of(out, "p") == "Bool"
  end

  test "infers across a private→private call chain (the fixpoint)" do
    src = "mod M do\n  def b(x Int53) Int53 := x + 1\n  def a(x Int53) Int53 := b(x)\nend"
    out = infer(src, ["a", "b"])
    assert ret_of(out, "b") == "Int53"
    assert ret_of(out, "a") == "Int53"
  end

  test "a `pub` function's return is NEVER filled (the declared boundary)" do
    prog = Decl.parse("mod M do\n  pub def f(x Int53) Int53 := x + 1\nend") |> null_ret("f")
    out = InferLocal.fill_returns(prog)
    assert ret_of(out, "f") == nil
  end

  test "an un-inferable return (self-recursion) raises 'annotate it', not a guess" do
    assert_raise Rian.Decl.Error, ~r/cannot infer the return type of private `loop`/, fn ->
      infer("mod M do\n  def loop(n Int53) Int53 := loop(n)\nend", ["loop"])
    end
  end

  test "an already-declared private return is left exactly as written" do
    # not nulled — fill_returns must be a no-op on declared functions
    prog = Decl.parse("mod M do\n  def k(x Int53) Int8 := 3\nend")
    out = InferLocal.fill_returns(prog)
    assert ret_of(out, "k") == "Int8"
  end
end
