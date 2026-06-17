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

  describe "private PARAMETER inference (ADR-0034 Phase 2, bidirectional)" do
    # `Decl.parse` runs the InferLocal pass, so a parsed lowercase lone param is
    # already resolved. `param_of/3` reads the resolved `{name, type}`.
    defp param_of(src, name, i),
      do:
        src
        |> Decl.parse()
        |> all_funcs()
        |> Enum.find(&(&1.name == name))
        |> Map.get(:params)
        |> Enum.at(i)

    defp tvars_of(src, name),
      do: src |> Decl.parse() |> all_funcs() |> Enum.find(&(&1.name == name)) |> Map.get(:tvars)

    test "an arithmetic body pins a lone param to Int53" do
      assert %{name: "x", type: "Int53"} = param_of("def inc(x) := x + 1", "inc", 0)
    end

    test "a string-concat body pins a lone param to String" do
      assert %{name: "s", type: "String"} = param_of(~s|def cat(s) := s <> "!"|, "cat", 0)
    end

    test "a pure pass-through param auto-generalizes to a fresh `forall T`" do
      assert %{name: "x", type: "T"} = param_of("def id(x) := x", "id", 0)
      assert tvars_of("def id(x) := x", "id") == ["T"]
    end

    test "a clause-head literal pattern pins the param (multi-clause)" do
      src = "def f(n)\n  case n do\n    0 -> 0\n    k -> k + 1\n  end\nend"
      assert %{type: "Int53"} = param_of(src, "f", 0)
    end

    test "a typed callee pushes its expected param type inward (bidirectional)" do
      src = "mod M do\n  pub def twice(y Int53) Int53 := y + y\n  def w(x) := twice(x)\nend"
      assert %{name: "x", type: "Int53"} = param_of(src, "w", 0)
    end

    test "a `pub` lone lowercase param keeps the permissive anonymous reading (no infer, no raise)" do
      # the self-hosted dispatchers rely on this: `pub def lower_pat(p) Pat` etc.
      f = "pub def disp(p) Int53 := 0" |> Decl.parse() |> Map.get(:funcs) |> hd()
      assert [%{type: "p"}] = f.params
    end

    test "a provable parameter-type conflict raises 'annotate it'" do
      # `x` is matched as an Int literal in one clause and a String literal in another
      src = "def bad(x)\n  case x do\n    0 -> 1\n    \"a\" -> 2\n  end\nend"

      assert_raise Rian.Decl.Error, ~r/parameter `x` of private `bad`.*conflicting/, fn ->
        Decl.parse(src)
      end
    end

    test "a param used only inside a `with` infers from the callee, not `forall T`" do
      # `x` appears solely in `g(x)` *inside* the `with` clause — `var_constraint`
      # must recurse into the `with` node to recover `g`'s parameter type (else it
      # would auto-generalize `x` to a wrong `forall T`).
      src =
        "mod M do\n  pub def g(n Int64) Int64 := n\n  def f(x) Int64 := with y <- g(x) do y end\nend"

      assert %{name: "x", type: "Int64"} = param_of(src, "f", 0)
      assert tvars_of(src, "f") == []
    end
  end
end
